# ALEX STANDARD LIBRARY — netgame
#
# Réseau pour les jeux multijoueurs, au-dessus d'UDP :
#   - connexion avec poignée de main (défi anti-usurpation, paquets de demande remplis contre l'amplification),
#     délai d'expiration, déconnexion propre ;
#   - messages FIABLES ORDONNÉS (renvoyés jusqu'à accusé) et NON FIABLES dans le même flux de paquets ;
#     accusés de réception groupés (numéro + 32 bits), RTT lissé, taux de perte ; fragmentation au-delà d'environ
#     1 Kio (fiable : reconstitution ordonnée ; non fiable : abandon si un morceau manque) ;
#   - transports : UDP réel (UdpTransport), boucle locale en mémoire (LoopbackHub, tests et jeu solo) et simulateur
#     de liaison (LinkSim : latence, gigue, pertes, doublons ; graine fixe -> reproductible).
# Au-dessus : netgame.snapshot (instantanés delta + interpolation), netgame.prediction (prédiction côté client,
# réconciliation, tampon d'entrées serveur), netgame.rollback (simulation à retour arrière, style GGPO).
#
#   use netgame
#   srv := netgame.Server(netgame.UdpTransport("0.0.0.0", 27015), 8)
#   cli := netgame.Client(netgame.UdpTransport())
#   cli.connect("127.0.0.1", 27015)
#   # boucle de jeu (les deux côtés) :
#   for e in srv.update():                     # {"type": "connect" | "disconnect" | "message", "client", "data"}
#       if e["type"] == "message":
#           srv.send(e["client"], {"echo": e["data"]}, true)
#   srv.flush()                                # envoie les paquets (une fois par pas réseau)
#   for e in cli.update(): ...
#   cli.send({"t": "chat", "texte": "salut"}, true)
#   cli.flush()
#
# Messages : valeurs netgame.codec (null, bool, int, float, str, list, dict) ; send_raw / "raw" pour des octets.
# Horloge : Clock (temps réel) ou ManualClock (tests, simulations déterministes), partagée avec LinkSim.
# Erreurs : ValueError (paquet invalide, message trop gros), NetworkError (socket).

from core use len, type, to_int
from collections use append, keys, remove, contains_key
use math
use time as _time
use _native_net as _nn
use network.udp as _udp
use network.dns as _dns
use netgame.codec as nc

const MTU := 1200                # taille maximale d'un paquet (octets)
const FRAGMENT := 1024           # taille d'un morceau de message fragmenté
const PROTOCOL := 0x4E41         # identifiant de protocole par défaut (2 octets en tête de chaque paquet)

const _DATA := 0
const _REQUEST := 1
const _CHALLENGE := 2
const _RESPONSE := 3
const _ACCEPT := 4
const _DENY := 5
const _DISCONNECT := 6

# ---------------------------------------------------------------------------------------------------------------------
# Horloges et hasard reproductible
# ---------------------------------------------------------------------------------------------------------------------

class Clock:
    func now():
        return _time.monotonic()

class ManualClock:
    func init(t=0.0):
        self.t = t * 1.0

    func now():
        return self.t

    func advance(dt):
        self.t += dt

# Générateur congruentiel (reproductible, indépendant du module random).
class Rng:
    func init(seed=1):
        self.s = (seed * 2654435761 + 1) & 4294967295

    func next():
        self.s = (self.s * 1664525 + 1013904223) & 4294967295
        return self.s / 4294967296.0

    func u32():
        self.next()
        return self.s

_salt_rng := [null]

func _salt():
    if _salt_rng[0] == null:
        _salt_rng[0] = Rng(to_int(_time.time() * 1000.0) & 4294967295)
    return _salt_rng[0].u32()

func addr_key(addr):
    return str(addr[0]) + ":" + str(addr[1])

# ---------------------------------------------------------------------------------------------------------------------
# Transports : send(adresse [hôte, port], octets) ; poll() -> [[octets, adresse]...]
# ---------------------------------------------------------------------------------------------------------------------

class UdpTransport:
    func init(host="0.0.0.0", port=0):
        self.endpoint = _udp.bind(host, port)
        self.sock = self.endpoint.socket

    func send(addr, data):
        try:
            self.sock.send_to(nc.to_str(data), addr[0], addr[1])
        catch e:
            # hôte injoignable, tampon plein : comme une perte de paquet
            return

    func poll():
        out := []
        h := self.sock.handle
        while true:
            r := _nn.recvfrom(h, 2048, 0)
            if type(r) == "int":
                break
            append(out, [_nn.to_bytes(r[0]), [r[1], r[2]]])
        return out

    func port():
        return self.endpoint.port()

    func close():
        self.endpoint.close()

# Réseau en mémoire : endpoint(nom) donne un transport d'adresse [nom, 0].
class LoopbackHub:
    func init():
        self.queues = {}

    func endpoint(name):
        self.queues[name] = []
        return LoopbackTransport(self, name)

class LoopbackTransport:
    func init(hub, name):
        self.hub = hub
        self.name = name

    func send(addr, data):
        if addr[0] in self.hub.queues:
            append(self.hub.queues[addr[0]], [nc.to_bytes(data), [self.name, 0]])

    func poll():
        q := self.hub.queues[self.name]
        self.hub.queues[self.name] = []
        return q

    func port():
        return 0

    func close():
        return

# Simulateur de liaison (sortant) : latence + gigue (réordonnancement possible), pertes, doublons.
class LinkSim:
    func init(inner, latency=0.05, jitter=0.0, loss=0.0, duplicate=0.0, seed=1, clock=null):
        self.inner = inner
        self.latency = latency
        self.jitter = jitter
        self.loss = loss
        self.duplicate = duplicate
        self.rng = Rng(seed)
        self.clock = clock if clock != null else Clock()
        self.queue = []
        self.dropped = 0
        self.sent = 0

    func _schedule(addr, data):
        t := self.clock.now() + self.latency + self.rng.next() * self.jitter
        append(self.queue, [t, addr, data])

    func send(addr, data):
        self.sent += 1
        if self.rng.next() < self.loss:
            self.dropped += 1
            return
        self._schedule(addr, data)
        if self.duplicate > 0.0 and self.rng.next() < self.duplicate:
            self._schedule(addr, data)

    func pump():
        now := self.clock.now()
        keep := []
        due := []
        for q in self.queue:
            if q[0] <= now:
                append(due, q)
            else:
                append(keep, q)
        self.queue = keep
        # ordre d'arrivée (la gigue peut réordonner)
        n := len(due)
        i := 1
        while i < n:
            j := i
            while j > 0 and due[j - 1][0] > due[j][0]:
                tmp := due[j]
                due[j] = due[j - 1]
                due[j - 1] = tmp
                j -= 1
            i += 1
        for q in due:
            self.inner.send(q[1], q[2])

    func poll():
        self.pump()
        return self.inner.poll()

    func port():
        return self.inner.port()

    func close():
        self.inner.close()

# ---------------------------------------------------------------------------------------------------------------------
# Connexion : fiabilité, ordre, accusés, fragmentation (une par pair)
# ---------------------------------------------------------------------------------------------------------------------

func _newer(a, b):
    return ((a > b) and (a - b <= 32768)) or ((a < b) and (b - a > 32768))

class Connection:
    func init(send_fn, now, protocol=PROTOCOL, key=0):
        self.send_fn = send_fn
        self.protocol = protocol
        self.key = key               # clé de la connexion (poignée de main) : paquets usurpés ignorés
        self.seq = 0
        self.remote_seq = -1
        self.recv_mask = 0
        self.sent = {}               # seq -> [instant, [ids fiables], acquitté]
        self.rel_out = {}            # id -> [type, dernier morceau, octets, dernier envoi]
        self.rel_order = []
        self.rel_next = 0
        self.rel_in_next = 0
        self.rel_in = {}
        self.rel_partial = []
        self.unrel = []
        self.frag_group = 0
        self.frag_in = {}
        self.rtt = 0.1
        self.rtt_var = 0.05
        self.has_rtt = false
        self.last_recv = now
        self.last_send = -1000.0
        self.need_ack = false
        self.loss = 0.0
        self.stats = {"packets_sent": 0, "packets_received": 0, "bytes_sent": 0, "bytes_received": 0,
                      "resent": 0, "lost": 0, "acked": 0}

    # File un message (octets) ; reliable : renvoyé jusqu'à accusé et livré dans l'ordre.
    func send(data, reliable=false):
        b := nc.to_bytes(data)
        if reliable:
            if len(self.rel_order) + len(b) // FRAGMENT + 1 > 4096:
                raise("ValueError", "netgame : file des messages fiables pleine (pair injoignable ?)")
            if len(b) <= FRAGMENT:
                self._rel_add(1, 0, b)
            else:
                o := 0
                while o < len(b):
                    e := o + FRAGMENT
                    if e >= len(b):
                        self._rel_add(3, 1, b[o:len(b)])
                    else:
                        self._rel_add(3, 0, b[o:e])
                    o = e
            return
        if len(b) <= FRAGMENT:
            append(self.unrel, [0, b])
            return
        count := (len(b) + FRAGMENT - 1) // FRAGMENT
        if count > 255:
            raise("ValueError", "netgame : message non fiable trop gros (" + str(len(b)) + " octets)")
        g := self.frag_group
        self.frag_group = (self.frag_group + 1) & 65535
        k := 0
        while k < count:
            append(self.unrel, [2, g, k, count, b[k * FRAGMENT:math.min((k + 1) * FRAGMENT, len(b))]])
            k += 1

    func _rel_add(kind, last, b):
        id := self.rel_next
        self.rel_next = (self.rel_next + 1) & 65535
        self.rel_out[id] = [kind, last, b, -1000.0]
        append(self.rel_order, id)

    func pending_reliable():
        return len(self.rel_order)

    func _resend_delay():
        if not self.has_rtt:
            return 0.1
        return math.max(0.03, self.rtt + 2.0 * self.rtt_var + 0.01)

    # Paquets à envoyer maintenant (accusés + messages) ; force : paquet même vide (maintien de la connexion).
    func flush(now, force=false):
        entries := []
        rel_ids := []
        delay := self._resend_delay()
        live := []
        for id in self.rel_order:
            if id in self.rel_out:
                append(live, id)
                e := self.rel_out[id]
                if now - e[3] >= delay and len(rel_ids) < 64:
                    if e[3] > -999.0:
                        self.stats["resent"] = self.stats["resent"] + 1
                    e[3] = now
                    append(rel_ids, id)
                    if e[0] == 1:
                        append(entries, [1, id, e[2]])
                    else:
                        append(entries, [3, id, e[1], e[2]])
        self.rel_order = live
        for u in self.unrel:
            append(entries, u)
        self.unrel = []
        if len(entries) == 0 and not force and not self.need_ack and now - self.last_send < 0.25:
            return
        # regroupement dans des paquets <= MTU
        cur := []
        cur_ids := []
        size := 15
        packets := []
        for e in entries:
            w := nc.Writer()
            self._write_entry(w, e)
            eb := w.bytes()
            if size + len(eb) > MTU and len(cur) > 0:
                append(packets, [cur, cur_ids])
                cur = []
                cur_ids = []
                size = 15
            cur = cur + eb
            size += len(eb)
            if e[0] == 1 or e[0] == 3:
                append(cur_ids, e[1])
        if len(cur) > 0 or len(packets) == 0:
            append(packets, [cur, cur_ids])
        for p in packets:
            self._send_packet(now, p[0], p[1])
        self.need_ack = false
        # entrées d'envoi trop anciennes : pertes
        for s in keys(self.sent):
            st := self.sent[s]
            if now - st[0] > 1.5:
                if not st[2]:
                    self.stats["lost"] = self.stats["lost"] + 1
                    self.loss = self.loss * 0.95 + 0.05
                remove(self.sent, s)

    func _write_entry(w, e):
        k := e[0]
        w.u8(k)
        if k == 0:
            w.blob(e[1])
        elif k == 1:
            w.u16(e[1])
            w.blob(e[2])
        elif k == 2:
            w.u16(e[1])
            w.u8(e[2])
            w.u8(e[3])
            w.blob(e[4])
        else:
            w.u16(e[1])
            w.u8(e[2])
            w.blob(e[3])

    func _send_packet(now, body, ids):
        w := nc.Writer()
        w.u16(self.protocol)
        w.u8(_DATA)
        w.u32(self.key)
        w.u16(self.seq)
        w.u16(self.remote_seq & 65535 if self.remote_seq >= 0 else 0)
        w.u32(self.recv_mask if self.remote_seq >= 0 else 0)
        pkt := w.bytes() + body
        self.sent[self.seq] = [now, ids, false]
        self.seq = (self.seq + 1) & 65535
        self.last_send = now
        self.stats["packets_sent"] = self.stats["packets_sent"] + 1
        self.stats["bytes_sent"] = self.stats["bytes_sent"] + len(pkt)
        self.send_fn(pkt)

    # Paquet de données reçu (octets complets) ; rend [[octets, fiable]...] dans l'ordre de livraison.
    func receive(pkt, now):
        r := nc.Reader(pkt, 3)
        if r.u32() != self.key:
            return []
        seq := r.u16()
        ack := r.u16()
        bits := r.u32()
        self.last_recv = now
        self.stats["packets_received"] = self.stats["packets_received"] + 1
        self.stats["bytes_received"] = self.stats["bytes_received"] + len(pkt)
        self._acks(ack, bits, now)
        if not self._track(seq):
            return []
        self.need_ack = true
        out := []
        while not r.at_end():
            k := r.u8()
            if k == 0:
                append(out, [r.blob_bytes(), false])
            elif k == 1:
                id := r.u16()
                self._rel_store(id, [1, 0, r.blob_bytes()])
            elif k == 2:
                g := r.u16()
                idx := r.u8()
                cnt := r.u8()
                d := r.blob_bytes()
                if cnt == 0 or idx >= cnt:
                    raise("ValueError", "netgame : fragment invalide")
                if not (g in self.frag_in):
                    self.frag_in[g] = [cnt, {}, now]
                fg := self.frag_in[g]
                fg[1][idx] = d
                if len(keys(fg[1])) == fg[0]:
                    whole := []
                    j := 0
                    while j < fg[0]:
                        whole = whole + fg[1][j]
                        j += 1
                    remove(self.frag_in, g)
                    append(out, [whole, false])
            elif k == 3:
                id := r.u16()
                last := r.u8()
                self._rel_store(id, [3, last, r.blob_bytes()])
            else:
                raise("ValueError", "netgame : message de type inconnu " + str(k))
        # livraison ordonnée des messages fiables
        while self.rel_in_next in self.rel_in:
            e := self.rel_in[self.rel_in_next]
            remove(self.rel_in, self.rel_in_next)
            self.rel_in_next = (self.rel_in_next + 1) & 65535
            if e[0] == 1:
                append(out, [e[2], true])
            else:
                self.rel_partial = self.rel_partial + e[2]
                if e[1] == 1:
                    append(out, [self.rel_partial, true])
                    self.rel_partial = []
        for g in keys(self.frag_in):
            if now - self.frag_in[g][2] > 1.0:
                remove(self.frag_in, g)
        return out

    func _rel_store(id, e):
        d := (id - self.rel_in_next) & 65535
        if d < 32768 and not (id in self.rel_in):
            self.rel_in[id] = e

    func _track(seq):
        if self.remote_seq < 0:
            self.remote_seq = seq
            self.recv_mask = 0
            return true
        if _newer(seq, self.remote_seq):
            d := (seq - self.remote_seq) & 65535
            if d <= 32:
                self.recv_mask = ((self.recv_mask << d) | (1 << (d - 1))) & 4294967295
            else:
                self.recv_mask = 0
            self.remote_seq = seq
            return true
        d := (self.remote_seq - seq) & 65535
        if d == 0 or d > 32:
            return false
        bit := 1 << (d - 1)
        if (self.recv_mask & bit) != 0:
            return false
        self.recv_mask = self.recv_mask | bit
        return true

    func _acks(ack, bits, now):
        i := 0
        while i <= 32:
            if i == 0 or ((bits >> (i - 1)) & 1) == 1:
                s := (ack - i) & 65535
                if s in self.sent:
                    st := self.sent[s]
                    if not st[2]:
                        st[2] = true
                        self.stats["acked"] = self.stats["acked"] + 1
                        self.loss = self.loss * 0.95
                        sample := now - st[0]
                        if i != 0:
                            sample = -1.0          # accusé tardif (porté par les bits) : pas d'échantillon de RTT
                        if sample < 0.0:
                            sample = sample
                        elif not self.has_rtt:
                            self.rtt = sample
                            self.rtt_var = sample / 2.0
                            self.has_rtt = true
                        else:
                            self.rtt_var = self.rtt_var * 0.75 + math.abs(sample - self.rtt) * 0.25
                            self.rtt = self.rtt * 0.875 + sample * 0.125
                        for id in st[1]:
                            if id in self.rel_out:
                                remove(self.rel_out, id)
            i += 1

# ---------------------------------------------------------------------------------------------------------------------
# Serveur et client
# ---------------------------------------------------------------------------------------------------------------------

func _header(protocol, kind):
    w := nc.Writer()
    w.u16(protocol)
    w.u8(kind)
    return w

func _pad(w, n):
    while w.size() < n:
        w.u8(0)

func _message_event(kind, client, raw_bytes, reliable, raw_mode):
    data := null
    if raw_mode:
        data = nc.to_str(raw_bytes)
    else:
        data = nc.decode(raw_bytes)
    return {"type": "message", "client": client, "data": data, "reliable": reliable}

class Server:
    # transport : UdpTransport, LoopbackTransport, LinkSim... ; raw : messages livrés en octets (str), sans décodage.
    func init(transport, max_clients=16, protocol=PROTOCOL, timeout=5.0, clock=null, raw=false):
        self.transport = transport
        self.max_clients = max_clients
        self.protocol = protocol
        self.timeout = timeout
        self.clock = clock if clock != null else Clock()
        self.raw = raw
        self.clients = {}            # id -> {"addr", "conn", "key"}
        self.by_addr = {}
        self.pending = {}            # adresse -> [sel client, sel serveur, instant]
        self.next_id = 1
        self.rejected = 0

    func _send_to(addr, w):
        self.transport.send(addr, w.bytes())

    # Reçoit, gère les connexions et délais ; rend la liste des événements.
    func update(now=null):
        t := now if now != null else self.clock.now()
        events := []
        for item in self.transport.poll():
            pkt := item[0]
            addr := item[1]
            try:
                self._packet(pkt, addr, t, events)
            catch e:
                self.rejected += 1
        for id in keys(self.clients):
            c := self.clients[id]
            if t - c["conn"].last_recv > self.timeout:
                self._drop(id, "timeout", events, false)
        for k in keys(self.pending):
            if t - self.pending[k][2] > self.timeout:
                remove(self.pending, k)
        return events

    func _packet(pkt, addr, t, events):
        if len(pkt) < 3 or (pkt[0] | (pkt[1] << 8)) != self.protocol:
            self.rejected += 1
            return
        kind := pkt[2]
        key := addr_key(addr)
        if kind == _DATA:
            if key in self.by_addr:
                id := self.by_addr[key]
                c := self.clients[id]
                for m in c["conn"].receive(pkt, t):
                    append(events, _message_event("message", id, m[0], m[1], self.raw))
            return
        r := nc.Reader(pkt, 3)
        if kind == _REQUEST:
            if len(pkt) < 200:
                return
            csalt := r.u32()
            if key in self.by_addr:
                c := self.clients[self.by_addr[key]]
                if c["salt"] == csalt:
                    self._accept(addr, c)
                return
            if len(keys(self.clients)) >= self.max_clients:
                w := _header(self.protocol, _DENY)
                w.u32(csalt)
                self._send_to(addr, w)
                return
            if not (key in self.pending) or self.pending[key][0] != csalt:
                self.pending[key] = [csalt, _salt(), t]
            w := _header(self.protocol, _CHALLENGE)
            w.u32(csalt)
            w.u32(self.pending[key][1])
            self._send_to(addr, w)
        elif kind == _RESPONSE:
            if len(pkt) < 200:
                return
            csalt := r.u32()
            proof := r.u32()
            if key in self.by_addr:
                c := self.clients[self.by_addr[key]]
                if c["salt"] == csalt:
                    self._accept(addr, c)
                return
            if not (key in self.pending):
                return
            p := self.pending[key]
            if p[0] != csalt or (p[0] ^ p[1]) != proof:
                return
            if len(keys(self.clients)) >= self.max_clients:
                return
            remove(self.pending, key)
            id := self.next_id
            self.next_id += 1
            tr := self.transport
            conn := Connection((b) => tr.send(addr, b), t, self.protocol, csalt)
            c := {"id": id, "addr": addr, "conn": conn, "salt": csalt}
            self.clients[id] = c
            self.by_addr[key] = id
            self._accept(addr, c)
            append(events, {"type": "connect", "client": id, "address": addr})
        elif kind == _DISCONNECT:
            if key in self.by_addr:
                id := self.by_addr[key]
                if r.remaining() >= 4 and r.u32() == self.clients[id]["salt"]:
                    self._drop(id, "client", events, false)

    func _accept(addr, c):
        w := _header(self.protocol, _ACCEPT)
        w.u32(c["salt"])
        w.u16(c["id"])
        self._send_to(addr, w)

    func _drop(id, reason, events, notify):
        if not (id in self.clients):
            return
        c := self.clients[id]
        if notify:
            k := 0
            while k < 3:
                w := _header(self.protocol, _DISCONNECT)
                w.u32(c["salt"])
                self._send_to(c["addr"], w)
                k += 1
        remove(self.by_addr, addr_key(c["addr"]))
        remove(self.clients, id)
        append(events, {"type": "disconnect", "client": id, "reason": reason})

    # Envoie les paquets en attente de tous les clients (une fois par pas réseau).
    func flush(now=null):
        t := now if now != null else self.clock.now()
        for id in keys(self.clients):
            self.clients[id]["conn"].flush(t)

    func send(client, value, reliable=false):
        if client in self.clients:
            self.clients[client]["conn"].send(nc.encode(value), reliable)

    func send_raw(client, data, reliable=false):
        if client in self.clients:
            self.clients[client]["conn"].send(data, reliable)

    func broadcast(value, reliable=false, except_client=null):
        b := nc.encode(value)
        for id in keys(self.clients):
            if id != except_client:
                self.clients[id]["conn"].send(b, reliable)

    func client_ids():
        return keys(self.clients)

    func connection(client):
        return self.clients[client]["conn"] if client in self.clients else null

    func rtt(client):
        c := self.connection(client)
        return c.rtt if c != null else 0.0

    func disconnect(client):
        ev := []
        self._drop(client, "server", ev, true)

    func shutdown():
        for id in keys(self.clients):
            self.disconnect(id)
        self.transport.close()

class Client:
    func init(transport, protocol=PROTOCOL, timeout=5.0, clock=null, raw=false):
        self.transport = transport
        self.protocol = protocol
        self.timeout = timeout
        self.clock = clock if clock != null else Clock()
        self.raw = raw
        self.state = "disconnected"
        self.server = null
        self.conn = null
        self.id = 0
        self.salt = 0
        self.server_salt = 0
        self.started = 0.0
        self.last_try = -1000.0
        self.reason = null

    func connect(host, port):
        h := host
        if not _dns.is_ip(h):
            try:
                h = _dns.resolve_one(host, 4)
            catch e:
                h = host
        self.server = [h, port]
        self.state = "connecting"
        self.salt = _salt()
        self.started = self.clock.now()
        self.last_try = -1000.0
        self.reason = null

    func connected():
        return self.state == "connected"

    func _send(w):
        self.transport.send(self.server, w.bytes())

    func update(now=null):
        t := now if now != null else self.clock.now()
        events := []
        for item in self.transport.poll():
            if self.server == null or addr_key(item[1]) != addr_key(self.server):
                continue
            try:
                self._packet(item[0], t, events)
            catch e:
                continue
        if self.state == "connecting" or self.state == "challenged":
            if t - self.started > self.timeout:
                self.state = "disconnected"
                self.reason = "timeout"
                append(events, {"type": "disconnect", "reason": "timeout"})
            elif t - self.last_try >= 0.2:
                self.last_try = t
                w := _header(self.protocol, _REQUEST if self.state == "connecting" else _RESPONSE)
                w.u32(self.salt)
                if self.state == "challenged":
                    w.u32(self.salt ^ self.server_salt)
                _pad(w, 256)
                self._send(w)
        elif self.state == "connected":
            if t - self.conn.last_recv > self.timeout:
                self.state = "disconnected"
                self.reason = "timeout"
                append(events, {"type": "disconnect", "reason": "timeout"})
        return events

    func _packet(pkt, t, events):
        if len(pkt) < 3 or (pkt[0] | (pkt[1] << 8)) != self.protocol:
            return
        kind := pkt[2]
        r := nc.Reader(pkt, 3)
        if kind == _DATA:
            if self.state == "connected":
                for m in self.conn.receive(pkt, t):
                    append(events, _message_event("message", 0, m[0], m[1], self.raw))
        elif kind == _CHALLENGE:
            if self.state == "connecting" and r.u32() == self.salt:
                self.server_salt = r.u32()
                self.state = "challenged"
                self.last_try = -1000.0
        elif kind == _ACCEPT:
            if (self.state == "challenged" or self.state == "connecting") and r.u32() == self.salt:
                self.id = r.u16()
                tr := self.transport
                srv := self.server
                self.conn = Connection((b) => tr.send(srv, b), t, self.protocol, self.salt)
                self.state = "connected"
                append(events, {"type": "connect", "client": self.id})
        elif kind == _DENY:
            if self.state != "connected" and r.u32() == self.salt:
                self.state = "disconnected"
                self.reason = "full"
                append(events, {"type": "disconnect", "reason": "full"})
        elif kind == _DISCONNECT:
            if self.state == "connected" and r.u32() == self.salt:
                self.state = "disconnected"
                self.reason = "server"
                append(events, {"type": "disconnect", "reason": "server"})

    func send(value, reliable=false):
        if self.state == "connected":
            self.conn.send(nc.encode(value), reliable)

    func send_raw(data, reliable=false):
        if self.state == "connected":
            self.conn.send(data, reliable)

    func flush(now=null):
        if self.state == "connected":
            self.conn.flush(now if now != null else self.clock.now())

    func rtt():
        return self.conn.rtt if self.conn != null else 0.0

    func disconnect():
        if self.state == "connected":
            k := 0
            while k < 3:
                w := _header(self.protocol, _DISCONNECT)
                w.u32(self.salt)
                self._send(w)
                k += 1
        self.state = "disconnected"
        self.reason = "client"

    func close():
        self.disconnect()
        self.transport.close()

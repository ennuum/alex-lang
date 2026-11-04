# ALEX STANDARD LIBRARY — netgame.snapshot
#
# Synchronisation par INSTANTANÉS (serveur autoritaire) :
#   - le serveur capture l'état du monde à chaque pas (capture) et envoie à chaque client un instantané COMPRESSÉ
#     PAR DIFFÉRENCE avec le dernier instantané que ce client a confirmé (ack) : seuls les champs modifiés partent,
#     en écarts quantifiés ; entités nouvelles en entier, entités disparues par leur numéro ;
#   - le client reconstruit les instantanés, renvoie le dernier reçu (ack_tick) et les INTERPOLE avec un retard fixe
#     (delay, 100 ms par défaut : deux instantanés à 20 Hz) pour un mouvement fluide malgré la gigue et les pertes.
# Les instantanés partent en NON FIABLE (un instantané perdu est remplacé par le suivant).
#
#   use netgame.snapshot as snap
#   schema := snap.Schema([["x", "float", 0.01], ["y", "float", 0.01], ["angle", "angle"], ["hp", "uint"],
#                          ["nom", "str"]])
#   # serveur, à chaque pas
#   ss.capture(tick, {1: {"x": 3.2, "y": 0.5, "angle": 1.57, "hp": 100, "nom": "Ana"}, ...})
#   for c in srv.client_ids():
#       srv.send(c, ss.encode(c, {"input": dernier_numero[c]}))       # str d'octets, extra quelconque
#   # serveur, message reçu {"ack": t} : ss.ack(client, t)
#   # client
#   r := sc.receive(e["data"])                 # [tick, extra] ou null (base absente : attendre le suivant)
#   cli.send({"ack": sc.ack_tick(), ...})
#   for id, etat in sc.sample():               # états interpolés au temps de rendu
#
# Types de champs : "float" (pas de quantification, 0.01 par défaut), "angle" (radians, chemin le plus court,
# 0.001), "int", "uint", "bool", "str", "any" (valeur netgame.codec, non interpolée).
# Erreurs : ValueError (schéma, données invalides).

from core use len, type, to_int
from collections use append, keys, remove
use math
use netgame.codec as nc
use netgame as _ng

const _TWO_PI := 6.283185307179586

func _wrap(a):
    r := a - _TWO_PI * math.floor((a + math.PI) / _TWO_PI)
    return r

class Schema:
    func init(fields):
        self.names = []
        self.kinds = []
        self.scales = []
        for f in fields:
            k := f[1]
            sc := f[2] if len(f) > 2 else (0.001 if k == "angle" else 0.01)
            if not (k == "float" or k == "angle" or k == "int" or k == "uint" or k == "bool" or k == "str" or k == "any"):
                raise("ValueError", "netgame.snapshot : type de champ inconnu '" + str(k) + "'")
            append(self.names, f[0])
            append(self.kinds, k)
            append(self.scales, sc)
        if len(self.names) > 62:
            raise("ValueError", "netgame.snapshot : 62 champs au plus")

    # dict -> liste quantifiée (champ absent : 0 / false / "" / null)
    func quantize(d):
        out := []
        i := 0
        while i < len(self.names):
            k := self.kinds[i]
            v := d[self.names[i]] if self.names[i] in d else null
            if k == "float":
                append(out, nc.quantize(v if v != null else 0.0, self.scales[i]))
            elif k == "angle":
                append(out, nc.quantize(_wrap(v if v != null else 0.0), self.scales[i]))
            elif k == "int" or k == "uint":
                append(out, to_int(v) if v != null else 0)
            elif k == "bool":
                append(out, v == true)
            elif k == "str":
                append(out, v if v != null else "")
            else:
                append(out, v)
            i += 1
        return out

    func dequantize(q):
        d := {}
        i := 0
        while i < len(self.names):
            k := self.kinds[i]
            if k == "float" or k == "angle":
                d[self.names[i]] = q[i] * self.scales[i]
            else:
                d[self.names[i]] = q[i]
            i += 1
        return d

    func _write(w, i, v, base):
        k := self.kinds[i]
        if k == "float" or k == "angle" or k == "int":
            w.sint(v - base if base != null else v)
        elif k == "uint":
            if base != null:
                w.sint(v - base)
            else:
                w.uint(v)
        elif k == "bool":
            w.flag(v)
        elif k == "str":
            w.text(v)
        else:
            w.value(v)

    func _read(r, i, base):
        k := self.kinds[i]
        if k == "float" or k == "angle" or k == "int":
            return r.sint() + (base if base != null else 0)
        if k == "uint":
            if base != null:
                return base + r.sint()
            return r.uint()
        if k == "bool":
            return r.flag()
        if k == "str":
            return r.text()
        return r.value()

    # Interpolation de deux états quantifiés (t dans 0..1) -> dict.
    func lerp(a, b, t):
        d := {}
        i := 0
        while i < len(self.names):
            k := self.kinds[i]
            if k == "float":
                d[self.names[i]] = (a[i] + (b[i] - a[i]) * t) * self.scales[i]
            elif k == "angle":
                x := a[i] * self.scales[i]
                y := b[i] * self.scales[i]
                d[self.names[i]] = _wrap(x + _wrap(y - x) * t)
            elif k == "int" or k == "uint":
                d[self.names[i]] = a[i] if t < 0.5 else b[i]
            else:
                d[self.names[i]] = b[i] if t >= 1.0 else a[i]
            i += 1
        return d

# ---------------------------------------------------------------------------------------------------------------------
# Serveur
# ---------------------------------------------------------------------------------------------------------------------

class SnapshotServer:
    func init(schema, history=64):
        self.schema = schema
        self.history = {}            # tick -> {id: état quantifié}
        self.ticks = []
        self.keep = history
        self.acked = {}              # client -> dernier tick confirmé
        self.tick = -1
        self.stats = {"full_bytes": 0, "delta_bytes": 0, "sent": 0}

    func capture(tick, entities):
        snap := {}
        for id in keys(entities):
            snap[id] = self.schema.quantize(entities[id])
        self.history[tick] = snap
        append(self.ticks, tick)
        self.tick = tick
        while len(self.ticks) > self.keep:
            old := self.ticks[0]
            self.ticks = self.ticks[1:len(self.ticks)]
            remove(self.history, old)

    # Le client a reçu l'instantané `tick` : il devient sa base.
    func ack(client, tick):
        if not (tick in self.history):
            return
        if client in self.acked and self.acked[client] >= tick:
            return
        self.acked[client] = tick

    func forget(client):
        if client in self.acked:
            remove(self.acked, client)

    # Instantané du dernier tick capturé pour `client` (str d'octets), différentiel si une base est connue.
    func encode(client, extra=null, tick=null):
        t := tick if tick != null else self.tick
        if not (t in self.history):
            raise("ValueError", "netgame.snapshot : tick " + str(t) + " non capturé")
        cur := self.history[t]
        base := null
        bt := -1
        if client in self.acked and self.acked[client] in self.history and self.acked[client] < t:
            bt = self.acked[client]
            base = self.history[bt]
        sch := self.schema
        nf := len(sch.names)
        w := nc.Writer()
        w.u8(1)
        w.uint(t)
        w.uint(t - bt if base != null else 0)
        recs := []
        for id in keys(cur):
            q := cur[id]
            if base != null and id in base:
                b := base[id]
                mask := 0
                i := 0
                while i < nf:
                    if q[i] != b[i]:
                        mask = mask | (1 << i)
                    i += 1
                if mask != 0:
                    append(recs, [id, mask, q, b])
            else:
                append(recs, [id, -1, q, null])
        w.uint(len(recs))
        for rc in recs:
            w.sint(rc[0])
            if rc[1] < 0:
                w.u8(1)
                i := 0
                while i < nf:
                    sch._write(w, i, rc[2][i], null)
                    i += 1
            else:
                w.u8(0)
                w.uint(rc[1])
                i := 0
                while i < nf:
                    if ((rc[1] >> i) & 1) != 0:
                        sch._write(w, i, rc[2][i], rc[3][i])
                    i += 1
        gone := []
        if base != null:
            for id in keys(base):
                if not (id in cur):
                    append(gone, id)
        w.uint(len(gone))
        for id in gone:
            w.sint(id)
        w.value(extra)
        self.stats["sent"] = self.stats["sent"] + 1
        if base != null:
            self.stats["delta_bytes"] = self.stats["delta_bytes"] + w.size()
        else:
            self.stats["full_bytes"] = self.stats["full_bytes"] + w.size()
        return w.data()

# ---------------------------------------------------------------------------------------------------------------------
# Client
# ---------------------------------------------------------------------------------------------------------------------

class SnapshotClient:
    # tick_rate : instantanés par seconde du serveur ; delay : retard d'interpolation (s).
    func init(schema, tick_rate=20.0, delay=0.1, keep=32, clock=null):
        self.schema = schema
        self.rate = tick_rate * 1.0
        self.delay = delay
        self.keep = keep
        self.clock = clock if clock != null else _ng.Clock()
        self.snaps = {}              # tick -> {id: état quantifié}
        self.ticks = []              # ordonnés
        self.latest_tick = -1
        self.offset = null           # temps serveur - temps local
        self.extra = null
        self.stats = {"received": 0, "dropped": 0, "bytes": 0}

    # Décode un instantané ; rend [tick, extra], ou null s'il est ancien ou si sa base manque.
    func receive(payload, now=null):
        t0 := now if now != null else self.clock.now()
        r := nc.Reader(payload)
        if r.u8() != 1:
            raise("ValueError", "netgame.snapshot : version inconnue")
        tick := r.uint()
        bd := r.uint()
        self.stats["bytes"] = self.stats["bytes"] + r.remaining() + 1
        if tick in self.snaps or tick <= self.latest_tick - self.keep:
            self.stats["dropped"] = self.stats["dropped"] + 1
            return null
        base := {}
        if bd > 0:
            if not ((tick - bd) in self.snaps):
                self.stats["dropped"] = self.stats["dropped"] + 1
                return null
            base = self.snaps[tick - bd]
        sch := self.schema
        nf := len(sch.names)
        snap := {}
        for id in keys(base):
            snap[id] = base[id]
        n := r.uint()
        k := 0
        while k < n:
            id := r.sint()
            full := r.u8()
            if full == 1:
                q := []
                i := 0
                while i < nf:
                    append(q, sch._read(r, i, null))
                    i += 1
                snap[id] = q
            else:
                if not (id in base):
                    raise("ValueError", "netgame.snapshot : entité " + str(id) + " absente de la base")
                mask := r.uint()
                b := base[id]
                q := [x for x in b]
                i := 0
                while i < nf:
                    if ((mask >> i) & 1) != 0:
                        q[i] = sch._read(r, i, b[i])
                    i += 1
                snap[id] = q
            k += 1
        ng := r.uint()
        k = 0
        while k < ng:
            id := r.sint()
            if id in snap:
                remove(snap, id)
            k += 1
        extra := r.value()
        self.snaps[tick] = snap
        self._insert(tick)
        self.stats["received"] = self.stats["received"] + 1
        if tick > self.latest_tick:
            self.latest_tick = tick
            self.extra = extra
        # synchronisation d'horloge : décalage lissé, recalé si l'écart devient grand
        off := tick / self.rate - t0
        if self.offset == null or math.abs(off - self.offset) > 0.25:
            self.offset = off
        elif off > self.offset:
            self.offset += (off - self.offset) * 0.2
        else:
            self.offset += (off - self.offset) * 0.02
        return [tick, extra]

    func _insert(tick):
        i := len(self.ticks)
        append(self.ticks, tick)
        while i > 0 and self.ticks[i - 1] > tick:
            self.ticks[i] = self.ticks[i - 1]
            i -= 1
        self.ticks[i] = tick
        while len(self.ticks) > self.keep:
            old := self.ticks[0]
            self.ticks = self.ticks[1:len(self.ticks)]
            remove(self.snaps, old)

    # Dernier tick reçu (à renvoyer au serveur comme base).
    func ack_tick():
        return self.latest_tick

    # Temps de rendu en ticks (fractionnaire).
    func render_tick(now=null):
        t := now if now != null else self.clock.now()
        if self.offset == null:
            return -1.0
        return (t + self.offset - self.delay) * self.rate

    # États interpolés {id: dict} au temps de rendu.
    func sample(now=null):
        out := {}
        if len(self.ticks) == 0:
            return out
        rt := self.render_tick(now)
        a := -1
        b := -1
        for t in self.ticks:
            if t <= rt:
                a = t
            elif b < 0:
                b = t
        sch := self.schema
        if a < 0:
            s := self.snaps[self.ticks[0]]
            for id in keys(s):
                out[id] = sch.dequantize(s[id])
            return out
        sa := self.snaps[a]
        if b < 0:
            for id in keys(sa):
                out[id] = sch.dequantize(sa[id])
            return out
        sb := self.snaps[b]
        f := (rt - a) / (b - a)
        for id in keys(sa):
            if id in sb:
                out[id] = sch.lerp(sa[id], sb[id], f)
            else:
                out[id] = sch.dequantize(sa[id])
        return out

    # Dernier état reçu {id: dict} (réconciliation de la prédiction).
    func latest():
        out := {}
        if self.latest_tick < 0:
            return out
        s := self.snaps[self.latest_tick]
        for id in keys(s):
            out[id] = self.schema.dequantize(s[id])
        return out

    # Retard d'interpolation réellement subi (s) : temps serveur estimé - temps de rendu.
    func latency_budget():
        return self.delay

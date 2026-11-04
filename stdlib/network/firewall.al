# ALEX STANDARD LIBRARY — network.firewall
#
# Pare-feu applicatif : filtrage des connexions entrantes et sortantes d'un programme ALEX par règles ordonnées
# (protocole, adresses source / destination en CIDR, ports et plages), politique par défaut, liste de blocage
# temporaire, limitation du débit par adresse et journal des décisions. Il agit au niveau de l'application
# (accept / connect), sans modifier le pare-feu du système d'exploitation.
#
#   fw := Firewall("deny")
#   fw.add("allow tcp from 10.0.0.0/8 to any port 22,80,8000-8080")
#   fw.add("deny tcp from 192.168.1.66 to any")                  la première règle qui correspond l'emporte
#   fw.check("tcp", "10.1.2.3", 51515, "10.0.0.1", 80) -> Decision (action, rule)
#   écouteur := fw.guard(tcp.listen("0.0.0.0", 8080))           accept() refuse silencieusement les autres
#   conn := fw.connect("exemple.org", 443)                       sortie contrôlée (règles « out »)
#   fw.block("203.0.113.9", 600) ; fw.limit_rate(5, 20)          blocage temporaire, 5 connexions/s par source
#
# Syntaxe d'une règle : ACTION [in|out] [tcp|udp|any] [from SRC [port P]] [to DST [port P]] [# commentaire]
#   ACTION : allow, deny (abandon silencieux), reject (refus signalé) ; SRC / DST : any, adresse, CIDR, ou liste
#   séparée par des virgules ; P : port, plage « a-b » ou liste.
#
# Erreurs : FirewallError (connexion sortante refusée), ArgumentError (règle invalide).

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use time as _time
use network.ipaddress as _ip
use network.dns as _dns
use network.tcp as _tcp
use network.security as _sec

const ALLOW := "allow"
const DENY := "deny"
const REJECT := "reject"

func _bad(rule, why):
    raise("ArgumentError", "firewall : règle invalide « " + str(rule) + " » : " + why)

class PortSet:
    # spec : null / "any" (tous), int, « 80 », « 1000-2000 », « 22,80,443 ».
    func init(spec=null):
        self.ranges = []
        if spec == null or spec == "any" or spec == "*":
            return
        if type(spec) == "int":
            append(self.ranges, [spec, spec])
            return
        if type(spec) == "list":
            for p in spec:
                for r in PortSet(p).ranges:
                    append(self.ranges, r)
            return
        for part in _s.split(str(spec), ","):
            t := _s.trim(part)
            if t == "":
                continue
            dash := _s.find(t, "-")
            if dash > 0:
                a := _port(_s.substring(t, 0, dash), spec)
                b := _port(_s.substring(t, dash + 1, len(t)), spec)
                if a > b:
                    _bad(spec, "plage de ports inversée")
                append(self.ranges, [a, b])
            else:
                p := _port(t, spec)
                append(self.ranges, [p, p])

    func any():
        return len(self.ranges) == 0

    func contains(port):
        if len(self.ranges) == 0:
            return true
        if port == null:
            return false
        for r in self.ranges:
            if port >= r[0] and port <= r[1]:
                return true
        return false

    func str():
        if len(self.ranges) == 0:
            return "any"
        out := []
        for r in self.ranges:
            if r[0] == r[1]:
                append(out, str(r[0]))
            else:
                append(out, str(r[0]) + "-" + str(r[1]))
        return _s.join(",", out)

func _port(t, spec):
    v := _s.trim(t)
    if v == "":
        _bad(spec, "port vide")
    for c in v:
        if c < '0' or c > '9':
            _bad(spec, "port non numérique « " + v + " »")
    p := to_int(v)
    if p > 65535:
        _bad(spec, "port hors de 0..65535")
    return p

class AddressSet:
    # spec : null / "any", adresse, CIDR, ou liste (texte séparé par des virgules ou list).
    func init(spec=null):
        self.networks = []
        if spec == null or spec == "any" or spec == "*":
            return
        items := spec
        if type(spec) == "str":
            items = _s.split(spec, ",")
        for x in items:
            t := _s.trim(str(x))
            if t == "":
                continue
            try:
                append(self.networks, _ip.ip_network(t, false))
            catch e:
                _bad(spec, "adresse ou réseau invalide « " + t + " »")

    func any():
        return len(self.networks) == 0

    func contains(address):
        if len(self.networks) == 0:
            return true
        if address == null:
            return false
        a := null
        try:
            a = _ip.ip_address(address)
        catch e:
            return false
        m := a.ipv4_mapped()
        for n in self.networks:
            if n.contains(a) or (m != null and n.contains(m)):
                return true
        return false

    func str():
        if len(self.networks) == 0:
            return "any"
        out := []
        for n in self.networks:
            append(out, n.str())
        return _s.join(",", out)

class Rule:
    func init(action, direction="in", protocol="any", source=null, source_ports=null, destination=null, destination_ports=null, comment=""):
        if action != ALLOW and action != DENY and action != REJECT:
            _bad(action, "action allow, deny ou reject attendue")
        if direction != "in" and direction != "out" and direction != "any":
            _bad(direction, "sens in, out ou any attendu")
        if protocol != "tcp" and protocol != "udp" and protocol != "any":
            _bad(protocol, "protocole tcp, udp ou any attendu")
        self.action = action
        self.direction = direction
        self.protocol = protocol
        self.source = AddressSet(source)
        self.source_ports = PortSet(source_ports)
        self.destination = AddressSet(destination)
        self.destination_ports = PortSet(destination_ports)
        self.comment = comment
        self.hits = 0

    func matches(protocol, src, sport, dst, dport, direction):
        if self.direction != "any" and direction != "any" and self.direction != direction:
            return false
        if self.protocol != "any" and protocol != self.protocol:
            return false
        return self.source.contains(src) and self.source_ports.contains(sport) and self.destination.contains(dst) and self.destination_ports.contains(dport)

    func str():
        out := self.action + " " + self.direction + " " + self.protocol + " from " + self.source.str()
        if not self.source_ports.any():
            out += " port " + self.source_ports.str()
        out += " to " + self.destination.str()
        if not self.destination_ports.any():
            out += " port " + self.destination_ports.str()
        if self.comment != "":
            out += " # " + self.comment
        return out

# Règle depuis son texte (voir l'en-tête).
func parse_rule(text):
    t := text
    comment := ""
    h := _s.find(t, "#")
    if h >= 0:
        comment = _s.trim(_s.substring(t, h + 1, len(t)))
        t = _s.substring(t, 0, h)
    words := []
    for w in _s.split(_s.replace(_s.trim(t), "\t", " "), " "):
        if w != "":
            append(words, _s.lower(w))
    if len(words) == 0:
        _bad(text, "règle vide")
    action := words[0]
    i := 1
    direction := "in"
    protocol := "any"
    src := null
    sport := null
    dst := null
    dport := null
    if i < len(words) and (words[i] == "in" or words[i] == "out" or words[i] == "any") and (i + 1 >= len(words) or words[i + 1] != "port"):
        direction = words[i]
        i += 1
    if i < len(words) and (words[i] == "tcp" or words[i] == "udp" or words[i] == "any" or words[i] == "proto"):
        if words[i] == "proto":
            i += 1
        protocol = words[i]
        i += 1
    while i < len(words):
        w := words[i]
        if w == "from" and i + 1 < len(words):
            src = words[i + 1]
            i += 2
            if i + 1 < len(words) and words[i] == "port":
                sport = words[i + 1]
                i += 2
        elif w == "to" and i + 1 < len(words):
            dst = words[i + 1]
            i += 2
            if i + 1 < len(words) and words[i] == "port":
                dport = words[i + 1]
                i += 2
        elif w == "port" and i + 1 < len(words):
            dport = words[i + 1]
            i += 2
        else:
            _bad(text, "mot inattendu « " + w + " »")
    return Rule(action, direction, protocol, src, sport, dst, dport, comment)

class Decision:
    func init(action, rule, reason):
        self.action = action          # "allow", "deny" ou "reject"
        self.rule = rule              # Rule appliquée, ou null (politique par défaut, blocage, débit)
        self.reason = reason

    func allowed():
        return self.action == ALLOW

    func str():
        return self.action + " (" + self.reason + ")"

class Firewall:
    # default_policy : décision quand aucune règle ne correspond ; log : fonction(texte) appelée à chaque refus.
    func init(default_policy=DENY, log=null, default_out=ALLOW):
        if default_policy != ALLOW and default_policy != DENY and default_policy != REJECT:
            _bad(default_policy, "politique allow, deny ou reject attendue")
        self.default_policy = default_policy
        self.default_out = default_out
        self.rules = []
        self.blocked = {}         # adresse -> échéance (horodatage monotone) ou null (définitif)
        self.limiter = null
        self.log = log
        self.allowed_count = 0
        self.denied_count = 0
        self.history = []         # dernières décisions de refus (texte), 100 au plus

    # Ajoute une règle (Rule ou texte) à la fin ; rend la règle.
    func add(rule):
        r := rule
        if type(rule) == "str":
            r = parse_rule(rule)
        append(self.rules, r)
        return r

    func insert(index, rule):
        r := rule
        if type(rule) == "str":
            r = parse_rule(rule)
        out := []
        i := 0
        for x in self.rules:
            if i == index:
                append(out, r)
            append(out, x)
            i += 1
        if index >= len(self.rules):
            append(out, r)
        self.rules = out
        return r

    func remove(rule):
        kept := []
        for x in self.rules:
            if x != rule:
                append(kept, x)
        self.rules = kept

    func clear():
        self.rules = []

    # Bloque une adresse (seconds : durée, null : définitivement).
    func block(address, seconds=null):
        until := null
        if seconds != null:
            until = _time.monotonic() + seconds
        self.blocked[_ip.ip_address(address).str()] = until

    func unblock(address):
        k := _ip.ip_address(address).str()
        if contains_key(self.blocked, k):
            d := {}
            for x in keys(self.blocked):
                if x != k:
                    d[x] = self.blocked[x]
            self.blocked = d

    func is_blocked(address):
        k := null
        try:
            k = _ip.ip_address(address).str()
        catch e:
            return false
        if not contains_key(self.blocked, k):
            return false
        until := self.blocked[k]
        if until != null and _time.monotonic() >= until:
            self.unblock(k)
            return false
        return true

    # Limite les connexions entrantes : `rate` par seconde et par adresse source, rafales de `burst`.
    func limit_rate(rate, burst):
        self.limiter = _sec.RateLimiter(rate, burst)

    func _record(decision, protocol, src, sport, dst, dport, direction):
        if decision.allowed():
            self.allowed_count += 1
            return decision
        self.denied_count += 1
        line := decision.action + " " + direction + " " + protocol + " " + str(src) + ":" + str(sport) + " -> " + str(dst) + ":" + str(dport) + " (" + decision.reason + ")"
        append(self.history, line)
        if len(self.history) > 100:
            self.history = self.history[len(self.history) - 100:len(self.history)]
        if self.log != null:
            self.log(line)
        return decision

    # Décision pour un flux. direction : "in" (connexion reçue) ou "out" (connexion émise).
    func check(protocol, src, sport, dst, dport, direction="in"):
        if direction == "in" and src != null and self.is_blocked(src):
            return self._record(Decision(DENY, null, "adresse bloquée"), protocol, src, sport, dst, dport, direction)
        if direction == "out" and dst != null and self.is_blocked(dst):
            return self._record(Decision(REJECT, null, "destination bloquée"), protocol, src, sport, dst, dport, direction)
        for r in self.rules:
            if r.matches(protocol, src, sport, dst, dport, direction):
                r.hits += 1
                d := Decision(r.action, r, "règle « " + r.str() + " »")
                if d.allowed() and direction == "in" and self.limiter != null and not self.limiter.allow(str(src)):
                    d = Decision(DENY, r, "débit dépassé")
                return self._record(d, protocol, src, sport, dst, dport, direction)
        policy := self.default_policy
        if direction == "out":
            policy = self.default_out
        d := Decision(policy, null, "politique par défaut")
        if d.allowed() and direction == "in" and self.limiter != null and not self.limiter.allow(str(src)):
            d = Decision(DENY, null, "débit dépassé")
        return self._record(d, protocol, src, sport, dst, dport, direction)

    func allows(protocol, src, sport, dst, dport, direction="in"):
        return self.check(protocol, src, sport, dst, dport, direction).allowed()

    # Écouteur filtré (network.tcp.Listener ou TlsListener) : accept() ferme sans un mot les connexions refusées.
    func guard(listener):
        return GuardedListener(listener, self)

    # Connexion TCP sortante contrôlée : chaque adresse résolue est vérifiée (règles « out ») ; FirewallError si
    # toutes sont refusées.
    func connect(host, port, timeout=null):
        last := null
        for a in _dns.lookup(host, port, 0, "tcp"):
            d := self.check("tcp", null, null, a.host, port, "out")
            if not d.allowed():
                last = d
                continue
            return _tcp.connect(a.host, port, timeout)
        reason := "aucune adresse"
        if last != null:
            reason = last.reason
        raise("FirewallError", "firewall : connexion vers " + str(host) + ":" + str(port) + " refusée (" + reason + ")")

    # Règles en texte (une par ligne), relisibles par load_rules.
    func export_rules():
        out := []
        for r in self.rules:
            append(out, r.str())
        return _s.join("\n", out)

    # Ajoute les règles d'un texte (une par ligne ; lignes vides et commentaires « # » ignorés).
    func load_rules(text):
        n := 0
        for line in _s.split(text, "\n"):
            t := _s.trim(line)
            if t == "" or _s.starts_with(t, "#"):
                continue
            self.add(t)
            n += 1
        return n

    func stats():
        per_rule := []
        for r in self.rules:
            append(per_rule, [r.str(), r.hits])
        return {"allowed": self.allowed_count, "denied": self.denied_count, "rules": per_rule, "blocked": len(keys(self.blocked))}

class GuardedListener:
    func init(listener, firewall):
        self.listener = listener
        self.socket = listener.socket         # socket sous-jacent (network.socket.wait)
        self.firewall = firewall
        self.dropped = 0

    func port():
        return self.listener.port()

    func address():
        return self.listener.address()

    # Prochaine connexion AUTORISÉE (les autres sont fermées sans réponse ; « reject » les ferme aussitôt).
    func accept(timeout=null):
        end := null
        if timeout != null:
            end = _time.monotonic() + timeout
        while true:
            left := null
            if end != null:
                left = end - _time.monotonic()
                if left <= 0:
                    raise("TimeoutError", "firewall : aucune connexion autorisée dans le délai")
            conn := self.listener.accept(left)
            peer := null
            local := null
            try:
                peer = conn.peer_address()
                local = conn.local_address()
            catch e:
                conn.close()
                continue
            d := self.firewall.check("tcp", peer[0], peer[1], local[0], local[1], "in")
            if d.allowed():
                return conn
            self.dropped += 1
            conn.close()

    func close():
        self.listener.close()

    func is_closed():
        return self.listener.is_closed()

# ALEX STANDARD LIBRARY — network.network_monitor
#
# Surveillance du réseau : joignabilité et latence (connexion TCP, requête HTTP, résolution DNS), statistiques
# de sondes (min / moyenne / max / gigue / pertes), connexions ouvertes de la machine et ports en écoute (Linux :
# /proc/net/tcp, tcp6, udp, udp6), débit des interfaces, et surveillant périodique avec détection des
# changements d'état.
#
#   tcp_ping("exemple.org", 443) -> secondes ou null      probe("exemple.org", 443, 5) -> ProbeStats
#   http_check("https://exemple.org/santé") -> dict (status, latency, ok, error)
#   dns_check("exemple.org") -> dict                       connections("tcp") -> list[Socket]
#   listening_ports() -> list de (protocole, adresse, port)
#   b := Bandwidth() ; ... ; b.sample() -> dict interface -> {rx_rate, tx_rate} (octets/s)
#   m := Monitor() ; m.add_tcp("api", "api.exemple.org", 443) ; m.add_http("site", url, 200)
#   m.on_change((cible, ancien, nouveau) => print(cible.name, nouveau)) ; m.run(60.0, 5.0)
#
# Pas d'ICMP (ping) : il exige des droits privilégiés ; la latence est mesurée par l'établissement d'une connexion
# TCP, ce qui reflète aussi la disponibilité du service.

from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string as _s
use io as _io
use os as _os
use time as _time
use network.tcp as _tcp
use network.dns as _dns
use network.ipaddress as _ip
use network.network_interface as _ni
use network.http_client as _hc

# ---------------------------------------------------------------- sondes

# Durée (secondes) d'établissement d'une connexion TCP à host:port, ou null si elle échoue dans le délai.
func tcp_ping(host, port, timeout=2.0):
    start := _time.monotonic()
    try:
        c := _tcp.connect(host, port, timeout)
        elapsed := _time.monotonic() - start
        c.close()
        return elapsed
    catch e:
        if e.type == "NetworkError" or e.type == "TimeoutError" or e.type == "DnsError":
            return null
        raise(e)

class ProbeStats:
    func init(samples, sent):
        self.samples = samples        # latences réussies (secondes)
        self.sent = sent
        self.received = len(samples)
        self.loss = 0.0
        if sent > 0:
            self.loss = 1.0 - self.received * 1.0 / sent
        self.min = null
        self.max = null
        self.avg = null
        self.jitter = null
        if self.received > 0:
            mn := samples[0]
            mx := samples[0]
            total := 0.0
            for x in samples:
                if x < mn:
                    mn = x
                if x > mx:
                    mx = x
                total += x
            self.min = mn
            self.max = mx
            self.avg = total / self.received
            if self.received > 1:
                d := 0.0
                i := 1
                while i < self.received:
                    diff := samples[i] - samples[i - 1]
                    if diff < 0:
                        diff = -diff
                    d += diff
                    i += 1
                self.jitter = d / (self.received - 1)
            else:
                self.jitter = 0.0

    func ok():
        return self.received > 0

    func str():
        if self.received == 0:
            return str(self.sent) + " essais, 100 % de pertes"
        return str(self.received) + "/" + str(self.sent) + " réponses, min " + _ms(self.min) + ", moy " + _ms(self.avg) + ", max " + _ms(self.max) + ", gigue " + _ms(self.jitter)

func _ms(x):
    v := to_int(x * 10000.0 + 0.5)
    return str(v // 10) + "." + str(v % 10) + " ms"

# `count` sondes TCP espacées de `interval` secondes.
func probe(host, port, count=4, interval=0.5, timeout=2.0):
    samples := []
    i := 0
    while i < count:
        r := tcp_ping(host, port, timeout)
        if r != null:
            append(samples, r)
        i += 1
        if i < count and interval > 0:
            _time.sleep(interval)
    return ProbeStats(samples, count)

# Contrôle HTTP : dict {ok, status, latency, error, url}. expected : statut attendu (null : tout statut < 400).
func http_check(url, expected=null, timeout=10.0, verify=true, ca_file=null):
    start := _time.monotonic()
    out := {"url": url, "ok": false, "status": null, "latency": null, "error": null}
    c := _hc.Client(null, null, timeout, verify, ca_file, null, false, true, 5)
    try:
        r := c.get(url)
        out["status"] = r.status
        out["latency"] = _time.monotonic() - start
        if expected == null:
            out["ok"] = r.status < 400
        else:
            out["ok"] = r.status == expected
    catch e:
        out["error"] = e.type + " : " + e.message
    c.close()
    return out

# Contrôle DNS : dict {ok, addresses, latency, error}.
func dns_check(name, family=0):
    start := _time.monotonic()
    out := {"name": name, "ok": false, "addresses": [], "latency": null, "error": null}
    try:
        out["addresses"] = _dns.resolve(name, family)
        out["latency"] = _time.monotonic() - start
        out["ok"] = len(out["addresses"]) > 0
    catch e:
        out["error"] = e.type + " : " + e.message
    return out

# ---------------------------------------------------------------- connexions de la machine

const TCP_STATES := ["", "ESTABLISHED", "SYN_SENT", "SYN_RECV", "FIN_WAIT1", "FIN_WAIT2", "TIME_WAIT", "CLOSE", "CLOSE_WAIT", "LAST_ACK", "LISTEN", "CLOSING", "NEW_SYN_RECV"]

class Socket:
    func init(protocol, local_address, local_port, remote_address, remote_port, state, uid, inode):
        self.protocol = protocol      # "tcp", "tcp6", "udp", "udp6"
        self.local_address = local_address
        self.local_port = local_port
        self.remote_address = remote_address
        self.remote_port = remote_port
        self.state = state            # « LISTEN », « ESTABLISHED »... (UDP : « UNCONN » ou « ESTABLISHED »)
        self.uid = uid
        self.inode = inode

    func str():
        return self.protocol + " " + _fmt(self.local_address, self.local_port) + " -> " + _fmt(self.remote_address, self.remote_port) + " " + self.state

func _fmt(a, p):
    if _s.contains(a, ":"):
        return "[" + a + "]:" + str(p)
    return a + ":" + str(p)

func _hexv(h):
    v := 0
    for c in _s.upper(h):
        v = v * 16 + _s.find("0123456789ABCDEF", str(c))
    return v

# Adresse de /proc/net/* : groupes de 32 bits en ordre de l'hôte (petit-boutiste sur x86 / ARM).
func _proc_addr(h):
    if len(h) == 8:
        v := _hexv(h)
        return str(v & 255) + "." + str((v >> 8) & 255) + "." + str((v >> 16) & 255) + "." + str((v >> 24) & 255)
    groups := []
    i := 0
    while i < 32:
        w := _s.substring(h, i, i + 8)
        # chaque mot de 32 bits est petit-boutiste : octets inversés
        b := _s.substring(w, 6, 8) + _s.substring(w, 4, 6) + _s.substring(w, 2, 4) + _s.substring(w, 0, 2)
        append(groups, _s.substring(b, 0, 4))
        append(groups, _s.substring(b, 4, 8))
        i += 8
    return _ip.ip_address(_s.join(":", groups)).str()

# Connexions de la machine : kind "tcp", "udp" ou "all" (IPv4 et IPv6). Liste vide hors Linux.
func connections(kind="tcp"):
    files := []
    if kind == "tcp" or kind == "all":
        files = files + [["tcp", "/proc/net/tcp"], ["tcp6", "/proc/net/tcp6"]]
    if kind == "udp" or kind == "all":
        files = files + [["udp", "/proc/net/udp"], ["udp6", "/proc/net/udp6"]]
    out := []
    for f in files:
        text := null
        try:
            if _os.exists(f[1]):
                text = _io.read_file(f[1])
        catch e:
            text = null
        if text == null:
            continue
        first := true
        for line in _s.split(text, "\n"):
            if first:
                first = false
                continue
            p := []
            for x in _s.split(line, " "):
                if x != "":
                    append(p, x)
            if len(p) < 10:
                continue
            la := _s.split(p[1], ":")
            ra := _s.split(p[2], ":")
            st := _hexv(p[3])
            state := ""
            if _s.starts_with(f[0], "tcp"):
                if st < len(TCP_STATES):
                    state = TCP_STATES[st]
            else:
                state = "UNCONN"
                if st == 1:
                    state = "ESTABLISHED"
            append(out, Socket(f[0], _proc_addr(la[0]), _hexv(la[1]), _proc_addr(ra[0]), _hexv(ra[1]), state, to_int(p[7]), to_int(p[9])))
    return out

# Ports en écoute : liste de (protocole, adresse, port), TCP en LISTEN et UDP liés.
func listening_ports():
    out := []
    for c in connections("all"):
        if c.state == "LISTEN" or (c.state == "UNCONN" and c.local_port != 0):
            append(out, (c.protocol, c.local_address, c.local_port))
    return out

# Vrai si un programme de la machine écoute sur ce port TCP.
func is_listening(port, protocol="tcp"):
    for x in listening_ports():
        if _s.starts_with(x[0], protocol) and x[2] == port:
            return true
    return false

# Nombre de connexions TCP par état (« ESTABLISHED » : 12...).
func tcp_state_counts():
    out := {}
    for c in connections("tcp"):
        if not contains_key(out, c.state):
            out[c.state] = 0
        out[c.state] = out[c.state] + 1
    return out

# ---------------------------------------------------------------- débit

class Bandwidth:
    func init():
        self.last = _ni.counters()
        self.last_time = _time.monotonic()

    # Débits depuis l'appel précédent : dict interface -> {rx_rate, tx_rate, rx_bytes, tx_bytes} (octets/s).
    func sample():
        now := _time.monotonic()
        cur := _ni.counters()
        dt := now - self.last_time
        if dt <= 0:
            dt = 0.000001
        out := {}
        for name in keys(cur):
            if contains_key(self.last, name):
                rx := cur[name]["rx_bytes"] - self.last[name]["rx_bytes"]
                tx := cur[name]["tx_bytes"] - self.last[name]["tx_bytes"]
                if rx < 0:
                    rx = 0
                if tx < 0:
                    tx = 0
                out[name] = {"rx_rate": rx / dt, "tx_rate": tx / dt, "rx_bytes": rx, "tx_bytes": tx}
        self.last = cur
        self.last_time = now
        return out

# ---------------------------------------------------------------- surveillant

class Target:
    func init(name, kind, params, interval):
        self.name = name
        self.kind = kind              # "tcp", "http", "dns" ou "custom"
        self.params = params
        self.interval = interval
        self.state = "unknown"        # "up", "down" ou "unknown"
        self.last_latency = null
        self.last_error = null
        self.last_check = null
        self.checks = 0
        self.failures = 0
        self.changed_at = null

    # Disponibilité observée (0..1).
    func availability():
        if self.checks == 0:
            return null
        return 1.0 - self.failures * 1.0 / self.checks

class Monitor:
    func init(clock=null):
        self.targets = []
        self.listeners = []
        self.events = []              # [horodatage, nom, ancien, nouveau]
        self.clock = clock

    func _now():
        if self.clock != null:
            return self.clock()
        return _time.monotonic()

    func add_tcp(name, host, port, interval=10.0, timeout=2.0):
        t := Target(name, "tcp", {"host": host, "port": port, "timeout": timeout}, interval)
        append(self.targets, t)
        return t

    func add_http(name, url, expected=null, interval=30.0, timeout=10.0):
        t := Target(name, "http", {"url": url, "expected": expected, "timeout": timeout}, interval)
        append(self.targets, t)
        return t

    func add_dns(name, host, interval=60.0):
        t := Target(name, "dns", {"host": host}, interval)
        append(self.targets, t)
        return t

    # Cible personnalisée : check() -> true / false (ou lève une erreur = échec).
    func add_check(name, check, interval=10.0):
        t := Target(name, "custom", {"check": check}, interval)
        append(self.targets, t)
        return t

    # fn(cible, ancien_état, nouvel_état) à chaque changement d'état.
    func on_change(fn):
        append(self.listeners, fn)

    func _run_check(t):
        start := _time.monotonic()
        ok := false
        err := null
        latency := null
        try:
            if t.kind == "tcp":
                latency = tcp_ping(t.params["host"], t.params["port"], t.params["timeout"])
                ok = latency != null
                if not ok:
                    err = "connexion impossible"
            elif t.kind == "http":
                r := http_check(t.params["url"], t.params["expected"], t.params["timeout"])
                ok = r["ok"]
                latency = r["latency"]
                err = r["error"]
                if err == null and not ok:
                    err = "statut " + str(r["status"])
            elif t.kind == "dns":
                r := dns_check(t.params["host"])
                ok = r["ok"]
                latency = r["latency"]
                err = r["error"]
            else:
                ok = t.params["check"]() == true
                latency = _time.monotonic() - start
        catch e:
            ok = false
            err = e.type + " : " + e.message
        t.checks += 1
        if not ok:
            t.failures += 1
        t.last_latency = latency
        t.last_error = err
        t.last_check = self._now()
        new_state := "down"
        if ok:
            new_state = "up"
        if new_state != t.state:
            old := t.state
            t.state = new_state
            t.changed_at = t.last_check
            append(self.events, [t.last_check, t.name, old, new_state])
            for fn in self.listeners:
                fn(t, old, new_state)
        return ok

    # Vérifie toutes les cibles une fois ; rend dict nom -> état.
    func check_all():
        out := {}
        for t in self.targets:
            self._run_check(t)
            out[t.name] = t.state
        return out

    # Vérifie les cibles dont l'intervalle est écoulé.
    func check_due():
        now := self._now()
        n := 0
        for t in self.targets:
            if t.last_check == null or now - t.last_check >= t.interval:
                self._run_check(t)
                n += 1
        return n

    # Boucle de surveillance pendant `duration` secondes (null : sans fin), un tour toutes les `tick` secondes.
    func run(duration=null, tick=1.0):
        end := null
        if duration != null:
            end = _time.monotonic() + duration
        while end == null or _time.monotonic() < end:
            self.check_due()
            _time.sleep(tick)

    # Résumé : dict nom -> {state, latency, availability, error}.
    func summary():
        out := {}
        for t in self.targets:
            out[t.name] = {"state": t.state, "latency": t.last_latency, "availability": t.availability(), "error": t.last_error}
        return out

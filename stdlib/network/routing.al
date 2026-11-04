# ALEX STANDARD LIBRARY — network.routing
#
# Tables de routage : lecture de la table du système (Linux : /proc/net/route et /proc/net/ipv6_route), passerelle
# par défaut, choix de la route d'une destination (préfixe le plus long, puis métrique la plus faible), et table de
# routage logicielle (RoutingTable) pour vos propres décisions d'aiguillage (mandataires, VPN, tests).
#
#   routes(4) -> list[Route]           default_route(4) / default_gateway(4) -> passerelle (texte) ou null
#   lookup("8.8.8.8") -> Route         route système qu'emprunterait un paquet vers cette adresse
#   t := RoutingTable() ; t.add("10.0.0.0/8", "10.0.0.1", "vpn0", 10) ; t.lookup("10.1.2.3")
#
# Hors Linux, la table du système est vide (routes() rend []) : RoutingTable fonctionne partout.
#
# Exemple
#   use network.routing as rt
#   r := rt.lookup("1.1.1.1")
#   print(r.destination.str(), r.gateway, r.iface)       # 0.0.0.0/0 192.168.1.1 eth0

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use io as _io
use os as _os
use network.ipaddress as _ip

const RTF_UP := 1
const RTF_GATEWAY := 2
const RTF_HOST := 4
const RTF_REJECT := 512

class Route:
    func init(destination, gateway=null, iface=null, metric=0, flags=0, source="static"):
        self.destination = _ip.ip_network(destination, false)
        self.gateway = gateway            # adresse de la passerelle (texte), ou null (réseau directement relié)
        self.iface = iface
        self.metric = metric
        self.flags = flags
        self.source = source              # "kernel" (table du système) ou "static"

    func family():
        return self.destination.version

    func is_default():
        return self.destination.prefixlen == 0

    func is_direct():
        return self.gateway == null

    func matches(address):
        return self.destination.contains(address)

    func str():
        out := self.destination.str()
        if self.gateway != null:
            out += " via " + self.gateway
        if self.iface != null:
            out += " dev " + self.iface
        out += " metric " + str(self.metric)
        return out

func _hex_le32(h):
    # adresse IPv4 de /proc/net/route : 8 chiffres hexadécimaux, petit-boutiste
    v := 0
    i := 0
    while i < 8:
        v = v * 16 + _s.find("0123456789ABCDEF", _s.upper(str(h[i])))
        i += 1
    b0 := v & 255
    b1 := (v >> 8) & 255
    b2 := (v >> 16) & 255
    b3 := (v >> 24) & 255
    return str(b0) + "." + str(b1) + "." + str(b2) + "." + str(b3)

func _hex_to_v6(h):
    parts := []
    i := 0
    while i < 32:
        append(parts, _s.substring(h, i, i + 4))
        i += 4
    return _ip.ip_address(_s.join(":", parts)).str()

func _hexint(h):
    v := 0
    for c in _s.upper(h):
        v = v * 16 + _s.find("0123456789ABCDEF", str(c))
    return v

func _read(path):
    try:
        if _os.exists(path):
            return _io.read_file(path)
    catch e:
        return null
    return null

# Routes du système (family 0 : toutes, 4 ou 6), triées par préfixe décroissant puis métrique.
func routes(family=0):
    out := []
    if family == 0 or family == 4:
        text := _read("/proc/net/route")
        if text != null:
            first := true
            for line in _s.split(text, "\n"):
                if first:
                    first = false
                    continue
                f := []
                for p in _s.split(_s.replace(line, "\t", " "), " "):
                    if p != "":
                        append(f, p)
                if len(f) < 8:
                    continue
                flags := _hexint(f[3])
                if (flags & RTF_UP) == 0:
                    continue
                dest := _hex_le32(f[1])
                mask := _hex_le32(f[7])
                gw := null
                if (flags & RTF_GATEWAY) != 0:
                    gw = _hex_le32(f[2])
                try:
                    append(out, Route(dest + "/" + mask, gw, f[0], to_int(f[6]), flags, "kernel"))
                catch e:
                    ignored := e
    if family == 0 or family == 6:
        text := _read("/proc/net/ipv6_route")
        if text != null:
            for line in _s.split(text, "\n"):
                f := []
                for p in _s.split(line, " "):
                    if p != "":
                        append(f, p)
                if len(f) < 10:
                    continue
                flags := _hexint(f[8])
                if (flags & RTF_UP) == 0 or (flags & RTF_REJECT) != 0:
                    continue
                dest := _hex_to_v6(f[0])
                plen := _hexint(f[1])
                gw := _hex_to_v6(f[4])
                if gw == "::":
                    gw = null
                try:
                    append(out, Route(dest + "/" + str(plen), gw, f[9], _hexint(f[5]), flags, "kernel"))
                catch e:
                    ignored := e
    return _sorted(out)

func _better(a, b):
    # vrai si a doit passer avant b
    if a.destination.prefixlen != b.destination.prefixlen:
        return a.destination.prefixlen > b.destination.prefixlen
    return a.metric < b.metric

func _sorted(rs):
    out := []
    for r in rs:
        append(out, r)
    i := 1
    while i < len(out):
        x := out[i]
        j := i - 1
        while j >= 0 and _better(x, out[j]):
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = x
        i += 1
    return out

# Meilleure route (préfixe le plus long, puis métrique) d'une liste pour une adresse, ou null.
func best_route(route_list, address):
    a := _ip.ip_address(address)
    best := null
    for r in route_list:
        if r.destination.version != a.version or not r.destination.contains(a):
            continue
        if best == null or _better(r, best):
            best = r
    return best

# Route système vers une adresse, ou null.
func lookup(address):
    a := _ip.ip_address(address)
    return best_route(routes(a.version), a)

func default_route(family=4):
    best := null
    for r in routes(family):
        if r.is_default() and (best == null or r.metric < best.metric):
            best = r
    return best

# Passerelle par défaut (texte), ou null.
func default_gateway(family=4):
    r := default_route(family)
    if r == null:
        return null
    return r.gateway

# Table de routage logicielle.
class RoutingTable:
    func init(entries=null):
        self.entries = []
        if entries != null:
            for r in entries:
                append(self.entries, r)

    func add(destination, gateway=null, iface=null, metric=0):
        r := Route(destination, gateway, iface, metric)
        append(self.entries, r)
        return r

    # Retire les routes vers `destination` (toutes, ou celle de cette passerelle).
    func remove(destination, gateway=null):
        d := _ip.ip_network(destination, false)
        kept := []
        n := 0
        for r in self.entries:
            if r.destination == d and (gateway == null or r.gateway == gateway):
                n += 1
            else:
                append(kept, r)
        self.entries = kept
        return n

    func lookup(address):
        return best_route(self.entries, address)

    # Prochain saut vers une adresse : passerelle, ou l'adresse elle-même pour un réseau directement relié ; null
    # sans route.
    func next_hop(address):
        r := self.lookup(address)
        if r == null:
            return null
        if r.gateway == null:
            return _ip.ip_address(address).str()
        return r.gateway

    func routes():
        return _sorted(self.entries)

    func clear():
        self.entries = []

    func __len__():
        return len(self.entries)

    func str():
        out := []
        for r in self.routes():
            append(out, r.str())
        return _s.join("\n", out)

# Table logicielle remplie avec les routes du système.
func system_table():
    return RoutingTable(routes(0))

# ALEX STANDARD LIBRARY — network.network_interface
#
# Interfaces réseau de la machine : noms, état (up, running, loopback, multicast...), adresses IPv4 / IPv6 avec
# masque et réseau, adresse matérielle (MAC), MTU, débit annoncé, compteurs de trafic.
#
#   interfaces() -> list[Interface]          get("eth0")          names()
#   addresses(4) -> adresses IPv4 de la machine (hors boucle locale par défaut)
#   interface_for("192.168.1.20") -> Interface dont un réseau contient cette adresse
#   default_interface() -> interface de la route par défaut       counters() -> compteurs de /proc/net/dev
#
# Sources : getifaddrs (adresses, drapeaux) ; sous Linux, /sys/class/net (MAC, MTU, débit) et /proc/net/dev
# (compteurs). Ailleurs, ces champs valent null.
#
# Exemple
#   use network.network_interface as ni
#   for i in ni.interfaces():
#       print(i.name, i.is_up(), i.mac, i.mtu, [a.str() for a in i.addresses])

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use io as _io
use os as _os
use network.ipaddress as _ip
use network.socket as _sk
use network.routing as _routing

class InterfaceAddress:
    func init(family, address, netmask, broadcast):
        self.family = family          # 4 ou 6
        self.address = address        # texte (zone IPv6 « %eth0 » éventuelle)
        self.netmask = netmask
        self.broadcast = broadcast
        self.prefixlen = null
        self.network = null           # network.ipaddress.IPNetwork
        if netmask != null:
            try:
                self.prefixlen = _ip.netmask_to_prefix(netmask)
                base := address
                k := _s.find(base, "%")
                if k >= 0:
                    base = _s.substring(base, 0, k)
                self.network = _ip.ip_network(base + "/" + str(self.prefixlen), false)
            catch e:
                self.prefixlen = null

    # « adresse/préfixe ».
    func str():
        if self.prefixlen == null:
            return self.address
        return self.address + "/" + str(self.prefixlen)

    func ip():
        a := self.address
        k := _s.find(a, "%")
        if k >= 0:
            a = _s.substring(a, 0, k)
        return _ip.ip_address(a)

class Interface:
    func init(name, index):
        self.name = name
        self.index = index
        self.flags = []
        self.addresses = []           # list[InterfaceAddress]
        self.mac = null               # « aa:bb:cc:dd:ee:ff »
        self.mtu = null
        self.speed = null             # Mbit/s annoncés par le pilote, ou null
        self.kind = null              # type ARP Linux (1 = Ethernet, 772 = boucle locale...), ou null

    func has_flag(f):
        for x in self.flags:
            if x == f:
                return true
        return false

    func is_up():
        return self.has_flag("up")

    func is_running():
        return self.has_flag("running")

    func is_loopback():
        return self.has_flag("loopback")

    func supports_multicast():
        return self.has_flag("multicast")

    func supports_broadcast():
        return self.has_flag("broadcast")

    func ipv4():
        out := []
        for a in self.addresses:
            if a.family == 4:
                append(out, a)
        return out

    func ipv6():
        out := []
        for a in self.addresses:
            if a.family == 6:
                append(out, a)
        return out

    # Compteurs de trafic (octets, paquets, erreurs...), ou null.
    func counters():
        c := counters()
        if contains_key(c, self.name):
            return c[self.name]
        return null

    func str():
        return self.name

func _read(path):
    try:
        if _os.exists(path):
            return _s.trim(_io.read_file(path))
    catch e:
        return null
    return null

# Toutes les interfaces (une entrée par nom, adresses regroupées).
func interfaces():
    if not _sk.supported():
        raise("IoError", "network_interface : réseau non pris en charge sur cette plateforme")
    raw := _n.interfaces()
    if type(raw) == "int":
        _sk.fail("getifaddrs", raw)
    by_name := {}
    order := []
    for e in raw:
        name := e[0]
        if not contains_key(by_name, name):
            by_name[name] = Interface(name, e[6])
            append(order, name)
        itf := by_name[name]
        for f in e[5]:
            if not itf.has_flag(f):
                append(itf.flags, f)
        if e[1] == 4 or e[1] == 6:
            addr := e[2]
            if e[1] == 6 and _s.starts_with(_s.lower(addr), "fe80:") and not _s.contains(addr, "%"):
                addr = addr + "%" + name
            append(itf.addresses, InterfaceAddress(e[1], addr, e[3], e[4]))
    out := []
    for name in order:
        itf := by_name[name]
        base := "/sys/class/net/" + name + "/"
        mac := _read(base + "address")
        if mac != null and mac != "" and mac != "00:00:00:00:00:00":
            itf.mac = mac
        mtu := _read(base + "mtu")
        if mtu != null and mtu != "":
            itf.mtu = to_int(mtu)
        sp := _read(base + "speed")
        if sp != null and sp != "" and not _s.starts_with(sp, "-"):
            itf.speed = to_int(sp)
        t := _read(base + "type")
        if t != null and t != "":
            itf.kind = to_int(t)
        append(out, itf)
    return out

func names():
    out := []
    for i in interfaces():
        append(out, i.name)
    return out

# Interface nommée, ou null.
func get(name):
    for i in interfaces():
        if i.name == name:
            return i
    return null

func loopback():
    for i in interfaces():
        if i.is_loopback():
            return i
    return null

# Adresses IP de la machine (texte) ; family 0 : toutes ; include_loopback / include_link_local : à inclure.
func addresses(family=0, include_loopback=false, include_link_local=false):
    out := []
    for i in interfaces():
        if i.is_loopback() and not include_loopback:
            continue
        for a in i.addresses:
            if family != 0 and a.family != family:
                continue
            ip := a.ip()
            if ip.is_link_local() and not include_link_local:
                continue
            if ip.is_loopback() and not include_loopback:
                continue
            append(out, a.address)
    return out

# Interface dont un réseau contient l'adresse donnée, ou null.
func interface_for(address):
    target := _ip.ip_address(address)
    for i in interfaces():
        for a in i.addresses:
            if a.network != null and a.network.contains(target):
                return i
    return null

# Interface de la route par défaut (IPv4, sinon IPv6), ou null.
func default_interface():
    name := _default_route_interface()
    if name == null:
        return null
    return get(name)

func _default_route_interface():
    for fam in [4, 6]:
        r := _routing.default_route(fam)
        if r != null:
            return r.iface
    return null

# Compteurs de /proc/net/dev : dict nom -> {rx_bytes, rx_packets, rx_errors, rx_dropped, tx_bytes, tx_packets,
# tx_errors, tx_dropped} ; {} si indisponible.
func counters():
    out := {}
    text := _read("/proc/net/dev")
    if text == null:
        return out
    for line in _s.split(text, "\n"):
        c := _s.find(line, ":")
        if c < 0 or _s.contains(line, "|"):
            continue
        name := _s.trim(_s.substring(line, 0, c))
        nums := []
        for p in _s.split(_s.substring(line, c + 1, len(line)), " "):
            if p != "":
                append(nums, to_int(p))
        if len(nums) < 16:
            continue
        out[name] = {"rx_bytes": nums[0], "rx_packets": nums[1], "rx_errors": nums[2], "rx_dropped": nums[3], "tx_bytes": nums[8], "tx_packets": nums[9], "tx_errors": nums[10], "tx_dropped": nums[11]}
    return out

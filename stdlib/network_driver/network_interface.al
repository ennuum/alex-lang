# alex: native
# ALEX STANDARD LIBRARY — network_driver.network_interface
#
# Table des interfaces et routage IPv4 au-dessus des pilotes (NetworkDevice) :
#   - Iface : nom (eth0, lo...), périphérique, état administratif (up / down) et lien, MTU (bornée par la
#     carte), adresses IPv4 avec longueur de préfixe, adresse MAC ;
#   - InterfaceTable : ajout avec nommage automatique (eth0, eth1...), recherche par nom / adresse ;
#   - routes : réseau / préfixe, passerelle (0 : directement joignable), interface, métrique ; une route
#     « connectée » est ajoutée avec chaque adresse ; lookup : plus long préfixe puis plus petite métrique ;
#   - describe : texte façon « ip addr » et « ip route ».
#
#   use network_driver.network_interface as ni
#   t := ni.InterfaceTable()
#   eth0 := t.add(carte, "eth")                      # nom « eth0 »
#   eth0.add_address(np.ip("10.0.2.15"), 24)
#   eth0.set_up(true)
#   t.add_route(0, 0, np.ip("10.0.2.2"), "eth0", 100)   # route par défaut
#   r := t.lookup(np.ip("8.8.8.8"))                  # Route via 10.0.2.2 dev eth0
#
# Erreurs : NetworkDriverError (nom en double, interface inconnue, MTU invalide, préfixe invalide),
# LinkDown (aucune route utilisable). Compilable en natif.

from core use len
from collections use append
use network_driver.ethernet as eth
use network_driver.network_packet as np
use network_driver.network_device as nd
from network_driver.network_device use NetworkDevice

func mask(prefix: int) -> int:
    if prefix <= 0:
        return 0
    return (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF

func network_of(ip: int, prefix: int) -> int:
    return ip & mask(prefix)

class IfAddress:
    ip: int := 0
    prefix: int := 24

    func init(ip: int, prefix: int):
        self.ip = ip
        self.prefix = prefix

    func broadcast() -> int:
        return network_of(self.ip, self.prefix) | (~mask(self.prefix) & 0xFFFFFFFF)

    func contains(ip: int) -> bool:
        return network_of(ip, self.prefix) == network_of(self.ip, self.prefix)

    func describe() -> str:
        return np.ip_text(self.ip) + "/" + str(self.prefix)

class Iface:
    name: str := ""
    dev: NetworkDevice
    up: bool := false
    mtu_value: int := 1500
    addresses: list[IfAddress] := []
    index: int := 0

    func init(name: str, dev: NetworkDevice, index: int):
        self.name = name
        self.dev = dev
        self.up = false
        self.mtu_value = dev.mtu()
        if self.mtu_value > 9000 and name != "lo":
            self.mtu_value = 1500
        self.addresses = []
        self.index = index

    func mac() -> int:
        return self.dev.mac()

    func running() -> bool:
        return self.up and self.dev.link_up()

    func set_up(on: bool):
        self.up = on

    func mtu() -> int:
        return self.mtu_value

    func set_mtu(m: int):
        if m < 68 or m > self.dev.mtu():
            raise("NetworkDriverError", self.name + " : MTU " + str(m) + " hors de 68.." + str(self.dev.mtu()))
        self.mtu_value = m

    func add_address(ip: int, prefix: int) -> IfAddress:
        if prefix < 0 or prefix > 32:
            raise("NetworkDriverError", self.name + " : préfixe /" + str(prefix) + " invalide")
        for a in self.addresses:
            if a.ip == ip:
                return a
        a := IfAddress(ip, prefix)
        append(self.addresses, a)
        return a

    func remove_address(ip: int) -> bool:
        keep: list[IfAddress] := []
        found := false
        for a in self.addresses:
            if a.ip == ip:
                found = true
            else:
                append(keep, a)
        self.addresses = keep
        return found

    func has_address(ip: int) -> bool:
        for a in self.addresses:
            if a.ip == ip:
                return true
        return false

    func primary() -> int:
        if len(self.addresses) == 0:
            return 0
        return self.addresses[0].ip

    func describe() -> str:
        st := "UP" if self.up else "DOWN"
        if self.up and not self.dev.link_up():
            st = st + ",NO-CARRIER"
        elif self.up:
            st = st + ",LOWER_UP"
        t := str(self.index) + ": " + self.name + ": <" + st + "> mtu " + str(self.mtu_value) + "\n    link/ether " + eth.mac_text(self.dev.mac())
        for a in self.addresses:
            t = t + "\n    inet " + a.describe() + " brd " + np.ip_text(a.broadcast())
        return t

class Route:
    dest: int := 0
    prefix: int := 0
    gateway: int := 0
    iface: str := ""
    metric: int := 0
    connected: bool := false

    func init(dest: int, prefix: int, gateway: int, iface: str, metric: int):
        self.dest = network_of(dest, prefix)
        self.prefix = prefix
        self.gateway = gateway
        self.iface = iface
        self.metric = metric
        self.connected = false

    func matches(ip: int) -> bool:
        return network_of(ip, self.prefix) == self.dest

    # Adresse à résoudre (ARP) pour joindre ip par cette route.
    func next_hop(ip: int) -> int:
        if self.gateway == 0:
            return ip
        return self.gateway

    func describe() -> str:
        t := "default" if self.prefix == 0 else np.ip_text(self.dest) + "/" + str(self.prefix)
        if self.gateway != 0:
            t = t + " via " + np.ip_text(self.gateway)
        t = t + " dev " + self.iface
        if self.connected:
            t = t + " scope link"
        if self.metric != 0:
            t = t + " metric " + str(self.metric)
        return t

class InterfaceTable:
    ifaces: list[Iface] := []
    routes: list[Route] := []
    counter: int := 0

    func init():
        self.ifaces = []
        self.routes = []
        self.counter = 0

    func _taken(name: str) -> bool:
        for i in self.ifaces:
            if i.name == name:
                return true
        return false

    # prefix « eth » : premier nom libre eth0, eth1... ; un nom complet (« lo ») est pris tel quel.
    func add(dev: NetworkDevice, prefix: str) -> Iface:
        name := prefix
        if prefix != "lo":
            k := 0
            while self._taken(prefix + str(k)):
                k += 1
            name = prefix + str(k)
        elif self._taken(name):
            raise("NetworkDriverError", "interface « " + name + " » déjà présente")
        self.counter += 1
        i := Iface(name, dev, self.counter)
        append(self.ifaces, i)
        return i

    func get(name: str) -> Iface:
        for i in self.ifaces:
            if i.name == name:
                return i
        raise("NetworkDriverError", "interface « " + name + " » inconnue")

    func by_address(ip: int) -> Iface?:
        for i in self.ifaces:
            if i.has_address(ip):
                return i
        return null

    func remove(name: str):
        keep: list[Iface] := []
        for i in self.ifaces:
            if i.name != name:
                append(keep, i)
        self.ifaces = keep
        kr: list[Route] := []
        for r in self.routes:
            if r.iface != name:
                append(kr, r)
        self.routes = kr

    # Adresse + route connectée vers son réseau.
    func assign(name: str, ip: int, prefix: int) -> IfAddress:
        i := self.get(name)
        a := i.add_address(ip, prefix)
        exists := false
        for r in self.routes:
            if r.connected and r.iface == name and r.dest == network_of(ip, prefix) and r.prefix == prefix:
                exists = true
        if not exists:
            r := Route(ip, prefix, 0, name, 0)
            r.connected = true
            append(self.routes, r)
        return a

    func add_route(dest: int, prefix: int, gateway: int, iface: str, metric: int) -> Route:
        self.get(iface)
        if prefix < 0 or prefix > 32:
            raise("NetworkDriverError", "route : préfixe /" + str(prefix) + " invalide")
        r := Route(dest, prefix, gateway, iface, metric)
        append(self.routes, r)
        return r

    func remove_route(dest: int, prefix: int) -> int:
        keep: list[Route] := []
        n := 0
        for r in self.routes:
            if r.dest == network_of(dest, prefix) and r.prefix == prefix:
                n += 1
            else:
                append(keep, r)
        self.routes = keep
        return n

    # Meilleure route vers ip parmi celles dont l'interface est en marche ; LinkDown sinon.
    func lookup(ip: int) -> Route:
        best: Route? := null
        for r in self.routes:
            if r.matches(ip):
                i := self.get(r.iface)
                if i.running():
                    if best == null:
                        best = r
                    else:
                        b := best
                        if b != null:
                            if r.prefix > b.prefix or (r.prefix == b.prefix and r.metric < b.metric):
                                best = r
        if best == null:
            raise("LinkDown", "aucune route vers " + np.ip_text(ip))
        res := best
        if res != null:
            return res
        raise("LinkDown", "aucune route vers " + np.ip_text(ip))

    func describe() -> str:
        t := ""
        for i in self.ifaces:
            t = t + i.describe() + "\n"
        t = t + "routes :\n"
        for r in self.routes:
            t = t + "  " + r.describe() + "\n"
        return t

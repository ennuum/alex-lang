# ALEX STANDARD LIBRARY — network.udp
#
# Datagrammes UDP (IPv4 et IPv6) : envoi, réception, diffusion (broadcast).
#
# Un datagramme arrive entier ou pas du tout ; l'ordre et la livraison ne sont pas garantis (propriété d'UDP).
#
# Erreurs : NetworkError, TimeoutError, DnsError, voir network.socket.
#
# Exemple
#   use network.udp as udp
#   rx := udp.bind("127.0.0.1", 0)
#   udp.send("bonjour", "127.0.0.1", rx.port())
#   d := rx.receive(2.0)
#   print(d.text(), d.host, d.port)

from core use len, type
use _native_net as _n
use network.socket as _sk
use network.dns as _dns

class Datagram:
    func init(data, host, port):
        self.data = data    # octets bruts (str)
        self.host = host    # adresse de l'expéditeur
        self.port = port

    func text():
        return self.data

    func bytes():
        return _n.to_bytes(self.data)

    func size():
        return _n.blen(self.data)

class Endpoint:
    func init(sock):
        self.socket = sock

    func _target(host):
        if _dns.is_ip(host):
            return host
        return _dns.resolve_one(host, self.socket.family)

    # Envoie data (str ou list[int]) à host:port ; renvoie le nombre d'octets envoyés.
    func send_to(data, host, port):
        return self.socket.send_to(data, self._target(host), port)

    # Prochain datagramme reçu (au plus max octets) ; TimeoutError après timeout secondes.
    func receive(timeout=null, max=65536):
        r := self.socket.recv_from(max, timeout)
        return Datagram(r[0], r[1], r[2])

    # Comme receive sans attendre : null si aucun datagramme n'est arrivé.
    func try_receive(max=65536):
        try:
            return self.receive(0, max)
        catch e:
            if e.type == "TimeoutError":
                return null
            raise(e)

    func port():
        return self.socket.local_address()[1]

    func address():
        return self.socket.local_address()

    # Autorise l'envoi vers une adresse de diffusion (255.255.255.255, x.x.x.255...).
    func set_broadcast(on=true):
        self.socket.set_option("broadcast", on)

    func set_timeout(t):
        self.socket.set_timeout(t)

    func close():
        self.socket.close()

    func is_closed():
        return self.socket.is_closed()

func _family_of(host):
    if host == "" or _dns.is_ipv4(host):
        return 4
    if _dns.is_ipv6(host):
        return 6
    return _dns.lookup(host, null, 0, "udp")[0].family

# Point d'échange UDP attaché à host:port ("" : toutes les interfaces IPv4 ; port 0 : choisi par le système).
func bind(host="127.0.0.1", port=0, reuse_address=false):
    family := _family_of(host)
    addr := host
    if host != "" and not _dns.is_ip(host):
        addr = _dns.resolve_one(host, family)
    s := _sk.Socket(family, "udp")
    try:
        if reuse_address:
            s.set_option("reuse_address", true)
        s.bind(addr, port)
    catch e:
        s.close()
        raise(e)
    return Endpoint(s)

# Point d'échange non attaché (le système choisit l'adresse locale au premier envoi).
func open(family=4):
    return Endpoint(_sk.Socket(family, "udp"))

# Envoie un seul datagramme à host:port.
func send(data, host, port):
    family := _family_of(host)
    e := open(family)
    n := 0
    try:
        n = e.send_to(data, host, port)
    catch err:
        e.close()
        raise(err)
    e.close()
    return n

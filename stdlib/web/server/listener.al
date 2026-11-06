# ALEX STANDARD LIBRARY — web.server.listener
#
# Listener : la socket d'écoute du serveur (TCP, IPv4 ou IPv6), avec acceptation NON BLOQUANTE pour la boucle
# d'événements, et l'adresse réellement liée (port 0 : choisi par le système).
#
#   use web.server.listener as ls
#   l := ls.Listener("127.0.0.1", 0)
#   l.port()                      # port attribué
#   l.url("http")                 # http://127.0.0.1:43817/
#   r := l.try_accept()           # (socket, (hôte, port)) ou null si personne n'attend
#   l.close()
#
# host : "" ou "0.0.0.0" toutes les interfaces IPv4, "::" IPv6, un nom (résolu), une adresse.
# Erreurs : ServerConfigError (adresse invalide, port occupé), NetworkError.

from core use len, type
use network.tcp as _tcp
use network.socket as _sk
use network.dns as _dns
use web.server.server_errors as _err

class Listener:
    # reuse_port : SO_REUSEPORT, pour que plusieurs processus écoutent le même port (le noyau répartit les
    # connexions entre eux ; voir web.server.workers).
    func init(host="127.0.0.1", port=8080, backlog=128, reuse_address=true, reuse_port=false):
        if type(port) != "int" or port < 0 or port > 65535:
            _err.config_error("Listener", "port entre 0 et 65535 attendu (obtenu " + str(port) + ")")
        self.host = host
        try:
            if reuse_port:
                self.tcp = _listen_shared(host, port, backlog)
            else:
                self.tcp = _tcp.listen(host, port, backlog, reuse_address)
        catch e:
            _err.config_error("Listener", "impossible d'écouter sur " + _sk.format_address(host if host != "" else "0.0.0.0", port) + " : " + str(e.message))
        self.socket = self.tcp.socket
        self.accepted = 0
        self.closed = false

    func port():
        return self.tcp.port()

    func address():
        return self.tcp.address()

    # URL d'accès (hôte joignable : 127.0.0.1 pour une écoute sur toutes les interfaces).
    func url(scheme="http", path="/"):
        a := self.address()
        h := a[0]
        if h == "0.0.0.0" or h == "":
            h = "127.0.0.1"
        elif h == "::":
            h = "::1"
        return scheme + "://" + _sk.format_address(h, a[1]) + path

    # Connexion en attente : (socket, (hôte, port)), ou null s'il n'y en a pas.
    func try_accept():
        try:
            r := self.socket.accept(0)
            self.accepted += 1
            return (r[0], (r[1], r[2]))
        catch e:
            if e.type == "TimeoutError":
                return null
            if e.type == "NetworkError":
                return null
            raise(e)

    # Attente bloquante d'une connexion (timeout : secondes, null : sans limite).
    func accept(timeout=null):
        r := self.socket.accept(timeout)
        self.accepted += 1
        return (r[0], (r[1], r[2]))

    func close():
        if not self.closed:
            self.closed = true
            self.tcp.close()

    func is_closed():
        return self.closed

# Comme network.tcp.listen, avec SO_REUSEADDR et SO_REUSEPORT posés avant bind.
func _listen_shared(host, port, backlog):
    family := 4
    addr := host
    if host != "" and not _dns.is_ipv4(host):
        if _dns.is_ipv6(host):
            family = 6
        else:
            a := _dns.lookup(host, port, 0, "tcp")[0]
            family = a.family
            addr = a.host
    s := _sk.Socket(family, "tcp")
    try:
        s.set_option("reuse_address", true)
        s.set_option("reuse_port", true)
        s.bind(addr, port)
        s.listen(backlog)
    catch e:
        s.close()
        raise(e)
    return _tcp.Listener(s)

func listen(host="127.0.0.1", port=8080, backlog=128):
    return Listener(host, port, backlog)

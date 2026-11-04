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
use web.server.server_errors as _err

class Listener:
    func init(host="127.0.0.1", port=8080, backlog=128, reuse_address=true):
        if type(port) != "int" or port < 0 or port > 65535:
            _err.config_error("Listener", "port entre 0 et 65535 attendu (obtenu " + str(port) + ")")
        self.host = host
        try:
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

func listen(host="127.0.0.1", port=8080, backlog=128):
    return Listener(host, port, backlog)

# ALEX STANDARD LIBRARY — network.socket
#
# Sockets BSD (TCP et UDP, IPv4 et IPv6) : la couche basse de network.tcp, network.udp et network.http.
#
# Architecture
#   socket.al     API publique ALEX : classe Socket, attente sur plusieurs sockets (wait), erreurs.
#   _native_net   primitives système (runtime/alex/native/dyn_nat.al) : table de handles, sockets toujours non bloquants,
#                 délais par poll(). POSIX ; ailleurs, supported() vaut false et tout lève IoError.
#
# Données
#   - send / recv transportent des `str` : leurs octets partent et arrivent tels quels (texte UTF-8 ou binaire).
#   - send_bytes / recv_bytes transportent des `list[int]` d'octets 0..255 (comme io.read_bytes).
#   - Les tailles (max, valeurs renvoyées par send) sont en OCTETS.
#
# Délais
#   timeout = null : attendre sans limite ; nombre >= 0 : au plus ce nombre de secondes (0 : ne pas attendre).
#   Chaque méthode prend un délai ; à défaut, celui du socket (set_timeout, null au départ).
#
# Erreurs
#   NetworkError   l'opération réseau échoue (connexion refusée, réinitialisée, hôte injoignable, adresse
#                  occupée...) ; le message se termine par le nom de l'erreur système : « [ECONNREFUSED] ».
#   TimeoutError   délai dépassé (ou, avec un délai nul, opération qui bloquerait).
#   IoError        réseau non pris en charge sur la plateforme.
#   TypeError / ArgumentError   argument d'un mauvais type ou invalide (handle fermé, port hors limites...).
#
# Exemple
#   use network.socket as sk
#   s := sk.Socket(4, "tcp")
#   s.connect("127.0.0.1", 8080, 2.0)
#   s.send("ping\n")
#   print(s.recv(1024, 2.0))
#   s.close()

from core use len, type
from collections use append
use _native_net as _n

const TCP := "tcp"
const UDP := "udp"
const IPV4 := 4
const IPV6 := 6
const UNIX := 1   # socket local (chemin du système de fichiers, ou nom abstrait « @nom » sous Linux) : voir ipc.local_socket

func supported():
    return _n.supported()

func _require():
    if not _n.supported():
        raise("IoError", "network : non pris en charge sur cette plateforme")

# « hôte:port », ou « [hôte]:port » pour une adresse IPv6.
func format_address(host, port):
    if port == 0 and len(host) > 0 and (host[0] == '/' or host[0] == '@' or host[0] == '.'):
        return host
    for c in host:
        if c == ':':
            return "[" + host + "]:" + str(port)
    return host + ":" + str(port)

# Traduit le code -errno d'une primitive en erreur ALEX.
func fail(operation, code):
    name := _n.errno_name(code)
    if name == "ETIMEDOUT":
        raise("TimeoutError", operation + " : délai dépassé [ETIMEDOUT]")
    if name == "EAGAIN":
        raise("TimeoutError", operation + " : rien de prêt sans attendre [EAGAIN]")
    raise("NetworkError", operation + " : " + _n.strerror(code) + " [" + name + "]")

# Vrai si r (résultat d'une primitive) est un code d'erreur.
func is_error(r):
    return type(r) == "int" and r < 0

func _check_family(fn, family):
    if family != 4 and family != 6 and family != 1:
        raise("ArgumentError", "network.socket." + fn + " : famille 4, 6 ou 1 (UNIX, local) attendue (obtenu " + str(family) + ")")

func _check_timeout(fn, t):
    if t == null:
        return
    if type(t) != "int" and type(t) != "float":
        raise("TypeError", "network.socket." + fn + " : le délai doit être un nombre ou null (obtenu '" + type(t) + "')")
    if t < 0:
        raise("ArgumentError", "network.socket." + fn + " : délai négatif")

class Socket:
    # Nouveau socket (family 4 ou 6, kind "tcp" ou "udp"). handle : socket existant (accept), usage interne.
    func init(family=4, kind="tcp", handle=null):
        _require()
        _check_family("Socket", family)
        if kind != TCP and kind != UDP:
            raise("ArgumentError", "network.socket.Socket : type \"tcp\" ou \"udp\" attendu (obtenu " + str(kind) + ")")
        self.family = family
        self.kind = kind
        self.timeout = null
        self.closed = false
        if handle == null:
            h := _n.socket(family, kind)
            if is_error(h):
                fail("socket(" + ("UNIX" if family == 1 else "IPv" + str(family)) + ", " + kind + ")", h)
            self.handle = h
        else:
            self.handle = handle

    func _h(fn):
        if self.closed:
            raise("ArgumentError", "network.socket." + fn + " : socket fermé")
        return self.handle

    func _t(fn, t):
        if t == null:
            return self.timeout
        _check_timeout(fn, t)
        return t

    # Délai par défaut des opérations (null : sans limite).
    func set_timeout(t):
        _check_timeout("set_timeout", t)
        self.timeout = t

    # Connexion à une adresse NUMÉRIQUE (voir network.tcp.connect pour un nom d'hôte).
    func connect(host, port, timeout=null):
        r := _n.connect(self._h("connect"), host, port, self._t("connect", timeout))
        if is_error(r):
            fail("connect(" + format_address(host, port) + ")", r)

    # Attache le socket à une adresse locale ("" : toutes les interfaces ; port 0 : choisi par le système).
    func bind(host="", port=0):
        r := _n.bind(self._h("bind"), host, port)
        if is_error(r):
            fail("bind(" + format_address(host, port) + ")", r)

    func listen(backlog=128):
        r := _n.listen(self._h("listen"), backlog)
        if is_error(r):
            fail("listen", r)

    # Connexion entrante : (Socket, hôte, port).
    func accept(timeout=null):
        r := _n.accept(self._h("accept"), self._t("accept", timeout))
        if is_error(r):
            fail("accept", r)
        s := Socket(_n.family(r[0]), TCP, r[0])
        return (s, r[1], r[2])

    # Envoie TOUTES les données (str) ; renvoie le nombre d'octets envoyés. Délai dépassé après un envoi
    # partiel : renvoie ce qui est parti.
    func send(data, timeout=null):
        if type(data) != "str":
            raise("TypeError", "network.socket.send : str attendue (obtenu '" + type(data) + "'), voir send_bytes")
        r := _n.send(self._h("send"), data, self._t("send", timeout))
        if is_error(r):
            fail("send", r)
        return r

    func send_bytes(data, timeout=null):
        return self.send(_n.from_bytes(data), timeout)

    # Jusqu'à max octets reçus (str) ; "" : l'autre extrémité a fermé la connexion.
    func recv(max=65536, timeout=null):
        r := _n.recv(self._h("recv"), max, self._t("recv", timeout))
        if is_error(r):
            fail("recv", r)
        return r

    func recv_bytes(max=65536, timeout=null):
        return _n.to_bytes(self.recv(max, timeout))

    # Comme recv sans attendre : null si rien n'est disponible.
    func try_recv(max=65536):
        r := _n.recv(self._h("try_recv"), max, 0)
        if is_error(r):
            if _n.errno_name(r) == "EAGAIN":
                return null
            fail("recv", r)
        return r

    # UDP : envoie un datagramme à une adresse numérique ; renvoie le nombre d'octets envoyés.
    func send_to(data, host, port):
        if type(data) != "str":
            data = _n.from_bytes(data)
        r := _n.sendto(self._h("send_to"), data, host, port)
        if is_error(r):
            fail("send_to(" + format_address(host, port) + ")", r)
        return r

    # UDP : (données, hôte, port) du prochain datagramme.
    func recv_from(max=65536, timeout=null):
        r := _n.recvfrom(self._h("recv_from"), max, self._t("recv_from", timeout))
        if is_error(r):
            fail("recv_from", r)
        return (r[0], r[1], r[2])

    # (hôte, port) local et distant.
    func local_address():
        r := _n.local_address(self._h("local_address"))
        if is_error(r):
            fail("local_address", r)
        return (r[0], r[1])

    func peer_address():
        r := _n.peer_address(self._h("peer_address"))
        if is_error(r):
            fail("peer_address", r)
        return (r[0], r[1])

    # Options : "reuse_address", "no_delay", "broadcast", "keep_alive" (bool) ; "receive_buffer", "send_buffer" (int).
    func set_option(name, value):
        r := _n.set_option(self._h("set_option"), name, value)
        if is_error(r):
            fail("set_option(" + name + ")", r)

    # Ferme un sens de la connexion : "read", "write" ou "both".
    func shutdown(how="both"):
        r := _n.shutdown(self._h("shutdown"), how)
        if is_error(r) and _n.errno_name(r) != "ENOTCONN":
            fail("shutdown", r)

    func close():
        if not self.closed:
            _n.close(self.handle)
            self.closed = true

    func is_closed():
        return self.closed

# Sockets prêts parmi sockets (list de Socket) : mode "read" (données ou connexion à accepter) ou "write".
func wait(sockets, mode="read", timeout=null):
    _check_timeout("wait", timeout)
    handles := []
    for s in sockets:
        append(handles, s._h("wait"))
    ready := _n.wait(handles, mode, timeout)
    out := []
    for s in sockets:
        for h in ready:
            if h == s.handle:
                append(out, s)
    return out

# Nombre de sockets ouverts (diagnostic : un socket non fermé reste ouvert jusqu'à la fin du programme).
func open_count():
    return _n.live_count()

# ALEX STANDARD LIBRARY — network.core
#
# Point d'entrée du réseau : disponibilité et fonctionnalités de la plateforme, connexions TCP ou TLS sous une
# seule forme (open_connection), passage d'une connexion en clair à TLS (start_tls, pour STARTTLS / AUTH TLS),
# points d'extrémité « hôte:port ».
#
# Une connexion est toujours une network.tcp.Connection (lectures tamponnées : read_line, read_exact...), que le
# flux soit en clair ou chiffré.
#
# Exemple
#   use network.core as net
#   print(net.features())              # {"tcp": true, "tls": true, "ipv6": true, ...}
#   c := net.open_connection("smtp.exemple.org", 587, false, 10.0)
#   print(c.read_line())                # bannière « 220 ... »
#   c.write("STARTTLS\r\n") ...
#   c = net.start_tls(c, "smtp.exemple.org")

from core use len, type
from collections use append
use string as _s
use _native_net as _n
use network.socket as _sk
use network.dns as _dns
use network.tcp as _tcp
use network.tls as _tls
use network.constants as _c
use network.utils as _u

const VERSION := "1.0.0"

# Vrai si le réseau est disponible sur cette plateforme (POSIX).
func supported():
    return _sk.supported()

func tls_supported():
    return _tls.supported()

_IPV6 := [null]

# Vrai si la machine peut ouvrir un socket IPv6 sur la boucle locale (::1).
func has_ipv6():
    if _IPV6[0] == null:
        ok := false
        try:
            s := _sk.Socket(6, "tcp")
            try:
                s.bind("::1", 0)
                ok = true
            catch e:
                ok = false
            s.close()
        catch e:
            ok = false
        _IPV6[0] = ok
    return _IPV6[0]

# Fonctionnalités disponibles : dict nom -> bool (et version d'OpenSSL).
func features():
    tls_ok := _tls.supported()
    f := {"tcp": supported(), "udp": supported(), "unix": supported(), "ipv6": supported() and has_ipv6(), "tls": tls_ok, "multicast": supported(), "dns": supported(), "openssl": null}
    if tls_ok:
        f["openssl"] = _tls.library_version()
    return f

func _check_timeout(t):
    if t != null and type(t) != "int" and type(t) != "float":
        raise("TypeError", "network.core : délai nombre ou null attendu (obtenu '" + type(t) + "')")

# Connexion TCP (secure=false) ou TLS (secure=true) à host:port : network.tcp.Connection.
# verify / ca_file / server_name / alpn / cert_file / key_file : voir network.tls.connect.
func open_connection(host, port, secure=false, timeout=null, verify=true, ca_file=null, alpn=null, server_name=null, cert_file=null, key_file=null, family=0):
    _check_timeout(timeout)
    if not _u.is_valid_port(port):
        raise("ArgumentError", "network.core.open_connection : port 1..65535 attendu (obtenu " + str(port) + ")")
    if secure:
        if not _tls.supported():
            raise("IoError", "network.core.open_connection : TLS indisponible — " + _tls.why())
        return _tls.connect(host, port, timeout, verify, ca_file, alpn, family, server_name, cert_file, key_file)
    return _tcp.connect(host, port, timeout, family)

# Passe une connexion TCP établie en TLS (STARTTLS) : rend une NOUVELLE Connection chiffrée sur le même socket.
# Lève ProtocolError si des octets non lus restent dans le tampon (ils ne seraient pas protégés : attaque par
# injection de commandes avant la négociation, CVE-2011-0411).
func start_tls(conn, hostname, verify=true, ca_file=null, alpn=null, timeout=null, cert_file=null, key_file=null):
    if not _tls.supported():
        raise("IoError", "network.core.start_tls : TLS indisponible — " + _tls.why())
    if _n.blen(conn.buffer) > 0:
        raise("ProtocolError", "start_tls : " + str(_n.blen(conn.buffer)) + " octets reçus en clair avant la négociation TLS (refusés)")
    if conn.eof:
        raise("NetworkError", "start_tls : connexion fermée par le pair")
    ts := _tls.wrap_client(conn.socket, hostname, verify, ca_file, alpn, timeout, cert_file, key_file)
    return _tcp.Connection(ts)

# Côté serveur : poignée de main TLS sur une connexion acceptée en clair (STARTTLS serveur).
func accept_tls(conn, cert_file, key_file, alpn=null, timeout=null):
    if _n.blen(conn.buffer) > 0:
        raise("ProtocolError", "accept_tls : octets reçus en clair avant la négociation TLS (refusés)")
    ts := _tls.wrap_server(conn.socket, cert_file, key_file, alpn, timeout)
    return _tcp.Connection(ts)

# Vrai si la connexion est chiffrée (TLS).
func is_secure(conn):
    return isinstance(conn.socket, _tls.TlsSocket)

# Informations TLS d'une connexion (version, chiffrement, alpn, sujet du pair...) ou null en clair.
func tls_info(conn):
    if not is_secure(conn):
        return null
    s := conn.socket
    return {"version": s.version, "cipher": s.cipher, "alpn": s.alpn, "verify_result": s.verify_result, "peer_subject": s.peer_subject, "peer_issuer": s.peer_issuer}

# ---------------------------------------------------------------- points d'extrémité

class Endpoint:
    # host : nom ou adresse ; port : 0..65535 ; secure : TLS.
    func init(host, port, secure=false):
        if type(host) != "str" or host == "":
            raise("ArgumentError", "network.core.Endpoint : hôte non vide attendu")
        if not _u.is_valid_port(port, true):
            raise("ArgumentError", "network.core.Endpoint : port hors de 0..65535 (" + str(port) + ")")
        self.host = host
        self.port = port
        self.secure = secure

    func str():
        return _sk.format_address(self.host, self.port)

    func __str__():
        return self.str()

    func __eq__(other):
        if not isinstance(other, Endpoint):
            return false
        return _s.lower(self.host) == _s.lower(other.host) and self.port == other.port and self.secure == other.secure

    # Clé de regroupement (réserve de connexions).
    func key():
        scheme := "tcp"
        if self.secure:
            scheme = "tls"
        return scheme + "://" + _s.lower(self.host) + ":" + str(self.port)

    func resolve(family=0):
        return _dns.lookup(self.host, self.port, family)

    func connect(timeout=null, verify=true, ca_file=null, alpn=null):
        return open_connection(self.host, self.port, self.secure, timeout, verify, ca_file, alpn)

# Endpoint depuis « hôte:port », « [v6]:port », « tls://hôte:port » ou « hôte » (+ default_port).
func endpoint(text, default_port=null, secure=false):
    t := text
    sec := secure
    i := _s.find(t, "://")
    if i > 0:
        scheme := _s.lower(_s.substring(t, 0, i))
        t = _s.substring(t, i + 3, len(t))
        if _s.ends_with(t, "/"):
            t = _s.substring(t, 0, len(t) - 1)
        sec = scheme == "tls" or scheme == "ssl" or _c.is_secure_scheme(scheme)
        if default_port == null:
            default_port = _c.default_port(scheme)
    hp := _u.split_host_port(t, default_port)
    if hp[1] == null:
        raise("ArgumentError", "network.core.endpoint : port manquant dans '" + text + "'")
    return Endpoint(hp[0], hp[1], sec)

# Nombre de sockets et de sessions TLS ouverts (diagnostic de fuites).
func open_counts():
    n := 0
    if _tls.supported():
        n = _tls.open_count()
    return {"sockets": _sk.open_count(), "tls_sessions": n}

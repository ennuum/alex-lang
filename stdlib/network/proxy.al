# ALEX STANDARD LIBRARY — network.proxy
#
# Mandataires (proxies) côté client et petits relais côté serveur.
#
#   Proxy(url)                  « http://utilisateur:mdp@hôte:3128 », « https://... », « socks5h://hôte:1080 »,
#                               « socks5:// », « socks4a:// », « socks4:// »
#   connect(proxy, hôte, port)  connexion TCP au travers du mandataire -> network.tcp.Connection
#                               (HTTP CONNECT, SOCKS5 avec ou sans mot de passe, SOCKS4 / 4a)
#   proxy_for(url, config)      mandataire à utiliser pour une URL (variables *_PROXY / NO_PROXY de
#                               network.config ; la boucle locale n'est jamais relayée)
#   relay(a, b)                 recopie les octets entre deux connexions jusqu'à la fermeture
#   TunnelServer                mandataire HTTP CONNECT minimal (développement, tests ; un tunnel à la fois)
#
# Avec « socks5h:// » et « socks4a:// », le NOM est résolu par le mandataire (rien ne fuit vers le DNS local) ;
# avec « socks5:// » et « socks4:// », il est résolu localement.
#
# Erreurs : ProxyError (refus du mandataire, authentification, réponse invalide), NetworkError, TimeoutError.
#
# Exemple
#   use network.proxy as px
#   c := px.connect("socks5h://127.0.0.1:1080", "exemple.org", 80, 10.0)
#   c.write("HEAD / HTTP/1.0\r\nHost: exemple.org\r\n\r\n")
#   print(c.read_line())

from core use len, type, to_int
from collections use append, keys
use string as _s
use _native_net as _n
use network.socket as _sk
use network.tcp as _tcp
use network.tls as _tls
use network.dns as _dns
use network.url as _url
use network.config as _cfg
use network.encoding as _enc
use network.ipaddress as _ip

func _fail(message):
    raise("ProxyError", "proxy : " + message)

const SCHEMES := ["http", "https", "socks4", "socks4a", "socks5", "socks5h"]

class Proxy:
    func init(url):
        u := url
        if type(url) == "str":
            t := url
            if not _s.contains(t, "://"):
                t = "http://" + t
            u = _url.parse(t)
        ok := false
        for s in SCHEMES:
            if s == u.scheme:
                ok = true
        if not ok:
            _fail("schéma de mandataire non pris en charge « " + u.scheme + " » (http, https, socks4, socks4a, socks5, socks5h)")
        self.scheme = u.scheme
        self.host = u.host
        self.port = u.port
        if self.port == null:
            if u.scheme == "http":
                self.port = 8080
            elif u.scheme == "https":
                self.port = 443
            else:
                self.port = 1080
        self.username = u.username
        self.password = u.password

    func is_socks():
        return _s.starts_with(self.scheme, "socks")

    # Vrai si le mandataire résout lui-même les noms (socks5h, socks4a, http, https).
    func remote_dns():
        return self.scheme == "socks5h" or self.scheme == "socks4a" or self.scheme == "http" or self.scheme == "https"

    # En-tête Proxy-Authorization (mandataire HTTP avec identifiants), ou null.
    func authorization():
        if self.username == null:
            return null
        pw := self.password
        if pw == null:
            pw = ""
        return "Basic " + _enc.base64_encode(self.username + ":" + pw)

    func str():
        h := self.host
        if _s.contains(h, ":"):
            h = "[" + h + "]"
        return self.scheme + "://" + h + ":" + str(self.port)

func _as_proxy(p):
    if isinstance(p, Proxy):
        return p
    return Proxy(p)

# Ouvre la connexion vers le mandataire lui-même (TLS pour un mandataire https://).
func _open(proxy, timeout, verify, ca_file):
    if proxy.scheme == "https":
        return _tls.connect(proxy.host, proxy.port, timeout, verify, ca_file)
    return _tcp.connect(proxy.host, proxy.port, timeout)

# Connexion à host:port au travers du mandataire ; rend une network.tcp.Connection dont les octets vont à la
# destination (pour HTTPS au-delà, faire ensuite network.core.start_tls(connexion, host)).
func connect(proxy, host, port, timeout=30.0, verify=true, ca_file=null, headers=null):
    p := _as_proxy(proxy)
    conn := _open(p, timeout, verify, ca_file)
    try:
        if p.scheme == "http" or p.scheme == "https":
            _http_connect(conn, p, host, port, timeout, headers)
        elif p.scheme == "socks5" or p.scheme == "socks5h":
            _socks5(conn, p, host, port, timeout)
        else:
            _socks4(conn, p, host, port, timeout)
        return conn
    catch e:
        conn.close()
        raise(e)

func _authority(host, port):
    h := host
    if _s.contains(h, ":"):
        h = "[" + h + "]"
    return h + ":" + str(port)

func _http_connect(conn, p, host, port, timeout, headers):
    target := _authority(host, port)
    req := "CONNECT " + target + " HTTP/1.1\r\nHost: " + target + "\r\n"
    auth := p.authorization()
    if auth != null:
        req += "Proxy-Authorization: " + auth + "\r\n"
    if headers != null:
        for k in keys(headers):
            req += k + ": " + str(headers[k]) + "\r\n"
    conn.write(req + "\r\n", timeout)
    line := conn.read_line(timeout, 8192)
    if line == null:
        _fail("CONNECT " + target + " : connexion fermée par le mandataire")
    parts := _s.split(line, " ")
    if len(parts) < 2 or not _s.starts_with(parts[0], "HTTP/"):
        _fail("CONNECT " + target + " : réponse invalide « " + line + " »")
    status := to_int(parts[1])
    # en-têtes de la réponse (ignorés, sauf pour le message d'erreur)
    total := 0
    while true:
        h := conn.read_line(timeout, 8192)
        if h == null or h == "":
            break
        total += len(h)
        if total > 65536:
            _fail("CONNECT : en-têtes de réponse trop longs")
    if status < 200 or status >= 300:
        if status == 407:
            _fail("CONNECT " + target + " : authentification du mandataire requise (407)")
        _fail("CONNECT " + target + " refusé : " + line)
    if _n.blen(conn.buffer) > 0:
        _fail("CONNECT : octets inattendus après la réponse du mandataire")

const _SOCKS5_ERRORS := ["succès", "défaillance générale du serveur SOCKS", "connexion interdite par les règles", "réseau injoignable", "hôte injoignable", "connexion refusée", "TTL expiré", "commande non prise en charge", "type d'adresse non pris en charge"]

func _socks5(conn, p, host, port, timeout):
    if p.username != null:
        conn.write(_n.from_bytes([5, 2, 0, 2]), timeout)
    else:
        conn.write(_n.from_bytes([5, 1, 0]), timeout)
    r := _n.to_bytes(conn.read_exact(2, timeout))
    if r[0] != 5:
        _fail("SOCKS5 : réponse invalide (version " + str(r[0]) + ")")
    if r[1] == 255:
        _fail("SOCKS5 : aucune méthode d'authentification acceptée par le mandataire")
    if r[1] == 2:
        if p.username == null:
            _fail("SOCKS5 : le mandataire exige un identifiant")
        u := p.username
        pw := p.password
        if pw == null:
            pw = ""
        if _n.blen(u) > 255 or _n.blen(pw) > 255:
            _fail("SOCKS5 : identifiant ou mot de passe trop long")
        conn.write(_n.from_bytes([1, _n.blen(u)]) + u + _n.from_bytes([_n.blen(pw)]) + pw, timeout)
        a := _n.to_bytes(conn.read_exact(2, timeout))
        if a[1] != 0:
            _fail("SOCKS5 : authentification refusée")
    elif r[1] != 0:
        _fail("SOCKS5 : méthode d'authentification inattendue " + str(r[1]))
    req := [5, 1, 0]
    addr := host
    if not p.remote_dns() and not _dns.is_ip(host):
        addr = _dns.resolve_one(host)
    if _dns.is_ipv4(addr):
        append(req, 1)
        for b in _ip.IPv4Address(addr).bytes():
            append(req, b)
    elif _dns.is_ipv6(addr):
        append(req, 4)
        for b in _ip.IPv6Address(addr).bytes():
            append(req, b)
    else:
        name := _n.to_bytes(addr)
        if len(name) > 255:
            _fail("SOCKS5 : nom d'hôte trop long")
        append(req, 3)
        append(req, len(name))
        for b in name:
            append(req, b)
    append(req, (port >> 8) & 255)
    append(req, port & 255)
    conn.write(_n.from_bytes(req), timeout)
    head := _n.to_bytes(conn.read_exact(4, timeout))
    if head[0] != 5:
        _fail("SOCKS5 : réponse invalide")
    if head[1] != 0:
        why := "code " + str(head[1])
        if head[1] < len(_SOCKS5_ERRORS):
            why = _SOCKS5_ERRORS[head[1]]
        _fail("SOCKS5 : connexion à " + _authority(host, port) + " refusée (" + why + ")")
    atyp := head[3]
    if atyp == 1:
        conn.read_exact(4 + 2, timeout)
    elif atyp == 4:
        conn.read_exact(16 + 2, timeout)
    elif atyp == 3:
        n := _n.to_bytes(conn.read_exact(1, timeout))[0]
        conn.read_exact(n + 2, timeout)
    else:
        _fail("SOCKS5 : type d'adresse de réponse inconnu " + str(atyp))

func _socks4(conn, p, host, port, timeout):
    req := [4, 1, (port >> 8) & 255, port & 255]
    user := p.username
    if user == null:
        user = ""
    tail := []
    if p.scheme == "socks4a" and not _dns.is_ip(host):
        req = req + [0, 0, 0, 1]
        tail = _n.to_bytes(host) + [0]
    else:
        addr := host
        if not _dns.is_ipv4(addr):
            addr = _dns.resolve_one(host, 4)
        for b in _ip.IPv4Address(addr).bytes():
            append(req, b)
    for b in _n.to_bytes(user):
        append(req, b)
    append(req, 0)
    for b in tail:
        append(req, b)
    conn.write(_n.from_bytes(req), timeout)
    r := _n.to_bytes(conn.read_exact(8, timeout))
    if r[0] != 0:
        _fail("SOCKS4 : réponse invalide")
    if r[1] != 90:
        _fail("SOCKS4 : connexion à " + _authority(host, port) + " refusée (code " + str(r[1]) + ")")

# ---------------------------------------------------------------- choix du mandataire

func _is_loopback(host):
    if host == null:
        return false
    h := _s.lower(host)
    if h == "localhost" or _s.ends_with(h, ".localhost"):
        return true
    if _ip.is_ip(h):
        return _ip.ip_address(h).is_loopback()
    return false

# Mandataire (Proxy) à utiliser pour une URL d'après la configuration (défaut : network.config.defaults()), ou
# null pour une connexion directe.
func proxy_for(target_url, config=null):
    c := config
    if c == null:
        c = _cfg.defaults()
    u := _url.parse(target_url)
    if _is_loopback(u.host):
        return null
    if c.bypass_proxy(u.host, u.effective_port()):
        return null
    scheme := u.scheme
    if scheme == "ws":
        scheme = "http"
    elif scheme == "wss":
        scheme = "https"
    p := c.proxy_for(scheme)
    if p == null:
        return null
    return Proxy(p)

# ---------------------------------------------------------------- relais

# Recopie les octets dans les deux sens entre deux connexions (network.tcp.Connection) jusqu'à ce que l'une se
# ferme ou reste inactive plus de idle_timeout secondes. Rend (octets a->b, octets b->a).
func relay(a, b, idle_timeout=300.0):
    sent := 0
    received := 0
    # vider ce qui est déjà en tampon
    if _n.blen(a.buffer) > 0:
        sent += b.write(a._take(_n.blen(a.buffer)))
    if _n.blen(b.buffer) > 0:
        received += a.write(b._take(_n.blen(b.buffer)))
    while true:
        ready := _ready([a.socket, b.socket], idle_timeout)
        if len(ready) == 0:
            return (sent, received)
        for s in ready:
            if s == a.socket:
                data := a.socket.recv(65536, 0)
                if data == "":
                    _half_close(b)
                    return (sent, received)
                sent += b.write(data)
            else:
                data := b.socket.recv(65536, 0)
                if data == "":
                    _half_close(a)
                    return (sent, received)
                received += a.write(data)

func _half_close(c):
    try:
        c.close_write()
    catch e:
        ignored := e

func _ready(socks, timeout):
    plain := []
    secure := []
    for s in socks:
        if isinstance(s, _tls.TlsSocket):
            append(secure, s)
        else:
            append(plain, s)
    if len(secure) == 0:
        return _sk.wait(plain, "read", timeout)
    # TLS : des octets déjà déchiffrés comptent comme prêts
    out := []
    for s in secure:
        if s.pending() > 0:
            append(out, s)
    if len(out) > 0:
        return out
    raws := []
    for s in socks:
        if isinstance(s, _tls.TlsSocket):
            append(raws, s.socket)
        else:
            append(raws, s)
    r := _sk.wait(raws, "read", timeout)
    for s in socks:
        for x in r:
            if (isinstance(s, _tls.TlsSocket) and x == s.socket) or x == s:
                append(out, s)
    return out

# Mandataire HTTP CONNECT minimal : accepte un client, ouvre le tunnel vers la destination demandée, relaie, puis
# passe au suivant (un tunnel à la fois). allow(hôte, port) -> bool filtre les destinations.
class TunnelServer:
    func init(host="127.0.0.1", port=0, allow=null, username=null, password=null):
        self.listener = _tcp.listen(host, port)
        self.allow = allow
        self.username = username
        self.password = password
        self.tunnels = 0
        self.refused = 0

    func port():
        return self.listener.port()

    func url():
        a := self.listener.address()
        return "http://" + _sk.format_address(a[0], a[1])

    func handle_one(accept_timeout=null, connect_timeout=10.0):
        client := self.listener.accept(accept_timeout)
        try:
            self._handle(client, connect_timeout)
        catch e:
            ignored := e
        client.close()

    func _handle(client, connect_timeout):
        line := client.read_line(30.0, 8192)
        if line == null:
            return
        auth := null
        while true:
            h := client.read_line(30.0, 8192)
            if h == null or h == "":
                break
            if _s.starts_with(_s.lower(h), "proxy-authorization:"):
                auth = _s.trim(_s.substring(h, 20, len(h)))
        parts := _s.split(line, " ")
        if len(parts) != 3 or _s.upper(parts[0]) != "CONNECT":
            client.write("HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            self.refused += 1
            return
        if self.username != null:
            expected := "Basic " + _enc.base64_encode(self.username + ":" + self.password)
            if auth != expected:
                client.write("HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm=\"alex\"\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                self.refused += 1
                return
        hp := null
        try:
            hp = _split_target(parts[1])
        catch e:
            client.write("HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            self.refused += 1
            return
        if self.allow != null and not self.allow(hp[0], hp[1]):
            client.write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            self.refused += 1
            return
        upstream := null
        try:
            upstream = _tcp.connect(hp[0], hp[1], connect_timeout)
        catch e:
            client.write("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            self.refused += 1
            return
        client.write("HTTP/1.1 200 Connection Established\r\n\r\n")
        self.tunnels += 1
        try:
            relay(client, upstream)
        catch e:
            ignored := e
        upstream.close()

    func serve(max_tunnels=null):
        n := 0
        while max_tunnels == null or n < max_tunnels:
            self.handle_one()
            n += 1

    func close():
        self.listener.close()

func _split_target(t):
    if _s.starts_with(t, "["):
        e := _s.find(t, "]")
        return (_s.substring(t, 1, e), to_int(_s.substring(t, e + 2, len(t))))
    c := _s.find(t, ":")
    if c <= 0:
        raise("ValueError", "cible CONNECT sans port")
    p := to_int(_s.substring(t, c + 1, len(t)))
    if p < 1 or p > 65535:
        raise("ValueError", "port invalide")
    return (_s.substring(t, 0, c), p)

# ALEX STANDARD LIBRARY — web.client.connection
#
# Connection : une connexion du client vers un serveur HTTP — TCP, TLS (https), directe ou à travers un
# mandataire (cible absolue pour http, tunnel CONNECT pour https). Elle envoie et reçoit des octets bruts ; le
# protocole est géré par web.client.response_reader et web.http.
#
#   use web.client.connection as cn
#   c := cn.open("https", "exemple.org", 443, tls_cfg, timeout_cfg)
#   c.send("GET / HTTP/1.1\r\nHost: exemple.org\r\n\r\n", 30)
#   octets := c.recv(65536, 30)       # "" : fin du flux
#   c.is_reusable()                   # encore ouverte et sans données inattendues
#   c.close()
#
# Erreurs : ClientConnectionError, ClientTimeoutError, ClientTlsError, ClientProxyError.

from core use len, type
use string as _s
use time as _time
use network.tcp as _tcp
use network.tls as _tls
use network.socket as _sk
use web.client.client_errors as _err
use web.client.timeout as _timeout
use web.client.tls_config as _tlsconf
use web.http.protocol_parser as _pp
use web.http.headers as _headers

class Connection:
    func init(scheme, host, port, sock, via_proxy=null, tunnel=false):
        self.scheme = scheme
        self.host = host
        self.port = port
        self.socket = sock               # network.socket.Socket ou network.tls.TlsSocket
        self.via_proxy = via_proxy       # Proxy, ou null
        self.tunnel = tunnel             # https à travers un mandataire (CONNECT)
        self.created_at = _time.monotonic()
        self.last_used = self.created_at
        self.requests = 0
        self.bytes_sent = 0
        self.bytes_received = 0
        self.closed = false
        self.reused = false              # vrai si la connexion vient de la réserve

    # Clé de réserve : (schéma, hôte, port, mandataire).
    func key():
        return connection_key(self.scheme, self.host, self.port, self.via_proxy)

    # Cible en forme absolue (requête http à travers un mandataire, sans tunnel).
    func needs_absolute_target():
        return self.via_proxy != null and not self.tunnel

    func is_secure():
        return self.scheme == "https"

    func send(data, timeout=null):
        if self.closed:
            _err.connection_error("Connection.send", "connexion fermée")
        try:
            n := self.socket.send(data, timeout)
            self.bytes_sent += n
            self.last_used = _time.monotonic()
            return n
        catch e:
            self.close()
            _err.wrap(e, self.host + ":" + str(self.port))

    # Jusqu'à max octets bruts ; "" : fin du flux.
    func recv(max=65536, timeout=null):
        if self.closed:
            return ""
        try:
            d := self.socket.recv(max, timeout)
            self.bytes_received += _s.byte_len(d)
            self.last_used = _time.monotonic()
            return d
        catch e:
            self.close()
            _err.wrap(e, self.host + ":" + str(self.port))

    # Vraie si la connexion peut servir une nouvelle requête : ouverte, et le serveur n'a ni fermé ni envoyé
    # d'octets inattendus pendant l'inactivité.
    func is_reusable():
        if self.closed:
            return false
        try:
            d := self.socket.try_recv(1)
            if d == null:
                return true
            self.close()
            return false
        catch e:
            self.close()
            return false

    func idle_time():
        return _time.monotonic() - self.last_used

    func age():
        return _time.monotonic() - self.created_at

    func close():
        if self.closed:
            return
        self.closed = true
        try:
            self.socket.close()
        catch e:
            ignored := e

    func is_closed():
        return self.closed

    func peer_address():
        try:
            return self.socket.peer_address()
        catch e:
            return null

    # Version et suite TLS négociées (https), ou null.
    func tls_info():
        if not self.is_secure():
            return null
        try:
            return {"version": self.socket.version, "cipher": self.socket.cipher, "alpn": self.socket.alpn}
        catch e:
            return null

    func __str__():
        return "<Connection " + self.scheme + "://" + self.host + ":" + str(self.port) + (" via " + str(self.via_proxy) if self.via_proxy != null else "") + ">"

func connection_key(scheme, host, port, proxy=null):
    k := scheme + "://" + host + ":" + str(port)
    if proxy != null:
        k = k + " via " + proxy.host + ":" + str(proxy.port)
    return k

# Socket TCP brut connecté (chaque adresse résolue essayée), ou erreur du client.
func _tcp_socket(host, port, timeout):
    try:
        return _tcp.connect(host, port, timeout).socket
    catch e:
        _err.wrap(e, host + ":" + str(port))

func _tls_wrap(sock, host, tls_cfg, timeout):
    if not _tls.supported():
        sock.close()
        _err.tls_error("connection", "TLS indisponible : " + str(_tls.why()))
    try:
        return _tls.wrap_client(sock, tls_cfg.name_for(host), tls_cfg.verify, tls_cfg.ca_file, tls_cfg.alpn, timeout, tls_cfg.cert_file, tls_cfg.key_file, false)
    catch e:
        sock.close()
        _err.wrap(e, "TLS " + host)

# Tunnel CONNECT à travers le mandataire (socket déjà connecté au mandataire).
func _connect_tunnel(sock, proxy, host, port, timeout):
    authority := ("[" + host + "]" if _s.contains(host, ":") else host) + ":" + str(port)
    req := "CONNECT " + authority + " HTTP/1.1\r\nHost: " + authority + "\r\n"
    auth := proxy.authorization()
    if auth != null:
        req = req + "Proxy-Authorization: " + auth + "\r\n"
    req = req + "\r\n"
    try:
        sock.send(req, timeout)
        p := _pp.ResponseParser("CONNECT")
        while true:
            d := sock.recv(4096, timeout)
            if d == "":
                _err.proxy_error("connection", "le mandataire a fermé la connexion pendant CONNECT")
            msgs := p.feed(d)
            if len(msgs) > 0:
                r := msgs[0]
                if r.status < 200 or r.status >= 300:
                    _err.proxy_error("connection", "le mandataire refuse le tunnel vers " + authority + " : " + str(r.status) + " " + r.reason)
                if p.pending() > 0:
                    _err.proxy_error("connection", "octets inattendus après la réponse CONNECT")
                return
    catch e:
        sock.close()
        if e.type == _err.PROXY:
            raise(e)
        _err.wrap(e, "mandataire " + proxy.host + ":" + str(proxy.port))

# Ouvre une connexion vers scheme://host:port (proxy : web.client.proxy.Proxy ou null).
func open(scheme, host, port, tls_cfg=null, timeout_cfg=null, proxy=null):
    t := timeout_cfg if timeout_cfg != null else _timeout.Timeout()
    tc := tls_cfg if tls_cfg != null else _tlsconf.TlsConfig()
    if proxy == null:
        sock := _tcp_socket(host, port, t.connect)
        if scheme == "https":
            sock = _tls_wrap(sock, host, tc, t.connect)
        return Connection(scheme, host, port, sock)
    psock := null
    try:
        psock = _tcp.connect(proxy.host, proxy.port, t.connect).socket
    catch e:
        _err.proxy_error("connection", "mandataire " + proxy.host + ":" + str(proxy.port) + " injoignable : " + str(e.message))
    if proxy.scheme == "https":
        psock = _tls_wrap(psock, proxy.host, _tlsconf.TlsConfig(), t.connect)
    if scheme == "https":
        _connect_tunnel(psock, proxy, host, port, t.connect)
        return Connection(scheme, host, port, _tls_wrap(psock, host, tc, t.connect), proxy, true)
    return Connection(scheme, host, port, psock, proxy, false)

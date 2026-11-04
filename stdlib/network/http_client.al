# ALEX STANDARD LIBRARY — network.http_client
#
# Client HTTP/1.1 complet, au-dessus de network.tcp / network.tls :
#
#   - connexions persistantes (keep-alive) réutilisées par une réserve (network.connection_pool), avec reprise
#     transparente si le serveur a fermé une connexion inactive ;
#   - redirections (301/302/303/307/308, historique), sans jamais transmettre Authorization, Cookie ni
#     Proxy-Authorization à une autre origine ;
#   - cookies (network.http_cookies.CookieJar), authentification Basic, Bearer et Digest (RFC 7616) ;
#   - corps : texte, octets, formulaire (dict), JSON, multipart (fichiers) ; paramètres de requête ;
#   - réponses compressées (gzip, deflate) décodées ; taille maximale ; délais connexion / lecture / total ;
#   - mandataires HTTP, HTTPS (CONNECT) et SOCKS (variables *_PROXY / NO_PROXY) ;
#   - nouvelles tentatives (network.retry.RetryPolicy) sur erreurs passagères et statuts 429 / 503... ;
#   - réponses en flux (stream=true) et téléchargement vers un fichier.
#
#   c := Client(base_url, headers, timeout...)       c.get / post / put / patch / delete / head / options / request
#   Response : status, reason, headers, url, history, elapsed ; text(), json(), bytes(), ok(), raise_for_status()
#   get(url) ... : raccourcis sur un client partagé ; download(url, chemin)
#
# Erreurs : HttpError (réponse invalide, trop de redirections, raise_for_status), NetworkError, TimeoutError,
# DnsError, TlsError, ProxyError.
#
# Exemple
#   use network.http_client as hc
#   c := hc.Client("https://api.exemple.org/v1/", {"Accept": "application/json"}, 10.0)
#   r := c.get("articles", {"page": 2})
#   for a in r.raise_for_status().json():
#       print(a["titre"])
#   r2 := c.post("articles", null, {"titre": "Nouveau"})          # corps JSON
#   r3 := c.post("fichiers", null, null, {"desc": "logo"}, {"f": hc.File("logo.png", octets)})
#   c.close()

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use json as _json
use io as _io
use time as _time
use crypto as _crypto
use network.tcp as _tcp
use network.tls as _tls
use network.core as _core
use network.url as _url
use network.http_headers as _hh
use network.http_cookies as _ck
use network.http_multipart as _mp
use network.compression as _z
use network.connection_pool as _pool
use network.proxy as _px
use network.config as _cfg
use network.retry as _retry
use network.timeout as _to
use network.encoding as _enc
use network.constants as _c

const USER_AGENT := "Alex-http_client/1.0"
const MAX_HEADER_BYTES := 65536
const MAX_HEADERS := 200

# Fichier pour un envoi multipart (voir network.http_multipart.File).
func File(filename, data, content_type=null):
    return _mp.File(filename, data, content_type)

func _fail(message):
    raise("HttpError", "http_client : " + message)

# ---------------------------------------------------------------- lecture d'un corps

class _BodyReader:
    # mode : "length" (n octets), "chunked", "close" (jusqu'à la fermeture) ou "none".
    func init(conn, mode, length, timeout, max_body):
        self.conn = conn
        self.mode = mode
        self.remaining = length
        self.timeout = timeout
        self.max_body = max_body
        self.total = 0
        self.done = mode == "none" or (mode == "length" and length == 0)
        self.chunk_left = 0
        self.trailers = []

    func _count(n):
        self.total += n
        if self.max_body != null and self.total > self.max_body:
            _fail("corps de réponse trop grand (plus de " + str(self.max_body) + " octets)")

    # Prochain morceau d'octets (au plus max), ou null à la fin du corps.
    func read_chunk(max=65536):
        if self.done:
            return null
        c := self.conn
        if self.mode == "length":
            n := self.remaining
            if n > max:
                n = max
            data := ""
            if _n.blen(c.buffer) > 0:
                k := _n.blen(c.buffer)
                if k > n:
                    k = n
                data = c._take(k)
            else:
                data = c.socket.recv(n, self.timeout)
                if data == "":
                    _fail("connexion fermée avant la fin du corps (" + str(self.remaining) + " octets manquants)")
            self.remaining -= _n.blen(data)
            self._count(_n.blen(data))
            if self.remaining <= 0:
                self.done = true
            return data
        if self.mode == "chunked":
            if self.chunk_left == 0:
                line := c.read_line(self.timeout, MAX_HEADER_BYTES)
                if line == null:
                    _fail("connexion fermée dans un corps « chunked »")
                semi := _s.find(line, ";")
                if semi >= 0:
                    line = _s.substring(line, 0, semi)
                size := _parse_hex(line)
                if size == 0:
                    # en-têtes de fin (trailers) jusqu'à la ligne vide
                    while true:
                        t := c.read_line(self.timeout, MAX_HEADER_BYTES)
                        if t == null or t == "":
                            break
                        append(self.trailers, t)
                    self.done = true
                    return null
                self.chunk_left = size
            n := self.chunk_left
            if n > max:
                n = max
            data := c.read_exact(n, self.timeout)
            self.chunk_left -= n
            self._count(n)
            if self.chunk_left == 0:
                end := c.read_exact(2, self.timeout)
                if end != "\r\n":
                    _fail("fin de morceau « chunked » invalide")
            return data
        # jusqu'à la fermeture
        if _n.blen(c.buffer) > 0:
            k := _n.blen(c.buffer)
            if k > max:
                k = max
            data := c._take(k)
            self._count(_n.blen(data))
            return data
        data := c.socket.recv(max, self.timeout)
        if data == "":
            self.done = true
            c.eof = true
            return null
        self._count(_n.blen(data))
        return data

    func read_all():
        parts := []
        while true:
            d := self.read_chunk(65536)
            if d == null:
                break
            append(parts, d)
        return _s.join("", parts)

func _parse_hex(text):
    t := _s.trim(text)
    if t == "" or len(t) > 15:
        _fail("taille de morceau invalide « " + t + " »")
    n := 0
    for ch in _s.lower(t):
        d := _s.find("0123456789abcdef", str(ch))
        if d < 0:
            _fail("taille de morceau invalide « " + t + " »")
        n = n * 16 + d
    return n

# ---------------------------------------------------------------- réponses

class Response:
    func init(status, reason, version, headers, body, url, method):
        self.status = status
        self.reason = reason
        self.version = version        # « HTTP/1.1 »
        self.headers = headers        # network.http_headers.Headers
        self.body = body              # octets décodés (Content-Encoding défait) ; null en mode flux
        self.url = url                # URL finale (str)
        self.method = method
        self.history = []             # réponses de redirection précédentes
        self.elapsed = 0.0            # secondes jusqu'à la fin des en-têtes
        self.request_headers = null
        self._reader = null           # mode flux
        self._release = null

    func ok():
        return self.status >= 200 and self.status < 300

    func is_redirect():
        return _c.is_redirect_status(self.status) and self.headers.has("location")

    func header(name, default=null):
        return self.headers.get(name, default)

    func content_type():
        return self.headers.content_type()

    # Jeu de caractères déclaré (Content-Type), sinon UTF-8.
    func encoding():
        cs := self.headers.charset()
        if cs == null:
            return "utf-8"
        return cs

    func bytes():
        return _n.to_bytes(self.content())

    # Octets bruts du corps (lit tout le flux si stream=true).
    func content():
        if self.body == null and self._reader != null:
            self.body = self._finish_stream()
        return self.body

    # Texte décodé selon le charset (caractères invalides remplacés).
    func text():
        return _enc.decode_charset(self.content(), self.encoding(), "replace")

    func json():
        return _json.parse(self.text())

    # dict nom -> valeur des cookies posés par cette réponse.
    func cookies():
        out := {}
        for v in self.headers.get_all("set-cookie"):
            c := _ck.parse_set_cookie(v)
            if c != null:
                out[c.name] = c.value
        return out

    # URL du lien `rel` de l'en-tête Link (pagination « next »...), ou null.
    func link(rel):
        return _hh.find_link(self.headers.get("link"), rel)

    func raise_for_status():
        if self.status >= 400:
            kind := "erreur client"
            if self.status >= 500:
                kind = "erreur serveur"
            raise("HttpError", "HTTP " + str(self.status) + " " + self.reason + " (" + kind + ") : " + self.method + " " + self.url)
        return self

    # --- mode flux (stream=true) ---

    # Prochain morceau du corps décodé du réseau (sans décompression), ou null à la fin.
    func read_chunk(max=65536):
        if self._reader == null:
            if self.body == null:
                return null
            b := self.body
            self.body = null
            if b == "":
                return null
            return b
        d := self._reader.read_chunk(max)
        if d == null:
            self._end_stream(true)
        return d

    func _finish_stream():
        try:
            raw := self._reader.read_all()
            self._end_stream(true)
            return _z.decode(raw, self.headers.get("content-encoding"))
        catch e:
            self._end_stream(false)
            raise(e)

    func _end_stream(reusable):
        if self._release != null:
            rel := self._release
            self._release = null
            reader := self._reader
            rel(reusable and reader.done)
        self._reader = null

    # Écrit le corps dans un fichier (en flux, décompressé si besoin) ; rend le nombre d'octets écrits.
    func save(path):
        coding := self.headers.get("content-encoding")
        if coding != null and _s.lower(_s.trim(coding)) != "identity":
            data := self.content()
            _io.write_bytes(path, _n.to_bytes(data))
            return _n.blen(data)
        _io.write_bytes(path, [])
        n := 0
        while true:
            d := self.read_chunk(65536)
            if d == null:
                break
            _io.write_bytes_at(path, _n.to_bytes(d), n)
            n += _n.blen(d)
        return n

    # Abandonne la lecture du corps (la connexion n'est pas réutilisée).
    func close():
        if self._reader != null:
            self._reader.conn.close()
            self._end_stream(false)

    func str():
        return "<Response " + str(self.status) + " " + self.reason + ">"

# ---------------------------------------------------------------- authentification Digest (RFC 7616)

class _DigestState:
    func init(challenge):
        self.realm = challenge.params["realm"]
        self.nonce = challenge.params["nonce"]
        self.opaque = null
        if contains_key(challenge.params, "opaque"):
            self.opaque = challenge.params["opaque"]
        self.algorithm = "MD5"
        if contains_key(challenge.params, "algorithm"):
            self.algorithm = _s.upper(challenge.params["algorithm"])
        self.qop = null
        if contains_key(challenge.params, "qop"):
            for q in _s.split(challenge.params["qop"], ","):
                if _s.trim(q) == "auth":
                    self.qop = "auth"
        self.nc = 0

    func _h(text):
        if _s.starts_with(self.algorithm, "SHA-256"):
            return _crypto.sha256(_n.to_bytes(text))
        return _crypto.md5(_n.to_bytes(text))

    func header(user, password, method, uri):
        self.nc += 1
        cnonce := _enc.hex_encode(_n.random_bytes(8))
        ha1 := self._h(user + ":" + self.realm + ":" + password)
        if _s.ends_with(self.algorithm, "-SESS"):
            ha1 = self._h(ha1 + ":" + self.nonce + ":" + cnonce)
        ha2 := self._h(method + ":" + uri)
        ncs := _s.lower(_enc.hex_encode(_n.from_bytes([(self.nc >> 24) & 255, (self.nc >> 16) & 255, (self.nc >> 8) & 255, self.nc & 255])))
        resp := ""
        if self.qop == "auth":
            resp = self._h(ha1 + ":" + self.nonce + ":" + ncs + ":" + cnonce + ":auth:" + ha2)
        else:
            resp = self._h(ha1 + ":" + self.nonce + ":" + ha2)
        out := "Digest username=" + _hh.quote(user) + ", realm=" + _hh.quote(self.realm) + ", nonce=" + _hh.quote(self.nonce) + ", uri=" + _hh.quote(uri) + ", algorithm=" + self.algorithm + ", response=\"" + resp + "\""
        if self.qop == "auth":
            out += ", qop=auth, nc=" + ncs + ", cnonce=\"" + cnonce + "\""
        if self.opaque != null:
            out += ", opaque=" + _hh.quote(self.opaque)
        return out

# ---------------------------------------------------------------- client

class Client:
    # base_url : préfixe des URL relatives ; headers : en-têtes ajoutés à chaque requête ; timeout : nombre,
    # network.timeout.Timeouts ou null ; auth : (utilisateur, mot de passe) pour Basic/Digest, ou str (jeton
    # Bearer) ; cookies : true (bocal neuf), un CookieJar, ou false ; retry : RetryPolicy ou null ;
    # proxy : URL de mandataire imposée, false (aucun) ou null (configuration / environnement).
    func init(base_url=null, headers=null, timeout=30.0, verify=true, ca_file=null, auth=null, cookies=true, follow_redirects=true, max_redirects=10, retry=null, proxy=null, config=null, cert_file=null, key_file=null, max_body=null, pool_size=10, keep_alive=true, user_agent=USER_AGENT, accept_compressed=true):
        self.config = config
        if config == null:
            self.config = _cfg.defaults()
        self.base_url = null
        if base_url != null:
            self.base_url = _url.parse(base_url)
        self.headers = _hh.Headers(headers)
        self.timeouts = _to.timeouts(timeout)
        self.verify = verify
        self.ca_file = ca_file
        if ca_file == null:
            self.ca_file = self.config.get("ca_file")
        self.cert_file = cert_file
        self.key_file = key_file
        self.auth = auth
        self.cookies = null
        if cookies == true:
            self.cookies = _ck.CookieJar()
        elif cookies != false and cookies != null:
            self.cookies = cookies
        self.follow_redirects = follow_redirects
        self.max_redirects = max_redirects
        self.retry = retry
        self.proxy = proxy
        self.max_body = max_body
        if max_body == null:
            self.max_body = self.config.get("max_body")
        self.keep_alive = keep_alive
        self.pool = _pool.ConnectionPool(pool_size, null, self.config.get("pool_idle_timeout"))
        self.user_agent = user_agent
        self.accept_compressed = accept_compressed
        self.hooks = {"request": [], "response": []}
        self._digest = {}             # origine -> _DigestState
        self.requests_sent = 0

    func __enter__():
        return self

    func __exit__(t, v, tb):
        self.close()
        return false

    func close():
        self.pool.close_all()

    # Ajoute une fonction appelée avant chaque envoi (hook(méthode, url, Headers)) ou après chaque réponse
    # (hook(Response)) : event = "request" ou "response".
    func add_hook(event, fn):
        if not contains_key(self.hooks, event):
            raise("ArgumentError", "http_client.add_hook : événement \"request\" ou \"response\" attendu")
        append(self.hooks[event], fn)

    func _resolve(target):
        if isinstance(target, _url.URL):
            return target
        t := str(target)
        if self.base_url != null and not _s.contains(t, "://"):
            return _url.parse(t, self.base_url)
        return _url.parse(t)

    func _proxy_for(u):
        if self.proxy == false:
            return null
        if self.proxy != null:
            return _px.Proxy(self.proxy)
        if not self.config.get("trust_env"):
            return null
        return _px.proxy_for(u.str(), self.config)

    func _pool_key(u, proxy):
        k := u.scheme + "://" + _s.lower(u.host) + ":" + str(u.effective_port())
        if proxy != null:
            k += " via " + proxy.str()
        return k

    func _open(u, proxy):
        t := self.timeouts.connect
        if proxy == null:
            if u.scheme == "https":
                return _core.open_connection(u.host, u.effective_port(), true, t, self.verify, self.ca_file, ["http/1.1"], null, self.cert_file, self.key_file)
            return _tcp.connect(u.host, u.effective_port(), t)
        if u.scheme == "https" or proxy.is_socks():
            conn := _px.connect(proxy, u.host, u.effective_port(), t, self.verify, self.ca_file)
            if u.scheme == "https":
                try:
                    conn = _core.start_tls(conn, u.host, self.verify, self.ca_file, ["http/1.1"], t, self.cert_file, self.key_file)
                catch e:
                    conn.close()
                    raise(e)
            return conn
        # http:// par un mandataire HTTP : connexion au mandataire, requête en forme absolue
        if proxy.scheme == "https":
            return _tls.connect(proxy.host, proxy.port, t, self.verify, self.ca_file)
        return _tcp.connect(proxy.host, proxy.port, t)

    # Corps et type de contenu d'une requête.
    func _body(data, json, files, fields):
        if json != null:
            return (_json.stringify(json), "application/json")
        if files != null or (fields != null and _has_file(fields)):
            r := _mp.encode(fields, files)
            return (r[0], r[1])
        if fields != null:
            return (_url.urlencode(fields), "application/x-www-form-urlencoded")
        if data == null:
            return (null, null)
        if type(data) == "dict" or (type(data) == "list" and len(data) > 0 and type(data[0]) == "list"):
            return (_url.urlencode(data), "application/x-www-form-urlencoded")
        if type(data) == "list":
            return (_n.from_bytes(data), "application/octet-stream")
        return (str(data), null)

    func _auth_header(u, method):
        a := self.auth
        if a == null:
            return null
        if type(a) == "str":
            return _hh.bearer_auth(a)
        if type(a) == "tuple" or type(a) == "list":
            o := u.origin()
            if contains_key(self._digest, o):
                return self._digest[o].header(a[0], a[1], method, u.target())
            return _hh.basic_auth(a[0], a[1])
        if type(a) == "function":
            return a(method, u.str())
        return null

    # Requête complète. url : absolue, ou relative à base_url ; params : paramètres ajoutés à l'URL ;
    # data : str / octets / dict (formulaire) ; json : valeur envoyée en JSON ; fields + files : multipart ;
    # stream : réponse lue à la demande (read_chunk, save) ; timeout : délai propre à cette requête.
    func request(method, url, params=null, data=null, json=null, headers=null, files=null, fields=null, timeout=null, stream=false, follow_redirects=null):
        m := _s.upper(method)
        _hh.check_name(m)
        u := self._resolve(url)
        if u.scheme != "http" and u.scheme != "https":
            _fail("schéma « " + u.scheme + " » non pris en charge (http, https)")
        if params != null:
            u = u.with_params(params)
        b := self._body(data, json, files, fields)
        body := b[0]
        hdrs := self.headers.copy()
        if headers != null:
            for p in _hh.Headers(headers).items():
                hdrs.set(p[0], p[1])
        if b[1] != null and not hdrs.has("content-type"):
            hdrs.set("Content-Type", b[1])
        tos := self.timeouts
        if timeout != null:
            tos = _to.timeouts(timeout)
        follow := self.follow_redirects
        if follow_redirects != null:
            follow = follow_redirects
        policy := self.retry
        if policy == null and self.config.get("retries") > 0:
            policy = _retry.RetryPolicy(self.config.get("retries") + 1, self.config.get("retry_backoff"))
        if policy == null:
            return self._send_follow(m, u, body, hdrs, tos, stream, follow)
        return _retry.retry_response(() => self._send_follow(m, u, body, hdrs, tos, stream, follow), policy)

    func _send_follow(method, u, body, hdrs, tos, stream, follow):
        deadline := _to.Deadline(tos.total)
        history := []
        cur_method := method
        cur_body := body
        cur_url := u
        cur_headers := hdrs
        digest_tried := false
        while true:
            r := self._send(cur_method, cur_url, cur_body, cur_headers, tos, stream, deadline)
            # Digest : un seul nouvel essai avec le défi reçu
            if r.status == 401 and not digest_tried and (type(self.auth) == "tuple" or type(self.auth) == "list"):
                for ch in _hh.parse_challenges(r.headers.get("www-authenticate")):
                    if ch.scheme == "digest" and contains_key(ch.params, "nonce"):
                        self._digest[cur_url.origin()] = _DigestState(ch)
                        digest_tried = true
                if digest_tried:
                    r.close()
                    if r.body == null:
                        r.body = ""
                    continue
            r.history = history
            if not follow or not r.is_redirect():
                return r
            if len(history) >= self.max_redirects:
                r.close()
                _fail("trop de redirections (plus de " + str(self.max_redirects) + ") depuis " + u.str())
            location := r.headers.get("location")
            nxt := null
            try:
                nxt = cur_url.join(location)
            catch e:
                r.close()
                _fail("redirection vers une URL invalide « " + location + " »")
            if nxt.scheme != "http" and nxt.scheme != "https":
                r.close()
                _fail("redirection vers un schéma non pris en charge : " + nxt.str())
            if stream:
                r.content()
            append(history, r)
            if r.status == 303 or ((r.status == 301 or r.status == 302) and cur_method == "POST"):
                if cur_method != "HEAD":
                    cur_method = "GET"
                cur_body = null
                cur_headers = cur_headers.copy()
                cur_headers.remove("content-type")
                cur_headers.remove("content-length")
            if nxt.origin() != cur_url.origin():
                cur_headers = cur_headers.copy()
                cur_headers.remove("authorization")
                cur_headers.remove("cookie")
                cur_headers.remove("proxy-authorization")
            if nxt.fragment == null and cur_url.fragment != null:
                nxt = nxt.with_fragment(cur_url.fragment)
            cur_url = nxt

    # Une requête, sans suivre les redirections.
    func _send(method, u, body, hdrs, tos, stream, deadline):
        proxy := self._proxy_for(u)
        key := self._pool_key(u, proxy)
        absolute := proxy != null and u.scheme == "http" and not proxy.is_socks()
        h := hdrs.copy()
        if not h.has("host"):
            h.set("Host", u.netloc())
        if not h.has("user-agent") and self.user_agent != null:
            h.set("User-Agent", self.user_agent)
        if not h.has("accept"):
            h.set("Accept", "*/*")
        if self.accept_compressed and not h.has("accept-encoding"):
            h.set("Accept-Encoding", _z.accept_encoding())
        if not h.has("authorization"):
            if u.username != null:
                pw := u.password
                if pw == null:
                    pw = ""
                h.set("Authorization", _hh.basic_auth(u.username, pw))
            else:
                a := self._auth_header(u, method)
                if a != null:
                    h.set("Authorization", a)
        if self.cookies != null and not h.has("cookie"):
            cv := self.cookies.header_for(u.str())
            if cv != null:
                h.set("Cookie", cv)
        if absolute and proxy.authorization() != null and not h.has("proxy-authorization"):
            h.set("Proxy-Authorization", proxy.authorization())
        if body != null or method == "POST" or method == "PUT" or method == "PATCH":
            b := body
            if b == null:
                b = ""
            h.set("Content-Length", str(_n.blen(b)))
        if self.keep_alive:
            h.set("Connection", "keep-alive")
        else:
            h.set("Connection", "close")
        for hook in self.hooks["request"]:
            hook(method, u.str(), h)
        target := u.target()
        if absolute:
            target = u.redacted().with_fragment(null).str()
        head := method + " " + target + " HTTP/1.1\r\n" + h.to_text() + "\r\n"
        payload := head
        if body != null:
            payload = head + body
        attempt := 0
        while true:
            attempt += 1
            before := self.pool.reused
            conn := self.pool.acquire(key, () => self._open(u, proxy))
            was_reused := self.pool.reused > before
            start := _time.monotonic()
            status_line := null
            try:
                conn.write(payload, deadline.remaining(tos.write))
                status_line = conn.read_line(deadline.remaining(tos.read), MAX_HEADER_BYTES)
            catch e:
                self.pool.discard(key, conn)
                # connexion réutilisée fermée par le serveur pendant son inactivité : une nouvelle tentative
                if attempt == 1 and was_reused and (e.type == "NetworkError" or e.type == "TlsError"):
                    continue
                raise(e)
            if status_line == null:
                self.pool.discard(key, conn)
                if attempt == 1 and was_reused:
                    continue
                _fail("réponse vide de " + u.origin())
            self.requests_sent += 1
            return self._read_response(conn, key, method, u, status_line, tos, stream, deadline, start, h)

    func _read_response(conn, key, method, u, status_line, tos, stream, deadline, start, sent_headers):
        while true:
            parts := _s.split(status_line, " ")
            if len(parts) < 2 or not _s.starts_with(parts[0], "HTTP/") or len(parts[1]) != 3:
                self.pool.discard(key, conn)
                _fail("ligne de statut invalide « " + status_line + " » (" + u.origin() + ")")
            status := 0
            for ch in parts[1]:
                if ch < '0' or ch > '9':
                    self.pool.discard(key, conn)
                    _fail("statut non numérique « " + parts[1] + " »")
            status = to_int(parts[1])
            reason := ""
            if len(parts) > 2:
                reason = _s.join(" ", parts[2:len(parts)])
            headers := null
            try:
                headers = _read_headers(conn, deadline.remaining(tos.read))
            catch e:
                self.pool.discard(key, conn)
                raise(e)
            if status >= 100 and status < 200 and status != 101:
                status_line = conn.read_line(deadline.remaining(tos.read), MAX_HEADER_BYTES)
                if status_line == null:
                    self.pool.discard(key, conn)
                    _fail("connexion fermée après une réponse " + str(status))
                continue
            version := parts[0]
            r := Response(status, reason, version, headers, null, u.str(), method)
            r.elapsed = _time.monotonic() - start
            r.request_headers = sent_headers
            if self.cookies != null:
                self.cookies.extract(headers, u.str())
            # mode de lecture du corps
            mode := "close"
            length := 0
            if not _c.response_has_body(status, method):
                mode = "none"
            elif _s.contains(_s.lower(headers.get("transfer-encoding", "")), "chunked"):
                mode = "chunked"
            elif headers.has("content-length"):
                cl := headers.get_int("content-length")
                vals := headers.get_all("content-length")
                consistent := true
                for v in vals:
                    if _s.trim(v) != _s.trim(vals[0]):
                        consistent = false
                if cl == null or not consistent:
                    self.pool.discard(key, conn)
                    _fail("Content-Length invalide « " + headers.get("content-length") + " »")
                if self.max_body != null and cl > self.max_body:
                    self.pool.discard(key, conn)
                    _fail("corps annoncé trop grand (" + str(cl) + " octets, limite " + str(self.max_body) + ")")
                mode = "length"
                length = cl
            conn_hdr := _s.lower(headers.get("connection", ""))
            reusable := self.keep_alive and mode != "close" and not _s.contains(conn_hdr, "close") and (version != "HTTP/1.0" or _s.contains(conn_hdr, "keep-alive"))
            reader := _BodyReader(conn, mode, length, deadline.remaining(tos.read), self.max_body)
            pool := self.pool
            release := (ok) => _release_conn(pool, key, conn, ok and reusable)
            if stream:
                r._reader = reader
                r._release = release
                if reader.done:
                    r._end_stream(true)
                    r.body = ""
            else:
                raw := ""
                try:
                    raw = reader.read_all()
                catch e:
                    self.pool.discard(key, conn)
                    raise(e)
                release(true)
                r.body = _z.decode(raw, headers.get("content-encoding"), self.max_body)
            for hook in self.hooks["response"]:
                hook(r)
            return r

    # Raccourcis -------------------------------------------------------------------------------------------

    func get(url, params=null, headers=null, timeout=null, stream=false):
        return self.request("GET", url, params, null, null, headers, null, null, timeout, stream)

    func head(url, params=null, headers=null, timeout=null):
        return self.request("HEAD", url, params, null, null, headers, null, null, timeout)

    func options(url, headers=null, timeout=null):
        return self.request("OPTIONS", url, null, null, null, headers, null, null, timeout)

    func delete(url, params=null, headers=null, timeout=null):
        return self.request("DELETE", url, params, null, null, headers, null, null, timeout)

    # data : str, octets ou dict (formulaire) ; json : valeur JSON ; fields + files : multipart.
    func post(url, data=null, json=null, fields=null, files=null, headers=null, timeout=null, params=null):
        return self.request("POST", url, params, data, json, headers, files, fields, timeout)

    func put(url, data=null, json=null, headers=null, timeout=null, params=null):
        return self.request("PUT", url, params, data, json, headers, null, null, timeout)

    func patch(url, data=null, json=null, headers=null, timeout=null, params=null):
        return self.request("PATCH", url, params, data, json, headers, null, null, timeout)

    # Télécharge url dans un fichier (en flux) ; rend la Response (corps déjà écrit).
    func download(url, path, params=null, headers=null, timeout=null):
        r := self.request("GET", url, params, null, null, headers, null, null, timeout, true)
        if r.status >= 400:
            r.content()
            r.raise_for_status()
        r.save(path)
        return r

func _release_conn(pool, key, conn, reusable):
    if reusable:
        pool.release(key, conn)
    else:
        pool.discard(key, conn)

func _has_file(fields):
    if type(fields) == "dict":
        for k in keys(fields):
            if isinstance(fields[k], _mp.File):
                return true
    return false

func _read_headers(conn, timeout):
    h := _hh.Headers()
    total := 0
    count := 0
    last := null
    while true:
        line := conn.read_line(timeout, MAX_HEADER_BYTES)
        if line == null:
            _fail("connexion fermée au milieu des en-têtes")
        if line == "":
            return h
        total += _n.blen(line)
        count += 1
        if total > MAX_HEADER_BYTES or count > MAX_HEADERS:
            _fail("en-têtes de réponse trop longs")
        if (line[0] == ' ' or line[0] == '\t') and last != null:
            last[1] = last[1] + " " + _s.trim(line)
            continue
        c := _s.find(line, ":")
        if c <= 0:
            _fail("en-tête mal formé « " + line + " »")
        name := _s.trim(_s.substring(line, 0, c))
        append(h.entries, [name, _s.trim(_s.substring(line, c + 1, len(line)))])
        last = h.entries[len(h.entries) - 1]

# ---------------------------------------------------------------- raccourcis module

_SHARED := [null]

# Client partagé par les fonctions du module (créé au premier appel).
func shared_client():
    if _SHARED[0] == null:
        _SHARED[0] = Client()
    return _SHARED[0]

func request(method, url, params=null, data=null, json=null, headers=null, files=null, fields=null, timeout=null, stream=false):
    return shared_client().request(method, url, params, data, json, headers, files, fields, timeout, stream)

func get(url, params=null, headers=null, timeout=null):
    return shared_client().get(url, params, headers, timeout)

func head(url, params=null, headers=null, timeout=null):
    return shared_client().head(url, params, headers, timeout)

func delete(url, params=null, headers=null, timeout=null):
    return shared_client().delete(url, params, headers, timeout)

func options(url, headers=null, timeout=null):
    return shared_client().options(url, headers, timeout)

func post(url, data=null, json=null, fields=null, files=null, headers=null, timeout=null):
    return shared_client().post(url, data, json, fields, files, headers, timeout)

func put(url, data=null, json=null, headers=null, timeout=null):
    return shared_client().put(url, data, json, headers, timeout)

func patch(url, data=null, json=null, headers=null, timeout=null):
    return shared_client().patch(url, data, json, headers, timeout)

func download(url, path, params=null, headers=null, timeout=null):
    return shared_client().download(url, path, params, headers, timeout)

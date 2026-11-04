# ALEX STANDARD LIBRARY — web.client.http_client
#
# HttpClient : le client HTTP/1.1 complet — réserve de connexions persistantes, HTTPS vérifié, mandataires,
# redirections sûres, reprises avec attente exponentielle, délais (connexion, lecture, écriture, total),
# décompression, cookies (CookieJar, RFC 6265 simplifiée), URL de base, en-têtes par défaut.
#
#   use web.client.http_client as hc
#   use web.client.client_config as cc
#   c := hc.HttpClient(cc.ClientConfig().with_base_url("https://api.exemple.org/v1/").with_timeout(10))
#   r := c.get("notes", {"page": 2})                    # GET https://api.exemple.org/v1/notes?page=2
#   notes := c.get_json("notes")                        # corps JSON décodé (HttpStatusError si 4xx / 5xx)
#   r2 := c.post_json("notes", {"titre": "Été"})
#   r3 := c.build("DELETE", "notes/7").bearer(jeton).send()
#   c.download("https://exemple.org/rapport.pdf", "/tmp/rapport.pdf")
#   c.close()
#
# Les méthodes acceptent des arguments positionnels (les arguments nommés ne sont possibles que vers les
# fonctions de module : voir web.client, qui offre get(url, params=…, headers=…, json=…)).
#
# Erreurs : ClientError, ClientConnectionError, ClientTimeoutError, ClientTlsError, ClientProxyError,
# TooManyRedirects, ClientResponseError, HttpStatusError (raise_for_status / get_json).

from core use len, type, to_int
from collections use append, keys
use string as _s
use time as _time
use io as _io
use web.client.client_errors as _err
use web.client.client_config as _config
use web.client.client_request as _creq
use web.client.client_response as _cresp
use web.client.connection_pool as _pool
use web.client.response_reader as _reader
use web.client.request_builder as _builder
use web.client.timeout as _timeout
use web.client.proxy as _proxy
use web.http.protocol_writer as _writer
use web.http.response as _response
use web.http.date_header as _date
use web.http.method as _method
use web.url.url as _url
use web.url.path as _path

# ---------------------------------------------------------------- cookies

class CookieJar:
    func init():
        self.cookies = []     # dict : name, value, domain, host_only, path, expires, secure, http_only, same_site

    func _now():
        return _date.timestamp_now()

    func _purge():
        now := self._now()
        kept := []
        for c in self.cookies:
            if c["expires"] == null or c["expires"] > now:
                append(kept, c)
        self.cookies = kept

    # Mémorise les Set-Cookie d'une réponse à une requête vers url (Url).
    func store(url, response):
        host := _s.lower(url.hostname())
        for line in response.headers.get_all("set-cookie"):
            c := _response.parse_set_cookie(line)
            if c == null:
                continue
            a := c["attributes"]
            domain := host
            host_only := true
            if "domain" in a and a["domain"] != true and a["domain"] != "":
                d := _s.lower(a["domain"])
                if _s.starts_with(d, "."):
                    d = d[1:len(d)]
                if not _domain_match(host, d) or not _s.contains(d, "."):
                    continue      # domaine étranger ou de premier niveau : refusé
                domain = d
                host_only = false
            path := a["path"] if "path" in a and a["path"] != true and _s.starts_with(a["path"], "/") else _default_path(url.path)
            expires := null
            if "max-age" in a and a["max-age"] != true:
                ma := _int_or_null(a["max-age"])
                if ma != null:
                    expires = self._now() + ma if ma > 0 else 0
            elif "expires" in a and a["expires"] != true:
                expires = _date.parse(a["expires"])
            secure := "secure" in a
            if secure and url.scheme != "https":
                continue
            self._remove(c["name"], domain, path)
            if expires != null and expires <= self._now():
                continue
            append(self.cookies, {"name": c["name"], "value": c["value"], "domain": domain, "host_only": host_only, "path": path, "expires": expires, "secure": secure, "http_only": "httponly" in a, "same_site": a["samesite"] if "samesite" in a else null})

    func _remove(name, domain, path):
        kept := []
        for c in self.cookies:
            if not (c["name"] == name and c["domain"] == domain and c["path"] == path):
                append(kept, c)
        self.cookies = kept

    # Cookies à envoyer pour url : liste de dict, chemins les plus longs d'abord.
    func matching(url):
        self._purge()
        host := _s.lower(url.hostname())
        p := url.path if url.path != "" else "/"
        out := []
        for c in self.cookies:
            if c["host_only"]:
                if host != c["domain"]:
                    continue
            elif not _domain_match(host, c["domain"]):
                continue
            if not _path_match(p, c["path"]):
                continue
            if c["secure"] and url.scheme != "https":
                continue
            append(out, c)
        # tri par longueur de chemin décroissante (stable)
        i := 1
        while i < len(out):
            cur := out[i]
            j := i - 1
            while j >= 0 and len(out[j]["path"]) < len(cur["path"]):
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = cur
            i += 1
        return out

    # Valeur d'en-tête Cookie pour url, ou null.
    func header_for(url):
        parts := []
        for c in self.matching(url):
            append(parts, c["name"] + "=" + c["value"])
        if len(parts) == 0:
            return null
        return _s.join("; ", parts)

    func set(name, value, domain, path="/", secure=false):
        self._remove(name, _s.lower(domain), path)
        append(self.cookies, {"name": name, "value": value, "domain": _s.lower(domain), "host_only": false, "path": path, "expires": null, "secure": secure, "http_only": false, "same_site": null})

    func get(name, domain=null):
        for c in self.cookies:
            if c["name"] == name and (domain == null or c["domain"] == _s.lower(domain)):
                return c["value"]
        return null

    func clear(domain=null):
        if domain == null:
            self.cookies = []
            return
        kept := []
        for c in self.cookies:
            if c["domain"] != _s.lower(domain):
                append(kept, c)
        self.cookies = kept

    func size():
        self._purge()
        return len(self.cookies)

    # dict nom -> valeur (tous domaines).
    func to_dict():
        self._purge()
        out := {}
        for c in self.cookies:
            out[c["name"]] = c["value"]
        return out

func _int_or_null(text):
    t := _s.trim(str(text))
    neg := false
    if _s.starts_with(t, "-"):
        neg = true
        t = t[1:len(t)]
    if t == "":
        return null
    n := 0
    for c in t:
        if c < '0' or c > '9':
            return null
        n = n * 10 + (_s.ord(c) - 48)
    return -n if neg else n

func _domain_match(host, domain):
    return host == domain or _s.ends_with(host, "." + domain)

func _path_match(request_path, cookie_path):
    if request_path == cookie_path:
        return true
    if _s.starts_with(request_path, cookie_path):
        return _s.ends_with(cookie_path, "/") or request_path[len(cookie_path)] == '/'
    return false

func _default_path(path):
    if path == "" or not _s.starts_with(path, "/"):
        return "/"
    i := len(path) - 1
    while i > 0 and path[i] != '/':
        i -= 1
    if i == 0:
        return "/"
    return path[0:i]

# ---------------------------------------------------------------- client

class HttpClient:
    func init(config=null):
        self.config = config if config != null else _config.ClientConfig()
        c := self.config
        self.pool = _pool.ConnectionPool(c.max_connections_per_host, c.max_idle_connections, c.idle_timeout)
        self.reader = _reader.ResponseReader(c.max_response_size, c.max_header_bytes, c.decompress)
        self.cookies = CookieJar()
        self.closed = false
        self.requests_sent = 0
        self.hooks = []            # fonctions (requête, réponse) appelées après chaque échange (journal, mesures)

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.close()

    func close():
        self.pool.close_all()
        self.closed = true

    func stats():
        s := self.pool.stats()
        s["requests"] = self.requests_sent
        s["cookies"] = self.cookies.size()
        return s

    # Ajoute une fonction appelée avec (ClientRequest, ClientResponse) après chaque échange.
    func add_hook(fn):
        append(self.hooks, fn)
        return self

    # URL absolue (Url) : résolue contre base_url si relative.
    func resolve_url(u):
        if type(u) != "str":
            return u
        if self.config.base_url != null:
            return _url.parse(u, self.config.base_url)
        return _url.parse(u)

    func build(method, url):
        return _builder.RequestBuilder(self, method, url)

    # ---------------------------------------------------------------- raccourcis

    # Requête générique : body (str), sinon json_value (valeur JSON), sinon form (dict de formulaire).
    func request(method, url, params=null, headers=null, body=null, json_value=null, form=null, timeout=null):
        r := _creq.ClientRequest(method, self.resolve_url(url), headers, null, params, timeout)
        if body != null:
            r.set_body(body)
        elif json_value != null:
            r.set_json(json_value)
        elif form != null:
            r.set_form(form)
        return self.send(r)

    func get(url, params=null, headers=null):
        return self.request("GET", url, params, headers)

    func head(url, params=null, headers=null):
        return self.request("HEAD", url, params, headers)

    func delete(url, params=null, headers=null):
        return self.request("DELETE", url, params, headers)

    func options(url, headers=null):
        return self.request("OPTIONS", url, null, headers)

    func post(url, body=null, content_type=null, headers=null):
        r := _creq.ClientRequest("POST", self.resolve_url(url), headers)
        r.set_body(body if body != null else "", content_type)
        return self.send(r)

    func put(url, body=null, content_type=null, headers=null):
        r := _creq.ClientRequest("PUT", self.resolve_url(url), headers)
        r.set_body(body if body != null else "", content_type)
        return self.send(r)

    func patch(url, body=null, content_type=null, headers=null):
        r := _creq.ClientRequest("PATCH", self.resolve_url(url), headers)
        r.set_body(body if body != null else "", content_type)
        return self.send(r)

    func post_json(url, value, headers=null):
        return self.request("POST", url, null, headers, null, value)

    func put_json(url, value, headers=null):
        return self.request("PUT", url, null, headers, null, value)

    func patch_json(url, value, headers=null):
        return self.request("PATCH", url, null, headers, null, value)

    func post_form(url, data, headers=null):
        return self.request("POST", url, null, headers, null, null, data)

    # Envoi multipart/form-data : fields (dict) et files (liste de (champ, nom, contenu, type)).
    func post_multipart(url, fields=null, files=null, headers=null):
        r := _creq.ClientRequest("POST", self.resolve_url(url), headers)
        r.set_multipart(fields, files)
        return self.send(r)

    # Corps JSON décodé d'un GET ; HttpStatusError si le statut est une erreur.
    func get_json(url, params=null, headers=null):
        r := _creq.ClientRequest("GET", self.resolve_url(url), headers, null, params)
        r.headers.set_default("Accept", "application/json")
        return self.send(r).raise_for_status().json()

    # Télécharge url dans le fichier path (octets bruts) ; HttpStatusError si erreur ; renvoie la réponse.
    func download(url, path, params=null, headers=null):
        resp := self.get(url, params, headers).raise_for_status()
        _io.write_bytes(path, _s.byte_unpack(resp.body))
        return resp

    # ---------------------------------------------------------------- envoi

    func _prepare(req):
        c := self.config
        for e in c.headers.entries:
            if not req.headers.has(e[0]):
                req.headers.add(e[0], e[1])
        if c.user_agent != null and c.user_agent != false and not req.headers.has("user-agent"):
            req.headers.set("User-Agent", c.user_agent)
        if not req.headers.has("accept"):
            req.headers.set("Accept", "*/*")
        if c.decompress and not req.headers.has("accept-encoding"):
            req.headers.set("Accept-Encoding", "gzip, deflate")
        if c.cookies and not req.headers.has("cookie"):
            ck := self.cookies.header_for(req.url)
            if ck != null:
                req.headers.set("Cookie", ck)

    # Envoie une ClientRequest : redirections et reprises comprises ; renvoie la ClientResponse.
    func send(req):
        if self.closed:
            _err.client_error("HttpClient.send", "client fermé")
        t := self.config.timeout if req.timeout == null else _timeout.from_value(req.timeout)
        deadline := _timeout.Deadline(t.total)
        history := []
        current := req
        while true:
            self._prepare(current)
            resp := self._send_with_retries(current, t, deadline)
            if self.config.cookies:
                self.cookies.store(current.url, resp)
            for h in self.hooks:
                h(current, resp)
            nxt := self.config.redirect.next_request(current, resp, history)
            if nxt == null:
                resp.history = history
                resp.elapsed = deadline.elapsed()
                if self.config.raise_for_status:
                    resp.raise_for_status()
                return resp
            append(history, resp)
            nxt.headers.remove("cookie")
            current = nxt

    func _send_with_retries(req, t, deadline):
        policy := self.config.retry
        attempt := 0
        while true:
            resp := null
            try:
                resp = self._send_once(req, t, deadline)
            catch e:
                if policy.should_retry_error(req.method, e, attempt) and not deadline.expired():
                    attempt += 1
                    self._sleep(policy.delay(attempt), deadline)
                    continue
                raise(e)
            if policy.should_retry_status(req.method, resp.status, attempt) and not deadline.expired():
                attempt += 1
                req.attempt = attempt
                self._sleep(policy.delay(attempt, resp), deadline)
                continue
            return resp

    func _sleep(seconds, deadline):
        s := deadline.cap(seconds)
        if s != null and s > 0:
            _time.sleep(s)

    func _proxy_for(req):
        p := self.config.proxy
        if p == null:
            return null
        return _proxy.select(req.url, p)

    # Un échange : connexion (réserve), envoi, lecture. Une connexion de réserve périmée (fermée par le serveur
    # pendant l'inactivité) est remplacée une fois, de façon transparente, pour une méthode idempotente.
    func _send_once(req, t, deadline):
        tries := 0
        while true:
            tries += 1
            deadline.check(req.url.redacted())
            proxy := self._proxy_for(req)
            ct := deadline.cap(t.connect)
            open_timeout := _timeout.Timeout(ct if ct != null else false)    # seul le délai de connexion sert
            conn := self.pool.acquire(req.url.scheme, req.url.hostname(), req.url.effective_port(), self.config.tls, open_timeout, proxy)
            reused := conn.reused
            hreq := req.to_http(conn.needs_absolute_target())
            if conn.needs_absolute_target() and proxy.authorization() != null:
                hreq.headers.set("Proxy-Authorization", proxy.authorization())
            if not self.config.keep_alive:
                hreq.headers.set("Connection", "close")
            wire := _writer.write_request(hreq)
            result := null
            try:
                conn.send(wire, deadline.cap(t.write))
                conn.requests += 1
                self.requests_sent += 1
                result = self.reader.read(conn, req.method, t.read, deadline)
            catch e:
                self.pool.discard(conn)
                if reused and tries == 1 and _method.is_idempotent(req.method) and (e.type == _err.CONNECTION):
                    continue
                raise(e)
            if result.stale:
                self.pool.discard(conn)
                if reused and tries == 1 and _method.is_idempotent(req.method):
                    continue
                _err.connection_error("HttpClient", req.url.redacted() + " : le serveur a fermé la connexion sans répondre")
            if result.reusable and self.config.keep_alive:
                self.pool.release(conn)
            else:
                self.pool.discard(conn)
            resp := _cresp.from_response(result.response, req, req.url)
            return resp

func client(config=null):
    return HttpClient(config)

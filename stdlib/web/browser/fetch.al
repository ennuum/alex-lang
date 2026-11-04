# ALEX STANDARD LIBRARY — web.browser.fetch
#
# fetch() du navigateur simulé, ASYNCHRONE (promesses de web.browser.timers) : URL data: et blob:,
# réponses SIMULÉES (mock d'URL ou de chemin), serveurs ALEX EN PROCESSUS (un web.server Router par origine,
# appelé directement sans réseau), et réseau réel facultatif (web.client) ; règles d'origine (same-origin,
# CORS avec Access-Control-Allow-Origin, no-cors -> réponse opaque), cookies (credentials), redirections
# (follow, error, manual), annulation par AbortSignal, latence simulée et journal des requêtes.
#
#   use web.browser.fetch as ft
#   net := ft.Network(loop)
#   net.mock("https://api.exemple.org/notes", (req) => {"notes": [1, 2]})       # dict -> JSON
#   net.mock("/bonjour", (req) => "Bonjour")                                    # chemin, toutes origines
#   net.route("https://app.exemple.org", router)                                # web.server Router
#   p := ft.fetch(net, "https://api.exemple.org/notes")
#   r := p.wait()                       # Response
#   r.json().wait()["notes"]            # [1, 2]
#   net.log                             # [(GET, https://api.exemple.org/notes, 200)]
#   net.allow_network = true            # requêtes réelles par web.client (désactivées par défaut)
#
# Erreurs (rejets) : TypeError « Failed to fetch » (réseau, CORS, URL), AbortError (annulation).

from core use len, type
from collections use append, keys
use string as _s
use json as _json
use web.url.url as _url
use web.http.request as _hreq
use web.http.headers as _hh
use web.browser.browser_errors as _err
use web.browser.timers as _tm
use web.browser.request as _rq
use web.browser.response as _rs
use web.browser.blob as _blob
use web.browser.object_url as _ou
use web.client.http_client as _http_client

class _JarResponse:
    func init(set_cookies):
        self.headers = _hh.Headers()
        for c in set_cookies:
            self.headers.add("Set-Cookie", c)

class Network:
    func init(loop=null, cookie_jar=null):
        self.loop = loop if loop != null else _tm.default_loop()
        self.cookie_jar = cookie_jar
        self.mocks = []              # (méthode, motif, gestionnaire)
        self.routers = {}            # origine -> Router web.server
        self.client = null
        self.allow_network = false
        self.latency = 0             # ms simulées par requête
        self.offline = false
        self.log = []                # (méthode, URL, statut ou nom d'erreur)
        self.requests = []           # Request envoyées (dernière à la fin)
        self.max_redirects = 20

    # Réponse simulée : pattern = URL exacte, URL terminée par « * » (préfixe), ou chemin « /… » (toutes
    # origines) ; handler(Request) -> Response, dict / liste (JSON), str (texte), (statut, corps) ou null (404).
    func mock(pattern, handler, method="*"):
        append(self.mocks, (_s.upper(method), str(pattern), handler))
        return self

    func clear_mocks():
        self.mocks = []

    func route(origin, router):
        self.routers[_s.lower(_s.trim(str(origin)))] = router
        return self

    func _find_mock(method, u):
        href := u.href()
        path := u.path
        for m in self.mocks:
            if m[0] != "*" and m[0] != method:
                continue
            p := m[1]
            if _s.ends_with(p, "*"):
                pre := p[0:len(p) - 1]
                if _s.starts_with(href, pre) or (_s.starts_with(pre, "/") and _s.starts_with(path, pre)):
                    return m[2]
            elif p == href or (_s.starts_with(p, "/") and (p == path or p == path + ("?" + u.query if u.query != null else ""))):
                return m[2]
        return null

func _to_response(v, loop, u):
    if isinstance(v, _rs.Response):
        return v
    if v == null:
        return _rs.Response("Not Found", {"status": 404}, loop)
    if type(v) == "dict" or type(v) == "list":
        return _rs.json_response(v, null, loop)
    if type(v) == "tuple" and len(v) >= 2:
        r := _to_response(v[1], loop, u)
        r.status = v[0]
        r.ok = v[0] >= 200 and v[0] <= 299
        r.status_text = ""
        if len(v) > 2:
            for k in keys(v[2]):
                r.headers.set(k, v[2][k])
        return r
    if type(v) == "str":
        return _rs.Response(v, {"status": 200}, loop)
    try:
        return _rs.from_http(v, u.href(), false, loop)
    catch e:
        _err.type_error("fetch", "réponse simulée invalide")

# Contexte d'appel : origine du document, URL de base, cookies, registre d'objets.
class FetchContext:
    func init(base_url=null, cookie_jar=null, origin=null):
        self.base_url = base_url
        self.cookie_jar = cookie_jar
        self.origin = origin

func _origin_of(u):
    try:
        return u.origin()
    catch e:
        return "null"

func _http_request(req, u, cookie):
    h := _hh.Headers()
    for p in req.headers.entries():
        h.add(p[0], p[1])
    if not h.has("host") and u.host != null:
        h.set("Host", u.host_port())
    if cookie != null:
        h.set("Cookie", cookie)
    target := u.path if u.path != "" else "/"
    if u.query != null:
        target = target + "?" + u.query
    body := req.body_text()
    return _hreq.Request(req.method, target, h, body)

# Un échange (sans redirection) : renvoie une Response (ou lève TypeError).
func _exchange(net, req, u, ctx):
    if net.offline:
        _err.network_error("fetch", "Failed to fetch (hors ligne)")
    scheme := u.scheme
    if scheme == "data":
        b := _blob.from_data_url(u.href())
        return _rs.Response(b, {"status": 200, "headers": {"Content-Type": b.type}, "url": u.href()}, net.loop)
    if scheme == "blob":
        b := _ou.resolve(u.href())
        if b == null:
            _err.network_error("fetch", "Failed to fetch (URL blob: inconnue ou révoquée)")
        return _rs.Response(b, {"status": 200, "headers": {"Content-Type": b.type, "Content-Length": str(b.size)}, "url": u.href()}, net.loop)
    if scheme == "about":
        return _rs.Response("", {"status": 200, "url": u.href()}, net.loop)
    if scheme != "http" and scheme != "https":
        _err.network_error("fetch", "Failed to fetch (schéma « " + str(scheme) + " » non pris en charge)")
    jar := ctx.cookie_jar if ctx != null and ctx.cookie_jar != null else net.cookie_jar
    same := ctx == null or ctx.origin == null or ctx.origin == _origin_of(u)
    send_cookies := req.credentials == "include" or (req.credentials == "same-origin" and same)
    cookie := jar.header_for(u) if jar != null and send_cookies else null
    handler := net._find_mock(req.method, u)
    resp := null
    if handler != null:
        resp = _to_response(handler(req), net.loop, u)
    else:
        origin := _origin_of(u)
        if origin in net.routers:
            hr := _http_request(req, u, cookie)
            resp = _rs.from_http(net.routers[origin].dispatch(hr), u.href(), false, net.loop)
        elif net.allow_network:
            resp = _real(net, req, u, cookie)
        else:
            _err.network_error("fetch", "Failed to fetch (réseau désactivé : " + u.href() + ")")
    if jar != null and send_cookies:
        sc := resp.headers.get_set_cookie()
        if len(sc) > 0:
            jar.store(u, _JarResponse(sc))
    return resp

func _real(net, req, u, cookie):
    use_client := net.client
    if use_client == null:
        use_client = _http_client.HttpClient()
        net.client = use_client
    h := {}
    for p in req.headers.entries():
        h[p[0]] = p[1]
    if cookie != null:
        h["Cookie"] = cookie
    body := req.body_text() if req.body_bytes != null else null
    try:
        r := use_client.request(req.method, u.href(), null, h, body)
        return _rs.from_http(r, u.href(), false, net.loop)
    catch e:
        _err.network_error("fetch", "Failed to fetch (" + str(e.type) + " : " + str(e.message) + ")")

# Applique les règles CORS au résultat d'une requête d'une autre origine.
func _cors(req, resp, ctx, u):
    if ctx == null or ctx.origin == null or ctx.origin == _origin_of(u) or u.scheme == "data":
        if resp.type == "default":
            resp.type = "basic"
        return resp
    if req.mode == "same-origin":
        _err.network_error("fetch", "Failed to fetch (mode same-origin, origine différente)")
    if req.mode == "no-cors":
        return _rs.opaque(resp.loop)
    allow := resp.headers.get("access-control-allow-origin")
    if allow == null or (allow != "*" and allow != ctx.origin):
        _err.network_error("fetch", "Failed to fetch (CORS : « " + ctx.origin + " » non autorisée par " + u.href() + ")")
    if req.credentials == "include":
        if allow == "*" or resp.headers.get("access-control-allow-credentials") != "true":
            _err.network_error("fetch", "Failed to fetch (CORS : informations d'identification non autorisées)")
    resp.type = "cors"
    return resp

func _resolve(input, ctx):
    t := input.url if isinstance(input, _rq.Request) else str(input)
    try:
        if ctx != null and ctx.base_url != null:
            return _url.parse(t, ctx.base_url)
        return _url.parse(t)
    catch e:
        _err.type_error("fetch", "URL invalide « " + t + " »")

func _perform(net, req, ctx):
    u := _resolve(req, ctx)
    redirected := false
    count := 0
    current := req
    while true:
        resp := _exchange(net, current, u, ctx)
        st := resp.status
        loc := resp.headers.get("location")
        if st in [301, 302, 303, 307, 308] and loc != null:
            if current.redirect == "error":
                _err.network_error("fetch", "Failed to fetch (redirection interdite)")
            if current.redirect == "manual":
                r := _rs.Response(null, {"status": 0, "type": "opaqueredirect", "url": u.href(), "_allow_any": true}, net.loop)
                r.ok = false
                return r
            count += 1
            if count > net.max_redirects:
                _err.network_error("fetch", "Failed to fetch (trop de redirections)")
            nu := _url.parse(loc, u)
            method := current.method
            body := current.body_bytes
            if st == 303 and method != "HEAD" or ((st == 301 or st == 302) and method == "POST"):
                method = "GET" if method != "HEAD" else "HEAD"
                body = null
            o := {"method": method, "headers": current.headers, "mode": current.mode, "credentials": current.credentials, "redirect": current.redirect, "signal": current.signal}
            if body != null:
                o["body"] = body
            current = _rq.Request(nu.href(), o, net.loop)
            u = nu
            redirected = true
            continue
        resp.url = u.href()
        resp.redirected = redirected
        return _cors(current, resp, ctx, u)

# fetch(input, init) -> Promise de Response (rejet TypeError pour un échec réseau, AbortError à l'annulation).
func fetch(net, input, init_value=null, ctx=null):
    loop := net.loop
    p := _tm.Promise(loop)
    req := null
    try:
        req = input if isinstance(input, _rq.Request) and init_value == null else _rq.Request(input, init_value, loop)
    catch e:
        p.reject(_err.ErrorValue(str(e.type), str(e.message)))
        return p
    sig := req.signal
    if sig != null and sig.aborted:
        p.reject(sig.reason)
        append(net.log, (req.method, req.url, "AbortError"))
        return p
    append(net.requests, req)
    state := {"done": false}
    if sig != null:
        sig.on_abort((reason) => _abort_pending(p, state, reason, net, req))
    loop.set_timeout(() => _complete(net, req, ctx, p, state), net.latency)
    return p

func _abort_pending(p, state, reason, net, req):
    if state["done"]:
        return
    state["done"] = true
    append(net.log, (req.method, req.url, "AbortError"))
    p.reject(reason)

func _complete(net, req, ctx, p, state):
    if state["done"]:
        return
    try:
        r := _perform(net, req, ctx)
        state["done"] = true
        append(net.log, (req.method, r.url if r.url != "" else req.url, r.status))
        p.resolve(r)
    catch e:
        state["done"] = true
        append(net.log, (req.method, req.url, str(e.type)))
        p.reject(_err.ErrorValue(str(e.type), str(e.message)))

# navigator.sendBeacon : POST sans attendre de réponse ; renvoie true si la requête est mise en file.
func send_beacon(net, url, data=null, ctx=null):
    o := {"method": "POST", "keepalive": true, "credentials": "include"}
    if data != null:
        o["body"] = data
    fetch(net, url, o, ctx)
    return true

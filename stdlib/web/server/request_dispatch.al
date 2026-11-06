# ALEX STANDARD LIBRARY — web.server.request_dispatch
#
# Router : aiguillage des requêtes vers les gestionnaires — routes avec paramètres typés, montage de sous-routeurs
# et de dossiers statiques, intergiciels (middleware), gestion des erreurs, et intergiciels prêts à l'emploi
# (journal, CORS, en-têtes de sécurité, identifiant de requête, authentification Basic, limitation de débit,
# compression).
#
#   use web.server.request_dispatch as rd
#   app := rd.Router()
#   app.get("/", (req) => "<h1>Accueil</h1>")                          # str commençant par « < » : HTML
#   app.get("/articles/{id:int}", voir_article, "article")            # nommée : app.url_for("article", {"id": 7})
#   app.post("/articles", (req) => (req.json(), 201))                  # (corps, statut) ; dict / list : JSON
#   app.get("/fichiers/{chemin:path}", (req) => req.route_params["chemin"])
#   app.static("/static", "public")                                    # web.server.static_files
#   app.mount("/api/v2", autre_routeur)
#   app.middleware(rd.logger())                                        # intergiciel : fn(req, suivant)
#   app.middleware(rd.cors(["https://exemple.org"]))
#   app.on_error(404, (req, status, message) => "<h1>Introuvable</h1>")
#   reponse := app.dispatch(requete)                                   # toujours une Response
#
# Types de paramètres : str (défaut, un segment), int, float, slug ([a-z0-9-]+), uuid, path (tout le reste, « / »
# compris ; dernier segment seulement). Un « * » final équivaut à {path:path}.
# Résultats acceptés d'un gestionnaire : Response, str, dict / list (JSON), (corps, statut[, en-têtes]), int
# (statut seul), Document / Element web.html, null (204).
# HEAD est servi par la route GET ; OPTIONS répond 204 avec Allow ; méthode non permise : 405 avec Allow ;
# « /a/ » vs « /a » : redirection 308 vers la forme déclarée.
#
# Erreurs : RouteError (motif invalide, doublon), ServerError.

from core use len, type, to_int, to_float
from collections use append, keys
use string as _s
use time as _time
use asyncio as _aio
use network.compression as _z
use web.server.server_errors as _err
use web.server.static_files as _static
use web.server.request_parser as _rp
use web.server.websocket as _wsk
use web.http.response as _response
use web.http.status_code as _status
use web.http.header_value as _hv
use web.http.method as _method
use web.http.message_body as _mb
use web.http.request as _request
use web.html.body as _html_body
use web.html.html_serializer as _ser
use web.url.path as _path
use web.url.percent_encoding as _pe
use web.url.path_segment as _seg

const PARAM_TYPES := ["str", "int", "float", "slug", "uuid", "path"]

# ---------------------------------------------------------------- motifs de route

class Route:
    func init(methods, pattern, handler, name=null):
        self.methods = methods          # liste de méthodes, ou ["*"]
        self.pattern = pattern
        self.handler = handler
        self.name = name
        self.parts = compile_pattern(pattern)   # liste de (kind, valeur, type) : ("lit", "articles") / ("param", "id", "int")
        self.trailing_slash = len(pattern) > 1 and _s.ends_with(pattern, "/")

    func allows(method):
        return "*" in self.methods or method in self.methods

    # Paramètres (dict) si les segments correspondent, sinon null.
    func match_segments(segments):
        params := {}
        i := 0
        n := len(self.parts)
        while i < n:
            p := self.parts[i]
            if p[0] == "param" and p[2] == "path":
                rest := segments[i:len(segments)]
                params[p[1]] = _s.join("/", rest)
                return params
            if i >= len(segments):
                return null
            seg := segments[i]
            if p[0] == "lit":
                if seg != p[1]:
                    return null
            else:
                v := convert(seg, p[2])
                if v == null:
                    return null
                params[p[1]] = v
            i += 1
        if i != len(segments):
            return null
        return params

    # Chemin pour des valeurs de paramètres (url_for).
    func build(values):
        out := []
        for p in self.parts:
            if p[0] == "lit":
                append(out, _seg.encode(p[1]))
            else:
                if not (p[1] in values):
                    _err.route_error("Route.build", "paramètre manquant « " + p[1] + " » pour " + self.pattern)
                v := str(values[p[1]])
                if p[2] == "path":
                    parts := []
                    for x in _s.split(v, "/"):
                        append(parts, _seg.encode(x))
                    append(out, _s.join("/", parts))
                else:
                    append(out, _seg.encode(v))
        path := "/" + _s.join("/", out)
        if self.trailing_slash and not _s.ends_with(path, "/"):
            path = path + "/"
        return path

# Motif -> liste de (« lit », texte, null) / (« param », nom, type).
func compile_pattern(pattern):
    fn := "request_dispatch.compile_pattern"
    if type(pattern) != "str" or not _s.starts_with(pattern, "/"):
        _err.route_error(fn, "le motif doit commencer par « / » (obtenu « " + str(pattern) + " »)")
    out := []
    names := []
    segs := _s.split(pattern[1:len(pattern)], "/")
    k := 0
    for seg in segs:
        k += 1
        if seg == "" and k == len(segs):
            continue       # « / » final
        if seg == "*":
            if k != len(segs):
                _err.route_error(fn, "« * » doit être le dernier segment de " + pattern)
            append(out, ("param", "path", "path"))
            continue
        if _s.starts_with(seg, "{") and _s.ends_with(seg, "}"):
            inner := seg[1:len(seg) - 1]
            name := inner
            kind := "str"
            c := _s.find(inner, ":")
            if c >= 0:
                name = inner[0:c]
                kind = inner[c + 1:len(inner)]
            if name == "" or not _is_ident(name):
                _err.route_error(fn, "nom de paramètre invalide « " + name + " » dans " + pattern)
            if not (kind in PARAM_TYPES):
                _err.route_error(fn, "type de paramètre inconnu « " + kind + " » dans " + pattern + " (" + _s.join(", ", PARAM_TYPES) + ")")
            if name in names:
                _err.route_error(fn, "paramètre « " + name + " » répété dans " + pattern)
            if kind == "path" and k != len(segs):
                _err.route_error(fn, "{" + name + ":path} doit être le dernier segment de " + pattern)
            append(names, name)
            append(out, ("param", name, kind))
        else:
            if _s.contains(seg, "{") or _s.contains(seg, "}"):
                _err.route_error(fn, "accolades dans un segment littéral « " + seg + " » de " + pattern)
            append(out, ("lit", _pe.decode(seg), null))
    return out

func _is_ident(t):
    for c in t:
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_'):
            return false
    return true

# Valeur convertie d'un segment, ou null s'il ne correspond pas au type.
func convert(seg, kind):
    if seg == "":
        return null
    if kind == "str" or kind == "path":
        return seg
    if kind == "int":
        t := seg
        if _s.starts_with(t, "-"):
            t = t[1:len(t)]
        if t == "" or len(t) > 18:
            return null
        for c in t:
            if c < '0' or c > '9':
                return null
        return to_int(seg)
    if kind == "float":
        dot := false
        t := seg
        if _s.starts_with(t, "-"):
            t = t[1:len(t)]
        if t == "":
            return null
        for c in t:
            if c == '.':
                if dot:
                    return null
                dot = true
            elif c < '0' or c > '9':
                return null
        return to_float(seg)
    if kind == "slug":
        for c in seg:
            if not ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-' or c == '_'):
                return null
        return seg
    if kind == "uuid":
        if len(seg) != 36:
            return null
        i := 0
        for c in _s.lower(seg):
            if i == 8 or i == 13 or i == 18 or i == 23:
                if c != '-':
                    return null
            elif not ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f')):
                return null
            i += 1
        return _s.lower(seg)
    return null

# Segments décodés du chemin de routage (« . » / « .. » résolus).
func path_segments(raw_path):
    p := _path.normalize(raw_path)
    out := []
    if p == "/" or p == "":
        return out
    parts := _s.split(p[1:len(p)], "/")
    k := 0
    for seg in parts:
        k += 1
        if seg == "" and k == len(parts):
            continue
        append(out, _pe.decode(seg))
    return out

# ---------------------------------------------------------------- résultats

# Response depuis le résultat d'un gestionnaire.
func to_response(result, req=null):
    if result == null:
        return _response.no_content()
    if _aio.is_future(result):
        _err.server_error("to_response", "réponse async reçue par un intergiciel synchrone qui la transforme : attendre (await) le résultat dans un intergiciel async, ou placer cet intergiciel autour de routes synchrones")
    if isinstance(result, _response.Response):
        return result
    t := type(result)
    if t == "str":
        s := _s.trim(result)
        if _s.starts_with(s, "<"):
            return _response.html(result)
        return _response.text(result)
    if t == "dict" or t == "list":
        return _response.json(result)
    if t == "int":
        return error_response(req, result)
    if t == "tuple":
        if len(result) < 2 or type(result[1]) != "int":
            _err.server_error("to_response", "tuple (corps, statut[, en-têtes]) attendu")
        r := to_response(result[0], req)
        r.with_status(result[1])
        if len(result) > 2 and result[2] != null:
            r.headers.replace_all(result[2])
        return r
    if t == "instance":
        try:
            nt := result.node_type
            if nt == "document" or nt == "element":
                return _response.html(_ser.serialize(result))
        catch e:
            ignored := e
    _err.server_error("to_response", "résultat de gestionnaire non pris en charge (" + t + ")")

# Réponse d'erreur négociée : HTML (navigateurs), JSON (API) ou texte.
func error_response(req, status, message=null):
    reason := _status.reason(status)
    if req != null:
        accept := req.headers.get("accept", null, true)
        if accept != null:
            best := _hv.best_match(accept, ["text/html", "application/json", "text/plain"])
            if best == "application/json":
                return _response.json({"error": reason, "status": status, "message": message}, status)
            if best == "text/html" and _hv.quality_of(accept, "text/html") > 0.0 and _s.contains(accept, "html"):
                doc := _html_body.error_page(status, reason, message)
                return _response.html(doc.to_html(), status)
    return _response.error(status, message)

# ---------------------------------------------------------------- routeur

class Mount:
    func init(prefix, target, kind):
        self.prefix = prefix              # segments décodés
        self.target = target              # Router, StaticFiles, ou fonction (req, sous_chemin)
        self.kind = kind                  # router, static, handler

class Router:
    func init():
        self.routes = []
        self.mounts = []
        self.middlewares = []
        self.error_handlers = {}
        self.names = {}
        self.debug = false
        self.errors = []                 # « Type : message » des exceptions des gestionnaires (100 dernières)
        self.on_exception = null         # fn(req, erreur) appelée pour chaque exception de gestionnaire

    # Ajoute une route ; methods : str ou liste (« * » : toutes) ; name : pour url_for.
    func route(methods, pattern, handler, name=null):
        ms := methods if type(methods) == "list" or type(methods) == "tuple" else [methods]
        norm := []
        for m in ms:
            append(norm, m if m == "*" else _method.normalize(m))
        r := Route(norm, pattern, handler, name)
        for old in self.routes:
            if old.pattern == pattern:
                for m in norm:
                    if old.allows(m) and m != "*":
                        _err.route_error("Router.route", "route en double : " + m + " " + pattern)
        append(self.routes, r)
        if name != null:
            if name in self.names:
                _err.route_error("Router.route", "nom de route en double « " + name + " »")
            self.names[name] = r
        return self

    func get(pattern, handler, name=null):
        return self.route(["GET"], pattern, handler, name)

    func post(pattern, handler, name=null):
        return self.route(["POST"], pattern, handler, name)

    func put(pattern, handler, name=null):
        return self.route(["PUT"], pattern, handler, name)

    func patch(pattern, handler, name=null):
        return self.route(["PATCH"], pattern, handler, name)

    func delete(pattern, handler, name=null):
        return self.route(["DELETE"], pattern, handler, name)

    func options(pattern, handler, name=null):
        return self.route(["OPTIONS"], pattern, handler, name)

    func any(pattern, handler, name=null):
        return self.route(["*"], pattern, handler, name)

    # Point d'accès WebSocket (web.server.websocket) : handler(requête, session), de préférence async. Exige la
    # boucle async du serveur. protocols : sous-protocoles acceptés ; origins : origines permises (null : toutes).
    func websocket(pattern, handler, protocols=null, max_message=16777216, origins=null, name=null):
        return self.route(["GET"], pattern, (req) => _wsk.upgrade(req, handler, protocols, max_message, origins), name)

    # Monte un sous-routeur, un StaticFiles ou une fonction (req, sous_chemin) sous un préfixe.
    func mount(prefix, target):
        segs := path_segments(prefix)
        kind := "handler"
        if isinstance(target, Router):
            kind = "router"
        elif isinstance(target, _static.StaticFiles):
            kind = "static"
        append(self.mounts, Mount(segs, target, kind))
        # préfixes les plus longs d'abord
        i := len(self.mounts) - 1
        while i > 0 and len(self.mounts[i - 1].prefix) < len(self.mounts[i].prefix):
            tmp := self.mounts[i - 1]
            self.mounts[i - 1] = self.mounts[i]
            self.mounts[i] = tmp
            i -= 1
        return self

    # Sert le dossier directory sous prefix (voir web.server.static_files.StaticFiles).
    func static(prefix, directory, index=null, listing=false, max_age=0, fallback=null):
        return self.mount(prefix, _static.StaticFiles(directory, index, listing, max_age, fallback))

    # Intergiciel : fn(req, suivant) -> résultat ; suivant(req) appelle la suite de la chaîne. Le premier ajouté
    # est le plus extérieur.
    func middleware(middleware_fn):
        append(self.middlewares, middleware_fn)
        return self

    # Gestionnaire d'erreur pour un statut : fn(req, statut, message) -> résultat.
    func on_error(status, handler):
        self.error_handlers[status] = handler
        return self

    func url_for(name, values=null):
        if not (name in self.names):
            _err.route_error("Router.url_for", "route inconnue « " + name + " »")
        return self.names[name].build(values if values != null else {})

    # Liste (méthodes, motif, nom) pour inspection.
    func describe():
        out := []
        for r in self.routes:
            append(out, (r.methods, r.pattern, r.name))
        return out

    # ---------------------------------------------------------------- aiguillage

    # Réponse pour une requête (jamais d'exception : les erreurs deviennent des réponses).
    func dispatch(req):
        chain := (r) => self._route_request(r)
        i := len(self.middlewares) - 1
        while i >= 0:
            chain = _wrap(self.middlewares[i], chain)
            i -= 1
        result := null
        try:
            result = chain(req)
            if _aio.is_future(result):
                return self._finish_async(result, req)
            return to_response(result, req)
        catch e:
            return self._error_from_exception(req, e)

    # Gestionnaire async : tâche qui rend TOUJOURS une Response (les exceptions deviennent des réponses d'erreur,
    # comme pour un gestionnaire ordinaire). Le serveur l'attend sans bloquer les autres connexions.
    async func _finish_async(pending, req):
        try:
            return to_response(await pending, req)
        catch e:
            return self._error_from_exception(req, e)

    func _error_from_exception(req, e):
        if _err.is_abort(e):
            d := _err.abort_details(e)
            return self.error(req, d[0], d[1])
        if e.type == "JSONError":
            return self.error(req, 400, "JSON invalide")
        append(self.errors, str(e.type) + " : " + str(e.message))
        if len(self.errors) > 100:
            self.errors = self.errors[len(self.errors) - 100:len(self.errors)]
        if self.on_exception != null:
            try:
                self.on_exception(req, e)
            catch e2:
                ignored := e2
        msg := str(e.type) + " : " + str(e.message) if self.debug else null
        return self.error(req, 500, msg)

    # Réponse d'erreur (gestionnaire on_error si défini, sinon réponse négociée).
    func error(req, status, message=null):
        if status in self.error_handlers:
            try:
                r := to_response(self.error_handlers[status](req, status, message), req)
                if r.status == 200:
                    r.with_status(status)
                return r
            catch e:
                ignored := e
        return error_response(req, status, message)

    func _route_request(req):
        if _rp.has_bad_target(req):
            return self.error(req, 400, "cible de requête invalide")
        if req.target == "*":
            if req.method == "OPTIONS":
                r := _response.no_content()
                r.headers.set("Allow", "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS")
                return r
            return self.error(req, 400)
        return self._route_segments(req, path_segments(req.raw_path()), _s.ends_with(req.raw_path(), "/"))

    func _route_segments(req, segs, trailing):
        # montages
        for m in self.mounts:
            if _starts_with(segs, m.prefix):
                rest := segs[len(m.prefix):len(segs)]
                if m.kind == "router":
                    return m.target._route_segments(req, rest, trailing)
                elif m.kind == "static":
                    sub := _s.join("/", _encoded(rest))
                    if trailing and sub != "":
                        sub = sub + "/"
                    r := m.target.serve(req, sub)
                    if r != null:
                        return r
                else:
                    r := m.target(req, _s.join("/", rest))
                    if r != null:
                        return r
        allowed := []
        found := null
        get_route := null
        for r in self.routes:
            params := r.match_segments(segs)
            if params == null:
                continue
            if r.allows(req.method):
                found = (r, params)
                break
            for m in r.methods:
                if not (m in allowed):
                    append(allowed, m)
            if r.allows("GET") and get_route == null:
                get_route = (r, params)
        if found == null and req.method == "HEAD" and get_route != null:
            found = get_route
        if found != null:
            r := found[0]
            if r.trailing_slash != trailing and len(segs) > 0 and r.parts[len(r.parts) - 1][2] != "path":
                return _slash_redirect(req, r.trailing_slash)
            req.route_params = found[1]
            req.state["route"] = r.pattern
            if r.name != null:
                req.state["route_name"] = r.name
            return r.handler(req)
        if len(allowed) > 0:
            if req.method == "OPTIONS":
                resp := _response.no_content()
                resp.headers.set("Allow", _method.allow_header(allowed + ["OPTIONS"]))
                return resp
            resp := self.error(req, 405)
            resp.headers.set("Allow", _method.allow_header(allowed))
            return resp
        return self.error(req, 404)

func _wrap(mw, nxt):
    return (r) => mw(r, nxt)

func _starts_with(segs, prefix):
    if len(prefix) > len(segs):
        return false
    i := 0
    while i < len(prefix):
        if segs[i] != prefix[i]:
            return false
        i += 1
    return true

func _encoded(segs):
    out := []
    for s in segs:
        append(out, _seg.encode(s))
    return out

func _slash_redirect(req, want_trailing):
    p := req.raw_path()
    if want_trailing:
        p = p + "/"
    else:
        while len(p) > 1 and _s.ends_with(p, "/"):
            p = p[0:len(p) - 1]
    q := req.query_string()
    if q != null:
        p = p + "?" + q
    return _response.redirect(p, 308)

func router():
    return Router()

# ---------------------------------------------------------------- intergiciels

# Journal d'accès (format proche du « Common Log Format ») : sink(ligne) ; print par défaut.
func logger(sink=null):
    out := sink if sink != null else (line) => print(line)
    return (req, nxt) => _log(req, nxt, out)

func _log(req, nxt, out):
    t0 := _time.monotonic()
    r := to_response(nxt(req), req)
    ms := to_int((_time.monotonic() - t0) * 1000)
    who := req.remote_address[0] if req.remote_address != null else "-"
    size := r.body_size()
    out(who + " \"" + req.method + " " + req.target + " " + req.version + "\" " + str(r.status) + " " + (str(size) if size != null else "-") + " " + str(ms) + "ms")
    return r

# CORS (Cross-Origin Resource Sharing) : origins = liste d'origines autorisées ou ["*"] ; requêtes de
# pré-vérification (OPTIONS + Access-Control-Request-Method) traitées ici.
func cors(origins=null, methods=null, headers=null, credentials=false, max_age=600, expose=null):
    o := origins if origins != null else ["*"]
    ms := methods if methods != null else ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]
    hs := headers if headers != null else ["Content-Type", "Authorization"]
    return (req, nxt) => _cors(req, nxt, o, ms, hs, credentials, max_age, expose)

func _cors(req, nxt, origins, methods, headers, credentials, max_age, expose):
    origin := req.headers.get("origin")
    if origin == null:
        return nxt(req)
    allowed := "*" in origins or origin in origins
    if req.method == "OPTIONS" and req.headers.has("access-control-request-method"):
        r := _response.no_content()
        if allowed:
            r.headers.set("Access-Control-Allow-Origin", origin if credentials or not ("*" in origins) else "*")
            r.headers.set("Access-Control-Allow-Methods", _s.join(", ", methods))
            r.headers.set("Access-Control-Allow-Headers", _s.join(", ", headers))
            r.headers.set("Access-Control-Max-Age", str(max_age))
            if credentials:
                r.headers.set("Access-Control-Allow-Credentials", "true")
        r.headers.add("Vary", "Origin")
        return r
    r := to_response(nxt(req), req)
    if allowed:
        r.headers.set("Access-Control-Allow-Origin", origin if credentials or not ("*" in origins) else "*")
        if credentials:
            r.headers.set("Access-Control-Allow-Credentials", "true")
        if expose != null:
            r.headers.set("Access-Control-Expose-Headers", _s.join(", ", expose))
        r.headers.add("Vary", "Origin")
    return r

# En-têtes de sécurité recommandés ; hsts_seconds : HSTS (requêtes HTTPS seulement), false pour ne pas l'envoyer.
func security_headers(csp="default-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'", hsts_seconds=31536000):
    return (req, nxt) => _secure(req, nxt, csp, hsts_seconds)

func _secure(req, nxt, csp, hsts_seconds):
    r := to_response(nxt(req), req)
    defaults := {"X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", "Referrer-Policy": "strict-origin-when-cross-origin", "Cross-Origin-Opener-Policy": "same-origin", "Permissions-Policy": "camera=(), microphone=(), geolocation=()"}
    if csp != null and csp != false:
        defaults["Content-Security-Policy"] = csp
    if req.secure and hsts_seconds != false and hsts_seconds != null:
        defaults["Strict-Transport-Security"] = "max-age=" + str(hsts_seconds)
    for k in keys(defaults):
        if not r.headers.has(k):
            r.headers.set(k, defaults[k])
    return r

_request_counter := [0]

# Identifiant de requête (X-Request-Id) : repris du client s'il est fourni (et sûr), sinon généré ; renvoyé dans
# la réponse et rangé dans req.state["request_id"].
func request_id(header="X-Request-Id"):
    return (req, nxt) => _rid(req, nxt, header)

func _rid(req, nxt, header):
    id := req.headers.get(header)
    if id == null or len(id) > 128 or not _hv.is_token(id):
        _request_counter[0] = _request_counter[0] + 1
        id = _hex(to_int(_time.time() * 1000)) + "-" + str(_request_counter[0])
    req.state["request_id"] = id
    r := to_response(nxt(req), req)
    r.headers.set(header, id)
    return r

func _hex(v):
    digits := "0123456789abcdef"
    out := ""
    x := v
    if x == 0:
        return "0"
    while x > 0:
        out = str(digits[x & 15]) + out
        x = x >> 4
    return out

# Authentification Basic : check(utilisateur, mot_de_passe) -> bool ; 401 avec défi sinon ; utilisateur dans
# req.state["user"].
func basic_auth(check, realm="alex"):
    return (req, nxt) => _basic(req, nxt, check, realm)

func _basic(req, nxt, check, realm):
    cred := req.basic_auth()
    if cred != null and check(cred[0], cred[1]):
        req.state["user"] = cred[0]
        return nxt(req)
    r := error_response(req, 401)
    r.headers.set("WWW-Authenticate", "Basic realm=" + _hv.quote(realm) + ", charset=\"UTF-8\"")
    return r

# Limitation de débit par client (seau à jetons) : rate jetons par seconde, burst au plus ; 429 + Retry-After.
# key(req) -> clé (IP du client par défaut).
func rate_limit(rate, burst, key=null):
    buckets := {}
    k := key if key != null else (req) => (req.remote_address[0] if req.remote_address != null else "-")
    return (req, nxt) => _limit(req, nxt, buckets, rate, burst, k)

func _limit(req, nxt, buckets, rate, burst, key):
    id := key(req)
    now := _time.monotonic()
    b := buckets[id] if id in buckets else [to_float(burst), now]
    tokens := b[0] + (now - b[1]) * rate
    if tokens > burst:
        tokens = to_float(burst)
    if tokens < 1.0:
        buckets[id] = [tokens, now]
        r := error_response(req, 429)
        r.headers.set("Retry-After", str(to_int((1.0 - tokens) / rate) + 1))
        return r
    buckets[id] = [tokens - 1.0, now]
    if len(buckets) > 10000:
        for old in keys(buckets):
            if now - buckets[old][1] > 60:
                del buckets[old]
    return nxt(req)

# Compression gzip / deflate des réponses textuelles d'au moins min_size octets, si le client l'accepte.
func compress(min_size=1024, level=6):
    return (req, nxt) => _compress(req, nxt, min_size, level)

func _compress(req, nxt, min_size, level):
    r := to_response(nxt(req), req)
    if r.body_file != null or r.body_stream != null or r.headers.has("content-encoding") or r.status < 200 or r.status == 204 or r.status == 206 or r.status == 304:
        return r
    size := _s.byte_len(r.body)
    m := r.content_type()
    if size < min_size or m == null or not m.is_text():
        return r
    enc := null
    a := req.headers.get("accept-encoding", null, true)
    if a == null:
        return r
    if _hv.quality_of(a, "gzip") > 0.0:
        enc = "gzip"
    elif _hv.quality_of(a, "deflate") > 0.0:
        enc = "deflate"
    if enc == null:
        return r
    try:
        r.body = _z.encode(r.body, enc, level)
    catch e:
        return r
    r.headers.set("Content-Encoding", enc)
    r.headers.add("Vary", "Accept-Encoding")
    et := r.headers.get("etag")
    if et != null and not _s.starts_with(et, "W/"):
        r.headers.set("ETag", "W/" + et)
    return r

# En-tête Server-Timing (durée de traitement, visible dans les outils de développement des navigateurs).
func timing():
    return (req, nxt) => _timing(req, nxt)

func _timing(req, nxt):
    t0 := _time.monotonic()
    r := to_response(nxt(req), req)
    ms := (_time.monotonic() - t0) * 1000
    r.headers.add("Server-Timing", "app;dur=" + str(to_int(ms * 10) / 10.0))
    return r

# ALEX STANDARD LIBRARY — network.http_server
#
# Serveur HTTP/1.1 d'application : routage avec paramètres, intergiciels (middleware), connexions persistantes
# multiplexées, HTTPS, fichiers statiques (plages, ETag, 304), cookies, formulaires et multipart, CORS,
# compression, limites et protection contre les requêtes malformées, mise à niveau WebSocket.
#
#   app := App()                                   routes + intergiciels
#   app.get("/articles/{id:int}", handler)         handler(requête) -> Response, str, dict/list (JSON) ou null
#   app.use_middleware(intergiciel)                intergiciel(requête, suivant) -> Response
#   app.static("/static", "public")                fichiers d'un dossier
#   app.websocket("/ws", handler_ws)               handler_ws(requête, websocket) (network.websocket)
#   srv := Server(app, "127.0.0.1", 8080)          srv.serve_forever() / srv.serve(n) / srv.stop()
#
# Modèle d'exécution : un seul fil, une boucle d'événements (network.socket.wait) sur l'écouteur et toutes les
# connexions ouvertes ; une requête est lue et traitée entièrement avant de passer à la suivante (un gestionnaire
# lent retarde les autres clients). Keep-alive, pipelining et HTTP/1.0 sont pris en charge.
#
# Réponses d'erreur automatiques : 400 (requête malformée), 404, 405 (avec Allow), 408 (délai), 413 (corps trop
# grand), 414 (cible trop longue), 431 (en-têtes trop longs), 500 (exception du gestionnaire, message dans
# server.errors), 501 (Transfer-Encoding inconnu), 505 (version).
#
# Exemple
#   use network.http_server as hs
#   app := hs.App()
#   app.get("/", (req) => "Bonjour !")
#   app.get("/salut/{nom}", (req) => hs.json_response({"salut": req.params["nom"]}))
#   app.post("/echo", (req) => hs.text(req.text()))
#   app.use_middleware(hs.logger())
#   hs.Server(app, "127.0.0.1", 8080).serve_forever()

from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use json as _json
use io as _io
use os as _os
use time as _time
use network.socket as _sk
use network.tcp as _tcp
use network.tls as _tls
use network.url as _url
use network.http_headers as _hh
use network.http_cookies as _ck
use network.http_multipart as _mp
use network.compression as _z
use network.mime as _mime
use network.constants as _c
use network.security as _sec
use network.encoding as _enc
use network.websocket as _ws

const SERVER_NAME := "Alex-http_server/1.0"

# ---------------------------------------------------------------- requêtes

class Request:
    func init(method, target, version, headers, body, client, secure=false):
        self.method = method              # « GET »...
        self.target = target              # tel que reçu (« /chemin?requête »)
        self.version = version            # « HTTP/1.1 »
        self.headers = headers            # network.http_headers.Headers
        self.body = body                  # octets bruts (str)
        self.client = client              # (hôte, port) du client
        self.secure = secure
        self.params = {}                  # paramètres de la route (« {id} »)
        self.state = {}                   # données libres des intergiciels
        self.connection = null            # network.tcp.Connection (mise à niveau WebSocket)
        q := _s.find(target, "?")
        self.raw_path = target
        self.query_string = ""
        if q >= 0:
            self.raw_path = _s.substring(target, 0, q)
            self.query_string = _s.substring(target, q + 1, len(target))
        self.path = _enc.to_text(_url.unquote(self.raw_path))
        self.query = {}
        for p in _url.parse_qsl(self.query_string):
            self.query[p[0]] = p[1]
        self._form = null
        self._cookies = null

    func header(name, default=null):
        return self.headers.get(name, default)

    # Paramètre de la chaîne de requête (dernière valeur), ou default.
    func param(name, default=null):
        if contains_key(self.query, name):
            return self.query[name]
        return default

    func param_list(name):
        out := []
        for p in _url.parse_qsl(self.query_string):
            if p[0] == name:
                append(out, p[1])
        return out

    func content_type():
        return self.headers.content_type()

    func text():
        return _enc.decode_charset(self.body, self.headers.charset("utf-8"), "replace")

    func json():
        try:
            return _json.parse(self.text())
        catch e:
            raise("HttpError", "corps JSON invalide : " + e.message)

    # Champs d'un formulaire (urlencoded ou multipart) : dict nom -> valeur.
    func form():
        if self._form == null:
            ct := self.content_type()
            if ct != null and _s.starts_with(ct, "multipart/"):
                self._form = _mp.parse(self.body, self.headers.get("content-type"))
            else:
                f := _mp.FormData()
                for p in _url.parse_qsl(self.body):
                    append(f.fields, p)
                self._form = f
        return self._form.to_dict()

    # Fichier envoyé (multipart) dans le champ `name`, ou null.
    func file(name):
        self.form()
        return self._form.file(name)

    func files():
        self.form()
        return self._form.files

    # dict nom -> valeur des cookies reçus.
    func cookies():
        if self._cookies == null:
            self._cookies = _ck.parse_cookie_header(self.headers.get("cookie"))
        return self._cookies

    func cookie(name, default=null):
        c := self.cookies()
        if contains_key(c, name):
            return c[name]
        return default

    # Hôte demandé (en-tête Host, sans port).
    func host():
        h := self.headers.get("host", "")
        if _s.starts_with(h, "["):
            return _s.substring(h, 1, _s.find(h, "]"))
        c := _s.find(h, ":")
        if c >= 0:
            return _s.substring(h, 0, c)
        return h

    # URL complète de la requête (d'après Host).
    func url():
        scheme := "http"
        if self.secure:
            scheme = "https"
        return scheme + "://" + self.headers.get("host", "localhost") + self.target

    # Meilleur type accepté par le client parmi `offers` (en-tête Accept), ou null.
    func accepts(offers):
        return _hh.negotiate(self.headers.get("accept"), offers)

    func is_json():
        ct := self.content_type()
        return ct == "application/json" or (ct != null and _s.ends_with(ct, "+json"))

    func keep_alive():
        conn := _s.lower(self.headers.get("connection", ""))
        if self.version == "HTTP/1.0":
            return _s.contains(conn, "keep-alive")
        return not _s.contains(conn, "close")

    func wants_websocket():
        return _s.lower(self.headers.get("upgrade", "")) == "websocket" and _s.contains(_s.lower(self.headers.get("connection", "")), "upgrade")

# ---------------------------------------------------------------- réponses

class Response:
    func init(status=200, body="", headers=null, content_type=null):
        self.status = status
        self.reason = null
        self.headers = _hh.Headers(headers)
        self.body = body
        if body == null:
            self.body = ""
        elif type(body) == "list":
            self.body = _n.from_bytes(body)
        if content_type != null:
            self.headers.set("Content-Type", content_type)
        self.file_path = null         # corps lu depuis un fichier (envoi en morceaux)
        self.file_range = null        # [début, fin] dans le fichier
        self.upgrade = null           # fonction appelée après l'envoi (WebSocket)

    func header(name, default=null):
        return self.headers.get(name, default)

    func set_header(name, value):
        self.headers.set(name, value)
        return self

    # Pose un cookie (Cookie de network.http_cookies, ou nom + valeur + attributs).
    func set_cookie(name_or_cookie, value=null, max_age=null, path="/", domain=null, secure=false, http_only=true, same_site="Lax"):
        c := name_or_cookie
        if not isinstance(c, _ck.Cookie):
            c = _ck.Cookie(name_or_cookie, value, domain, path, null, max_age, secure, http_only, same_site, domain == null)
        self.headers.add("Set-Cookie", c.set_cookie_header())
        return self

    func delete_cookie(name, path="/", domain=null):
        self.headers.add("Set-Cookie", _ck.deletion_cookie(name, path, domain).set_cookie_header())
        return self

    func body_size():
        if self.file_path != null:
            return self.file_range[1] - self.file_range[0] + 1
        return _n.blen(self.body)

func text(body, status=200, headers=null):
    return Response(status, str(body), headers, "text/plain; charset=utf-8")

func html(body, status=200, headers=null):
    return Response(status, str(body), headers, "text/html; charset=utf-8")

func json_response(value, status=200, headers=null, indent=null):
    return Response(status, _json.stringify(value, indent), headers, "application/json")

func redirect(location, status=302):
    _hh.check_value("Location", location)
    return Response(status, "", {"Location": location})

func no_content():
    return Response(204, "")

# Réponse d'erreur (texte, ou JSON si le client préfère JSON).
func error(status, message=null, request=null):
    msg := message
    if msg == null:
        msg = _c.status_reason(status)
    if request != null and request.accepts(["text/plain", "application/json"]) == "application/json" and _s.contains(request.headers.get("accept", ""), "json"):
        return json_response({"error": msg, "status": status}, status)
    return text(msg + "\n", status)

# Réponse d'un fichier : type deviné, ETag et Last-Modified, 304 sur If-None-Match / If-Modified-Since, plages
# (Range -> 206, 416), HEAD. download_name : force le téléchargement sous ce nom.
func file_response(path, request=null, content_type=null, download_name=null, max_age=3600):
    if not _os.isfile(path):
        return error(404, null, request)
    size := _os.size(path)
    mtime := to_int(_os.mtime(path))
    etag := "\"" + _enc.hex_encode(_n.from_bytes([(size >> 24) & 255, (size >> 16) & 255, (size >> 8) & 255, size & 255])) + "-" + str(mtime) + "\""
    r := Response(200, "")
    ct := content_type
    if ct == null:
        ct = _mime.guess_type(path)
        if _mime.is_text_type(ct) and not _s.contains(ct, "charset"):
            ct += "; charset=utf-8"
    r.headers.set("Content-Type", ct)
    r.headers.set("ETag", etag)
    r.headers.set("Last-Modified", _hh.format_http_date(mtime))
    r.headers.set("Accept-Ranges", "bytes")
    if max_age != null:
        r.headers.set("Cache-Control", "public, max-age=" + str(max_age))
    if download_name != null:
        r.headers.set("Content-Disposition", _hh.content_disposition("attachment", download_name))
    if request != null:
        inm := request.header("if-none-match")
        if inm != null:
            if _hh.etag_matches(inm, etag):
                r.status = 304
                return r
        else:
            ims := _hh.parse_http_date(request.header("if-modified-since"))
            if ims != null and mtime <= ims:
                r.status = 304
                return r
        rng := request.header("range")
        if rng != null and (request.method == "GET" or request.method == "HEAD"):
            ir := request.header("if-range")
            if ir == null or ir == etag or _hh.parse_http_date(ir) == mtime:
                ranges := _hh.parse_range(rng, size)
                if ranges == null:
                    r416 := Response(416, "")
                    r416.headers.set("Content-Range", _hh.content_range(null, null, size))
                    return r416
                if len(ranges) == 1:
                    r.status = 206
                    r.headers.set("Content-Range", _hh.content_range(ranges[0][0], ranges[0][1], size))
                    r.file_path = path
                    r.file_range = ranges[0]
                    return r
                data := _n.from_bytes(_io.read_bytes(path))
                mb := _mp.byteranges(data, ranges, ct, size)
                r.status = 206
                r.body = mb[0]
                r.headers.set("Content-Type", mb[1])
                return r
    r.file_path = path
    r.file_range = [0, size - 1]
    if size == 0:
        r.file_path = null
        r.body = ""
    return r

func _make_response(value, request):
    if isinstance(value, Response):
        return value
    if value == null:
        return no_content()
    t := type(value)
    if t == "str":
        return text(value)
    if t == "dict" or t == "list":
        return json_response(value)
    if t == "tuple" and len(value) == 2:
        r := _make_response(value[0], request)
        r.status = value[1]
        return r
    return text(str(value))

# ---------------------------------------------------------------- routage

class Route:
    func init(methods, pattern, handler, name=null):
        self.methods = methods        # list[str] ou null (toutes)
        self.pattern = pattern
        self.handler = handler
        self.name = name
        self.segments = _split_pattern(pattern)

    # dict des paramètres si le chemin correspond, sinon null.
    func matches(path):
        parts := _split_path(path)
        params := {}
        i := 0
        for seg in self.segments:
            if seg[0] == "rest":
                rest := []
                while i < len(parts):
                    append(rest, parts[i])
                    i += 1
                params[seg[1]] = _s.join("/", rest)
                return params
            if i >= len(parts):
                return null
            p := parts[i]
            if seg[0] == "lit":
                if p != seg[1]:
                    return null
            else:
                v := _convert(p, seg[2])
                if v == null:
                    return null
                params[seg[1]] = v
            i += 1
        if i != len(parts):
            return null
        return params

    func allows(method):
        if self.methods == null:
            return true
        for m in self.methods:
            if m == method or (m == "GET" and method == "HEAD"):
                return true
        return false

func _split_path(path):
    out := []
    for p in _s.split(path, "/"):
        if p != "":
            append(out, p)
    if _s.ends_with(path, "/") and len(path) > 1:
        append(out, "")
    return out

# Segments d'un motif : ["lit", texte] / ["param", nom, type] / ["rest", nom].
func _split_pattern(pattern):
    out := []
    for p in _split_path(pattern):
        if _s.starts_with(p, "{") and _s.ends_with(p, "}"):
            inner := _s.substring(p, 1, len(p) - 1)
            if _s.ends_with(inner, "*"):
                append(out, ["rest", _s.substring(inner, 0, len(inner) - 1)])
                continue
            kind := "str"
            c := _s.find(inner, ":")
            if c >= 0:
                kind = _s.substring(inner, c + 1, len(inner))
                inner = _s.substring(inner, 0, c)
                if kind != "int" and kind != "str" and kind != "float" and kind != "slug" and kind != "uuid":
                    raise("ArgumentError", "http_server : type de paramètre inconnu « " + kind + " » (int, float, str, slug, uuid)")
            append(out, ["param", inner, kind])
        else:
            append(out, ["lit", _enc.to_text(_url.unquote(p))])
    return out

func _convert(p, kind):
    if kind == "str":
        return p
    if kind == "int":
        if p == "" or len(p) > 18:
            return null
        start := 0
        if p[0] == '-':
            start = 1
        if start >= len(p):
            return null
        for c in _s.substring(p, start, len(p)):
            if c < '0' or c > '9':
                return null
        return to_int(p)
    if kind == "float":
        return _to_float(p)
    if kind == "slug":
        for c in p:
            if not ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-' or c == '_'):
                return null
        return p
    if kind == "uuid":
        if len(p) != 36:
            return null
        i := 0
        for c in _s.lower(p):
            if i == 8 or i == 13 or i == 18 or i == 23:
                if c != '-':
                    return null
            elif not ((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f')):
                return null
            i += 1
        return _s.lower(p)
    return p

func _to_float(p):
    seen_digit := false
    for c in p:
        if c >= '0' and c <= '9':
            seen_digit = true
        elif c != '.' and c != '-' and c != '+' and c != 'e' and c != 'E':
            return null
    if not seen_digit:
        return null
    try:
        return to_float(p)
    catch e:
        return null

class App:
    func init():
        self.routes = []
        self.middleware = []
        self.not_found = null         # handler(requête) personnalisé pour 404
        self.on_error = null          # handler(requête, erreur) personnalisé pour 500

    # Ajoute une route. methods : str, liste ou null (toutes). pattern : « /a/{x}/{n:int}/{reste*} ».
    func route(methods, pattern, handler, name=null):
        ms := methods
        if type(methods) == "str":
            ms = [_s.upper(methods)]
        elif methods != null:
            ms = []
            for m in methods:
                append(ms, _s.upper(m))
        append(self.routes, Route(ms, pattern, handler, name))
        return self

    func get(pattern, handler):
        return self.route("GET", pattern, handler)

    func post(pattern, handler):
        return self.route("POST", pattern, handler)

    func put(pattern, handler):
        return self.route("PUT", pattern, handler)

    func patch(pattern, handler):
        return self.route("PATCH", pattern, handler)

    func delete(pattern, handler):
        return self.route("DELETE", pattern, handler)

    func options(pattern, handler):
        return self.route("OPTIONS", pattern, handler)

    func any(pattern, handler):
        return self.route(null, pattern, handler)

    # Intergiciel : mw(requête, suivant) où suivant(requête) produit la réponse de la suite de la chaîne.
    func use_middleware(mw):
        append(self.middleware, mw)
        return self

    # Fichiers d'un dossier sous un préfixe d'URL (« /static/css/a.css » -> dossier/css/a.css). index : fichier
    # servi pour un dossier. Les chemins qui sortiraient du dossier sont refusés (404).
    func static(prefix, directory, index="index.html", max_age=3600):
        p := prefix
        if _s.ends_with(p, "/"):
            p = _s.substring(p, 0, len(p) - 1)
        root := _os.absolute(directory)
        handler := (req) => _serve_static(req, root, index, max_age)
        self.route(["GET", "HEAD"], p + "/{path*}", handler)
        if p != "":
            self.route(["GET", "HEAD"], p, handler)
        return self

    # Mise à niveau WebSocket sur `pattern` : handler(requête, websocket) ; la connexion est fermée au retour.
    func websocket(pattern, handler, protocols=null, max_message=16777216, origins=null):
        h := (req) => _upgrade_websocket(req, handler, protocols, max_message, origins)
        return self.route("GET", pattern, h)

    # URL d'une route nommée avec ses paramètres.
    func url_for(name, params=null):
        for r in self.routes:
            if r.name == name:
                parts := []
                for seg in r.segments:
                    if seg[0] == "lit":
                        append(parts, _url.quote(seg[1], ""))
                    else:
                        append(parts, _url.quote(str(params[seg[1]]), "/"))
                return "/" + _s.join("/", parts)
        raise("ArgumentError", "http_server.url_for : route « " + str(name) + " » inconnue")

    func _dispatch(req):
        allowed := []
        for r in self.routes:
            params := r.matches(req.path)
            if params == null:
                continue
            if not r.allows(req.method):
                for m in r.methods:
                    append(allowed, m)
                continue
            req.params = params
            return _make_response(r.handler(req), req)
        if len(allowed) > 0:
            if req.method == "OPTIONS":
                resp := no_content()
                resp.headers.set("Allow", _s.join(", ", _unique(allowed + ["OPTIONS"])))
                return resp
            resp := error(405, null, req)
            resp.headers.set("Allow", _s.join(", ", _unique(allowed)))
            return resp
        if self.not_found != null:
            return _make_response(self.not_found(req), req)
        return error(404, "introuvable : " + req.path, req)

    # Réponse complète à une requête (intergiciels compris). Les exceptions deviennent des réponses 500.
    func handle(req):
        chain := self._chain(0)
        return chain(req)

    func _chain(i):
        if i >= len(self.middleware):
            return (req) => self._dispatch(req)
        mw := self.middleware[i]
        nxt := self._chain(i + 1)
        return (req) => _make_response(mw(req, nxt), req)

    func __call__(req):
        return self.handle(req)

func _unique(xs):
    out := []
    for x in xs:
        seen := false
        for y in out:
            if y == x:
                seen = true
        if not seen:
            append(out, x)
    return out

func _serve_static(req, root, index, max_age):
    rel := ""
    if contains_key(req.params, "path"):
        rel = req.params["path"]
    for seg in _s.split(_s.replace(rel, "\\", "/"), "/"):
        if seg == ".." or _s.contains(seg, "\x00"):
            return error(404, null, req)
    target := root
    if rel != "":
        target = _os.join(root, rel)
    full := _os.absolute(target)
    inside := _s.starts_with(full, root + "/")
    if not inside and _os.platform() == "windows":
        inside = _s.starts_with(full, root + "\\")
    if full != root and not inside:
        return error(404, null, req)
    if _os.isdir(full):
        if not _s.ends_with(req.path, "/"):
            return redirect(req.raw_path + "/", 301)
        full = _os.join(full, index)
    return file_response(full, req, null, null, max_age)

func _upgrade_websocket(req, handler, protocols, max_message, origins):
    if not req.wants_websocket():
        return error(426, "mise à niveau WebSocket attendue", req)
    key := req.header("sec-websocket-key")
    if key == null or req.header("sec-websocket-version") != "13":
        r := error(400, "poignée de main WebSocket invalide", req)
        r.headers.set("Sec-WebSocket-Version", "13")
        return r
    if origins != null:
        o := req.header("origin")
        ok := false
        for x in origins:
            if x == o:
                ok = true
        if not ok:
            return error(403, "origine refusée", req)
    chosen := null
    if protocols != null:
        for p in _hh.parse_list(req.header("sec-websocket-protocol")):
            for want in protocols:
                if chosen == null and p == want:
                    chosen = p
    r := Response(101, "")
    r.headers.set("Upgrade", "websocket")
    r.headers.set("Connection", "Upgrade")
    r.headers.set("Sec-WebSocket-Accept", _ws.accept_key(key))
    if chosen != null:
        r.headers.set("Sec-WebSocket-Protocol", chosen)
    r.upgrade = (conn) => _run_websocket(conn, req, handler, max_message, chosen)
    return r

func _run_websocket(conn, req, handler, max_message, protocol):
    ws := _ws.WebSocket(conn, false, max_message, protocol, req.url())
    try:
        handler(req, ws)
    catch e:
        ws.close(1011, "erreur interne")
        raise(e)
    if not ws.is_closed():
        ws.close()

# ---------------------------------------------------------------- intergiciels prêts à l'emploi

# Journal d'accès (format « commun » étendu) : sink(ligne) — print par défaut.
func logger(sink=null):
    out := sink
    if out == null:
        out = (line) => print(line)
    return (req, nxt) => _log_request(req, nxt, out)

func _log_request(req, nxt, out):
    start := _time.monotonic()
    r := _make_response(nxt(req), req)
    ms := to_int((_time.monotonic() - start) * 1000.0)
    out(req.client[0] + " \"" + req.method + " " + req.target + " " + req.version + "\" " + str(r.status) + " " + str(r.body_size()) + " " + str(ms) + "ms")
    return r

# CORS : origins (liste ou "*"), méthodes et en-têtes permis ; répond aux requêtes préalables (OPTIONS).
func cors(origins="*", methods=null, headers=null, credentials=false, max_age=600, expose=null):
    return (req, nxt) => _cors(req, nxt, origins, methods, headers, credentials, max_age, expose)

func _cors(req, nxt, origins, methods, headers, credentials, max_age, expose):
    origin := req.header("origin")
    allowed := null
    if origin != null:
        if origins == "*" and not credentials:
            allowed = "*"
        elif origins == "*":
            allowed = origin
        else:
            for o in origins:
                if o == origin:
                    allowed = origin
    if req.method == "OPTIONS" and origin != null and req.header("access-control-request-method") != null:
        r := no_content()
        if allowed != null:
            r.headers.set("Access-Control-Allow-Origin", allowed)
            ms := methods
            if ms == null:
                ms = ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]
            r.headers.set("Access-Control-Allow-Methods", _s.join(", ", ms))
            hs := headers
            if hs == null:
                hs = req.header("access-control-request-headers")
                if hs != null:
                    hs = _hh.parse_list(hs)
            if hs != null:
                r.headers.set("Access-Control-Allow-Headers", _s.join(", ", hs))
            if credentials:
                r.headers.set("Access-Control-Allow-Credentials", "true")
            r.headers.set("Access-Control-Max-Age", str(max_age))
            if allowed != "*":
                r.headers.set("Vary", "Origin")
        return r
    r := _make_response(nxt(req), req)
    if allowed != null:
        r.headers.set("Access-Control-Allow-Origin", allowed)
        if credentials:
            r.headers.set("Access-Control-Allow-Credentials", "true")
        if expose != null:
            r.headers.set("Access-Control-Expose-Headers", _s.join(", ", expose))
        if allowed != "*":
            r.headers.add("Vary", "Origin")
    return r

# Compression gzip / deflate des réponses textuelles d'au moins min_size octets si le client l'accepte.
func compress(min_size=512, level=6):
    return (req, nxt) => _compress(req, nxt, min_size, level)

func _compress(req, nxt, min_size, level):
    r := _make_response(nxt(req), req)
    if r.file_path != null and r.file_range != null and r.status == 200:
        size := r.body_size()
        if size >= min_size and size <= 16777216 and _z.should_compress(r.headers.get("content-type"), size, min_size):
            r.body = _n.from_bytes(_io.read_bytes(r.file_path))
            r.file_path = null
            r.file_range = null
    if r.headers.has("content-encoding") or r.file_path != null or r.status < 200 or r.status == 204 or r.status == 206 or r.status == 304:
        return r
    if not _z.should_compress(r.headers.get("content-type"), _n.blen(r.body), min_size):
        return r
    enc := _z.choose_encoding(req.header("accept-encoding"))
    if enc == null or enc == "identity":
        return r
    r.body = _z.encode(r.body, enc, level)
    r.headers.set("Content-Encoding", enc)
    r.headers.add("Vary", "Accept-Encoding")
    etag := r.headers.get("etag")
    if etag != null and not _s.starts_with(etag, "W/"):
        r.headers.set("ETag", "W/" + etag)
    return r

# En-têtes de sécurité (voir network.security.security_headers) ; HSTS seulement sur les requêtes HTTPS.
func security_headers(hsts_seconds=31536000, csp="default-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'"):
    return (req, nxt) => _secure(req, nxt, hsts_seconds, csp)

func _secure(req, nxt, hsts_seconds, csp):
    r := _make_response(nxt(req), req)
    hs := hsts_seconds
    if not req.secure:
        hs = null
    h := _sec.security_headers(hs, csp)
    for k in keys(h):
        if not r.headers.has(k):
            r.headers.set(k, h[k])
    return r

# Limitation de débit par adresse IP (seau à jetons) : 429 avec Retry-After au-delà.
func rate_limit(rate, burst, key=null):
    limiter := _sec.RateLimiter(rate, burst)
    k := key
    if k == null:
        k = (req) => req.client[0]
    return (req, nxt) => _limit(req, nxt, limiter, k)

func _limit(req, nxt, limiter, key):
    id := key(req)
    if not limiter.allow(id):
        r := error(429, "trop de requêtes", req)
        wait := limiter.retry_after(id)
        r.headers.set("Retry-After", str(to_int(wait) + 1))
        return r
    return nxt(req)

# Authentification Basic : check(utilisateur, mot_de_passe) -> bool ; 401 avec défi sinon. L'utilisateur
# authentifié est rangé dans req.state["user"].
func basic_auth(check, realm="alex"):
    return (req, nxt) => _basic(req, nxt, check, realm)

func _basic(req, nxt, check, realm):
    cred := _hh.parse_basic(req.header("authorization"))
    if cred != null and check(cred[0], cred[1]):
        req.state["user"] = cred[0]
        return nxt(req)
    r := error(401, "authentification requise", req)
    r.headers.set("WWW-Authenticate", "Basic realm=" + _hh.quote(realm) + ", charset=\"UTF-8\"")
    return r

# ---------------------------------------------------------------- serveur

class _Client:
    func init(conn, address, secure):
        self.conn = conn
        self.address = address
        self.secure = secure
        self.last_active = _time.monotonic()
        self.requests = 0

class Server:
    # app : App, ou fonction handler(requête). cert_file + key_file : HTTPS.
    func init(app, host="127.0.0.1", port=0, cert_file=null, key_file=null, max_body=104857600, max_header_bytes=65536, request_timeout=15.0, keep_alive_timeout=15.0, max_connections=256, max_requests_per_connection=1000, server_name=SERVER_NAME):
        self.app = app
        self.listener = _tcp.listen(host, port)
        self.secure = cert_file != null
        self.cert_file = cert_file
        self.key_file = key_file
        self.max_body = max_body
        self.max_header_bytes = max_header_bytes
        self.request_timeout = request_timeout
        self.keep_alive_timeout = keep_alive_timeout
        self.max_connections = max_connections
        self.max_requests_per_connection = max_requests_per_connection
        self.server_name = server_name
        self.clients = []
        self.running = false
        self.handled = 0
        self.errors = []          # « Type: message » des exceptions des gestionnaires
        self.rejected = 0         # poignées de main TLS refusées, requêtes malformées

    func port():
        return self.listener.port()

    func address():
        return self.listener.address()

    func url(path="/"):
        a := self.listener.address()
        scheme := "http"
        if self.secure:
            scheme = "https"
        return scheme + "://" + _sk.format_address(a[0], a[1]) + path

    func stop():
        self.running = false

    # Sert jusqu'à stop() (appelé par un gestionnaire, par exemple). poll : attente maximale d'un tour de boucle.
    func serve_forever(poll=0.5):
        self.running = true
        while self.running:
            self.step(poll)
        self.close_clients()

    # Sert jusqu'à avoir traité `count` requêtes de plus (ou jusqu'à stop()).
    func serve(count, poll=0.5):
        target := self.handled + count
        self.running = true
        while self.running and self.handled < target:
            self.step(poll)

    # Un tour de boucle : accepte les nouvelles connexions, traite les requêtes prêtes, ferme les inactives.
    func step(timeout=0.5):
        socks := [self.listener.socket]
        for c in self.clients:
            if _n.blen(c.conn.buffer) > 0 or (c.secure and c.conn.socket.pending() > 0):
                self._serve_client(c)
                return
            append(socks, _raw(c.conn.socket))
        ready := _sk.wait(socks, "read", timeout)
        for s in ready:
            if s == self.listener.socket:
                self._accept()
            else:
                for c in self.clients:
                    if _raw(c.conn.socket) == s:
                        self._serve_client(c)
        self._sweep()

    func _accept():
        r := null
        try:
            r = self.listener.socket.accept(0)
        catch e:
            return
        sock := r[0]
        address := (r[1], r[2])
        conn := null
        if self.secure:
            try:
                conn = _tcp.Connection(_tls.wrap_server(sock, self.cert_file, self.key_file, ["http/1.1"], self.request_timeout))
            catch e:
                sock.close()
                self.rejected += 1
                return
        else:
            conn = _tcp.Connection(sock)
        if len(self.clients) >= self.max_connections:
            self._evict_idle()
        append(self.clients, _Client(conn, address, self.secure))

    func _evict_idle():
        if len(self.clients) == 0:
            return
        oldest := self.clients[0]
        for c in self.clients:
            if c.last_active < oldest.last_active:
                oldest = c
        self._drop(oldest)

    func _drop(c):
        kept := []
        for x in self.clients:
            if x != c:
                append(kept, x)
        self.clients = kept
        try:
            c.conn.close()
        catch e:
            ignored := e

    func _sweep():
        now := _time.monotonic()
        for c in self.clients:
            if now - c.last_active > self.keep_alive_timeout:
                self._drop(c)

    func close_clients():
        for c in self.clients:
            try:
                c.conn.close()
            catch e:
                ignored := e
        self.clients = []

    func close():
        self.close_clients()
        self.listener.close()

    # Lit et traite les requêtes disponibles sur une connexion (pipelining compris).
    func _serve_client(c):
        while true:
            keep := self._one_request(c)
            c.last_active = _time.monotonic()
            if not keep:
                self._drop(c)
                return
            if _n.blen(c.conn.buffer) == 0:
                return

    func _send_error(conn, status, message):
        r := text(message + "\n", status)
        r.headers.set("Connection", "close")
        self._write(conn, "GET", r, false, "HTTP/1.1")

    # Traite une requête ; false : la connexion doit être fermée.
    func _one_request(c):
        conn := c.conn
        line := null
        try:
            line = conn.read_line(self.request_timeout, 8192)
        catch e:
            if e.type == "TimeoutError":
                self._send_error(conn, 408, "délai de requête dépassé")
                return false
            if e.type == "NetworkError" and _s.contains(e.message, "plus de"):
                self._send_error(conn, 414, "cible trop longue")
                self.rejected += 1
                return false
            return false
        if line == null:
            return false
        if line == "":
            # lignes vides tolérées avant une requête (RFC 9112 §2.2)
            return true
        parts := _s.split(line, " ")
        if len(parts) != 3 or not _s.starts_with(parts[2], "HTTP/1.") or not _hh.is_valid_name(parts[0]):
            if len(parts) == 3 and _s.starts_with(parts[2], "HTTP/"):
                self._send_error(conn, 505, "version HTTP non prise en charge")
            else:
                self._send_error(conn, 400, "ligne de requête invalide")
            self.rejected += 1
            return false
        method := parts[0]
        target := parts[1]
        version := parts[2]
        if not _s.starts_with(target, "/") and target != "*":
            # forme absolue (mandataire) : on n'en garde que le chemin
            try:
                u := _url.parse(target)
                target = u.target()
            catch e:
                self._send_error(conn, 400, "cible invalide")
                return false
        headers := null
        try:
            headers = _read_headers(conn, self.request_timeout, self.max_header_bytes)
        catch e:
            if e.type == "HttpError" and _s.contains(e.message, "trop"):
                self._send_error(conn, 431, "en-têtes trop longs")
            elif e.type == "TimeoutError":
                self._send_error(conn, 408, "délai de requête dépassé")
            else:
                self._send_error(conn, 400, "en-têtes invalides")
            self.rejected += 1
            return false
        if version == "HTTP/1.1" and not headers.has("host"):
            self._send_error(conn, 400, "en-tête Host manquant")
            self.rejected += 1
            return false
        # corps
        body := ""
        te := headers.get("transfer-encoding")
        if te != null:
            if _s.lower(_s.trim(te)) != "chunked":
                self._send_error(conn, 501, "Transfer-Encoding non pris en charge")
                return false
            if headers.has("content-length"):
                self._send_error(conn, 400, "Content-Length et Transfer-Encoding ensemble")
                self.rejected += 1
                return false
        if _s.lower(headers.get("expect", "")) == "100-continue":
            cl0 := headers.get_int("content-length", 0)
            if cl0 > self.max_body:
                self._send_error(conn, 413, "corps trop grand")
                return false
            conn.write("HTTP/1.1 100 Continue\r\n\r\n", self.request_timeout)
        try:
            body = _read_body(conn, headers, self.request_timeout, self.max_body)
        catch e:
            if e.type == "HttpError" and _s.contains(e.message, "trop grand"):
                self._send_error(conn, 413, "corps trop grand")
            elif e.type == "TimeoutError":
                self._send_error(conn, 408, "délai de requête dépassé")
            else:
                self._send_error(conn, 400, e.message)
            self.rejected += 1
            return false
        req := Request(_s.upper(method), target, version, headers, body, c.address, c.secure)
        req.connection = conn
        r := null
        try:
            if type(self.app) == "function":
                r = _make_response(self.app(req), req)
            else:
                r = self.app.handle(req)
        catch e:
            if e.type == "HttpError" and _s.starts_with(e.message, "corps JSON invalide"):
                r = error(400, e.message, req)
            else:
                append(self.errors, e.type + ": " + e.message)
            if r != null:
                pass
            elif isinstance(self.app, App) and self.app.on_error != null:
                try:
                    r = _make_response(self.app.on_error(req, e), req)
                catch e2:
                    r = error(500, "erreur interne du serveur", req)
            else:
                r = error(500, "erreur interne du serveur", req)
        c.requests += 1
        self.handled += 1
        keep := req.keep_alive() and c.requests < self.max_requests_per_connection and self.running
        if r.status == 101 and r.upgrade != null:
            self._write(conn, method, r, false, version)
            try:
                r.upgrade(conn)
            catch e:
                append(self.errors, e.type + ": " + e.message)
            return false
        self._write(conn, _s.upper(method), r, keep, version)
        return keep and _s.lower(r.headers.get("connection", "")) != "close"

    func _write(conn, method, r, keep, version):
        status := r.status
        reason := r.reason
        if reason == null:
            reason = _c.status_reason(status)
        head := []
        append(head, "HTTP/1.1 " + str(status) + " " + reason + "\r\n")
        if not r.headers.has("date"):
            append(head, "Date: " + _hh.format_http_date() + "\r\n")
        if not r.headers.has("server") and self.server_name != null:
            append(head, "Server: " + self.server_name + "\r\n")
        for e in r.headers.entries:
            lk := _s.lower(e[0])
            if lk != "content-length" and lk != "transfer-encoding" and (lk != "connection" or status == 101):
                append(head, e[0] + ": " + e[1] + "\r\n")
        has_body := _c.response_has_body(status, "GET") and status != 101
        if has_body:
            append(head, "Content-Length: " + str(r.body_size()) + "\r\n")
        if status != 101:
            if keep:
                if version == "HTTP/1.0":
                    append(head, "Connection: keep-alive\r\n")
            else:
                append(head, "Connection: close\r\n")
        append(head, "\r\n")
        h := _s.join("", head)
        if method == "HEAD" or not has_body:
            conn.write(h, self.request_timeout)
            return
        if r.file_path != null:
            conn.write(h, self.request_timeout)
            start := r.file_range[0]
            stop := r.file_range[1] + 1
            pos := start
            while pos < stop:
                n := 262144
                if stop - pos < n:
                    n = stop - pos
                chunk := _io.read_bytes(r.file_path, pos, n)
                if len(chunk) == 0:
                    break
                conn.write(_n.from_bytes(chunk), self.request_timeout)
                pos += len(chunk)
            return
        if _n.blen(r.body) < 65536:
            conn.write(h + r.body, self.request_timeout)
        else:
            conn.write(h, self.request_timeout)
            conn.write(r.body, self.request_timeout)

func _raw(s):
    if isinstance(s, _tls.TlsSocket):
        return s.socket
    return s

func _read_headers(conn, timeout, max_bytes):
    h := _hh.Headers()
    total := 0
    while true:
        line := conn.read_line(timeout, max_bytes)
        if line == null:
            raise("HttpError", "connexion fermée au milieu des en-têtes")
        if line == "":
            return h
        total += _n.blen(line) + 2
        if total > max_bytes or len(h.entries) >= 200:
            raise("HttpError", "en-têtes trop longs")
        if line[0] == ' ' or line[0] == '\t':
            raise("HttpError", "en-tête replié refusé")
        c := _s.find(line, ":")
        if c <= 0:
            raise("HttpError", "en-tête mal formé")
        name := _s.substring(line, 0, c)
        if not _hh.is_valid_name(name):
            raise("HttpError", "nom d'en-tête invalide")
        value := _s.trim(_s.substring(line, c + 1, len(line)))
        if not _hh.is_valid_value(value):
            raise("HttpError", "valeur d'en-tête invalide")
        append(h.entries, [name, value])

func _read_body(conn, headers, timeout, max_body):
    te := headers.get("transfer-encoding")
    if te != null:
        parts := []
        total := 0
        while true:
            size_line := conn.read_line(timeout, 1024)
            if size_line == null:
                raise("HttpError", "corps « chunked » tronqué")
            semi := _s.find(size_line, ";")
            if semi >= 0:
                size_line = _s.substring(size_line, 0, semi)
            t := _s.trim(size_line)
            if t == "" or len(t) > 8:
                raise("HttpError", "taille de morceau invalide")
            n := 0
            for ch in _s.lower(t):
                d := _s.find("0123456789abcdef", str(ch))
                if d < 0:
                    raise("HttpError", "taille de morceau invalide")
                n = n * 16 + d
            if n == 0:
                while true:
                    tl := conn.read_line(timeout, 8192)
                    if tl == null or tl == "":
                        break
                return _s.join("", parts)
            total += n
            if total > max_body:
                raise("HttpError", "corps trop grand")
            append(parts, conn.read_exact(n, timeout))
            if conn.read_exact(2, timeout) != "\r\n":
                raise("HttpError", "fin de morceau invalide")
    vals := headers.get_all("content-length")
    if len(vals) == 0:
        return ""
    for v in vals:
        if _s.trim(v) != _s.trim(vals[0]):
            raise("HttpError", "Content-Length contradictoires")
    n := headers.get_int("content-length")
    if n == null:
        raise("HttpError", "Content-Length invalide")
    if n > max_body:
        raise("HttpError", "corps trop grand")
    if n == 0:
        return ""
    return conn.read_exact(n, timeout)

# Lance un serveur pour `app` et sert indéfiniment (raccourci).
func run(app, host="127.0.0.1", port=8080, cert_file=null, key_file=null):
    srv := Server(app, host, port, cert_file, key_file)
    print("Serveur HTTP sur " + srv.url())
    srv.serve_forever()

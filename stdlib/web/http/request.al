# ALEX STANDARD LIBRARY — web.http.request
#
# Request : une requête HTTP (méthode, cible, version, en-têtes, corps) avec ses vues pratiques : chemin et
# paramètres de requête décodés, corps en texte / JSON / formulaire, cookies, négociation (Accept), Host, URL
# complète. Utilisée par le serveur (web.server, requêtes reçues) et le client (web.client, requêtes envoyées).
#
#   use web.http.request as rq
#   r := rq.Request("POST", "/articles?brouillon=1", {"Host": "exemple.org", "Content-Type": "application/json"}, "{\"titre\":\"Été\"}")
#   r.path()                     # /articles
#   r.query_param("brouillon")   # 1
#   r.json()["titre"]            # Été
#   r.header("host")             # exemple.org
#   r.url().href()               # http://exemple.org/articles?brouillon=1
#   r.accepts("application/json")    # true (pas d'Accept : tout est accepté)
#   r.cookies()                  # {} ; « Cookie: a=1; b=2 » -> {"a": "1", "b": "2"}
#
# Erreurs : HttpParseError (corps JSON invalide -> json() lève JSONError), HttpHeaderError, TypeError.

from core use len, type
from collections use append, keys
use string as _s
use web.http.http_errors as _err
use web.http.headers as _headers
use web.http.header_value as _hv
use web.http.method as _method
use web.http.version as _version
use web.http.content_type as _ct
use web.http.content_length as _cl
use web.http.request_target as _rt
use web.http.message_body as _mb
use web.url.url as _url
use web.url.query_params as _qp
use web.url.form_url_encoding as _form

class Request:
    func init(method="GET", target="/", headers=null, body="", version="HTTP/1.1"):
        self.method = _method.normalize(method)
        self.target = target
        self.version = version if type(version) == "str" else str(version)
        self.headers = _headers.from_data(headers) if headers != null else _headers.Headers()
        self.body = _mb.to_bytes(body)
        self.remote_address = null    # (hôte, port) du client (serveur)
        self.local_address = null
        self.secure = false           # reçue sur une connexion TLS
        self.route_params = {}        # paramètres de route (« /articles/{id} »)
        self.state = {}               # données libres (intergiciels)
        self.trailers = null          # en-têtes de fin d'un corps chunked
        self.received_at = null       # horodatage de réception (serveur)
        self._target = null
        self._query = null
        self._form = null

    # ---------------------------------------------------------------- cible

    func request_target():
        if self._target == null:
            self._target = _rt.parse(self.target, self.method, false)
        return self._target

    # Chemin encodé (« /docs/caf%C3%A9 »).
    func raw_path():
        return self.request_target().path

    # Chemin décodé (« /docs/café »).
    func path():
        return self.request_target().decoded_path()

    func path_segments():
        return self.request_target().segments()

    # Requête brute (sans « ? »), ou null.
    func query_string():
        return self.request_target().query

    # Paramètres de requête (web.url.query_params.QueryParams).
    func query():
        if self._query == null:
            self._query = self.request_target().params()
        return self._query

    func query_param(name, fallback=null):
        return self.query().get(name, fallback)

    # Paramètre de route, puis de requête, puis de formulaire (dans cet ordre).
    func param(name, fallback=null):
        if name in self.route_params:
            return self.route_params[name]
        v := self.query().get(name)
        if v != null:
            return v
        if self.is_form():
            v = self.form().get(name)
            if v != null:
                return v
        return fallback

    # ---------------------------------------------------------------- en-têtes

    func header(name, fallback=null):
        return self.headers.get(name, fallback)

    func has_header(name):
        return self.headers.has(name)

    func set_header(name, value):
        self.headers.set(name, value)
        return self

    # Host (sans port) ; pour une cible absolue, l'hôte de la cible.
    func host():
        t := self.request_target()
        if t.form == _rt.ABSOLUTE:
            return t.host
        h := self.headers.get("host")
        if h == null:
            return null
        if _s.starts_with(h, "["):
            e := _s.find(h, "]")
            if e > 0:
                return h[1:e]
        c := _s.find(h, ":")
        if c >= 0:
            return h[0:c]
        return h

    func content_type():
        return _ct.try_parse(self.headers.get("content-type"))

    func content_length():
        return _cl.from_headers(self.headers, false)

    func user_agent():
        return self.headers.get("user-agent")

    # URL complète reconstruite (schéma selon secure, Host, cible).
    func url():
        t := self.request_target()
        if t.form == _rt.ABSOLUTE:
            return _url.parse(self.target)
        scheme := "https" if self.secure else "http"
        host := self.headers.get("host", "localhost")
        return _url.parse(scheme + "://" + host + t.origin_form())

    # Connexion persistante demandée ? (HTTP/1.1 : oui sauf « Connection: close » ; 1.0 : seulement keep-alive).
    func keep_alive():
        if self.headers.has_token("connection", "close"):
            return false
        if self.version == "HTTP/1.0":
            return self.headers.has_token("connection", "keep-alive")
        return true

    func expects_continue():
        return _s.lower(self.headers.get("expect", "")) == "100-continue"

    # Mise à niveau demandée (« Upgrade: websocket ») : nom du protocole en minuscules, ou null.
    func upgrade():
        if not self.headers.has_token("connection", "upgrade"):
            return null
        u := self.headers.get("upgrade")
        if u == null:
            return null
        return _s.lower(_hv.trim(u))

    func is_websocket_upgrade():
        return self.upgrade() == "websocket"

    # Client accepte-t-il ce type de média (Accept, qualité > 0) ?
    func accepts(media_type):
        return _hv.quality_of(self.headers.get("accept", null, true), media_type) > 0.0

    # Meilleur type parmi available selon Accept.
    func negotiate(available):
        return _hv.best_match(self.headers.get("accept", null, true), available)

    func accepts_encoding(coding):
        a := self.headers.get("accept-encoding", null, true)
        if a == null:
            return coding == "identity"
        return _hv.quality_of(a, coding) > 0.0

    func preferred_language(available):
        return _hv.best_match(self.headers.get("accept-language", null, true), available)

    # Cookies reçus (« Cookie: a=1; b=2 »).
    func cookies():
        return parse_cookie_header(self.headers.get("cookie", null, false))

    func cookie(name, fallback=null):
        c := self.cookies()
        if name in c:
            return c[name]
        return fallback

    # Identifiants Basic (« Authorization: Basic … ») : (utilisateur, mot de passe), ou null.
    func basic_auth():
        return parse_basic_auth(self.headers.get("authorization"))

    # Jeton Bearer, ou null.
    func bearer_token():
        a := self.headers.get("authorization")
        if a == null or not _s.starts_with(_s.lower(a), "bearer "):
            return null
        return _hv.trim(a[7:len(a)])

    # ---------------------------------------------------------------- corps

    func has_body():
        return self.body != ""

    func text():
        return self.body

    func is_json():
        m := self.content_type()
        return m != null and m.is_json()

    func is_form():
        m := self.content_type()
        return m != null and m.is_form()

    # Corps JSON décodé (null si vide) ; JSONError si invalide.
    func json():
        return _mb.parse_json(self.body)

    # Corps de formulaire application/x-www-form-urlencoded (QueryParams).
    func form():
        if self._form == null:
            self._form = _qp.QueryParams(_form.decode(self.body))
        return self._form

    func set_body(body, content_type=null):
        self.body = _mb.to_bytes(body)
        self.headers.set("Content-Length", _s.byte_len(self.body))
        if content_type != null:
            self.headers.set("Content-Type", content_type)
        self._form = null
        return self

    func set_json(value):
        b := _mb.json_body(value)
        return self.set_body(b[0], b[1])

    func set_form(data):
        b := _mb.form_body(data)
        return self.set_body(b[0], b[1])

    # ---------------------------------------------------------------- divers

    func copy():
        r := Request(self.method, self.target, self.headers.copy(), self.body, self.version)
        r.remote_address = self.remote_address
        r.local_address = self.local_address
        r.secure = self.secure
        for k in keys(self.route_params):
            r.route_params[k] = self.route_params[k]
        for k in keys(self.state):
            r.state[k] = self.state[k]
        return r

    # « GET /chemin HTTP/1.1 »
    func request_line():
        return self.method + " " + self.target + " " + self.version

    func __str__():
        return "<Request " + self.request_line() + ">"

# ---------------------------------------------------------------- fonctions

func request(method, target, headers=null, body=""):
    return Request(method, target, headers, body)

func get(target, headers=null):
    return Request("GET", target, headers)

func post(target, body="", headers=null):
    return Request("POST", target, headers, body)

# « a=1; b=2 » -> {"a": "1", "b": "2"} (paires mal formées ignorées ; guillemets retirés).
func parse_cookie_header(value):
    out := {}
    if value == null:
        return out
    for piece in _s.split(value, ";"):
        p := _hv.trim(piece)
        eq := _s.find(p, "=")
        if eq <= 0:
            continue
        name := _hv.trim(p[0:eq])
        v := _hv.trim(p[eq + 1:len(p)])
        if len(v) >= 2 and v[0] == '"' and v[len(v) - 1] == '"':
            v = v[1:len(v) - 1]
        if not (name in out):
            out[name] = v
    return out

# Valeur d'en-tête Cookie depuis un dict.
func format_cookie_header(cookies):
    parts := []
    for k in keys(cookies):
        append(parts, k + "=" + str(cookies[k]))
    return _s.join("; ", parts)

# « Basic dXNlcjpwYXNz » -> ("user", "pass"), ou null.
func parse_basic_auth(value):
    if value == null:
        return null
    v := _hv.trim(value)
    if not _s.starts_with(_s.lower(v), "basic "):
        return null
    decoded := _b64decode(_hv.trim(v[6:len(v)]))
    if decoded == null:
        return null
    c := _s.find(decoded, ":")
    if c < 0:
        return null
    return (decoded[0:c], decoded[c + 1:len(decoded)])

# « Basic … » pour un couple utilisateur / mot de passe.
func basic_auth_header(user, password):
    return "Basic " + _b64encode(user + ":" + password)

const _B64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

func _b64encode(text):
    bytes := _s.byte_unpack(text)
    out := []
    i := 0
    n := len(bytes)
    while i < n:
        b0 := bytes[i]
        b1 := bytes[i + 1] if i + 1 < n else 0
        b2 := bytes[i + 2] if i + 2 < n else 0
        append(out, str(_B64[b0 >> 2]))
        append(out, str(_B64[((b0 & 3) << 4) | (b1 >> 4)]))
        append(out, str(_B64[((b1 & 15) << 2) | (b2 >> 6)]) if i + 1 < n else "=")
        append(out, str(_B64[b2 & 63]) if i + 2 < n else "=")
        i += 3
    return _s.join("", out)

func _b64value(c):
    o := _s.ord(c)
    if o >= 65 and o <= 90:
        return o - 65
    if o >= 97 and o <= 122:
        return o - 71
    if o >= 48 and o <= 57:
        return o + 4
    if c == '+' or c == '-':
        return 62
    if c == '/' or c == '_':
        return 63
    return -1

func _b64decode(text):
    vals := []
    for c in text:
        if c == '=':
            break
        v := _b64value(c)
        if v < 0:
            return null
        append(vals, v)
    out := []
    i := 0
    n := len(vals)
    while i + 1 < n:
        a := vals[i]
        b := vals[i + 1]
        append(out, ((a << 2) | (b >> 4)) & 255)
        if i + 2 < n:
            c2 := vals[i + 2]
            append(out, (((b & 15) << 4) | (c2 >> 2)) & 255)
            if i + 3 < n:
                append(out, (((c2 & 3) << 6) | vals[i + 3]) & 255)
        i += 4
    return _s.byte_pack(out)

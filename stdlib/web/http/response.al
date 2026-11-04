# ALEX STANDARD LIBRARY — web.http.response
#
# Response : une réponse HTTP (statut, raison, version, en-têtes, corps) et ses constructeurs usuels. Le corps
# peut être une str d'octets (body), un fichier (body_file, envoyé par morceaux par le serveur) ou un flux
# (body_stream : fonction sans argument qui rend le morceau suivant, ou null à la fin ; envoyé en « chunked »).
#
#   use web.http.response as rs
#   r := rs.text("Bonjour")                     # 200, text/plain; charset=utf-8
#   rs.html("<h1>Accueil</h1>")                 # text/html
#   rs.json({"id": 7}, 201)                     # application/json
#   rs.redirect("/connexion")                   # 302 + Location
#   rs.error(404)                               # page d'erreur texte « 404 Not Found »
#   r.set_cookie("sid", "abc", 3600, "/", null, true, true, "Lax")
#   r.ok(), r.is_redirect(), r.header("content-type")
#   r.json_value()                              # côté client : corps JSON décodé
#   r.raise_for_status()                        # HttpStatusError si 4xx / 5xx
#
# Erreurs : HttpStatusError, HttpHeaderError, TypeError.

from core use len, type, to_int
from collections use append, keys
use string as _s
use web.http.http_errors as _err
use web.http.headers as _headers
use web.http.header_value as _hv
use web.http.status_code as _status
use web.http.content_type as _ct
use web.http.content_length as _cl
use web.http.date_header as _date
use web.http.message_body as _mb
use web.url.percent_encoding as _pe

class Response:
    func init(status=200, body="", headers=null, reason=null, version="HTTP/1.1"):
        _status.check(status)
        self.status = status
        self.reason = reason if reason != null else _status.reason(status)
        self.version = version if type(version) == "str" else str(version)
        self.headers = _headers.from_data(headers) if headers != null else _headers.Headers()
        self.body = _mb.to_bytes(body)
        self.body_file = null          # chemin d'un fichier à envoyer comme corps
        self.body_range = null         # (début, longueur) dans body_file
        self.body_stream = null        # fonction () -> morceau str, ou null à la fin
        self.trailers = null           # en-têtes de fin (client : reçus)
        self.url = null                # client : URL finale
        self.history = []              # client : réponses de redirection précédentes
        self.elapsed = null            # client : durée en secondes
        self.request = null            # requête d'origine (client ou serveur)
        self.keep_alive = null         # décision de persistance (protocol_writer.prepare_response)

    # ---------------------------------------------------------------- statut

    func ok():
        return _status.is_success(self.status)

    func is_success():
        return _status.is_success(self.status)

    func is_redirect():
        return _status.is_redirect(self.status) and self.headers.has("location")

    func is_client_error():
        return _status.is_client_error(self.status)

    func is_server_error():
        return _status.is_server_error(self.status)

    func is_error():
        return self.status >= 400

    # HttpStatusError si le statut est une erreur (4xx, 5xx) ; renvoie la réponse sinon.
    func raise_for_status():
        if self.status >= 400:
            where := ""
            if self.url != null:
                where = " pour " + str(self.url)
            _err.status_error("Response.raise_for_status", str(self.status) + " " + self.reason + where, self.status)
        return self

    func with_status(status, reason=null):
        _status.check(status)
        self.status = status
        self.reason = reason if reason != null else _status.reason(status)
        return self

    # « HTTP/1.1 200 OK »
    func status_line():
        return self.version + " " + str(self.status) + " " + self.reason

    # ---------------------------------------------------------------- en-têtes

    func header(name, fallback=null):
        return self.headers.get(name, fallback)

    func set_header(name, value):
        self.headers.set(name, value)
        return self

    func add_header(name, value):
        self.headers.add(name, value)
        return self

    func content_type():
        return _ct.try_parse(self.headers.get("content-type"))

    func set_content_type(value):
        self.headers.set("Content-Type", str(value))
        return self

    func location():
        return self.headers.get("location")

    func content_length():
        return _cl.from_headers(self.headers, false)

    func etag():
        return self.headers.get("etag")

    func set_etag(tag, weak=false):
        t := tag
        if not _s.starts_with(t, "\"") and not _s.starts_with(t, "W/"):
            t = "\"" + t + "\""
        if weak and not _s.starts_with(t, "W/"):
            t = "W/" + t
        self.headers.set("ETag", t)
        return self

    func set_last_modified(timestamp):
        self.headers.set("Last-Modified", _date.format(timestamp))
        return self

    # Cache-Control depuis des directives (dict) ou une str.
    func cache_control(directives):
        if type(directives) == "str":
            self.headers.set("Cache-Control", directives)
        else:
            self.headers.set("Cache-Control", _hv.format_directives(directives))
        return self

    func no_cache():
        return self.cache_control("no-store")

    # Retry-After en secondes (int) ou date (horodatage via retry_at).
    func retry_after(seconds):
        self.headers.set("Retry-After", str(to_int(seconds)))
        return self

    # ---------------------------------------------------------------- cookies

    # Ajoute un Set-Cookie (RFC 6265). max_age : secondes (null : cookie de session ; 0 : suppression) ;
    # same_site : « Strict », « Lax », « None » (implique Secure), false : absent ; path=false : sans Path.
    func set_cookie(name, value, max_age=null, path="/", domain=null, secure=false, http_only=true, same_site="Lax", expires=null):
        self.headers.add("Set-Cookie", format_set_cookie(name, value, max_age, path, domain, secure, http_only, same_site, expires))
        return self

    func delete_cookie(name, path="/", domain=null):
        self.headers.add("Set-Cookie", format_set_cookie(name, "", 0, path, domain, false, false, false, 0))
        return self

    # Cookies posés par la réponse : dict nom -> valeur (côté client).
    func cookies():
        out := {}
        for line in self.headers.get_all("set-cookie"):
            c := parse_set_cookie(line)
            if c != null:
                out[c["name"]] = c["value"]
        return out

    # ---------------------------------------------------------------- corps

    func set_body(body, content_type=null):
        self.body = _mb.to_bytes(body)
        self.body_file = null
        self.body_stream = null
        if content_type != null:
            self.headers.set("Content-Type", content_type)
        return self

    func text():
        return self.body

    # Corps JSON décodé (null si vide) ; JSONError si invalide.
    func json_value():
        return _mb.parse_json(self.body)

    func has_body():
        return self.body != "" or self.body_file != null or self.body_stream != null

    # Taille du corps si elle est connue (null pour un flux).
    func body_size():
        if self.body_stream != null:
            return null
        if self.body_file != null:
            if self.body_range != null:
                return self.body_range[1]
            return null
        return _s.byte_len(self.body)

    func copy():
        r := Response(self.status, self.body, self.headers.copy(), self.reason, self.version)
        r.body_file = self.body_file
        r.body_range = self.body_range
        r.body_stream = self.body_stream
        r.url = self.url
        r.history = self.history
        r.elapsed = self.elapsed
        r.request = self.request
        return r

    func __str__():
        return "<Response " + str(self.status) + " " + self.reason + ">"

# ---------------------------------------------------------------- constructeurs

func response(status=200, body="", headers=null):
    return Response(status, body, headers)

func text(body, status=200, headers=null):
    r := Response(status, str(body), headers)
    r.headers.set_default("Content-Type", "text/plain; charset=utf-8")
    return r

func html(body, status=200, headers=null):
    r := Response(status, str(body), headers)
    r.headers.set_default("Content-Type", "text/html; charset=utf-8")
    return r

func json(value, status=200, headers=null):
    b := _mb.json_body(value)
    r := Response(status, b[0], headers)
    r.headers.set_default("Content-Type", b[1])
    return r

func bytes(data, content_type="application/octet-stream", status=200):
    r := Response(status, _mb.to_bytes(data))
    r.headers.set("Content-Type", content_type)
    return r

# Redirection (302 par défaut ; 301, 303, 307, 308 possibles).
func redirect(location, status=302):
    if not _status.is_redirect(status):
        _err.http_error("response.redirect", "statut de redirection attendu (301, 302, 303, 307, 308), obtenu " + str(status))
    r := Response(status)
    r.headers.set("Location", _pe.encode_set(_hv.check(location, "Location"), " \"<>`"))
    return r

func no_content():
    return Response(204)

func not_modified(etag=null):
    r := Response(304)
    if etag != null:
        r.headers.set("ETag", etag)
    return r

# Réponse d'erreur texte (« 404 Not Found » + message éventuel).
func error(status, message=null):
    body := str(status) + " " + _status.reason(status)
    if message != null and message != "":
        body = body + "\n" + str(message)
    return text(body + "\n", status)

func not_found(message=null):
    return error(404, message)

func bad_request(message=null):
    return error(400, message)

func method_not_allowed(allowed):
    r := error(405)
    r.headers.set("Allow", _s.join(", ", allowed))
    return r

func unauthorized(realm="alex", scheme="Basic"):
    r := error(401)
    r.headers.set("WWW-Authenticate", scheme + " realm=" + _hv.quote(realm))
    return r

func server_error(message=null):
    return error(500, message)

# Corps lu depuis un fichier par le serveur (taille connue : length octets à partir de offset).
func file(path, content_type=null, offset=0, length=null):
    r := Response(200)
    r.body_file = path
    if length != null:
        r.body_range = (offset, length)
    if content_type != null:
        r.headers.set("Content-Type", content_type)
    return r

# Corps produit par next_chunk() (null : fin), envoyé en « chunked ».
func stream(next_chunk, content_type="application/octet-stream", status=200):
    r := Response(status)
    r.body_stream = next_chunk
    r.headers.set("Content-Type", content_type)
    return r

# ---------------------------------------------------------------- Set-Cookie

func _check_cookie_name(name):
    if not _hv.is_token(name):
        _err.header_error("response.set_cookie", "nom de cookie invalide '" + _hv.sanitize(name) + "'")

func _cookie_value(value):
    v := str(value)
    for c in v:
        o := _s.ord(c)
        if o <= 32 or o >= 127 or c == '"' or c == ',' or c == ';' or c == '\\':
            return _pe.encode(v, "!#$&'()*+-./:<=>?@[]^_`{|}~")
    return v

func format_set_cookie(name, value, max_age=null, path="/", domain=null, secure=false, http_only=true, same_site="Lax", expires=null):
    _check_cookie_name(name)
    out := name + "=" + _cookie_value(value)
    if max_age != null:
        out = out + "; Max-Age=" + str(to_int(max_age))
    if expires != null:
        out = out + "; Expires=" + _date.format(expires)
    if domain != null:
        out = out + "; Domain=" + _hv.check(domain, "Domain")
    if path != null and path != false:
        out = out + "; Path=" + _hv.check(path, "Path")
    if same_site == false:
        same_site = null
    if secure or same_site == "None":
        out = out + "; Secure"
    if http_only:
        out = out + "; HttpOnly"
    if same_site != null:
        if not (same_site in ["Strict", "Lax", "None"]):
            _err.header_error("response.set_cookie", "SameSite doit valoir Strict, Lax ou None (obtenu " + str(same_site) + ")")
        out = out + "; SameSite=" + same_site
    return out

# « sid=abc; Path=/; HttpOnly » -> {"name", "value", "attributes" : dict en minuscules} ; null si invalide.
func parse_set_cookie(line):
    parts := _s.split(line, ";")
    first := _hv.trim(parts[0])
    eq := _s.find(first, "=")
    if eq <= 0:
        return null
    attrs := {}
    i := 1
    while i < len(parts):
        p := _hv.trim(parts[i])
        e := _s.find(p, "=")
        if e < 0:
            if p != "":
                attrs[_s.lower(p)] = true
        else:
            attrs[_s.lower(_hv.trim(p[0:e]))] = _hv.trim(p[e + 1:len(p)])
        i += 1
    v := _hv.trim(first[eq + 1:len(first)])
    if len(v) >= 2 and v[0] == '"' and v[len(v) - 1] == '"':
        v = v[1:len(v) - 1]
    return {"name": _hv.trim(first[0:eq]), "value": v, "attributes": attrs}

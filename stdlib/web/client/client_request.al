# ALEX STANDARD LIBRARY — web.client.client_request
#
# ClientRequest : une requête à envoyer — méthode, URL (web.url.Url), en-têtes, corps — et ses aides pour les
# corps courants (JSON, formulaire, multipart avec fichiers), l'authentification (Basic, Bearer) et la conversion
# en message web.http (origin-form, ou absolute-form à travers un mandataire).
#
#   use web.client.client_request as cr
#   r := cr.ClientRequest("POST", "https://api.exemple.org/notes", {"Accept": "application/json"}, null, {"brouillon": 1})
#   r.set_json({"titre": "Été"})
#   r.set_bearer("jeton")
#   r.url.href()                     # https://api.exemple.org/notes?brouillon=1
#   r.to_http().request_line()       # POST /notes?brouillon=1 HTTP/1.1
#   m := cr.ClientRequest("POST", "https://h/upload")
#   m.set_multipart({"titre": "Rapport"}, [("fichier", "r.pdf", octets, "application/pdf")])
#
# Erreurs : ClientError (URL non http(s), corps invalide), erreurs de web.url et web.http.

from core use len, type, to_int
from collections use append, keys
use string as _s
use time as _time
use random as _random
use web.client.client_errors as _err
use web.url.url as _url
use web.url.query as _query
use web.url.query_params as _qp
use web.http.headers as _headers
use web.http.method as _method
use web.http.request as _request
use web.http.message_body as _mb
use web.http.header_value as _hv
use web.http.content_type as _ct

class ClientRequest:
    # url : texte ou Url ; params : dict / paires / QueryParams ajoutés à la requête de l'URL ; body : str d'octets,
    # liste d'octets ou null ; timeout : délai propre à cette requête (nombre ou web.client.timeout.Timeout).
    func init(method, url, headers=null, body=null, params=null, timeout=null):
        self.method = _method.normalize(method)
        u := url
        if type(url) == "str":
            u = _url.parse(url)
        if not u.is_http():
            _err.client_error("ClientRequest", "URL http ou https attendue (obtenu « " + u.href() + " »)")
        if u.host == null or u.host == "":
            _err.client_error("ClientRequest", "URL sans hôte « " + u.href() + " »")
        if params != null:
            p := u.params()
            p.update(params)
            u = u.with_query(p)
        self.url = u.without_fragment()
        self.headers = _headers.from_data(headers) if headers != null else _headers.Headers()
        self.body = _mb.to_bytes(body)
        self.timeout = timeout
        self.follow_redirects = null     # null : selon la politique du client
        self.attempt = 0                 # reprises déjà faites (renseigné par le client)

    # ---------------------------------------------------------------- en-têtes

    func set_header(name, value):
        self.headers.set(name, value)
        return self

    func add_header(name, value):
        self.headers.add(name, value)
        return self

    func accept(media_type):
        self.headers.set("Accept", media_type)
        return self

    func set_basic_auth(username, password):
        self.headers.set("Authorization", _request.basic_auth_header(username, password))
        return self

    func set_bearer(token):
        self.headers.set("Authorization", "Bearer " + token)
        return self

    func set_cookies(cookies):
        self.headers.set("Cookie", _request.format_cookie_header(cookies))
        return self

    # ---------------------------------------------------------------- corps

    func set_body(data, content_type=null):
        self.body = _mb.to_bytes(data)
        if content_type != null:
            self.headers.set("Content-Type", content_type)
        return self

    func set_text(text, sub="plain"):
        b := _mb.text_body(text, sub)
        return self.set_body(b[0], b[1])

    func set_json(value):
        b := _mb.json_body(value)
        self.headers.set_default("Accept", "application/json")
        return self.set_body(b[0], b[1])

    func set_form(data):
        b := _mb.form_body(data)
        return self.set_body(b[0], b[1])

    # multipart/form-data (RFC 7578) : fields = dict / paires de champs texte ; files = liste de
    # (champ, nom de fichier, contenu str ou liste d'octets, type MIME ou null).
    func set_multipart(fields=null, files=null):
        boundary := new_boundary()
        self.body = encode_multipart(fields, files, boundary)
        self.headers.set("Content-Type", "multipart/form-data; boundary=" + boundary)
        return self

    func has_body():
        return self.body != ""

    # ---------------------------------------------------------------- protocole

    # Valeur de Host : hôte, et port s'il n'est pas celui par défaut.
    func host_header():
        return self.url.host_port()

    func origin():
        return self.url.origin()

    # Cible : origin-form (« /chemin?requête »), ou absolute-form à travers un mandataire http.
    func target(absolute=false):
        if absolute:
            return self.url.href()
        return self.url.target()

    # Message web.http.Request prêt à écrire (Host en premier, Content-Length si corps).
    func to_http(absolute=false):
        h := _headers.Headers()
        h.set("Host", self.host_header())
        for e in self.headers.entries:
            if e[2] != "host":
                append(h.entries, [e[0], e[1], e[2]])
        if self.body != "" or _method.expects_body(self.method):
            if not h.has("transfer-encoding"):
                h.set("Content-Length", _s.byte_len(self.body))
        return _request.Request(self.method, self.target(absolute), h, self.body)

    func copy():
        r := ClientRequest(self.method, self.url, self.headers.copy(), self.body, null, self.timeout)
        r.follow_redirects = self.follow_redirects
        return r

    func __str__():
        return "<ClientRequest " + self.method + " " + self.url.redacted() + ">"

func request(method, url, headers=null, body=null, params=null):
    return ClientRequest(method, url, headers, body, params)

# ---------------------------------------------------------------- multipart

_boundary_counter := [0]

# Frontière multipart aléatoire (aucune chance de figurer dans le contenu).
func new_boundary():
    _boundary_counter[0] = _boundary_counter[0] + 1
    r1 := _random.getrandbits(32)
    r2 := _random.getrandbits(32)
    return "----AlexFormBoundary" + _hex(r1) + _hex(r2) + _hex(to_int(_time.time()) & 1048575) + str(_boundary_counter[0])

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

func _disposition_value(text):
    return "\"" + _s.replace(_s.replace(_s.replace(str(text), "\\", "\\\\"), "\"", "%22"), "\r\n", " ") + "\""

# Corps multipart/form-data.
func encode_multipart(fields, files, boundary):
    parts := []
    pairs := []
    if fields != null:
        if type(fields) == "dict":
            for k in keys(fields):
                v := fields[k]
                if type(v) == "list" or type(v) == "tuple":
                    for x in v:
                        append(pairs, (k, x))
                else:
                    append(pairs, (k, v))
        else:
            for p in fields:
                append(pairs, (p[0], p[1]))
    for p in pairs:
        append(parts, "--" + boundary + "\r\n")
        append(parts, "Content-Disposition: form-data; name=" + _disposition_value(p[0]) + "\r\n\r\n")
        append(parts, str(p[1]) + "\r\n")
    if files != null:
        for f in files:
            name := f[0]
            filename := f[1]
            content := _mb.to_bytes(f[2])
            mime := f[3] if len(f) > 3 and f[3] != null else _ct.guess(filename)
            append(parts, "--" + boundary + "\r\n")
            disp := "Content-Disposition: form-data; name=" + _disposition_value(name) + "; filename=" + _disposition_value(filename)
            append(parts, disp + "\r\n")
            append(parts, "Content-Type: " + mime + "\r\n\r\n")
            append(parts, content)
            append(parts, "\r\n")
    append(parts, "--" + boundary + "--\r\n")
    return _s.byte_join(parts)

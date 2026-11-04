# ALEX STANDARD LIBRARY — network.http
#
# HTTP/1.1 : client (requêtes, redirections, corps Content-Length / chunked / jusqu'à la fermeture, JSON) et
# serveur séquentiel (une requête à la fois), sur network.tcp. Outils d'URL : analyse, encodage « %XX »,
# chaînes de requête.
#
# HTTPS
#   https:// passe par network.tls (OpenSSL chargé à l'exécution) : certificat ET nom du serveur vérifiés par défaut
#   (verify=true ; ca_file pour une autorité privée). Une réponse sans longueur (corps « jusqu'à la fermeture ») doit
#   se terminer par close_notify, sinon TlsError : une coupure ne passe pas pour une fin normale. Redirections :
#   les en-têtes Authorization, Cookie et Proxy-Authorization ne suivent JAMAIS vers une autre origine
#   (schéma, hôte ou port différents).
#
# Limites
#   - Sans OpenSSL sur la machine, https:// lève HttpError (voir network.tls.why()).
#   - Une connexion par requête (Connection: close) ; pas de compression (Accept-Encoding: identity).
#   - Le serveur traite les requêtes l'une après l'autre (pas de connexions simultanées).
#
# Erreurs
#   HttpError      URL invalide ou non prise en charge, réponse mal formée, trop de redirections,
#                  raise_for_status() sur un statut >= 400.
#   NetworkError, TimeoutError, DnsError   voir network.tcp.
#
# Exemple (client)
#   use network.http as http
#   r := http.get("http://example.org/")
#   print(r.status, r.header("content-type"), len(r.text()))
#   r2 := http.post_json("http://127.0.0.1:8080/api", {"nom": "Alex"})
#   print(r2.json())
#
# Exemple (serveur)
#   func handler(req):
#       if req.path == "/bonjour":
#           return http.text("Bonjour " + req.param("nom", "inconnu") + "\n")
#       return http.Response(404, "introuvable\n")
#   srv := http.Server("127.0.0.1", 8080)
#   srv.serve(handler)

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use json as _json
use crypto as _crypto
use _native_net as _n
use network.tcp as _tcp
use network.tls as _tls

const USER_AGENT := "Alex-http/0.7"
const DEFAULT_TIMEOUT := 30.0
const HEADER_LIMIT := 65536
const BODY_LIMIT := 104857600

# ---------------------------------------------------------------- URL

const _HEX := "0123456789ABCDEF"

func _hex_digit(c):
    i := _s.find("0123456789abcdef", _s.lower(str(c)))
    if i < 0:
        return -1
    return i

# Encode s (UTF-8) en « %XX » sauf les caractères non réservés (A-Z a-z 0-9 - . _ ~).
# plus=true : l'espace devient « + » (formulaires).
func url_encode(s, plus=false):
    out := ""
    for b in _n.to_bytes(str(s)):
        if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or (b >= 48 and b <= 57) or b == 45 or b == 46 or b == 95 or b == 126:
            out += str(_s.chr(b))
        elif b == 32 and plus:
            out += "+"
        else:
            out += "%" + str(_HEX[b >> 4]) + str(_HEX[b & 15])
    return out

# Décode les « %XX » (et « + » en espace si plus=true).
func url_decode(s, plus=false):
    raw := _n.to_bytes(s)
    out := []
    i := 0
    while i < len(raw):
        b := raw[i]
        if b == 37 and i + 2 < len(raw):
            hi := _hex_digit(_s.chr(raw[i + 1]))
            lo := _hex_digit(_s.chr(raw[i + 2]))
            if hi >= 0 and lo >= 0:
                append(out, hi * 16 + lo)
                i += 3
                continue
        if b == 43 and plus:
            append(out, 32)
        else:
            append(out, b)
        i += 1
    return _n.from_bytes(out)

# « a=1&b=x%20y » depuis un dict (valeurs converties en str ; une list donne plusieurs paires).
func encode_query(params):
    parts := []
    for k in keys(params):
        v := params[k]
        if type(v) == "list":
            for x in v:
                append(parts, url_encode(k, true) + "=" + url_encode(x, true))
        else:
            append(parts, url_encode(k, true) + "=" + url_encode(v, true))
    return _s.join("&", parts)

# dict nom -> valeur (dernière valeur si un nom est répété) d'une chaîne de requête.
func parse_query(q):
    out := {}
    if q == null or q == "":
        return out
    for pair in _s.split(q, "&"):
        if pair == "":
            continue
        i := _s.find(pair, "=")
        if i < 0:
            out[url_decode(pair, true)] = ""
        else:
            out[url_decode(_s.substring(pair, 0, i), true)] = url_decode(_s.substring(pair, i + 1, len(pair)), true)
    return out

class Url:
    func init(scheme, host, port, path, query, fragment):
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path         # commence par « / »
        self.query = query       # sans « ? », "" si absente
        self.fragment = fragment

    # Chemin et requête tels qu'envoyés au serveur.
    func target():
        if self.query == "":
            return self.path
        return self.path + "?" + self.query

    func authority():
        h := self.host
        if _s.contains(h, ":"):
            h = "[" + h + "]"
        if (self.scheme == "http" and self.port == 80) or (self.scheme == "https" and self.port == 443):
            return h
        return h + ":" + str(self.port)

    func str():
        s := self.scheme + "://" + self.authority() + self.target()
        if self.fragment != "":
            s += "#" + self.fragment
        return s

func _url_fail(url, why):
    raise("HttpError", "URL invalide '" + str(url) + "' : " + why)

# Analyse une URL absolue http:// ou https://.
func parse_url(url):
    if type(url) != "str":
        raise("TypeError", "http.parse_url : str attendue (obtenu '" + type(url) + "')")
    i := _s.find(url, "://")
    if i <= 0:
        _url_fail(url, "schéma attendu (http://...)")
    scheme := _s.lower(_s.substring(url, 0, i))
    if scheme != "http" and scheme != "https":
        _url_fail(url, "schéma « " + scheme + " » non pris en charge")
    rest := _s.substring(url, i + 3, len(url))
    fragment := ""
    j := _s.find(rest, "#")
    if j >= 0:
        fragment = _s.substring(rest, j + 1, len(rest))
        rest = _s.substring(rest, 0, j)
    k := _s.find(rest, "/")
    q := _s.find(rest, "?")
    cut := k
    if cut < 0 or (q >= 0 and q < cut):
        cut = q
    authority := rest
    target := "/"
    if cut >= 0:
        authority = _s.substring(rest, 0, cut)
        target = _s.substring(rest, cut, len(rest))
        if _s.starts_with(target, "?"):
            target = "/" + target
    at := _s.find(authority, "@")
    if at >= 0:
        authority = _s.substring(authority, at + 1, len(authority))
    host := authority
    port := 80
    if scheme == "https":
        port = 443
    if _s.starts_with(authority, "["):
        e := _s.find(authority, "]")
        if e < 0:
            _url_fail(url, "« ] » manquant")
        host = _s.substring(authority, 1, e)
        after := _s.substring(authority, e + 1, len(authority))
        if _s.starts_with(after, ":"):
            port = _port_of(url, _s.substring(after, 1, len(after)))
    else:
        c := _s.find(authority, ":")
        if c >= 0:
            host = _s.substring(authority, 0, c)
            port = _port_of(url, _s.substring(authority, c + 1, len(authority)))
    if host == "":
        _url_fail(url, "hôte manquant")
    path := target
    query := ""
    qi := _s.find(target, "?")
    if qi >= 0:
        path = _s.substring(target, 0, qi)
        query = _s.substring(target, qi + 1, len(target))
    return Url(scheme, host, port, path, query, fragment)

func _port_of(url, text):
    if text == "":
        _url_fail(url, "port vide")
    for c in text:
        if c < '0' or c > '9':
            _url_fail(url, "port non numérique")
    p := to_int(text)
    if p < 1 or p > 65535:
        _url_fail(url, "port hors de 1..65535")
    return p

# URL absolue de location (absolue, « //hôte/... », « /chemin » ou relative) par rapport à base (Url).
func resolve_url(base, location):
    if _s.contains(location, "://"):
        return location
    if _s.starts_with(location, "//"):
        return base.scheme + ":" + location
    if _s.starts_with(location, "/"):
        return base.scheme + "://" + base.authority() + location
    dir := base.path
    k := len(dir) - 1
    while k >= 0 and dir[k] != '/':
        k -= 1
    return base.scheme + "://" + base.authority() + _s.substring(dir, 0, k + 1) + location

# ---------------------------------------------------------------- en-têtes et corps

# En-têtes reçus : dict nom en minuscules -> valeur (valeurs répétées jointes par « , »), et la liste brute.
class Headers:
    func init():
        self.values = {}
        self.list = []    # [nom tel que reçu, valeur] dans l'ordre

    func add(name, value):
        append(self.list, [name, value])
        k := _s.lower(name)
        if contains_key(self.values, k):
            self.values[k] = self.values[k] + ", " + value
        else:
            self.values[k] = value

    func get(name, default=null):
        k := _s.lower(name)
        if contains_key(self.values, k):
            return self.values[k]
        return default

    func has(name):
        return contains_key(self.values, _s.lower(name))

func _read_headers(conn, timeout, what):
    h := Headers()
    total := 0
    while true:
        line := conn.read_line(timeout, HEADER_LIMIT)
        if line == null:
            raise("HttpError", what + " : connexion fermée au milieu des en-têtes")
        if line == "":
            return h
        total += _n.blen(line)
        if total > HEADER_LIMIT:
            raise("HttpError", what + " : en-têtes trop longs")
        c := _s.find(line, ":")
        if c <= 0:
            raise("HttpError", what + " : en-tête mal formé « " + line + " »")
        h.add(_s.trim(_s.substring(line, 0, c)), _s.trim(_s.substring(line, c + 1, len(line))))

func _parse_hex(text, what):
    t := _s.trim(text)
    if t == "":
        raise("HttpError", what + " : taille de morceau vide")
    n := 0
    for c in t:
        d := _hex_digit(c)
        if d < 0:
            raise("HttpError", what + " : taille de morceau invalide « " + t + " »")
        n = n * 16 + d
        if n > BODY_LIMIT:
            raise("HttpError", what + " : morceau trop grand")
    return n

# Corps d'un message : Transfer-Encoding chunked, Content-Length, ou jusqu'à la fermeture (until_close).
func _read_body(conn, headers, timeout, until_close, what):
    te := _s.lower(headers.get("transfer-encoding", ""))
    if _s.contains(te, "chunked"):
        body := ""
        while true:
            size_line := conn.read_line(timeout, HEADER_LIMIT)
            if size_line == null:
                raise("HttpError", what + " : connexion fermée dans un corps « chunked »")
            semi := _s.find(size_line, ";")
            if semi >= 0:
                size_line = _s.substring(size_line, 0, semi)
            size := _parse_hex(size_line, what)
            if size == 0:
                trailer := conn.read_line(timeout, HEADER_LIMIT)
                while trailer != null and trailer != "":
                    trailer = conn.read_line(timeout, HEADER_LIMIT)
                return body
            if _n.blen(body) + size > BODY_LIMIT:
                raise("HttpError", what + " : corps trop grand")
            body = body + conn.read_exact(size, timeout)
            conn.read_line(timeout, HEADER_LIMIT)
    cl := headers.get("content-length")
    if cl != null:
        t := _s.trim(cl)
        for c in t:
            if c < '0' or c > '9':
                raise("HttpError", what + " : Content-Length invalide « " + cl + " »")
        if t == "":
            raise("HttpError", what + " : Content-Length vide")
        n := to_int(t)
        if n > BODY_LIMIT:
            raise("HttpError", what + " : corps trop grand")
        if n == 0:
            return ""
        return conn.read_exact(n, timeout)
    if until_close:
        return conn.read_all(timeout)
    return ""

# ---------------------------------------------------------------- client

class Response:
    func init(status, reason, headers, body, url):
        self.status = status
        self.reason = reason
        self.headers = headers    # Headers (reçus) ou dict nom -> valeur (serveur)
        self.body = body          # octets (str)
        self.url = url            # URL finale (après redirections), côté client

    func ok():
        return self.status >= 200 and self.status < 300

    func header(name, default=null):
        if type(self.headers) == "dict":
            for k in keys(self.headers):
                if _s.lower(k) == _s.lower(name):
                    return self.headers[k]
            return default
        return self.headers.get(name, default)

    func text():
        return self.body

    func bytes():
        return _n.to_bytes(self.body)

    func json():
        return _json.parse(self.body)

    func raise_for_status():
        if self.status >= 400:
            raise("HttpError", f"HTTP {self.status} {self.reason} : {self.url}")
        return self

func _request_once(method, u, body, headers, timeout, verify=true, ca_file=null):
    conn := null
    if u.scheme == "https":
        if not _tls.supported():
            raise("HttpError", "https:// indisponible : " + _tls.why() + " (" + u.str() + ")")
        conn = _tls.connect(u.host, u.port, timeout, verify, ca_file, ["http/1.1"])
    else:
        conn = _tcp.connect(u.host, u.port, timeout)
    try:
        lines := method + " " + u.target() + " HTTP/1.1\r\n"
        sent := {}
        if headers != null:
            for k in keys(headers):
                sent[_s.lower(k)] = true
                lines += k + ": " + str(headers[k]) + "\r\n"
        if not contains_key(sent, "host"):
            lines += "Host: " + u.authority() + "\r\n"
        if not contains_key(sent, "user-agent"):
            lines += "User-Agent: " + USER_AGENT + "\r\n"
        if not contains_key(sent, "accept-encoding"):
            lines += "Accept-Encoding: identity\r\n"
        lines += "Connection: close\r\n"
        if body != null or method == "POST" or method == "PUT" or method == "PATCH":
            b := body
            if b == null:
                b = ""
            if not contains_key(sent, "content-length"):
                lines += "Content-Length: " + str(_n.blen(b)) + "\r\n"
            conn.write(lines + "\r\n" + b, timeout)
        else:
            conn.write(lines + "\r\n", timeout)
        status_line := conn.read_line(timeout, HEADER_LIMIT)
        while true:
            if status_line == null:
                raise("HttpError", "réponse vide de " + u.str())
            parts := _s.split(status_line, " ")
            if len(parts) < 2 or not _s.starts_with(parts[0], "HTTP/"):
                raise("HttpError", "ligne de statut invalide « " + status_line + " » (" + u.str() + ")")
            status := to_int(parts[1])
            reason := ""
            if len(parts) > 2:
                reason = _s.join(" ", [parts[i] for i in 2..len(parts)])
            hdrs := _read_headers(conn, timeout, "réponse de " + u.host)
            if status >= 100 and status < 200: # réponse intermédiaire (100 Continue...) : la suivante
                status_line = conn.read_line(timeout, HEADER_LIMIT)
                continue
            data := ""
            if method != "HEAD" and status != 204 and status != 304:
                data = _read_body(conn, hdrs, timeout, true, "réponse de " + u.host)
            conn.close()
            return Response(status, reason, hdrs, data, u.str())
    catch e:
        conn.close()
        raise(e)

# Requête HTTP ; body : str (octets envoyés tels quels) ou null ; headers : dict nom -> valeur.
# Redirections (301, 302, 303, 307, 308) suivies jusqu'à max_redirects : 303 (et 301/302 pour POST)
# repassent en GET sans corps, 307 / 308 gardent la méthode et le corps.
func request(method, url, body=null, headers=null, timeout=DEFAULT_TIMEOUT, follow_redirects=true, max_redirects=5, verify=true, ca_file=null):
    if type(method) != "str" or method == "":
        raise("TypeError", "http.request : méthode str attendue")
    if body != null and type(body) != "str":
        raise("TypeError", "http.request : corps str attendu (obtenu '" + type(body) + "'), voir post_json / post_form")
    m := _s.upper(method)
    u := parse_url(url)
    hops := 0
    while true:
        r := _request_once(m, u, body, headers, timeout, verify, ca_file)
        if not follow_redirects or not (r.status == 301 or r.status == 302 or r.status == 303 or r.status == 307 or r.status == 308):
            return r
        location := r.header("location")
        if location == null:
            return r
        hops += 1
        if hops > max_redirects:
            raise("HttpError", "trop de redirections (plus de " + str(max_redirects) + ") depuis " + url)
        if r.status == 303 or ((r.status == 301 or r.status == 302) and m != "GET" and m != "HEAD"):
            m = "GET"
            body = null
        nxt := parse_url(resolve_url(u, location))
        if nxt.scheme != u.scheme or nxt.host != u.host or nxt.port != u.port:
            headers = _without_credentials(headers)
        u = nxt

# Copie de headers sans les en-têtes qui authentifient auprès d'UNE origine (jamais renvoyés ailleurs).
func _without_credentials(headers):
    if headers == null:
        return null
    out := {}
    for k in keys(headers):
        low := _s.lower(k)
        if low != "authorization" and low != "cookie" and low != "proxy-authorization":
            out[k] = headers[k]
    return out

# Valeur d'en-tête Authorization pour l'authentification « Basic » : headers["Authorization"] = basic_auth(u, mdp).
func basic_auth(user, password):
    if type(user) != "str" or type(password) != "str":
        raise("TypeError", "http.basic_auth : user et password doivent être des str")
    if _s.contains(user, ":"):
        raise("ArgumentError", "http.basic_auth : l'identifiant ne peut pas contenir « : »")
    return "Basic " + _crypto.base64_encode(_n.to_bytes(user + ":" + password))

# Valeur d'en-tête Authorization pour un jeton porteur (Bearer).
func bearer_auth(token):
    if type(token) != "str" or token == "":
        raise("TypeError", "http.bearer_auth : jeton str non vide attendu")
    return "Bearer " + token

func get(url, headers=null, timeout=DEFAULT_TIMEOUT, verify=true, ca_file=null):
    return request("GET", url, null, headers, timeout, true, 5, verify, ca_file)

func head(url, headers=null, timeout=DEFAULT_TIMEOUT, verify=true, ca_file=null):
    return request("HEAD", url, null, headers, timeout, true, 5, verify, ca_file)

func delete(url, headers=null, timeout=DEFAULT_TIMEOUT, verify=true, ca_file=null):
    return request("DELETE", url, null, headers, timeout, true, 5, verify, ca_file)

func post(url, body="", headers=null, timeout=DEFAULT_TIMEOUT, verify=true, ca_file=null):
    return request("POST", url, body, headers, timeout, true, 5, verify, ca_file)

func put(url, body="", headers=null, timeout=DEFAULT_TIMEOUT, verify=true, ca_file=null):
    return request("PUT", url, body, headers, timeout, true, 5, verify, ca_file)

func _with(headers, name, value):
    h := {}
    if headers != null:
        for k in keys(headers):
            h[k] = headers[k]
    has := false
    for k in keys(h):
        if _s.lower(k) == _s.lower(name):
            has = true
    if not has:
        h[name] = value
    return h

# POST d'une valeur en JSON (Content-Type: application/json).
func post_json(url, value, headers=null, timeout=DEFAULT_TIMEOUT, verify=true, ca_file=null):
    return post(url, _json.stringify(value), _with(headers, "Content-Type", "application/json"), timeout, verify, ca_file)

# POST d'un formulaire (dict) encodé en application/x-www-form-urlencoded.
func post_form(url, fields, headers=null, timeout=DEFAULT_TIMEOUT, verify=true, ca_file=null):
    return post(url, encode_query(fields), _with(headers, "Content-Type", "application/x-www-form-urlencoded"), timeout, verify, ca_file)

# ---------------------------------------------------------------- serveur

_REASONS := {100: "Continue", 101: "Switching Protocols", 200: "OK", 201: "Created", 202: "Accepted", 204: "No Content", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified", 307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 413: "Payload Too Large", 415: "Unsupported Media Type", 422: "Unprocessable Content", 426: "Upgrade Required", 429: "Too Many Requests", 500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout"}

func reason_phrase(status):
    if contains_key(_REASONS, status):
        return _REASONS[status]
    return "Status " + str(status)

class Request:
    func init(method, target, version, headers, body, client):
        self.method = method
        self.target = target          # tel que reçu (« /chemin?requête »)
        self.version = version
        self.headers = headers        # Headers
        self.body = body
        self.client = client          # (hôte, port) du client
        q := _s.find(target, "?")
        if q >= 0:
            self.path = url_decode(_s.substring(target, 0, q))
            self.query = parse_query(_s.substring(target, q + 1, len(target)))
        else:
            self.path = url_decode(target)
            self.query = {}

    func header(name, default=null):
        return self.headers.get(name, default)

    # Paramètre de la chaîne de requête.
    func param(name, default=null):
        if contains_key(self.query, name):
            return self.query[name]
        return default

    func text():
        return self.body

    func json():
        return _json.parse(self.body)

    # Champs d'un formulaire application/x-www-form-urlencoded.
    func form():
        return parse_query(self.body)

# Réponses toutes faites pour un gestionnaire.
func text(body, status=200, headers=null):
    return Response(status, reason_phrase(status), _with(headers, "Content-Type", "text/plain; charset=utf-8"), body, null)

func html(body, status=200, headers=null):
    return Response(status, reason_phrase(status), _with(headers, "Content-Type", "text/html; charset=utf-8"), body, null)

func json_response(value, status=200, headers=null):
    return Response(status, reason_phrase(status), _with(headers, "Content-Type", "application/json"), _json.stringify(value), null)

func redirect(location, status=302):
    return Response(status, reason_phrase(status), {"Location": location}, "", null)

func _make_response(r):
    if type(r) == "str":
        return text(r)
    if r == null:
        return Response(204, "No Content", {}, "", null)
    return r

func _write_response(conn, req_method, r):
    status := r.status
    reason := r.reason
    if reason == null or reason == "":
        reason = reason_phrase(status)
    if type(r.headers) != "dict":
        raise("TypeError", "http : les en-têtes d'une réponse du serveur doivent être un dict")
    b := r.body
    if b == null:
        b = ""
    out := "HTTP/1.1 " + str(status) + " " + reason + "\r\n"
    for k in keys(r.headers):
        lk := _s.lower(k)
        if lk != "content-length" and lk != "connection" and lk != "transfer-encoding":
            out += k + ": " + str(r.headers[k]) + "\r\n"
    if r.header("server") == null:
        out += "Server: " + USER_AGENT + "\r\n"
    out += "Content-Length: " + str(_n.blen(b)) + "\r\nConnection: close\r\n\r\n"
    if req_method == "HEAD":
        conn.write(out)
    else:
        conn.write(out + b)

class Server:
    # Serveur HTTP en écoute sur host:port (port 0 : choisi par le système, voir port()).
    # cert_file + key_file (PEM) : serveur HTTPS ; un client dont la poignée de main TLS échoue est ignoré.
    func init(host="127.0.0.1", port=0, cert_file=null, key_file=null):
        self.secure = cert_file != null
        if self.secure:
            self.listener = _tls.listen(host, port, cert_file, key_file, ["http/1.1"])
        else:
            self.listener = _tcp.listen(host, port)
        self.rejected = 0     # poignées de main TLS refusées
        self.timeout = 10.0   # délai d'inactivité de lecture d'une requête
        self.handled = 0
        self.errors = []      # messages des exceptions des gestionnaires (réponses 500)

    func port():
        return self.listener.port()

    func url(path="/"):
        a := self.listener.address()
        scheme := "http"
        if self.secure:
            scheme = "https"
        return scheme + "://" + a[0] + ":" + str(a[1]) + path

    # Accepte une connexion, lit sa requête, répond par handler(requête) (Response, str ou null). Une requête
    # mal formée reçoit 400, une exception du gestionnaire 500 (message dans errors).
    func handle_one(handler, accept_timeout=null):
        conn := null
        try:
            conn = self.listener.accept(accept_timeout)
        catch e:
            if self.secure and e.type == "TlsError":
                self.rejected += 1
                return
            raise(e)
        try:
            self._handle(conn, handler)
        catch e:
            conn.close()
            raise(e)
        conn.close()
        self.handled += 1

    func _handle(conn, handler):
        req := null
        try:
            line := conn.read_line(self.timeout, HEADER_LIMIT)
            if line == null or line == "":
                return
            parts := _s.split(line, " ")
            if len(parts) != 3 or not _s.starts_with(parts[2], "HTTP/"):
                raise("HttpError", "ligne de requête invalide « " + line + " »")
            hdrs := _read_headers(conn, self.timeout, "requête")
            body := _read_body(conn, hdrs, self.timeout, false, "requête")
            req = Request(_s.upper(parts[0]), parts[1], parts[2], hdrs, body, conn.peer_address())
        catch e:
            if e.type == "HttpError":
                _write_response(conn, "GET", text("requête invalide : " + e.message + "\n", 400))
                return
            raise(e)
        r := null
        try:
            r = _make_response(handler(req))
        catch e:
            append(self.errors, e.type + ": " + e.message)
            r = text("erreur interne du serveur\n", 500)
        _write_response(conn, req.method, r)

    # Sert les requêtes une par une (max_requests : null pour toujours).
    func serve(handler, max_requests=null):
        while max_requests == null or self.handled < max_requests:
            self.handle_one(handler)

    func close():
        self.listener.close()

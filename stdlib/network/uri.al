# ALEX STANDARD LIBRARY — network.uri
#
# URI génériques (RFC 3986) : découpage en composants SANS décodage (scheme, userinfo, host, port, path, query,
# fragment), validation stricte de la grammaire, résolution d'une référence relative (§5.2), normalisation et
# équivalence (§6), recomposition. Formes particulières : data: (RFC 2397), mailto: (RFC 6068), urn: (RFC 8141).
# Gabarits d'URI (RFC 6570, niveaux 1 à 4) : expand("/users{/id}{?q,lang}", variables).
#
# network.url s'appuie sur ce module pour les URL web (décodage, requêtes, IDNA).
#
# Erreurs : UrlError (URI invalide), TypeError.
#
# Exemple
#   use network.uri as uri
#   u := uri.parse("foo://user@example.com:8042/over/there?name=ferret#nose")
#   print(u.scheme, u.host, u.port, u.path, u.query, u.fragment)
#   print(uri.resolve("http://a/b/c/d;p?q", "../../g"))       # http://a/g
#   print(uri.expand("/search{?q,lang}", {"q": "chat", "lang": "fr"}))   # /search?q=chat&lang=fr
#   d := uri.parse_data("data:text/plain;charset=utf-8;base64,QWxleA==")
#   print(d.media_type, d.data)                                # text/plain Alex

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use network.encoding as _enc

func _fail(text, why):
    raise("UrlError", "URI invalide '" + str(text) + "' : " + why)

func _is_alpha(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

func _is_digit(c):
    return c >= '0' and c <= '9'

func _is_hex(c):
    return _is_digit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')

const _UNRESERVED_PUNCT := "-._~"
const _SUB_DELIMS := "!$&'()*+,;="
const _GEN_DELIMS := ":/?#[]@"

func _in(c, chars):
    for x in chars:
        if x == c:
            return true
    return false

func is_unreserved(c):
    return _is_alpha(c) or _is_digit(c) or _in(c, _UNRESERVED_PUNCT)

# Schéma valide : ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ).
func is_valid_scheme(s):
    if type(s) != "str" or s == "" or not _is_alpha(s[0]):
        return false
    for c in s:
        if not (_is_alpha(c) or _is_digit(c) or c == '+' or c == '-' or c == '.'):
            return false
    return true

class URI:
    # Composants bruts (encodés « %XX » tels quels). null : composant absent ; "" : présent mais vide.
    func init(scheme=null, userinfo=null, host=null, port=null, path="", query=null, fragment=null):
        self.scheme = scheme
        self.userinfo = userinfo
        self.host = host          # sans crochets pour IPv6 (« ::1 »)
        self.port = port          # int ou null
        self.path = path
        self.query = query
        self.fragment = fragment

    func has_authority():
        return self.host != null

    func is_absolute():
        return self.scheme != null

    # « userinfo@hôte:port » (crochets autour d'une adresse IPv6), ou null.
    func authority():
        if self.host == null:
            return null
        a := ""
        if self.userinfo != null:
            a = self.userinfo + "@"
        h := self.host
        if _s.contains(h, ":"):
            h = "[" + h + "]"
        a += h
        if self.port != null:
            a += ":" + str(self.port)
        return a

    # Recomposition (RFC 3986 §5.3).
    func str():
        out := ""
        if self.scheme != null:
            out += self.scheme + ":"
        if self.host != null:
            out += "//" + self.authority()
        out += self.path
        if self.query != null:
            out += "?" + self.query
        if self.fragment != null:
            out += "#" + self.fragment
        return out

    func __str__():
        return self.str()

    func __eq__(other):
        if type(other) == "str":
            return self.str() == other
        if not isinstance(other, URI):
            return false
        return self.str() == other.str()

    func copy():
        return URI(self.scheme, self.userinfo, self.host, self.port, self.path, self.query, self.fragment)

    # Segments du chemin, décodés.
    func segments():
        out := []
        p := self.path
        if _s.starts_with(p, "/"):
            p = _s.substring(p, 1, len(p))
        if p == "":
            return out
        for seg in _s.split(p, "/"):
            append(out, _enc.percent_decode(seg))
        return out

    func normalize():
        return normalize(self)

# Découpe une référence d'URI (absolue ou relative) — aucune validation des caractères (voir is_valid).
func parse(text):
    if isinstance(text, URI):
        return text.copy()
    if type(text) != "str":
        raise("TypeError", "network.uri.parse : str attendue (obtenu '" + type(text) + "')")
    rest := text
    scheme := null
    # schéma : avant le premier « : » s'il précède tout « / ? # »
    i := 0
    n := len(rest)
    while i < n:
        c := rest[i]
        if c == ':':
            cand := _s.substring(rest, 0, i)
            if is_valid_scheme(cand):
                scheme = _s.lower(cand)
                rest = _s.substring(rest, i + 1, n)
            break
        if c == '/' or c == '?' or c == '#':
            break
        i += 1
    fragment := null
    j := _s.find(rest, "#")
    if j >= 0:
        fragment = _s.substring(rest, j + 1, len(rest))
        rest = _s.substring(rest, 0, j)
    query := null
    q := _s.find(rest, "?")
    if q >= 0:
        query = _s.substring(rest, q + 1, len(rest))
        rest = _s.substring(rest, 0, q)
    userinfo := null
    host := null
    port := null
    path := rest
    if _s.starts_with(rest, "//"):
        rest = _s.substring(rest, 2, len(rest))
        k := _s.find(rest, "/")
        auth := rest
        path = ""
        if k >= 0:
            auth = _s.substring(rest, 0, k)
            path = _s.substring(rest, k, len(rest))
        at := -1
        m := 0
        while m < len(auth):
            if auth[m] == '@':
                at = m
            m += 1
        if at >= 0:
            userinfo = _s.substring(auth, 0, at)
            auth = _s.substring(auth, at + 1, len(auth))
        hostport := auth
        if _s.starts_with(hostport, "["):
            e := _s.find(hostport, "]")
            if e < 0:
                _fail(text, "« ] » manquant")
            host = _s.substring(hostport, 1, e)
            after := _s.substring(hostport, e + 1, len(hostport))
            if after != "":
                if not _s.starts_with(after, ":"):
                    _fail(text, "caractère inattendu après « ] »")
                port = _port(text, _s.substring(after, 1, len(after)))
        else:
            c := -1
            m = len(hostport) - 1
            while m >= 0:
                if hostport[m] == ':':
                    c = m
                    break
                m -= 1
            if c >= 0:
                host = _s.substring(hostport, 0, c)
                port = _port(text, _s.substring(hostport, c + 1, len(hostport)))
            else:
                host = hostport
    return URI(scheme, userinfo, host, port, path, query, fragment)

func _port(text, p):
    if p == "":
        return null      # « hôte: » : port vide permis par la grammaire (équivaut à l'absence)
    for c in p:
        if not _is_digit(c):
            _fail(text, "port non numérique « " + p + " »")
    if len(p) > 5 or to_int(p) > 65535:
        _fail(text, "port hors de 0..65535")
    return to_int(p)

# Vrai si chaque caractère d'un composant est permis (`allowed` en plus des non réservés et des « %XX » valides).
func _valid_component(s, allowed):
    i := 0
    n := len(s)
    while i < n:
        c := s[i]
        if c == '%':
            if i + 2 >= n or not _is_hex(s[i + 1]) or not _is_hex(s[i + 2]):
                return false
            i += 3
            continue
        if not (is_unreserved(c) or _in(c, _SUB_DELIMS) or _in(c, allowed) or _s.ord(c) >= 128):
            return false
        i += 1
    return true

# Vrai si text respecte la grammaire de RFC 3986 (les caractères non ASCII des IRI, RFC 3987, sont acceptés).
# absolute=true : un schéma est exigé.
func is_valid(text, absolute=false):
    if type(text) != "str":
        return false
    for c in text:
        if c == ' ' or c == '"' or c == '<' or c == '>' or c == '\\' or c == '^' or c == '`' or c == '{' or c == '|' or c == '}' or _s.ord(c) < 32 or _s.ord(c) == 127:
            return false
    u := null
    try:
        u = parse(text)
    catch e:
        return false
    if absolute and u.scheme == null:
        return false
    if u.scheme == null and u.host == null:
        # référence relative : le premier segment d'un chemin sans schéma ne contient pas « : »
        first := u.path
        sl := _s.find(first, "/")
        if sl >= 0:
            first = _s.substring(first, 0, sl)
        if _s.contains(first, ":"):
            return false
    if u.userinfo != null and not _valid_component(u.userinfo, ":"):
        return false
    if u.host != null:
        if _s.contains(u.host, ":"):
            if not _valid_component(u.host, ":."):
                return false
        elif not _valid_component(u.host, ""):
            return false
    if u.host != null and u.path != "" and not _s.starts_with(u.path, "/"):
        return false
    if u.host == null and _s.starts_with(u.path, "//"):
        return false
    if not _valid_component(u.path, ":@/"):
        return false
    if u.query != null and not _valid_component(u.query, ":@/?"):
        return false
    if u.fragment != null and not _valid_component(u.fragment, ":@/?"):
        return false
    return true

# ---------------------------------------------------------------- résolution (RFC 3986 §5.2)

# Supprime les segments « . » et « .. » d'un chemin (§5.2.4).
func remove_dot_segments(path):
    inp := path
    out := []
    while inp != "":
        if _s.starts_with(inp, "../"):
            inp = _s.substring(inp, 3, len(inp))
        elif _s.starts_with(inp, "./"):
            inp = _s.substring(inp, 2, len(inp))
        elif _s.starts_with(inp, "/./"):
            inp = _s.substring(inp, 2, len(inp))
        elif inp == "/.":
            inp = "/"
        elif _s.starts_with(inp, "/../"):
            inp = _s.substring(inp, 3, len(inp))
            if len(out) > 0:
                out = out[0:len(out) - 1]
        elif inp == "/..":
            inp = "/"
            if len(out) > 0:
                out = out[0:len(out) - 1]
        elif inp == "." or inp == "..":
            inp = ""
        else:
            start := 0
            if _s.starts_with(inp, "/"):
                start = 1
            k := start
            while k < len(inp) and inp[k] != '/':
                k += 1
            append(out, _s.substring(inp, 0, k))
            inp = _s.substring(inp, k, len(inp))
    return _s.join("", out)

func _merge(base, ref_path):
    if base.host != null and base.path == "":
        return "/" + ref_path
    k := len(base.path) - 1
    while k >= 0 and base.path[k] != '/':
        k -= 1
    if k < 0:
        return ref_path
    return _s.substring(base.path, 0, k + 1) + ref_path

# Résout une référence (relative ou absolue) par rapport à une URI de base ABSOLUE ; rend une URI.
func resolve_uri(base, reference):
    b := parse(base)
    r := parse(reference)
    if b.scheme == null:
        _fail(b.str(), "l'URI de base doit être absolue")
    t := URI()
    if r.scheme != null:
        t.scheme = r.scheme
        t.userinfo = r.userinfo
        t.host = r.host
        t.port = r.port
        t.path = remove_dot_segments(r.path)
        t.query = r.query
    else:
        if r.host != null:
            t.userinfo = r.userinfo
            t.host = r.host
            t.port = r.port
            t.path = remove_dot_segments(r.path)
            t.query = r.query
        else:
            if r.path == "":
                t.path = b.path
                if r.query != null:
                    t.query = r.query
                else:
                    t.query = b.query
            else:
                if _s.starts_with(r.path, "/"):
                    t.path = remove_dot_segments(r.path)
                else:
                    t.path = remove_dot_segments(_merge(b, r.path))
                t.query = r.query
            t.userinfo = b.userinfo
            t.host = b.host
            t.port = b.port
        t.scheme = b.scheme
    t.fragment = r.fragment
    return t

# Comme resolve_uri, rendu sous forme de texte.
func resolve(base, reference):
    return resolve_uri(base, reference).str()

# ---------------------------------------------------------------- normalisation (RFC 3986 §6)

const _HEXU := "0123456789ABCDEF"

# Normalise les « %XX » : chiffres en majuscules, octets non réservés décodés.
func normalize_percent(s):
    if s == null:
        return null
    out := []
    i := 0
    n := len(s)
    while i < n:
        c := s[i]
        if c == '%' and i + 2 < n and _is_hex(s[i + 1]) and _is_hex(s[i + 2]):
            v := _hexv(s[i + 1]) * 16 + _hexv(s[i + 2])
            ch := _s.chr(v)
            if v < 128 and is_unreserved(ch):
                append(out, str(ch))
            else:
                append(out, "%" + str(_HEXU[v >> 4]) + str(_HEXU[v & 15]))
            i += 3
            continue
        append(out, str(c))
        i += 1
    return _s.join("", out)

func _hexv(c):
    if _is_digit(c):
        return _s.ord(c) - 48
    if c >= 'a' and c <= 'f':
        return _s.ord(c) - 87
    return _s.ord(c) - 55

_DEFAULT_PORTS := {"http": 80, "https": 443, "ws": 80, "wss": 443, "ftp": 21}

# Forme normalisée : schéma et hôte en minuscules, « %XX » normalisés, segments « . » / « .. » retirés, port par
# défaut du schéma retiré, chemin vide d'une URI avec autorité remplacé par « / ».
func normalize(u):
    x := parse(u)
    if x.host != null:
        x.host = _s.lower(normalize_percent(x.host))
    x.userinfo = normalize_percent(x.userinfo)
    x.path = remove_dot_segments(normalize_percent(x.path))
    x.query = normalize_percent(x.query)
    x.fragment = normalize_percent(x.fragment)
    if x.scheme != null and x.port != null and contains_key(_DEFAULT_PORTS, x.scheme) and _DEFAULT_PORTS[x.scheme] == x.port:
        x.port = null
    if x.host != null and x.path == "":
        x.path = "/"
    return x

# Vrai si deux URI désignent la même ressource après normalisation.
func equivalent(a, b):
    return normalize(a).str() == normalize(b).str()

# ---------------------------------------------------------------- data: (RFC 2397)

class DataURI:
    func init(media_type, params, is_base64, data):
        self.media_type = media_type      # « text/plain » par défaut
        self.params = params              # dict (charset...)
        self.is_base64 = is_base64
        self.data = data                  # octets décodés (str brute)

    func charset():
        if contains_key(self.params, "charset"):
            return self.params["charset"]
        return null

    func text():
        return _enc.decode_charset(self.data, self.charset(), "replace")

    func str():
        return make_data(self.data, self.media_type, self.params, self.is_base64)

func parse_data(text):
    if type(text) != "str" or not _s.starts_with(_s.lower(text), "data:"):
        _fail(text, "schéma data: attendu")
    rest := _s.substring(text, 5, len(text))
    comma := _s.find(rest, ",")
    if comma < 0:
        _fail(text, "« , » manquante dans un URI data:")
    meta := _s.substring(rest, 0, comma)
    payload := _s.substring(rest, comma + 1, len(rest))
    media := "text/plain"
    params := {}
    b64 := false
    parts := _s.split(meta, ";")
    idx := 0
    for p in parts:
        t := _s.trim(p)
        if idx == 0:
            if t != "":
                media = _s.lower(t)
            elif len(parts) == 1:
                params["charset"] = "US-ASCII"
        elif _s.lower(t) == "base64" and idx == len(parts) - 1:
            b64 = true
        elif t != "":
            eq := _s.find(t, "=")
            if eq > 0:
                params[_s.lower(_s.substring(t, 0, eq))] = _enc.percent_decode(_s.substring(t, eq + 1, len(t)))
        idx += 1
    if idx == 1 and media == "text/plain" and not contains_key(params, "charset"):
        params["charset"] = "US-ASCII"
    data := null
    if b64:
        data = _enc.base64_decode(_enc.percent_decode(payload))
    else:
        data = _enc.percent_decode(payload)
    return DataURI(media, params, b64, data)

# URI data: pour des octets (base64 par défaut ; base64=false : encodage « %XX »).
func make_data(data, media_type="application/octet-stream", params=null, base64=true):
    meta := media_type
    if params != null:
        for k in keys(params):
            meta += ";" + k + "=" + _enc.percent_encode(str(params[k]))
    raw := data
    if type(data) == "list":
        raw = _n.from_bytes(data)
    if base64:
        return "data:" + meta + ";base64," + _enc.base64_encode(raw)
    return "data:" + meta + "," + _enc.percent_encode(raw, "/:;=,!$&'()*+@")

# ---------------------------------------------------------------- mailto: (RFC 6068)

class MailtoURI:
    func init(to, headers):
        self.to = to              # list[str] d'adresses
        self.headers = headers    # dict nom en minuscules -> valeur (subject, cc, body...)

    func subject():
        if contains_key(self.headers, "subject"):
            return self.headers["subject"]
        return null

    func body():
        if contains_key(self.headers, "body"):
            return self.headers["body"]
        return null

func parse_mailto(text):
    if type(text) != "str" or not _s.starts_with(_s.lower(text), "mailto:"):
        _fail(text, "schéma mailto: attendu")
    rest := _s.substring(text, 7, len(text))
    q := _s.find(rest, "?")
    addrs := rest
    query := ""
    if q >= 0:
        addrs = _s.substring(rest, 0, q)
        query = _s.substring(rest, q + 1, len(rest))
    to := []
    for a in _s.split(addrs, ","):
        d := _s.trim(_enc.percent_decode(a))
        if d != "":
            append(to, d)
    headers := {}
    if query != "":
        for pair in _s.split(query, "&"):
            eq := _s.find(pair, "=")
            if eq <= 0:
                continue
            name := _s.lower(_enc.percent_decode(_s.substring(pair, 0, eq)))
            value := _enc.percent_decode(_s.substring(pair, eq + 1, len(pair)))
            if name == "to":
                for a in _s.split(value, ","):
                    if _s.trim(a) != "":
                        append(to, _s.trim(a))
            else:
                headers[name] = value
    return MailtoURI(to, headers)

func make_mailto(to, subject=null, body=null, cc=null):
    addrs := to
    if type(to) == "list":
        addrs = _s.join(",", to)
    out := "mailto:" + _enc.percent_encode(addrs, "@,")
    q := []
    if subject != null:
        append(q, "subject=" + _enc.percent_encode(subject))
    if cc != null:
        c := cc
        if type(cc) == "list":
            c = _s.join(",", cc)
        append(q, "cc=" + _enc.percent_encode(c, "@,"))
    if body != null:
        append(q, "body=" + _enc.percent_encode(body))
    if len(q) > 0:
        out += "?" + _s.join("&", q)
    return out

# ---------------------------------------------------------------- urn: (RFC 8141)

class URN:
    func init(nid, nss, rest):
        self.nid = nid            # identifiant d'espace de noms, en minuscules (« isbn »)
        self.nss = nss            # chaîne propre à l'espace (« 0451450523 »)
        self.rest = rest          # composants r/q/f éventuels, bruts

    func str():
        return "urn:" + self.nid + ":" + self.nss + self.rest

func parse_urn(text):
    if type(text) != "str" or not _s.starts_with(_s.lower(text), "urn:"):
        _fail(text, "schéma urn: attendu")
    rest := _s.substring(text, 4, len(text))
    c := _s.find(rest, ":")
    if c < 2 or c > 32:
        _fail(text, "identifiant d'espace de noms (NID) invalide")
    nid := _s.substring(rest, 0, c)
    for ch in nid:
        if not (_is_alpha(ch) or _is_digit(ch) or ch == '-'):
            _fail(text, "NID invalide « " + nid + " »")
    nss := _s.substring(rest, c + 1, len(rest))
    tail := ""
    for mark in ["?+", "?=", "#"]:
        k := _s.find(nss, mark)
        if k >= 0:
            tail = _s.substring(nss, k, len(nss)) + tail
            nss = _s.substring(nss, 0, k)
    if nss == "":
        _fail(text, "NSS vide")
    return URN(_s.lower(nid), nss, tail)

# ---------------------------------------------------------------- gabarits d'URI (RFC 6570)

func _pct(s, allow_reserved):
    if allow_reserved:
        # garde les réservés et les « %XX » déjà présents
        out := []
        i := 0
        n := len(s)
        while i < n:
            c := s[i]
            if c == '%' and i + 2 < n and _is_hex(s[i + 1]) and _is_hex(s[i + 2]):
                append(out, _s.substring(s, i, i + 3))
                i += 3
                continue
            if _in(c, _GEN_DELIMS) or _in(c, _SUB_DELIMS):
                append(out, str(c))
            else:
                append(out, _enc.percent_encode(str(c)))
            i += 1
        return _s.join("", out)
    return _enc.percent_encode(s)

func _str_value(v):
    if v == true:
        return "true"
    if v == false:
        return "false"
    return str(v)

func _prefix(s, n):
    if n == null or len(s) <= n:
        return s
    return _s.substring(s, 0, n)

# Développe un gabarit RFC 6570 (opérateurs + # . / ; ? &, modificateurs :n et *) avec un dict de variables
# (valeurs str/nombre, list ou dict ; null ou absente : ignorée).
func expand(template, variables):
    out := ""
    i := 0
    n := len(template)
    while i < n:
        c := template[i]
        if c != '{':
            out += str(c)
            i += 1
            continue
        e := i + 1
        while e < n and template[e] != '}':
            e += 1
        if e >= n:
            raise("UrlError", "gabarit d'URI : « } » manquante dans '" + template + "'")
        out += _expand_expr(_s.substring(template, i + 1, e), variables, template)
        i = e + 1
    return out

func _expand_expr(expr, vars, template):
    op := ""
    if expr != "" and _in(expr[0], "+#./;?&"):
        op = str(expr[0])
        expr = _s.substring(expr, 1, len(expr))
    first := ""
    sep := ","
    named := false
    ifemp := ""
    allow := false
    if op == "+":
        allow = true
    elif op == "#":
        first = "#"
        allow = true
    elif op == ".":
        first = "."
        sep = "."
    elif op == "/":
        first = "/"
        sep = "/"
    elif op == ";":
        first = ";"
        sep = ";"
        named = true
    elif op == "?":
        first = "?"
        sep = "&"
        named = true
        ifemp = "="
    elif op == "&":
        first = "&"
        sep = "&"
        named = true
        ifemp = "="
    parts := []
    for spec in _s.split(expr, ","):
        name := spec
        explode := false
        maxlen := null
        if _s.ends_with(name, "*"):
            explode = true
            name = _s.substring(name, 0, len(name) - 1)
        colon := _s.find(name, ":")
        if colon >= 0:
            maxlen = to_int(_s.substring(name, colon + 1, len(name)))
            name = _s.substring(name, 0, colon)
        if name == "":
            raise("UrlError", "gabarit d'URI : nom de variable vide dans '" + template + "'")
        if not contains_key(vars, name):
            continue
        v := vars[name]
        if v == null:
            continue
        t := type(v)
        if t == "list" or t == "tuple":
            if len(v) == 0:
                continue
            items := []
            for x in v:
                enc := _pct(_str_value(x), allow)
                if explode and named:
                    if enc == "":
                        append(items, name + ifemp)
                    else:
                        append(items, name + "=" + enc)
                else:
                    append(items, enc)
            if explode:
                append(parts, _s.join(sep, items))
            elif named:
                append(parts, name + "=" + _s.join(",", items))
            else:
                append(parts, _s.join(",", items))
        elif t == "dict":
            ks := keys(v)
            if len(ks) == 0:
                continue
            items := []
            for k in ks:
                ek := _pct(str(k), allow)
                ev := _pct(_str_value(v[k]), allow)
                if explode:
                    append(items, ek + "=" + ev)
                else:
                    append(items, ek)
                    append(items, ev)
            if explode:
                append(parts, _s.join(sep, items))
            elif named:
                append(parts, name + "=" + _s.join(",", items))
            else:
                append(parts, _s.join(",", items))
        else:
            s := _pct(_prefix(_str_value(v), maxlen), allow)
            if named:
                if s == "":
                    append(parts, name + ifemp)
                else:
                    append(parts, name + "=" + s)
            else:
                append(parts, s)
    if len(parts) == 0:
        return ""
    return first + _s.join(sep, parts)

# Noms des variables d'un gabarit.
func template_variables(template):
    out := []
    i := 0
    n := len(template)
    while i < n:
        if template[i] == '{':
            e := i + 1
            while e < n and template[e] != '}':
                e += 1
            expr := _s.substring(template, i + 1, e)
            if expr != "" and _in(expr[0], "+#./;?&"):
                expr = _s.substring(expr, 1, len(expr))
            for spec in _s.split(expr, ","):
                nm := spec
                if _s.ends_with(nm, "*"):
                    nm = _s.substring(nm, 0, len(nm) - 1)
                k := _s.find(nm, ":")
                if k >= 0:
                    nm = _s.substring(nm, 0, k)
                if nm != "":
                    seen := false
                    for x in out:
                        if x == nm:
                            seen = true
                    if not seen:
                        append(out, nm)
            i = e
        i += 1
    return out

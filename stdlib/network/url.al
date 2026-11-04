# ALEX STANDARD LIBRARY — network.url
#
# URL web (http, https, ws, wss, ftp... et tout schéma hiérarchique) : analyse avec base relative, encodage des
# caractères non permis (espaces, non ASCII) comme un navigateur, noms d'hôte internationalisés (IDNA), port
# effectif, origine, paramètres de requête (lecture, ajout, suppression), recomposition.
#
# Fonctions d'encodage à la Python : quote, quote_plus, unquote, unquote_plus, urlencode, parse_qs, parse_qsl.
#
# Erreurs : UrlError (URL invalide), TypeError.
#
# Exemple
#   use network.url as url
#   u := url.parse("https://Bücher.example/a b/c?x=1&y=é#top")
#   print(u.host, u.effective_port(), u.path, u.query)   # xn--bcher-kva.example 443 /a%20b/c x=1&y=%C3%A9
#   print(u.param("y"), u.origin())                       # é https://xn--bcher-kva.example
#   v := u.join("../d?z=2")                               # https://xn--bcher-kva.example/d?z=2
#   w := u.with_params({"page": 2})                       # ...?x=1&y=%C3%A9&page=2
#   print(url.urlencode({"q": "chat noir", "n": [1, 2]})) # q=chat+noir&n=1&n=2

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use network.uri as _uri
use network.encoding as _enc
use network.constants as _c
use network.ipaddress as _ip

func _fail(text, why):
    raise("UrlError", "URL invalide '" + str(text) + "' : " + why)

# Schémas « spéciaux » : autorité obligatoire, chemin vide -> « / ».
const SPECIAL_SCHEMES := ["http", "https", "ws", "wss", "ftp", "ftps"]

func is_special(scheme):
    for s in SPECIAL_SCHEMES:
        if s == scheme:
            return true
    return false

# ---------------------------------------------------------------- encodage

# Encode pour un composant d'URL : tout sauf les non réservés et `safe` (« / » par défaut, comme Python).
func quote(text, safe="/"):
    return _enc.percent_encode(str(text), safe)

# Comme quote, l'espace devenant « + » (formulaires).
func quote_plus(text, safe=""):
    return _enc.percent_encode(str(text), safe, true)

func unquote(text):
    return _enc.percent_decode(text)

func unquote_plus(text):
    return _enc.percent_decode(text, true)

# Encode les caractères qui ne peuvent pas figurer tels quels dans une URL (espace, non ASCII, contrôles, " < > ` {
# } | \ ^) en gardant les réservés et les « %XX » déjà présents. extra : caractères à encoder en plus.
func _escape_component(s, extra=""):
    if s == null:
        return null
    out := []
    i := 0
    n := len(s)
    while i < n:
        c := s[i]
        o := _s.ord(c)
        if c == '%':
            if i + 2 < n and _is_hex(s[i + 1]) and _is_hex(s[i + 2]):
                append(out, "%")
            else:
                append(out, "%25")
        elif o <= 32 or o >= 127 or c == '"' or c == '<' or c == '>' or c == '`' or c == '{' or c == '}' or c == '|' or c == '\\' or c == '^' or _in(c, extra):
            append(out, _enc.percent_encode(str(c)))
        else:
            append(out, str(c))
        i += 1
    return _s.join("", out)

func _is_hex(c):
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F')

func _in(c, chars):
    for x in chars:
        if x == c:
            return true
    return false

# « a=1&b=x+y » depuis un dict, une liste de paires ou un dict de listes (doseq : une list donne plusieurs paires).
func urlencode(params, doseq=true, safe=""):
    pairs := _pairs(params)
    out := []
    for p in pairs:
        k := quote_plus(_str_value(p[0]), safe)
        v := p[1]
        if doseq and (type(v) == "list" or type(v) == "tuple"):
            for x in v:
                append(out, k + "=" + quote_plus(_str_value(x), safe))
        else:
            append(out, k + "=" + quote_plus(_str_value(v), safe))
    return _s.join("&", out)

func _str_value(v):
    if v == null:
        return ""
    if v == true:
        return "true"
    if v == false:
        return "false"
    return str(v)

func _pairs(params):
    if params == null:
        return []
    if type(params) == "dict":
        out := []
        for k in keys(params):
            append(out, [k, params[k]])
        return out
    if type(params) == "list" or type(params) == "tuple":
        out := []
        for p in params:
            append(out, [p[0], p[1]])
        return out
    raise("TypeError", "network.url : paramètres dict ou liste de paires attendus (obtenu '" + type(params) + "')")

# Paires [nom, valeur] décodées d'une chaîne de requête, dans l'ordre. keep_blank : garder « a= » et « a ».
func parse_qsl(query, keep_blank=true):
    out := []
    if query == null or query == "":
        return out
    q := query
    if _s.starts_with(q, "?"):
        q = _s.substring(q, 1, len(q))
    for part in _s.split(q, "&"):
        if part == "":
            continue
        eq := _s.find(part, "=")
        name := part
        value := ""
        if eq >= 0:
            name = _s.substring(part, 0, eq)
            value = _s.substring(part, eq + 1, len(part))
        if value == "" and not keep_blank:
            continue
        append(out, [unquote_plus(name), unquote_plus(value)])
    return out

# dict nom -> list des valeurs.
func parse_qs(query, keep_blank=true):
    out := {}
    for p in parse_qsl(query, keep_blank):
        if not contains_key(out, p[0]):
            out[p[0]] = []
        append(out[p[0]], p[1])
    return out

# ---------------------------------------------------------------- URL

class URL:
    func init(scheme, username, password, host, port, path, query, fragment):
        self.scheme = scheme          # minuscules
        self.username = username      # décodé, ou null
        self.password = password      # décodé, ou null
        self.host = host              # forme ASCII en minuscules (IDNA), sans crochets ; null sans autorité
        self.port = port              # port explicite (int) ou null
        self.path = path              # encodé (« /a%20b »)
        self.query = query            # encodée, sans « ? » ; null si absente
        self.fragment = fragment      # encodé, sans « # » ; null si absent

    # Port à utiliser : explicite, sinon celui du schéma.
    func effective_port():
        if self.port != null:
            return self.port
        return _c.default_port(self.scheme)

    func is_secure():
        return _c.is_secure_scheme(self.scheme)

    func is_default_port():
        return self.port == null or self.port == _c.default_port(self.scheme)

    # Hôte en Unicode (« bücher.example »).
    func host_unicode():
        if self.host == null:
            return null
        return _enc.idna_decode(self.host)

    # Hôte tel qu'il s'écrit dans une URL (crochets pour IPv6).
    func host_text():
        if self.host == null:
            return ""
        if _s.contains(self.host, ":"):
            return "[" + self.host + "]"
        return self.host

    # « hôte[:port] » (port omis s'il est celui du schéma).
    func netloc():
        h := self.host_text()
        if self.port != null and not self.is_default_port():
            h += ":" + str(self.port)
        return h

    # « utilisateur:motdepasse@hôte:port ».
    func authority():
        a := ""
        if self.username != null:
            a = quote(self.username, "!$&'()*+,;=")
            if self.password != null:
                a += ":" + quote(self.password, "!$&'()*+,;=")
            a += "@"
        return a + self.netloc()

    # Origine (RFC 6454) : « schéma://hôte[:port] », ou « null » sans hôte.
    func origin():
        if self.host == null:
            return "null"
        return self.scheme + "://" + self.netloc()

    # Cible d'une requête HTTP : chemin + « ?requête ».
    func target():
        p := self.path
        if p == "":
            p = "/"
        if self.query != null:
            return p + "?" + self.query
        return p

    func str():
        out := self.scheme + ":"
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
        if other == null:
            return false
        if type(other) == "str":
            try:
                return parse(other).str() == self.str()
            catch e:
                return false
        if not isinstance(other, URL):
            return false
        return self.str() == other.str()

    func copy():
        return URL(self.scheme, self.username, self.password, self.host, self.port, self.path, self.query, self.fragment)

    # Forme sans identifiants ni fragment (journaux, en-tête Referer).
    func redacted():
        u := self.copy()
        u.username = null
        u.password = null
        u.fragment = null
        return u

    # URL absolue d'une référence relative (« ../x », « /y », « ?q », « //hôte/z », URL complète).
    func join(reference):
        return parse(reference, self)

    # Segments du chemin, décodés.
    func path_segments():
        out := []
        p := self.path
        if _s.starts_with(p, "/"):
            p = _s.substring(p, 1, len(p))
        if p == "":
            return out
        for seg in _s.split(p, "/"):
            append(out, unquote(seg))
        return out

    # Dernier segment décodé (« fichier.txt »), "" si le chemin finit par « / ».
    func filename():
        segs := self.path_segments()
        if len(segs) == 0 or _s.ends_with(self.path, "/"):
            return ""
        return segs[len(segs) - 1]

    # Paramètres de requête décodés : liste de [nom, valeur].
    func params():
        return parse_qsl(self.query)

    # Dernière valeur du paramètre `name`, ou default.
    func param(name, default=null):
        v := default
        for p in self.params():
            if p[0] == name:
                v = p[1]
        return v

    func param_list(name):
        out := []
        for p in self.params():
            if p[0] == name:
                append(out, p[1])
        return out

    func has_param(name):
        for p in self.params():
            if p[0] == name:
                return true
        return false

    func query_dict():
        d := {}
        for p in self.params():
            d[p[0]] = p[1]
        return d

    # Copies modifiées ---------------------------------------------------------------------------------

    func with_scheme(scheme):
        u := self.copy()
        u.scheme = _s.lower(scheme)
        return u

    func with_host(host):
        u := self.copy()
        u.host = _normalize_host(host, host)
        return u

    func with_port(port):
        u := self.copy()
        u.port = port
        return u

    func with_path(path):
        u := self.copy()
        p := _escape_component(path, "?#")
        if not _s.starts_with(p, "/") and u.host != null:
            p = "/" + p
        u.path = p
        return u

    # Requête remplacée : str brute (encodée) ou dict / liste de paires (encodés ici) ; null la retire.
    func with_query(query):
        u := self.copy()
        if query == null:
            u.query = null
        elif type(query) == "str":
            q := query
            if _s.starts_with(q, "?"):
                q = _s.substring(q, 1, len(q))
            u.query = _escape_component(q, "#")
        else:
            u.query = urlencode(query)
        return u

    # Ajoute des paramètres à la requête existante.
    func with_params(params):
        u := self.copy()
        extra := urlencode(params)
        if extra == "":
            return u
        if u.query == null or u.query == "":
            u.query = extra
        else:
            u.query = u.query + "&" + extra
        return u

    # Fixe un paramètre (remplace toutes ses occurrences).
    func set_param(name, value):
        kept := []
        for p in self.params():
            if p[0] != name:
                append(kept, p)
        append(kept, [name, value])
        return self.with_query(kept)

    func without_param(name):
        kept := []
        for p in self.params():
            if p[0] != name:
                append(kept, p)
        if len(kept) == 0:
            return self.with_query(null)
        return self.with_query(kept)

    func with_fragment(fragment):
        u := self.copy()
        if fragment == null:
            u.fragment = null
        else:
            u.fragment = _escape_component(fragment)
        return u

    func with_credentials(username, password=null):
        u := self.copy()
        u.username = username
        u.password = password
        return u

# Hôte normalisé : minuscules, IDNA pour les noms non ASCII, IPv6 sans crochets et canonique, caractères vérifiés.
func _normalize_host(host, text):
    if host == null:
        return null
    h := unquote(host)
    if _s.starts_with(h, "[") and _s.ends_with(h, "]"):
        h = _s.substring(h, 1, len(h) - 1)
    if _s.contains(h, ":"):
        try:
            return _ip.IPv6Address(h).str()
        catch e:
            _fail(text, "adresse IPv6 invalide « " + h + " »")
    ascii := true
    for c in h:
        if _s.ord(c) >= 128:
            ascii = false
    if not ascii:
        h = _enc.idna_encode(h)
    h = _s.lower(h)
    for c in h:
        o := _s.ord(c)
        if o <= 32 or c == '#' or c == '%' or c == '/' or c == ':' or c == '<' or c == '>' or c == '?' or c == '@' or c == '[' or c == '\\' or c == ']' or c == '^' or c == '|' or o == 127:
            _fail(text, "caractère interdit dans l'hôte : « " + str(c) + " »")
    return h

# Analyse une URL absolue, ou une référence relative à `base` (URL ou texte).
func parse(text, base=null):
    if isinstance(text, URL) and base == null:
        return text.copy()
    if type(text) != "str":
        raise("TypeError", "network.url.parse : str attendue (obtenu '" + type(text) + "')")
    t := _s.trim(text)
    # tabulations et sauts de ligne retirés, comme le fait un navigateur
    t = _s.replace(_s.replace(_s.replace(t, "\t", ""), "\n", ""), "\r", "")
    if base != null:
        b := base
        if type(b) == "str":
            b = parse(b)
        if _s.contains(t, "\\") and is_special(b.scheme):
            t = _s.replace(t, "\\", "/")
        t = _uri.resolve(b.str(), _escape_component(t))
    u := null
    try:
        u = _uri.parse(t)
    catch e:
        _fail(text, e.message)
    if u.scheme == null:
        _fail(text, "schéma manquant (URL absolue attendue, ou passer base)")
    scheme := u.scheme
    special := is_special(scheme)
    if special and (u.host == null or u.host == ""):
        _fail(text, "hôte manquant")
    username := null
    password := null
    if u.userinfo != null:
        c := _s.find(u.userinfo, ":")
        if c >= 0:
            username = unquote(_s.substring(u.userinfo, 0, c))
            password = unquote(_s.substring(u.userinfo, c + 1, len(u.userinfo)))
        else:
            username = unquote(u.userinfo)
    host := null
    if u.host != null:
        host = _normalize_host(u.host, text)
    port := u.port
    path := _escape_component(u.path)
    if special:
        path = _uri.remove_dot_segments(path)
        if path == "":
            path = "/"
    query := _escape_component(u.query)
    fragment := _escape_component(u.fragment)
    return URL(scheme, username, password, host, port, path, query, fragment)

# Vrai si text est une URL absolue valide (schemes : liste de schémas permis, ou null).
func is_url(text, schemes=null):
    try:
        u := parse(text)
        if schemes == null:
            return true
        for s in schemes:
            if s == u.scheme:
                return true
        return false
    catch e:
        return false

# URL absolue d'une référence par rapport à une base (texte).
func join(base, reference):
    return parse(reference, base).str()

# Forme normalisée (texte) : minuscules, port par défaut retiré, « %XX » normalisés, segments « . » retirés.
func normalize(text):
    u := parse(text)
    if u.is_default_port():
        u.port = null
    u.path = _uri.normalize_percent(u.path)
    if u.query != null:
        u.query = _uri.normalize_percent(u.query)
    if u.fragment != null:
        u.fragment = _uri.normalize_percent(u.fragment)
    return u.str()

# Vrai si deux URL ont la même origine (schéma, hôte, port).
func same_origin(a, b):
    ua := parse(a)
    ub := parse(b)
    return ua.scheme == ub.scheme and ua.host == ub.host and ua.effective_port() == ub.effective_port()

# Construit une URL à partir de ses parties (path et fragment non encodés ; query : dict, liste ou str encodée).
func build(scheme, host, path="/", query=null, fragment=null, port=null, username=null, password=null):
    u := URL(_s.lower(scheme), username, password, _normalize_host(host, host), port, "/", null, null)
    u = u.with_path(_s.join("/", _quote_segments(path)))
    if query != null:
        u = u.with_query(query)
    if fragment != null:
        u = u.with_fragment(fragment)
    return u

func _quote_segments(path):
    out := []
    for seg in _s.split(path, "/"):
        append(out, quote(seg, "!$&'()*+,;=:@"))
    return out

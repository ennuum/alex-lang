# ALEX STANDARD LIBRARY — network.http_cookies
#
# Cookies HTTP (RFC 6265 et ses mises à jour : SameSite, préfixes __Secure- / __Host-).
#
#   Cookie                    un cookie et ses attributs ; set_cookie_header() pour un serveur
#   parse_set_cookie          en-tête Set-Cookie -> Cookie (analyse tolérante du §5.2)
#   parse_cookie_header       en-tête Cookie reçu par un serveur -> dict nom -> valeur
#   format_cookie_header      dict ou liste de Cookie -> « a=1; b=2 »
#   CookieJar                 bocal d'un client : règles de domaine et de chemin, Secure, expiration, ordre
#                             d'envoi ; extract(en-têtes, url) après une réponse, header_for(url) avant une
#                             requête ; save / load en JSON.
#
# Sécurité : un cookie n'est accepté que pour un domaine qui contient l'hôte de la réponse et n'est pas un simple
# suffixe public d'un seul niveau (« com », « fr ») ; Secure n'est accepté et renvoyé que sur https ; les
# préfixes __Secure- et __Host- sont contrôlés.
#
# Exemple
#   use network.http_cookies as ck
#   jar := ck.CookieJar()
#   jar.set_from_header("sid=abc; Path=/; HttpOnly; Max-Age=3600", "https://exemple.org/connexion")
#   print(jar.header_for("https://exemple.org/compte"))     # sid=abc
#   c := ck.Cookie("theme", "sombre", max_age=86400, same_site="Lax")
#   print(c.set_cookie_header())                             # theme=sombre; Max-Age=86400; Path=/; SameSite=Lax

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use json as _json
use io as _io
use time as _time
use network.url as _url
use network.http_headers as _hh
use network.ipaddress as _ip

func _now():
    return _time.time()

class Cookie:
    func init(name, value, domain=null, path="/", expires=null, max_age=null, secure=false, http_only=false, same_site=null, host_only=true, partitioned=false):
        if type(name) != "str" or not _valid_name(name):
            raise("ArgumentError", "http_cookies.Cookie : nom invalide « " + str(name) + " »")
        v := str(value)
        if not _valid_value(v):
            raise("ArgumentError", "http_cookies.Cookie : valeur invalide pour « " + name + " » (espace, « ; », « , » ou guillemet interdits)")
        self.name = name
        self.value = v
        self.domain = domain          # minuscules, sans point initial ; null : hôte de la requête
        self.path = path
        self.expires = expires        # horodatage Unix absolu, ou null (cookie de session)
        self.max_age = max_age        # secondes (relatif à la création)
        self.secure = secure
        self.http_only = http_only
        self.same_site = same_site    # « Strict », « Lax », « None » ou null
        self.host_only = host_only
        self.partitioned = partitioned
        self.creation = _now()
        self.last_access = self.creation

    # Échéance effective (Max-Age l'emporte sur Expires), ou null.
    func expiry():
        if self.max_age != null:
            return self.creation + self.max_age
        return self.expires

    func is_expired(now=null):
        e := self.expiry()
        if e == null:
            return false
        t := now
        if t == null:
            t = _now()
        return e <= t

    func is_session():
        return self.expiry() == null

    # En-tête Set-Cookie (côté serveur).
    func set_cookie_header():
        out := self.name + "=" + self.value
        if self.expires != null:
            out += "; Expires=" + _hh.format_http_date(self.expires)
        if self.max_age != null:
            out += "; Max-Age=" + str(self.max_age)
        if self.domain != null and not self.host_only:
            out += "; Domain=" + self.domain
        if self.path != null:
            out += "; Path=" + self.path
        if self.secure:
            out += "; Secure"
        if self.http_only:
            out += "; HttpOnly"
        if self.same_site != null:
            out += "; SameSite=" + self.same_site
        if self.partitioned:
            out += "; Partitioned"
        return out

    func pair():
        return self.name + "=" + self.value

    func str():
        return self.set_cookie_header()

    func to_dict():
        return {"name": self.name, "value": self.value, "domain": self.domain, "path": self.path, "expires": self.expiry(), "secure": self.secure, "http_only": self.http_only, "same_site": self.same_site, "host_only": self.host_only, "creation": self.creation}

func _valid_name(name):
    if name == "":
        return false
    return _hh.is_valid_name(name)

func _valid_value(v):
    t := v
    if len(t) >= 2 and t[0] == '"' and t[len(t) - 1] == '"':
        t = _s.substring(t, 1, len(t) - 1)
    for c in t:
        o := _s.ord(c)
        if o <= 32 or o == 127 or c == '"' or c == ',' or c == ';' or c == '\\':
            return false
    return true

# Cookie qui supprime `name` chez le client (Max-Age=0, date passée).
func deletion_cookie(name, path="/", domain=null):
    c := Cookie(name, "", domain, path, 0, 0)
    c.host_only = domain == null
    return c

# ---------------------------------------------------------------- analyse

func _cookie_date(text):
    # Les dates des cookies sont tolérantes (§5.1.1) : on accepte les formats HTTP, puis un repli par jetons.
    t := _hh.parse_http_date(text)
    if t != null:
        return t
    day := null
    month := -1
    year := null
    secs := null
    months := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    tokens := []
    cur := ""
    for c in text:
        delim := c == ' ' or c == ',' or c == '-' or c == '/' or c == ';' or c == '\t'
        if delim:
            if cur != "":
                append(tokens, cur)
            cur = ""
        else:
            cur += str(c)
    if cur != "":
        append(tokens, cur)
    for tok in tokens:
        if secs == null and _s.count(tok, ":") == 2:
            p := _s.split(tok, ":")
            ok := true
            for x in p:
                if x == "" or len(x) > 2 or not _digits(x):
                    ok = false
            if ok:
                secs = to_int(p[0]) * 3600 + to_int(p[1]) * 60 + to_int(p[2])
                continue
        if day == null and len(tok) <= 2 and _digits(tok):
            day = to_int(tok)
            continue
        if month < 0 and len(tok) >= 3:
            i := 0
            while i < 12:
                if _s.lower(_s.substring(tok, 0, 3)) == months[i]:
                    month = i + 1
                i += 1
            if month >= 0:
                continue
        if year == null and (len(tok) == 2 or len(tok) == 4) and _digits(tok):
            year = to_int(tok)
            if year >= 70 and year <= 99:
                year += 1900
            elif year < 70:
                year += 2000
    if day == null or month < 0 or year == null or secs == null or year < 1601 or day < 1 or day > 31:
        return null
    return _time.days_from_civil(year, month, day) * 86400 + secs

func _digits(t):
    if t == "":
        return false
    for c in t:
        if c < '0' or c > '9':
            return false
    return true

# Cookie décrit par un en-tête Set-Cookie (null si le couple nom=valeur est inexploitable). Les attributs
# inconnus sont ignorés ; Domain et Path ne sont pas contrôlés ici (voir CookieJar).
func parse_set_cookie(header):
    if header == null:
        return null
    parts := _s.split(str(header), ";")
    nv := parts[0]
    eq := _s.find(nv, "=")
    if eq < 0:
        return null
    name := _s.trim(_s.substring(nv, 0, eq))
    value := _s.trim(_s.substring(nv, eq + 1, len(nv)))
    if name == "" or not _valid_name(name):
        return null
    if not _valid_value(value):
        return null
    c := Cookie(name, value)
    c.path = null
    i := 1
    while i < len(parts):
        a := _s.trim(parts[i])
        i += 1
        if a == "":
            continue
        k := a
        v := ""
        e := _s.find(a, "=")
        if e >= 0:
            k = _s.trim(_s.substring(a, 0, e))
            v = _s.trim(_s.substring(a, e + 1, len(a)))
        lk := _s.lower(k)
        if lk == "expires":
            t := _cookie_date(v)
            if t != null:
                c.expires = t
        elif lk == "max-age":
            neg := _s.starts_with(v, "-")
            digits := v
            if neg:
                digits = _s.substring(v, 1, len(v))
            if _digits(digits):
                n := to_int(digits)
                if neg:
                    n = 0
                c.max_age = n
        elif lk == "domain":
            d := _s.lower(v)
            if _s.starts_with(d, "."):
                d = _s.substring(d, 1, len(d))
            if d != "":
                c.domain = d
                c.host_only = false
        elif lk == "path":
            if _s.starts_with(v, "/"):
                c.path = v
        elif lk == "secure":
            c.secure = true
        elif lk == "httponly":
            c.http_only = true
        elif lk == "samesite":
            sv := _s.lower(v)
            if sv == "strict":
                c.same_site = "Strict"
            elif sv == "lax":
                c.same_site = "Lax"
            elif sv == "none":
                c.same_site = "None"
        elif lk == "partitioned":
            c.partitioned = true
    return c

# En-tête Cookie reçu par un serveur -> dict nom -> valeur (la première occurrence d'un nom l'emporte : la plus
# précise d'après l'ordre d'envoi des navigateurs).
func parse_cookie_header(header):
    out := {}
    if header == null:
        return out
    for part in _s.split(header, ";"):
        p := _s.trim(part)
        e := _s.find(p, "=")
        if e <= 0:
            continue
        name := _s.trim(_s.substring(p, 0, e))
        value := _s.trim(_s.substring(p, e + 1, len(p)))
        if len(value) >= 2 and value[0] == '"' and value[len(value) - 1] == '"':
            value = _s.substring(value, 1, len(value) - 1)
        if not contains_key(out, name):
            out[name] = value
    return out

# « a=1; b=2 » depuis un dict nom -> valeur ou une liste de Cookie.
func format_cookie_header(cookies):
    out := []
    if type(cookies) == "dict":
        for k in keys(cookies):
            append(out, k + "=" + str(cookies[k]))
    else:
        for c in cookies:
            append(out, c.pair())
    return _s.join("; ", out)

# ---------------------------------------------------------------- règles RFC 6265

# Chemin par défaut (§5.1.4) d'une URL de requête.
func default_path(path):
    if path == null or path == "" or not _s.starts_with(path, "/"):
        return "/"
    k := len(path) - 1
    while k > 0 and path[k] != '/':
        k -= 1
    if k == 0:
        return "/"
    return _s.substring(path, 0, k)

# Vrai si l'hôte correspond au domaine (§5.1.3).
func domain_match(host, domain):
    h := _s.lower(host)
    d := _s.lower(domain)
    if h == d:
        return true
    if _ip.is_ip(h):
        return false
    return _s.ends_with(h, "." + d)

# Vrai si le chemin de la requête correspond au chemin du cookie (§5.1.4).
func path_match(request_path, cookie_path):
    rp := request_path
    if rp == "":
        rp = "/"
    if rp == cookie_path:
        return true
    if _s.starts_with(rp, cookie_path):
        if _s.ends_with(cookie_path, "/"):
            return true
        if len(rp) > len(cookie_path) and rp[len(cookie_path)] == '/':
            return true
    return false

# Suffixes publics les plus courants à plusieurs niveaux (en plus de tout domaine d'un seul niveau).
const PUBLIC_SUFFIXES := ["co.uk", "org.uk", "ac.uk", "gov.uk", "com.au", "net.au", "org.au", "co.jp", "ne.jp", "or.jp", "com.br", "com.cn", "com.mx", "co.nz", "co.in", "co.za", "com.tr", "gouv.fr", "asso.fr", "github.io", "herokuapp.com", "blogspot.com", "appspot.com", "cloudfront.net", "azurewebsites.net", "netlify.app", "vercel.app", "pages.dev", "workers.dev"]

func is_public_suffix(domain):
    d := _s.lower(domain)
    if not _s.contains(d, ".") and not _ip.is_ip(d):
        return true
    for s in PUBLIC_SUFFIXES:
        if d == s:
            return true
    return false

class CookieJar:
    # policy_public_suffixes : liste supplémentaire de suffixes refusés comme domaine.
    func init(public_suffixes=null):
        self.cookies = []
        self.extra_suffixes = public_suffixes
        if public_suffixes == null:
            self.extra_suffixes = []
        self.rejected = 0

    func _is_suffix(domain):
        if is_public_suffix(domain):
            return true
        for s in self.extra_suffixes:
            if _s.lower(domain) == _s.lower(s):
                return true
        return false

    # Range un cookie reçu d'une réponse à `url` (texte ou network.url.URL) ; false s'il est refusé.
    func set_cookie(cookie, url):
        u := _url.parse(url)
        host := u.host
        if host == null:
            self.rejected += 1
            return false
        c := cookie
        secure_origin := u.scheme == "https" or u.scheme == "wss" or host == "localhost" or host == "127.0.0.1" or host == "::1"
        if c.domain != null and not c.host_only:
            if self._is_suffix(c.domain) and c.domain != host:
                self.rejected += 1
                return false
            if not domain_match(host, c.domain):
                self.rejected += 1
                return false
        else:
            c.domain = host
            c.host_only = true
        if c.path == null or c.path == "":
            c.path = default_path(u.path)
        if c.secure and not secure_origin:
            self.rejected += 1
            return false
        if _s.starts_with(c.name, "__Secure-") and not (c.secure and secure_origin):
            self.rejected += 1
            return false
        if _s.starts_with(c.name, "__Host-") and not (c.secure and secure_origin and c.host_only and c.path == "/"):
            self.rejected += 1
            return false
        if c.same_site == "None" and not c.secure:
            self.rejected += 1
            return false
        # remplace un cookie de même nom, domaine et chemin (en gardant sa date de création)
        kept := []
        for old in self.cookies:
            if old.name == c.name and old.domain == c.domain and old.path == c.path:
                c.creation = old.creation
            else:
                append(kept, old)
        if not c.is_expired():
            append(kept, c)
        self.cookies = kept
        return true

    # Analyse un en-tête Set-Cookie et le range (false s'il est refusé ou illisible).
    func set_from_header(header, url):
        c := parse_set_cookie(header)
        if c == null:
            self.rejected += 1
            return false
        return self.set_cookie(c, url)

    # Range tous les Set-Cookie d'une réponse (headers : network.http_headers.Headers, network.http.Headers ou
    # dict) ; rend le nombre de cookies acceptés.
    func extract(headers, url):
        values := []
        if type(headers) == "dict":
            for k in keys(headers):
                if _s.lower(k) == "set-cookie":
                    v := headers[k]
                    if type(v) == "list":
                        for x in v:
                            append(values, x)
                    else:
                        append(values, v)
        elif isinstance(headers, _hh.Headers):
            values = headers.get_all("set-cookie")
        else:
            # network.http.Headers : liste brute [nom, valeur]
            for e in headers.list:
                if _s.lower(e[0]) == "set-cookie":
                    append(values, e[1])
        n := 0
        for v in values:
            if self.set_from_header(v, url):
                n += 1
        return n

    # Cookies à envoyer pour une requête vers `url`, dans l'ordre RFC 6265 (chemin le plus long d'abord, puis le
    # plus ancien). same_site_context : "same-site" (défaut) ou "cross-site" (exclut Strict, et Lax hors navigation).
    func cookies_for(url, same_site_context="same-site", top_level_navigation=true):
        u := _url.parse(url)
        now := _now()
        self.remove_expired(now)
        secure_channel := u.scheme == "https" or u.scheme == "wss" or u.host == "localhost" or u.host == "127.0.0.1" or u.host == "::1"
        out := []
        for c in self.cookies:
            if c.host_only:
                if _s.lower(u.host) != c.domain:
                    continue
            elif not domain_match(u.host, c.domain):
                continue
            if not path_match(u.path, c.path):
                continue
            if c.secure and not secure_channel:
                continue
            if same_site_context == "cross-site":
                if c.same_site == "Strict":
                    continue
                if (c.same_site == "Lax" or c.same_site == null) and not top_level_navigation:
                    continue
            append(out, c)
        # tri : chemin le plus long, puis création la plus ancienne
        i := 1
        while i < len(out):
            x := out[i]
            j := i - 1
            while j >= 0 and (len(out[j].path) < len(x.path) or (len(out[j].path) == len(x.path) and out[j].creation > x.creation)):
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = x
            i += 1
        for c in out:
            c.last_access = now
        return out

    # Valeur de l'en-tête Cookie pour `url`, ou null s'il n'y a rien à envoyer.
    func header_for(url, same_site_context="same-site", top_level_navigation=true):
        cs := self.cookies_for(url, same_site_context, top_level_navigation)
        if len(cs) == 0:
            return null
        return format_cookie_header(cs)

    # Valeur du cookie `name` (domaine facultatif), ou default.
    func get(name, domain=null, default=null):
        for c in self.cookies:
            if c.name == name and (domain == null or c.domain == _s.lower(domain)):
                if not c.is_expired():
                    return c.value
        return default

    # Ajoute un cookie directement (domaine obligatoire, sans contrôle d'origine).
    func set(name, value, domain, path="/", secure=false, expires=null):
        c := Cookie(name, value, _s.lower(domain), path, expires, null, secure)
        kept := []
        for old in self.cookies:
            if not (old.name == name and old.domain == c.domain and old.path == path):
                append(kept, old)
        append(kept, c)
        self.cookies = kept

    func remove_expired(now=null):
        kept := []
        for c in self.cookies:
            if not c.is_expired(now):
                append(kept, c)
        self.cookies = kept

    # Supprime les cookies (tous, ceux d'un domaine, ou un nom précis).
    func clear(domain=null, name=null):
        kept := []
        for c in self.cookies:
            match_domain := domain == null or c.domain == _s.lower(domain)
            match_name := name == null or c.name == name
            if not (match_domain and match_name):
                append(kept, c)
        self.cookies = kept

    # Supprime les cookies de session (fin de session du navigateur).
    func clear_session():
        kept := []
        for c in self.cookies:
            if not c.is_session():
                append(kept, c)
        self.cookies = kept

    func __len__():
        return len(self.cookies)

    func to_list():
        out := []
        for c in self.cookies:
            append(out, c.to_dict())
        return out

    # Enregistre les cookies persistants (session_too : aussi les cookies de session) en JSON.
    func save(path, session_too=false):
        out := []
        for c in self.cookies:
            if session_too or not c.is_session():
                append(out, c.to_dict())
        _io.write_file(path, _json.pretty(out))

    func load(path):
        for d in _json.parse(_io.read_file(path)):
            c := Cookie(d["name"], d["value"], d["domain"], d["path"], d["expires"], null, d["secure"], d["http_only"], d["same_site"], d["host_only"])
            c.creation = d["creation"]
            if not c.is_expired():
                append(self.cookies, c)
        return self

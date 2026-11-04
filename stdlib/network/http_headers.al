# ALEX STANDARD LIBRARY — network.http_headers
#
# En-têtes HTTP (RFC 9110) : collection ordonnée insensible à la casse et à valeurs multiples, validation contre
# l'injection (CR/LF), analyse des valeurs structurées les plus courantes.
#
#   Headers                 add, set, get, get_all, remove, has, items, names, to_text ; parse(texte brut)
#   parse_value / format_value       « text/html; charset=utf-8 » <-> ("text/html", {"charset": "utf-8"})
#   parse_list              liste séparée par des virgules (guillemets respectés)
#   parse_accept, negotiate          Accept / Accept-Language / Accept-Encoding pondérés (q=)
#   parse_cache_control, format_cache_control
#   format_http_date, parse_http_date        dates IMF-fixdate (et RFC 850, asctime en lecture)
#   parse_content_disposition, content_disposition   noms de fichier, y compris filename* (RFC 6266 / 8187)
#   parse_range, content_range       plages d'octets (RFC 9110 §14)
#   parse_etags, etag_matches        If-Match / If-None-Match
#   parse_link                       Link (RFC 8288)
#   parse_challenges, parse_authorization, basic_auth, bearer_auth, parse_basic   authentification
#   canonical_name                   « content-type » -> « Content-Type »
#
# Erreurs : HttpError (en-tête invalide), TypeError.
#
# Exemple
#   use network.http_headers as hh
#   h := hh.Headers()
#   h.add("Set-Cookie", "a=1")
#   h.add("set-cookie", "b=2")
#   print(h.get_all("SET-COOKIE"))                       # [a=1, b=2]
#   print(hh.parse_value("text/html; charset=\"utf-8\""))   # (text/html, {charset: utf-8})
#   print(hh.negotiate("text/*;q=0.5, application/json", ["text/html", "application/json"]))   # application/json

from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use time as _time
use network.encoding as _enc

func _fail(message):
    raise("HttpError", "http_headers : " + message)

# ---------------------------------------------------------------- validation

const _TCHARS := "!#$%&'*+-.^_`|~"

func _is_tchar(c):
    if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9'):
        return true
    for x in _TCHARS:
        if x == c:
            return true
    return false

# Vrai si name est un nom d'en-tête valide (« token »).
func is_valid_name(name):
    if type(name) != "str" or name == "":
        return false
    for c in name:
        if not _is_tchar(c):
            return false
    return true

# Vrai si value ne contient ni CR, ni LF, ni NUL.
func is_valid_value(value):
    if type(value) != "str":
        return false
    for c in value:
        if c == '\r' or c == '\n' or c == '\x00':
            return false
    return true

func check_name(name):
    if not is_valid_name(name):
        _fail("nom d'en-tête invalide « " + str(name) + " »")
    return name

func check_value(name, value):
    v := value
    if type(v) != "str":
        v = str(v)
    if not is_valid_value(v):
        _fail("valeur de « " + str(name) + " » invalide (retour à la ligne interdit : injection d'en-tête)")
    return v

# « content-type » -> « Content-Type » (forme d'affichage habituelle ; les noms restent insensibles à la casse).
func canonical_name(name):
    parts := []
    for p in _s.split(_s.lower(name), "-"):
        if p == "":
            append(parts, p)
        else:
            append(parts, _s.upper(str(p[0])) + _s.substring(p, 1, len(p)))
    out := _s.join("-", parts)
    if _s.lower(out) == "www-authenticate":
        return "WWW-Authenticate"
    if _s.lower(out) == "etag":
        return "ETag"
    if _s.lower(out) == "te":
        return "TE"
    return out

# ---------------------------------------------------------------- collection

class Headers:
    # initial : dict nom -> valeur (str ou list), liste de paires, ou autre Headers.
    func init(initial=null):
        self.entries = []      # [nom tel que donné, valeur]
        if initial != null:
            self.update(initial)

    func add(name, value):
        check_name(name)
        if type(value) == "list":
            for v in value:
                append(self.entries, [name, check_value(name, v)])
            return self
        append(self.entries, [name, check_value(name, value)])
        return self

    # Remplace toutes les valeurs de name.
    func set(name, value):
        self.remove(name)
        return self.add(name, value)

    # Ajoute seulement si l'en-tête est absent.
    func set_default(name, value):
        if not self.has(name):
            self.add(name, value)
        return self

    # Valeur de name (plusieurs valeurs jointes par « , », sauf Set-Cookie : la première), ou default.
    func get(name, default=null):
        vals := self.get_all(name)
        if len(vals) == 0:
            return default
        if _s.lower(name) == "set-cookie":
            return vals[0]
        if len(vals) == 1:
            return vals[0]
        return _s.join(", ", vals)

    func get_all(name):
        k := _s.lower(name)
        out := []
        for e in self.entries:
            if _s.lower(e[0]) == k:
                append(out, e[1])
        return out

    # Valeur entière (Content-Length...), ou default si absente ou non numérique.
    func get_int(name, default=null):
        v := self.get(name)
        if v == null:
            return default
        t := _s.trim(v)
        if t == "":
            return default
        for c in t:
            if c < '0' or c > '9':
                return default
        return to_int(t)

    func has(name):
        k := _s.lower(name)
        for e in self.entries:
            if _s.lower(e[0]) == k:
                return true
        return false

    func __contains__(name):
        return self.has(name)

    func __getitem__(name):
        v := self.get(name)
        if v == null:
            raise("KeyError", "en-tête absent : " + str(name))
        return v

    func __setitem__(name, value):
        self.set(name, value)

    func __len__():
        return len(self.entries)

    func remove(name):
        k := _s.lower(name)
        kept := []
        for e in self.entries:
            if _s.lower(e[0]) != k:
                append(kept, e)
        self.entries = kept
        return self

    # Paires [nom, valeur] dans l'ordre d'ajout.
    func items():
        out := []
        for e in self.entries:
            append(out, [e[0], e[1]])
        return out

    # Noms distincts (forme de la première occurrence).
    func names():
        out := []
        seen := {}
        for e in self.entries:
            k := _s.lower(e[0])
            if not contains_key(seen, k):
                seen[k] = true
                append(out, e[0])
        return out

    func update(other):
        if isinstance(other, Headers):
            for e in other.entries:
                self.add(e[0], e[1])
        elif type(other) == "dict":
            for k in keys(other):
                self.set(k, other[k])
        elif type(other) == "list":
            for p in other:
                self.add(p[0], p[1])
        else:
            raise("TypeError", "http_headers.Headers.update : dict, liste de paires ou Headers attendu")
        return self

    func copy():
        h := Headers()
        for e in self.entries:
            append(h.entries, [e[0], e[1]])
        return h

    # dict nom en minuscules -> valeur jointe.
    func to_dict():
        d := {}
        for n in self.names():
            d[_s.lower(n)] = self.get(n)
        return d

    # Bloc « Nom: valeur\r\n » (sans la ligne vide finale).
    func to_text():
        out := []
        for e in self.entries:
            append(out, e[0] + ": " + e[1] + "\r\n")
        return _s.join("", out)

    func str():
        return self.to_text()

    # Type de contenu sans paramètres, en minuscules (« application/json »), ou null.
    func content_type():
        v := self.get("content-type")
        if v == null:
            return null
        return parse_value(v)[0]

    # Paramètre charset du Content-Type, ou default.
    func charset(default=null):
        v := self.get("content-type")
        if v == null:
            return default
        p := parse_value(v)[1]
        if contains_key(p, "charset"):
            return p["charset"]
        return default

    func content_length():
        return self.get_int("content-length")

# Analyse un bloc d'en-têtes brut (lignes « Nom: valeur », lignes de continuation repliées acceptées).
func parse(text, strict=false):
    h := Headers()
    last := null
    for line in _s.split(text, "\n"):
        l := line
        if _s.ends_with(l, "\r"):
            l = _s.substring(l, 0, len(l) - 1)
        if l == "":
            continue
        if l[0] == ' ' or l[0] == '\t':
            if last == null or strict:
                _fail("ligne de continuation inattendue « " + l + " »")
            last[1] = last[1] + " " + _s.trim(l)
            continue
        c := _s.find(l, ":")
        if c <= 0:
            _fail("en-tête mal formé « " + l + " »")
        name := _s.substring(l, 0, c)
        if not is_valid_name(name):
            _fail("nom d'en-tête invalide « " + name + " »")
        value := _s.trim(_s.substring(l, c + 1, len(l)))
        append(h.entries, [name, value])
        last = h.entries[len(h.entries) - 1]
    return h

# ---------------------------------------------------------------- valeurs structurées

# Découpe s sur sep hors des chaînes entre guillemets.
func _split_quoted(s, sep):
    out := []
    cur := []
    inq := false
    esc := false
    for c in s:
        if esc:
            append(cur, str(c))
            esc = false
            continue
        if c == '\\' and inq:
            append(cur, str(c))
            esc = true
            continue
        if c == '"':
            inq = not inq
            append(cur, str(c))
            continue
        if c == sep and not inq:
            append(out, _s.join("", cur))
            cur = []
            continue
        append(cur, str(c))
    append(out, _s.join("", cur))
    return out

# Retire les guillemets et les échappements d'une chaîne « quoted-string ».
func unquote(s):
    t := _s.trim(s)
    if len(t) >= 2 and t[0] == '"' and t[len(t) - 1] == '"':
        inner := _s.substring(t, 1, len(t) - 1)
        out := []
        esc := false
        for c in inner:
            if esc:
                append(out, str(c))
                esc = false
            elif c == '\\':
                esc = true
            else:
                append(out, str(c))
        return _s.join("", out)
    return t

# Met une valeur entre guillemets si elle n'est pas un « token ».
func quote(s):
    v := str(s)
    plain := v != ""
    for c in v:
        if not _is_tchar(c):
            plain = false
    if plain:
        return v
    return "\"" + _s.replace(_s.replace(v, "\\", "\\\\"), "\"", "\\\"") + "\""

# « valeur; a=1; b="x y" » -> (valeur en minuscules si lower, {a: "1", b: "x y"}) ; noms de paramètres en minuscules.
# Un paramètre étendu « nom*=UTF-8''%C3%A9 » (RFC 8187) est décodé sous « nom ».
func parse_value(value, lower=true):
    parts := _split_quoted(str(value), ';')
    main := _s.trim(parts[0])
    if lower:
        main = _s.lower(main)
    params := {}
    extended := {}
    i := 1
    while i < len(parts):
        p := _s.trim(parts[i])
        i += 1
        if p == "":
            continue
        eq := _s.find(p, "=")
        if eq < 0:
            params[_s.lower(p)] = ""
            continue
        name := _s.lower(_s.trim(_s.substring(p, 0, eq)))
        v := _s.trim(_s.substring(p, eq + 1, len(p)))
        if _s.ends_with(name, "*"):
            extended[_s.substring(name, 0, len(name) - 1)] = decode_ext_value(v)
        else:
            params[name] = unquote(v)
    for k in keys(extended):      # la forme étendue (Unicode) l'emporte
        params[k] = extended[k]
    return (main, params)

# Valeur étendue RFC 8187 : « UTF-8'fr'%C3%A9t%C3%A9 » -> « été ».
func decode_ext_value(v):
    t := unquote(v)
    a := _s.find(t, "'")
    if a < 0:
        return _enc.percent_decode(t)
    rest := _s.substring(t, a + 1, len(t))
    b := _s.find(rest, "'")
    if b < 0:
        return _enc.percent_decode(t)
    charset := _s.substring(t, 0, a)
    raw := _enc.percent_decode(_s.substring(rest, b + 1, len(rest)))
    if charset == "" or _s.lower(charset) == "utf-8":
        return _enc.to_text(raw)
    return _enc.decode_charset(raw, charset, "replace")

# Valeur étendue RFC 8187 d'un texte UTF-8.
func encode_ext_value(text):
    return "UTF-8''" + _enc.percent_encode(text, "!#$&+^`|")

# (valeur, {paramètres}) -> « valeur; a=1; b="x y" ».
func format_value(value, params=null):
    out := str(value)
    if params != null:
        for k in keys(params):
            out += "; " + k + "=" + quote(params[k])
    return out

# Éléments d'une liste « a, b, "c, d" » (vides ignorés).
func parse_list(value):
    out := []
    if value == null:
        return out
    for p in _split_quoted(str(value), ','):
        t := _s.trim(p)
        if t != "":
            append(out, t)
    return out

# ---------------------------------------------------------------- négociation de contenu

class AcceptItem:
    func init(value, q, params):
        self.value = value      # « text/html », « fr-ch », « gzip »...
        self.q = q              # 0.0 .. 1.0
        self.params = params    # autres paramètres

    func str():
        return self.value + ";q=" + str(self.q)

func _specificity(v):
    if v == "*" or v == "*/*":
        return 0
    if _s.ends_with(v, "/*"):
        return 1
    return 2

# Éléments d'un en-tête Accept* triés par préférence (q décroissant, puis du plus précis au moins précis).
func parse_accept(value):
    items := []
    for part in parse_list(value):
        pv := parse_value(part)
        q := 1.0
        params := pv[1]
        if contains_key(params, "q"):
            try:
                q = to_float(params["q"])
            catch e:
                q = 0.0
            if q < 0:
                q = 0.0
            if q > 1:
                q = 1.0
        rest := {}
        for k in keys(params):
            if k != "q":
                rest[k] = params[k]
        append(items, AcceptItem(pv[0], q, rest))
    # tri stable par insertion
    i := 1
    while i < len(items):
        x := items[i]
        j := i - 1
        while j >= 0 and (items[j].q < x.q or (items[j].q == x.q and _specificity(items[j].value) < _specificity(x.value))):
            items[j + 1] = items[j]
            j -= 1
        items[j + 1] = x
        i += 1
    return items

func _media_match(pattern, offer):
    if pattern == "*/*" or pattern == "*":
        return true
    if pattern == offer:
        return true
    if _s.ends_with(pattern, "/*"):
        return _s.starts_with(offer, _s.substring(pattern, 0, len(pattern) - 1))
    # langues : « fr » accepte « fr-ch »
    if _s.starts_with(offer, pattern + "-"):
        return true
    return false

# Qualité accordée par l'en-tête à une offre (la règle la plus précise qui correspond l'emporte).
func quality(accept, offer):
    o := _s.lower(offer)
    best := -1.0
    best_spec := -1
    for it in parse_accept(accept):
        if _media_match(it.value, o):
            sp := _specificity(it.value)
            if it.value == o:
                sp = 3
            if sp > best_spec:
                best_spec = sp
                best = it.q
    if best < 0:
        return 0.0
    return best

# Meilleure offre (parmi `available`, dans l'ordre de préférence du serveur à qualité égale) pour l'en-tête
# Accept* ; null si aucune n'est acceptable. Un en-tête absent ou vide accepte tout (première offre).
func negotiate(accept, available):
    if len(available) == 0:
        return null
    if accept == null or _s.trim(accept) == "":
        return available[0]
    best := null
    bq := 0.0
    for offer in available:
        q := quality(accept, offer)
        if q > bq:
            bq = q
            best = offer
    return best

# ---------------------------------------------------------------- Cache-Control

# dict directive (minuscules) -> valeur (str) ou true (« no-cache », « public »...). Les nombres restent des str.
func parse_cache_control(value):
    out := {}
    for part in parse_list(value):
        eq := _s.find(part, "=")
        if eq < 0:
            out[_s.lower(_s.trim(part))] = true
        else:
            out[_s.lower(_s.trim(_s.substring(part, 0, eq)))] = unquote(_s.substring(part, eq + 1, len(part)))
    return out

func format_cache_control(directives):
    out := []
    for k in keys(directives):
        v := directives[k]
        if v == true:
            append(out, k)
        elif v == false or v == null:
            continue
        else:
            append(out, k + "=" + quote(v))
    return _s.join(", ", out)

# Durée de fraîcheur (secondes) d'une réponse : s-maxage / max-age, ou null ; 0 si no-store / no-cache.
func max_age(cache_control):
    cc := parse_cache_control(cache_control)
    if contains_key(cc, "no-store") or contains_key(cc, "no-cache"):
        return 0
    for k in ["s-maxage", "max-age"]:
        if contains_key(cc, k):
            v := cc[k]
            ok := v != true and v != ""
            if ok:
                for c in v:
                    if c < '0' or c > '9':
                        ok = false
            if ok:
                return to_int(v)
    return null

# ---------------------------------------------------------------- dates HTTP

const _DAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func _two(n):
    if n < 10:
        return "0" + str(n)
    return str(n)

# Date IMF-fixdate (« Sun, 06 Nov 1994 08:49:37 GMT ») d'un horodatage Unix (défaut : maintenant).
func format_http_date(ts=null):
    t := ts
    if t == null:
        t = _time.time()
    secs := to_int(t)
    if secs > t:
        secs -= 1
    days := secs // 86400
    rem := secs - days * 86400
    ymd := _time.civil_from_days(days)
    wd := _time.weekday_of_days(days)
    return _DAYS[wd] + ", " + _two(ymd[2]) + " " + _MONTHS[ymd[1] - 1] + " " + str(ymd[0]) + " " + _two(rem // 3600) + ":" + _two((rem % 3600) // 60) + ":" + _two(rem % 60) + " GMT"

func _month_index(m):
    i := 0
    while i < 12:
        if _s.lower(_MONTHS[i]) == _s.lower(m):
            return i + 1
        i += 1
    return -1

func _hms(text):
    p := _s.split(text, ":")
    if len(p) != 3:
        return null
    for x in p:
        if x == "" or len(x) > 2:
            return null
        for c in x:
            if c < '0' or c > '9':
                return null
    return to_int(p[0]) * 3600 + to_int(p[1]) * 60 + to_int(p[2])

func _num(t):
    if t == "":
        return null
    for c in t:
        if c < '0' or c > '9':
            return null
    return to_int(t)

# Horodatage Unix d'une date HTTP (IMF-fixdate, RFC 850 ou asctime), ou null si elle est illisible.
func parse_http_date(text):
    if text == null:
        return null
    t := _s.trim(str(text))
    parts := []
    for p in _s.split(t, " "):
        if p != "":
            append(parts, p)
    day := null
    month := -1
    year := null
    secs := null
    if len(parts) == 6 and _s.ends_with(parts[0], ","):          # Sun, 06 Nov 1994 08:49:37 GMT
        day = _num(parts[1])
        month = _month_index(parts[2])
        year = _num(parts[3])
        secs = _hms(parts[4])
    elif len(parts) == 4 and _s.ends_with(parts[0], ","):        # Sunday, 06-Nov-94 08:49:37 GMT
        d := _s.split(parts[1], "-")
        if len(d) == 3:
            day = _num(d[0])
            month = _month_index(d[1])
            year = _num(d[2])
            if year != null and year < 100:
                if year < 70:
                    year += 2000
                else:
                    year += 1900
        secs = _hms(parts[2])
    elif len(parts) == 5:                                         # Sun Nov  6 08:49:37 1994
        month = _month_index(parts[1])
        day = _num(parts[2])
        secs = _hms(parts[3])
        year = _num(parts[4])
    if day == null or month < 0 or year == null or secs == null:
        return null
    if day < 1 or day > 31:
        return null
    return _time.days_from_civil(year, month, day) * 86400 + secs

# ---------------------------------------------------------------- Content-Disposition

# (type, nom de fichier ou null, paramètres) — filename* (UTF-8) l'emporte sur filename.
func parse_content_disposition(value):
    pv := parse_value(value)
    params := pv[1]
    fname := null
    if contains_key(params, "filename"):
        fname = params["filename"]
    return (pv[0], fname, params)

# Valeur Content-Disposition (« attachment; filename="a.txt"; filename*=UTF-8''%C3%A9.txt »).
func content_disposition(disposition="attachment", filename=null, name=null):
    out := disposition
    if name != null:
        out += "; name=" + quote(name)
    if filename != null:
        ascii := true
        for c in filename:
            if _s.ord(c) >= 128 or c == '"' or c == '\\':
                ascii = false
        if ascii:
            out += "; filename=" + quote(filename)
        else:
            fallback := []
            for c in filename:
                if _s.ord(c) < 128 and c != '"' and c != '\\':
                    append(fallback, str(c))
                else:
                    append(fallback, "_")
            out += "; filename=" + quote(_s.join("", fallback)) + "; filename*=" + encode_ext_value(filename)
    return out

# ---------------------------------------------------------------- plages (Range)

# Plages demandées par « bytes=0-99,200-,-50 » pour une ressource de `size` octets : liste de [début, fin]
# inclusives, ou null si l'en-tête est invalide ou aucune plage n'est satisfaisable (réponse 416).
func parse_range(value, size):
    if value == null:
        return null
    v := _s.trim(value)
    if not _s.starts_with(_s.lower(v), "bytes="):
        return null
    out := []
    for part in _s.split(_s.substring(v, 6, len(v)), ","):
        p := _s.trim(part)
        if p == "":
            continue
        dash := _s.find(p, "-")
        if dash < 0:
            return null
        a := _s.trim(_s.substring(p, 0, dash))
        b := _s.trim(_s.substring(p, dash + 1, len(p)))
        if a == "":
            n := _num(b)
            if n == null:
                return null
            if n == 0:
                continue
            if n > size:
                n = size
            if size > 0:
                append(out, [size - n, size - 1])
        else:
            start := _num(a)
            if start == null:
                return null
            end := size - 1
            if b != "":
                end = _num(b)
                if end == null or end < start:
                    return null
                if end > size - 1:
                    end = size - 1
            if start < size:
                append(out, [start, end])
    if len(out) == 0:
        return null
    return out

# Valeur Content-Range (« bytes 0-99/1234 ») ; start=null : « bytes */1234 » (réponse 416).
func content_range(start, end, size):
    if start == null:
        return "bytes */" + str(size)
    return "bytes " + str(start) + "-" + str(end) + "/" + str(size)

# ---------------------------------------------------------------- ETag

# Liste des étiquettes d'If-Match / If-None-Match (« * » rend ["*"]).
func parse_etags(value):
    out := []
    if value == null:
        return out
    for p in parse_list(value):
        append(out, p)
    return out

func _opaque(tag):
    t := _s.trim(tag)
    if _s.starts_with(t, "W/"):
        t = _s.substring(t, 2, len(t))
    return t

# Vrai si l'étiquette `etag` figure dans header (weak=true : comparaison faible, pour If-None-Match).
func etag_matches(header, etag, weak=true):
    if header == null or etag == null:
        return false
    for t in parse_etags(header):
        if t == "*":
            return true
        if weak:
            if _opaque(t) == _opaque(etag):
                return true
        elif t == etag and not _s.starts_with(t, "W/"):
            return true
    return false

# Étiquette forte depuis un contenu (empreinte hexadécimale fournie) : « "abc123" ».
func make_etag(fingerprint, weak=false):
    t := "\"" + str(fingerprint) + "\""
    if weak:
        return "W/" + t
    return t

# ---------------------------------------------------------------- Link (RFC 8288)

class Link:
    func init(url, params):
        self.url = url
        self.params = params

    func rel():
        if contains_key(self.params, "rel"):
            return self.params["rel"]
        return null

    func str():
        return format_value("<" + self.url + ">", self.params)

# Liens d'un en-tête Link : liste de Link (url, params dont rel).
func parse_link(value):
    out := []
    if value == null:
        return out
    for part in _split_quoted(value, ','):
        p := _s.trim(part)
        if not _s.starts_with(p, "<"):
            continue
        e := _s.find(p, ">")
        if e < 0:
            continue
        u := _s.substring(p, 1, e)
        params := parse_value("x" + _s.substring(p, e + 1, len(p)), true)[1]
        append(out, Link(u, params))
    return out

# URL du lien de relation rel (« next »...), ou null.
func find_link(value, rel):
    for l in parse_link(value):
        r := l.rel()
        if r != null:
            for x in _s.split(_s.lower(r), " "):
                if x == _s.lower(rel):
                    return l.url
    return null

# ---------------------------------------------------------------- authentification

class Challenge:
    func init(scheme, params, token=null):
        self.scheme = scheme      # minuscules : « basic », « bearer », « digest »...
        self.params = params      # dict (realm, charset, error...)
        self.token = token        # token68 éventuel

    func realm():
        if contains_key(self.params, "realm"):
            return self.params["realm"]
        return null

# Défis d'un en-tête WWW-Authenticate / Proxy-Authenticate (plusieurs schémas possibles).
func parse_challenges(value):
    out := []
    if value == null:
        return out
    cur := null
    for item in _split_quoted(value, ','):
        t := _s.trim(item)
        if t == "":
            continue
        sp := _s.find(t, " ")
        eq := _s.find(t, "=")
        if eq < 0 or (sp > 0 and sp < eq):
            # nouveau défi : « Basic realm="x" », « Negotiate jeton== » ou « Negotiate »
            scheme := t
            rest := ""
            if sp > 0:
                scheme = _s.substring(t, 0, sp)
                rest = _s.trim(_s.substring(t, sp + 1, len(t)))
            cur = Challenge(_s.lower(scheme), {}, null)
            append(out, cur)
            if rest != "":
                e2 := _s.find(rest, "=")
                if e2 > 0 and not _only_equals(_s.substring(rest, e2, len(rest))):
                    cur.params[_s.lower(_s.trim(_s.substring(rest, 0, e2)))] = unquote(_s.substring(rest, e2 + 1, len(rest)))
                else:
                    cur.token = rest
        elif cur != null:
            cur.params[_s.lower(_s.trim(_s.substring(t, 0, eq)))] = unquote(_s.substring(t, eq + 1, len(t)))
    return out

func _only_equals(s):
    for c in s:
        if c != '=':
            return false
    return true

# (schéma en minuscules, crédit brut) d'un en-tête Authorization, ou null.
func parse_authorization(value):
    if value == null:
        return null
    t := _s.trim(value)
    sp := _s.find(t, " ")
    if sp <= 0:
        return (_s.lower(t), "")
    return (_s.lower(_s.substring(t, 0, sp)), _s.trim(_s.substring(t, sp + 1, len(t))))

# Valeur Authorization « Basic » (identifiant et mot de passe en UTF-8).
func basic_auth(user, password):
    if type(user) != "str" or type(password) != "str":
        raise("TypeError", "http_headers.basic_auth : user et password doivent être des str")
    if _s.contains(user, ":"):
        raise("ArgumentError", "http_headers.basic_auth : l'identifiant ne peut pas contenir « : »")
    return "Basic " + _enc.base64_encode(user + ":" + password)

func bearer_auth(token):
    if type(token) != "str" or token == "" or not is_valid_value(token):
        raise("TypeError", "http_headers.bearer_auth : jeton str non vide sur une ligne attendu")
    return "Bearer " + token

# (identifiant, mot de passe) d'un en-tête « Basic ... », ou null s'il n'est pas de ce schéma ou est mal formé.
func parse_basic(value):
    a := parse_authorization(value)
    if a == null or a[0] != "basic":
        return null
    try:
        raw := _enc.base64_decode(a[1])
        c := _n.bfind(raw, ":", 0)
        if c < 0:
            return null
        return (_enc.to_text(_n.bslice(raw, 0, c)), _enc.to_text(_n.bslice(raw, c + 1, _n.blen(raw))))
    catch e:
        return null

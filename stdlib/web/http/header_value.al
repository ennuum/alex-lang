# ALEX STANDARD LIBRARY — web.http.header_value
#
# Valeurs d'en-têtes HTTP (RFC 9110 §5.5, §5.6) : validation (aucun CR, LF ni NUL : c'est ce qui empêche
# l'injection d'en-têtes), suppression des espaces optionnels, et analyse des structures courantes :
#
#   listes          « gzip, br »                                   split_list
#   paramètres      « text/html; charset=utf-8 »                   parse_parameters / format_parameters
#   qualités        « fr-FR, fr;q=0.9, en;q=0.5 »                  parse_quality_list / best_match
#   directives      « max-age=3600, no-cache, private="Set-Cookie" »  parse_directives / format_directives
#   chaînes         « "a \"b\"" »                                   quote / unquote
#   RFC 8187        « UTF-8''caf%C3%A9.pdf » (filename*=)           decode_ext_value / encode_ext_value
#
#   use web.http.header_value as hv
#   hv.parse_parameters("text/html; charset=\"utf-8\"")      # ("text/html", {"charset": "utf-8"})
#   hv.split_list("a, \"b, c\", d")                          # ["a", "\"b, c\"", "d"]
#   hv.parse_quality_list("br;q=0.5, gzip, *;q=0")           # [("gzip", 1.0), ("br", 0.5), ("*", 0.0)]
#   hv.best_match("fr-CA, fr;q=0.9, en;q=0.5", ["en", "fr"]) # fr
#   hv.parse_directives("max-age=60, no-store")              # {"max-age": "60", "no-store": null}
#
# Erreurs : HttpHeaderError (check), TypeError.

from core use len, type, to_float
from collections use append, keys
use string as _s
use web.http.http_errors as _err
use web.http.method as _method
use web.url.percent_encoding as _pe

# Valeurs déjà reconnues valides (les mêmes reviennent à chaque requête : Content-Type, en-têtes de sécurité...).
_valid := [{}, 0]
const _CACHE_MAX := 4096
const _CACHE_LEN := 256

# Vrai si la valeur ne contient aucun caractère interdit (CR, LF, NUL, autres contrôles sauf HTAB).
func is_valid(value):
    if type(value) != "str":
        return false
    seen := _valid[0]
    if value in seen:
        return true
    for c in value:
        if (c < ' ' and c != '\t') or c == '\x7f':
            return false
    if len(value) <= _CACHE_LEN:
        if _valid[1] >= _CACHE_MAX:
            _valid[0] = {}
            _valid[1] = 0
        _valid[0][value] = true
        _valid[1] = _valid[1] + 1
    return true

func check(value, name="valeur"):
    if type(value) != "str":
        raise("TypeError", "header_value.check : str attendue pour " + name + " (obtenu " + type(value) + ")")
    if not is_valid(value):
        _err.header_error("header_value.check", "caractère de contrôle interdit (CR, LF, NUL...) dans l'en-tête " + name)
    return value

# Texte d'une valeur (int, float, bool acceptés) validé.
func to_text(value, name="valeur"):
    t := type(value)
    if t == "int" or t == "float":
        return str(value)
    if value == true:
        return "true"
    if value == false:
        return "false"
    return check(value, name)

# Retire les contrôles interdits (remplacés par une espace) : pour journaliser une valeur reçue.
func sanitize(value):
    out := []
    for c in str(value):
        o := _s.ord(c)
        if (o < 32 and o != 9) or o == 127:
            append(out, " ")
        else:
            append(out, str(c))
    return _s.join("", out)

func _is_ows(c):
    return c == ' ' or c == '\t'

# Supprime les espaces optionnels (SP, HTAB) aux extrémités.
func trim(value):
    start := 0
    n := len(value)
    while start < n and _is_ows(value[start]):
        start += 1
    end := n
    while end > start and _is_ows(value[end - 1]):
        end -= 1
    return value[start:end]

# ---------------------------------------------------------------- chaînes entre guillemets

# Vrai si value peut s'écrire sans guillemets (c'est un token).
func is_token(value):
    return _method.is_token(value)

# Chaîne entre guillemets (« " » et « \ » échappés).
func quote(value):
    return "\"" + _s.replace(_s.replace(value, "\\", "\\\\"), "\"", "\\\"") + "\""

# Token tel quel, sinon chaîne entre guillemets.
func quote_if_needed(value):
    if is_token(value):
        return value
    return quote(value)

# Retire les guillemets et les échappements d'une chaîne « "…" » ; rend value telle quelle sinon.
func unquote(value):
    v := trim(value)
    if len(v) < 2 or v[0] != '"' or v[len(v) - 1] != '"':
        return v
    out := []
    i := 1
    n := len(v) - 1
    while i < n:
        c := v[i]
        if c == '\\' and i + 1 < n:
            append(out, str(v[i + 1]))
            i += 2
        else:
            append(out, str(c))
            i += 1
    return _s.join("", out)

# ---------------------------------------------------------------- listes

# Découpe sur sep en dehors des chaînes entre guillemets ; éléments vides ignorés, espaces retirés.
func split_quoted(value, sep):
    out := []
    cur := []
    quoted := false
    escaped := false
    for c in value:
        if escaped:
            append(cur, str(c))
            escaped = false
        elif quoted and c == '\\':
            append(cur, str(c))
            escaped = true
        elif c == '"':
            append(cur, str(c))
            quoted = not quoted
        elif c == sep and not quoted:
            item := trim(_s.join("", cur))
            if item != "":
                append(out, item)
            cur = []
        else:
            append(cur, str(c))
    item := trim(_s.join("", cur))
    if item != "":
        append(out, item)
    return out

# Liste « a, b, c » (RFC 9110 §5.6.1).
func split_list(value):
    if value == null:
        return []
    return split_quoted(value, ',')

func join_list(items):
    out := []
    for x in items:
        append(out, str(x))
    return _s.join(", ", out)

# Vrai si la liste contient token (insensible à la casse) : « Connection: keep-alive, Upgrade ».
func list_contains(value, token):
    t := _s.lower(token)
    for item in split_list(value):
        if _s.lower(item) == t:
            return true
    return false

# ---------------------------------------------------------------- paramètres

# « valeur; a=1; b="x y" » -> (valeur, {"a": "1", "b": "x y"}) ; noms de paramètres en minuscules ;
# « nom*=UTF-8''… » (RFC 8187) décodé et rangé sous « nom ».
func parse_parameters(value):
    if value == null:
        return ("", {})
    parts := split_quoted(value, ';')
    if len(parts) == 0:
        return ("", {})
    main := parts[0]
    params := {}
    extended := {}
    i := 1
    while i < len(parts):
        p := parts[i]
        eq := _s.find(p, "=")
        if eq < 0:
            params[_s.lower(trim(p))] = ""
        else:
            k := _s.lower(trim(p[0:eq]))
            v := trim(p[eq + 1:len(p)])
            if _s.ends_with(k, "*"):
                dv := decode_ext_value(v)
                if dv != null:
                    extended[k[0:len(k) - 1]] = dv
            else:
                params[k] = unquote(v)
        i += 1
    for k in keys(extended):
        params[k] = extended[k]
    return (main, params)

# Inverse de parse_parameters (valeurs non token entre guillemets ; non ASCII en « nom*=UTF-8''… »).
func format_parameters(main, params):
    out := main
    if params == null:
        return out
    for k in keys(params):
        v := params[k]
        if v == null:
            out = out + "; " + k
        else:
            sv := str(v)
            if _is_ascii(sv):
                out = out + "; " + k + "=" + quote_if_needed(sv)
            else:
                out = out + "; " + k + "*=" + encode_ext_value(sv)
    return out

func _is_ascii(text):
    for c in text:
        if _s.ord(c) >= 128:
            return false
    return true

# RFC 8187 : « UTF-8'langue'valeur%XX » -> valeur ; null si la forme est invalide.
func decode_ext_value(value):
    v := unquote(value)
    a := _s.find(v, "'")
    if a < 0:
        return null
    rest := v[a + 1:len(v)]
    b := _s.find(rest, "'")
    if b < 0:
        return null
    charset := _s.lower(v[0:a])
    data := rest[b + 1:len(rest)]
    if charset != "utf-8" and charset != "iso-8859-1" and charset != "us-ascii":
        return null
    try:
        if charset == "iso-8859-1":
            return _latin1_decode(data)
        return _pe.decode(data, false, true)
    catch e:
        return null

func _latin1_decode(data):
    bytes := _s.byte_unpack(_pe_decode_raw(data))
    out := []
    for b in bytes:
        append(out, str(_s.chr(b)))
    return _s.join("", out)

func _pe_decode_raw(data):
    out := []
    bytes := _s.byte_unpack(data)
    i := 0
    while i < len(bytes):
        b := bytes[i]
        if b == 37 and i + 2 < len(bytes) and _pe.is_hex_byte(bytes[i + 1]) and _pe.is_hex_byte(bytes[i + 2]):
            append(out, _pe.hex_value(bytes[i + 1]) * 16 + _pe.hex_value(bytes[i + 2]))
            i += 3
        else:
            append(out, b)
            i += 1
    return _s.byte_pack(out)

# Valeur RFC 8187 : « UTF-8''caf%C3%A9 ».
func encode_ext_value(value, language=""):
    return "UTF-8'" + language + "'" + _pe.encode(value, "!#$&+.^_`|~-")

# ---------------------------------------------------------------- qualités (Accept-*)

# « a;q=0.5, b, c;q=0 » -> [(a minuscule, qualité float)] triés par qualité décroissante (ordre stable).
func parse_quality_list(value):
    items := []
    idx := 0
    for item in split_list(value):
        pr := parse_parameters(item)
        q := 1.0
        if "q" in pr[1]:
            try:
                q = to_float(pr[1]["q"])
            catch e:
                q = 0.0
            if q < 0.0:
                q = 0.0
            if q > 1.0:
                q = 1.0
        append(items, (_s.lower(trim(pr[0])), q, idx))
        idx += 1
    # tri par insertion stable, qualité décroissante
    n := len(items)
    i := 1
    while i < n:
        cur := items[i]
        j := i - 1
        while j >= 0 and items[j][1] < cur[1]:
            items[j + 1] = items[j]
            j -= 1
        items[j + 1] = cur
        i += 1
    out := []
    for it in items:
        append(out, (it[0], it[1]))
    return out

# Qualité accordée à candidate par l'en-tête (« * », « type/* » et préfixe de langue « fr » pour « fr-CA »
# compris) ; 1.0 si l'en-tête est absent.
func quality_of(value, candidate):
    if value == null or trim(value) == "":
        return 1.0
    c := _s.lower(candidate)
    best := -1.0
    best_spec := -1
    for item in parse_quality_list(value):
        name := item[0]
        spec := -1
        if name == c:
            spec = 3
        elif name == "*" or name == "*/*":
            spec = 0
        elif _s.ends_with(name, "/*") and _s.starts_with(c, name[0:len(name) - 1]):
            spec = 1
        elif _s.starts_with(c, name + "-") or _s.starts_with(name, c + "-"):
            spec = 2
        if spec > best_spec:
            best_spec = spec
            best = item[1]
    if best_spec < 0:
        return 0.0
    return best

# Meilleur choix parmi available pour un en-tête Accept-* (null si aucun n'est acceptable).
func best_match(value, available):
    best := null
    best_q := 0.0
    for a in available:
        q := quality_of(value, a)
        if q > best_q:
            best = a
            best_q = q
    return best

# ---------------------------------------------------------------- directives (Cache-Control...)

# « max-age=60, no-store, private="a, b" » -> {"max-age": "60", "no-store": null, "private": "a, b"} (clés en
# minuscules).
func parse_directives(value):
    out := {}
    for item in split_list(value):
        eq := _s.find(item, "=")
        if eq < 0:
            out[_s.lower(trim(item))] = null
        else:
            out[_s.lower(trim(item[0:eq]))] = unquote(item[eq + 1:len(item)])
    return out

func format_directives(directives):
    out := []
    for k in keys(directives):
        v := directives[k]
        if v == null or v == true:
            append(out, k)
        elif v == false:
            continue
        else:
            append(out, k + "=" + quote_if_needed(str(v)))
    return _s.join(", ", out)

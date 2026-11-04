# ALEX STANDARD LIBRARY — web.url.path_segment
#
# Segments de chemin d'URL (RFC 3986 §3.3) : ce qui se trouve entre deux « / ». Un segment a une forme ENCODÉE
# (dans l'URL : « a%20b ») et une valeur DÉCODÉE (« a b ») ; « / » dans une valeur est encodé « %2F » pour ne pas
# créer de nouveau segment.
#
#   use web.url.path_segment as seg
#   seg.encode("rapport 2024/v2.pdf")   # rapport%202024%2Fv2.pdf
#   seg.decode("caf%C3%A9")             # café
#   seg.is_dot("%2E%2e")                # true (« .. » encodé)
#   seg.extension("archive.tar.gz")     # gz
#
# Erreurs : UrlEncodingError (decode strict), TypeError.

from core use len, type
use string as _s
use web.url.url_errors as _err
use web.url.percent_encoding as _pe

# Forme encodée d'une valeur de segment (« / », « ? », « # », espaces, non ASCII encodés).
func encode(value):
    _err.need_str("path_segment.encode", "value", value)
    return _pe.encode(value, _pe.PCHAR_SAFE)

# Valeur décodée d'un segment encodé.
func decode(segment, strict=false):
    _err.need_str("path_segment.decode", "segment", segment)
    return _pe.decode(segment, false, strict)

# « . » ou son équivalent encodé « %2e » (insensible à la casse).
func is_single_dot(segment):
    return segment == "." or _s.lower(segment) == "%2e"

# « .. » ou ses formes encodées (« .%2e », « %2e. », « %2e%2e »).
func is_double_dot(segment):
    s := _s.lower(segment)
    return s == ".." or s == ".%2e" or s == "%2e." or s == "%2e%2e"

func is_dot(segment):
    return is_single_dot(segment) or is_double_dot(segment)

# Vrai si la valeur décodée contient un caractère qui rendrait un chemin de fichier dangereux : « / », « \ »,
# octet nul, ou si elle vaut « . » / « .. ».
func is_unsafe_for_filesystem(segment):
    v := decode(segment)
    if v == "." or v == "..":
        return true
    for c in v:
        if c == '/' or c == '\\' or _s.ord(c) == 0:
            return true
    return false

# Extension (sans le point) de la valeur décodée, ou "".
func extension(segment):
    v := decode(segment)
    i := len(v) - 1
    while i > 0:
        if v[i] == '.':
            return v[i + 1:len(v)]
        i -= 1
    return ""

# Partie avant l'extension.
func stem(segment):
    v := decode(segment)
    i := len(v) - 1
    while i > 0:
        if v[i] == '.':
            return v[0:i]
        i -= 1
    return v

# Paramètres de segment « ;clé=valeur » (RFC 3986 les laisse aux schémas) : (nom, dict des paramètres).
func split_params(segment):
    parts := _s.split(segment, ";")
    params := {}
    i := 1
    while i < len(parts):
        p := parts[i]
        eq := _s.find(p, "=")
        if eq >= 0:
            params[decode(p[0:eq])] = decode(p[eq + 1:len(p)])
        elif p != "":
            params[decode(p)] = ""
        i += 1
    return (decode(parts[0]), params)

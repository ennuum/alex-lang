# ALEX STANDARD LIBRARY — web.http.content_length
#
# En-tête Content-Length (RFC 9110 §8.6, RFC 9112 §6.3) : longueur du corps en OCTETS. Son analyse est stricte,
# car une longueur mal comprise par un mandataire ou un serveur permet la « contrebande de requêtes » (request
# smuggling) : chiffres décimaux uniquement, valeurs répétées identiques seulement, jamais avec Transfer-Encoding.
#
#   use web.http.content_length as cl
#   cl.parse("42")               # 42
#   cl.parse("42, 42")           # 42   (liste de valeurs identiques tolérée)
#   cl.parse("-1")               # HttpParseError [400]
#   cl.of("été")                 # 5    (octets UTF-8, pas caractères)
#   cl.from_headers(h)           # null si absent ; erreur si incohérent avec Transfer-Encoding
#
# Erreurs : HttpParseError (400), HttpLimitError (413, check_limit).

from core use len, type
use string as _s
use web.http.http_errors as _err
use web.http.header_value as _hv

# Plus grand Content-Length accepté à l'analyse (au-delà : 413), indépendamment des limites du serveur.
const MAX_VALUE := 1099511627776

func _parse_one(text):
    t := _hv.trim(text)
    if len(t) == 0 or len(t) > 15:
        _err.parse_error("content_length.parse", "Content-Length invalide '" + _hv.sanitize(text) + "'")
    n := 0
    for c in t:
        if c < '0' or c > '9':
            _err.parse_error("content_length.parse", "Content-Length invalide '" + _hv.sanitize(text) + "'")
        n = n * 10 + (_s.ord(c) - 48)
    if n > MAX_VALUE:
        _err.limit_error("content_length.parse", "Content-Length trop grand (" + t + ")", 413)
    return n

# Longueur depuis la valeur de l'en-tête (« 12 » ou « 12, 12 ») ; HttpParseError si invalide ou incohérente.
func parse(value):
    if type(value) == "int":
        return check(value)
    if type(value) != "str":
        raise("TypeError", "content_length.parse : str attendue (obtenu " + type(value) + ")")
    parts := _s.split(value, ",")
    first := _parse_one(parts[0])
    i := 1
    while i < len(parts):
        if _parse_one(parts[i]) != first:
            _err.parse_error("content_length.parse", "valeurs de Content-Length différentes '" + _hv.sanitize(value) + "'")
        i += 1
    return first

func is_valid(value):
    try:
        parse(value)
        return true
    catch e:
        return false

func check(n):
    if type(n) != "int" or n < 0:
        _err.http_error("content_length.check", "longueur entière >= 0 attendue (obtenu " + str(n) + ")")
    return n

# Longueur (octets) d'un corps str ; 0 pour null.
func of(body):
    if body == null:
        return 0
    return _s.byte_len(body)

# Longueur déclarée par des en-têtes (web.http.headers.Headers) : null si absente. Plusieurs lignes doivent être
# identiques ; la présence simultanée de Transfer-Encoding est une erreur (RFC 9112 §6.1) si strict.
func from_headers(headers, strict=true):
    values := headers.get_all("content-length")
    if len(values) == 0:
        return null
    if strict and headers.has("transfer-encoding"):
        _err.parse_error("content_length.from_headers", "Content-Length et Transfer-Encoding ensemble")
    first := parse(values[0])
    for v in values:
        if parse(v) != first:
            _err.parse_error("content_length.from_headers", "plusieurs Content-Length différents")
    return first

# HttpLimitError (413) si n dépasse limit (null : pas de limite).
func check_limit(n, limit):
    if limit != null and n > limit:
        _err.limit_error("content_length.check_limit", "corps de " + str(n) + " octets, limite " + str(limit), 413)
    return n

# ALEX STANDARD LIBRARY — web.http.header_name
#
# Noms d'en-têtes HTTP (RFC 9110 §5.1) : un « token », insensible à la casse. Ce module valide les noms, donne leur
# forme canonique d'affichage (« content-type » -> « Content-Type », « www-authenticate » -> « WWW-Authenticate »),
# et classe les en-têtes : saut par saut (hop-by-hop), à valeur unique, sensibles (à masquer dans les journaux).
#
#   use web.http.header_name as hn
#   hn.canonical("x-request-id")        # X-Request-Id
#   hn.canonical("etag")                # ETag
#   hn.is_valid("Content Type")         # false (espace interdit)
#   hn.is_hop_by_hop("Connection")      # true
#   hn.is_sensitive("authorization")    # true
#   hn.CONTENT_TYPE                     # Content-Type
#
# Erreurs : HttpHeaderError (check).

from core use len, type
from collections use append
use string as _s
use web.http.http_errors as _err
use web.http.method as _method

const ACCEPT := "Accept"
const ACCEPT_CHARSET := "Accept-Charset"
const ACCEPT_ENCODING := "Accept-Encoding"
const ACCEPT_LANGUAGE := "Accept-Language"
const ACCEPT_RANGES := "Accept-Ranges"
const AGE := "Age"
const ALLOW := "Allow"
const AUTHORIZATION := "Authorization"
const CACHE_CONTROL := "Cache-Control"
const CONNECTION := "Connection"
const CONTENT_DISPOSITION := "Content-Disposition"
const CONTENT_ENCODING := "Content-Encoding"
const CONTENT_LANGUAGE := "Content-Language"
const CONTENT_LENGTH := "Content-Length"
const CONTENT_LOCATION := "Content-Location"
const CONTENT_RANGE := "Content-Range"
const CONTENT_SECURITY_POLICY := "Content-Security-Policy"
const CONTENT_TYPE := "Content-Type"
const COOKIE := "Cookie"
const DATE := "Date"
const ETAG := "ETag"
const EXPECT := "Expect"
const EXPIRES := "Expires"
const FORWARDED := "Forwarded"
const HOST := "Host"
const IF_MATCH := "If-Match"
const IF_MODIFIED_SINCE := "If-Modified-Since"
const IF_NONE_MATCH := "If-None-Match"
const IF_RANGE := "If-Range"
const IF_UNMODIFIED_SINCE := "If-Unmodified-Since"
const KEEP_ALIVE := "Keep-Alive"
const LAST_MODIFIED := "Last-Modified"
const LINK := "Link"
const LOCATION := "Location"
const ORIGIN := "Origin"
const PROXY_AUTHENTICATE := "Proxy-Authenticate"
const PROXY_AUTHORIZATION := "Proxy-Authorization"
const PROXY_CONNECTION := "Proxy-Connection"
const RANGE := "Range"
const REFERER := "Referer"
const RETRY_AFTER := "Retry-After"
const SERVER := "Server"
const SET_COOKIE := "Set-Cookie"
const STRICT_TRANSPORT_SECURITY := "Strict-Transport-Security"
const TE := "TE"
const TRAILER := "Trailer"
const TRANSFER_ENCODING := "Transfer-Encoding"
const UPGRADE := "Upgrade"
const USER_AGENT := "User-Agent"
const VARY := "Vary"
const VIA := "Via"
const WWW_AUTHENTICATE := "WWW-Authenticate"
const X_CONTENT_TYPE_OPTIONS := "X-Content-Type-Options"
const X_FORWARDED_FOR := "X-Forwarded-For"
const X_FORWARDED_HOST := "X-Forwarded-Host"
const X_FORWARDED_PROTO := "X-Forwarded-Proto"
const X_FRAME_OPTIONS := "X-Frame-Options"
const X_REQUEST_ID := "X-Request-Id"

# Écritures particulières (sinon : majuscule après chaque « - »).
const _SPECIAL := {"etag": "ETag", "te": "TE", "www-authenticate": "WWW-Authenticate", "content-md5": "Content-MD5", "dnt": "DNT", "x-xss-protection": "X-XSS-Protection", "x-ua-compatible": "X-UA-Compatible", "x-dns-prefetch-control": "X-DNS-Prefetch-Control", "sec-websocket-key": "Sec-WebSocket-Key", "sec-websocket-accept": "Sec-WebSocket-Accept", "sec-websocket-version": "Sec-WebSocket-Version", "sec-websocket-protocol": "Sec-WebSocket-Protocol", "sec-websocket-extensions": "Sec-WebSocket-Extensions", "x-request-id": "X-Request-Id", "nel": "NEL"}

# En-têtes saut par saut (RFC 9110 §7.6.1) : jamais retransmis par un mandataire.
const HOP_BY_HOP := ["connection", "keep-alive", "proxy-connection", "proxy-authenticate", "proxy-authorization", "te", "trailer", "transfer-encoding", "upgrade"]

# En-têtes qui ne peuvent apparaître qu'une fois (une répétition est une erreur ou un risque de désynchronisation).
const SINGLETONS := ["content-length", "content-type", "host", "authorization", "proxy-authorization", "location", "content-location", "date", "etag", "expires", "last-modified", "if-modified-since", "if-unmodified-since", "if-range", "max-forwards", "referer", "retry-after", "server", "user-agent", "age", "content-range", "range", "from", "origin"]

# En-têtes dont la valeur est secrète (masquée par Headers.redacted).
const SENSITIVE := ["authorization", "proxy-authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token", "x-csrf-token"]

# En-têtes qui NE se combinent PAS par « , » (Set-Cookie : une ligne par cookie, RFC 6265 §3).
const NOT_COMBINABLE := ["set-cookie"]

func is_valid(name):
    return _method.is_token(name)

func check(name):
    if type(name) != "str":
        raise("TypeError", "header_name.check : str attendue (obtenu " + type(name) + ")")
    if not is_valid(name):
        _err.header_error("header_name.check", "nom d'en-tête invalide '" + name + "'")
    return name

# Clé de comparaison (minuscules).
func key(name):
    return _s.lower(name)

# Forme d'affichage canonique.
func canonical(name):
    k := _s.lower(name)
    if k in _SPECIAL:
        return _SPECIAL[k]
    out := []
    up := true
    for c in k:
        if up and c >= 'a' and c <= 'z':
            append(out, _s.upper(str(c)))
        else:
            append(out, str(c))
        up = c == '-'
    return _s.join("", out)

func equals(a, b):
    return _s.lower(a) == _s.lower(b)

func is_hop_by_hop(name):
    return _s.lower(name) in HOP_BY_HOP

func is_singleton(name):
    return _s.lower(name) in SINGLETONS

func is_sensitive(name):
    return _s.lower(name) in SENSITIVE

func is_combinable(name):
    return not (_s.lower(name) in NOT_COMBINABLE)

# En-têtes de requête qu'un client ne doit jamais laisser fixer par du code non fiable (contrôle du cadrage).
func is_framing(name):
    k := _s.lower(name)
    return k == "content-length" or k == "transfer-encoding" or k == "host" or k == "connection" or k == "trailer" or k == "te" or k == "upgrade"

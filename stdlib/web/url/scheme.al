# ALEX STANDARD LIBRARY — web.url.scheme
#
# Schémas d'URL (RFC 3986 §3.1) : validation, forme canonique (minuscules), ports par défaut et schémas
# « spéciaux » au sens du WHATWG (http, https, ws, wss, ftp, file) : autorité obligatoire, « \ » accepté comme
# « / », chemin vide ramené à « / », port par défaut omis.
#
#   use web.url.scheme as sc
#   sc.normalize("HTTPS")          # https
#   sc.is_valid("svn+ssh")         # true
#   sc.default_port("wss")         # 443
#   sc.is_special("mailto")        # false
#   sc.is_secure("https")          # true
#
# Erreurs : UrlSchemeError (normalize/check sur un schéma invalide).

from core use len, type
use string as _s
use web.url.url_errors as _err

const HTTP := "http"
const HTTPS := "https"
const WS := "ws"
const WSS := "wss"
const FTP := "ftp"
const FILE := "file"
const MAILTO := "mailto"
const DATA := "data"

const SPECIAL := ["http", "https", "ws", "wss", "ftp", "file"]
const SECURE := ["https", "wss", "ftps", "sftp"]

# Ports par défaut connus (au-delà des schémas spéciaux, pour information).
const _PORTS := {"http": 80, "https": 443, "ws": 80, "wss": 443, "ftp": 21, "ftps": 990, "sftp": 22, "ssh": 22, "telnet": 23, "gopher": 70, "ldap": 389, "ldaps": 636, "smtp": 25, "imap": 143, "pop3": 110, "redis": 6379, "postgres": 5432, "postgresql": 5432, "mysql": 3306, "mongodb": 27017, "amqp": 5672, "mqtt": 1883}

func _is_alpha(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

func _is_digit(c):
    return c >= '0' and c <= '9'

# Vrai si text est un schéma valide : ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ).
func is_valid(text):
    if type(text) != "str" or len(text) == 0:
        return false
    if not _is_alpha(text[0]):
        return false
    for c in text:
        if not (_is_alpha(c) or _is_digit(c) or c == '+' or c == '-' or c == '.'):
            return false
    return true

# Forme canonique (minuscules) ; UrlSchemeError si le schéma est invalide.
func normalize(text):
    check(text)
    return _s.lower(text)

func check(text):
    if type(text) != "str":
        raise("TypeError", "scheme.check : str attendue (obtenu " + type(text) + ")")
    if not is_valid(text):
        _err.scheme_error("scheme.check", "schéma invalide '" + text + "'")

func is_special(scheme):
    if scheme == null:
        return false
    return _s.lower(scheme) in SPECIAL

func is_secure(scheme):
    if scheme == null:
        return false
    return _s.lower(scheme) in SECURE

# Port par défaut du schéma, ou null s'il n'en a pas (ou s'il est inconnu).
func default_port(scheme):
    if scheme == null:
        return null
    k := _s.lower(scheme)
    if k in _PORTS:
        return _PORTS[k]
    return null

# Vrai si port est le port par défaut du schéma (il est alors omis dans la forme canonique d'une URL spéciale).
func is_default_port(scheme, port):
    d := default_port(scheme)
    return d != null and port == d

# Schéma « web » (requêtes HTTP) : http, https.
func is_http(scheme):
    return scheme == HTTP or scheme == HTTPS

func is_websocket(scheme):
    return scheme == WS or scheme == WSS

# Équivalent sécurisé d'un schéma (http -> https, ws -> wss), sinon le schéma lui-même.
func secure_variant(scheme):
    if scheme == HTTP:
        return HTTPS
    if scheme == WS:
        return WSS
    if scheme == FTP:
        return "ftps"
    return scheme

# Recherche un schéma au début de text (« http:... ») : renvoie (schéma en minuscules, position après « : »),
# ou null s'il n'y en a pas.
func detect(text):
    n := len(text)
    i := 0
    while i < n:
        c := text[i]
        if c == ':':
            if i == 0:
                return null
            return (_s.lower(text[0:i]), i + 1)
        if i == 0:
            if not _is_alpha(c):
                return null
        elif not (_is_alpha(c) or _is_digit(c) or c == '+' or c == '-' or c == '.'):
            return null
        i += 1
    return null

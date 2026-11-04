# ALEX STANDARD LIBRARY — web.url.port
#
# Ports d'URL (RFC 3986 §3.2.3) : un entier décimal de 0 à 65535, sans signe ni espace. Un port vide (« http://h:/ »)
# vaut « pas de port ». Le port effectif d'une URL est son port explicite, sinon celui du schéma.
#
#   use web.url.port as pt
#   pt.parse("8080")                 # 8080
#   pt.parse("")                     # null
#   pt.effective("https", null)      # 443
#   pt.serialize("http", 80)         # ""        (port par défaut omis)
#   pt.serialize("http", 8080)       # ":8080"
#
# Erreurs : UrlPortError.

from core use len, type
use string as _s
use web.url.url_errors as _err
use web.url.scheme as _scheme

const MIN := 0
const MAX := 65535

func is_valid(port):
    return type(port) == "int" and port >= MIN and port <= MAX

func check(port):
    if not is_valid(port):
        _err.port_error("port.check", "entier entre 0 et 65535 attendu (obtenu " + str(port) + ")")
    return port

# Analyse le texte d'un port ; null s'il est vide ; UrlPortError s'il n'est pas un entier décimal dans 0..65535.
func parse(text):
    if text == null:
        return null
    if type(text) == "int":
        return check(text)
    _err.need_str("port.parse", "text", text)
    if len(text) == 0:
        return null
    value := 0
    for c in text:
        if c < '0' or c > '9':
            _err.port_error("port.parse", "port non numérique '" + text + "'")
        value = value * 10 + (_s.ord(c) - 48)
        if value > MAX:
            _err.port_error("port.parse", "port hors de 0..65535 '" + text + "'")
    return value

# Port effectif : port explicite, sinon port par défaut du schéma (null si aucun).
func effective(scheme, port):
    if port != null:
        return port
    return _scheme.default_port(scheme)

# Port à garder dans la forme canonique : null s'il est égal au port par défaut du schéma.
func canonical(scheme, port):
    if port != null and _scheme.is_default_port(scheme, port):
        return null
    return port

# « :8080 », ou "" si le port est absent ou par défaut.
func serialize(scheme, port):
    p := canonical(scheme, port)
    if p == null:
        return ""
    return ":" + str(p)

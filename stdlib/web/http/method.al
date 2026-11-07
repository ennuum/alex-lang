# ALEX STANDARD LIBRARY — web.http.method
#
# Méthodes HTTP (RFC 9110 §9) : constantes, validation (un « token », sensible à la casse), et propriétés
# sémantiques utilisées par les clients, les serveurs et les caches.
#
#   | Méthode | sûre | idempotente | corps de requête | réponse cachable |
#   |---------|------|-------------|------------------|------------------|
#   | GET     | oui  | oui         | non (sans sens)  | oui              |
#   | HEAD    | oui  | oui         | non              | oui              |
#   | POST    | non  | non         | oui              | si explicite     |
#   | PUT     | non  | oui         | oui              | non              |
#   | DELETE  | non  | oui         | rare             | non              |
#   | PATCH   | non  | non         | oui (RFC 5789)   | non              |
#   | OPTIONS | oui  | oui         | rare             | non              |
#   | TRACE   | oui  | oui         | non              | non              |
#   | CONNECT | non  | non         | non              | non              |
#
#   use web.http.method as m
#   m.is_safe("GET")             # true
#   m.is_idempotent("PUT")       # true   (un client peut la rejouer après une coupure)
#   m.normalize("get")           # GET    (les méthodes standard sont ramenées en majuscules)
#   m.check("BREW")              # BREW   (méthode d'extension valide)
#   m.check("GE T")              # HttpMethodError
#
# Erreurs : HttpMethodError.

from core use len, type
use string as _s
use web.http.http_errors as _err

const GET := "GET"
const HEAD := "HEAD"
const POST := "POST"
const PUT := "PUT"
const DELETE := "DELETE"
const PATCH := "PATCH"
const OPTIONS := "OPTIONS"
const TRACE := "TRACE"
const CONNECT := "CONNECT"

const STANDARD := ["GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "TRACE", "CONNECT"]
const SAFE := ["GET", "HEAD", "OPTIONS", "TRACE"]
const IDEMPOTENT := ["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]
const CACHEABLE := ["GET", "HEAD"]
const WITH_BODY := ["POST", "PUT", "PATCH"]

# Caractères « tchar » d'un token (RFC 9110 §5.6.2) : ! # $ % & ' * + - . ^ _ ` | ~ chiffres lettres.
const TCHAR_MARKS := "!#$%&'*+-.^_`|~"

func is_tchar(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c in TCHAR_MARKS

# Tokens déjà reconnus (noms d'en-têtes, méthodes : peu de valeurs distinctes).
_tokens := [{}, 0]

func is_token(text):
    if type(text) != "str" or len(text) == 0:
        return false
    seen := _tokens[0]
    if text in seen:
        return true
    for c in text:
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c in TCHAR_MARKS):
            return false
    if len(text) <= 128:
        if _tokens[1] >= 4096:
            _tokens[0] = {}
            _tokens[1] = 0
        _tokens[0][text] = true
        _tokens[1] = _tokens[1] + 1
    return true

func is_valid(method):
    return is_token(method)

# Méthode validée ; HttpMethodError si ce n'est pas un token.
func check(method):
    if not is_token(method):
        _err.method_error("method.check", "méthode invalide '" + str(method) + "'", 400)
    return method

# Méthode standard ramenée en majuscules (« get » -> « GET ») ; les méthodes d'extension sont gardées telles
# quelles (elles sont sensibles à la casse).
func normalize(method):
    check(method)
    up := _s.upper(method)
    if up in STANDARD:
        return up
    return method

func is_standard(method):
    return method in STANDARD

func is_safe(method):
    return method in SAFE

func is_idempotent(method):
    return method in IDEMPOTENT

func is_cacheable(method):
    return method in CACHEABLE

# Vrai si la méthode transporte normalement un corps de requête.
func expects_body(method):
    return method in WITH_BODY

# Vrai si une réponse à cette méthode n'a jamais de corps (HEAD) ; CONNECT réussi : tunnel.
func response_has_no_body(method):
    return method == HEAD

# Méthode après une redirection (RFC 9110 §15.4) : 303 -> GET (sauf HEAD) ; 301/302 : POST -> GET (usage des
# navigateurs) ; 307/308 : inchangée.
func after_redirect(method, status):
    if status == 303:
        if method == HEAD:
            return HEAD
        return GET
    if (status == 301 or status == 302) and method == POST:
        return GET
    return method

# Valeur de l'en-tête Allow pour une liste de méthodes (HEAD ajouté si GET est présent).
func allow_header(methods):
    out := []
    for m in methods:
        if not (m in out):
            out = out + [m]
    if GET in out and not (HEAD in out):
        out = out + [HEAD]
    return _s.join(", ", out)

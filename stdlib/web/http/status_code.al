# ALEX STANDARD LIBRARY — web.http.status_code
#
# Codes de statut HTTP (RFC 9110 §15 et registre IANA) : constantes, phrases de raison, classes, et propriétés
# utiles aux clients (reprise, redirection) et aux serveurs (corps interdit).
#
#   use web.http.status_code as sc
#   sc.reason(404)               # Not Found
#   sc.is_client_error(404)      # true
#   sc.category(503)             # server_error
#   sc.is_redirect(308)          # true
#   sc.allows_body(304)          # false
#   sc.is_retryable(503)         # true
#   sc.NOT_FOUND                 # 404
#   sc.describe(418)             # 418 I'm a teapot
#
# Erreurs : HttpStatusError (check).

from core use len, type
use web.http.http_errors as _err

const CONTINUE := 100
const SWITCHING_PROTOCOLS := 101
const PROCESSING := 102
const EARLY_HINTS := 103
const OK := 200
const CREATED := 201
const ACCEPTED := 202
const NON_AUTHORITATIVE_INFORMATION := 203
const NO_CONTENT := 204
const RESET_CONTENT := 205
const PARTIAL_CONTENT := 206
const MULTI_STATUS := 207
const ALREADY_REPORTED := 208
const IM_USED := 226
const MULTIPLE_CHOICES := 300
const MOVED_PERMANENTLY := 301
const FOUND := 302
const SEE_OTHER := 303
const NOT_MODIFIED := 304
const USE_PROXY := 305
const TEMPORARY_REDIRECT := 307
const PERMANENT_REDIRECT := 308
const BAD_REQUEST := 400
const UNAUTHORIZED := 401
const PAYMENT_REQUIRED := 402
const FORBIDDEN := 403
const NOT_FOUND := 404
const METHOD_NOT_ALLOWED := 405
const NOT_ACCEPTABLE := 406
const PROXY_AUTHENTICATION_REQUIRED := 407
const REQUEST_TIMEOUT := 408
const CONFLICT := 409
const GONE := 410
const LENGTH_REQUIRED := 411
const PRECONDITION_FAILED := 412
const CONTENT_TOO_LARGE := 413
const URI_TOO_LONG := 414
const UNSUPPORTED_MEDIA_TYPE := 415
const RANGE_NOT_SATISFIABLE := 416
const EXPECTATION_FAILED := 417
const IM_A_TEAPOT := 418
const MISDIRECTED_REQUEST := 421
const UNPROCESSABLE_CONTENT := 422
const LOCKED := 423
const FAILED_DEPENDENCY := 424
const TOO_EARLY := 425
const UPGRADE_REQUIRED := 426
const PRECONDITION_REQUIRED := 428
const TOO_MANY_REQUESTS := 429
const REQUEST_HEADER_FIELDS_TOO_LARGE := 431
const UNAVAILABLE_FOR_LEGAL_REASONS := 451
const INTERNAL_SERVER_ERROR := 500
const NOT_IMPLEMENTED := 501
const BAD_GATEWAY := 502
const SERVICE_UNAVAILABLE := 503
const GATEWAY_TIMEOUT := 504
const HTTP_VERSION_NOT_SUPPORTED := 505
const VARIANT_ALSO_NEGOTIATES := 506
const INSUFFICIENT_STORAGE := 507
const LOOP_DETECTED := 508
const NOT_EXTENDED := 510
const NETWORK_AUTHENTICATION_REQUIRED := 511

const _REASONS := {100: "Continue", 101: "Switching Protocols", 102: "Processing", 103: "Early Hints", 200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content", 205: "Reset Content", 206: "Partial Content", 207: "Multi-Status", 208: "Already Reported", 226: "IM Used", 300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified", 305: "Use Proxy", 307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 402: "Payment Required", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Content Too Large", 414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed", 418: "I'm a teapot", 421: "Misdirected Request", 422: "Unprocessable Content", 423: "Locked", 424: "Failed Dependency", 425: "Too Early", 426: "Upgrade Required", 428: "Precondition Required", 429: "Too Many Requests", 431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons", 500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout", 505: "HTTP Version Not Supported", 506: "Variant Also Negotiates", 507: "Insufficient Storage", 508: "Loop Detected", 510: "Not Extended", 511: "Network Authentication Required"}

const INFORMATIONAL := "informational"
const SUCCESS := "success"
const REDIRECTION := "redirection"
const CLIENT_ERROR := "client_error"
const SERVER_ERROR := "server_error"

func is_valid(code):
    return type(code) == "int" and code >= 100 and code <= 999

func check(code):
    if not is_valid(code):
        _err.status_error("status_code.check", "code de statut à trois chiffres attendu (obtenu " + str(code) + ")")
    return code

# Phrase de raison standard, ou fallback (par défaut, celle de la classe : « Client Error »...).
func reason(code, fallback=null):
    if code in _REASONS:
        return _REASONS[code]
    if fallback != null:
        return fallback
    c := category(code)
    if c == INFORMATIONAL:
        return "Informational"
    if c == SUCCESS:
        return "Success"
    if c == REDIRECTION:
        return "Redirection"
    if c == CLIENT_ERROR:
        return "Client Error"
    if c == SERVER_ERROR:
        return "Server Error"
    return "Unknown"

func is_known(code):
    return code in _REASONS

# « 404 Not Found »
func describe(code):
    return str(code) + " " + reason(code)

func category(code):
    if code >= 100 and code < 200:
        return INFORMATIONAL
    if code >= 200 and code < 300:
        return SUCCESS
    if code >= 300 and code < 400:
        return REDIRECTION
    if code >= 400 and code < 500:
        return CLIENT_ERROR
    if code >= 500 and code < 600:
        return SERVER_ERROR
    return "unknown"

func is_informational(code):
    return code >= 100 and code < 200

func is_success(code):
    return code >= 200 and code < 300

func is_redirection(code):
    return code >= 300 and code < 400

func is_client_error(code):
    return code >= 400 and code < 500

func is_server_error(code):
    return code >= 500 and code < 600

func is_error(code):
    return code >= 400

# Redirection que suit un client (Location) : 301, 302, 303, 307, 308.
func is_redirect(code):
    return code == 301 or code == 302 or code == 303 or code == 307 or code == 308

# Redirection qui conserve méthode et corps (307, 308).
func preserves_method(code):
    return code == 307 or code == 308

func is_permanent_redirect(code):
    return code == 301 or code == 308

# Une réponse de ce statut n'a jamais de corps : 1xx, 204, 304 (RFC 9110 §6.4.1).
func allows_body(code):
    return not (is_informational(code) or code == 204 or code == 304)

# Statuts pour lesquels réessayer plus tard a un sens : 408, 425, 429, 500, 502, 503, 504.
func is_retryable(code):
    return code == 408 or code == 425 or code == 429 or code == 500 or code == 502 or code == 503 or code == 504

# Réponse cachable par défaut (RFC 9110 §15.1).
func is_cacheable_by_default(code):
    return code in [200, 203, 204, 206, 300, 301, 308, 404, 405, 410, 414, 501]

# Tous les codes connus, triés.
func all_codes():
    out := []
    code := 100
    while code < 600:
        if code in _REASONS:
            out = out + [code]
        code += 1
    return out

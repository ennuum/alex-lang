# ALEX STANDARD LIBRARY — network.constants
#
# Constantes partagées par les modules network.* : familles d'adresses, ports bien connus, codes et raisons
# HTTP, limites par défaut, séparateurs de protocole.
#
# Exemple
#   use network.constants as nc
#   print(nc.PORT_HTTPS)                 # 443
#   print(nc.default_port("imaps"))      # 993
#   print(nc.status_reason(404))         # "Not Found"
#   print(nc.status_class(503))          # "server_error"

from collections use contains_key
use string as _s

# ---------------------------------------------------------------- familles et transports

const FAMILY_ANY := 0
const FAMILY_UNIX := 1
const FAMILY_IPV4 := 4
const FAMILY_IPV6 := 6
const TCP := "tcp"
const UDP := "udp"

# ---------------------------------------------------------------- séparateurs

const CRLF := "\r\n"
const LF := "\n"
const CRLF2 := "\r\n\r\n"

# ---------------------------------------------------------------- ports bien connus (IANA)

const PORT_ECHO := 7
const PORT_FTP_DATA := 20
const PORT_FTP := 21
const PORT_SSH := 22
const PORT_TELNET := 23
const PORT_SMTP := 25
const PORT_DNS := 53
const PORT_HTTP := 80
const PORT_POP3 := 110
const PORT_NTP := 123
const PORT_IMAP := 143
const PORT_SNMP := 161
const PORT_LDAP := 389
const PORT_HTTPS := 443
const PORT_SMTPS := 465
const PORT_SUBMISSION := 587
const PORT_LDAPS := 636
const PORT_FTPS := 990
const PORT_IMAPS := 993
const PORT_POP3S := 995
const PORT_SOCKS := 1080
const PORT_MDNS := 5353
const PORT_HTTP_ALT := 8080
const PORT_GRPC := 50051

_SCHEME_PORTS := {"http": 80, "https": 443, "ws": 80, "wss": 443, "ftp": 21, "ftps": 990, "sftp": 22, "ssh": 22, "telnet": 23, "smtp": 25, "smtps": 465, "submission": 587, "imap": 143, "imaps": 993, "pop3": 110, "pop3s": 995, "ldap": 389, "ldaps": 636, "dns": 53, "ntp": 123, "socks": 1080, "socks4": 1080, "socks4a": 1080, "socks5": 1080, "socks5h": 1080, "gopher": 70, "rtsp": 554, "mqtt": 1883, "mqtts": 8883, "redis": 6379, "postgres": 5432, "postgresql": 5432, "mysql": 3306, "mongodb": 27017, "amqp": 5672, "amqps": 5671, "grpc": 50051, "grpcs": 443, "xmpp": 5222, "irc": 6667, "ircs": 6697, "nntp": 119, "git": 9418}

# Port par défaut d'un schéma d'URL (« https » -> 443), ou null s'il n'en a pas.
func default_port(scheme):
    if scheme == null:
        return null
    k := _s.lower(str(scheme))
    if contains_key(_SCHEME_PORTS, k):
        return _SCHEME_PORTS[k]
    return null

# Schémas dont la connexion est chiffrée d'emblée (TLS implicite).
func is_secure_scheme(scheme):
    k := _s.lower(str(scheme))
    return k == "https" or k == "wss" or k == "ftps" or k == "smtps" or k == "imaps" or k == "pop3s" or k == "ldaps" or k == "mqtts" or k == "amqps" or k == "ircs" or k == "grpcs"

# ---------------------------------------------------------------- délais et limites par défaut (secondes, octets)

const DEFAULT_CONNECT_TIMEOUT := 10.0
const DEFAULT_TIMEOUT := 30.0
const DEFAULT_IDLE_TIMEOUT := 60.0
const DEFAULT_MAX_REDIRECTS := 10
const DEFAULT_BUFFER_SIZE := 65536
const MAX_LINE := 1048576
const MAX_HEADER_BYTES := 65536
const MAX_HEADERS := 200
const MAX_BODY := 104857600
const MAX_DATAGRAM := 65507

# ---------------------------------------------------------------- HTTP

const HTTP_10 := "HTTP/1.0"
const HTTP_11 := "HTTP/1.1"
const HTTP_METHODS := ["GET", "HEAD", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "TRACE", "CONNECT"]
const SAFE_METHODS := ["GET", "HEAD", "OPTIONS", "TRACE"]
const IDEMPOTENT_METHODS := ["GET", "HEAD", "PUT", "DELETE", "OPTIONS", "TRACE"]

const STATUS_CONTINUE := 100
const STATUS_SWITCHING_PROTOCOLS := 101
const STATUS_OK := 200
const STATUS_CREATED := 201
const STATUS_ACCEPTED := 202
const STATUS_NO_CONTENT := 204
const STATUS_PARTIAL_CONTENT := 206
const STATUS_MOVED_PERMANENTLY := 301
const STATUS_FOUND := 302
const STATUS_SEE_OTHER := 303
const STATUS_NOT_MODIFIED := 304
const STATUS_TEMPORARY_REDIRECT := 307
const STATUS_PERMANENT_REDIRECT := 308
const STATUS_BAD_REQUEST := 400
const STATUS_UNAUTHORIZED := 401
const STATUS_FORBIDDEN := 403
const STATUS_NOT_FOUND := 404
const STATUS_METHOD_NOT_ALLOWED := 405
const STATUS_REQUEST_TIMEOUT := 408
const STATUS_CONFLICT := 409
const STATUS_PAYLOAD_TOO_LARGE := 413
const STATUS_URI_TOO_LONG := 414
const STATUS_UNSUPPORTED_MEDIA_TYPE := 415
const STATUS_RANGE_NOT_SATISFIABLE := 416
const STATUS_TOO_MANY_REQUESTS := 429
const STATUS_HEADERS_TOO_LARGE := 431
const STATUS_INTERNAL_SERVER_ERROR := 500
const STATUS_NOT_IMPLEMENTED := 501
const STATUS_BAD_GATEWAY := 502
const STATUS_SERVICE_UNAVAILABLE := 503
const STATUS_GATEWAY_TIMEOUT := 504

_REASONS := {100: "Continue", 101: "Switching Protocols", 102: "Processing", 103: "Early Hints", 200: "OK", 201: "Created", 202: "Accepted", 203: "Non-Authoritative Information", 204: "No Content", 205: "Reset Content", 206: "Partial Content", 207: "Multi-Status", 300: "Multiple Choices", 301: "Moved Permanently", 302: "Found", 303: "See Other", 304: "Not Modified", 307: "Temporary Redirect", 308: "Permanent Redirect", 400: "Bad Request", 401: "Unauthorized", 402: "Payment Required", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 406: "Not Acceptable", 407: "Proxy Authentication Required", 408: "Request Timeout", 409: "Conflict", 410: "Gone", 411: "Length Required", 412: "Precondition Failed", 413: "Content Too Large", 414: "URI Too Long", 415: "Unsupported Media Type", 416: "Range Not Satisfiable", 417: "Expectation Failed", 418: "I'm a teapot", 421: "Misdirected Request", 422: "Unprocessable Content", 425: "Too Early", 426: "Upgrade Required", 428: "Precondition Required", 429: "Too Many Requests", 431: "Request Header Fields Too Large", 451: "Unavailable For Legal Reasons", 500: "Internal Server Error", 501: "Not Implemented", 502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout", 505: "HTTP Version Not Supported", 507: "Insufficient Storage", 511: "Network Authentication Required"}

# Raison standard d'un statut HTTP (« Status 299 » pour un code inconnu).
func status_reason(status):
    if contains_key(_REASONS, status):
        return _REASONS[status]
    return "Status " + str(status)

# Classe d'un statut : "informational", "success", "redirect", "client_error", "server_error" ou "invalid".
func status_class(status):
    if status >= 100 and status < 200:
        return "informational"
    if status >= 200 and status < 300:
        return "success"
    if status >= 300 and status < 400:
        return "redirect"
    if status >= 400 and status < 500:
        return "client_error"
    if status >= 500 and status < 600:
        return "server_error"
    return "invalid"

func is_redirect_status(status):
    return status == 301 or status == 302 or status == 303 or status == 307 or status == 308

# Statuts pour lesquels une nouvelle tentative a un sens (surcharge, indisponibilité passagère).
func is_retryable_status(status):
    return status == 408 or status == 425 or status == 429 or status == 500 or status == 502 or status == 503 or status == 504

# Un corps est interdit dans la réponse (1xx, 204, 304, ou à une requête HEAD).
func response_has_body(status, method="GET"):
    if method == "HEAD":
        return false
    return not ((status >= 100 and status < 200) or status == 204 or status == 304)

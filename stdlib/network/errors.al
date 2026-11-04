# ALEX STANDARD LIBRARY — network.errors
#
# Types d'erreurs du réseau et outils pour les classer. Les exceptions ALEX ont un type libre (str) : ce module en
# fixe les noms et leur hiérarchie, pour qu'un appelant puisse écrire `errors.is_a(e, errors.NETWORK)` et
# attraper aussi bien une DnsError qu'une TlsError.
#
# Hiérarchie
#   NetworkError
#   ├── TimeoutError            délai dépassé (connexion, lecture, écriture, opération complète)
#   ├── DnsError                nom introuvable
#   ├── TlsError                poignée de main, certificat, coupure sans close_notify
#   │   └── CertificateError    certificat illisible, expiré, nom non conforme
#   ├── ProxyError              mandataire HTTP CONNECT / SOCKS refusé ou injoignable
#   ├── PoolError               réserve de connexions épuisée ou fermée
#   ├── FirewallError           connexion refusée par une règle de network.firewall
#   └── ProtocolError           réponse mal formée ou refusée par le pair
#       ├── HttpError, WebSocketError, FtpError, SmtpError, ImapError, Pop3Error, GrpcError, XmlRpcFault
#   UrlError, EncodingError, XmlError, HtmlError, ProtobufError, MimeError, EmailError, SecurityError,
#   RetryError, CompressionError : erreurs de données ou d'usage (hors NetworkError).
#
# Les erreurs système gardent leur nom POSIX à la fin du message (« [ECONNREFUSED] ») : errno_of(e) le retrouve.
#
# Exemple
#   use network.errors as ne
#   try:
#       c := tcp.connect("hôte", 80, 2.0)
#   catch e:
#       if ne.is_a(e, ne.NETWORK) and ne.is_transient(e):
#           print("réessayer plus tard :", ne.describe(e))
#       else:
#           raise(e)

from core use len, type
from collections use contains_key, append
use string as _s

const NETWORK := "NetworkError"
const TIMEOUT := "TimeoutError"
const DNS := "DnsError"
const TLS := "TlsError"
const CERTIFICATE := "CertificateError"
const PROXY := "ProxyError"
const POOL := "PoolError"
const FIREWALL := "FirewallError"
const PROTOCOL := "ProtocolError"
const HTTP := "HttpError"
const WEBSOCKET := "WebSocketError"
const FTP := "FtpError"
const SMTP := "SmtpError"
const IMAP := "ImapError"
const POP3 := "Pop3Error"
const GRPC := "GrpcError"
const XMLRPC_FAULT := "XmlRpcFault"
const URL := "UrlError"
const ENCODING := "EncodingError"
const XML := "XmlError"
const HTML := "HtmlError"
const PROTOBUF := "ProtobufError"
const MIME := "MimeError"
const EMAIL := "EmailError"
const SECURITY := "SecurityError"
const RETRY := "RetryError"
const COMPRESSION := "CompressionError"

# Parent direct de chaque type (null : racine).
_PARENT := {"NetworkError": null, "TimeoutError": "NetworkError", "DnsError": "NetworkError", "TlsError": "NetworkError", "CertificateError": "TlsError", "ProxyError": "NetworkError", "PoolError": "NetworkError", "FirewallError": "NetworkError", "ProtocolError": "NetworkError", "HttpError": "ProtocolError", "WebSocketError": "ProtocolError", "FtpError": "ProtocolError", "SmtpError": "ProtocolError", "ImapError": "ProtocolError", "Pop3Error": "ProtocolError", "GrpcError": "ProtocolError", "XmlRpcFault": "ProtocolError", "UrlError": null, "EncodingError": null, "XmlError": null, "HtmlError": null, "ProtobufError": null, "MimeError": null, "EmailError": null, "SecurityError": null, "RetryError": null, "CompressionError": null}

# Erreurs système qui traduisent un incident passager (le même appel peut réussir plus tard).
const TRANSIENT_ERRNO := ["ECONNREFUSED", "ECONNRESET", "ECONNABORTED", "EPIPE", "ETIMEDOUT", "EHOSTUNREACH", "ENETUNREACH", "ENETDOWN", "EAGAIN", "EADDRNOTAVAIL"]

# Lève une erreur réseau ; kind est un des noms ci-dessus (ou tout autre type libre).
func fail(kind, message):
    raise(str(kind), str(message))

func _type_of(e_or_type):
    if type(e_or_type) == "str":
        return e_or_type
    return e_or_type.type

# Parent du type (ou null).
func parent(kind):
    if contains_key(_PARENT, kind):
        return _PARENT[kind]
    return null

# Chaîne des types, du plus précis à la racine : ["HttpError", "ProtocolError", "NetworkError"].
func lineage(e_or_type):
    out := []
    k := _type_of(e_or_type)
    depth := 0
    while k != null and depth < 16:
        append(out, k)
        k = parent(k)
        depth += 1
    return out

# Vrai si l'erreur (ou le type) est `kind` ou en descend. Accepte une liste de types.
func is_a(e_or_type, kind):
    chain := lineage(e_or_type)
    if type(kind) == "list":
        for k in kind:
            for c in chain:
                if c == k:
                    return true
        return false
    for c in chain:
        if c == kind:
            return true
    return false

# Vrai pour toute erreur de la famille NetworkError.
func is_network_error(e):
    return is_a(e, NETWORK)

func is_timeout(e):
    return _type_of(e) == TIMEOUT

# Nom POSIX (« ECONNRESET ») cité à la fin du message d'une erreur système, ou null.
func errno_of(e):
    m := e.message
    if type(m) != "str":
        return null
    i := len(m) - 1
    if i < 0 or m[i] != ']':
        return null
    j := i - 1
    while j >= 0 and m[j] != '[':
        j -= 1
    if j < 0:
        return null
    name := _s.substring(m, j + 1, i)
    if len(name) < 2 or name[0] != 'E':
        return null
    return name

# Vrai si l'erreur est probablement passagère : délai dépassé, connexion refusée ou coupée, réseau injoignable.
# Les erreurs de protocole, de certificat ou d'usage ne le sont pas.
func is_transient(e):
    t := _type_of(e)
    if t == TIMEOUT or t == POOL:
        return true
    if t == NETWORK or t == PROXY:
        n := errno_of(e)
        if n == null:
            return t == NETWORK
        for x in TRANSIENT_ERRNO:
            if x == n:
                return true
        return false
    if t == DNS:
        m := _s.lower(e.message)
        return _s.contains(m, "temporary") or _s.contains(m, "temporaire") or _s.contains(m, "again")
    return false

# « Type : message » sur une ligne.
func describe(e):
    return _type_of(e) + " : " + str(e.message)

# Relance e avec un contexte ajouté devant le message (même type) : « smtp.send : … ».
func wrap(e, context):
    raise(e.type, str(context) + " : " + str(e.message))

# Code numérique de réponse d'un protocole texte en tête de message (« 550 … » -> 550), ou null.
func reply_code(e):
    m := e.message
    if type(m) != "str":
        return null
    i := 0
    n := len(m)
    while i + 2 < n:
        c := m[i]
        if c >= '0' and c <= '9' and m[i + 1] >= '0' and m[i + 1] <= '9' and m[i + 2] >= '0' and m[i + 2] <= '9':
            before := i == 0 or not (m[i - 1] >= '0' and m[i - 1] <= '9')
            after := i + 3 >= n or not (m[i + 3] >= '0' and m[i + 3] <= '9')
            if before and after:
                return (_s.ord(c) - 48) * 100 + (_s.ord(m[i + 1]) - 48) * 10 + (_s.ord(m[i + 2]) - 48)
        i += 1
    return null

# Liste des types connus (documentation, outils).
func known_types():
    out := []
    for k in _PARENT:
        append(out, k)
    return out

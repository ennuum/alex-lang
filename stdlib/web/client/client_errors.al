# ALEX STANDARD LIBRARY — web.client.client_errors
#
# Erreurs du client HTTP (web.client) et leur classification pour les reprises :
#
#   ClientError             usage invalide (URL non http(s), corps incohérent, client fermé)
#   ClientConnectionError   connexion impossible ou perdue (refus, réinitialisation, DNS)          -> réessayable
#   ClientTimeoutError      délai dépassé (connexion, lecture, écriture, total)                     -> réessayable
#   ClientTlsError          échec TLS (certificat refusé, nom différent, poignée de main)           -> non
#   ClientProxyError        mandataire injoignable ou refus du tunnel CONNECT                       -> selon le cas
#   TooManyRedirects        plus de redirections que permis, ou boucle                              -> non
#   ClientResponseError     réponse invalide du serveur (protocole, trop grande, tronquée)          -> non
#   HttpStatusError         (web.http) statut 4xx / 5xx avec raise_for_status()
#
#   use web.client.client_errors as ce
#   try:
#       r := client.get("https://exemple.org/")
#   catch e:
#       if ce.is_retryable(e):
#           ...
#       print(ce.explain(e.type))
#
# Les erreurs réseau de bas niveau (NetworkError, TimeoutError, DnsError, TlsError de network.*) sont traduites
# par wrap() en erreurs du client, avec l'URL concernée dans le message.

from core use len, type
use string as _s

const CLIENT := "ClientError"
const CONNECTION := "ClientConnectionError"
const TIMEOUT := "ClientTimeoutError"
const TLS := "ClientTlsError"
const PROXY := "ClientProxyError"
const TOO_MANY_REDIRECTS := "TooManyRedirects"
const RESPONSE := "ClientResponseError"

func kinds():
    return [CLIENT, CONNECTION, TIMEOUT, TLS, PROXY, TOO_MANY_REDIRECTS, RESPONSE]

func is_client_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func explain(error_type):
    if error_type == CLIENT:
        return "usage invalide du client HTTP"
    if error_type == CONNECTION:
        return "connexion au serveur impossible ou interrompue"
    if error_type == TIMEOUT:
        return "délai dépassé (connexion, lecture, écriture ou total)"
    if error_type == TLS:
        return "échec de la connexion sécurisée (certificat, nom d'hôte, protocole)"
    if error_type == PROXY:
        return "erreur du mandataire (proxy)"
    if error_type == TOO_MANY_REDIRECTS:
        return "trop de redirections, ou boucle de redirections"
    if error_type == RESPONSE:
        return "réponse HTTP invalide, tronquée ou trop grande"
    return "erreur " + str(error_type)

# Vrai pour les erreurs qu'il est raisonnable de réessayer (réseau, délai).
func is_retryable(e):
    t := e.type
    return t == CONNECTION or t == TIMEOUT or t == "NetworkError" or t == "TimeoutError" or t == "DnsError"

func client_error(fn, message):
    raise(CLIENT, fn + " : " + message)

func connection_error(fn, message):
    raise(CONNECTION, fn + " : " + message)

func timeout_error(fn, message):
    raise(TIMEOUT, fn + " : " + message)

func tls_error(fn, message):
    raise(TLS, fn + " : " + message)

func proxy_error(fn, message):
    raise(PROXY, fn + " : " + message)

func too_many_redirects(fn, message):
    raise(TOO_MANY_REDIRECTS, fn + " : " + message)

func response_error(fn, message):
    raise(RESPONSE, fn + " : " + message)

# Traduit une erreur de bas niveau en erreur du client (where : URL ou hôte concerné) ; les erreurs déjà
# traduites et les autres sont relancées telles quelles.
func wrap(e, where):
    t := e.type
    m := str(e.message)
    if t == "TimeoutError":
        raise(TIMEOUT, where + " : " + m)
    if t == "NetworkError" or t == "DnsError":
        raise(CONNECTION, where + " : " + m)
    if t == "TlsError":
        raise(TLS, where + " : " + m)
    if t == "HttpParseError" or t == "HttpLimitError" or t == "HttpVersionError" or t == "HttpHeaderError":
        raise(RESPONSE, where + " : " + m)
    raise(e)

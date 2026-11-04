# ALEX STANDARD LIBRARY — web.http.http_errors
#
# Erreurs du paquet web.http. Chaque erreur de protocole porte, dans son message, le code de statut HTTP qu'un
# serveur devrait renvoyer (status_for) : un serveur traduit ainsi une erreur d'analyse en réponse 4xx/5xx.
#
#   HttpError               usage invalide de l'API (valeur hors limites, objet incohérent)
#   HttpParseError          message mal formé (ligne de départ, en-tête, corps fragmenté)          -> 400
#   HttpHeaderError         nom ou valeur d'en-tête invalide (caractère interdit, CR/LF)             -> 400
#   HttpMethodError         méthode invalide ou non prise en charge                                   -> 501
#   HttpVersionError        version HTTP invalide ou non prise en charge                              -> 505
#   HttpLimitError          limite dépassée (ligne trop longue, en-têtes trop gros, corps trop grand) -> 413/414/431
#   HttpStatusError         code de statut invalide, ou réponse d'erreur (raise_for_status d'un client)
#
#   use web.http.http_errors as he
#   try:
#       msg := parser.parse_request(texte)
#   catch e:
#       if he.is_http_error(e.type):
#           code := he.status_for(e)        # 400, 413, 414, 431, 501, 505...

from core use len, type, to_int
use string as _s

const HTTP := "HttpError"
const PARSE := "HttpParseError"
const HEADER := "HttpHeaderError"
const METHOD := "HttpMethodError"
const VERSION := "HttpVersionError"
const LIMIT := "HttpLimitError"
const STATUS := "HttpStatusError"

func kinds():
    return [HTTP, PARSE, HEADER, METHOD, VERSION, LIMIT, STATUS]

func is_http_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func explain(error_type):
    if error_type == HTTP:
        return "usage invalide de l'API HTTP"
    if error_type == PARSE:
        return "message HTTP mal formé"
    if error_type == HEADER:
        return "nom ou valeur d'en-tête HTTP invalide"
    if error_type == METHOD:
        return "méthode HTTP invalide ou non prise en charge"
    if error_type == VERSION:
        return "version HTTP invalide ou non prise en charge"
    if error_type == LIMIT:
        return "limite de taille HTTP dépassée"
    if error_type == STATUS:
        return "code de statut HTTP invalide ou réponse d'erreur"
    return "erreur " + str(error_type)

# Les messages des erreurs de protocole commencent par « [code] » : status_for le relit.
func _tagged(code, fn, message):
    return "[" + str(code) + "] " + fn + " : " + message

func http_error(fn, message):
    raise(HTTP, fn + " : " + message)

func parse_error(fn, message, status=400):
    raise(PARSE, _tagged(status, fn, message))

func header_error(fn, message, status=400):
    raise(HEADER, _tagged(status, fn, message))

func method_error(fn, message, status=501):
    raise(METHOD, _tagged(status, fn, message))

func version_error(fn, message, status=505):
    raise(VERSION, _tagged(status, fn, message))

# status : 413 (corps), 414 (cible), 431 (en-têtes).
func limit_error(fn, message, status=413):
    raise(LIMIT, _tagged(status, fn, message))

func status_error(fn, message, status=500):
    raise(STATUS, _tagged(status, fn, message))

# Code de statut à renvoyer pour une erreur (objet erreur) : celui du message « [code] … », sinon selon le type,
# sinon 500.
func status_for(e):
    m := e.message
    if type(m) == "str" and _s.starts_with(m, "[") and len(m) >= 5 and m[4] == ']':
        try:
            return to_int(m[1:4])
        catch err:
            return 500
    t := e.type
    if t == PARSE or t == HEADER:
        return 400
    if t == METHOD:
        return 501
    if t == VERSION:
        return 505
    if t == LIMIT:
        return 413
    if t == "TimeoutError":
        return 408
    return 500

# Message sans le préfixe « [code] ».
func message_of(e):
    m := e.message
    if type(m) == "str" and _s.starts_with(m, "[") and len(m) >= 6 and m[4] == ']':
        return m[6:len(m)]
    return str(m)

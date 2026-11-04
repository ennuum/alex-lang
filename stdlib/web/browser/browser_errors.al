# ALEX STANDARD LIBRARY — web.browser.browser_errors
#
# Erreurs du navigateur simulé. Comme dans un vrai navigateur, une promesse rejetée porte une erreur nommée
# (fetch échoue avec TypeError « Failed to fetch », une annulation donne AbortError…) ; ces noms sont les
# types d'erreur ALEX levés par Promise.wait().
#
#   BrowserError          usage invalide de l'API ALEX
#   TypeError             argument invalide, échec réseau de fetch, corps déjà lu
#   AbortError            opération annulée (AbortSignal)
#   TimeoutError          délai dépassé (AbortSignal.timeout, attente de la boucle)
#   QuotaExceededError    stockage plein
#   SecurityError         opération interdite par l'origine (history.push_state vers une autre origine)
#   NotAllowedError       permission refusée ou activation utilisateur requise
#   InvalidStateError     objet dans un état incompatible (lecture déjà en cours…)
#   NotFoundError         ressource absente (URL blob: révoquée…)
#   DataCloneError        valeur non sérialisable
#   SyntaxError           URL ou valeur mal formée
#   EncodingError         données mal encodées (URL data: invalide)
#
#   use web.browser.browser_errors as be
#   be.network_error("fetch", "Failed to fetch")       # lève TypeError
#   be.explain("NotAllowedError")

from core use len, type

const BROWSER := "BrowserError"
const TYPE := "TypeError"
const ABORT := "AbortError"
const TIMEOUT := "TimeoutError"
const QUOTA := "QuotaExceededError"
const SECURITY := "SecurityError"
const NOT_ALLOWED := "NotAllowedError"
const INVALID_STATE := "InvalidStateError"
const NOT_FOUND := "NotFoundError"
const DATA_CLONE := "DataCloneError"
const SYNTAX := "SyntaxError"
const ENCODING := "EncodingError"
const NOT_SUPPORTED := "NotSupportedError"

func kinds():
    return [BROWSER, TYPE, ABORT, TIMEOUT, QUOTA, SECURITY, NOT_ALLOWED, INVALID_STATE, NOT_FOUND, DATA_CLONE, SYNTAX, ENCODING, NOT_SUPPORTED]

func is_browser_error(name):
    for k in kinds():
        if k == name:
            return true
    return false

func explain(name):
    if name == TYPE:
        return "argument invalide ou échec réseau"
    if name == ABORT:
        return "opération annulée"
    if name == TIMEOUT:
        return "délai dépassé"
    if name == QUOTA:
        return "quota de stockage dépassé"
    if name == SECURITY:
        return "opération interdite pour cette origine"
    if name == NOT_ALLOWED:
        return "permission refusée"
    if name == INVALID_STATE:
        return "état invalide"
    if name == NOT_FOUND:
        return "ressource introuvable"
    if name == DATA_CLONE:
        return "valeur non clonable"
    if name == SYNTAX:
        return "syntaxe invalide"
    if name == ENCODING:
        return "données mal encodées"
    return "erreur du navigateur"

# Objet d'erreur porté par une promesse rejetée (name, message), sans lever.
class ErrorValue:
    func init(name, message):
        self.name = name
        self.message = message
        self.type = name

    func __str__():
        return self.name + ": " + self.message

func error_value(name, message):
    return ErrorValue(name, message)

func fail(name, fn, message):
    raise(name, fn + " : " + message)

func browser_error(fn, message):
    raise(BROWSER, fn + " : " + message)

func type_error(fn, message):
    raise(TYPE, fn + " : " + message)

func network_error(fn, message="Failed to fetch"):
    raise(TYPE, fn + " : " + message)

func abort_error(fn, message="opération annulée"):
    raise(ABORT, fn + " : " + message)

func quota_error(fn, message):
    raise(QUOTA, fn + " : " + message)

func security_error(fn, message):
    raise(SECURITY, fn + " : " + message)

func not_allowed(fn, message):
    raise(NOT_ALLOWED, fn + " : " + message)

func invalid_state(fn, message):
    raise(INVALID_STATE, fn + " : " + message)

func not_found(fn, message):
    raise(NOT_FOUND, fn + " : " + message)

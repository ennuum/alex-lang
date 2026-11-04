# ALEX STANDARD LIBRARY — web.server.server_errors
#
# Erreurs du serveur HTTP (web.server), et abort() : la façon, pour un gestionnaire, d'interrompre le traitement
# avec une réponse d'erreur HTTP précise.
#
#   ServerError         usage invalide (serveur déjà démarré, gestionnaire non appelable)
#   ServerConfigError   configuration invalide (port, limites, certificat absent)
#   RouteError          route invalide (motif mal formé, doublon, nom de paramètre répété)
#   HttpAbort           interruption volontaire d'un gestionnaire : abort(404), abort(403, "réservé")
#
#   use web.server.server_errors as se
#   func voir(req):
#       note := trouver(req.route_params["id"])
#       if note == null:
#           se.abort(404, "note introuvable")
#       return note
#
# Une exception non prévue dans un gestionnaire donne une réponse 500 (le détail n'est montré qu'en mode debug)
# et est consignée dans server.errors.

from core use len, type, to_int
use string as _s

const SERVER := "ServerError"
const CONFIG := "ServerConfigError"
const ROUTE := "RouteError"
const ABORT := "HttpAbort"

func kinds():
    return [SERVER, CONFIG, ROUTE, ABORT]

func is_server_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func explain(error_type):
    if error_type == SERVER:
        return "usage invalide du serveur HTTP"
    if error_type == CONFIG:
        return "configuration du serveur invalide"
    if error_type == ROUTE:
        return "route invalide"
    if error_type == ABORT:
        return "traitement interrompu avec un statut HTTP (abort)"
    return "erreur " + str(error_type)

func server_error(fn, message):
    raise(SERVER, fn + " : " + message)

func config_error(fn, message):
    raise(CONFIG, fn + " : " + message)

func route_error(fn, message):
    raise(ROUTE, fn + " : " + message)

# Interrompt le gestionnaire : le serveur répond status (message facultatif dans le corps).
func abort(status, message=null):
    m := str(status)
    if message != null:
        m = m + " " + str(message)
    raise(ABORT, m)

func is_abort(e):
    return e.type == ABORT

# (statut, message ou null) d'une erreur HttpAbort.
func abort_details(e):
    m := str(e.message)
    sp := _s.find(m, " ")
    code_text := m if sp < 0 else m[0:sp]
    status := 500
    try:
        status = to_int(code_text)
    catch err:
        status = 500
    if sp < 0:
        return (status, null)
    return (status, m[sp + 1:len(m)])

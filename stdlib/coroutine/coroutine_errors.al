# ALEX STANDARD LIBRARY — coroutine.coroutine_errors
#
# Erreurs des coroutines :
#   CoroutineError   reprise d'une coroutine terminée ou en cours d'exécution, corps qui n'est pas une
#                    async func, yield hors de sa coroutine
#   CoroutineExit    levée DANS le corps au point de suspension quand on ferme la coroutine (close) ; le corps
#                    peut l'attraper pour nettoyer, mais doit la laisser sortir
#   StopCoroutine    plus aucune valeur (next() d'un générateur asynchrone épuisé)
#   CancelledError   coroutine annulée (cancel)
#
#   use coroutine.coroutine_errors as ce

const COROUTINE := "CoroutineError"
const EXIT := "CoroutineExit"
const STOP := "StopCoroutine"
const CANCELLED := "CancelledError"

func kinds():
    return [COROUTINE, EXIT, STOP, CANCELLED]

func is_coroutine_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func coroutine_error(fn, message):
    raise(COROUTINE, fn + " : " + message)

func explain(error_type):
    if error_type == COROUTINE:
        return "la coroutine n'est pas dans un état qui permet cette opération"
    if error_type == EXIT:
        return "la coroutine a été fermée pendant sa suspension"
    if error_type == STOP:
        return "la coroutine (ou le générateur) n'a plus de valeur à produire"
    if error_type == CANCELLED:
        return "la coroutine a été annulée"
    return "erreur " + str(error_type)

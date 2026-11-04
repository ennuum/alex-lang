# ALEX STANDARD LIBRARY — async.async_errors
#
# Erreurs de la programmation asynchrone :
#   CancelledError      tâche annulée (cancel, jeton d'annulation, groupe dont une tâche a échoué)
#   TimeoutError        délai dépassé (timeout, TaskScope avec échéance)
#   DeadlockError       plus aucune tâche ne peut avancer
#   InvalidStateError   résultat lu trop tôt, groupe déjà attendu, portée fermée
#   AsyncError          await hors d'une async func (à l'analyse)
#   TaskGroupError      plusieurs tâches d'un groupe ont échoué (async.task_group, mode collect)
#
#   use async.async_errors as ae
#   catch e:
#       if ae.is_cancellation(e): ...

const CANCELLED := "CancelledError"
const TIMEOUT := "TimeoutError"
const DEADLOCK := "DeadlockError"
const INVALID_STATE := "InvalidStateError"
const ASYNC := "AsyncError"
const GROUP := "TaskGroupError"

func kinds():
    return [CANCELLED, TIMEOUT, DEADLOCK, INVALID_STATE, ASYNC, GROUP]

func is_async_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func is_cancellation(e):
    return e.type == CANCELLED

func is_timeout(e):
    return e.type == TIMEOUT

func explain(error_type):
    if error_type == CANCELLED:
        return "la tâche a été annulée (directement, par un jeton, ou parce qu'une tâche sœur a échoué)"
    if error_type == TIMEOUT:
        return "l'opération asynchrone n'a pas abouti dans le délai"
    if error_type == DEADLOCK:
        return "interblocage : toutes les tâches attendent quelque chose qui n'arrivera pas"
    if error_type == INVALID_STATE:
        return "opération impossible dans l'état actuel (résultat pas encore prêt, groupe fermé)"
    if error_type == ASYNC:
        return "await utilisé hors d'une async func"
    if error_type == GROUP:
        return "plusieurs tâches du groupe ont échoué (détail dans le message)"
    return "erreur " + str(error_type)

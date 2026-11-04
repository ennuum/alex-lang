# ALEX STANDARD LIBRARY — future.future_errors
#
# Erreurs des futurs et promesses :
#   InvalidStateError   résultat lu avant la fin, promesse complétée deux fois (strict), futur qui s'attend
#   CancelledError      futur annulé
#   TimeoutError        délai dépassé (with_timeout, ThreadPromise.wait)
#   DeadlockError       plus aucune tâche ne peut avancer alors que le programme attend
#   BrokenPromiseError  promesse abandonnée sans jamais être complétée (future.exception_result)
#   + toute erreur levée par la tâche, relancée par await avec son type d'origine
#
#   use future.future_errors as fe
#   try:
#       v := await f
#   catch e:
#       if fe.is_cancellation(e): ...
#       print(fe.explain(e.type))

const INVALID_STATE := "InvalidStateError"
const CANCELLED := "CancelledError"
const TIMEOUT := "TimeoutError"
const DEADLOCK := "DeadlockError"
const BROKEN_PROMISE := "BrokenPromiseError"

func kinds():
    return [INVALID_STATE, CANCELLED, TIMEOUT, DEADLOCK, BROKEN_PROMISE]

func is_future_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func is_cancellation(e):
    return e.type == CANCELLED

func is_timeout(e):
    return e.type == TIMEOUT

func explain(error_type):
    if error_type == INVALID_STATE:
        return "le futur n'est pas dans l'état voulu (pas encore terminé, ou déjà complété)"
    if error_type == CANCELLED:
        return "le futur a été annulé"
    if error_type == TIMEOUT:
        return "le futur n'a pas abouti dans le délai"
    if error_type == DEADLOCK:
        return "interblocage : aucune tâche ne peut avancer (une promesse ne sera jamais complétée ?)"
    if error_type == BROKEN_PROMISE:
        return "la promesse a été abandonnée sans résultat"
    return "erreur " + str(error_type)

func invalid_state(fn, message):
    raise(INVALID_STATE, fn + " : " + message)

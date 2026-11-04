# ALEX STANDARD LIBRARY — thread.thread_errors
#
# Erreurs des fils d'exécution :
#   ThreadError          démarrage impossible (trop de fils, spawn depuis le code de haut niveau d'un module
#                        importé dans un fil), fil démarré deux fois, opération avant start
#   TimeoutError         join / receive / résultat non obtenu dans le délai
#   ChannelClosedError   envoi / réception sur un canal fermé
#   PoolShutdownError    soumission à un ThreadPool arrêté
#   ThreadPriorityError  priorité refusée ou hors bornes (thread.thread_priority)
#   (une erreur levée DANS un fil est relancée par join avec son type d'origine)
#
#   use thread.thread_errors as te
#   try:
#       t.join(1.0)
#   catch e:
#       print(te.explain(e.type))

const THREAD := "ThreadError"
const TIMEOUT := "TimeoutError"
const CHANNEL_CLOSED := "ChannelClosedError"
const POOL_SHUTDOWN := "PoolShutdownError"
const PRIORITY := "ThreadPriorityError"

func kinds():
    return [THREAD, TIMEOUT, CHANNEL_CLOSED, POOL_SHUTDOWN, PRIORITY]

func is_thread_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func explain(error_type):
    if error_type == THREAD:
        return "fil impossible à démarrer ou à piloter (protéger le programme principal par `if thread.is_main():`)"
    if error_type == TIMEOUT:
        return "le fil n'a pas répondu dans le délai"
    if error_type == CHANNEL_CLOSED:
        return "le canal a été fermé par l'autre bout"
    if error_type == POOL_SHUTDOWN:
        return "la réserve de fils est arrêtée : plus de nouvelles tâches"
    if error_type == PRIORITY:
        return "priorité hors de -20..19, ou hausse refusée sans droits (CAP_SYS_NICE)"
    return "erreur " + str(error_type)

func thread_error(fn, message):
    raise(THREAD, fn + " : " + message)

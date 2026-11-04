# ALEX STANDARD LIBRARY — synchronization.synchronization_errors
#
# Erreurs des primitives de synchronisation entre fils :
#   SyncError               usage invalide (compter en dessous de zéro, ajouter à un CountdownEvent déjà levé)
#   BrokenBarrierError      barrière cassée (un participant est parti, délai, abort)
#   TimeoutError            délai dépassé (wait, acquire, run)
#   LockError               verrou rendu par un fil qui ne le détient pas, interblocage certain
#   SemaphoreOverflowError  release au-delà de la borne d'un BoundedSemaphore
#
#   use synchronization.synchronization_errors as se
#   try:
#       barriere.wait(1.0)
#   catch e:
#       if se.is_timeout(e): ...
#       print(se.explain(e.type))

const SYNC := "SyncError"
const BROKEN_BARRIER := "BrokenBarrierError"
const TIMEOUT := "TimeoutError"
const LOCK := "LockError"
const SEMAPHORE_OVERFLOW := "SemaphoreOverflowError"

func kinds():
    return [SYNC, BROKEN_BARRIER, TIMEOUT, LOCK, SEMAPHORE_OVERFLOW]

func is_sync_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func is_timeout(e):
    return e.type == TIMEOUT

func explain(error_type):
    if error_type == SYNC:
        return "opération de synchronisation incohérente avec l'état de l'objet"
    if error_type == BROKEN_BARRIER:
        return "la barrière est cassée : un participant a abandonné ou dépassé son délai (reset() pour la réarmer)"
    if error_type == TIMEOUT:
        return "délai dépassé avant que la condition ne soit remplie"
    if error_type == LOCK:
        return "verrou rendu par un fil qui ne le détient pas, ou repris par son propriétaire (non récursif)"
    if error_type == SEMAPHORE_OVERFLOW:
        return "release au-delà de la valeur maximale du sémaphore borné"
    return "erreur " + str(error_type)

func sync_error(fn, message):
    raise(SYNC, fn + " : " + message)

func timeout(fn, seconds):
    raise(TIMEOUT, fn + " : délai de " + str(seconds) + " s dépassé")

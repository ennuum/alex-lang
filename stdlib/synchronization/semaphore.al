# ALEX STANDARD LIBRARY — synchronization.semaphore
#
# Sémaphores entre FILS d'exécution : un compteur de jetons ; acquire en prend (attend s'il n'y en a pas assez),
# release en rend. Limite le nombre de fils qui utilisent une ressource en même temps.
#
#   use synchronization.semaphore as sem
#   connexions := sem.Semaphore(4)                  # 4 fils au plus
#   connexions.with_permit(() => interroger_base())
#   b := sem.BoundedSemaphore(2)                    # rendre plus de jetons qu'au départ : ValueError
#   if s.acquire(1, 0.5): ...                       # 1 jeton, 0,5 s d'attente au plus
#   await s.acquire_async()                          # depuis une tâche async
#
# Entre processus : ipc.semaphore. Entre tâches async d'un même fil : concurrency.semaphore.
#
# Erreurs : ValueError (BoundedSemaphore dépassé), TimeoutError (with_permit), ArgumentError, TypeError.

from core use type
use _native_sync as _s
use mutex._common as _c

class Semaphore:
    func init(value=1, id=null, bound=0):
        if id != null:
            _c.check_kind("Semaphore", id, "semaphore")
            self.id = id
        else:
            if type(value) != "int" or value < 0:
                raise("ArgumentError", "Semaphore : nombre de jetons >= 0 attendu")
            self.id = _s.sem_new(value, bound)

    # Prend n jetons ; false si timeout secondes passent avant.
    func acquire(n=1, timeout=null):
        _c.need_timeout("Semaphore.acquire", timeout)
        return _s.sem_acquire(self.id, n, timeout) == 1

    func try_acquire(n=1):
        return self.acquire(n, 0)

    func release(n=1):
        if _s.sem_release(self.id, n) != 0:
            raise("ValueError", "Semaphore.release : plus de jetons que la borne (" + str(_s.sem_value(self.id)[1]) + ")")

    func value():
        return _s.sem_value(self.id)[0]

    func waiting():
        return _s.sem_value(self.id)[2]

    func with_permit(fn, timeout=null):
        if not self.acquire(1, timeout):
            raise("TimeoutError", "Semaphore.with_permit : aucun jeton dans le délai")
        try:
            return fn()
        finally:
            self.release(1)

    # Futur (vrai si obtenu) pour une tâche async, sans immobiliser le fil.
    func acquire_async(n=1, timeout=null):
        return _c.poll_acquire(() => self.try_acquire(n), timeout)

    func destroy():
        _s.destroy(self.id)

class BoundedSemaphore extends Semaphore:
    func init(value=1, id=null):
        super.init(value, id, value)

func attach(id):
    return Semaphore(1, id)

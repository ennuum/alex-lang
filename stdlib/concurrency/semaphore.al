# ALEX STANDARD LIBRARY — concurrency.semaphore
#
# Sémaphores entre tâches async : limiter le nombre de tâches qui font quelque chose en même temps (connexions
# ouvertes, téléchargements...).
#
#   sem := Semaphore(3)
#   async func telecharger(url):
#       await sem.acquire()
#       try:
#           return await recuperer(url)
#       finally:
#           sem.release()
#   # ou : await semaphore.with_permit(sem, () => recuperer(url))
#
# Équitable (ordre des demandes) ; une tâche annulée pendant son attente ne consomme pas de jeton.
# BoundedSemaphore refuse de rendre plus de jetons qu'il n'en a été pris (erreur de programmation fréquente).
#
# Erreurs : ValueError (valeur initiale négative), LockError (BoundedSemaphore : release de trop).

from core use len, type
use asyncio
use concurrency._waitq as _q

class Semaphore:
    func init(value=1):
        if type(value) != "int":
            raise("TypeError", "Semaphore : valeur initiale int attendue")
        if value < 0:
            raise("ValueError", "Semaphore : valeur initiale négative (" + str(value) + ")")
        self._value = value
        self._waiters = _q.WaitQueue()

    # Futur terminé quand un jeton est obtenu : `await sem.acquire()`.
    func acquire():
        if self._value > 0:
            self._value = self._value - 1
            return _q.ready(true)
        return self._waiters.add()

    # Prend un jeton s'il y en a un, sans attendre ; renvoie true si c'est le cas.
    func try_acquire():
        if self._value > 0:
            self._value = self._value - 1
            return true
        return false

    # Rend un jeton : il passe directement à la plus ancienne tâche en attente, s'il y en a une.
    func release():
        self._check_release()
        p := self._waiters.pop_alive()
        if p != null:
            asyncio.resolve(p, true)
            return
        self._value = self._value + 1

    func _check_release():
        return

    # Jetons disponibles tout de suite.
    func value():
        return self._value

    func waiting():
        return self._waiters.count()

class BoundedSemaphore extends Semaphore:
    func init(value=1):
        super.init(value)
        self._max = value

    func _check_release():
        if self._value >= self._max and self._waiters.count() == 0:
            raise("LockError", "BoundedSemaphore.release : plus de jetons rendus que pris (maximum " + str(self._max) + ")")

# Exécute f() avec un jeton (attend f() si c'est une tâche), le rend même en cas d'erreur.
async func with_permit(sem, f):
    await sem.acquire()
    try:
        r := f()
        if asyncio.is_future(r):
            r = await r
        return r
    finally:
        sem.release()

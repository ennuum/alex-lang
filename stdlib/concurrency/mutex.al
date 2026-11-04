# ALEX STANDARD LIBRARY — concurrency.mutex
#
# Exclusion mutuelle entre tâches async (Mutex) et attente d'une condition sous verrou (Condition).
#
# Les tâches Alex sont coopératives (docs/ASYNC.md) : entre deux `await`, une tâche n'est jamais interrompue.
# Un verrou n'est donc utile que pour une section critique QUI CONTIENT un `await` (lire, attendre, écrire) :
# sans lui, une autre tâche pourrait s'intercaler pendant l'attente.
#
#   m := Mutex()
#   async func retirer(compte, montant):
#       await m.lock()
#       try:
#           solde := await lire_solde(compte)
#           await ecrire_solde(compte, solde - montant)
#       finally:
#           m.unlock()
#   # ou : await mutex.with_lock(m, () => ...)
#
# Équitable : les tâches obtiennent le verrou dans l'ordre de leur demande. Une tâche annulée pendant qu'elle
# attend le verrou ne le reçoit jamais (il passe à la suivante). Comme asyncio.Lock de Python, le verrou n'a pas
# de propriétaire : unlock() par une autre tâche que celle qui l'a pris est permis.
#
# Erreurs : LockError (unlock d'un verrou libre, wait/notify d'une Condition dont le verrou est libre).

from core use len
use asyncio
use concurrency._waitq as _q

class Mutex:
    func init():
        self._locked = false
        self._waiters = _q.WaitQueue()

    # Futur terminé quand le verrou est obtenu (tout de suite s'il est libre) : `await m.lock()`.
    func lock():
        if not self._locked:
            self._locked = true
            return _q.ready(true)
        return self._waiters.add()

    # Prend le verrou s'il est libre ; renvoie true si c'est le cas, false sinon (sans attendre).
    func try_lock():
        if self._locked:
            return false
        self._locked = true
        return true

    # Rend le verrou ; la plus ancienne tâche en attente (encore vivante) le reçoit directement.
    func unlock():
        if not self._locked:
            raise("LockError", "Mutex.unlock : le verrou est déjà libre")
        p := self._waiters.pop_alive()
        if p != null:
            asyncio.resolve(p, true) # le verrou reste pris, par elle
            return
        self._locked = false

    func locked():
        return self._locked

    # Nombre de tâches en attente du verrou.
    func waiting():
        return self._waiters.count()

# Exécute f() verrou pris (attend f() si c'est une tâche), rend le verrou même en cas d'erreur ; renvoie son
# résultat.
async func with_lock(m, f):
    await m.lock()
    try:
        r := f()
        if asyncio.is_future(r):
            r = await r
        return r
    finally:
        m.unlock()

class Condition:
    # Condition attachée à un Mutex (un nouveau si mutex est null).
    func init(mutex=null):
        if mutex == null:
            mutex = Mutex()
        self.mutex = mutex
        self._waiters = _q.WaitQueue()

    func lock():
        return self.mutex.lock()

    func unlock():
        self.mutex.unlock()

    # Verrou pris : le rend, attend notify(), puis le reprend avant de revenir.
    async func wait():
        if not self.mutex.locked():
            raise("LockError", "Condition.wait : le verrou doit être pris")
        p := self._waiters.add()
        self.mutex.unlock()
        try:
            await p
        finally:
            await self.mutex.lock()
        return true

    # Attend que predicate() soit vrai (verrou pris pendant chaque évaluation).
    async func wait_for(predicate):
        while not predicate():
            await self.wait()
        return true

    # Réveille au plus n tâches en attente ; renvoie leur nombre.
    func notify(n=1):
        if not self.mutex.locked():
            raise("LockError", "Condition.notify : le verrou doit être pris")
        k := 0
        while k < n:
            p := self._waiters.pop_alive()
            if p == null:
                return k
            asyncio.resolve(p, true)
            k = k + 1
        return k

    func notify_all():
        if not self.mutex.locked():
            raise("LockError", "Condition.notify_all : le verrou doit être pris")
        return self._waiters.resolve_all(true)

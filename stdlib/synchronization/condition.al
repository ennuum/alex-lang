# ALEX STANDARD LIBRARY — synchronization.condition
#
# Variables de condition entre FILS : attendre, verrou pris, qu'un autre fil signale un changement d'état.
# Une Condition est liée à un mutex.Mutex (créé si absent) : wait() le rend pendant l'attente et le reprend avant
# de revenir.
#
#   use synchronization.condition as cond
#   c := cond.Condition()
#   # consommateur                           # producteur
#   c.lock()                                 c.lock()
#   c.wait_for(() => file_non_vide(), 5.0)   ajouter(x)
#   x := retirer()                           c.notify()
#   c.unlock()                               c.unlock()
#
# Les réveils sans raison sont possibles en théorie : toujours revérifier la condition (wait_for le fait).
# Passage à un fil : (c.id, c.mutex.id), puis cond.attach(cid, mid) dans le fil.
#
# Erreurs : LockError (wait / notify sans détenir le verrou), TypeError, ArgumentError.

from core use type
use _native_sync as _s
use mutex._common as _c
use mutex as _mutex
use os as _os

class Condition:
    func init(mutex=null, id=null):
        if mutex == null:
            mutex = _mutex.Mutex()
        self.mutex = mutex
        if id != null:
            _c.check_kind("Condition", id, "condition")
            self.id = id
        else:
            self.id = _s.cond_new(mutex.id)

    func lock(timeout=null):
        return self.mutex.lock(timeout)

    func unlock():
        self.mutex.unlock()

    # Verrou pris : le rend, attend notify() (au plus timeout secondes), puis le reprend. false : délai écoulé.
    func wait(timeout=null):
        _c.need_timeout("Condition.wait", timeout)
        r := _s.cond_wait(self.id, timeout)
        if r == -1:
            raise("LockError", "Condition.wait : le verrou doit être pris par ce fil")
        return r == 1

    # Attend que predicate() soit vrai (évalué verrou pris) ; false si le délai TOTAL expire avant.
    func wait_for(predicate, timeout=null):
        deadline := null
        if timeout != null:
            deadline = _os.monotonic_time() + timeout
        while not predicate():
            left := null
            if deadline != null:
                left = deadline - _os.monotonic_time()
                if left <= 0:
                    return predicate()
            self.wait(left)
        return true

    # Réveille au plus n fils qui attendent ; renvoie leur nombre.
    func notify(n=1):
        r := _s.cond_notify(self.id, n)
        if r < 0:
            raise("LockError", "Condition.notify : le verrou doit être pris par ce fil")
        return r

    func notify_all():
        r := _s.cond_notify(self.id, -1)
        if r < 0:
            raise("LockError", "Condition.notify_all : le verrou doit être pris par ce fil")
        return r

    # fn() verrou pris.
    func run(fn, timeout=null):
        return self.mutex.run(fn, timeout)

    func destroy():
        _s.destroy(self.id)

# Condition existante (créée dans un autre fil) : identifiants de la condition et de son mutex.
func attach(id, mutex_id):
    return Condition(_mutex.attach(mutex_id), id)

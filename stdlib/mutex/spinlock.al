# ALEX STANDARD LIBRARY — mutex.spinlock
#
# Verrou TOURNANT entre fils : en attente, le fil réessaie en boucle (instruction atomique) au lieu de dormir,
# puis cède le processeur toutes les 64 tentatives. Pour des sections TRÈS courtes, sinon Mutex est préférable.
# Sans OS (--freestanding), hw.spin_lock / hw.spin_unlock sont l'équivalent sur un mot de la mémoire.
#
#   use mutex.spinlock as sl
#   s := sl.SpinLock()
#   s.run(() => compteur_global_incrementer())
#
# Erreurs : LockError (unlock par un autre fil, reprise par le détenteur), TimeoutError (run), TypeError.

use _native_sync as _s
use mutex._common as _c

class SpinLock:
    func init(id=null):
        if id != null:
            _c.check_kind("SpinLock", id, "spinlock")
            self.id = id
        else:
            self.id = _s.spin_new()

    func lock(timeout=null):
        _c.need_timeout("SpinLock.lock", timeout)
        r := _s.spin_lock(self.id, timeout)
        if r == -1:
            raise("LockError", "SpinLock.lock : ce fil détient déjà le verrou")
        return r == 1

    func try_lock():
        return self.lock(0)

    func unlock():
        if _s.spin_unlock(self.id) != 0:
            raise("LockError", "SpinLock.unlock : ce fil ne détient pas le verrou")

    func locked():
        return _s.spin_info(self.id) != 0

    func run(fn, timeout=null):
        if not self.lock(timeout):
            raise("TimeoutError", "SpinLock.run : verrou non obtenu dans le délai")
        try:
            return fn()
        finally:
            self.unlock()

    func destroy():
        _s.destroy(self.id)

func attach(id):
    return SpinLock(id)

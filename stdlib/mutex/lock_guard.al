# ALEX STANDARD LIBRARY — mutex.lock_guard
#
# Gardes de verrou (RAII, comme std::lock_guard / unique_lock / scoped_lock / shared_lock) : le verrou est
# pris à la construction et rendu par release() — ou automatiquement avec `with` — exactement une fois.
#
#   use mutex.lock_guard as lg
#   with lg.LockGuard(m) as g:                 # pris ici, rendu à la sortie du bloc (même sur erreur)
#       section_critique()
#   u := lg.UniqueLock(m, true)                # différé : pas encore pris
#   if u.try_lock_for(0.5):
#       ...
#       u.unlock()                             # peut être rendu puis repris
#   with lg.ScopedLock([a, b]) as s:           # plusieurs verrous sans interblocage
#       transferer()
#   with lg.SharedLock(rw) as r:               # lecture partagée d'un ReadWriteLock
#       lire()
#   lg.guarded(m, fn)                          # fn() sous le verrou
#
# Erreurs : LockError (double release, unlock d'un verrou non pris), TimeoutError, TypeError.

from core use type
use mutex.try_lock as _tl

class LockGuard:
    func init(lock, timeout=null):
        self.lock = lock
        self._held = false
        if not _tl.try_lock_for(lock, timeout):
            raise("TimeoutError", "LockGuard : verrou non obtenu dans le délai")
        self._held = true

    func owns_lock():
        return self._held

    # Rend le verrou (idempotent).
    func release():
        if self._held:
            self._held = false
            _tl.unlock(self.lock)

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.release()

class UniqueLock:
    func init(lock, defer=false, timeout=null):
        self.lock = lock
        self._held = false
        if not defer:
            if not _tl.try_lock_for(lock, timeout):
                raise("TimeoutError", "UniqueLock : verrou non obtenu dans le délai")
            self._held = true

    func lock_now(timeout=null):
        if self._held:
            raise("LockError", "UniqueLock.lock : verrou déjà détenu par cette garde")
        if not _tl.try_lock_for(self.lock, timeout):
            raise("TimeoutError", "UniqueLock.lock : verrou non obtenu dans le délai")
        self._held = true

    func try_lock():
        if self._held:
            raise("LockError", "UniqueLock.try_lock : verrou déjà détenu par cette garde")
        self._held = _tl.try_lock(self.lock)
        return self._held

    func try_lock_for(timeout):
        if self._held:
            raise("LockError", "UniqueLock.try_lock_for : verrou déjà détenu par cette garde")
        self._held = _tl.try_lock_for(self.lock, timeout)
        return self._held

    func unlock():
        if not self._held:
            raise("LockError", "UniqueLock.unlock : la garde ne détient pas le verrou")
        self._held = false
        _tl.unlock(self.lock)

    func owns_lock():
        return self._held

    # Abandonne la garde sans rendre le verrou ; renvoie le verrou (à rendre soi-même).
    func detach():
        self._held = false
        return self.lock

    func __enter__():
        if not self._held:
            self.lock_now()
        return self

    func __exit__(a, b, c):
        if self._held:
            self.unlock()

class ScopedLock:
    func init(locks, timeout=null):
        self.locks = locks
        _tl.lock_all(locks, timeout)
        self._held = true

    func release():
        if self._held:
            self._held = false
            _tl.unlock_all(self.locks)

    func owns_lock():
        return self._held

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.release()

class SharedLock:
    func init(rw_lock, timeout=null):
        self.lock = rw_lock
        self._held = false
        if not rw_lock.read_lock(timeout):
            raise("TimeoutError", "SharedLock : lecture non obtenue dans le délai")
        self._held = true

    func release():
        if self._held:
            self._held = false
            self.lock.read_unlock()

    func owns_lock():
        return self._held

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.release()

# fn() sous le verrou, rendu ensuite (même sur erreur).
func guarded(lock, fn, timeout=null):
    g := LockGuard(lock, timeout)
    try:
        return fn()
    finally:
        g.release()

func shared(rw_lock, fn, timeout=null):
    g := SharedLock(rw_lock, timeout)
    try:
        return fn()
    finally:
        g.release()

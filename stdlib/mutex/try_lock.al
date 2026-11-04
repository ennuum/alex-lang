# ALEX STANDARD LIBRARY — mutex.try_lock
#
# Prise de verrous SANS blocage indéfini, sur tous les verrous du paquet (Mutex, RecursiveMutex, SpinLock,
# ReadWriteLock en écriture) :
#   try_lock(l)                 essai immédiat
#   try_lock_for(l, s)          essai pendant au plus s secondes
#   try_lock_all(locks)         tout ou rien (std::try_lock) : -1 si tous pris, sinon la position de l'échec
#                               (et aucun verrou n'est gardé)
#   lock_all(locks, timeout)    prend TOUS les verrous sans interblocage (algorithme de std::lock : essai,
#                               recul, nouvel essai en commençant par celui qui a résisté)
#   with_try_lock(l, fn, default)   fn() si le verrou est libre, sinon default sans attendre
#
#   use mutex.try_lock as tl
#   if tl.try_lock(m):
#       try:
#           travail()
#       finally:
#           m.unlock()
#   i := tl.try_lock_all([a, b, c])        # -1 : les trois sont pris
#   tl.lock_all([compte_a, compte_b], 2.0) # TimeoutError après 2 s
#   n := tl.with_try_lock(cache_lock, rafraichir, "occupé")
#
# Erreurs : TimeoutError (lock_all), TypeError (objet qui n'est pas un verrou), LockError.

from core use len, type
from collections use append
use os as _os
use _native_reflect as _r

func _is_rw(l):
    return _r.method(l, "try_write_lock") != null

func _check(l):
    if not _r.is_instance(l) or (_r.method(l, "try_lock") == null and _r.method(l, "try_write_lock") == null):
        raise("TypeError", "try_lock : verrou attendu (objet doté de try_lock / unlock)")

# Essai immédiat ; false si le verrou est pris (y compris par ce fil, pour un verrou non récursif).
func try_lock(l):
    _check(l)
    try:
        if _is_rw(l):
            return l.try_write_lock()
        return l.try_lock()
    catch LockError:
        return false

func unlock(l):
    if _is_rw(l):
        l.write_unlock()
    else:
        l.unlock()

func try_lock_for(l, timeout):
    _check(l)
    try:
        if _is_rw(l):
            return l.write_lock(timeout)
        return l.lock(timeout)
    catch LockError:
        return false

# -1 si tous les verrous ont été pris ; sinon position du premier refus (ceux déjà pris sont rendus).
func try_lock_all(locks):
    taken := []
    i := 0
    while i < len(locks):
        if not try_lock(locks[i]):
            k := len(taken) - 1
            while k >= 0:
                unlock(taken[k])
                k -= 1
            return i
        append(taken, locks[i])
        i += 1
    return -1

# Prend tous les verrous sans interblocage ; TimeoutError après timeout secondes (null : sans limite).
func lock_all(locks, timeout=null, backoff=0.0005):
    n := len(locks)
    if n == 0:
        return true
    t0 := _os.monotonic_time()
    first := 0
    pause := backoff
    while true:
        # Le verrou qui a résisté est pris en attente bloquante bornée, les autres par essai.
        if not try_lock_for(locks[first], 0.05):
            if timeout != null and _os.monotonic_time() - t0 >= timeout:
                raise("TimeoutError", "lock_all : verrous non obtenus après " + str(timeout) + " s")
            continue
        failed := -1
        k := 1
        while k < n:
            j := (first + k) % n
            if not try_lock(locks[j]):
                failed = j
                break
            k += 1
        if failed < 0:
            return true
        # Recul : rendre ce qui a été pris, puis recommencer par le verrou qui a résisté.
        m := 0
        while m < k:
            unlock(locks[(first + m) % n])
            m += 1
        first = failed
        if timeout != null and _os.monotonic_time() - t0 >= timeout:
            raise("TimeoutError", "lock_all : verrous non obtenus après " + str(timeout) + " s")
        _os.sleep(pause)
        if pause < 0.01:
            pause = pause * 2

func unlock_all(locks):
    k := len(locks) - 1
    while k >= 0:
        unlock(locks[k])
        k -= 1

# fn() si le verrou est libre (rendu ensuite), sinon default — sans jamais attendre.
func with_try_lock(l, fn, default=null):
    if not try_lock(l):
        return default
    try:
        return fn()
    finally:
        unlock(l)

# fn() avec tous les verrous (lock_all), rendus ensuite.
func with_locks(locks, fn, timeout=null):
    lock_all(locks, timeout)
    try:
        return fn()
    finally:
        unlock_all(locks)

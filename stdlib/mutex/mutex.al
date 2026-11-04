# ALEX STANDARD LIBRARY — mutex
#
# Verrous d'exclusion mutuelle entre FILS d'exécution réels (thread, concurrency.thread) : un seul fil à la fois
# exécute la section protégée. Le verrou a un PROPRIÉTAIRE (le fil qui l'a pris) : seul lui peut le rendre.
#
#   use mutex
#   m := mutex.Mutex()
#   thread.spawn(travail, [m.id])              # dans le fil : m := mutex.attach(id)
#   m.lock()
#   try:
#       section_critique()
#   finally:
#       m.unlock()
#   m.run(section_critique)                    # la même chose
#   if m.lock(0.5): ...                        # au plus 0,5 s d'attente (false sinon)
#   await m.lock_async()                       # depuis une tâche async : n'arrête pas les autres tâches
#
# Variantes : mutex.recursive_mutex (reprenable par son propriétaire), mutex.read_write_lock (lecteurs multiples
# ou un écrivain), mutex.spinlock (attente active, sections très courtes). Pour des tâches async d'un même fil,
# mutex.async_mutex() renvoie le verrou coopératif de concurrency.mutex.
#
# Erreurs : LockError (rendre un verrou non détenu ; reprendre un Mutex non récursif qu'on détient déjà :
# interblocage certain), TimeoutError (run avec délai), TypeError, ArgumentError.

from core use type, len
from collections use append
use _native_sync as _s
use concurrency.mutex as _amutex
use mutex._common as _c

class Mutex:
    func init(id=null):
        if id != null:
            _c.check_kind("Mutex", id, "mutex")
            self.id = id
        else:
            self.id = _s.mutex_new(false)
        self.kind = "Mutex"

    # Prend le verrou ; renvoie false si timeout secondes passent avant (null : attendre sans limite).
    func lock(timeout=null):
        _c.need_timeout(self.kind + ".lock", timeout)
        r := _s.mutex_lock(self.id, timeout)
        if r == -1:
            raise("LockError", self.kind + ".lock : ce fil détient déjà le verrou (interblocage)")
        return r == 1

    func try_lock():
        return self.lock(0)

    # Rend le verrou (LockError si ce fil ne le détient pas).
    func unlock():
        if _s.mutex_unlock(self.id) != 0:
            raise("LockError", self.kind + ".unlock : ce fil ne détient pas le verrou")

    func locked():
        return _s.mutex_info(self.id)[0]

    # Vrai si le fil courant détient le verrou.
    func owned():
        return _s.mutex_info(self.id)[1] == _s.token()

    # Nombre de fils en attente du verrou.
    func waiting():
        return _s.mutex_info(self.id)[3]

    # Exécute fn() verrou pris, le rend même en cas d'erreur ; renvoie le résultat. TimeoutError si le verrou
    # n'est pas obtenu dans le délai.
    func run(fn, timeout=null):
        if not self.lock(timeout):
            raise("TimeoutError", self.kind + ".run : verrou non obtenu dans le délai")
        try:
            return fn()
        finally:
            self.unlock()

    # Depuis une tâche async : futur (vrai si obtenu) qui n'immobilise pas le fil pendant l'attente.
    func lock_async(timeout=null):
        return _c.poll_acquire(() => self.try_lock(), timeout)

    func destroy():
        _s.destroy(self.id)

func attach(id):
    return Mutex(id)

# Verrou coopératif pour les tâches async d'un même fil (concurrency.mutex.Mutex : lock() est un futur).
func async_mutex():
    return _amutex.Mutex()

# Prend tous les verrous dans un ordre global fixe (identifiants croissants) pour éviter les interblocages entre
# fils qui prennent les mêmes verrous ; fn() puis rend tout. Renvoie le résultat de fn.
func with_all(locks, fn):
    ordered := _sorted_by_id(locks)
    taken := []
    try:
        for l in ordered:
            l.lock()
            append(taken, l)
        return fn()
    finally:
        k := len(taken) - 1
        while k >= 0:
            taken[k].unlock()
            k -= 1

func _sorted_by_id(locks):
    out := [l for l in locks]
    i := 1
    while i < len(out):
        v := out[i]
        j := i - 1
        while j >= 0 and out[j].id > v.id:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = v
        i += 1
    return out

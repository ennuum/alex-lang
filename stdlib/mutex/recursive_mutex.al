# ALEX STANDARD LIBRARY — mutex.recursive_mutex
#
# Verrou RÉENTRANT entre fils : le fil qui le détient peut le reprendre (appels imbriqués, récursion) ; il est
# libéré quand chaque lock() a été suivi de son unlock().
#
#   use mutex.recursive_mutex as rm
#   m := rm.RecursiveMutex()
#   func ajouter(x):
#       m.run(() => _ajouter_sans_verrou(x))
#   func ajouter_tout(xs):
#       m.lock()                         # reprise par le même fil : pas d'interblocage
#       for x in xs:
#           ajouter(x)
#       m.unlock()
#
# Erreurs : LockError (unlock par un autre fil ou verrou libre), TimeoutError (run), TypeError.

use _native_sync as _s
use mutex._common as _c
from mutex use Mutex

class RecursiveMutex extends Mutex:
    func init(id=null):
        if id != null:
            _c.check_kind("RecursiveMutex", id, "mutex")
            self.id = id
        else:
            self.id = _s.mutex_new(true)
        self.kind = "RecursiveMutex"

    # Nombre de prises en cours par le propriétaire (0 : libre).
    func level():
        return _s.mutex_info(self.id)[2]

func attach(id):
    return RecursiveMutex(id)

# ALEX STANDARD LIBRARY — smart_pointer.weak_ptr
#
# WeakPtr : référence FAIBLE vers une valeur détenue par des SharedPtr (std::weak_ptr). Elle n'empêche pas
# la destruction : lock() rend un nouveau SharedPtr si la valeur vit encore, sinon null. Sert à casser les
# cycles (parent <-> enfant), aux caches et aux observateurs.
#
#   use smart_pointer.shared_ptr as sp
#   use smart_pointer.weak_ptr as wp
#   s := sp.make_shared(Noeud("racine"))
#   w := wp.WeakPtr(s)
#   p := w.lock()                  # SharedPtr (2 propriétaires)
#   p.drop()
#   s.drop()                       # plus de propriétaire : valeur détruite
#   print(w.expired(), w.lock())   # true null
#   w.lock_or_raise()              # ExpiredError
#
# Erreurs : ExpiredError (lock_or_raise), TypeError.

from core use type
from smart_pointer.shared_ptr use SharedPtr
use smart_pointer.smart_pointer_errors as _e

class WeakPtr:
    func init(shared=null):
        self._cb = null
        if shared != null:
            if not isinstance(shared, SharedPtr):
                raise("TypeError", "WeakPtr : SharedPtr attendu")
            self._cb = shared._control()
            if self._cb != null:
                self._cb.acquire_weak()

    func expired():
        return self._cb == null or not self._cb.alive()

    # Nouveau SharedPtr propriétaire, ou null si la valeur n'existe plus.
    func lock():
        if self.expired():
            return null
        return SharedPtr(null, null, self._cb)

    func lock_or_raise():
        p := self.lock()
        if p == null:
            _e.expired("WeakPtr.lock")
        return p

    # Lecture sans prise de propriété (null si expirée).
    func peek():
        if self.expired():
            return null
        return self._cb.value

    func use_count():
        if self.expired():
            return 0
        return self._cb.strong

    func reset():
        if self._cb != null:
            self._cb.release_weak()
        self._cb = null

    func points_to(shared):
        return self._cb != null and shared._control() != null and shared._control().id == self._cb.id

    func __str__():
        if self.expired():
            return "WeakPtr(<expiré>)"
        return "WeakPtr(" + str(self._cb.value) + ")"

func downgrade(shared):
    return WeakPtr(shared)

# ALEX STANDARD LIBRARY — smart_pointer.reference_count
#
# Bloc de contrôle à comptage de références, partagé par SharedPtr et WeakPtr (comme le « control block »
# de std::shared_ptr) : compte FORT (propriétaires), compte FAIBLE (observateurs), suppresseur appelé
# exactement une fois quand le compte fort tombe à zéro.
#
#   use smart_pointer.reference_count as rc
#   cb := rc.ControlBlock(fichier, (f) => f.close())
#   cb.acquire()                 # +1 fort
#   cb.release()                 # -1 fort ; à 0 : suppresseur appelé, valeur oubliée
#   print(cb.alive(), cb.strong, cb.weak)
#   c := rc.Counter()            # compteur de références simple (ressources manuelles)
#   c.retain()
#   print(c.release())           # true : dernier relâchement
#
# Erreurs : OwnershipError (release sous zéro), DeleterError.

from core use type
use smart_pointer.smart_pointer_errors as _e

_ids := [0]

func _next():
    _ids[0] += 1
    return _ids[0]

class ControlBlock:
    func init(value, deleter=null):
        _e.need_deleter("ControlBlock", deleter)
        self.id = _next()
        self.value = value
        self.deleter = deleter
        self.strong = 0
        self.weak = 0
        self.destroyed = false
        self.deleter_error = null

    func acquire():
        if self.destroyed:
            _e.expired("ControlBlock.acquire")
        self.strong += 1
        return self.strong

    # Relâche une référence forte ; true si c'était la dernière (la valeur est alors détruite).
    func release():
        if self.strong <= 0:
            raise(_e.OWNERSHIP, "ControlBlock.release : compte fort déjà nul")
        self.strong -= 1
        if self.strong == 0:
            self._destroy()
            return true
        return false

    func _destroy():
        v := self.value
        self.value = null
        self.destroyed = true
        if self.deleter != null:
            d := self.deleter
            self.deleter = null
            try:
                d(v)
            catch e:
                self.deleter_error = e
                raise(_e.DELETER, "suppresseur : " + e.type + " : " + e.message)

    func acquire_weak():
        self.weak += 1

    func release_weak():
        if self.weak > 0:
            self.weak -= 1

    func alive():
        return not self.destroyed

    func __str__():
        return "ControlBlock(#" + str(self.id) + ", fort " + str(self.strong) + ", faible " + str(self.weak) + ")"

# Compteur de références manuel (retain / release), pour des ressources partagées sans pointeur.
class Counter:
    func init(initial=1, on_zero=null):
        self.count = initial
        self.on_zero = on_zero

    func retain():
        if self.count <= 0:
            raise(_e.OWNERSHIP, "Counter.retain : ressource déjà relâchée")
        self.count += 1
        return self.count

    # true si le compteur atteint zéro (on_zero est alors appelée).
    func release():
        if self.count <= 0:
            raise(_e.OWNERSHIP, "Counter.release : compteur déjà à zéro")
        self.count -= 1
        if self.count == 0:
            if self.on_zero != null:
                self.on_zero()
            return true
        return false

    func is_released():
        return self.count == 0

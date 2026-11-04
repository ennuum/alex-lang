# ALEX STANDARD LIBRARY — atomic.atomic_reference
#
# Référence ATOMIQUE à une valeur copiable (null, bool, nombres, str, list, tuple, dict — comme les messages entre
# fils) : lecture, remplacement, échange et compare-and-set de la valeur ENTIÈRE, entre fils.
#
#   use atomic.atomic_reference as ar
#   config := ar.AtomicReference({"niveau": "info"})
#   config.set({"niveau": "debug"})                  # visible de tous les fils (attach(config.id))
#   config.update((c) => fusion(c, {"x": 1}))        # boucle compare-and-set
#   if config.compare_and_set(ancienne, nouvelle): ...
#
# Comme entre fils les valeurs sont COPIÉES, get() renvoie une copie : la modifier ne change pas la référence
# (il faut set()). compare_and_set compare par égalité de structure (==), pas par identité. version() augmente
# à chaque écriture (détecter un changement sans comparer les valeurs).
#
# Erreurs : TypeError (valeur non copiable : fonction, objet...), ArgumentError.

use _native_sync as _s
use atomic._common as _c

class AtomicReference:
    func init(value=null, id=null):
        if id != null:
            _c.check_kind("AtomicReference", id, "ref")
            self.id = id
        else:
            self.id = _s.ref_new(value)

    func get():
        return _s.ref_load(self.id)

    func set(value):
        _s.ref_store(self.id, value)

    func get_and_set(value):
        return _s.ref_exchange(self.id, value)

    # Si la valeur actuelle est égale (==) à expected, la remplace par new et renvoie true.
    func compare_and_set(expected, new):
        return _s.ref_cas(self.id, expected, new)[0]

    # (réussi, valeur actuelle après l'opération)
    func compare_exchange(expected, new):
        r := _s.ref_cas(self.id, expected, new)
        return (r[0], r[1])

    # Remplace v par f(v) atomiquement (f peut être rappelée) ; renvoie la nouvelle valeur.
    func update(f):
        while true:
            old := self.get()
            new := f(old)
            if _s.ref_cas(self.id, old, new)[0]:
                return new

    func version():
        return _s.ref_version(self.id)

    func destroy():
        _s.destroy(self.id)

    func to_string():
        return "AtomicReference(" + str(self.get()) + ")"

func attach(id):
    return AtomicReference(null, id)

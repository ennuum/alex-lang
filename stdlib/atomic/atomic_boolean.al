# ALEX STANDARD LIBRARY — atomic.atomic_boolean
#
# Booléen ATOMIQUE partagé entre fils : drapeau d'arrêt, « déjà fait », verrou rudimentaire.
#
#   use atomic.atomic_boolean as ab
#   arret := ab.AtomicBoolean(false)
#   thread.spawn(boucle, [arret.id])              # dans le fil : a := ab.attach(id) ; while not a.get(): ...
#   arret.set(true)
#   if not deja.test_and_set():                   # le premier fil qui arrive passe
#       initialiser()
#
# Erreurs : TypeError, ArgumentError.

from core use type
use _native_sync as _s
use atomic._common as _c

func _b(v):
    if v:
        return 1
    return 0

func _need_bool(fn, v):
    if type(v) != "bool":
        raise("TypeError", fn + " : bool attendu (obtenu '" + type(v) + "')")

class AtomicBoolean:
    func init(value=false, id=null):
        if id != null:
            _c.check_kind("AtomicBoolean", id, "atomic")
            self.id = id
        else:
            _need_bool("AtomicBoolean", value)
            self.id = _s.atomic_new(_b(value))

    func get():
        return _s.atomic_load(self.id) != 0

    func set(value):
        _need_bool("AtomicBoolean.set", value)
        _s.atomic_store(self.id, _b(value))

    func get_and_set(value):
        _need_bool("AtomicBoolean.get_and_set", value)
        return _s.atomic_exchange(self.id, _b(value)) != 0

    func compare_and_set(expected, new):
        _need_bool("AtomicBoolean.compare_and_set", expected)
        _need_bool("AtomicBoolean.compare_and_set", new)
        return _s.atomic_cas(self.id, _b(expected), _b(new))[0]

    # Met à true ; renvoie l'ANCIENNE valeur (false : c'est cet appel qui l'a levé).
    func test_and_set():
        return _s.atomic_exchange(self.id, 1) != 0

    func clear():
        _s.atomic_store(self.id, 0)

    # Inverse ; renvoie la NOUVELLE valeur.
    func toggle():
        return (_s.atomic_fetch(self.id, "xor", 1) ^ 1) != 0

    # Attend que la valeur devienne value ; false après timeout secondes.
    func wait_until(value, timeout=null):
        _need_bool("AtomicBoolean.wait_until", value)
        _c.need_timeout("AtomicBoolean.wait_until", timeout)
        if self.get() == value:
            return true
        r := _s.atomic_wait(self.id, _b(not value), timeout)
        return self.get() == value

    func destroy():
        _s.destroy(self.id)

    func to_string():
        return "AtomicBoolean(" + str(self.get()) + ")"

func attach(id):
    return AtomicBoolean(false, id)

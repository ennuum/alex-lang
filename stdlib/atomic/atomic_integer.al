# ALEX STANDARD LIBRARY — atomic.atomic_integer
#
# Entier de 64 bits à opérations ATOMIQUES, partagé entre FILS (thread, concurrency.thread) : chaque opération
# lire-modifier-écrire est indivisible, même quand plusieurs cœurs l'exécutent en même temps. Un AtomicInteger se
# transmet à un fil par son identifiant (.id), que le fil rattache avec attach(id).
#
#   use atomic.atomic_integer as ai
#   compteur := ai.AtomicInteger(0)
#   t := thread.spawn(travailleur, [compteur.id])        # dans le fil : c := ai.attach(id) ; c.increment()
#   print(compteur.increment())                          # nouvelle valeur
#   print(compteur.get_and_add(10))                      # ancienne valeur
#   compteur.compare_and_set(11, 0)                      # true si la valeur était 11
#   compteur.update((v) => v * 2)                        # boucle CAS : f peut être rappelée
#   compteur.wait_while(0, 5.0)                          # attend qu'il ne vaille plus 0 (5 s au plus)
#
# Arithmétique enroulée sur 64 bits, comme les int d'Alex (max + 1 == min).
#
# Erreurs : TypeError (valeur non entière, identifiant d'un autre type), ArgumentError (objet détruit).

from core use type
use _native_sync as _s
use atomic._common as _c

class AtomicInteger:
    # value : valeur initiale ; id : rattache un AtomicInteger existant (créé dans un autre fil).
    func init(value=0, id=null):
        if id != null:
            _c.check_kind("AtomicInteger", id, "atomic")
            self.id = id
        else:
            _c.need_int("AtomicInteger", value)
            self.id = _s.atomic_new(value)

    func get():
        return _s.atomic_load(self.id)

    func set(value):
        _c.need_int("AtomicInteger.set", value)
        _s.atomic_store(self.id, value)

    func get_and_set(value):
        _c.need_int("AtomicInteger.get_and_set", value)
        return _s.atomic_exchange(self.id, value)

    # Si la valeur vaut expected, la remplace par new : renvoie true ; sinon false.
    func compare_and_set(expected, new):
        _c.need_int("AtomicInteger.compare_and_set", expected)
        _c.need_int("AtomicInteger.compare_and_set", new)
        return _s.atomic_cas(self.id, expected, new)[0]

    # Comme compare_and_set, mais renvoie (réussi, valeur trouvée).
    func compare_exchange(expected, new):
        _c.need_int("AtomicInteger.compare_exchange", expected)
        _c.need_int("AtomicInteger.compare_exchange", new)
        r := _s.atomic_cas(self.id, expected, new)
        return (r[0], r[1])

    func get_and_add(delta):
        _c.need_int("AtomicInteger.get_and_add", delta)
        return _s.atomic_fetch(self.id, "add", delta)

    func add_and_get(delta):
        _c.need_int("AtomicInteger.add_and_get", delta)
        return _s.atomic_fetch(self.id, "add", delta) + delta

    func get_and_increment():
        return _s.atomic_fetch(self.id, "add", 1)

    func get_and_decrement():
        return _s.atomic_fetch(self.id, "sub", 1)

    # +1 ; renvoie la NOUVELLE valeur.
    func increment():
        return _s.atomic_fetch(self.id, "add", 1) + 1

    func decrement():
        return _s.atomic_fetch(self.id, "sub", 1) - 1

    func fetch_and(mask):
        return _s.atomic_fetch(self.id, "and", mask)

    func fetch_or(mask):
        return _s.atomic_fetch(self.id, "or", mask)

    func fetch_xor(mask):
        return _s.atomic_fetch(self.id, "xor", mask)

    # Garde le maximum (ou le minimum) ; renvoie l'ancienne valeur.
    func fetch_max(v):
        return _s.atomic_fetch(self.id, "max", v)

    func fetch_min(v):
        return _s.atomic_fetch(self.id, "min", v)

    # Remplace la valeur v par f(v) de façon atomique (boucle compare-and-set : f peut être appelée plusieurs
    # fois si un autre fil modifie la valeur entre-temps, elle doit donc être sans effet de bord) ; renvoie la
    # nouvelle valeur.
    func update(f):
        while true:
            old := _s.atomic_load(self.id)
            new := f(old)
            _c.need_int("AtomicInteger.update", new)
            if _s.atomic_cas(self.id, old, new)[0]:
                return new

    # f(valeur, x) atomiquement ; renvoie la nouvelle valeur.
    func accumulate(x, f):
        return self.update((v) => f(v, x))

    # Attend que la valeur soit différente de value ; false si timeout secondes passent avant.
    func wait_while(value, timeout=null):
        _c.need_timeout("AtomicInteger.wait_while", timeout)
        return _s.atomic_wait(self.id, value, timeout) == 1

    # Attend que la valeur soit égale à value ; false après timeout.
    func wait_until(value, timeout=null):
        _c.need_timeout("AtomicInteger.wait_until", timeout)
        deadline := null
        if timeout != null:
            deadline = _now() + timeout
        while true:
            cur := _s.atomic_load(self.id)
            if cur == value:
                return true
            left := null
            if deadline != null:
                left = deadline - _now()
                if left <= 0:
                    return false
            _s.atomic_wait(self.id, cur, left)

    # Réveille les fils qui attendent un changement (après une modification hors de cette API).
    func notify_all():
        _s.atomic_notify(self.id, true)

    # Libère l'objet natif (plus aucun fil ne doit s'en servir).
    func destroy():
        _s.destroy(self.id)

    func to_string():
        return "AtomicInteger(" + str(self.get()) + ")"

use os as _os

func _now():
    return _os.monotonic_time()

func attach(id):
    return AtomicInteger(0, id)

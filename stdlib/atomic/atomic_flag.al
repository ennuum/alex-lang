# ALEX STANDARD LIBRARY — atomic.atomic_flag
#
# AtomicFlag : le drapeau atomique minimal (std::atomic_flag) — deux états, test_and_set / clear, et attente
# d'un changement (wait / notify), sans autre valeur. Base des verrous tournants et des signaux « une fois ».
# Partageable entre fils réels par son identifiant (.id, attach).
#
#   use atomic.atomic_flag as af
#   f := af.AtomicFlag()
#   if not f.test_and_set():         # le premier fil qui arrive passe
#       initialiser()
#   f.clear()
#   pret := af.AtomicFlag()          # fil A : pret.wait(false) ; fil B : pret.set_and_notify()
#   pret.spin_lock()                 # verrou tournant rudimentaire
#   pret.unlock()
#
# Erreurs : TypeError, ArgumentError (attach d'un objet inconnu), TimeoutError (spin_lock avec délai).

from core use type
use os as _os
use _native_sync as _s
use atomic._common as _c
use atomic.memory_order as _mo

class AtomicFlag:
    func init(id=null):
        if id != null:
            _c.check_kind("AtomicFlag", id, "atomic")
            self.id = id
        else:
            self.id = _s.atomic_new(0)

    # Lève le drapeau ; renvoie l'ANCIEN état (false : c'est cet appel qui l'a levé).
    func test_and_set(order="seq_cst"):
        _mo.check_rmw(order)
        return _s.atomic_exchange(self.id, 1) != 0

    func clear(order="seq_cst"):
        _mo.check_store(order)
        _s.atomic_store(self.id, 0)

    func test(order="seq_cst"):
        _mo.check_load(order)
        return _s.atomic_load(self.id) != 0

    # Attend que l'état soit différent de old (au plus timeout s) ; renvoie true si c'est le cas.
    func wait(old, timeout=null):
        _c.need_timeout("AtomicFlag.wait", timeout)
        v := 0
        if old:
            v = 1
        if _s.atomic_load(self.id) != v:
            return true
        _s.atomic_wait(self.id, v, timeout)
        return _s.atomic_load(self.id) != v

    func notify_one():
        _s.atomic_notify(self.id, false)

    func notify_all():
        _s.atomic_notify(self.id, true)

    func set_and_notify():
        _s.atomic_store(self.id, 1)
        _s.atomic_notify(self.id, true)

    # Verrou tournant : attend que le drapeau soit libre puis le lève ; TimeoutError après timeout s.
    func spin_lock(timeout=null):
        t0 := _os.monotonic_time()
        while _s.atomic_exchange(self.id, 1) != 0:
            if timeout != null and _os.monotonic_time() - t0 >= timeout:
                raise("TimeoutError", "AtomicFlag.spin_lock : drapeau toujours levé après " + str(timeout) + " s")
            _s.atomic_wait(self.id, 1, 0.001)

    func try_lock():
        return _s.atomic_exchange(self.id, 1) == 0

    func unlock():
        _s.atomic_store(self.id, 0)
        _s.atomic_notify(self.id, false)

    func destroy():
        _s.destroy(self.id)

    func to_string():
        return "AtomicFlag(" + str(self.test()) + ")"

func attach(id):
    return AtomicFlag(id)

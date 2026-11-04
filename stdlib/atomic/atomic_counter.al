# ALEX STANDARD LIBRARY — atomic.atomic_counter
#
# Compteurs atomiques prêts à l'emploi, partagés entre fils réels :
#   AtomicCounter   compte borné (min / max) : increment/decrement SATURANTS ou stricts (erreur au-delà),
#                   try_increment (false au plafond : jetons, places disponibles), reset, statistiques
#   Sequence        générateur d'identifiants uniques croissants (next / next_block)
#
#   use atomic.atomic_counter as ac
#   places := ac.AtomicCounter(0, 0, 10)          # 10 places au plus
#   if places.try_increment():                    # prendre une place, sans jamais dépasser 10
#       servir()
#       places.decrement()
#   ids := ac.Sequence(1000)
#   print(ids.next(), ids.next())                 # 1000 1001 (uniques, même entre fils)
#   bloc := ids.next_block(50)                    # [1002, 1052) réservé d'un coup
#   thread.spawn(travail, [places.id])            # dans le fil : ac.attach(id)
#
# Erreurs : CounterOverflowError (dépassement en mode strict), TypeError, ArgumentError.

from core use type
use _native_sync as _s
use os as _os
use atomic._common as _c

const OVERFLOW := "CounterOverflowError"

class AtomicCounter:
    # min / max : bornes (null : sans borne) ; saturate=true : on bloque à la borne au lieu de lever.
    func init(value=0, min=null, max=null, saturate=false, id=null):
        self.min = min
        self.max = max
        self.saturate = saturate
        if id != null:
            _c.check_kind("AtomicCounter", id, "atomic")
            self.id = id
        else:
            _c.need_int("AtomicCounter", value)
            if (min != null and value < min) or (max != null and value > max):
                raise("ArgumentError", "AtomicCounter : valeur initiale hors des bornes")
            self.id = _s.atomic_new(value)

    func get():
        return _s.atomic_load(self.id)

    func value():
        return _s.atomic_load(self.id)

    # Ajoute delta en respectant les bornes ; renvoie la nouvelle valeur.
    func add(delta):
        _c.need_int("AtomicCounter.add", delta)
        while true:
            cur := _s.atomic_load(self.id)
            nxt := cur + delta
            if self.max != null and nxt > self.max:
                if not self.saturate:
                    raise(OVERFLOW, "AtomicCounter : " + str(nxt) + " > max " + str(self.max))
                nxt = self.max
            if self.min != null and nxt < self.min:
                if not self.saturate:
                    raise(OVERFLOW, "AtomicCounter : " + str(nxt) + " < min " + str(self.min))
                nxt = self.min
            if _s.atomic_cas(self.id, cur, nxt)[0]:
                return nxt

    func increment():
        return self.add(1)

    func decrement():
        return self.add(-1)

    # +delta seulement si le plafond n'est pas dépassé ; false sinon (aucun changement).
    func try_add(delta):
        while true:
            cur := _s.atomic_load(self.id)
            nxt := cur + delta
            if (self.max != null and nxt > self.max) or (self.min != null and nxt < self.min):
                return false
            if _s.atomic_cas(self.id, cur, nxt)[0]:
                return true

    func try_increment():
        return self.try_add(1)

    func try_decrement():
        return self.try_add(-1)

    # Remet à value ; renvoie l'ancienne valeur.
    func reset(value=0):
        return _s.atomic_exchange(self.id, value)

    func at_max():
        return self.max != null and self.get() >= self.max

    func at_min():
        return self.min != null and self.get() <= self.min

    # Attend que la valeur atteigne target (au plus timeout s) ; true si c'est le cas.
    func wait_for(target, timeout=null):
        _c.need_timeout("AtomicCounter.wait_for", timeout)
        t0 := _now()
        while true:
            cur := _s.atomic_load(self.id)
            if cur == target:
                return true
            left := null
            if timeout != null:
                left = timeout - (_now() - t0)
                if left <= 0:
                    return false
            _s.atomic_wait(self.id, cur, left)

    func destroy():
        _s.destroy(self.id)

    func to_string():
        return "AtomicCounter(" + str(self.get()) + ")"



func _now():
    return _os.monotonic_time()

class Sequence:
    func init(start=1, id=null):
        if id != null:
            _c.check_kind("Sequence", id, "atomic")
            self.id = id
        else:
            _c.need_int("Sequence", start)
            self.id = _s.atomic_new(start)

    func next():
        return _s.atomic_fetch(self.id, "add", 1)

    # Réserve n valeurs consécutives ; renvoie [début, fin) .
    func next_block(n):
        _c.need_int("Sequence.next_block", n)
        if n < 1:
            raise("ArgumentError", "Sequence.next_block : n >= 1 attendu")
        a := _s.atomic_fetch(self.id, "add", n)
        return [a, a + n]

    # Prochaine valeur sans la consommer.
    func peek():
        return _s.atomic_load(self.id)

    func destroy():
        _s.destroy(self.id)

func attach(id, min=null, max=null, saturate=false):
    return AtomicCounter(0, min, max, saturate, id)

func attach_sequence(id):
    return Sequence(1, id)

# ALEX STANDARD LIBRARY — synchronization.countdown_event
#
# CountdownEvent : un événement qui se LÈVE quand un compteur atteint zéro (comme CountdownEvent de .NET).
# À la différence de CountDownLatch, le compte peut AUGMENTER tant qu'il n'est pas à zéro (add_count : des
# travaux découverts en cours de route), et l'événement peut être réarmé (reset).
#
#   use synchronization.countdown_event as ce
#   fin := ce.CountdownEvent(3)
#   for i in 0..3:
#       thread.spawn(travailleur, [fin.ids()])     # dans le fil : e := ce.attach(ids) ... e.signal()
#   fin.add_count(1)                               # un travail de plus
#   if fin.wait(10.0):                             # true quand le compte est revenu à 0
#       print("tout est fini")
#   fin.reset(5)                                   # réarme pour un nouveau tour
#
# Erreurs : SyncError (signal sous zéro, add_count sur un événement levé), TypeError, ArgumentError.

from core use type
use _native_sync as _s
use synchronization.synchronization_errors as _e

class CountdownEvent:
    # ids : [compteur, événement] d'un CountdownEvent créé dans un autre fil.
    func init(count=1, ids=null):
        if ids != null:
            self._count = ids[0]
            self._event = ids[1]
        else:
            if type(count) != "int" or count < 0:
                raise("ArgumentError", "CountdownEvent : compte >= 0 attendu")
            self._count = _s.atomic_new(count)
            self._event = _s.event_new(count == 0)
        self.initial = count

    func ids():
        return [self._count, self._event]

    func current_count():
        return _s.atomic_load(self._count)

    func is_set():
        return _s.event_is_set(self._event)

    # Décompte n ; renvoie true si le compte atteint zéro (l'événement est alors levé).
    func signal(n=1):
        if type(n) != "int" or n < 1:
            raise("ArgumentError", "CountdownEvent.signal : n >= 1 attendu")
        while true:
            cur := _s.atomic_load(self._count)
            if cur < n:
                _e.sync_error("CountdownEvent.signal", "compte " + str(cur) + " < " + str(n))
            if _s.atomic_cas(self._count, cur, cur - n)[0]:
                if cur - n == 0:
                    _s.event_set(self._event)
                    return true
                return false

    # Ajoute n au compte ; SyncError si l'événement est déjà levé (compte à zéro).
    func add_count(n=1):
        if not self.try_add_count(n):
            _e.sync_error("CountdownEvent.add_count", "événement déjà levé (compte à zéro) : utiliser reset()")

    func try_add_count(n=1):
        if type(n) != "int" or n < 1:
            raise("ArgumentError", "CountdownEvent.add_count : n >= 1 attendu")
        while true:
            cur := _s.atomic_load(self._count)
            if cur == 0:
                return false
            if _s.atomic_cas(self._count, cur, cur + n)[0]:
                return true

    # Attend que le compte atteigne zéro ; false après timeout secondes.
    func wait(timeout=null):
        return _s.event_wait(self._event, timeout) == 1

    func wait_or_raise(timeout):
        if not self.wait(timeout):
            _e.timeout("CountdownEvent.wait", timeout)

    # Réarme avec un nouveau compte (par défaut : le compte initial).
    func reset(count=null):
        c := count
        if c == null:
            c = self.initial
        _s.atomic_store(self._count, c)
        if c == 0:
            _s.event_set(self._event)
        else:
            _s.event_clear(self._event)

    func destroy():
        _s.destroy(self._count)
        _s.destroy(self._event)

    func to_string():
        return "CountdownEvent(" + str(self.current_count()) + ")"

func attach(ids):
    return CountdownEvent(0, ids)

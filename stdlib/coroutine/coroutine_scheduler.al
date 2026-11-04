# ALEX STANDARD LIBRARY — coroutine.coroutine_scheduler
#
# Planificateur COOPÉRATIF de coroutines, à tours : chaque coroutine prête est reprise à son tour ; elle
# s'exécute jusqu'à sa prochaine suspension. Une coroutine qui rend yield.wait(s) n'est reprise qu'après s
# secondes ; toute autre valeur rendue est remise à on_value(nom, valeur) si fourni. Utile pour simuler des
# processus concurrents (jeux, automates, protocoles) de façon déterministe.
#
#   use coroutine.coroutine_scheduler as cs
#   use coroutine.yield as y
#   async func clignotant(yy, nom):
#       i := 0
#       while i < 3:
#           await yy.yield_(y.wait(0.01))      # pause de 10 ms (sans bloquer les autres)
#           i += 1
#       return nom + " fini"
#   s := cs.Scheduler()
#   s.spawn(clignotant, ["a"])
#   s.spawn(clignotant, ["b"])
#   resultats := await s.run()                 # {"coroutine-1": "a fini", ...}
#   print(s.stats())                           # tours, reprises, durée
#
# Erreurs : SchedulerError (planificateur déjà en cours), erreurs des coroutines (policy "raise", défaut) ou
#           consignées dans s.errors (policy "collect").

from core use len, type
from collections use append
use asyncio
use coroutine.coroutine as _co
use coroutine.yield as _y

class _Slot:
    func init(co):
        self.co = co
        self.wake_at = 0
        self.resumes = 0

class Scheduler:
    func init(on_value=null, policy="raise"):
        self._slots = []
        self.on_value = on_value
        self.policy = policy
        self.results = {}
        self.errors = {}
        self.rounds = 0
        self.resumes = 0
        self._running = false
        self.started = null
        self.elapsed = 0

    func spawn(body, args=null, name=null):
        c := _co.Coroutine(body, args, name)
        append(self._slots, _Slot(c))
        return c

    func add(co):
        append(self._slots, _Slot(co))
        return co

    func size():
        return len(self._slots)

    func active():
        return [s.co.name for s in self._slots if not s.co.is_finished()]

    # Futur : exécute jusqu'à ce que toutes les coroutines soient terminées (ou max_rounds tours) ; renvoie
    # {nom: valeur de retour}.
    func run(max_rounds=null):
        if self._running:
            raise("SchedulerError", "Scheduler.run : déjà en cours")
        return _run(self, max_rounds)

    func stats():
        return {"coroutines": len(self._slots), "rounds": self.rounds, "resumes": self.resumes,
                "finished": len(self.results), "failed": len(self.errors), "seconds": self.elapsed}

async func _run(s, max_rounds):
    s._running = true
    s.started = asyncio.now()
    try:
        while true:
            live := [x for x in s._slots if not x.co.is_finished()]
            if len(live) == 0:
                break
            if max_rounds != null and s.rounds >= max_rounds:
                break
            s.rounds += 1
            now := asyncio.now()
            ran := false
            soonest := null
            for slot in live:
                if slot.wake_at > now:
                    if soonest == null or slot.wake_at < soonest:
                        soonest = slot.wake_at
                    continue
                ran = true
                v := null
                try:
                    v = await slot.co.resume()
                catch e:
                    if s.policy == "raise":
                        raise(e)
                    s.errors[slot.co.name] = e.type + " : " + e.message
                    continue
                slot.resumes += 1
                s.resumes += 1
                if slot.co.is_finished():
                    s.results[slot.co.name] = slot.co.result
                elif isinstance(v, _y.Wait):
                    slot.wake_at = asyncio.now() + v.seconds
                elif s.on_value != null:
                    s.on_value(slot.co.name, v)
            if not ran and soonest != null:
                await asyncio.sleep(soonest - asyncio.now())
    finally:
        s._running = false
        s.elapsed = asyncio.now() - s.started
    return s.results

# Exécute des corps de coroutine (async func(y)) en tourniquet ; futur des résultats.
func run_all(bodies):
    s := Scheduler()
    for b in bodies:
        s.spawn(b)
    return s.run()

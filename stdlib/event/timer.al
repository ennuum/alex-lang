# ALEX STANDARD LIBRARY — event.timer
#
# Minuteries sur la boucle async : déclencher une fonction après un délai (Timer), périodiquement (Interval), et
# deux outils pour les événements en rafale : debounce (n'agir qu'après un calme) et throttle (au plus une fois
# par période).
#
#   use event.timer as timer
#   t := timer.Timer(2.0, () => print("2 s plus tard"))
#   t.start()
#   t.cancel()                                    # avant l'échéance : rien ne se passe
#   i := timer.Interval(0.5, () => print("tic"), 3).start()   # 3 fois
#   await i.wait()                                 # futur de fin
#   sauvegarder_bientot := timer.debounce(sauvegarder, 0.3)   # appelée 10 fois de suite : 1 seule sauvegarde
#   rafraichir_ecran := timer.throttle(redessiner, 1.0 / 60)
#
# Les fonctions peuvent être async (leur futur est attendu avant le tic suivant). Il faut que la boucle async
# tourne (await, ou event.event_loop) pour que les minuteries se déclenchent.
#
# Erreurs : ArgumentError (délai négatif), TypeError ; une exception de la fonction est gardée dans last_error et
# remise à on_error si défini (sinon le minuteur s'arrête et wait() la relance).

from core use len, type, arity
use asyncio

func _call(fn, args):
    if args == null or len(args) == 0:
        return fn()
    if len(args) == 1:
        return fn(args[0])
    if len(args) == 2:
        return fn(args[0], args[1])
    return fn(args[0], args[1], args[2])

class Timer:
    func init(delay, fn, args=null):
        if delay < 0:
            raise("ArgumentError", "Timer : délai négatif")
        if type(fn) != "function":
            raise("TypeError", "Timer : fonction attendue")
        self.delay = delay
        self.fn = fn
        self.args = args
        self.interval = null
        self.count = 1
        self.fired = 0
        self.last_error = null
        self.on_error = null
        self._task = null
        self._done = asyncio.future()

    func start():
        if self._task != null and not asyncio.done(self._task):
            return self
        if asyncio.done(self._done):
            self._done = asyncio.future()
        self._task = _run_timer(self)
        return self

    # Annule les déclenchements à venir ; renvoie true s'il en restait.
    func cancel():
        if self._task == null or asyncio.done(self._task):
            return false
        asyncio.cancel(self._task)
        asyncio.resolve(self._done, self.fired)
        return true

    func stop():
        return self.cancel()

    # Recommence le décompte depuis maintenant (avec un nouveau délai éventuel).
    func restart(delay=null):
        self.cancel()
        if delay != null:
            self.delay = delay
        self._done = asyncio.future()
        return self.start()

    func active():
        return self._task != null and not asyncio.done(self._task)

    # Futur terminé quand le minuteur a fini (valeur : nombre de déclenchements).
    func wait():
        return self._done

async func _run_timer(t):
    try:
        await asyncio.sleep(t.delay)
        while true:
            try:
                r := _call(t.fn, t.args)
                if asyncio.is_future(r):
                    await r
            catch CancelledError as e:
                raise(e.type, e.message)
            catch e:
                t.last_error = e.type + ": " + e.message
                if t.on_error == null:
                    asyncio.reject(t._done, e.type, e.message)
                    return
                h := t.on_error
                h(e.type, e.message)
            t.fired += 1
            if t.interval == null or (t.count != null and t.fired >= t.count):
                asyncio.resolve(t._done, t.fired)
                return
            await asyncio.sleep(t.interval)
    catch CancelledError as e:
        asyncio.resolve(t._done, t.fired)

# Toutes les interval secondes (première fois après interval, ou first_delay) ; count fois (null : sans fin).
class Interval extends Timer:
    func init(interval, fn, count=null, args=null, first_delay=null):
        if interval <= 0:
            raise("ArgumentError", "Interval : période > 0 attendue")
        if first_delay == null:
            first_delay = interval
        super.init(first_delay, fn, args)
        self.interval = interval
        self.count = count

func after(delay, fn, args=null):
    return Timer(delay, fn, args).start()

func every(interval, fn, count=null, args=null):
    return Interval(interval, fn, count, args).start()

# Fonction qui retarde fn : chaque appel repousse l'exécution de wait secondes ; seul le dernier appel d'une
# rafale exécute fn (avec ses arguments, 3 au plus).
func debounce(fn, wait):
    state := [null]
    func call(a=null, b=null, c=null):
        if state[0] != null:
            state[0].cancel()
        args := _trim([a, b, c], fn)
        state[0] = Timer(wait, fn, args).start()
        return state[0]
    return call

# Fonction qui exécute fn au plus une fois par période (les appels en trop sont ignorés) ; renvoie true si fn a
# été exécutée.
func throttle(fn, period):
    last := [null]
    func call(a=null, b=null, c=null):
        now := asyncio.now()
        if last[0] != null and now - last[0] < period:
            return false
        last[0] = now
        _call(fn, _trim([a, b, c], fn))
        return true
    return call

func _trim(args, fn):
    n := arity(fn)[1]
    if n > len(args):
        n = len(args)
    return [args[k] for k in 0..n]

# Futur terminé après delay secondes (valeur value).
async func sleep(delay, value=null):
    await asyncio.sleep(delay)
    return value

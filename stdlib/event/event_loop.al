# ALEX STANDARD LIBRARY — event.event_loop
#
# Boucle d'événements d'APPLICATION : une seule boucle qui réunit
#   - une file d'événements (post / on : gestionnaires par type, avec priorités),
#   - des appels différés et périodiques (call_soon, call_later, every),
#   - des descripteurs à surveiller (add_reader : tube, socket, terminal, inotify...),
#   - des signaux du système (add_signal_handler),
#   - des sources sondées à chaque tour (add_source : par exemple ui.window.poll ou un FileWatcher),
# au-dessus des tâches async (asyncio) : les tâches et les gestionnaires async avancent en même temps.
#
#   use event.event_loop as el
#   loop := el.EventLoop()
#   loop.on("commande", (e) => executer(e.data))
#   loop.add_reader(tube.reader.fd, () => lire_et_poster(loop))
#   loop.add_signal_handler("TERM", () => loop.stop())
#   loop.every(1.0, rafraichir_statistiques)
#   loop.post("commande", "démarrer")
#   await loop.run()                         # jusqu'à loop.stop() (ou run(secondes))
#
# Un gestionnaire reçoit l'événement (event.Event) ; s'il renvoie un futur (async), la boucle ne l'attend pas
# (il s'exécute en tâche) sauf avec on(type, fn, priorité, true) (sérialisé). Une exception d'un gestionnaire est
# passée à on_error(fn) ; sans on_error, elle arrête la boucle et run() la relance.
#
# Erreurs : celles des gestionnaires ; ArgumentError ; ThreadError (signaux hors du programme principal).

from core use len, type, arity
from collections use append, contains_key, keys
use asyncio
use event as _ev
use event.event_queue as _eq
use event.event_dispatcher as _ed
use system.signal as _sig
use _native_fd as _f

func _call0(fn, arg):
    if arity(fn)[1] == 0:
        return fn()
    return fn(arg)

class EventLoop:
    # tick : attente maximale entre deux tours quand des descripteurs ou des sources sont surveillés (secondes).
    func init(tick=0.01):
        self.queue = _eq.EventQueue()
        self.tick = tick
        self._handlers = {}          # type -> [[priorité, fonction, attendre]]
        self._timers = []            # [échéance, période | null, fonction, id]
        self._readers = {}           # fd -> fonction
        self._writers = {}
        self._sources = []
        self._signals = {}
        self._error_handler = null
        self._error = null
        self._running = false
        self._stop = false
        self._wake_future = null
        self._next_id = 1
        self.iterations = 0
        self.handled = 0

    # ---- événements ----
    func on(event_type, handler, priority=0, serialize=false):
        if not contains_key(self._handlers, event_type):
            self._handlers[event_type] = []
        lst := self._handlers[event_type]
        i := 0
        while i < len(lst) and lst[i][0] >= priority:
            i += 1
        out := [lst[k] for k in 0..i]
        append(out, [priority, handler, serialize])
        for k in i..len(lst):
            append(out, lst[k])
        self._handlers[event_type] = out
        return () => self.off(event_type, handler)

    func off(event_type, handler):
        if contains_key(self._handlers, event_type):
            self._handlers[event_type] = [h for h in self._handlers[event_type] if h[1] != handler]

    func on_error(fn):
        self._error_handler = fn
        return self

    # Ajoute un événement à la file (traité au prochain tour) ; priorité : plus grand = plus tôt.
    func post(e, data=null, priority=0):
        r := self.queue.post(e, data, priority)
        self._wake()
        return r

    func post_unique(e, data=null, priority=0):
        r := self.queue.post_unique(e, data, priority)
        self._wake()
        return r

    # ---- appels planifiés ----
    func _add_timer(due, period, fn):
        id := self._next_id
        self._next_id += 1
        append(self._timers, [due, period, fn, id])
        self._wake()
        return id

    func call_soon(fn):
        return self._add_timer(asyncio.now(), null, fn)

    func call_later(delay, fn):
        if delay < 0:
            raise("ArgumentError", "EventLoop.call_later : délai négatif")
        return self._add_timer(asyncio.now() + delay, null, fn)

    func every(interval, fn):
        if interval <= 0:
            raise("ArgumentError", "EventLoop.every : période > 0 attendue")
        return self._add_timer(asyncio.now() + interval, interval, fn)

    # Annule un appel planifié (identifiant renvoyé par call_soon / call_later / every).
    func cancel(id):
        before := len(self._timers)
        self._timers = [t for t in self._timers if t[3] != id]
        return len(self._timers) < before

    # ---- descripteurs ----
    # fn() quand fd a des données à lire (ou est fermé de l'autre côté).
    func add_reader(fd, fn):
        self._readers[fd] = fn
        self._wake()

    func remove_reader(fd):
        if contains_key(self._readers, fd):
            self._readers = _without(self._readers, fd)

    func add_writer(fd, fn):
        self._writers[fd] = fn
        self._wake()

    func remove_writer(fd):
        if contains_key(self._writers, fd):
            self._writers = _without(self._writers, fd)

    # fn() à chaque tour (doit être rapide et ne pas bloquer : par exemple dispatch d'un FileWatcher, ou une
    # fonction qui lit ui.window.poll et poste des événements).
    func add_source(fn):
        append(self._sources, fn)
        return () => self._remove_source(fn)

    func _remove_source(fn):
        self._sources = [s for s in self._sources if s != fn]

    # ---- signaux ----
    func add_signal_handler(sig, fn):
        name := _sig.name_of(sig)
        self._signals[name] = fn
        _sig.on(name, (n) => self._on_signal(n))

    func remove_signal_handler(sig):
        name := _sig.name_of(sig)
        if contains_key(self._signals, name):
            self._signals = _without(self._signals, name)
            _sig.reset(name)

    func _on_signal(name):
        self.post("signal", name, 1000)
        if contains_key(self._signals, name):
            fn := self._signals[name]
            self.call_soon(() => _call0(fn, name))

    # ---- exécution ----
    func _wake():
        if self._wake_future != null:
            asyncio.resolve(self._wake_future, true)

    func stop():
        self._stop = true
        self._wake()

    func running():
        return self._running

    func _fail(err_type, message, context):
        if self._error_handler == null:
            self._stop = true
            self._error = [err_type, message]
            return
        h := self._error_handler
        h(err_type, message, context)

    func _run_fn(fn, arg, wait_async):
        try:
            r := _call0(fn, arg)
            if asyncio.is_future(r):
                if wait_async:
                    return r
                _watch_future(self, r, arg)
        catch e:
            self._fail(e.type, e.message, arg)
        return null

    # Traite les événements en attente ; renvoie le nombre traité.
    func dispatch_pending(limit=1000):
        return _dispatch_now(self, limit)

    # Futur : fait tourner la boucle pendant duration secondes (null : jusqu'à stop()).
    func run(duration=null):
        return _run_loop(self, duration)

    # Fait tourner la boucle jusqu'à ce que f (futur) soit terminé ; renvoie son résultat.
    func run_until(f):
        return _run_until(self, f)

func _without(d, key):
    out := {}
    for k in keys(d):
        if k != key:
            out[k] = d[k]
    return out

async func _watch_future(loop, f, ctx):
    try:
        await f
    catch e:
        loop._fail(e.type, e.message, ctx)

func _dispatch_now(loop, limit):
    n := 0
    while n < limit and not loop.queue.empty():
        e := loop.queue.poll()
        n += 1
        loop.handled += 1
        hs := []
        if contains_key(loop._handlers, e.type):
            for h in loop._handlers[e.type]:
                append(hs, h)
        if contains_key(loop._handlers, "*"):
            for h in loop._handlers["*"]:
                append(hs, h)
        for h in hs:
            if e.immediate_stopped:
                break
            loop._run_fn(h[1], e, false)
    return n

async func _dispatch_async(loop, limit):
    n := 0
    while n < limit and not loop.queue.empty():
        e := loop.queue.poll()
        n += 1
        loop.handled += 1
        hs := []
        if contains_key(loop._handlers, e.type):
            for h in loop._handlers[e.type]:
                append(hs, h)
        if contains_key(loop._handlers, "*"):
            for h in loop._handlers["*"]:
                append(hs, h)
        for h in hs:
            if e.immediate_stopped:
                break
            r := loop._run_fn(h[1], e, h[2])
            if r != null:
                try:
                    await r
                catch ex:
                    loop._fail(ex.type, ex.message, e)
    return n

func _run_timers(loop):
    now := asyncio.now()
    due := [t for t in loop._timers if t[0] <= now]
    if len(due) == 0:
        return 0
    keep := [t for t in loop._timers if t[0] > now]
    for t in due:
        if t[1] != null:
            t[0] = t[0] + t[1]
            if t[0] < now:
                t[0] = now + t[1]
            append(keep, t)
    loop._timers = keep
    for t in due:
        loop._run_fn(t[2], null, false)
    return len(due)

func _poll_fds(loop):
    items := []
    for fd in keys(loop._readers):
        append(items, [fd, "r"])
    for fd in keys(loop._writers):
        append(items, [fd, "w"])
    if len(items) == 0:
        return 0
    ready := _f.poll(items, 0)
    if type(ready) == "int":
        return 0
    n := 0
    for pair in ready:
        fd := pair[0]
        st := pair[1]
        if contains_key(loop._readers, fd) and _has_char(st, "rhe"):
            loop._run_fn(loop._readers[fd], fd, false)
            n += 1
        if contains_key(loop._writers, fd) and _has_char(st, "we"):
            loop._run_fn(loop._writers[fd], fd, false)
            n += 1
    return n

func _has_char(s, chars):
    for c in s:
        for d in chars:
            if c == d:
                return true
    return false

async func _run_loop(loop, duration):
    if loop._running:
        raise("InvalidStateError", "EventLoop.run : la boucle tourne déjà")
    loop._running = true
    loop._stop = false
    loop._error = null
    end := null
    if duration != null:
        end = asyncio.now() + duration
    try:
        while not loop._stop:
            loop.iterations += 1
            for s in [x for x in loop._sources]:
                loop._run_fn(s, null, false)
            _poll_fds(loop)
            _run_timers(loop)
            await _dispatch_async(loop, 1000)
            if loop._stop:
                break
            now := asyncio.now()
            if end != null and now >= end:
                break
            if not loop.queue.empty():
                await asyncio.sleep(0)
                continue
            wait := 3600.0
            for t in loop._timers:
                if t[0] - now < wait:
                    wait = t[0] - now
            if len(loop._readers) > 0 or len(loop._writers) > 0 or len(loop._sources) > 0:
                if loop.tick < wait:
                    wait = loop.tick
            if end != null and end - now < wait:
                wait = end - now
            if wait < 0:
                wait = 0
            loop._wake_future = asyncio.future()
            await asyncio.race([asyncio.sleep(wait), loop._wake_future])
            loop._wake_future = null
    finally:
        loop._running = false
    if loop._error != null:
        raise(loop._error[0], loop._error[1])
    return loop.handled

async func _run_until(loop, f):
    async func stopper():
        try:
            await f
        finally:
            loop.stop()
    stopper()
    await _run_loop(loop, null)
    return await f

_default := [null]

# Boucle partagée de l'application (créée à la première demande).
func default():
    if _default[0] == null:
        _default[0] = EventLoop()
    return _default[0]

# ALEX STANDARD LIBRARY — web.browser.timers
#
# Boucle d'événements du navigateur simulé : minuteries (set_timeout, set_interval, avec bridage des
# minuteries imbriquées à 4 ms), tâches, MICRO-TÂCHES (queue_microtask, réactions de promesses, livraison des
# MutationObserver), images d'animation (requestAnimationFrame à 60 i/s), horloge VIRTUELLE (avance
# instantanée et déterministe, pour les tests) ou réelle. Et Promise : promesses à la JavaScript (then,
# catch_, finally_, all, race, all_settled, any) dont wait() fait tourner la boucle jusqu'au résultat.
#
#   use web.browser.timers as tm
#   loop := tm.EventLoop()                      # horloge virtuelle à 0 ms
#   loop.set_timeout(() => print("100 ms"), 100)
#   loop.queue_microtask(() => print("micro-tâche"))
#   loop.advance(150)                           # micro-tâche, puis 100 ms ; loop.now() == 150
#   p := tm.delay(loop, 50, "ok").then((v) => v + " !")
#   p.wait()                                    # "ok !" (la boucle avance de 50 ms)
#   tm.all(loop, [tm.resolved(loop, 1), tm.delay(loop, 10, 2)]).wait()   # [1, 2]
#   loop.run_until_idle()                       # exécute tout ce qui reste
#
# Erreurs : TimeoutError (wait sans résultat dans le délai), l'erreur de rejet d'une promesse (wait), BrowserError.

from core use len, type
from collections use append, pop
use time as _time
use web.browser.browser_errors as _err
use web.browser.animation_frame as _af

const MAX_NESTING := 5
const MIN_NESTED_DELAY := 4

class Timer:
    func init(id, due, fn, args, interval, seq, nesting):
        self.id = id
        self.due = due
        self.fn = fn
        self.args = args
        self.interval = interval
        self.seq = seq
        self.nesting = nesting
        self.cancelled = false

func _call(fn, args):
    if args == null or len(args) == 0:
        return fn()
    if len(args) == 1:
        return fn(args[0])
    if len(args) == 2:
        return fn(args[0], args[1])
    return fn(args[0], args[1], args[2])

class EventLoop:
    # virtual : horloge virtuelle (true) ou réelle ; frame_rate : images par seconde des animations.
    func init(virtual=true, frame_rate=60):
        self.virtual = virtual
        self.clock = 0.0
        self.real_start = _time.monotonic()
        self.timers = []
        self.tasks = []
        self.microtasks = []
        self.frames = _af.FrameScheduler()
        self.frame_interval = 1000.0 / frame_rate
        self.next_frame = self.frame_interval
        self.next_id = 1
        self.seq = 0
        self.nesting = 0
        self.errors = []          # (type, message) des exceptions non rattrapées des rappels
        self.on_error = null      # fn(erreur) : rapport (console.error du navigateur)
        self.unhandled = []       # promesses rejetées sans gestionnaire
        self.tasks_run = 0

    # Millisecondes écoulées (performance.now()).
    func now():
        if self.virtual:
            return self.clock
        return (_time.monotonic() - self.real_start) * 1000.0

    func _report(e):
        append(self.errors, (str(e.type), str(e.message)))
        if self.on_error != null:
            try:
                self.on_error(e)
            catch e2:
                pass

    func run_callback(fn, args=null):
        try:
            _call(fn, args)
        catch e:
            self._report(e)

    # ------------------------------------------------------------ minuteries

    func _add_timer(fn, delay, args, interval):
        d := delay if delay != null and delay > 0 else 0
        if self.nesting >= MAX_NESTING and d < MIN_NESTED_DELAY:
            d = MIN_NESTED_DELAY
        id := self.next_id
        self.next_id += 1
        self.seq += 1
        append(self.timers, Timer(id, self.now() + d, fn, args, d if interval else null, self.seq, self.nesting + 1))
        return id

    func set_timeout(fn, delay=0, args=null):
        return self._add_timer(fn, delay, args, false)

    func set_interval(fn, delay=0, args=null):
        return self._add_timer(fn, delay, args, true)

    func clear_timeout(id):
        kept := []
        for t in self.timers:
            if t.id == id:
                t.cancelled = true
            else:
                append(kept, t)
        self.timers = kept

    func clear_interval(id):
        self.clear_timeout(id)

    func queue_task(fn, args=null):
        append(self.tasks, (fn, args))

    func queue_microtask(fn):
        append(self.microtasks, fn)

    func request_animation_frame(fn):
        if not self.frames.has_pending():
            # prochaine image alignée sur la cadence
            n := 0
            while n * self.frame_interval <= self.now():
                n += 1
            self.next_frame = n * self.frame_interval
        return self.frames.request(fn)

    func cancel_animation_frame(id):
        self.frames.cancel(id)

    # ------------------------------------------------------------ exécution

    func run_microtasks():
        count := 0
        while len(self.microtasks) > 0 and count < 100000:
            fn := pop(self.microtasks, 0)
            self.run_callback(fn)
            count += 1
        return count

    func _earliest_timer():
        best := null
        for t in self.timers:
            if best == null or t.due < best.due or (t.due == best.due and t.seq < best.seq):
                best = t
        return best

    func _run_timer(t):
        kept := []
        for x in self.timers:
            if x != t:
                append(kept, x)
        self.timers = kept
        self.nesting = t.nesting
        self.run_callback(t.fn, t.args)
        self.nesting = 0
        if t.interval != null and not t.cancelled:
            self.seq += 1
            t.due = t.due + (t.interval if t.interval > 0 else 1)
            if t.due < self.now():
                t.due = self.now()
            t.seq = self.seq
            append(self.timers, t)
        self.tasks_run += 1
        self.run_microtasks()

    func _run_frame():
        ts := self.next_frame
        self.frames.run_frame(ts, (fn, stamp) => self.run_callback(fn, [stamp]))
        self.next_frame = ts + self.frame_interval
        self.run_microtasks()

    # Exécute une tâche prête (tâche en file, minuterie échue ou image due) ; vrai si quelque chose a tourné.
    func step():
        self.run_microtasks()
        if len(self.tasks) > 0:
            t := pop(self.tasks, 0)
            self.run_callback(t[0], t[1])
            self.tasks_run += 1
            self.run_microtasks()
            return true
        now := self.now()
        t := self._earliest_timer()
        frame_due := self.frames.has_pending() and self.next_frame <= now
        if t != null and t.due <= now and (not frame_due or t.due <= self.next_frame):
            self._run_timer(t)
            return true
        if frame_due:
            self._run_frame()
            return true
        return false

    # Prochaine échéance (minuterie ou image), ou null.
    func next_deadline():
        t := self._earliest_timer()
        d := t.due if t != null else null
        if self.frames.has_pending() and (d == null or self.next_frame < d):
            d = self.next_frame
        return d

    # Avance de ms millisecondes en exécutant tout ce qui échoit (horloge réelle : attend réellement).
    func advance(ms):
        target := self.now() + ms
        guard := 0
        while guard < 1000000:
            guard += 1
            while self.step():
                pass
            if len(self.tasks) > 0 or len(self.microtasks) > 0:
                continue
            d := self.next_deadline()
            if d == null or d > target:
                break
            if self.virtual:
                self.clock = d if d > self.clock else self.clock
            else:
                wait := (d - self.now()) / 1000.0
                if wait > 0:
                    _time.sleep(wait)
        if self.virtual:
            if target > self.clock:
                self.clock = target
        else:
            rest := (target - self.now()) / 1000.0
            if rest > 0:
                _time.sleep(rest)
            while self.step():
                pass
        return self

    func is_idle():
        return len(self.timers) == 0 and len(self.tasks) == 0 and len(self.microtasks) == 0 and not self.frames.has_pending()

    # Exécute jusqu'à ne plus rien avoir à faire (au plus max_ms de temps simulé) ; renvoie le temps écoulé.
    func run_until_idle(max_ms=60000):
        start := self.now()
        guard := 0
        while not self.is_idle() and guard < 1000000:
            guard += 1
            if self.step():
                continue
            d := self.next_deadline()
            if d == null:
                break
            if d - start > max_ms:
                self.advance(start + max_ms - self.now())
                break
            if self.virtual:
                self.clock = d
            else:
                w := (d - self.now()) / 1000.0
                if w > 0:
                    _time.sleep(w)
        return self.now() - start

    # Avance jusqu'à ce que predicate() soit vrai (au plus timeout_ms) ; renvoie predicate().
    func run_until(predicate, timeout_ms=10000):
        start := self.now()
        guard := 0
        while not predicate() and guard < 1000000:
            guard += 1
            if self.step():
                continue
            d := self.next_deadline()
            if d == null or d - start > timeout_ms:
                break
            if self.virtual:
                self.clock = d
            else:
                w := (d - self.now()) / 1000.0
                if w > 0:
                    _time.sleep(w if w < 0.05 else 0.05)
        return predicate()

    func pending():
        return {"timers": len(self.timers), "tasks": len(self.tasks), "microtasks": len(self.microtasks), "frames": len(self.frames.callbacks)}

_default := [null]

# Boucle partagée par défaut (horloge virtuelle).
func default_loop():
    if _default[0] == null:
        _default[0] = EventLoop()
    return _default[0]

# ---------------------------------------------------------------- promesses

const PENDING := "pending"
const FULFILLED := "fulfilled"
const REJECTED := "rejected"

func _error_of(e):
    try:
        return _err.ErrorValue(str(e.type), str(e.message))
    catch x:
        return _err.ErrorValue("Error", str(e))

func _is_promise(v):
    return isinstance(v, Promise)

class Promise:
    # executor : fn(resolve, reject) appelée immédiatement (une exception rejette la promesse).
    func init(loop=null, executor=null):
        self.loop = loop if loop != null else default_loop()
        self.state = PENDING
        self.value = null
        self.reactions = []
        self.handled = false
        self.settled_lock = false
        if executor != null:
            p := self
            try:
                executor((v) => p.resolve(v), (e) => p.reject(e))
            catch e:
                self.reject(_error_of(e))

    func resolve(v):
        if self.settled_lock:
            return
        self.settled_lock = true
        if _is_promise(v):
            if v == self:
                self.settled_lock = false
                self._settle(REJECTED, _err.ErrorValue("TypeError", "une promesse ne peut pas se résoudre en elle-même"))
                return
            p := self
            v.then((x) => p._settle(FULFILLED, x), (e) => p._settle(REJECTED, e))
            return
        self._settle(FULFILLED, v)

    func reject(e):
        if self.settled_lock:
            return
        self.settled_lock = true
        self._settle(REJECTED, e)

    func _settle(state, value):
        if self.state != PENDING:
            return
        self.state = state
        self.value = value
        rs := self.reactions
        self.reactions = []
        for r in rs:
            self._schedule(r)
        if state == REJECTED and len(rs) == 0:
            append(self.loop.unhandled, self)

    func _schedule(reaction):
        p := self
        self.loop.queue_microtask(() => reaction(p.state, p.value))

    # Nouvelle promesse résolue avec le résultat du gestionnaire (on_ok si tenue, on_err si rejetée).
    func then(on_ok=null, on_err=null):
        child := Promise(self.loop)
        self.handled = true
        self._remove_unhandled()
        handler := (state, value) => _react(child, state, value, on_ok, on_err)
        if self.state == PENDING:
            append(self.reactions, handler)
        else:
            self._schedule(handler)
        return child

    func _remove_unhandled():
        kept := []
        for x in self.loop.unhandled:
            if x != self:
                append(kept, x)
        self.loop.unhandled = kept

    func catch_(on_err):
        return self.then(null, on_err)

    func finally_(fn):
        return self.then((v) => _finally_ok(fn, v), (e) => _finally_err(fn, e))

    func is_pending():
        return self.state == PENDING

    func is_fulfilled():
        return self.state == FULFILLED

    func is_rejected():
        return self.state == REJECTED

    # Fait tourner la boucle jusqu'au règlement (au plus timeout_ms) : valeur, ou lève l'erreur de rejet.
    func wait(timeout_ms=30000):
        self.handled = true
        self._remove_unhandled()
        self.loop.run_until(() => self.state != PENDING, timeout_ms)
        if self.state == PENDING:
            _err.fail(_err.TIMEOUT, "Promise.wait", "promesse non réglée après " + str(timeout_ms) + " ms")
        if self.state == REJECTED:
            e := self.value
            name := "Error"
            msg := str(e)
            try:
                name = e.name
                msg = e.message
            catch x:
                pass
            raise(name, msg)
        return self.value

    func __str__():
        return "Promise<" + self.state + ">"

func _react(child, state, value, on_ok, on_err):
    h := on_ok if state == FULFILLED else on_err
    if h == null:
        if state == FULFILLED:
            child.resolve(value)
        else:
            child.reject(value)
        return
    try:
        child.resolve(h(value))
    catch e:
        child.reject(_error_of(e))

func _finally_ok(fn, v):
    fn()
    return v

func _finally_err(fn, e):
    fn()
    raise(e.name if _has_name(e) else "Error", e.message if _has_name(e) else str(e))

func _has_name(e):
    try:
        n := e.name
        return true
    catch x:
        return false

func resolved(loop, value):
    p := Promise(loop)
    p.resolve(value)
    return p

func rejected(loop, error):
    p := Promise(loop)
    p.reject(error)
    return p

# Promesse tenue avec value après ms millisecondes.
func delay(loop, ms, value=null):
    p := Promise(loop)
    loop.set_timeout(() => p.resolve(value), ms)
    return p

func all(loop, promises):
    out := Promise(loop)
    n := len(promises)
    results := []
    count := [0]
    i := 0
    while i < n:
        append(results, null)
        i += 1
    if n == 0:
        out.resolve([])
        return out
    i = 0
    for p in promises:
        q := p if _is_promise(p) else resolved(loop, p)
        _track_all(q, i, results, count, n, out)
        i += 1
    return out

func _track_all(q, i, results, count, n, out):
    q.then((v) => _all_ok(results, i, v, count, n, out), (e) => out.reject(e))

func _all_ok(results, i, v, count, n, out):
    results[i] = v
    count[0] = count[0] + 1
    if count[0] == n:
        out.resolve(results)

func all_settled(loop, promises):
    out := Promise(loop)
    n := len(promises)
    results := []
    count := [0]
    for p in promises:
        append(results, null)
    if n == 0:
        out.resolve([])
        return out
    i := 0
    for p in promises:
        q := p if _is_promise(p) else resolved(loop, p)
        _track_settled(q, i, results, count, n, out)
        i += 1
    return out

func _track_settled(q, i, results, count, n, out):
    q.then((v) => _settled_one(results, i, {"status": FULFILLED, "value": v}, count, n, out), (e) => _settled_one(results, i, {"status": REJECTED, "reason": e}, count, n, out))

func _settled_one(results, i, r, count, n, out):
    results[i] = r
    count[0] = count[0] + 1
    if count[0] == n:
        out.resolve(results)

func race(loop, promises):
    out := Promise(loop)
    for p in promises:
        q := p if _is_promise(p) else resolved(loop, p)
        q.then((v) => out.resolve(v), (e) => out.reject(e))
    return out

func any(loop, promises):
    out := Promise(loop)
    n := len(promises)
    errors := []
    count := [0]
    if n == 0:
        out.reject(_err.ErrorValue("AggregateError", "aucune promesse"))
        return out
    for p in promises:
        q := p if _is_promise(p) else resolved(loop, p)
        q.then((v) => out.resolve(v), (e) => _any_err(errors, e, count, n, out))
    return out

func _any_err(errors, e, count, n, out):
    append(errors, e)
    count[0] = count[0] + 1
    if count[0] == n:
        out.reject(_err.ErrorValue("AggregateError", "toutes les promesses ont été rejetées"))

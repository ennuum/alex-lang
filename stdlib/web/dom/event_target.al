# ALEX STANDARD LIBRARY — web.dom.event_target
#
# EventTarget et l'algorithme de DISTRIBUTION du DOM : écouteurs par type, phase de capture puis cible puis
# bouillonnement, options capture / once / passive / signal (annulation par un AbortSignal), objets
# écouteurs (méthode handle_event), gestionnaires « on… » (set_event_handler : un retour false annule),
# arrêt de propagation, et exceptions d'écouteurs signalées sans interrompre la distribution.
#
#   use web.dom.event_target as et
#   use web.dom.event as ev
#   t := et.EventTarget()
#   t.add_event_listener("ping", (e) => print("reçu", e.type), {"once": true})
#   t.dispatch_event(ev.Event("ping"))           # true (non annulé)
#   t.set_event_handler("ping", (e) => false)    # comme t.onping = …
#   et.reported_errors()                         # exceptions levées par des écouteurs (les plus récentes)
#
# Les nœuds (web.dom.node) redéfinissent get_the_parent(event) pour donner le chemin de propagation.
#
# Erreurs : InvalidStateError (événement déjà en cours de distribution), DomError (type ou écouteur invalide).

from core use len, type
from collections use append, pop
use web.dom.dom_errors as _err
use web.dom.event as _ev

_errors := []

# Exceptions levées par les écouteurs pendant les distributions (au plus 50, les plus récentes).
func reported_errors():
    return _errors

func clear_reported_errors():
    while len(_errors) > 0:
        pop(_errors)

func _report(e, listener_type):
    append(_errors, str(e.type) + " : " + str(e.message) + " (écouteur « " + listener_type + " »)")
    while len(_errors) > 50:
        pop(_errors, 0)

class Listener:
    func init(event_type, callback, capture, once, passive):
        self.type = event_type
        self.callback = callback
        self.capture = capture
        self.once = once
        self.passive = passive
        self.removed = false

func _flatten_options(options):
    # -> (capture, once, passive, signal)
    if options == null:
        return (false, false, false, null)
    if type(options) == "bool":
        return (options, false, false, null)
    if type(options) == "dict":
        return (options["capture"] if "capture" in options else false, options["once"] if "once" in options else false, options["passive"] if "passive" in options else false, options["signal"] if "signal" in options else null)
    _err.dom_error("add_event_listener", "options : booléen ou dict attendu")

func _same_callback(a, b):
    return a == b

class EventTarget:
    func init():
        self.listeners = []
        self.event_handlers = {}

    func add_event_listener(event_type, callback, options=null):
        if callback == null:
            return
        o := _flatten_options(options)
        signal := o[3]
        if signal != null and signal.aborted:
            return
        for l in self.listeners:
            if l.type == event_type and l.capture == o[0] and _same_callback(l.callback, callback) and not l.removed:
                return
        entry := Listener(event_type, callback, o[0], o[1], o[2])
        append(self.listeners, entry)
        if signal != null:
            target := self
            signal.add_event_listener("abort", (e) => target._remove_listener(entry))

    func _remove_listener(l):
        l.removed = true
        kept := []
        for x in self.listeners:
            if x != l:
                append(kept, x)
        self.listeners = kept

    func remove_event_listener(event_type, callback, options=null):
        capture := _flatten_options(options)[0]
        for l in self.listeners:
            if l.type == event_type and l.capture == capture and _same_callback(l.callback, callback):
                self._remove_listener(l)
                return

    func has_event_listener(event_type):
        for l in self.listeners:
            if l.type == event_type and not l.removed:
                return true
        return event_type in self.event_handlers and self.event_handlers[event_type] != null

    func listener_count(event_type=null):
        n := 0
        for l in self.listeners:
            if (event_type == null or l.type == event_type) and not l.removed:
                n += 1
        return n

    # Gestionnaire « on<type> » (un seul par type ; null le retire). Un retour false annule l'événement.
    func set_event_handler(event_type, fn):
        first := not (event_type in self.event_handlers)
        self.event_handlers[event_type] = fn
        if first:
            target := self
            self.add_event_listener(event_type, _HandlerListener(target, event_type))

    func get_event_handler(event_type):
        if event_type in self.event_handlers:
            return self.event_handlers[event_type]
        return null

    # Parent dans le chemin de propagation (null : fin du chemin).
    func get_the_parent(event):
        return null

    func dispatch_event(event):
        if event.dispatching:
            _err.invalid_state("dispatch_event", "l'événement « " + event.type + " » est déjà en cours de distribution")
        if event.event_phase != _ev.NONE:
            _err.invalid_state("dispatch_event", "événement non initialisé")
        event.is_trusted = false
        return dispatch(self, event)

class _HandlerListener:
    func init(target, event_type):
        self.target = target
        self.event_type = event_type

    func handle_event(e):
        fn := self.target.event_handlers[self.event_type] if self.event_type in self.target.event_handlers else null
        if fn == null:
            return
        r := fn(e)
        if r == false and self.event_type != "mouseover" and self.event_type != "error":
            e.prevent_default()
        if self.event_type == "error" and r == true:
            e.prevent_default()

func _invoke(node, event, phase_capture):
    if event.stop_flag:
        return
    event.current_target = node
    snapshot := []
    for l in node.listeners:
        if l.type == event.type and l.capture and phase_capture != "bubble":
            append(snapshot, l)
    for l in node.listeners:
        if l.type == event.type and not l.capture and phase_capture != "capture":
            append(snapshot, l)
    for l in snapshot:
        if l.removed:
            continue
        if l.once:
            node._remove_listener(l)
        event.in_passive_listener = l.passive
        cb := l.callback
        try:
            is_obj := false
            try:
                h := cb.handle_event
                is_obj = true
            catch e0:
                is_obj = false
            if is_obj:
                cb.handle_event(event)
            else:
                cb(event)
        catch e:
            _report(e, event.type)
        event.in_passive_listener = false
        if event.stop_immediate_flag:
            return

# Distribue l'événement à partir de target (capture, cible, bouillonnement) ; renvoie not default_prevented.
func dispatch(target, event, trusted=false):
    event.is_trusted = trusted
    path := [target]
    p := target.get_the_parent(event)
    guard := 0
    while p != null and guard < 10000:
        append(path, p)
        p = p.get_the_parent(event)
        guard += 1
    event.target = target
    event.path = path
    event.dispatching = true
    i := len(path) - 1
    while i >= 1:
        event.event_phase = _ev.CAPTURING_PHASE
        _invoke(path[i], event, "capture")
        i -= 1
    event.event_phase = _ev.AT_TARGET
    _invoke(target, event, "target")
    if event.bubbles:
        i = 1
        while i < len(path):
            event.event_phase = _ev.BUBBLING_PHASE
            _invoke(path[i], event, "bubble")
            i += 1
    event.event_phase = _ev.NONE
    event.current_target = null
    event.dispatching = false
    event.stop_flag = false
    event.stop_immediate_flag = false
    return not event.default_prevented

# ALEX STANDARD LIBRARY — event.event_errors
#
# Erreurs du système d'événements, et outils pour qu'un écouteur défaillant ne casse pas toute la chaîne :
#   EventError        usage incorrect (type d'événement vide, écouteur invalide, abonnement terminé)
#   ListenerError     un ou plusieurs écouteurs ont échoué (message récapitulatif)
#   QueueFull         file d'événements pleine (event.event_queue)
#   TimeoutError      attente d'un événement trop longue (wait_for, get)
#
#   use event.event_errors as ev_err
#   journal := ev_err.ErrorCollector()
#   bus.on("commande", ev_err.safe(traiter, journal))     # l'erreur est notée, pas propagée
#   bus.emit("commande", c)
#   print(journal.count(), journal.last())                 # 1 {"type": "KeyError", "message": ..., "event": ...}
#   journal.raise_if_any()                                 # ListenerError récapitulative s'il y en a eu
#
# Erreurs : ListenerError (raise_if_any), EventError.

from core use len, type
from collections use append
use string as _s
use os as _os

const EVENT := "EventError"
const LISTENER := "ListenerError"
const QUEUE_FULL := "QueueFull"
const TIMEOUT := "TimeoutError"

func fail(message):
    raise(EVENT, message)

func is_event_error(t):
    return t == EVENT or t == LISTENER or t == QUEUE_FULL

class ErrorCollector:
    func init(max_kept=100):
        self.errors = []
        self.max_kept = max_kept
        self.total = 0

    func add(error_type, message, event=null, listener=null):
        self.total += 1
        ev := event
        if ev != null and type(ev) != "str" and type(ev) != "int" and type(ev) != "dict" and type(ev) != "list":
            try:
                ev = ev.type
            catch e:
                ev = str(ev)
        append(self.errors, {"type": error_type, "message": message, "event": ev, "listener": listener, "time": _os.time()})
        if len(self.errors) > self.max_kept:
            self.errors = self.errors[1:]

    func count():
        return self.total

    func last():
        if len(self.errors) == 0:
            return null
        return self.errors[len(self.errors) - 1]

    func clear():
        self.errors = []
        self.total = 0

    func summary():
        return _s.join("\n", [e["type"] + " : " + e["message"] + _where(e) for e in self.errors])

    func raise_if_any():
        if self.total > 0:
            raise(LISTENER, str(self.total) + " écouteur(s) en échec — " + self.summary())

func _where(e):
    if e["event"] == null:
        return ""
    return " (événement " + str(e["event"]) + ")"

# Écouteur protégé : ses erreurs sont remises au collecteur (ou à on_error(type, message, arg0)) au lieu de
# remonter ; renvoie null en cas d'échec.
func safe(fn, collector=null, on_error=null, name=null):
    return (*args) => _run_safe(fn, args, collector, on_error, name)

func _run_safe(fn, args, collector, on_error, name):
    try:
        return fn(*args)
    catch e:
        first := null
        if len(args) > 0:
            first = args[0]
        if collector != null:
            collector.add(e.type, e.message, first, name)
        if on_error != null:
            on_error(e.type, e.message, first)
        return null

# Appelle chaque écouteur, même si certains échouent ; lève ListenerError récapitulative à la fin si besoin.
func call_all(listeners, args):
    col := ErrorCollector()
    results := []
    for l in listeners:
        try:
            append(results, l(*args))
        catch e:
            col.add(e.type, e.message, null, null)
    col.raise_if_any()
    return results

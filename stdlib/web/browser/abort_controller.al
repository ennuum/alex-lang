# ALEX STANDARD LIBRARY — web.browser.abort_controller
#
# AbortController / AbortSignal : annulation coopérative d'opérations (fetch, écouteurs d'événements,
# lectures de fichiers, attentes). Un signal annulé distribue « abort » une seule fois ; AbortSignal.timeout
# s'annule seul après un délai (boucle d'événements), any() combine plusieurs signaux.
#
#   use web.browser.abort_controller as ac
#   ctl := ac.AbortController()
#   loop_fetch := browser.fetch("/lent", {"signal": ctl.signal})
#   ctl.abort()                                  # la promesse est rejetée avec AbortError
#   ctl.signal.aborted, ctl.signal.reason.name   # true AbortError
#   s := ac.timeout(loop, 500)                   # annulé (TimeoutError) après 500 ms
#   ac.any([s, ctl.signal])
#   el.add_event_listener("click", f, {"signal": ctl.signal})   # retiré à l'annulation
#
# Erreurs : la raison d'annulation (AbortError par défaut) levée par throw_if_aborted().

from core use len, type
from collections use append
use web.browser.browser_errors as _err
use web.dom.event as _ev
use web.dom.event_target as _et
from web.dom.event_target use EventTarget

class AbortSignal extends EventTarget:
    func init():
        super.init()
        self.aborted = false
        self.reason = null
        self.dependents = []

    func _abort(reason):
        if self.aborted:
            return
        self.aborted = true
        self.reason = reason if reason != null else _err.ErrorValue(_err.ABORT, "signal is aborted without reason")
        _et.dispatch(self, _ev.Event("abort"), true)
        for d in self.dependents:
            d._abort(self.reason)

    func throw_if_aborted():
        if self.aborted:
            r := self.reason
            name := _err.ABORT
            msg := "opération annulée"
            try:
                name = r.name
                msg = r.message
            catch e:
                msg = str(r)
            raise(name, msg)

    # Rappel quand le signal est annulé (immédiat s'il l'est déjà).
    func on_abort(fn):
        if self.aborted:
            fn(self.reason)
        else:
            sig := self
            self.add_event_listener("abort", (e) => fn(sig.reason), {"once": true})

class AbortController:
    func init():
        self.signal = AbortSignal()

    func abort(reason=null):
        self.signal._abort(reason)

# Signal déjà annulé.
func abort(reason=null):
    s := AbortSignal()
    s._abort(reason)
    return s

# Signal annulé (TimeoutError) après ms millisecondes de la boucle.
func timeout(loop, ms):
    s := AbortSignal()
    loop.set_timeout(() => s._abort(_err.ErrorValue(_err.TIMEOUT, "signal timed out")), ms)
    return s

# Signal annulé dès que l'un des signaux l'est (avec sa raison).
func any(signals):
    s := AbortSignal()
    for x in signals:
        if x.aborted:
            s._abort(x.reason)
            return s
    for x in signals:
        append(x.dependents, s)
    return s

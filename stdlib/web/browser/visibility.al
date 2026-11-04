# ALEX STANDARD LIBRARY — web.browser.visibility
#
# Visibilité et cycle de vie de la page : document.visibility_state / hidden, « visibilitychange » sur le
# document, pagehide / pageshow (persisted), freeze / resume, focus / blur de la fenêtre — pour simuler un
# onglet passé en arrière-plan, une fenêtre réduite ou une page mise en cache.
#
#   use web.browser.visibility as vis
#   pv := vis.PageVisibility(document, window)
#   pv.hide()                          # visibilitychange : hidden
#   document.visibility_state          # hidden
#   pv.show()                          # visible
#   pv.freeze(); pv.resume()
#   pv.page_hide(true)                 # pagehide persisted=true (mise en cache)
#
# Erreurs : aucune.

from core use len, type
use web.dom.event as _ev
use web.dom.event_target as _et
from web.dom.event use Event

const VISIBLE := "visible"
const HIDDEN := "hidden"

class PageTransitionEvent extends Event:
    func init(event_type, persisted=false):
        super.init(event_type)
        self.persisted = persisted

class PageVisibility:
    func init(document, window=null):
        self.document = document
        self.window = window
        self.frozen = false
        self.transitions = []          # historique des états (visible / hidden / frozen / resumed)

    func state():
        return self.document.visibility_state

    func is_hidden():
        return self.document.hidden

    func _set(state):
        d := self.document
        if d.visibility_state == state:
            return
        d.visibility_state = state
        d.hidden = state == HIDDEN
        self.transitions = self.transitions + [state]
        _et.dispatch(d, _ev.Event("visibilitychange", true), true)

    func hide():
        self._set(HIDDEN)
        if self.window != null:
            _et.dispatch(self.window, _ev.Event("blur"), true)

    func show():
        self._set(VISIBLE)
        if self.window != null:
            _et.dispatch(self.window, _ev.Event("focus"), true)

    func toggle():
        if self.is_hidden():
            self.show()
        else:
            self.hide()

    func freeze():
        if self.frozen:
            return
        self.frozen = true
        self.transitions = self.transitions + ["frozen"]
        _et.dispatch(self.document, _ev.Event("freeze", true), true)

    func resume():
        if not self.frozen:
            return
        self.frozen = false
        self.transitions = self.transitions + ["resumed"]
        _et.dispatch(self.document, _ev.Event("resume", true), true)

    func page_hide(persisted=false):
        if self.window != null:
            _et.dispatch(self.window, PageTransitionEvent("pagehide", persisted), true)
        self._set(HIDDEN)

    func page_show(persisted=false):
        self._set(VISIBLE)
        if self.window != null:
            _et.dispatch(self.window, PageTransitionEvent("pageshow", persisted), true)

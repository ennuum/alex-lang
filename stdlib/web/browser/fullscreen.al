# ALEX STANDARD LIBRARY — web.browser.fullscreen
#
# Plein écran : request_fullscreen(élément) / exit_fullscreen() en promesses, document.fullscreen_element,
# pseudo-classe :fullscreen (état de l'élément), événements fullscreenchange / fullscreenerror (sur
# l'élément, bouillonnant jusqu'au document), exigence d'activation utilisateur et de permission, fenêtre
# agrandie à la taille de l'écran pendant le plein écran.
#
#   use web.browser.fullscreen as fs
#   mgr := fs.FullscreenManager(document, window, loop)
#   mgr.request(video).wait()            # vidéo en plein écran
#   mgr.element() == video               # true ; video.matches(":fullscreen")
#   mgr.exit().wait()
#   mgr.require_user_activation = true   # refus sans geste utilisateur (TypeError comme Chrome)
#
# Erreurs (rejets) : TypeError (élément non connecté, pas d'activation utilisateur, permission refusée).

from core use len, type
use web.browser.browser_errors as _err
use web.browser.timers as _tm
use web.dom.event as _ev
use web.dom.event_target as _et

class FullscreenManager:
    func init(document, window=null, loop=null):
        self.document = document
        self.window = window
        self.loop = loop if loop != null else _tm.default_loop()
        self.current = null
        self.enabled = true
        self.require_user_activation = false
        self.user_activation = false      # vrai juste après un geste utilisateur (le navigateur le règle)
        self.saved_size = null
        document.fullscreen_element = null
        document.fullscreen_enabled = true

    func element():
        return self.current

    func _fire(el, kind):
        target := el if el != null and el.is_connected() else self.document
        _et.dispatch(target, _ev.Event(kind, true, false, true), true)

    func request(element, options=null):
        p := _tm.Promise(self.loop)
        why := null
        if not self.enabled:
            why = "plein écran désactivé"
        elif element == null or not element.is_connected():
            why = "élément non connecté au document"
        elif self.require_user_activation and not self.user_activation:
            why = "activation utilisateur requise"
        if why != null:
            self._fire(element, "fullscreenerror")
            p.reject(_err.ErrorValue(_err.TYPE, "request_fullscreen : " + why))
            return p
        old := self.current
        if old != null:
            old.set_state("fullscreen", false)
        self.current = element
        element.set_state("fullscreen", true)
        self.document.fullscreen_element = element
        if self.window != null and self.saved_size == null:
            self.saved_size = (self.window.inner_width, self.window.inner_height)
            self.window.resize(self.window.screen["width"], self.window.screen["height"])
        m := self
        self.loop.queue_task(() => m._fire(element, "fullscreenchange"))
        p.resolve(null)
        return p

    func exit():
        p := _tm.Promise(self.loop)
        el := self.current
        if el == null:
            p.reject(_err.ErrorValue(_err.TYPE, "exit_fullscreen : le document n'est pas en plein écran"))
            return p
        el.set_state("fullscreen", false)
        self.current = null
        self.document.fullscreen_element = null
        if self.window != null and self.saved_size != null:
            self.window.resize(self.saved_size[0], self.saved_size[1])
            self.saved_size = null
        m := self
        self.loop.queue_task(() => m._fire(el, "fullscreenchange"))
        p.resolve(null)
        return p

    func is_fullscreen():
        return self.current != null

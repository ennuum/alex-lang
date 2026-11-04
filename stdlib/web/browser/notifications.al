# ALEX STANDARD LIBRARY — web.browser.notifications
#
# Notifications système (API Notification) : permission par origine (request_permission en promesse,
# réponse simulée de l'utilisateur), création d'une notification (titre, corps, icône, étiquette — une
# notification de même étiquette remplace la précédente —, données, silence, interaction requise),
# événements show / click / close / error, fermeture automatique simulée ; centre de notifications
# consultable par les tests.
#
#   use web.browser.notifications as nt
#   center := nt.NotificationCenter(permissions, "https://exemple.org", loop)
#   center.request_permission().wait()          # "granted" si l'utilisateur simulé accepte
#   n := center.notify("Nouveau message", {"body": "Ada vous a écrit", "tag": "msg"})
#   n.add_event_listener("click", (e) => print("ouverte"))
#   center.visible()                            # notifications affichées
#   center.click(n)                             # simule le clic de l'utilisateur
#
# Erreurs : TypeError (permission non accordée : la notification émet « error » et n'est pas affichée).

from core use len, type
from collections use append
use web.browser.browser_errors as _err
use web.browser.timers as _tm
use web.browser.permissions as _perm
use web.dom.event as _ev
use web.dom.event_target as _et
from web.dom.event_target use EventTarget

func _opt(o, k, d):
    if o != null and k in o:
        return o[k]
    return d

class Notification extends EventTarget:
    func init(title, options=null, center=null):
        super.init()
        self.title = str(title)
        self.body = _opt(options, "body", "")
        self.icon = _opt(options, "icon", "")
        self.badge = _opt(options, "badge", "")
        self.image = _opt(options, "image", "")
        self.tag = _opt(options, "tag", "")
        self.data = _opt(options, "data", null)
        self.lang = _opt(options, "lang", "")
        self.dir = _opt(options, "dir", "auto")
        self.silent = _opt(options, "silent", false)
        self.require_interaction = _opt(options, "require_interaction", false)
        self.renotify = _opt(options, "renotify", false)
        self.actions = _opt(options, "actions", [])
        self.timestamp = center.loop.now() if center != null else 0
        self.center = center
        self.shown = false
        self.closed = false

    func close():
        if self.closed:
            return
        self.closed = true
        if self.center != null:
            self.center._remove(self)
        _et.dispatch(self, _ev.Event("close"), true)

class NotificationCenter:
    # auto_close_ms : fermeture automatique simulée (null : jamais) sauf require_interaction.
    func init(permissions, origin, loop=null, auto_close_ms=null):
        self.permissions = permissions
        self.origin = origin
        self.loop = loop if loop != null else _tm.default_loop()
        self.auto_close_ms = auto_close_ms
        self.shown = []
        self.history = []

    func permission():
        st := self.permissions.state(self.origin, "notifications")
        return "default" if st == _perm.PROMPT else st

    func request_permission():
        st := self.permissions.request(self.origin, "notifications")
        return _tm.resolved(self.loop, "default" if st == _perm.PROMPT else st)

    func notify(title, options=null):
        n := Notification(title, options, self)
        if self.permission() != _perm.GRANTED:
            self.loop.queue_task(() => _et.dispatch(n, _ev.Event("error"), true))
            return n
        if n.tag != "":
            for old in self.shown:
                if old.tag == n.tag:
                    self._remove(old)
                    old.closed = true
        self.shown = self.shown + [n]
        append(self.history, n)
        n.shown = true
        self.loop.queue_task(() => _et.dispatch(n, _ev.Event("show"), true))
        if self.auto_close_ms != null and not n.require_interaction:
            self.loop.set_timeout(() => n.close(), self.auto_close_ms)
        return n

    func _remove(n):
        kept := []
        for x in self.shown:
            if x != n:
                append(kept, x)
        self.shown = kept

    func visible():
        return self.shown

    # Simule un clic de l'utilisateur sur la notification.
    func click(n, action=null):
        e := _ev.Event("click", false, true)
        e.action = action
        _et.dispatch(n, e, true)

    func close_all():
        for n in self.shown:
            n.close()

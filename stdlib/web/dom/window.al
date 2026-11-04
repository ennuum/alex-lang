# ALEX STANDARD LIBRARY — web.dom.window
#
# Window : la fenêtre d'un document — dimensions, densité de pixels, défilement, préférences (thème, réduction
# des animations, pointeur), match_media (MediaQueryList vivante avec événements change, évaluée par
# web.css.media_query), get_computed_style (cascade de web.css.stylesheet : feuille de l'agent utilisateur,
# éléments <style>, feuilles ajoutées), redimensionnement et défilement avec événements et recalcul des
# observateurs, boîtes de dialogue simulées. web.browser y branche timers, location, history, navigator,
# stockage et console.
#
#   use web.dom.window as wn
#   w := wn.Window(document, 390, 844, 3)          # mobile
#   mq := w.match_media("(max-width: 600px)")
#   mq.matches()                                   # true
#   mq.add_event_listener("change", (e) => print(e.matches))
#   w.resize(1024, 768)                            # resize + change (false)
#   w.get_computed_style(element).get("display")
#   w.scroll_to(0, 400)
#   w.confirm_answers = [false]; w.confirm("Supprimer ?")   # false
#
# Erreurs : NotSupportedError (API du navigateur non branchée : timers, stockage…).

from core use len, type
from collections use append, pop
use string as _s
use web.dom.dom_errors as _err
use web.dom.event as _ev
use web.dom.event_target as _et
use web.css.media_query as _mq
use web.css.stylesheet as _sheet
use web.css.css_parser as _cssp
from web.dom.event_target use EventTarget
from web.dom.event use Event

class MediaQueryListEvent extends Event:
    func init(media, matches):
        super.init("change")
        self.media = media
        self.matches = matches

class MediaQueryList extends EventTarget:
    func init(window, query):
        super.init()
        self.window = window
        self.media = _mq.parse_lenient(query).to_css()
        self.query = query
        self.last = self.matches()

    func matches():
        return _mq.matches(self.query, self.window.environment())

    # API historique : add_listener(fn) / remove_listener(fn).
    func add_listener(fn):
        self.add_event_listener("change", fn)

    func remove_listener(fn):
        self.remove_event_listener("change", fn)

    func _reevaluate():
        now := self.matches()
        if now != self.last:
            self.last = now
            _et.dispatch(self, MediaQueryListEvent(self.media, now), true)

class Window extends EventTarget:
    func init(document=null, width=1280, height=720, dpr=1, color_scheme="light"):
        super.init()
        self.document = document
        self.inner_width = width
        self.inner_height = height
        self.outer_width = width
        self.outer_height = height + 80
        self.device_pixel_ratio = dpr
        self.screen = {"width": width, "height": height, "avail_width": width, "avail_height": height, "color_depth": 24, "pixel_depth": 24, "orientation": "portrait-primary" if height >= width else "landscape-primary"}
        self.scroll_x = 0
        self.scroll_y = 0
        self.name = ""
        self.closed = false
        self.color_scheme = color_scheme
        self.reduced_motion = "no-preference"
        self.hover = "hover" if dpr < 2 else "none"
        self.pointer = "fine" if dpr < 2 else "coarse"
        self.media_type = "screen"
        self.media_lists = []
        self.alerts = []                # messages de alert / confirm / prompt affichés
        self.confirm_answers = []       # réponses à donner à confirm() (vrai par défaut)
        self.prompt_answers = []        # réponses à donner à prompt() (null par défaut)
        self.print_requests = 0
        # branchés par web.browser
        self.timers = null
        self.location = null
        self.history = null
        self.navigator = null
        self.local_storage = null
        self.session_storage = null
        self.console = null
        self.performance = null
        self._sheet_cache = {}
        if document != null:
            document.default_view = self

    # Environnement des requêtes média (web.css.media_query.Environment).
    func environment():
        e := _mq.Environment(self.inner_width, self.inner_height, self.media_type, self.device_pixel_ratio, self.color_scheme, self.reduced_motion, self.hover, self.pointer)
        return e

    func match_media(query):
        m := MediaQueryList(self, query)
        append(self.media_lists, m)
        return m

    func _media_changed():
        for m in self.media_lists:
            m._reevaluate()

    func resize(width, height):
        self.inner_width = width
        self.inner_height = height
        self.outer_width = width
        self.outer_height = height + 80
        self.screen["orientation"] = "portrait-primary" if height >= width else "landscape-primary"
        _et.dispatch(self, _ev.Event("resize"), true)
        self._media_changed()
        if self.document != null:
            self.document.layout_changed()

    func set_color_scheme(scheme):
        self.color_scheme = scheme
        self._media_changed()

    func set_reduced_motion(on):
        self.reduced_motion = "reduce" if on else "no-preference"
        self._media_changed()

    func set_media_type(media_type):
        self.media_type = media_type
        self._media_changed()

    func scroll_to(x, y):
        if x == self.scroll_x and y == self.scroll_y:
            return
        self.scroll_x = x if x > 0 else 0
        self.scroll_y = y if y > 0 else 0
        if self.document != null:
            _et.dispatch(self.document, _ev.Event("scroll", true), true)
            self.document.layout_changed()
        else:
            _et.dispatch(self, _ev.Event("scroll"), true)

    func scroll_by(dx, dy):
        self.scroll_to(self.scroll_x + dx, self.scroll_y + dy)

    # ------------------------------------------------------------ styles

    func _style_sheets():
        out := [_sheet.default_stylesheet()]
        if self.document == null:
            return out
        for st in self.document.query_selector_all("style").to_list():
            media := st.get_attribute("media")
            if media != null and not _mq.matches(media, self.environment()):
                continue
            text := st.text_content()
            if not (text in self._sheet_cache):
                self._sheet_cache[text] = _cssp.parse(text)
            append(out, self._sheet_cache[text])
        for sh in self.document.style_sheets:
            append(out, sh)
        return out

    # Style calculé (web.css.stylesheet.ComputedStyle) ; pseudo non pris en charge (ignoré).
    func get_computed_style(element, pseudo=null):
        return _sheet.compute(element, self._style_sheets(), self.environment())

    # ------------------------------------------------------------ boîtes de dialogue simulées

    func alert(message=""):
        append(self.alerts, ("alert", str(message)))

    func confirm(message=""):
        append(self.alerts, ("confirm", str(message)))
        if len(self.confirm_answers) > 0:
            return pop(self.confirm_answers, 0)
        return true

    func prompt(message="", default=""):
        append(self.alerts, ("prompt", str(message)))
        if len(self.prompt_answers) > 0:
            return pop(self.prompt_answers, 0)
        return null

    func print_page():
        self.print_requests += 1
        _et.dispatch(self, _ev.Event("beforeprint"), true)
        _et.dispatch(self, _ev.Event("afterprint"), true)

    # ------------------------------------------------------------ API branchées par web.browser

    func _require(api, name):
        if api == null:
            _err.not_supported("Window." + name, "API non disponible hors de web.browser")
        return api

    func set_timeout(fn, delay=0):
        return self._require(self.timers, "set_timeout").set_timeout(fn, delay)

    func clear_timeout(id):
        self._require(self.timers, "clear_timeout").clear_timeout(id)

    func set_interval(fn, delay=0):
        return self._require(self.timers, "set_interval").set_interval(fn, delay)

    func clear_interval(id):
        self._require(self.timers, "clear_interval").clear_interval(id)

    func queue_microtask(fn):
        self._require(self.timers, "queue_microtask").queue_microtask(fn)

    func request_animation_frame(fn):
        return self._require(self.timers, "request_animation_frame").request_animation_frame(fn)

    func cancel_animation_frame(id):
        self._require(self.timers, "cancel_animation_frame").cancel_animation_frame(id)

    func get_the_parent(event):
        return null

    func close():
        self.closed = true

    func __str__():
        return "<Window " + str(self.inner_width) + "×" + str(self.inner_height) + ">"

func window_for(document, width=1280, height=720):
    return Window(document, width, height)

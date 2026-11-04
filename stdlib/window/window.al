# ALEX STANDARD LIBRARY — window
#
# Fenêtres d'application : création, titre, taille, POSITION, ÉTAT (normale, réduite, agrandie, plein écran),
# style (redimensionnable, décorée, toujours devant, opacité, tailles min / max), focus, curseur, événements
# (clavier et souris typés, gestes), pixels bruts (rendu logiciel, graphics), capture d'écran.
#
#   use window
#   w := window.Window("Mon appli", 800, 600, {"min_size": (400, 300)})
#   w.on("key", (e) => print("touche", e.combo()))          # keyboard.key_event.KeyEvent
#   w.on("click", (g) => print("clic", g.x, g.y))           # geste (mouse.pointer)
#   w.on("close", () => print("fermée"))
#   w.show()
#   w.center()
#   w.maximize()
#   while w.is_open():
#       w.dispatch_events()                                 # ou : w.run() / await w.run_async()
#
# Événements (on) : les types bruts de la fenêtre (key_down, key_up, pointer_down, pointer_up, pointer_move,
# pointer_leave, wheel, resize, move, state, focus_in, focus_out, close, close_request, drop, shortcut...) reçoivent
# le dict d'origine ; « key » reçoit un KeyEvent, « mouse » un MouseEvent, et les gestes « click », « double_click »,
# « drag_start », « drag », « drag_end » un MouseEvent produit par mouse.pointer. « * » reçoit tous les dicts.
# Les fenêtres partagent l'écran et la file du système : window.window_manager en gère plusieurs.
#
# Backends : X11 (Linux), Win32, et « headless » (ALEX_UI_BACKEND=headless : fenêtres virtuelles, pour les tests
# et les serveurs ; les déplacements, états et focus y sont immédiats et produisent leurs événements).
#
# Erreurs : IoError (pas d'affichage, fenêtre fermée), ArgumentError (dimensions, état, réglages invalides),
# TypeError.

from core use len, type, arity
from collections use append, contains_key, keys
use _native_ui as _ui
use asyncio
use os as _os
use event.event_emitter as _ee
use keyboard as _kbd
use keyboard.key as _key
use keyboard.key_event as _ke
use mouse.mouse_event as _me
use mouse.pointer as _pt
use window.window_state as _ws

func available():
    return _ui.available()

func backend():
    return _ui.backend()

func _need_size(fn, w, h):
    if type(w) != "int" or type(h) != "int":
        raise("TypeError", "window." + fn + " : dimensions entières attendues")
    if w <= 0 or h <= 0:
        raise("ArgumentError", "window." + fn + " : dimensions strictement positives attendues")

func _opt(options, k, fallback):
    if options != null and contains_key(options, k):
        return options[k]
    return fallback

class Window:
    # options (dict, facultatif) : resizable, decorated, topmost, opacity, min_size, max_size, x, y, state,
    # cursor, visible (true : montrée tout de suite), confirm_close.
    func init(title="Alex", width=800, height=600, options=null):
        if type(title) != "str":
            raise("TypeError", "window.Window : titre (str) attendu")
        _need_size("Window", width, height)
        if options != null and type(options) != "dict":
            raise("TypeError", "window.Window : options (dict) attendues")
        self.handle = _ui.window_create(title, width, height, _opt(options, "resizable", true))
        self.id = self.handle
        self.keyboard = _kbd.Keyboard()
        self.pointer = _pt.Pointer(4, 0.4, 4)
        self.events = _ee.EventEmitter(1000)
        self._open = true
        self._idle = false          # headless : file vidée (fermeture synthétisée par le backend)
        self._canvas = null
        self._hints = [_opt(options, "resizable", true), _opt(options, "decorated", true), _opt(options, "topmost", false),
                       _opt(options, "opacity", 1.0), _opt(options, "min_size", null), _opt(options, "max_size", null)]
        if options != null:
            if contains_key(options, "decorated") or contains_key(options, "topmost") or contains_key(options, "opacity") or contains_key(options, "min_size") or contains_key(options, "max_size"):
                self._apply_hints()
            if contains_key(options, "x") or contains_key(options, "y"):
                self.move(_opt(options, "x", 0), _opt(options, "y", 0))
            if contains_key(options, "cursor"):
                self.set_cursor(options["cursor"])
            if contains_key(options, "confirm_close"):
                self.confirm_close(options["confirm_close"])
        if _opt(options, "visible", false):
            self.show()
        if options != null and contains_key(options, "state") and options["state"] != "normal":
            self.set_state(options["state"])

    func _h():
        if not self._open:
            raise("IoError", "window : fenêtre fermée")
        return self.handle

    # ---- visibilité ----
    func show():
        _ui.window_show(self._h())
        return self

    func hide():
        _ui.window_hide(self._h())
        return self

    func close():
        if self._open:
            if self._canvas != null:
                _ui.canvas_destroy(self._canvas)
                self._canvas = null
            _ui.window_close(self.handle)
            self._open = false
            self.events.emit("closed")

    func is_open():
        if not self._open:
            return false
        return self.info()["alive"]

    func visible():
        return self.info()["visible"]

    # La croix ne ferme plus la fenêtre : un événement « close_request » est émis, l'application décide.
    func confirm_close(enabled=true):
        _ui.window_set_confirm_close(self._h(), enabled)
        return self

    # ---- titre, taille, position ----
    func title():
        return self.info()["title"]

    func set_title(t):
        _ui.window_set_title(self._h(), t)
        return self

    # (largeur, hauteur) de la zone cliente.
    func size():
        i := self.info()
        return (i["width"], i["height"])

    func set_size(width, height):
        _need_size("set_size", width, height)
        _ui.window_set_size(self._h(), width, height)
        return self

    func resize(width, height):
        return self.set_size(width, height)

    # (x, y) du coin de la zone cliente sur l'écran.
    func position():
        i := self.info()
        return (i["x"], i["y"])

    func move(x, y):
        _ui.window_set_position(self._h(), x, y)
        return self

    func center():
        i := _ui.screen_info()
        sz := self.size()
        return self.move((i["work_width"] - sz[0]) // 2, (i["work_height"] - sz[1]) // 2)

    # ---- état ----
    func state():
        return self.info()["state"]

    func set_state(state):
        _ws.check(state)
        _ui.window_set_state(self._h(), state)
        return self

    func minimize():
        return self.set_state("minimized")

    func maximize():
        return self.set_state("maximized")

    func fullscreen():
        return self.set_state("fullscreen")

    func restore():
        return self.set_state("normal")

    func toggle_fullscreen():
        if self.state() == "fullscreen":
            return self.restore()
        return self.fullscreen()

    # Instantané (window_state.WindowState) : géométrie et état.
    func snapshot():
        i := self.info()
        return _ws.WindowState(i["x"], i["y"], i["width"], i["height"], i["state"])

    # ---- style ----
    func _apply_hints():
        h := self._hints
        mn := h[4]
        mx := h[5]
        if mn == null:
            mn = (0, 0)
        if mx == null:
            mx = (0, 0)
        _ui.window_set_hints(self._h(), h[0], h[1], h[2], h[3] * 1.0, mn[0], mn[1], mx[0], mx[1])

    # Tous les réglages d'un coup (voir window_style.WindowStyle.apply).
    func set_hints(resizable, decorated, topmost, opacity, min_size, max_size):
        self._hints = [resizable, decorated, topmost, opacity, min_size, max_size]
        self._apply_hints()
        return self

    func set_resizable(v):
        self._hints[0] = v
        self._apply_hints()
        return self

    func set_decorated(v):
        self._hints[1] = v
        self._apply_hints()
        return self

    func set_topmost(v):
        self._hints[2] = v
        self._apply_hints()
        return self

    func set_opacity(v):
        if v < 0 or v > 1:
            raise("ArgumentError", "window.set_opacity : opacité hors de 0..1")
        self._hints[3] = v
        self._apply_hints()
        return self

    func set_min_size(width, height):
        self._hints[4] = (width, height)
        self._apply_hints()
        return self

    func set_max_size(width, height):
        self._hints[5] = (width, height)
        self._apply_hints()
        return self

    # ---- focus, curseur, informations ----
    func focus():
        _ui.window_focus(self._h())
        return self

    func focused():
        return self.info()["focused"]

    func set_cursor(name):
        _ui.window_set_cursor(self._h(), name)
        return self

    func cursor():
        return _ui.window_get_cursor(self._h())

    # dict : x, y, width, height, state, title, visible, alive, focused, resizable, decorated, topmost, opacity,
    # min_width, min_height, max_width, max_height.
    func info():
        return _ui.window_info(self.handle)

    func dpi():
        return _ui.dpi(self._h())

    # ---- pixels et capture ----
    func _ensure_canvas():
        if self._canvas == null:
            self._canvas = _ui.canvas_create(self._h())
        return self._canvas

    # Copie un bloc de pixels RGBA (str de largeur x hauteur x 4 octets) en (x, y) puis l'affiche.
    func draw_pixels(x, y, width, height, rgba):
        c := self._ensure_canvas()
        _ui.canvas_resize(c)
        _ui.canvas_begin(c)
        _ui.canvas_put_pixels(c, x, y, width, height, rgba)
        _ui.canvas_end(c)

    # Image PNG de la fenêtre (contenu composé, widgets compris) ; true si écrite.
    func screenshot(path):
        return _ui.window_screenshot(self._h(), path)

    # ---- événements ----
    func on(event_type, fn):
        return self.events.on(event_type, fn)

    func once(event_type, fn):
        return self.events.once(event_type, fn)

    func off(event_type, fn):
        return self.events.off(event_type, fn)

    # Traite un dict d'événement : états clavier / pointeur, puis gestionnaires. Renvoie l'événement.
    func _process(ev):
        t := ev["type"]
        self._idle = false
        if t == "close":
            self._open = false
        self.events.emit("*", ev)
        self.events.emit(t, ev)
        k := self.keyboard.feed_window_event(ev)
        if k != null:
            self.events.emit("key", k)
        m := _me.from_window_event(ev)
        if m != null:
            for g in self.pointer.feed(m):
                if g == m:
                    self.events.emit("mouse", g)
                else:
                    self.events.emit(g.kind, g)
        return ev

    # Prochain événement (dict, traité : états et gestionnaires), ou null s'il n'y en a pas.
    func poll():
        if not self._open:
            return null
        ev := _ui.window_poll(self.handle)
        if ev == null:
            return null
        if ev["type"] == "close" and _ui.window_info(self.handle)["alive"]:
            # Backend headless : personne ne fermera la fenêtre ; le backend signale que sa file est vide par un
            # « close » synthétique. La fenêtre reste ouverte ; les boucles run() s'arrêtent (idle()).
            self._idle = true
            return null
        return self._process(ev)

    # Tous les événements en attente (traités).
    func poll_all(limit=1000):
        out := []
        while len(out) < limit:
            ev := self.poll()
            if ev == null:
                break
            append(out, ev)
        return out

    # Vrai sous le backend headless quand la file d'événements a été vidée (rien ne viendra plus de l'extérieur).
    func idle():
        return self._idle

    # Traite les événements en attente ; renvoie leur nombre.
    func dispatch_events():
        return len(self.poll_all())

    # Boucle bloquante jusqu'à la fermeture ; frame() (facultatif) est appelée à chaque tour (~fps).
    func run(frame=null, fps=60):
        self.show()
        period := 1.0 / fps
        while self.is_open() and not self._idle:
            self.dispatch_events()
            if frame != null:
                frame()
            _os.sleep(period)

    # Même boucle, en tâche async (les autres tâches avancent) ; futur terminé à la fermeture.
    func run_async(frame=null, fps=60):
        self.show()
        return _run_async(self, frame, fps)

    # Futur du prochain événement de ce type (dict ; KeyEvent / MouseEvent pour key / mouse / gestes).
    func wait_for(event_type, timeout=null):
        return _wait_for(self, event_type, timeout)

    # ---- automatisation (tests, démonstrations) ----
    func inject_key(name, mods=0):
        vk := _key.code(name)
        if vk == null:
            raise("ArgumentError", "window.inject_key : touche sans code virtuel '" + str(name) + "'")
        _ui.inject_key(self._h(), vk, mods)

    func inject_key_up(name, mods=0):
        vk := _key.code(name)
        if vk == null:
            raise("ArgumentError", "window.inject_key_up : touche sans code virtuel '" + str(name) + "'")
        _ui.inject_key_up(self._h(), vk, mods)

    # Appui puis relâchement.
    func inject_press(name, mods=0):
        self.inject_key(name, mods)
        self.inject_key_up(name, mods)

    func inject_text(text):
        _ui.inject_text(self._h(), text)

    # kind : move, down, up, click, leave ; button : 1 gauche, 2 droit, 3 milieu.
    func inject_mouse(kind, x, y, button=1, mods=0):
        _ui.inject_mouse(self._h(), kind, x, y, button, mods)

    func inject_wheel(x, y, dx, dy, mods=0):
        _ui.inject_wheel(self._h(), x, y, dx, dy, mods)

    func inject_close():
        _ui.inject_close(self._h())

async func _run_async(win, frame, fps):
    period := 1.0 / fps
    while win.is_open() and not win.idle():
        win.dispatch_events()
        if frame != null:
            r := frame()
            if asyncio.is_future(r):
                await r
        await asyncio.sleep(period)
    return null

async func _wait_for(win, event_type, timeout):
    p := asyncio.future()
    off := win.events.once(event_type, (x) => asyncio.resolve(p, x))
    start := asyncio.now()
    while not asyncio.done(p):
        if not win.is_open() and event_type != "close" and event_type != "closed":
            off()
            raise("IoError", "window.wait_for : fenêtre fermée")
        if timeout != null and asyncio.now() - start >= timeout:
            off()
            raise("TimeoutError", "window.wait_for(" + event_type + ") : délai dépassé")
        win.dispatch_events()
        if asyncio.done(p):
            break
        await asyncio.sleep(0.005)
    return await p

func create(title="Alex", width=800, height=600, options=null):
    return Window(title, width, height, options)

# Handles des fenêtres ouvertes (toutes, y compris celles créées par ui).
func handles():
    return _ui.window_list()

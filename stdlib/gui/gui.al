# ALEX STANDARD LIBRARY — gui
#
# Applications dans une fenêtre. La vue est décrite avec ui.view (les mêmes composants que tui.run dans le
# terminal) et dessinée sur un canvas (Windows : Win32/Direct2D ; Linux : X11 ; partout : « headless »,
# hors écran, pour les tests et les captures).
#
#   use ui.view as v
#   use gui
#   etat := {"n": 0}
#   func plus():
#       etat["n"] += 1
#   func vue():
#       return v.column([v.text("Valeur : " + str(etat["n"])), v.button("+1", plus)], padding=2)
#   gui.run(vue, "Compteur", 480, 320)
#
# Clavier : Tab / Maj+Tab, flèches, Entrée, Espace, Échap, F10 (menus), Ctrl+Q pour quitter ; souris : clics,
# glisser, molette, survol. La croix de la fenêtre ferme l'application.
#
# Tests : TestApp(vue, largeur, hauteur) (backend headless : ALEX_UI_BACKEND=headless) pilote l'application
# avec de vrais événements de fenêtre (press, type, click, wheel) et enregistre des captures (screenshot).

from core use len, type, to_int
from collections use contains_key
use string as _s
use _native_ui as _ui
use ui.view.runtime as _rt
use gui.surface as _sf

# Vrai si une fenêtre peut s'ouvrir (affichage disponible ou backend headless).
func available():
    return _ui.available()

func backend():
    return _ui.backend()

# Taille (px, 8 à 40) de la police à chasse fixe : éditeur de code, consoles ; effet immédiat, même fenêtre ouverte.
func set_code_font_size(px):
    _sf.set_mono_size(px)

func code_font_size():
    return _sf.mono_size()

# Taille (px, 10 à 32 ; 14 par défaut) de la police de l'interface : menus, libellés, listes, onglets, dialogues ;
# hauteurs de ligne et de menu ajustées ; effet immédiat, même fenêtre ouverte.
func set_ui_font_size(px):
    _sf.set_ui_size(px)

func ui_font_size():
    return _sf.ui_size()

func _window(title, width, height, resizable):
    try:
        return _ui.window_create(str(title), width, height, resizable)
    catch e:
        raise("IoError", "gui : impossible d'ouvrir une fenêtre (" + e.message + ")")

# Lance l'application ; revient quand la fenêtre est fermée, ou par ui.view.quit() / Ctrl+Q.
#   on_key(touche), on_tick(temps) toutes les tick secondes, theme "dark" / "light" / dict de rôles.
func run(view, title="Application Alex", width=900, height=600, theme="dark", on_key=null, on_tick=null, tick=null, resizable=true, quit_keys=null):
    if quit_keys == null:
        quit_keys = ["ctrl+q"]
    win := _window(title, width, height, resizable)
    s := _sf.Surface(win, width, height, theme)
    app := _rt.App(view, s, on_key, on_tick, tick, quit_keys)
    return app.run()

# Touches nommées → code de touche et modificateurs de la fenêtre (injection).
const _NAMED := {"backspace": 8, "tab": 9, "enter": 13, "escape": 27, "space": 32, "page_up": 33, "page_down": 34, "end": 35, "home": 36, "left": 37, "up": 38, "right": 39, "down": 40, "insert": 45, "delete": 46, "f1": 112, "f2": 113, "f3": 114, "f4": 115, "f5": 116, "f6": 117, "f7": 118, "f8": 119, "f9": 120, "f10": 121, "f11": 122, "f12": 123}

class TestApp:
    func init(view, width=900, height=600, theme="dark", on_key=null):
        self.win = _window("Test ui.view", width, height, true)
        self.surface = _sf.Surface(self.win, width, height, theme)
        self.surface.virtual = true
        self.app = _rt.App(view, self.surface, on_key, null, null, ["ctrl+q"])
        self.app.running = true
        _rt.set_current(self.app)
        self.surface.start()
        self.app.render()

    func step():
        _rt.set_current(self.app)
        return self.app.step()

    # Touche par son nom : « enter », « tab », « shift+tab », « ctrl+s », « down », « a »...
    func press(name, times=1):
        i := 0
        while i < times:
            self._key(name)
            i += 1
        return self.step()

    func _key(name):
        if name == "+":
            _ui.inject_text(self.win, "+")
            return null
        parts := _s.split(name, "+")
        mods := 0
        base := parts[len(parts) - 1]
        k := 0
        while k < len(parts) - 1:
            if parts[k] == "ctrl":
                mods = mods | 2
            elif parts[k] == "alt":
                mods = mods | 1
            elif parts[k] == "shift":
                mods = mods | 4
            k += 1
        if contains_key(_NAMED, base):
            _ui.inject_key(self.win, _NAMED[base], mods)
        elif len(base) == 1 and mods == 0:
            _ui.inject_text(self.win, base)
        elif len(base) == 1:
            code := _s.ord(_s.upper(base)[0])
            _ui.inject_key(self.win, code, mods)
        else:
            raise("ArgumentError", "gui.TestApp : touche inconnue '" + name + "'")

    func type(text):
        _ui.inject_text(self.win, text)
        return self.step()

    func paste(text):
        self.app.handle({"type": "paste", "text": text})
        self.app.render()

    # Centre du composant dont le texte contient target, ou le point (target, y).
    func where(target, y=null):
        if y != null:
            return [to_int(target), to_int(y)]
        k := len(self.surface.drawn) - 1
        while k >= 0:
            d := self.surface.drawn[k]
            if _s.contains(d[0], target):
                return [to_int(d[1] + d[3] / 2), to_int(d[2] + d[4] / 2)]
            k -= 1
        n := self.app.find(target)
        if n == null:
            raise("ArgumentError", "gui.TestApp : « " + str(target) + " » n'est pas affiché")
        return [to_int(n.x + n.w / 2), to_int(n.y + n.h / 2)]

    # Vrai si le texte est dessiné à l'écran (dans un même appel de dessin).
    func contains(text):
        for d in self.surface.drawn:
            if _s.contains(d[0], text):
                return true
        return false

    func click(target, y=null, clicks=1):
        p := self.where(target, y)
        k := 0
        while k < clicks:
            _ui.inject_mouse(self.win, "click", p[0], p[1], 1, 0)
            k += 1
        return self.step()

    func double_click(target, y=null):
        return self.click(target, y, 2)

    func move(target, y=null):
        p := self.where(target, y)
        _ui.inject_mouse(self.win, "move", p[0], p[1], 1, 0)
        return self.step()

    func drag(x0, y0, x1, y1):
        _ui.inject_mouse(self.win, "move", x0, y0, 1, 0)
        _ui.inject_mouse(self.win, "down", x0, y0, 1, 0)
        _ui.inject_mouse(self.win, "move", x1, y1, 1, 0)
        _ui.inject_mouse(self.win, "up", x1, y1, 1, 0)
        return self.step()

    func wheel(target, dy, y=null):
        p := self.where(target, y)
        _ui.inject_wheel(self.win, p[0], p[1], 0, dy, 0)
        return self.step()

    # Nouvelle taille de la fenêtre (comme un redimensionnement par l'utilisateur).
    func resize(width, height):
        _ui.window_set_size(self.win, width, height)
        self.surface.width = width
        self.surface.height = height
        _ui.canvas_resize(self.surface.canvas)
        self.app.handle({"type": "resize", "width": width, "height": height})
        return self.step()

    func screenshot(path):
        return _ui.window_screenshot(self.win, path)

    func find(text):
        return self.app.find(text)

    func focused():
        return self.app.focused()

    func running():
        return self.app.running

    func close():
        self.surface.stop()

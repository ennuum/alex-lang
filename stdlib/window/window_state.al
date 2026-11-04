# ALEX STANDARD LIBRARY — window.window_state
#
# États d'une fenêtre et instantané de sa géométrie (WindowState), avec sauvegarde / restauration (pour rouvrir
# une application là où l'utilisateur l'avait laissée, en restant visible sur l'écran actuel).
#
#   use window.window_state as ws
#   s := fenetre.snapshot()                       # WindowState
#   ws.save(s, "~/.config/mon-appli/fenetre.json")
#   s2 := ws.load("~/.config/mon-appli/fenetre.json")
#   if s2 != null:
#       s2.clamp_to(1920, 1080).apply(fenetre)
#
# Erreurs : ArgumentError (état inconnu), IoError (fichier).

from core use type, len
use string as _str
from collections use contains_key
use json as _json
use os as _os
use file as _file

const NORMAL := "normal"
const MINIMIZED := "minimized"
const MAXIMIZED := "maximized"
const FULLSCREEN := "fullscreen"

func all_states():
    return [NORMAL, MINIMIZED, MAXIMIZED, FULLSCREEN]

func is_valid(state):
    return state == NORMAL or state == MINIMIZED or state == MAXIMIZED or state == FULLSCREEN

func check(state):
    if not is_valid(state):
        raise("ArgumentError", "window_state : état inconnu '" + str(state) + "' (normal, minimized, maximized, fullscreen)")
    return state

func describe(state):
    d := {"normal": "normale", "minimized": "réduite", "maximized": "agrandie", "fullscreen": "plein écran"}
    if contains_key(d, state):
        return d[state]
    return str(state)

class WindowState:
    func init(x=0, y=0, width=800, height=600, state="normal"):
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.state = check(state)

    func to_dict():
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height, "state": self.state}

    # Ramène la fenêtre sur un écran de screen_w x screen_h (taille réduite si besoin, coin visible).
    func clamp_to(screen_w, screen_h, margin=32):
        w := self.width
        h := self.height
        if w > screen_w:
            w = screen_w
        if h > screen_h:
            h = screen_h
        x := self.x
        y := self.y
        if x + w < margin:
            x = 0
        if y + h < margin:
            y = 0
        if x > screen_w - margin:
            x = screen_w - w
        if y > screen_h - margin:
            y = screen_h - h
        if x < 0 and x + w > screen_w:
            x = 0
        if y < 0:
            y = 0
        st := self.state
        if st == MINIMIZED:
            st = NORMAL           # rouvrir réduite surprendrait l'utilisateur
        return WindowState(x, y, w, h, st)

    # Applique à une window.Window : taille et position d'abord (géométrie « normale »), puis l'état.
    func apply(win):
        win.set_size(self.width, self.height)
        win.move(self.x, self.y)
        if self.state != NORMAL:
            win.set_state(self.state)
        return win

    func to_string():
        return "WindowState(" + str(self.x) + ", " + str(self.y) + ", " + str(self.width) + "x" + str(self.height) + ", " + self.state + ")"

func from_dict(d):
    return WindowState(d["x"], d["y"], d["width"], d["height"], d["state"])

func _expand(path):
    if type(path) == "str" and len(path) > 0 and path[0] == '~':
        return _os.home() + _str.substring(path, 1, len(path))
    return path

# Écrit l'état en JSON (dossiers créés au besoin).
func save(state, path):
    p := _expand(path)
    d := _os.dirname(p)
    if d != "" and not _os.exists(d):
        _os.mkdir_all(d)
    _file.write_atomic(p, _json.pretty(state.to_dict()))

# État lu, ou null si le fichier est absent ou invalide.
func load(path):
    p := _expand(path)
    if not _os.exists(p):
        return null
    try:
        return from_dict(_json.parse(_file.read(p)))
    catch e:
        return null

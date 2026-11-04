# ALEX STANDARD LIBRARY — mouse.mouse_event
#
# MouseEvent : mouvement, appui, relâchement, molette, sortie de la fenêtre, clic, double clic, glisser — d'une
# fenêtre (window / ui) ou de la souris brute du noyau (evdev, hardware.mouse : déplacements relatifs).
#
#   use mouse.mouse_event as me
#   e := me.from_window_event(ev)          # ev : dict de window.poll()
#   if e != null and e.kind == "down" and e.button == "left":
#       commencer(e.x, e.y)
#
# kind : move | down | up | wheel | leave | click | double_click | drag_start | drag | drag_end | relative
# button : "left", "right", "middle" (ou null) ; buttons : ensemble des boutons enfoncés (pointer.Pointer).

from core use type
from collections use contains_key
use os as _os

const LEFT := "left"
const RIGHT := "right"
const MIDDLE := "middle"

_BUTTONS := {1: "left", 2: "right", 3: "middle"}

func button_name(n):
    if contains_key(_BUTTONS, n):
        return _BUTTONS[n]
    return null

class MouseEvent:
    func init(kind, x=0, y=0, button=null, mods=0, dx=0.0, dy=0.0, source="program", time=null):
        self.kind = kind
        self.x = x
        self.y = y
        self.button = button
        self.mods = mods
        self.dx = dx              # molette (crans : + droite / + haut) ou déplacement relatif (evdev)
        self.dy = dy
        self.source = source      # "window", "evdev" ou "program"
        self.buttons = []
        self.clicks = 0
        if time == null:
            time = _os.monotonic_time()
        self.time = time

    func is_press():
        return self.kind == "down"

    func is_release():
        return self.kind == "up"

    func position():
        return (self.x, self.y)

    func describe():
        t := self.kind + " (" + str(self.x) + ", " + str(self.y) + ")"
        if self.button != null:
            t = t + " " + self.button
        return t

    func to_dict():
        return {"kind": self.kind, "x": self.x, "y": self.y, "button": self.button, "mods": self.mods, "dx": self.dx,
                "dy": self.dy, "source": self.source}

func _get(d, k, fallback):
    if contains_key(d, k):
        return d[k]
    return fallback

# MouseEvent d'un dict d'événement de fenêtre (pointer_move, pointer_down, pointer_up, pointer_leave, wheel), ou
# null pour un autre type.
func from_window_event(ev):
    if ev == null or type(ev) != "dict" or not contains_key(ev, "type"):
        return null
    t := ev["type"]
    m := {"pointer_move": "move", "pointer_down": "down", "pointer_up": "up", "pointer_leave": "leave", "wheel": "wheel"}
    if not contains_key(m, t):
        return null
    e := MouseEvent(m[t], _get(ev, "x", 0), _get(ev, "y", 0), null, _get(ev, "mods", 0), 0.0, 0.0, "window")
    if t == "pointer_down" or t == "pointer_up":
        e.button = button_name(_get(ev, "button", 0))
    if t == "wheel":
        e.dx = _get(ev, "dx", 0.0)
        e.dy = _get(ev, "dy", 0.0)
    return e

# MouseEvent d'un hardware.mouse.MouseEvent (evdev) : déplacement relatif (kind "relative") et boutons.
func from_evdev(e):
    out := MouseEvent("relative", 0, 0, null, 0, e.dx * 1.0, e.dy * 1.0, "evdev", e.time)
    if e.wheel != 0 or e.hwheel != 0:
        out.kind = "wheel"
        out.dx = e.hwheel * 1.0
        out.dy = e.wheel * 1.0
    out.buttons = [b for b in ["left", "right", "middle"] if contains_key(e.buttons, b) and e.buttons[b]]
    return out

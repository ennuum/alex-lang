# ALEX STANDARD LIBRARY — mouse
#
# La souris : événements d'une fenêtre ou de la souris physique (evdev), suivi du pointeur et gestes (clic,
# double clic, glisser), forme du curseur.
#
#   use mouse
#   p := mouse.pointer()
#   for ev in fenetre.poll_all():
#       for g in p.feed(mouse.from_window_event(ev)):
#           if g.kind == "double_click":
#               ouvrir(g.x, g.y)
#   mouse.set_cursor(fenetre, "pointer")
#   brut := mouse.open_raw()                  # souris physique : déplacements relatifs (droits sur /dev/input)
#   e := brut.read(1.0)
#
# Modules : mouse.mouse_event (MouseEvent), mouse.pointer (Pointer : gestes, régions), mouse.cursor (formes),
# hardware.mouse (périphériques).
#
# Erreurs : HardwareError (souris brute absente ou droits), ArgumentError (curseur inconnu).

use mouse.mouse_event as _me
use mouse.pointer as _pt
use mouse.cursor as _cursor
use hardware.mouse as _hw

const LEFT := "left"
const RIGHT := "right"
const MIDDLE := "middle"

func pointer(drag_threshold=4, double_click_time=0.4):
    return _pt.Pointer(drag_threshold, double_click_time, 4)

func from_window_event(ev):
    return _me.from_window_event(ev)

func set_cursor(window, name):
    _cursor.set(window, name)

func get_cursor(window):
    return _cursor.get(window)

func cursors():
    return _cursor.names()

# Souris physiques (hardware.mouse.Mouse).
func devices():
    return _hw.mice()

func available():
    return _hw.available()

class RawMouse:
    func init(device=null):
        self._r = _hw.open(device)
        self.pointer = _pt.Pointer(4, 0.4, 4)

    # Prochain MouseEvent (relatif ou molette), ou null après timeout secondes ; le pointeur interne cumule les
    # déplacements (pointer.x, pointer.y).
    func read(timeout=null):
        e := self._r.read(timeout)
        if e == null:
            return null
        m := _me.from_evdev(e)
        self.pointer.feed(m)
        return m

    func close():
        self._r.close()

func open_raw(device=null):
    return RawMouse(device)

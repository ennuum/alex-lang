# ALEX STANDARD LIBRARY — hardware.mouse
#
# Souris et pavés tactiles branchés (Linux : /proc/bus/input/devices) et lecture de leurs mouvements, boutons
# et molette au niveau du matériel (/dev/input/eventN). Les mouvements sont RELATIFS (dx, dy en « comptes »
# du capteur) : la position du pointeur à l'écran appartient à l'interface graphique (module ui).
# La lecture exige les droits sur /dev/input (root ou groupe « input »), sinon HardwareError.
#
# Exemple
#   use hardware.mouse as mouse
#   m := mouse.open()
#   e := m.read(5.0)       # MouseEvent : e.dx, e.dy, e.wheel, e.buttons ({"left": true} = appui)
#   m.close()

from core use len, type
from collections use append, contains_key
use string as _s
use hardware._sys as _sys
use hardware._input as _in

class Mouse:
    func init(info):
        self.name = info["name"]
        self.path = null
        if len(info["events"]) > 0:
            self.path = info["events"][0]
        self.phys = info["phys"]
        self.vendor_id = info["vendor"]
        self.product_id = info["product"]
        self.touchpad = false
        if (info["ev"] >> _in.EV_ABS) & 1 == 1 and (info["ev"] >> _in.EV_REL) & 1 != 1:
            self.touchpad = true

    func open():
        return open(self)

func _is_mouse(d):
    for h in d["handlers"]:
        if _s.starts_with(h, "mouse"):
            return true
    return (d["ev"] >> _in.EV_REL) & 1 == 1 and d["rel"] & 3 == 3          # REL_X et REL_Y

# Souris et pavés tactiles présents (list de Mouse) ; [] hors Linux.
func mice():
    return [Mouse(d) for d in _sys.input_devices() if _is_mouse(d)]

func available():
    return len(mice()) > 0

_BUTTONS := {272: "left", 273: "right", 274: "middle", 275: "side", 276: "extra", 277: "forward", 278: "back", 330: "touch"}

class MouseEvent:
    func init(time):
        self.time = time
        self.dx = 0
        self.dy = 0
        self.wheel = 0          # crans de molette (positif : vers le haut)
        self.hwheel = 0         # molette horizontale (positif : vers la droite)
        self.buttons = {}       # bouton -> true (appui) / false (relâchement), pour ceux qui ont changé

    func moved():
        return self.dx != 0 or self.dy != 0

class MouseReader:
    func init(path):
        self.path = path
        self._r = _in.Reader(path, "mouse.open")

    # Prochain rapport du périphérique (MouseEvent : mouvement, boutons et molette depuis le précédent),
    # ou null après timeout secondes.
    func read(timeout=null):
        ev := null
        while true:
            e := self._r.read_event(timeout)
            if e == null:
                return ev
            if ev == null:
                ev = MouseEvent(e.time)
            if e.type == _in.EV_SYN and e.code == 0:
                if ev.moved() or ev.wheel != 0 or ev.hwheel != 0 or len(ev.buttons) > 0:
                    return ev
                ev = null
            elif e.type == _in.EV_REL:
                if e.code == 0:
                    ev.dx += e.value
                elif e.code == 1:
                    ev.dy += e.value
                elif e.code == 8:
                    ev.wheel += e.value
                elif e.code == 6:
                    ev.hwheel += e.value
            elif e.type == _in.EV_KEY and contains_key(_BUTTONS, e.code):
                ev.buttons[_BUTTONS[e.code]] = e.value != 0

    func close():
        self._r.close()

# Ouvre une souris (Mouse, chemin /dev/input/eventN, ou null : la première trouvée).
func open(device=null):
    path := device
    if device == null:
        ms := mice()
        if len(ms) == 0:
            _sys.fail("mouse.open", "aucune souris trouvée")
        path = ms[0].path
    elif type(device) != "str":
        path = device.path
    if path == null:
        _sys.fail("mouse.open", "cette souris n'a pas de nœud /dev/input/event")
    return MouseReader(path)

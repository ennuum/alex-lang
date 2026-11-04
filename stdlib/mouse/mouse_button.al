# ALEX STANDARD LIBRARY — mouse.mouse_button
#
# Boutons de la souris dans tous les systèmes de numérotation, autour d'un nom uniforme (left, right, middle,
# back, forward) :
#   window  numéros des événements de fenêtre (1 gauche, 2 droit, 3 milieu)
#   evdev   codes du noyau Linux (BTN_LEFT = 272 ...)
#   hid     bits du premier octet d'un rapport souris HID USB (bit 0 gauche, 1 droit, 2 milieu, 3 arrière, 4 avant)
#   dom     MouseEvent.button du Web (0 gauche, 1 milieu, 2 droit, 3 arrière, 4 avant) et masque buttons
# ButtonState suit les boutons enfoncés (accords « gauche + droit »), avec inversion pour gaucher.
#
#   use mouse.mouse_button as mb
#   print(mb.from_evdev(273), mb.to_dom("middle"), mb.from_hid_mask(5))     # right 1 [left, middle]
#   s := mb.ButtonState()
#   s.press("left") ; s.press("right")
#   print(s.chord(), s.is_down("left"))            # left+right true
#   s.left_handed = true
#   print(s.logical("left"))                       # right (bouton principal inversé)
#
# Erreurs : ArgumentError (bouton ou code inconnus).

from core use len, type
from collections use append
use string as _s

const LEFT := "left"
const RIGHT := "right"
const MIDDLE := "middle"
const BACK := "back"
const FORWARD := "forward"
const NAMES := ["left", "right", "middle", "back", "forward"]

const WINDOW := {1: "left", 2: "right", 3: "middle", 4: "back", 5: "forward"}
const EVDEV := {272: "left", 273: "right", 274: "middle", 275: "back", 276: "forward", 277: "forward", 278: "back"}
const EVDEV_BY_NAME := {"left": 272, "right": 273, "middle": 274, "back": 275, "forward": 276}
const HID_BITS := {"left": 1, "right": 2, "middle": 4, "back": 8, "forward": 16}
const DOM := {0: "left", 1: "middle", 2: "right", 3: "back", 4: "forward"}
const DOM_BY_NAME := {"left": 0, "middle": 1, "right": 2, "back": 3, "forward": 4}

func normalize(name):
    n := _s.lower(_s.trim(str(name)))
    aliases := {"gauche": "left", "droit": "right", "droite": "right", "milieu": "middle", "molette": "middle",
                "primary": "left", "secondary": "right", "auxiliary": "middle", "arrière": "back", "précédent": "back",
                "avant": "forward", "suivant": "forward", "side": "back", "extra": "forward"}
    if n in aliases:
        n = aliases[n]
    if not (n in NAMES):
        raise("ArgumentError", "bouton de souris inconnu : '" + str(name) + "'")
    return n

func from_window(n):
    if not (n in WINDOW):
        raise("ArgumentError", "numéro de bouton inconnu : " + str(n))
    return WINDOW[n]

func to_window(name):
    n := normalize(name)
    for k in WINDOW:
        if WINDOW[k] == n:
            return k
    return null

func from_evdev(code):
    if not (code in EVDEV):
        raise("ArgumentError", "code evdev de bouton inconnu : " + str(code))
    return EVDEV[code]

func to_evdev(name):
    return EVDEV_BY_NAME[normalize(name)]

func from_dom(n):
    if not (n in DOM):
        raise("ArgumentError", "MouseEvent.button inconnu : " + str(n))
    return DOM[n]

func to_dom(name):
    return DOM_BY_NAME[normalize(name)]

# Boutons d'un masque (HID ou MouseEvent.buttons du Web : mêmes bits).
func from_hid_mask(mask):
    return [n for n in NAMES if mask & HID_BITS[n] != 0]

func to_hid_mask(names):
    m := 0
    for n in names:
        m = m | HID_BITS[normalize(n)]
    return m

class ButtonState:
    func init(left_handed=false):
        self.down = []
        self.left_handed = left_handed
        self.presses = {}

    # Bouton logique : avec left_handed, gauche et droit sont échangés.
    func logical(name):
        n := normalize(name)
        if self.left_handed:
            if n == "left":
                return "right"
            if n == "right":
                return "left"
        return n

    func press(name):
        n := self.logical(name)
        if not (n in self.down):
            append(self.down, n)
        if n in self.presses:
            self.presses[n] += 1
        else:
            self.presses[n] = 1
        return n

    func release(name):
        n := self.logical(name)
        self.down = [b for b in self.down if b != n]
        return n

    func is_down(name):
        return normalize(name) in self.down

    func any_down():
        return len(self.down) > 0

    # Accord des boutons enfoncés, dans l'ordre canonique (« left+right »).
    func chord():
        return _s.join("+", [n for n in NAMES if n in self.down])

    func mask():
        return to_hid_mask(self.down)

    # Applique un MouseEvent (mouse.mouse_event) down / up.
    func feed(e):
        if e == null or e.button == null:
            return self
        if e.kind == "down":
            self.press(e.button)
        elif e.kind == "up":
            self.release(e.button)
        return self

    # Applique un masque HID complet (rapport souris) ; [appuyés, relâchés].
    func feed_hid_mask(mask):
        now := from_hid_mask(mask)
        pressed := [b for b in now if not (b in self.down)]
        released := [b for b in self.down if not (b in now)]
        self.down = now
        for b in pressed:
            if b in self.presses:
                self.presses[b] += 1
            else:
                self.presses[b] = 1
        return [pressed, released]

    func reset():
        self.down = []

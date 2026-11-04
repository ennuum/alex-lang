# ALEX STANDARD LIBRARY — web.dom.mouse_event
#
# MouseEvent (et WheelEvent) : coordonnées client / page / écran / relatives à la cible (offset), bouton et
# boutons enfoncés, modificateurs, élément associé (related_target), nombre de clics (detail), molette.
#
#   use web.dom.mouse_event as me
#   e := me.MouseEvent("click", {"client_x": 10, "client_y": 20, "button": me.LEFT, "bubbles": true})
#   e.client_x, e.page_x, e.button, e.buttons          # 10 10 0 0
#   me.click_event(10, 20)                              # click bouillonnant, annulable, detail 1
#   me.WheelEvent("wheel", {"delta_y": 120})
#   me.button_name(2)                                   # droit
#
# Erreurs : DomError (type vide).

from core use len, type
from collections use keys
from web.dom.event use UIEvent

const LEFT := 0
const MIDDLE := 1
const RIGHT := 2
const BACK := 3
const FORWARD := 4

const DOM_DELTA_PIXEL := 0
const DOM_DELTA_LINE := 1
const DOM_DELTA_PAGE := 2

func _opt(o, name, fallback):
    if type(o) == "dict" and name in o:
        return o[name]
    return fallback

func _copy(options, defaults):
    o := {}
    for k in keys(defaults):
        o[k] = defaults[k]
    if options != null:
        for k in keys(options):
            o[k] = options[k]
    return o

class MouseEvent extends UIEvent:
    func init(event_type, options=null):
        o := _copy(options, {"bubbles": event_type != "mouseenter" and event_type != "mouseleave", "cancelable": event_type != "mouseenter" and event_type != "mouseleave", "composed": true})
        super.init(event_type, o)
        self.screen_x = _opt(o, "screen_x", 0)
        self.screen_y = _opt(o, "screen_y", 0)
        self.client_x = _opt(o, "client_x", 0)
        self.client_y = _opt(o, "client_y", 0)
        self.page_x = _opt(o, "page_x", self.client_x + _opt(o, "scroll_x", 0))
        self.page_y = _opt(o, "page_y", self.client_y + _opt(o, "scroll_y", 0))
        self.offset_x = _opt(o, "offset_x", 0)
        self.offset_y = _opt(o, "offset_y", 0)
        self.movement_x = _opt(o, "movement_x", 0)
        self.movement_y = _opt(o, "movement_y", 0)
        self.button = _opt(o, "button", 0)
        self.buttons = _opt(o, "buttons", 0)
        self.ctrl_key = _opt(o, "ctrl_key", false)
        self.shift_key = _opt(o, "shift_key", false)
        self.alt_key = _opt(o, "alt_key", false)
        self.meta_key = _opt(o, "meta_key", false)
        self.related_target = _opt(o, "related_target", null)

    func x():
        return self.client_x

    func y():
        return self.client_y

    func get_modifier_state(name):
        if name == "Control":
            return self.ctrl_key
        if name == "Shift":
            return self.shift_key
        if name == "Alt":
            return self.alt_key
        if name == "Meta":
            return self.meta_key
        return false

    # Coordonnées relatives à un rectangle (DOMRect de la cible) : renseigne offset_x / offset_y.
    func relative_to(rect):
        self.offset_x = self.client_x - rect.x
        self.offset_y = self.client_y - rect.y
        return self

class WheelEvent extends MouseEvent:
    func init(event_type, options=null):
        super.init(event_type, options)
        o := options if options != null else {}
        self.delta_x = _opt(o, "delta_x", 0.0)
        self.delta_y = _opt(o, "delta_y", 0.0)
        self.delta_z = _opt(o, "delta_z", 0.0)
        self.delta_mode = _opt(o, "delta_mode", DOM_DELTA_PIXEL)

func button_name(b):
    if b == LEFT:
        return "gauche"
    if b == MIDDLE:
        return "milieu"
    if b == RIGHT:
        return "droit"
    if b == BACK:
        return "précédent"
    if b == FORWARD:
        return "suivant"
    return "inconnu"

# Masque « buttons » d'un bouton (gauche 1, droit 2, milieu 4, précédent 8, suivant 16).
func buttons_mask(b):
    if b == LEFT:
        return 1
    if b == RIGHT:
        return 2
    if b == MIDDLE:
        return 4
    if b == BACK:
        return 8
    if b == FORWARD:
        return 16
    return 0

func click_event(x=0, y=0, button=0, detail=1, event_type="click"):
    return MouseEvent(event_type, {"client_x": x, "client_y": y, "button": button, "detail": detail})

func mouse(event_type, x=0, y=0, options=null):
    o := _copy(options, {})
    o["client_x"] = x
    o["client_y"] = y
    return MouseEvent(event_type, o)

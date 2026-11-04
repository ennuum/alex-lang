# ALEX STANDARD LIBRARY — web.dom.pointer_event
#
# PointerEvent : pointeur unifié (souris, stylet, toucher) — identifiant, type, pointeur principal, pression,
# taille de contact, inclinaison, rotation — et suite d'événements d'un geste (pointerdown … pointerup).
#
#   use web.dom.pointer_event as pe
#   e := pe.PointerEvent("pointerdown", {"pointer_id": 1, "pointer_type": "touch", "pressure": 0.5, "client_x": 10})
#   e.pointer_type, e.is_primary, e.pressure           # touch true 0.5
#   pe.tap_sequence(10, 20, "touch")                   # [pointerover, pointerenter, pointerdown, pointerup, …]
#   pe.compatibility_mouse_type("pointerdown")         # mousedown
#
# Erreurs : DomError (type de pointeur inconnu).

from core use len, type
from collections use append, keys
use web.dom.dom_errors as _err
from web.dom.mouse_event use MouseEvent

const MOUSE := "mouse"
const PEN := "pen"
const TOUCH := "touch"

func _opt(o, name, fallback):
    if type(o) == "dict" and name in o:
        return o[name]
    return fallback

class PointerEvent extends MouseEvent:
    func init(event_type, options=null):
        super.init(event_type, options)
        o := options if options != null else {}
        self.pointer_id = _opt(o, "pointer_id", 1)
        self.pointer_type = _opt(o, "pointer_type", MOUSE)
        if not (self.pointer_type in [MOUSE, PEN, TOUCH, ""]):
            _err.dom_error("PointerEvent", "type de pointeur inconnu « " + str(self.pointer_type) + " »")
        self.is_primary = _opt(o, "is_primary", true)
        down := event_type == "pointerdown" or self.buttons != 0
        self.pressure = _opt(o, "pressure", 0.5 if down else 0.0)
        self.tangential_pressure = _opt(o, "tangential_pressure", 0.0)
        self.width = _opt(o, "width", 1)
        self.height = _opt(o, "height", 1)
        self.tilt_x = _opt(o, "tilt_x", 0)
        self.tilt_y = _opt(o, "tilt_y", 0)
        self.twist = _opt(o, "twist", 0)
        self.altitude_angle = _opt(o, "altitude_angle", 1.5707963267948966)
        self.azimuth_angle = _opt(o, "azimuth_angle", 0.0)

    func get_coalesced_events():
        return [self]

    func get_predicted_events():
        return []

# Événement souris de compatibilité émis après un événement pointeur (null s'il n'y en a pas).
func compatibility_mouse_type(pointer_type_name):
    table := {"pointerdown": "mousedown", "pointerup": "mouseup", "pointermove": "mousemove", "pointerover": "mouseover", "pointerout": "mouseout", "pointerenter": "mouseenter", "pointerleave": "mouseleave"}
    if pointer_type_name in table:
        return table[pointer_type_name]
    return null

# Suite d'événements d'un appui bref à (x, y) : survol, appui, relâchement, sortie (toucher), puis click.
func tap_sequence(x, y, pointer_type="mouse", pointer_id=1):
    out := []
    base := {"client_x": x, "client_y": y, "pointer_type": pointer_type, "pointer_id": pointer_id}
    for name in ["pointerover", "pointerenter", "pointerdown", "pointerup"]:
        o := {}
        for k in keys(base):
            o[k] = base[k]
        if name == "pointerdown":
            o["buttons"] = 1
        append(out, PointerEvent(name, o))
    if pointer_type == TOUCH:
        append(out, PointerEvent("pointerout", base))
        append(out, PointerEvent("pointerleave", base))
    return out

func pointer(event_type, x=0, y=0, pointer_type="mouse", options=null):
    o := {}
    if options != null:
        for k in keys(options):
            o[k] = options[k]
    o["client_x"] = x
    o["client_y"] = y
    o["pointer_type"] = pointer_type
    return PointerEvent(event_type, o)

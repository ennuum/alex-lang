# ALEX UI V0.8 — Paint
from core use type
use _native_ui as _ui_native

const DEFAULT_OPACITY := 1.0

func _num(v, name):
    if type(v) != "int" and type(v) != "float":
        raise("TypeError", "ui.paint." + name + "() : valeur numérique attendue")
    return v

func _color(c):
    if type(c) != "dict":
        raise("TypeError", "ui.paint : couleur invalide")
    return c

func fill(color, opacity=DEFAULT_OPACITY):
    _color(color)
    opacity = _num(opacity, "fill")
    return {"kind": "fill", "color": color, "opacity": opacity}

func stroke(color, width=1.0, opacity=DEFAULT_OPACITY):
    _color(color)
    width = _num(width, "stroke")
    opacity = _num(opacity, "stroke")
    if width < 0:
        raise("ArgumentError", "ui.paint.stroke() : width >= 0")
    return {"kind": "stroke", "color": color, "width": width, "opacity": opacity}

func _native(paint):
    if type(paint) != "dict":
        raise("TypeError", "ui.paint : peinture invalide")
    return paint

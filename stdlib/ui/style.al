from core use type, len
# ALEX STANDARD LIBRARY — ui.style V0.4
# Style descriptors are pure ALEX data. Native rendering consumes them through
# _native_ui.widget_set_style when available.

use ui.color as _color
use ui.font as _font
use _native_ui as _native

func style(background=null, foreground=null, font=null, padding=0, margin=0, radius=0):
    if background == null:
        background = _color.TRANSPARENT
    if foreground == null:
        foreground = _color.BLACK
    if font == null:
        font = _font.normal()
    return {
        "background": background,
        "foreground": foreground,
        "font": font,
        "padding": padding,
        "margin": margin,
        "radius": radius
    }

func apply(widget, value):
    if type(widget) != "int":
        raise("TypeError", "ui.style.apply() : widget doit être un handle int")
    if type(value) != "dict":
        raise("TypeError", "ui.style.apply() : style doit être un dict")
    return _native.widget_set_style(widget, value)

func merge(base, override):
    if type(base) != "dict" or type(override) != "dict":
        raise("TypeError", "ui.style.merge() : base et override doivent être des dict")
    result := base
    for key in override:
        result[key] = override[key]
    return result

# ALEX STANDARD LIBRARY — ui.button
from core use type
use _native_ui as _native

func create(parent, text, x=0, y=0, width=120, height=36):
    if x == null:
        x = 0
    if y == null:
        y = 0
    if width == null:
        width = 120
    if height == null:
        height = 36
    if type(text) != "str":
        raise("TypeError", "ui.button() : text doit être une str")
    return _native.button_create(parent, text, x, y, width, height)

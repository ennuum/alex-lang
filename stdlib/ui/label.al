# ALEX STANDARD LIBRARY — ui.label
from core use type
use _native_ui as _native

func create(parent, text, x=0, y=0, width=240, height=32):
    if x == null:
        x = 0
    if y == null:
        y = 0
    if width == null:
        width = 240
    if height == null:
        height = 32
    if type(text) != "str":
        raise("TypeError", "ui.label() : text doit être une str")
    return _native.label_create(parent, text, x, y, width, height)

# ALEX STANDARD LIBRARY — ui.combo_box
from core use type
use _native_ui as _native

func create(parent, text="", x=0, y=0, width=220, height=120):
    if text == null:
        text = ""
    if x == null:
        x = 0
    if y == null:
        y = 0
    if width == null:
        width = 220
    if height == null:
        height = 120
    return _native.combo_create(parent, text, x, y, width, height)

func add_item(handle, text):
    if type(text) != "str":
        raise("TypeError", "ui.combo_box.add_item() : text doit être une str")
    return _native.combo_add_item(handle, text)

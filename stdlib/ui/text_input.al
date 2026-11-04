# ALEX STANDARD LIBRARY — ui.text_input
from core use type
use _native_ui as _native

func create(parent, text="", x=0, y=0, width=260, height=32):
    if text == null:
        text = ""
    if x == null:
        x = 0
    if y == null:
        y = 0
    if width == null:
        width = 260
    if height == null:
        height = 32
    if type(text) != "str":
        raise("TypeError", "ui.text_input() : text doit être une str")
    return _native.input_create(parent, text, x, y, width, height)

func value(handle):
    return _native.widget_get_text(handle)
func set_value(handle, text):
    return _native.widget_set_text(handle, text)

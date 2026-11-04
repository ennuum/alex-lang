# ALEX STANDARD LIBRARY — ui.checkbox
from core use type
use _native_ui as _native

func create(parent, text, x=0, y=0, width=180, height=28):
    if x == null:
        x = 0
    if y == null:
        y = 0
    if width == null:
        width = 180
    if height == null:
        height = 28
    if type(text) != "str":
        raise("TypeError", "ui.checkbox() : text doit être une str")
    return _native.checkbox_create(parent, text, x, y, width, height)

func checked(handle):
    return _native.widget_get_checked(handle)
func set_checked(handle, value):
    if type(value) != "bool":
        raise("TypeError", "ui.checkbox.set_checked() : value doit être un bool")
    return _native.widget_set_checked(handle, value)

# ALEX STANDARD LIBRARY — ui.progress_bar
from core use type
use _native_ui as _native

func create(parent, x=0, y=0, width=240, height=22):
    if x == null:
        x = 0
    if y == null:
        y = 0
    if width == null:
        width = 240
    if height == null:
        height = 22
    return _native.progress_create(parent, "", x, y, width, height)

func set_value(handle, value):
    if type(value) != "int":
        raise("TypeError", "ui.progress_bar.set_value() : value doit être un int")
    if value < 0 or value > 100:
        raise("ArgumentError", "ui.progress_bar.set_value() : 0..100 attendu")
    return _native.progress_set(handle, value)

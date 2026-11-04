# ALEX STANDARD LIBRARY — ui.window
from core use type
use _native_ui as _native

func window(title="ALEX Application", width=900, height=600, resizable=true):
    if title == null:
        title = "ALEX Application"
    if width == null:
        width = 900
    if height == null:
        height = 600
    if resizable == null:
        resizable = true
    if type(title) != "str":
        raise("TypeError", "ui.window() : title doit être une str")
    if type(width) != "int" or type(height) != "int":
        raise("TypeError", "ui.window() : dimensions doivent être des int")
    if type(resizable) != "bool":
        raise("TypeError", "ui.window() : resizable doit être un bool")
    if width <= 0 or height <= 0:
        raise("ArgumentError", "ui.window() : dimensions strictement positives")
    return _native.window_create(title, width, height, resizable)

func show(handle):
    return _native.window_show(handle)
func hide(handle):
    return _native.window_hide(handle)
func close(handle):
    return _native.window_close(handle)
func set_title(handle, title):
    return _native.window_set_title(handle, title)
func set_size(handle, width, height):
    return _native.window_set_size(handle, width, height)
func poll(handle):
    return _native.window_poll(handle)
func run(handle):
    return _native.window_run(handle)

# ALEX STANDARD LIBRARY — ui.widget
# Base widget API. Handles are opaque integers owned by the native runtime.

from core use type
use _native_ui as _native

func require(handle, name="widget"):
    if type(handle) != "int":
        raise("TypeError", "ui." + name + "() : handle doit être un int")

func set_text(handle, text):
    require(handle, "widget.set_text")
    if type(text) != "str":
        raise("TypeError", "ui.widget.set_text() : text doit être une str")
    return _native.widget_set_text(handle, text)

func get_text(handle):
    require(handle, "widget.get_text")
    return _native.widget_get_text(handle)

func set_visible(handle, visible):
    require(handle, "widget.set_visible")
    if type(visible) != "bool":
        raise("TypeError", "ui.widget.set_visible() : visible doit être un bool")
    return _native.widget_set_visible(handle, visible)

func set_enabled(handle, enabled):
    require(handle, "widget.set_enabled")
    if type(enabled) != "bool":
        raise("TypeError", "ui.widget.set_enabled() : enabled doit être un bool")
    return _native.widget_set_enabled(handle, enabled)

func set_position(handle, x, y):
    require(handle, "widget.set_position")
    if x == null:
        x = 0
    if y == null:
        y = 0
    if type(x) != "int" or type(y) != "int":
        raise("TypeError", "ui.widget.set_position() : x et y doivent être des int")
    return _native.widget_set_position(handle, x, y)

func set_size(handle, width, height):
    require(handle, "widget.set_size")
    if width == null:
        width = 100
    if height == null:
        height = 30
    if type(width) != "int" or type(height) != "int":
        raise("TypeError", "ui.widget.set_size() : dimensions doivent être des int")
    if width <= 0 or height <= 0:
        raise("ArgumentError", "ui.widget.set_size() : dimensions strictement positives")
    return _native.widget_set_size(handle, width, height)

func set_checked(handle, checked):
    require(handle, "widget.set_checked")
    if type(checked) != "bool":
        raise("TypeError", "ui.widget.set_checked() : checked doit être un bool")
    return _native.widget_set_checked(handle, checked)

func checked(handle):
    require(handle, "widget.checked")
    return _native.widget_get_checked(handle)

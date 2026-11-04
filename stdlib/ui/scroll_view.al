# ALEX STANDARD LIBRARY — ui.scroll_view
use _native_ui as _native

func create(parent, x=0, y=0, width=320, height=240):
    if x == null:
        x = 0
    if y == null:
        y = 0
    if width == null:
        width = 320
    if height == null:
        height = 240
    return _native.scroll_create(parent, x, y, width, height)

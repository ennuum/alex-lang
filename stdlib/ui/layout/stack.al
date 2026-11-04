from core use len, type
# Stack — overlays all children in the same content rectangle.
use ui.layout.layout_core as _layout

func apply(children, width, height, padding=0):
    _layout._children(children)
    _layout._positive_int(width, "Stack.width")
    _layout._positive_int(height, "Stack.height")
    _layout._non_negative_int(padding, "Stack.padding")
    inner_w := width - padding * 2
    inner_h := height - padding * 2
    if inner_w <= 0 or inner_h <= 0:
        raise("ArgumentError", "ui.Stack : padding trop grand")
    i := 0
    while i < len(children):
        item := children[i]
        _layout.place(item, padding, padding, inner_w, inner_h)
        i = i + 1
    return null

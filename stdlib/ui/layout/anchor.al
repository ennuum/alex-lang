from core use len, type
# Anchor — positions widgets against container edges.
use ui.layout.layout_core as _layout

func apply(children, width, height, padding=0):
    _layout._children(children)
    _layout._positive_int(width, "Anchor.width")
    _layout._positive_int(height, "Anchor.height")
    _layout._non_negative_int(padding, "Anchor.padding")
    inner_w := width - padding * 2
    inner_h := height - padding * 2
    i := 0
    while i < len(children):
        item := children[i]
        left := item["left"]
        top := item["top"]
        right := item["right"]
        bottom := item["bottom"]
        x := padding + left
        y := padding + top
        w := item["width"]
        h := item["height"]
        if right != null and left != null:
            w = inner_w - left - right
        if bottom != null and top != null:
            h = inner_h - top - bottom
        if right != null and left == null:
            x = padding + inner_w - right - w
        if bottom != null and top == null:
            y = padding + inner_h - bottom - h
        if w <= 0 or h <= 0:
            raise("ArgumentError", "ui.Anchor : dimensions invalides")
        _layout.place(item, x, y, w, h)
        i = i + 1
    return null

func item(widget, width=100, height=30, left=0, top=0, right=null, bottom=null):
    base := _layout.item(widget, width, height)
    base["left"] = left
    base["top"] = top
    base["right"] = right
    base["bottom"] = bottom
    return base

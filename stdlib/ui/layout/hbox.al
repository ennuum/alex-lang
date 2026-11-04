from core use len, type
# HBox — horizontal layout.
use ui.layout.layout_core as _layout

func apply(children, width, height, gap=0, padding=0, alignment="start"):
    _layout._children(children)
    _layout._positive_int(width, "HBox.width")
    _layout._positive_int(height, "HBox.height")
    _layout._non_negative_int(gap, "HBox.gap")
    _layout._non_negative_int(padding, "HBox.padding")
    inner_w := width - padding * 2
    inner_h := height - padding * 2
    if inner_w <= 0 or inner_h <= 0:
        raise("ArgumentError", "ui.HBox : padding trop grand")
    count := len(children)
    if count == 0:
        return null
    fixed := 0
    flex_total := 0
    i := 0
    while i < count:
        item := children[i]
        fixed = fixed + item["width"] + item["margin"] * 2
        flex_total = flex_total + item["flex"]
        i = i + 1
    available := inner_w - fixed - gap * (count - 1)
    if available < 0:
        available = 0
    flex_unit := 0
    if flex_total > 0:
        flex_unit = available / flex_total
    x := padding
    i = 0
    while i < count:
        item := children[i]
        margin := item["margin"]
        item_w := item["width"]
        if item["flex"] > 0:
            item_w = flex_unit * item["flex"]
        y := padding + _layout.align_y(inner_h, item["height"], alignment)
        x = x + margin
        _layout.place(item, x, y, item_w, item["height"])
        x = x + item_w + margin
        if i < count - 1:
            x = x + gap
        i = i + 1
    return null

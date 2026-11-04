from core use len, type
# VBox — vertical layout.
use ui.layout.layout_core as _layout

func apply(children, width, height, gap=0, padding=0, alignment="start"):
    _layout._children(children)
    _layout._positive_int(width, "VBox.width")
    _layout._positive_int(height, "VBox.height")
    _layout._non_negative_int(gap, "VBox.gap")
    _layout._non_negative_int(padding, "VBox.padding")
    inner_w := width - padding * 2
    inner_h := height - padding * 2
    if inner_w <= 0 or inner_h <= 0:
        raise("ArgumentError", "ui.VBox : padding trop grand")
    count := len(children)
    if count == 0:
        return null
    fixed := 0
    flex_total := 0
    i := 0
    while i < count:
        item := children[i]
        fixed = fixed + item["height"] + item["margin"] * 2
        flex_total = flex_total + item["flex"]
        i = i + 1
    available := inner_h - fixed - gap * (count - 1)
    if available < 0:
        available = 0
    flex_unit := 0
    if flex_total > 0:
        flex_unit = available / flex_total
    y := padding
    i = 0
    while i < count:
        item := children[i]
        margin := item["margin"]
        item_h := item["height"]
        if item["flex"] > 0:
            item_h = flex_unit * item["flex"]
        x := padding + _layout.align_x(inner_w, item["width"], alignment)
        y = y + margin
        _layout.place(item, x, y, item["width"], item_h)
        y = y + item_h + margin
        if i < count - 1:
            y = y + gap
        i = i + 1
    return null

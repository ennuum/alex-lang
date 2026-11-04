from core use len, type
# Grid — equal cells with optional gap and padding.
use ui.layout.layout_core as _layout

func apply(children, width, height, columns=2, gap=0, padding=0):
    _layout._children(children)
    _layout._positive_int(width, "Grid.width")
    _layout._positive_int(height, "Grid.height")
    if columns == null:
        columns = 2
    _layout._positive_int(columns, "Grid.columns")
    _layout._non_negative_int(gap, "Grid.gap")
    _layout._non_negative_int(padding, "Grid.padding")
    if len(children) == 0:
        return null
    inner_w := width - padding * 2
    inner_h := height - padding * 2
    cell_w := (inner_w - gap * (columns - 1)) / columns
    rows := (len(children) + columns - 1) / columns
    cell_h := (inner_h - gap * (rows - 1)) / rows
    if cell_w <= 0 or cell_h <= 0:
        raise("ArgumentError", "ui.Grid : espace insuffisant")
    i := 0
    while i < len(children):
        row := i / columns
        col := i % columns
        item := children[i]
        x := padding + col * (cell_w + gap)
        y := padding + row * (cell_h + gap)
        _layout.place(item, x, y, cell_w, cell_h)
        i = i + 1
    return null

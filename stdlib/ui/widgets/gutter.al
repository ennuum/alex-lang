# ALEX UI V1.3 — Gouttière de numéros de ligne, synchronisée avec un text_area (source)
from core use type, len, clamp, to_int
use ui.widgets.widget as base
use ui.widgets.gfx as gfx
use ui.widgets.text_input as ti
use ui.paint as paint
use ui.canvas as canvas
use ui.text as text

func create(source, x=0.0, y=0.0, width=48.0, height=200.0):
    w := base.create("gutter", x, y, width, height)
    w["source"] = source
    w["focusable"] = false
    return w

func draw(w, c, t):
    if not w["visible"]:
        return null
    s := w["source"]
    ed := ti.sync(s)
    lh := ti.line_h(t)
    total := text.line_count(ed["text"])
    cur := text.line_of(ed["text"], ed["caret"])
    canvas.round_rect(c, w["x"], w["y"], w["width"], w["height"], t["radius"], paint.fill(t["surface_pressed"], w["opacity"]))
    gfx.push(c, w["x"], w["y"] + 3, w["width"], w["height"] - 6)
    first := clamp(to_int(s["scroll_y"] / lh), 0, total - 1)
    last := clamp(first + to_int(w["height"] / lh) + 2, 0, total - 1)
    i := first
    while i <= last:
        label := str(i + 1)
        col := t["muted"]
        if i == cur:
            col = t["text"]
        lw := text.width(label, t["font_size"])
        canvas.text(c, label, w["x"] + w["width"] - 10 - lw, w["y"] + ti.PAD_Y - s["scroll_y"] + i * lh, paint.fill(col), t["font"], t["font_size"])
        i += 1
    gfx.pop(c)
    return null

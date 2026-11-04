# ALEX UI V0.9 — Button
from core use len
use ui.widgets.widget as base
use ui.paint as paint
use ui.canvas as canvas
use ui.text as text

func create(text, x=0.0, y=0.0, width=120.0, height=40.0):
    w := base.create("button",x,y,width,height)
    w["text"] = text
    return w

func draw(w, c, t):
    if not w["visible"]:
        return
    bg := t["surface"]
    border := t["border"]
    if not w["enabled"]:
        bg = t["surface_pressed"]
    else:
        vs := base.visual_state(w)
        bg = base.mix(t["surface"],t["surface_hover"],vs[0])
        bg = base.mix(bg,t["surface_pressed"],vs[1])
        border = base.mix(t["border"],t["muted"],vs[0] * 0.7)
    canvas.round_rect(c,w["x"],w["y"],w["width"],w["height"],t["radius"],paint.fill(bg,w["opacity"]))
    canvas.round_rect(c,w["x"],w["y"],w["width"],w["height"],t["radius"],paint.stroke(border,1.0,w["opacity"]))
    tw := text.width(w["text"],t["font_size"])
    canvas.text(c,w["text"],w["x"]+(w["width"]-tw)*0.5,w["y"]+(w["height"]-t["font_size"]*1.3)*0.5,paint.fill(t["text"]),t["font"],t["font_size"])

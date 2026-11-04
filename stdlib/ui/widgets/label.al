# ALEX UI V0.9 — Label
use ui.widgets.widget as base
use ui.paint as paint
use ui.canvas as canvas

func create(text, x=0.0, y=0.0, width=200.0, height=28.0):
    w := base.create("label",x,y,width,height)
    w["text"] = text
    return w

func draw(w,c,t):
    if not w["visible"]:
        return
    canvas.text(c,w["text"],w["x"],w["y"]+(w["height"]-t["font_size"]*1.3)*0.5,paint.fill(t["text"]),t["font"],t["font_size"])

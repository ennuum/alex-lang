# ALEX UI V0.9 — Progress bar
use ui.widgets.widget as base
use ui.paint as paint
use ui.canvas as canvas

func create(value=0.0, x=0.0, y=0.0, width=240.0, height=8.0):
    w := base.create("progress",x,y,width,height)
    w["value"] = value
    return w

func set_value(w,value):
    if value < 0.0:
        value = 0.0
    if value > 1.0:
        value = 1.0
    w["value"] = value
    return w

func draw(w,c,t):
    if not w["visible"]:
        return
    canvas.round_rect(c,w["x"],w["y"],w["width"],w["height"],w["height"]*0.5,paint.fill(t["surface_pressed"],w["opacity"]))
    canvas.round_rect(c,w["x"],w["y"],w["width"]*w["value"],w["height"],w["height"]*0.5,paint.fill(t["primary"],w["opacity"]))

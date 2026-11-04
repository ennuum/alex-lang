# ALEX UI V0.9 — Text field facade
use ui.widgets.widget as base
use ui.paint as paint
use ui.canvas as canvas

func create(value="", placeholder="", x=0.0, y=0.0, width=260.0, height=40.0):
    w := base.create("text_field",x,y,width,height)
    w["value"] = value
    w["placeholder"] = placeholder
    return w

func set_value(w,value):
    w["value"] = value
    if w["on_change"] != null:
        w["on_change"](w,value)
    return w

func draw(w,c,t):
    if not w["visible"]:
        return
    bg := t["surface"]
    border := t["border"]
    if w["focused"]:
        border = t["primary"]
    canvas.round_rect(c,w["x"],w["y"],w["width"],w["height"],t["radius"],paint.fill(bg,w["opacity"]))
    canvas.round_rect(c,w["x"],w["y"],w["width"],w["height"],t["radius"],paint.stroke(border,1.0,w["opacity"]))
    value := w["value"]
    color := t["text"]
    if value == "":
        value = w["placeholder"]
        color = t["muted"]
    canvas.text(c,value,w["x"]+12,w["y"]+(w["height"]-t["font_size"]*1.3)*0.5,paint.fill(color),t["font"],t["font_size"])

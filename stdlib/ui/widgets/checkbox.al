# ALEX UI V0.9 — Checkbox
use ui.widgets.widget as base
use ui.paint as paint
use ui.canvas as canvas

func create(text, checked=false, x=0.0, y=0.0, width=180.0, height=32.0):
    w := base.create("checkbox",x,y,width,height)
    w["text"] = text
    w["value"] = checked
    return w

func toggle(w):
    if not w["enabled"]:
        return w
    w["value"] = not w["value"]
    if w["on_change"] != null:
        w["on_change"](w,w["value"])
    return w

func draw(w,c,t):
    if not w["visible"]:
        return
    box := 20.0
    vs := base.visual_state(w)
    bg := base.mix(t["surface"],t["surface_hover"],vs[0])
    if w["value"]:
        bg = base.mix(t["primary"],t["primary_hover"],vs[0])
    canvas.round_rect(c,w["x"],w["y"]+(w["height"]-box)*0.5,box,box,5,paint.fill(bg,w["opacity"]))
    canvas.round_rect(c,w["x"],w["y"]+(w["height"]-box)*0.5,box,box,5,paint.stroke(t["border"],1.0,w["opacity"]))
    if w["value"]:
        # coche : deux segments
        bx := w["x"]
        by := w["y"]+(w["height"]-box)*0.5
        canvas.line(c,bx+5.0,by+10.5,bx+9.0,by+14.5,paint.stroke(t["text"],2.0,w["opacity"]))
        canvas.line(c,bx+9.0,by+14.5,bx+15.5,by+6.0,paint.stroke(t["text"],2.0,w["opacity"]))
    if w["focused"]:
        canvas.round_rect(c,w["x"]-2,w["y"]+(w["height"]-box)*0.5-2,box+4,box+4,7,paint.stroke(t["primary"],1.0,w["opacity"]))
    canvas.text(c,w["text"],w["x"]+30,w["y"]+(w["height"]-t["font_size"]*1.3)*0.5,paint.fill(t["text"]),t["font"],t["font_size"])

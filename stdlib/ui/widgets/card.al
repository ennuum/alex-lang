# ALEX UI V0.9 — Card
use ui.widgets.widget as base
use ui.paint as paint
use ui.canvas as canvas

func create(x=0.0,y=0.0,width=280.0,height=160.0):
    w := base.create("card",x,y,width,height)
    w["layout"]["type"] = "column"
    w["layout"]["direction"] = "column"
    w["layout"]["padding"] = {"left":16.0,"top":16.0,"right":16.0,"bottom":16.0}
    w["layout"]["gap"] = 12.0
    w["layout"]["alignment"] = {"horizontal":"stretch","vertical":"start"}
    return w

func draw(w,c,t):
    if not w["visible"]:
        return
    canvas.shadow_round_rect(c,w["x"],w["y"],w["width"],w["height"],t["radius"],{"color":{"r":0,"g":0,"b":0,"a":255},"opacity":0.25,"blur":12.0,"offset_x":0.0,"offset_y":4.0},paint.fill(t["surface"],w["opacity"]))
    canvas.round_rect(c,w["x"],w["y"],w["width"],w["height"],t["radius"],paint.stroke(t["border"],1.0,w["opacity"]))

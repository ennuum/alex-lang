# ALEX UI V1.0 — Layout & Widget Composition (interactif, Windows + Linux)
use ui as ui
use ui.layout as layout
use ui.widgets as widgets
use ui.canvas as canvas

win := ui.window("ALEX UI V1.0", 900, 600, true)
c := canvas.create(win)
t := widgets.modern_theme()

root := layout.container("root",0,0,900,600)
layout.padding_all(root,24)
layout.gap(root,16)
layout.column(root)
layout.align(root,"stretch","start")

header := layout.container("header",0,0,0,56)
layout.row(header)
layout.align(header,"stretch","center")
layout.gap(header,12)
layout.add(root,header)

title := widgets.label("ALEX UI V1.0",0,0,220,36)
layout.add(header,title)

body := layout.container("body",0,0,0,0)
layout.row(body)
layout.align(body,"start","stretch")
layout.gap(body,16)
layout.flex(body,1)
layout.add(root,body)

left := widgets.card(0,0,0,0)
layout.flex(left,1)
layout.add(body,left)

right := widgets.card(0,0,0,0)
layout.flex(right,2)
layout.add(body,right)

button := widgets.button("Créer un projet")
layout.add(left,button)

check := widgets.checkbox("Activer le mode moderne")
layout.add(left,check)

field := widgets.text_field("Alex", "Nom du projet")
layout.add(right,field)

bar := widgets.progress(0.72)
layout.add(right,bar)

func on_click(w):
    print("clic:", w["kind"])
button["on_click"] = on_click

layout.perform(root,900,600)
widgets.draw(root,c,t)
ui.show(win)

# Boucle d'événements : redimensionnement -> nouvelle mise en page ; pointeur -> widgets.
running := true
while running:
    ev := ui.poll(win)
    if ev == null:
        continue
    kind := ui.event_type(ev)
    if kind == "close":
        running = false
    elif kind == "resize":
        root["width"] = ev["x"]
        root["height"] = ev["y"]
        canvas.resize(c)
        layout.perform(root,ev["x"],ev["y"])
        widgets.draw(root,c,t)
    elif kind == "pointer_move" or kind == "pointer_down" or kind == "pointer_up":
        widgets.dispatch(root,ev)
        widgets.draw(root,c,t)

canvas.destroy(c)
ui.close(win)

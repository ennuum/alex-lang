# ALEX UI V0.9 — Modern widgets smoke example
use ui
use ui.canvas as canvas
use ui.paint as paint
use ui.widgets.modern as widgets
use ui.widgets.widget as widget

window := ui.window("ALEX UI V0.9", 900, 620, true)
c := canvas.create(window)
t := widgets.theme_modern()

card := widgets.card_new(40,40,820,500)
title := widgets.label_new("ALEX UI V0.9 — Modern Widgets",70,70,500,30)
button := widgets.button_new("Continuer",70,125,150,44)
check := widgets.checkbox_new("Activer les notifications",true,70,190,300,32)
field := widgets.text_field_new("","Nom du projet",70,245,360,44)
bar := widgets.progress_new(0.72,70,320,360,10)

func on_button_click(w):
    print("Bouton activé")

func on_notifications_change(w, value):
    print("Notifications:", value)

button["on_click"] = on_button_click
check["on_change"] = on_notifications_change

widget.add(card,title)
widget.add(card,button)
widget.add(card,check)
widget.add(card,field)
widget.add(card,bar)

canvas.begin(c)
canvas.clear(c,{"r":18,"g":20,"b":25,"a":255})
widgets.draw_tree(card,c,t)
canvas.end(c)

ui.show(window)
ui.run(window)

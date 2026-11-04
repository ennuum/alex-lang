# ALEX UI V1.1 — État réactif avec widgets modernes (canvas) : rendu uniquement quand l'état change
use ui
use ui.canvas as canvas
use ui.layout as layout
use ui.widgets as widgets
use ui.state as state

func plus_one(v):
    return v + 1
func title_of(s):
    return "Compteur : " + str(state.get(s, "count"))
func ratio(s):
    return state.get(s, "count") / 10.0
func add_label(s):
    return "Ajouter (" + str(state.get(s, "count")) + ")"

func on_add(w):
    state.update(w["state_link"]["store"], "count", plus_one)

# Re-rendu : appelé par state.run seulement si l'état a changé.
func render(store, ctx):
    layout.perform(ctx["root"], ctx["w"], ctx["h"])
    widgets.draw(ctx["root"], ctx["canvas"], ctx["theme"])

# Événements bruts : resize et pointeur (le re-rendu n'a lieu que si l'état ou la taille changent).
func handler(ev, store, ctx):
    t := ev["type"]
    if t == "resize":
        ctx["w"] = ev["x"]
        ctx["h"] = ev["y"]
        ctx["root"]["width"] = ev["x"]
        ctx["root"]["height"] = ev["y"]
        canvas.resize(ctx["canvas"])
        state.invalidate(store)
    elif t == "pointer_move" or t == "pointer_down" or t == "pointer_up":
        widgets.dispatch(ctx["root"], ev)
        state.invalidate(store)

win := ui.window("ALEX UI V1.1 — Canvas réactif", 640, 420, true)
c := canvas.create(win)
t := widgets.modern_theme()

root := layout.container("root", 0, 0, 640, 420)
layout.padding_all(root, 24)
layout.gap(root, 16)
layout.column(root)
layout.align(root, "stretch", "start")

title := widgets.label("", 0, 0, 300, 36)
layout.add(root, title)
card := widgets.card(0, 0, 0, 0)
layout.flex(card, 1)
layout.add(root, card)
bar := widgets.progress(0.0)
layout.add(card, bar)
btn := widgets.button("")
layout.add(card, btn)
dark := widgets.checkbox("Option activée")
layout.add(card, dark)

store := state.create({"count": 2, "option": true})
state.computed(store, "title", title_of)
state.computed(store, "ratio", ratio)
state.computed(store, "add_label", add_label)

state.bind_prop(store, "title", title, "text")
state.bind_prop(store, "ratio", bar, "value")
state.bind_prop(store, "add_label", btn, "text")
state.link_widget(store, "option", dark)
btn["state_link"] = {"store": store}
btn["on_click"] = on_add

ctx := {"root": root, "canvas": c, "theme": t, "w": 640, "h": 420}
ui.show(win)
state.run(win, store, render, handler, ctx)
canvas.destroy(c)
ui.close(win)

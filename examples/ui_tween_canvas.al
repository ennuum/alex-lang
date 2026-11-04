# ALEX UI V1.2 — Animation avec widgets modernes (canvas) : ressort, couleur de thème, pulsation
use ui
use ui.canvas as canvas
use ui.layout as layout
use ui.widgets as widgets
use ui.state as state
use ui.tween as tw

const ORANGE := {"r": 255, "g": 107, "b": 0, "a": 255}
const BLUE := {"r": 56, "g": 132, "b": 255, "a": 255}

func plus_one(v):
    return v + 1
func title_of(s):
    return "Compteur : " + str(state.get(s, "count"))
func ratio(s):
    return state.get(s, "shown") / 10.0
func add_label(s):
    return "Ajouter (" + str(state.get(s, "count")) + ")"

# Clic : l'état saute, la barre suit avec un ressort (rebond), le bouton « pulse ».
func on_add(w):
    store := w["state_link"]["store"]
    state.update(store, "count", plus_one)
    state.spring(store, "shown", state.get(store, "count") + 0.0, null, 140.0, 9.0)
    pulse := tw.sequence([
        tw.tween(tw.target_dict(w, "opacity"), 0.35, 0.08, null, "ease_out"),
        tw.tween(tw.target_dict(w, "opacity"), 1.0, 0.30, null, "ease_in_out")
    ])
    state.play(store, pulse)

# La case à cocher change la couleur d'accent du THÈME : tween de couleur, tout le rendu suit.
func on_option(ev):
    target := ORANGE
    if not ev["value"]:
        target = BLUE
    state.play(ev["store"], tw.tween(tw.target_dict(ev["ctx"], "primary"), target, 0.45, null, "cubic_in_out"))

func render(store, ctx):
    layout.perform(ctx["root"], ctx["w"], ctx["h"])
    widgets.draw(ctx["root"], ctx["canvas"], ctx["theme"])

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

win := ui.window("ALEX UI V1.2 — Canvas animé", 640, 420, true)
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
accent := widgets.checkbox("Accent orange")
layout.add(card, accent)

store := state.create({"count": 0, "shown": 0.0, "option": true})
state.computed(store, "title", title_of)
state.computed(store, "ratio", ratio)
state.computed(store, "add_label", add_label)
state.bind_prop(store, "title", title, "text")
state.bind_prop(store, "ratio", bar, "value")
state.bind_prop(store, "add_label", btn, "text")
state.link_widget(store, "option", accent)
state.watch(store, "option", on_option, t)
btn["state_link"] = {"store": store}
btn["on_click"] = on_add

ctx := {"root": root, "canvas": c, "theme": t, "w": 640, "h": 420}
ui.show(win)
state.run(win, store, render, handler, ctx)
canvas.destroy(c)
ui.close(win)

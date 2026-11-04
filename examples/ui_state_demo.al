# ALEX UI V1.1 — État réactif (widgets natifs, Windows + Linux)
# Un seul store ; les widgets en dépendent, rien n'est mis à jour « à la main ».
use ui
use ui.state as state

func plus_one(v):
    return v + 1
func minus_one(v):
    return v - 1
func fmt_count(v):
    return "Compteur : " + str(v)

func greeting(s):
    n := state.get(s, "name")
    if n == "":
        return "Entrez votre nom"
    return "Bonjour " + n + " !"
func progress(s):
    return state.get(s, "count") * 10
func can_dec(s):
    return state.get(s, "count") > 0
func can_inc(s):
    return state.get(s, "count") < 10
func summary(s):
    mode := "clair"
    if state.get(s, "dark"):
        mode = "sombre"
    return "Mode " + mode + " — " + str(state.get(s, "count")) + "/10"

func on_inc(call):
    state.update(call["store"], "count", plus_one)
func on_dec(call):
    state.update(call["store"], "count", minus_one)
func on_reset(call):
    state.set_many(call["store"], {"count": 0, "name": "", "dark": false})

win := ui.window("ALEX UI V1.1 — État réactif", 460, 330, false)
ui.label(win, "Nom :", 20, 20, 60, 24)
name_in := ui.input_field(win, "", 90, 16, 340, 30)
dark := ui.checkbox(win, "Mode sombre", 20, 60, 200, 26)
greet := ui.label(win, "", 20, 100, 410, 26)
count_lbl := ui.label(win, "", 20, 140, 200, 26)
bar := ui.progress_bar(win, 20, 175, 410, 18)
minus := ui.button(win, "−", 20, 210, 60, 32)
plus := ui.button(win, "+", 90, 210, 60, 32)
reset := ui.button(win, "Réinitialiser", 160, 210, 130, 32)
info := ui.label(win, "", 20, 265, 410, 26)

store := state.create({"name": "Alex", "count": 3, "dark": false})
state.computed(store, "greeting", greeting)
state.computed(store, "progress", progress)
state.computed(store, "can_dec", can_dec)
state.computed(store, "can_inc", can_inc)
state.computed(store, "summary", summary)

state.link_input(store, "name", name_in)
state.link_checkbox(store, "dark", dark)
state.bind_text(store, "greeting", greet)
state.bind_text(store, "count", count_lbl, fmt_count)
state.bind_progress(store, "progress", bar)
state.bind_enabled(store, "can_dec", minus)
state.bind_enabled(store, "can_inc", plus)
state.bind_text(store, "summary", info)

state.on(store, plus, on_inc)
state.on(store, minus, on_dec)
state.on(store, reset, on_reset)

ui.show(win)
state.run(win, store)
ui.close(win)

# Tests de ui.state avec widgets natifs (backend headless) : liaisons, événements, boucle réactive.
from core use type, len
use collections
use ui
use ui.state as state

func check(cond, name):
    if not cond:
        raise("AssertionError", "ÉCHEC : " + name)
    print("ok  " + name)

func plus_one(v):
    return v + 1
func greeting(s):
    return "Bonjour " + state.get(s, "name") + " !"
func pct(s):
    return state.get(s, "count") * 10
func on_inc(call):
    state.update(call["store"], "count", plus_one)
func on_save(call):
    call["ctx"]["saved"] += 1
func render(store, ctx):
    ctx["renders"] += 1
func handler(ev, store, ctx):
    ctx["events"] += 1
func double_it(v):
    return v * 2

# Vide la file d'événements en les confiant à l'état (comme le fait state.run).
func pump(win, store):
    n := 0
    running := true
    while running:
        ev := ui.poll(win)
        if ev == null:
            running = false
        elif ui.event_type(ev) != "close":
            state.handle_event(store, ev)
            n += 1
    return n

check(ui.backend() == "headless", "backend headless")
win := ui.window("State", 420, 320, true)
name_in := ui.input_field(win, "", 10, 10, 200, 28)
chk := ui.checkbox(win, "Sombre", 10, 50, 150, 24)
lbl := ui.label(win, "", 10, 80, 300, 24)
bar := ui.progress_bar(win, 10, 110, 200, 16)
inc := ui.button(win, "+", 10, 140, 60, 28)
save := ui.button(win, "Sauver", 80, 140, 80, 28)
cnt := ui.label(win, "", 10, 180, 100, 24)
ui.show(win)

store := state.create({"name": "Alex", "dark": false, "count": 0})
state.computed(store, "greeting", greeting)
state.computed(store, "pct", pct)
state.link_input(store, "name", name_in)
state.link_checkbox(store, "dark", chk)
state.bind_text(store, "greeting", lbl)
state.bind_progress(store, "pct", bar)
state.bind_text(store, "count", cnt, double_it)
ctx := {"saved": 0, "renders": 0, "events": 0}
state.on(store, inc, on_inc)
state.on(store, save, on_save, ctx)

# ---- store -> widget (liaison initiale + mises à jour)
check(ui.widget_get_text(name_in) == "Alex", "bind initial : champ de saisie")
check(ui.widget_get_text(lbl) == "Bonjour Alex !", "bind initial : label calculé")
check(ui.widget_get_text(cnt) == "0", "bind avec transformation")
state.set(store, "name", "Bob")
check(ui.widget_get_text(name_in) == "Bob" and ui.widget_get_text(lbl) == "Bonjour Bob !", "set -> widgets mis à jour")
state.set(store, "dark", true)
check(ui.widget_get_checked(chk), "set -> case cochée")
state.set(store, "dark", false)
check(not ui.widget_get_checked(chk), "set -> case décochée")
state.set(store, "count", 4)
check(ui.widget_get_text(cnt) == "8", "transformation réappliquée (4 x 2)")
state.set(store, "count", 0)

# ---- widget -> store
ui.inject_mouse(win, "click", 100, 24)
ui.inject_text(win, "Z")
pump(win, store)
check(state.get(store, "name") == "BobZ", "saisie -> store")
check(ui.widget_get_text(lbl) == "Bonjour BobZ !", "saisie -> valeur calculée -> label")
ui.inject_text(win, "é")
pump(win, store)
check(state.get(store, "name") == "BobZé", "saisie UTF-8 -> store")

ui.inject_mouse(win, "click", 20, 62)
pump(win, store)
check(state.get(store, "dark") == true, "clic checkbox -> store")
ui.inject_mouse(win, "click", 20, 62)
pump(win, store)
check(state.get(store, "dark") == false, "second clic -> store")

# ---- handlers de boutons
ui.inject_mouse(win, "click", 40, 154)
ui.inject_mouse(win, "click", 40, 154)
pump(win, store)
check(state.get(store, "count") == 2 and state.get(store, "pct") == 20, "handler bouton + computed")
check(ui.widget_get_text(cnt) == "4", "handler -> widget lié")
ui.inject_mouse(win, "click", 100, 154)
pump(win, store)
check(ctx["saved"] == 1, "handler avec ctx")

# ---- widget désactivé / visible via état
func is_low(s):
    return state.get(s, "count") < 5
state.computed(store, "can_inc", is_low)
state.bind_enabled(store, "can_inc", inc)
state.set(store, "count", 9)
ui.inject_mouse(win, "click", 40, 154)
pump(win, store)
check(state.get(store, "count") == 9, "bind_enabled : bouton désactivé par l'état")
state.set(store, "count", 1)
ui.inject_mouse(win, "click", 40, 154)
pump(win, store)
check(state.get(store, "count") == 2, "bind_enabled : réactivé")

# ---- boucle réactive
state.clear_dirty(store)
ui.inject_mouse(win, "click", 40, 154)
ui.inject_mouse(win, "click", 40, 154)
state.run(win, store, render, handler, ctx)
check(state.get(store, "count") == 4, "run : événements traités")
check(ctx["renders"] >= 2, "run : rendu initial + re-rendu sur état modifié")
check(ctx["events"] >= 2, "run : handler appelé")

# ---- liaisons invalides
failed := false
try:
    state.bind_text(store, "name", "pas un handle")
catch e:
    failed = true
check(failed, "bind_text handle invalide -> TypeError")
failed = false
try:
    state.bind_text(store, "inconnue", name_in)
catch e:
    failed = true
check(failed, "bind clé inconnue -> erreur")

ui.close(win)
print("UI STATE + WIDGETS: OK")

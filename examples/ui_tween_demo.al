# ALEX UI V1.2 — Animation / Tweening (widgets natifs, Windows + Linux)
# L'état est animé (ressort, tween) ; les widgets liés suivent. Rien ne bloque la boucle d'événements.
use ui
use ui.state as state
use ui.tween as tw
from core use to_int

func fmt_value(v):
    return "Valeur : " + str(to_int(v))
# Les boutons fixent une cible ; le ressort remplace l'animation en cours (vitesse conservée).
func go_25(call):
    state.spring(call["store"], "shown", 25.0, null, 170.0, 14.0)
func go_75(call):
    state.spring(call["store"], "shown", 75.0, null, 170.0, 14.0)
func go_100(call):
    state.animate(call["store"], "shown", 100.0, 1.2, null, "bounce_out")
func go_0(call):
    state.animate(call["store"], "shown", 0.0, 0.6, null, "cubic_in_out")
func on_done(ev):
    state.set(ev["ctx"], "status", "Terminé")
func on_start(ev):
    state.set(ev["ctx"], "status", "Séquence...")
func run_sequence(call):
    s := call["store"]
    node := tw.sequence([
        tw.tween(tw.target_state(s, "shown"), 100.0, 0.6, 0.0, "cubic_out"),
        tw.wait(0.3),
        tw.tween(tw.target_state(s, "shown"), 40.0, 0.5, null, "ease_in_out"),
        tw.wait(0.2),
        tw.tween(tw.target_state(s, "shown"), 0.0, 0.4, null, "back_in")
    ])
    tw.callbacks(node, on_start, null, on_done, s)
    state.play(s, node, "sequence")

win := ui.window("ALEX UI V1.2 — Animation", 520, 300, false)
title := ui.label(win, "Animation d'état (ressorts, tweens, séquences)", 20, 16, 480, 24)
val := ui.label(win, "", 20, 56, 300, 24)
bar := ui.progress_bar(win, 20, 90, 480, 22)
b0 := ui.button(win, "0 (tween)", 20, 135, 110, 32)
b25 := ui.button(win, "25 (ressort)", 140, 135, 110, 32)
b75 := ui.button(win, "75 (ressort)", 260, 135, 110, 32)
b100 := ui.button(win, "100 (rebond)", 380, 135, 120, 32)
seq := ui.button(win, "Séquence", 20, 185, 110, 32)
status := ui.label(win, "", 140, 190, 360, 24)

store := state.create({"shown": 0.0, "status": "Prêt"})
state.bind_text(store, "shown", val, fmt_value)
state.bind_progress(store, "shown", bar)
state.bind_text(store, "status", status)

state.on(store, b0, go_0)
state.on(store, b25, go_25)
state.on(store, b75, go_75)
state.on(store, b100, go_100)
state.on(store, seq, run_sequence)

# Entrée en scène : le bouton « Séquence » glisse depuis la gauche (widget natif, géométrie suivie).
an := state.animator(store)
tw.track_native(an, seq, -120, 185, 110, 32)
tw.animate_native(an, seq, "x", 20, 0.6, -120, "cubic_out")

ui.show(win)
state.run(win, store)
ui.close(win)

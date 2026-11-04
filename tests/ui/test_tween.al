# Tests de ui.tween (V1.2) : logique pure et déterministe (tick(dt) manuel), sans fenêtre.
from core use type, len
use collections
use ui.tween as tw
use ui.state as state

func check(cond, name):
    if not cond:
        raise("AssertionError", "ÉCHEC : " + name)
    print("ok  " + name)

func near(a, b, eps=0.001):
    d := a - b
    return d < eps and d > 0 - eps

# --- rappels de test (fonctions de premier niveau) ---
func rec(ev):
    collections.append(ev["ctx"], ev["progress"])
func mark(ev):
    ev["ctx"]["n"] += 1
func boom(ev):
    raise("RuntimeError", "rappel en panne")
func write_log(ev):
    collections.append(ev["ctx"], ev["value"])

# ================= easing =================
check(near(tw.ease("linear", 0.3), 0.3), "easing : linear")
check(near(tw.ease("elastic_out", 0.5), 1.015625), "easing : elastic_out")
check(near(tw.ease("circ_in_out", 0.5), 0.5), "easing : circ_in_out")
check(tw.ease("back_in_out", 0.1) < 0, "easing : back_in_out dépasse (valeur négative au départ)")
b := tw.bezier(0.25, 0.1, 0.25, 1.0)
check(tw.ease(b, 0.0) == 0 and tw.ease(b, 1.0) == 1 and near(tw.ease(b, 0.5), 0.8024), "easing : cubic-bezier (CSS ease)")
check(near(tw.ease(tw.bezier(0.0, 0.0, 1.0, 1.0), 0.37), 0.37), "easing : bezier linéaire")
check(near(tw.ease(tw.steps(4), 0.26), 0.25) and near(tw.ease(tw.steps(4), 1.0), 1.0), "easing : steps(4)")
check(near(tw.ease(tw.steps(4, "start"), 0.01), 0.25), "easing : steps jump-start")
func half(t):
    return t / 2
check(near(tw.ease(half, 1.0), 0.5), "easing : fonction personnalisée")
failed := false
try:
    tw.ease("inconnue", 0.5)
catch e:
    failed = true
check(failed, "easing : nom inconnu -> erreur")
failed = false
try:
    tw.bezier(2.0, 0.0, 0.5, 1.0)
catch e:
    failed = true
check(failed, "bezier : x hors [0,1] -> erreur")

# ================= interpolation =================
check(tw.interpolate(0, 10, 0.5) == 5.0, "interpolate : nombre")
c := tw.interpolate({"r": 0, "g": 100, "b": 255}, {"r": 100, "g": 200, "b": 255, "a": 0}, 0.5)
check(c["r"] == 50 and c["g"] == 150 and c["b"] == 255 and c["a"] == 128, "interpolate : couleur (alpha implicite 255)")
c = tw.interpolate({"r": 250, "g": 0, "b": 0}, {"r": 255, "g": 0, "b": 0}, 3.0)
check(c["r"] == 255, "interpolate : canaux bornés à 255 (overshoot)")
v := tw.interpolate([0, 10], [10, 30], 0.5)
check(v[0] == 5.0 and v[1] == 20.0, "interpolate : vecteur")
failed = false
try:
    tw.interpolate(1, "x", 0.5)
catch e:
    failed = true
check(failed, "interpolate : types incompatibles -> erreur")

# ================= tween sur état =================
s := state.create({"x": 0.0, "y": 100.0})
an := tw.create()
tw.attach(an, s)
id := tw.animate_state(an, s, "x", 100.0, 2.0, null, "linear")
check(state.get(s, "x") == 0.0 and tw.is_active(an, id), "tween : valeur de départ appliquée au play")
tw.tick(an, 0.5)
check(near(state.get(s, "x"), 25.0), "tween : 25 % à t=0.5/2")
tw.tick(an, 1.0)
check(near(state.get(s, "x"), 75.0), "tween : 75 %")
tw.tick(an, 5.0)
check(state.get(s, "x") == 100.0 and tw.state(an, id) == "finished", "tween : valeur finale exacte, terminé")
check(not tw.is_active(an), "animateur inactif après la fin")
state.clear_dirty(s)
tw.tick(an, 1.0)
check(not state.is_dirty(s), "aucun travail ni invalidation sans animation active")

# start implicite = valeur courante
tw.animate_state(an, s, "y", 0.0, 1.0, null, "linear")
tw.tick(an, 0.5)
check(near(state.get(s, "y"), 50.0), "start implicite : depuis la valeur courante de l'état")

# observateurs de l'état reçoivent les images
log := []
state.watch(s, "x", write_log, log)
tw.animate_state(an, s, "x", 0.0, 1.0, null, "linear")
tw.tick(an, 0.5)
tw.tick(an, 0.5)
check(len(log) >= 2 and log[len(log) - 1] == 0.0, "tween : l'état notifie ses observateurs à chaque image")

# ================= délai, répétition, yoyo =================
s2 := state.create({"v": 0.0})
a2 := tw.create()
tw.animate_state(a2, s2, "v", 10.0, 1.0, 0.0, "linear", 0.5)
tw.tick(a2, 0.4)
check(state.get(s2, "v") == 0.0, "délai : rien avant la fin du délai")
tw.tick(a2, 0.6)
check(near(state.get(s2, "v"), 5.0), "délai : démarre après 0.5 s (0.5 s écoulées sur 1 s)")
tw.clear(a2)

s3 := state.create({"v": 0.0})
a3 := tw.create()
tw.animate_state(a3, s3, "v", 10.0, 1.0, 0.0, "linear", 0.0, 2, true)
tw.tick(a3, 1.5)
check(near(state.get(s3, "v"), 5.0), "yoyo : aller à t=1.5 -> retour à mi-chemin")
tw.tick(a3, 0.5)
check(near(state.get(s3, "v"), 0.0), "yoyo : cycle 2 -> retour au début")
tw.tick(a3, 0.5)
check(near(state.get(s3, "v"), 5.0), "yoyo : cycle 3 (aller)")
tw.tick(a3, 5.0)
check(state.get(s3, "v") == 10.0 and tw.active_count(a3) == 0, "repeat=2 + yoyo : s'arrête sur l'extrémité (3 cycles)")

s4 := state.create({"v": 0.0})
a4 := tw.create()
id4 := tw.animate_state(a4, s4, "v", 1.0, 1.0, 0.0, "linear", 0.0, -1)
tw.tick(a4, 100.25)
check(near(state.get(s4, "v"), 0.25) and tw.is_active(a4, id4), "repeat=-1 : boucle infinie")
failed = false
try:
    tw.finish(a4, id4)
catch e:
    failed = true
check(failed, "finish sur animation infinie -> erreur")
check(tw.cancel(a4, id4) and tw.state(a4, id4) == "cancelled", "cancel")
frozen := state.get(s4, "v")
tw.tick(a4, 1.0)
check(state.get(s4, "v") == frozen, "animation annulée : plus de mise à jour")

# ================= couleurs / vecteurs / propriété de dict =================
theme := {"primary": {"r": 0, "g": 0, "b": 0, "a": 255}, "size": [10, 20]}
a5 := tw.create()
tw.animate_prop(a5, theme, "primary", {"r": 200, "g": 100, "b": 50}, 1.0, null, "linear")
tw.animate_prop(a5, theme, "size", [20, 40], 1.0, null, "linear")
tw.tick(a5, 0.5)
check(theme["primary"]["r"] == 100 and theme["primary"]["g"] == 50 and theme["size"][1] == 30.0, "propriété de dict : couleur et vecteur")
tw.tick(a5, 1.0)
check(theme["primary"]["b"] == 50 and theme["size"][0] == 20, "propriété de dict : valeurs finales")

# ================= remplacement (même cible) =================
s6 := state.create({"v": 0.0})
a6 := tw.create()
first := tw.animate_state(a6, s6, "v", 100.0, 1.0, null, "linear")
tw.tick(a6, 0.5)
second := tw.animate_state(a6, s6, "v", 0.0, 1.0, null, "linear")
check(tw.state(a6, first) == "cancelled" and tw.is_active(a6, second), "même cible : l'ancienne animation est remplacée")
tw.tick(a6, 0.5)
check(near(state.get(s6, "v"), 25.0), "remplacement : repart de la valeur courante (50 -> 25)")

# ================= pause / reprise / vitesse / seek / reverse =================
s7 := state.create({"v": 0.0})
a7 := tw.create()
id7 := tw.animate_state(a7, s7, "v", 100.0, 1.0, null, "linear")
tw.tick(a7, 0.25)
tw.pause(a7, id7)
tw.tick(a7, 1.0)
check(near(state.get(s7, "v"), 25.0), "pause : l'animation est gelée")
tw.resume(a7, id7)
tw.set_speed(a7, id7, 2.0)
tw.tick(a7, 0.25)
check(near(state.get(s7, "v"), 75.0), "vitesse x2")
tw.seek(a7, id7, 0.1)
check(near(state.get(s7, "v"), 10.0), "seek en arrière")
tw.reverse(a7, id7)
tw.tick(a7, 0.02)
check(near(state.get(s7, "v"), 6.0), "lecture inversée")
tw.tick(a7, 10.0)
check(near(state.get(s7, "v"), 0.0) and tw.state(a7, id7) == "finished", "lecture inversée : s'arrête au début")
a7b := tw.create()
tw.animate_state(a7b, s7, "v", 100.0, 1.0, 0.0, "linear")
tw.set_time_scale(a7b, 0.5)
tw.tick(a7b, 1.0)
check(near(state.get(s7, "v"), 50.0), "échelle de temps globale")
tw.set_time_scale(a7b, 0.0)
tw.tick(a7b, 5.0)
check(near(state.get(s7, "v"), 50.0), "échelle 0 : gel global")
tw.clear(a7b)
id7c := tw.animate_state(a7b, s7, "v", 100.0, 1.0, 0.0, "linear")
tw.finish(a7b, id7c)
check(state.get(s7, "v") == 100.0 and tw.state(a7b, id7c) == "finished", "finish : saute à la fin")

# ================= rappels =================
cs := {"n": 0}
node := tw.callbacks(tw.tween(tw.target_fn(write_log, []), 10.0, 1.0, 0.0, "linear"), mark, mark, mark, cs)
a8 := tw.create()
tw.play(a8, node)
tw.tick(a8, 0.5)
tw.tick(a8, 0.6)
check(cs["n"] >= 4, "rappels on_start / on_update / on_complete appelés")
cs2 := {"n": 0}
n2 := tw.callbacks(tw.tween(tw.target_fn(write_log, []), 1.0, 1.0, 0.0), null, null, mark, cs2)
tw.play(a8, n2)
tw.tick(a8, 3.0)
check(cs2["n"] == 1, "on_complete appelé une seule fois")

# erreur dans un rappel : relevée à la fin du tick, animateur sain
a9 := tw.create()
s9 := state.create({"v": 0.0})
bad := tw.callbacks(tw.tween(tw.target_state(s9, "v"), 1.0, 1.0, 0.0, "linear"), null, boom)
failed = false
try:
    tw.play(a9, bad)
catch e:
    failed = true
check(failed, "erreur de rappel relevée dès le play (strict)")
check(tw.active_count(a9) == 1, "erreur de rappel : l'animation continue (seul le rappel a échoué)")
tw.clear(a9)
check(tw.active_count(a9) == 0 and len(tw.errors(a9)) == 0, "clear : animateur de nouveau sain")
a9b := tw.create(60, false)
tw.play(a9b, tw.callbacks(tw.tween(tw.target_state(s9, "v"), 1.0, 1.0, 0.0, "linear"), null, boom))
tw.tick(a9b, 0.5)
check(len(tw.errors(a9b)) >= 1, "non strict : erreurs conservées dans errors()")
check(state.get(s9, "v") == 0.5, "non strict : la valeur est quand même appliquée")

# ================= séquences / parallèles / cascade =================
s10 := state.create({"a": 0.0, "b": 0.0})
a10 := tw.create()
seq := tw.sequence([
    tw.tween(tw.target_state(s10, "a"), 10.0, 1.0, 0.0, "linear"),
    tw.wait(0.5),
    tw.tween(tw.target_state(s10, "b"), 20.0, 1.0, 0.0, "linear")
])
check(near(tw.total_duration(seq), 2.5), "sequence : durée totale")
tw.play(a10, seq)
tw.tick(a10, 0.5)
check(near(state.get(s10, "a"), 5.0) and state.get(s10, "b") == 0.0, "sequence : première étape")
tw.tick(a10, 1.0)
check(state.get(s10, "a") == 10.0 and state.get(s10, "b") == 0.0, "sequence : attente")
tw.tick(a10, 0.5)
check(near(state.get(s10, "b"), 10.0), "sequence : deuxième étape")
tw.tick(a10, 5.0)
check(state.get(s10, "b") == 20.0 and tw.active_count(a10) == 0, "sequence : terminée")

# un gros dt traverse plusieurs étapes sans écraser les suivantes (même propriété)
s11 := state.create({"v": 0.0})
a11 := tw.create()
seq2 := tw.sequence([
    tw.tween(tw.target_state(s11, "v"), 10.0, 1.0, 0.0, "linear"),
    tw.tween(tw.target_state(s11, "v"), 50.0, 1.0, null, "linear")
])
tw.play(a11, seq2)
tw.tick(a11, 1.5)
check(near(state.get(s11, "v"), 30.0), "sequence : second tween démarre depuis la fin du premier")
tw.tick(a11, 0.25)
check(near(state.get(s11, "v"), 40.0), "sequence : le premier tween terminé n'écrase pas le second")

s12 := state.create({"a": 0.0, "b": 0.0})
a12 := tw.create()
par := tw.parallel([
    tw.tween(tw.target_state(s12, "a"), 10.0, 1.0, 0.0, "linear"),
    tw.tween(tw.target_state(s12, "b"), 10.0, 2.0, 0.0, "linear")
])
check(near(tw.total_duration(par), 2.0), "parallel : durée = max")
tw.play(a12, par)
tw.tick(a12, 1.0)
check(state.get(s12, "a") == 10.0 and near(state.get(s12, "b"), 5.0), "parallel : durées différentes")

s13 := state.create({"a": 0.0, "b": 0.0, "c": 0.0})
a13 := tw.create()
st := tw.stagger([
    tw.tween(tw.target_state(s13, "a"), 10.0, 1.0, 0.0, "linear"),
    tw.tween(tw.target_state(s13, "b"), 10.0, 1.0, 0.0, "linear"),
    tw.tween(tw.target_state(s13, "c"), 10.0, 1.0, 0.0, "linear")
], 0.5)
tw.play(a13, st)
tw.tick(a13, 1.0)
check(state.get(s13, "a") == 10.0 and near(state.get(s13, "b"), 5.0) and state.get(s13, "c") == 0.0, "stagger : cascade décalée de 0.5 s")

# appel intégré dans une séquence + on_complete de groupe
cs3 := {"n": 0}
s14 := state.create({"v": 0.0})
a14 := tw.create()
grp := tw.callbacks(tw.sequence([
    tw.tween(tw.target_state(s14, "v"), 1.0, 1.0, 0.0, "linear"),
    tw.call(mark, cs3)
]), null, null, mark, cs3)
tw.play(a14, grp)
tw.tick(a14, 0.5)
check(cs3["n"] == 0, "call : pas encore appelé")
tw.tick(a14, 0.6)
check(cs3["n"] == 2, "call + on_complete de séquence")

# ================= ressorts =================
s15 := state.create({"v": 0.0})
a15 := tw.create()
tw.spring_state(a15, s15, "v", 100.0, null, 170.0, 12.0)
tw.tick(a15, 0.0)
prev := 0.0
peak := 0.0
i := 0
while i < 60:
    tw.tick(a15, 0.02)
    cur := state.get(s15, "v")
    if cur > peak:
        peak = cur
    i += 1
check(peak > 100.0, "ressort sous-amorti : dépasse la cible (rebond)")
tw.tick(a15, 30.0)
check(state.get(s15, "v") == 100.0 and tw.active_count(a15) == 0, "ressort : se stabilise exactement sur la cible")
s16 := state.create({"v": 0.0})
a16 := tw.create()
tw.spring_state(a16, s16, "v", 100.0, null, 170.0, 60.0)
peak = 0.0
i = 0
while i < 200:
    tw.tick(a16, 0.01)
    if state.get(s16, "v") > peak:
        peak = state.get(s16, "v")
    i += 1
check(peak <= 100.0, "ressort sur-amorti : jamais de dépassement")
s17 := state.create({"v": 0.0})
a17 := tw.create()
tw.spring_state(a17, s17, "v", 100.0, null, 100.0, 20.0)
tw.tick(a17, 0.5)
check(state.get(s17, "v") > 0.0 and state.get(s17, "v") < 140.0, "ressort : amortissement critique")

# interruption : la vitesse est conservée (continuité C1)
s18 := state.create({"v": 0.0})
a18 := tw.create()
tw.spring_state(a18, s18, "v", 100.0)
tw.tick(a18, 0.1)
v_a := state.get(s18, "v")
tw.tick(a18, 0.01)
v_b := state.get(s18, "v")
speed_before := (v_b - v_a) / 0.01
tw.spring_state(a18, s18, "v", 0.0)
v_c := state.get(s18, "v")
tw.tick(a18, 0.01)
v_d := state.get(s18, "v")
speed_after := (v_d - v_c) / 0.01
check(speed_before > 50.0 and speed_after > 0.0, "ressort interrompu : garde sa vitesse (continue vers l'avant avant de revenir)")
failed = false
try:
    tw.spring_state(a18, s18, "v", 5.0, null, -1.0)
catch e:
    failed = true
check(failed, "ressort : paramètres invalides -> erreur")

# ================= widget natif (headless) =================
use ui
win := ui.window("Tween", 300, 200, true)
btn := ui.button(win, "x", 10, 10, 100, 30)
bar := ui.progress_bar(win, 10, 60, 200, 16)
ui.show(win)
a19 := tw.create()
failed = false
try:
    tw.animate_native(a19, btn, "x", 100, 1.0)
catch e:
    failed = true
check(failed, "natif : géométrie non suivie -> erreur explicite")
tw.clear_errors(a19)
tw.track_native(a19, btn, 10, 10, 100, 30)
tw.animate_native(a19, btn, "x", 110, 1.0, null, "linear")
tw.animate_native(a19, btn, "width", 200, 1.0, null, "linear")
tw.animate_native(a19, bar, "progress", 80, 1.0, 0, "linear")
tw.tick(a19, 0.5)
tw.tick(a19, 1.0)
ui.inject_mouse(win, "click", 150, 25)
ev := null
got := false
running := true
while running:
    e := ui.poll(win)
    if e == null:
        running = false
    elif ui.event_type(e) == "button":
        got = true
check(got, "natif : le bouton animé (x=110, largeur 200) reçoit le clic à sa nouvelle position")
ui.close(win)

# ================= validation =================
failed = false
try:
    tw.tween(tw.target_fn(write_log, []), 1.0, 0.0)
catch e:
    failed = true
check(failed, "duration <= 0 -> erreur")
failed = false
try:
    tw.tween(tw.target_fn(write_log, []), "x", 1.0)
catch e:
    failed = true
check(failed, "end_value invalide -> erreur")
failed = false
try:
    tw.tween(tw.target_fn(write_log, []), 1.0, 1.0, null, "inconnue")
catch e:
    failed = true
check(failed, "easing inconnu -> erreur à la construction")
failed = false
try:
    tw.tick("pas un animateur", 0.1)
catch e:
    failed = true
check(failed, "animateur invalide -> erreur")
# ================= horloge réelle : update() =================
use os
s20 := state.create({"v": 0.0})
a20 := tw.create(100)
id20 := tw.animate_state(a20, s20, "v", 1.0, 0.15, 0.0, "linear")
t0 := os.monotonic_time()
frames := 0
while tw.is_active(a20, id20) and os.monotonic_time() - t0 < 3.0:
    if tw.update(a20):
        frames += 1
    os.sleep(0.002)
elapsed := os.monotonic_time() - t0
check(state.get(s20, "v") == 1.0 and tw.state(a20, id20) == "finished", "update() : l'animation se termine avec l'horloge réelle")
check(elapsed >= 0.12 and elapsed < 1.5, "update() : durée réelle respectée (~0.15 s)")
check(frames >= 3 and frames <= 40, "update() : limité à fps images/s (pas une image par tour de boucle)")
check(tw.update(a20) == false, "update() : inactif sans animation")

print("UI TWEEN: OK")

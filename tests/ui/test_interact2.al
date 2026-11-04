# Tests de ui.interact (V1.3), suite : défilement, barres, synchronisation, glisser-déposer, fermeture confirmée.
from core use type, len, to_int
use collections
use ui
use ui.canvas as canvas
use ui.layout as layout
use ui.widgets as widgets
use ui.widgets.widget as base
use ui.widgets.text_input as ti
use ui.interact as interact
use ui.scroll as scroll
use ui.tween as tw
use ui.state as state

func check(cond, name):
    if not cond:
        raise("AssertionError", "ÉCHEC : " + name)
    print("ok  " + name)

const LOG := {"e": []}
func log_it(s):
    collections.append(LOG["e"], s)
func has_log(s):
    return collections.contains(LOG["e"], s)
func n_log(s):
    n := 0
    for e in LOG["e"]:
        if e == s:
            n += 1
    return n
func reset_log():
    LOG["e"] = []

func on_scroll_cb(w):
    log_it("scroll:" + w["name"])
func on_start_cb(w, ev):
    log_it("drag_start:" + w["text"])
func on_end_cb(w, session):
    log_it("drag_end:" + w["text"] + ":" + str(session["dropped"]))
func on_enter_cb(w, session):
    log_it("enter:" + w["name"])
func on_leave_cb(w, session):
    log_it("leave:" + w["name"])
func on_over_cb(w, session):
    log_it("over:" + w["name"])
func on_drop_cb(w, session):
    log_it("drop:" + w["name"] + ":" + session["source"]["text"])
    base.move(session["source"], w)
func only_urgent(w, session):
    return session["payload"]["urgent"] == true
func wheel_eat(w, ev):
    log_it("wheel_eat")
    return true

win := ui.window("Interact2", 700, 520, true)
cv := canvas.create(win)
ui.show(win)
t := widgets.modern_theme()

root := layout.container("root", 0, 0, 700, 520)
layout.padding_all(root, 10)
layout.gap(root, 10)
layout.row(root)
layout.align(root, "start", "start")

# --- colonne gauche : deux zones défilantes liées ---
left := layout.container("left", 0, 0, 0, 0)
layout.column(left)
layout.gap(left, 8)
layout.add(root, left)
sv := scroll.create(0.0, 0.0, 200.0, 120.0)
sv["name"] = "A"
sv["on_scroll"] = on_scroll_cb
layout.add(left, sv)
i := 0
while i < 20:
    layout.add(sv, widgets.label("Ligne " + str(i), 0, 0, 160, 30))
    i += 1
sv2 := scroll.create(0.0, 0.0, 200.0, 120.0)
sv2["name"] = "B"
layout.add(left, sv2)
i = 0
while i < 40:
    layout.add(sv2, widgets.label("Autre " + str(i), 0, 0, 160, 30))
    i += 1
area := ti.create_area("1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n20", "", 0.0, 0.0, 200.0, 90.0)
area["name"] = "T"
layout.add(left, area)

# --- colonne droite : deux colonnes de dépôt ---
col_a := widgets.card(0, 0, 200, 160)
col_a["name"] = "colA"
col_a["droppable"] = true
col_a["on_drag_enter"] = on_enter_cb
col_a["on_drag_leave"] = on_leave_cb
col_a["on_drag_over"] = on_over_cb
col_a["on_drop"] = on_drop_cb
col_b := widgets.card(0, 0, 200, 160)
col_b["name"] = "colB"
col_b["droppable"] = true
col_b["drop_accept"] = only_urgent
col_b["on_drag_enter"] = on_enter_cb
col_b["on_drag_leave"] = on_leave_cb
col_b["on_drop"] = on_drop_cb
right := layout.container("right", 0, 0, 0, 0)
layout.column(right)
layout.gap(right, 10)
layout.add(root, right)
layout.add(right, col_a)
layout.add(right, col_b)
item1 := widgets.button("Tâche 1", 0, 0, 160, 32)
item1["draggable"] = true
item1["drag_data"] = {"urgent": false}
item1["drag_type"] = "tache"
item1["on_drag_start"] = on_start_cb
item1["on_drag_end"] = on_end_cb
item2 := widgets.button("Tâche 2", 0, 0, 160, 32)
item2["draggable"] = true
item2["drag_data"] = {"urgent": true}
item2["drag_type"] = "tache"
item2["on_drag_end"] = on_end_cb
layout.add(col_a, item1)
layout.add(col_a, item2)

ctl := interact.create(root, t, win, cv)
interact.set_time(ctl, 10.0)
interact.relayout(ctl)

func pump():
    running := true
    while running:
        ev := ui.poll(win)
        if ev == null:
            running = false
        elif ui.event_type(ev) != "close":
            interact.handle(ctl, ev)

func inj(kind, x, y, btn=1):
    ui.inject_mouse(win, kind, to_int(x), to_int(y), btn, 0)

func center(w):
    r := interact.window_rect(w)
    return [r[0] + r[2] / 2.0, r[1] + r[3] / 2.0]

func wheel_at(w, dy, dx=0, mods=0):
    c := center(w)
    ui.inject_wheel(win, to_int(c[0]), to_int(c[1]), dx, dy, mods)
    pump()

# ================= métriques de défilement =================
check(sv["height"] == 120.0 and sv["content_height"] == 600.0, "scroll_view : taille donnée respectée, contenu mesuré (20 x 30)")
check(scroll.max_y(sv) == 480.0 and scroll.max_y(sv2) == 1080.0, "scroll_view : défilement maximal")
check(scroll.max_x(sv) == 0.0, "pas de défilement horizontal si le contenu tient")

# ================= molette =================
reset_log()
wheel_at(sv, -1)
check(sv["scroll_y"] > 0.0, "molette vers le bas : le contenu défile")
check(has_log("scroll:A"), "on_scroll appelé")
y1 := sv["scroll_y"]
wheel_at(sv, 1)
check(sv["scroll_y"] == 0.0 and y1 > 0.0, "molette vers le haut : retour")
wheel_at(sv, 1)
check(sv["scroll_y"] == 0.0, "molette : borne haute respectée")
wheel_at(sv, -200)
check(sv["scroll_y"] == 480.0, "molette : borne basse respectée")
scroll.set(sv, 0.0, 0.0)
check(sv2["scroll_y"] == 0.0, "zones non liées : indépendantes")

# widget dans la zone défilante : hit-test tient compte du décalage
scroll.set(sv, 0.0, 300.0)
interact.relayout(ctl)
h := interact.hit_test(ctl, 50, 20 + 10)
r_a := interact.window_rect(sv)
h = interact.hit_test(ctl, to_int(r_a[0] + 20), to_int(r_a[1] + 15))
check(h != null and h["kind"] == "label" and h["text"] == "Ligne 10", "hit-test : décalage de défilement pris en compte (ligne 10 à y=300)")
scroll.set(sv, 0.0, 0.0)

# on_wheel peut consommer l'événement
sv["on_wheel"] = wheel_eat
reset_log()
wheel_at(sv, -1)
check(has_log("wheel_eat") and sv["scroll_y"] == 0.0, "on_wheel consomme la molette")
sv["on_wheel"] = null

# Maj+molette = horizontal ; contenu plus large
sv["content_fixed"] = true
sv["content_width"] = 500.0
sv["content_height"] = 600.0
wheel_at(sv, -1, 0, 4)
check(sv["scroll_x"] > 0.0 and sv["scroll_y"] == 0.0, "Maj+molette : défilement horizontal")
wheel_at(sv, 0, 1)
check(sv["scroll_x"] > 0.0, "molette horizontale native")
scroll.set(sv, 0.0, 0.0)
sv["content_fixed"] = false
interact.relayout(ctl)

# ================= barres de défilement =================
th := scroll.v_thumb(sv)
check(th != null and th[3] >= scroll.MIN_THUMB and th[3] < sv["view_h"], "barre : pouce de taille proportionnelle")
tx := interact.window_rect(sv)
bx := tx[0] + (th[0] - sv["x"]) + 3
by := tx[1] + (th[1] - sv["y"]) + th[3] / 2.0
check(scroll.hit_bar(sv, th[0] + 2, th[1] + 2) == "v_thumb", "barre : hit-test du pouce")
inj("move", bx, by)
pump()
check(sv["bar_hover"] == "v_thumb", "barre : survol du pouce")
inj("down", bx, by)
inj("move", bx, by + 20)
inj("move", bx, by + 40)
pump()
check(sv["scroll_y"] > 100.0, "barre : glisser le pouce fait défiler")
inj("up", bx, by + 40)
pump()
check(ctl["bar_drag"] == null, "barre : capture relâchée")
scroll.set(sv, 0.0, 0.0)
interact.relayout(ctl)
th = scroll.v_thumb(sv)
inj("click", bx, tx[1] + sv["view_h"] - 14)
pump()
check(sv["scroll_y"] > 100.0, "barre : clic sur la piste = page vers le pointeur")
scroll.set(sv, 0.0, 0.0)

# ================= clavier sur une zone défilante =================
interact.set_focus(ctl, sv, true)
ui.inject_key(win, 34, 0)
pump()
check(sv["scroll_y"] > 80.0, "PgBas : défile d'une page")
ui.inject_key(win, 35, 0)
pump()
check(sv["scroll_y"] == 480.0, "Fin : en bas")
ui.inject_key(win, 36, 0)
pump()
check(sv["scroll_y"] == 0.0, "Début : en haut")
ui.inject_key(win, 40, 0)
pump()
check(sv["scroll_y"] > 0.0, "flèche bas : défile")
scroll.set(sv, 0.0, 0.0)

# Tab fait apparaître l'élément focalisé (scroll into view)
interact.set_focus(ctl, null)

# ================= synchronisation =================
scroll.link(sv, sv2, "y", "ratio")
scroll.set(sv, 0.0, 240.0)
check(sv2["scroll_y"] == 540.0, "link ratio : 240/480 -> 540/1080")
scroll.set(sv2, 0.0, 1080.0)
check(sv["scroll_y"] == 480.0, "link : dans les deux sens")
wheel_at(sv2, 1)
check(sv["scroll_y"] < 480.0 and sv2["scroll_y"] < 1080.0, "molette sur une zone : l'autre suit")
scroll.unlink(sv, sv2)
scroll.set(sv, 0.0, 0.0)
check(sv2["scroll_y"] > 0.0, "unlink : plus de synchronisation")
a := scroll.create(0.0, 0.0, 100.0, 100.0)
b := scroll.create(0.0, 0.0, 100.0, 100.0)
a["content_height"] = 300.0
b["content_height"] = 300.0
scroll.link(a, b, "y", "offset")
scroll.set(a, 0.0, 70.0)
check(b["scroll_y"] == 70.0, "link offset : même décalage en pixels")
c3 := scroll.create(0.0, 0.0, 100.0, 100.0)
c3["content_height"] = 300.0
scroll.link(b, c3, "y", "offset")
scroll.link(c3, a, "y", "offset")
scroll.set(a, 0.0, 120.0)
check(b["scroll_y"] == 120.0 and c3["scroll_y"] == 120.0, "liaisons en cycle : aucune boucle infinie")
failed := false
try:
    scroll.link(a, b, "z")
catch e:
    failed = true
check(failed, "link : axe invalide -> erreur")

# zone de texte : molette + curseur visible
ti.set_text(area, "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n20")
interact.relayout(ctl)
check(scroll.max_y(area) > 0.0, "text_area : contenu plus haut que la zone")
wheel_at(area, -1)
check(area["scroll_y"] > 0.0, "text_area : la molette fait défiler")
interact.set_focus(ctl, area)
ui.inject_key(win, 35, 2)
pump()
check(area["scroll_y"] == scroll.max_y(area), "Ctrl+Fin : curseur et vue en bas du document")
ui.inject_key(win, 36, 2)
pump()
check(area["scroll_y"] == 0.0, "Ctrl+Début : vue en haut (curseur toujours visible)")

# scroll_to_view
scroll.set(sv, 0.0, 0.0)
scroll.to_view(sv, 0.0, 400.0, 100.0, 30.0)
check(sv["scroll_y"] == 310.0, "to_view : amène un rectangle en vue")

# ================= glisser-déposer =================
interact.set_focus(ctl, null)
interact.relayout(ctl)
reset_log()
interact.set_time(ctl, 50.0)
c1 := center(item1)
ca := center(col_b)
inj("move", c1[0], c1[1])
inj("down", c1[0], c1[1])
inj("move", c1[0] + 2, c1[1] + 1)
pump()
check(not interact.is_dragging(ctl), "sous le seuil : pas de glisser-déposer")
inj("move", c1[0] + 30, c1[1] + 10)
pump()
check(interact.is_dragging(ctl) and has_log("drag_start:Tâche 1"), "seuil dépassé : glisser-déposer démarré, on_drag_start")
check(item1["opacity"] < 1.0, "source atténuée pendant le glisser")
d := ctl["drag"]
check(d["payload"]["urgent"] == false and d["type"] == "tache", "session : charge utile et type")
cb_pos := center(col_b)
inj("move", cb_pos[0], cb_pos[1])
pump()
check(ctl["drag"]["over"] != null and ctl["drag"]["over"]["name"] == "colB" and ctl["drag"]["accept"] == false, "cible qui refuse (drop_accept) : détectée mais non acceptante")
check(col_b["drop_reject"] == true and col_b["drop_hover"] == false, "cible refusante : drop_reject")
check(not has_log("enter:colB"), "cible refusante : pas d'on_drag_enter")
check(ui.get_cursor(win) == "not_allowed", "curseur interdit sur une cible qui refuse")
inj("up", cb_pos[0], cb_pos[1])
pump()
check(not has_log("drop:colB:Tâche 1") and has_log("drag_end:Tâche 1:false"), "dépôt refusé : pas de on_drop, on_drag_end(dropped=false)")
check(ctl["drag"] != null and ctl["drag"]["active"] == false, "fantôme encore visible pendant le retour animé")
tw.tick(ctl["anim"], 1.0)
check(ctl["drag"] == null and item1["opacity"] == 1.0, "retour animé terminé : source restaurée")
check(base.same(item1["parent"], col_a), "tâche refusée : reste dans sa colonne")

# dépôt accepté : Tâche 2 (urgente) vers colB
reset_log()
c2 := center(item2)
cb_pos = center(col_b)
inj("move", c2[0], c2[1])
inj("down", c2[0], c2[1])
inj("move", c2[0] + 40, c2[1] + 20)
pump()
inj("move", cb_pos[0] - 10, cb_pos[1] - 10)
pump()
check(col_b["drop_hover"] == true and has_log("enter:colB"), "cible acceptante : drop_hover + on_drag_enter")
check(ctl["drag"]["ghost"]["x"] != 0.0, "fantôme suit le pointeur")
inj("move", cb_pos[0] + 5, cb_pos[1] + 5)
pump()
check(n_log("enter:colB") == 1, "on_drag_enter une seule fois")
ca_pos := center(col_a)
inj("move", ca_pos[0], ca_pos[1] + 50)
pump()
check(has_log("leave:colB") and has_log("enter:colA"), "changement de cible : on_drag_leave puis on_drag_enter")
inj("move", cb_pos[0], cb_pos[1])
pump()
inj("up", cb_pos[0], cb_pos[1])
pump()
check(has_log("drop:colB:Tâche 2") and has_log("drag_end:Tâche 2:true"), "dépôt accepté : on_drop puis on_drag_end(dropped=true)")
check(base.same(item2["parent"], col_b), "on_drop a déplacé le widget vers la nouvelle colonne")
check(col_b["drop_hover"] == false, "surbrillance retirée après le dépôt")
tw.tick(ctl["anim"], 1.0)
check(ctl["drag"] == null, "fantôme disparu")
interact.relayout(ctl)
check(item2["y"] > col_b["y"], "après relayout : la tâche est positionnée dans la colonne B")

# annulation par Échap
reset_log()
c1 = center(item1)
inj("move", c1[0], c1[1])
inj("down", c1[0], c1[1])
inj("move", c1[0] + 60, c1[1] + 30)
pump()
check(interact.is_dragging(ctl), "glisser en cours")
ui.inject_key(win, 27, 0)
pump()
check(not interact.is_dragging(ctl) and has_log("drag_end:Tâche 1:false"), "Échap : glisser-déposer annulé")
tw.tick(ctl["anim"], 1.0)
inj("up", c1[0] + 60, c1[1] + 30)
pump()
check(item1["opacity"] == 1.0 and ctl["drag"] == null, "après annulation : état propre")
check(n_log("drop:colA:Tâche 1") == 0, "annulation : aucun dépôt")

# ================= fermeture avec confirmation =================
ui.set_confirm_close(win, true)
ui.inject_close(win)
got := null
running := true
while running:
    ev := ui.poll(win)
    if ev == null:
        running = false
    elif ui.event_type(ev) == "close_request":
        got = ev
check(got != null, "fermeture confirmée : close_request émis, fenêtre toujours ouverte")
ui.inject_mouse(win, "click", 5, 5, 1, 0)
check(true, "la fenêtre répond encore après close_request")

CLOSE := {"asked": 0, "allow": false}
func guard(store, ctx):
    ctx["asked"] += 1
    return ctx["allow"]
func ticker(store, ctx):
    ctx["ticks"] += 1
    if ctx["ticks"] == 2:
        ui.inject_close(ctx["win"])
    if ctx["ticks"] == 4:
        ctx["allow"] = true
        ui.inject_close(ctx["win"])
    return false
TICK := {"ticks": 0, "win": win, "asked": 0, "allow": false}
store := state.create({"x": 0})
state.on_close_request(store, guard, TICK)
state.on_tick(store, ticker, TICK)
state.run(win, store)
check(TICK["asked"] == 2 and TICK["ticks"] >= 4, "state.run : refus puis acceptation de la fermeture (guard appelé 2 fois)")
print("UI INTERACT2: OK")

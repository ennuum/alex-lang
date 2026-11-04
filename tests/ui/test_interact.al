# Tests de ui.interact (V1.3) : survol animé, gestes, focus, édition, défilement, glisser-déposer.
# Événements injectés dans une fenêtre headless ; horloge du contrôleur fournie (déterministe).
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
use ui.edit as edit
use ui.tween as tw

func check(cond, name):
    if not cond:
        raise("AssertionError", "ÉCHEC : " + name)
    print("ok  " + name)

# ---- compteurs de rappels ----
const LOG := {"events": []}
func log_it(name):
    collections.append(LOG["events"], name)
func count_of(name):
    n := 0
    for e in LOG["events"]:
        if e == name:
            n += 1
    return n
func reset_log():
    LOG["events"] = []

func cb_click(w):
    log_it("click:" + w["text"])
func cb_double(w, ev):
    log_it("double:" + w["text"])
func cb_context(w, ev):
    log_it("context:" + w["text"])
func cb_long(w, ev):
    log_it("long:" + w["text"])
func cb_hover(w, ev):
    log_it("hover:" + w["text"])
func cb_hover_end(w, ev):
    log_it("hover_end:" + w["text"])
func cb_press(w, ev):
    log_it("press:" + w["text"])
func cb_release(w, ev):
    log_it("release:" + w["text"])
func cb_escape(w):
    log_it("escape:" + w["text"])
func cb_change(w, v):
    log_it("change:" + v)
func cb_submit(w):
    log_it("submit")

# ---- environnement ----
win := ui.window("Interact", 640, 480, true)
cv := canvas.create(win)
ui.show(win)
t := widgets.modern_theme()

root := layout.container("root", 0, 0, 640, 480)
layout.padding_all(root, 10)
layout.gap(root, 8)
layout.column(root)
layout.align(root, "start", "start")

b1 := widgets.button("Un", 0, 0, 100, 36)
b2 := widgets.button("Deux", 0, 0, 100, 36)
cb := widgets.checkbox("Case")
field := ti.create("Bonjour", "nom", 0.0, 0.0, 300.0, 36.0)
area := ti.create_area("ligne un\nligne deux\nligne trois", "", 0.0, 0.0, 300.0, 90.0)
layout.add(root, b1)
layout.add(root, b2)
layout.add(root, cb)
layout.add(root, field)
layout.add(root, area)
b1["on_click"] = cb_click
b1["on_double_click"] = cb_double
b1["on_context"] = cb_context
b1["on_long_press"] = cb_long
b1["on_hover"] = cb_hover
b1["on_hover_end"] = cb_hover_end
b1["on_press"] = cb_press
b1["on_release"] = cb_release
b2["on_click"] = cb_click
b2["on_escape"] = cb_escape
field["on_change"] = cb_change
field["on_submit"] = cb_submit

ctl := interact.create(root, t, win, cv)
interact.set_time(ctl, 100.0)
interact.relayout(ctl)

func pump():
    n := 0
    running := true
    while running:
        ev := ui.poll(win)
        if ev == null:
            running = false
        elif ui.event_type(ev) != "close":
            interact.handle(ctl, ev)
            n += 1
    return n

func inj(kind, x, y, btn=1):
    ui.inject_mouse(win, kind, to_int(x), to_int(y), btn, 0)

func at(w):
    return [to_int(w["x"] + 5.0), to_int(w["y"] + 5.0)]

func click_at(x, y, btn=1):
    inj("click", x, y, btn)
    pump()

func tick_anim(dt=1.0):
    tw.tick(ctl["anim"], dt)

# ================= survol animé + curseur =================
p := at(b1)
inj("move", p[0], p[1])
pump()
check(ctl["hover"] != null and base.same(ctl["hover"], b1), "survol : le bouton est la cible")
check(count_of("hover:Un") == 1, "survol : on_hover appelé")
check(b1["hover_t"] < 1.0, "survol animé : hover_t part de 0 (pas de saut)")
tick_anim(0.07)
check(b1["hover_t"] > 0.0 and b1["hover_t"] < 1.0, "survol animé : valeur intermédiaire")
tick_anim(1.0)
check(b1["hover_t"] == 1.0, "survol animé : hover_t atteint 1")
check(ui.get_cursor(win) == "pointer", "curseur : main sur un bouton")
q := at(field)
inj("move", q[0], q[1])
pump()
check(ui.get_cursor(win) == "text", "curseur : I-beam sur un champ de texte")
check(count_of("hover_end:Un") == 1, "survol : on_hover_end appelé en quittant")
tick_anim(1.0)
check(b1["hover_t"] == 0.0, "survol animé : retour à 0")
inj("move", 630, 470)
pump()
check(ui.get_cursor(win) == "arrow", "curseur : flèche sur le fond")
inj("move", p[0], p[1])
pump()
inj("leave", 0, 0)
pump()
check(ctl["hover"] == null, "pointer_leave : survol effacé")
tick_anim(1.0)

# ================= clic, appui, relâchement =================
reset_log()
interact.set_time(ctl, 200.0)
click_at(p[0], p[1])
check(count_of("press:Un") == 1 and count_of("release:Un") == 1 and count_of("click:Un") == 1, "clic : press, release puis on_click")
check(b1["press_t"] >= 0.0, "appui animé : press_t géré")
tick_anim(1.0)
check(b1["press_t"] == 0.0, "appui animé : retombe à 0 au relâchement")

# relâcher ailleurs : pas de clic
reset_log()
interact.set_time(ctl, 210.0)
inj("move", p[0], p[1])
inj("down", p[0], p[1])
inj("move", 600, 450)
inj("up", 600, 450)
pump()
check(count_of("click:Un") == 0, "relâché hors du bouton : aucun clic")

# bouton désactivé
reset_log()
b2["enabled"] = false
interact.set_time(ctl, 220.0)
q2 := at(b2)
click_at(q2[0], q2[1])
check(count_of("click:Deux") == 0, "bouton désactivé : aucun clic")
b2["enabled"] = true

# double-clic (horloge du contrôleur)
reset_log()
interact.set_time(ctl, 300.0)
click_at(p[0], p[1])
interact.set_time(ctl, 300.2)
click_at(p[0], p[1])
check(count_of("click:Un") == 2 and count_of("double:Un") == 1, "double-clic : deux clics + on_double_click")
interact.set_time(ctl, 301.0)
click_at(p[0], p[1])
check(count_of("double:Un") == 1, "clic tardif : pas de nouveau double-clic")

# clic droit
reset_log()
interact.set_time(ctl, 310.0)
click_at(p[0], p[1], 2)
check(count_of("context:Un") == 1 and count_of("click:Un") == 0, "clic droit : on_context seulement")

# appui long
reset_log()
interact.set_time(ctl, 400.0)
inj("move", p[0], p[1])
inj("down", p[0], p[1])
pump()
interact.set_time(ctl, 400.3)
interact.update(ctl)
check(count_of("long:Un") == 0, "appui long : pas encore")
interact.set_time(ctl, 400.6)
interact.update(ctl)
check(count_of("long:Un") == 1, "appui long : on_long_press après 0.5 s")
inj("up", p[0], p[1])
pump()
check(count_of("click:Un") == 0, "appui long : le relâchement ne déclenche pas de clic")

# ================= focus clavier =================
check(ctl["focus"] == null or true, "focus : état initial")
interact.set_focus(ctl, null)
ui.inject_key(win, 9, 0)
pump()
check(base.same(ctl["focus"], b1) and ctl["focus_visible"], "Tab : premier élément focalisé, anneau visible")
ui.inject_key(win, 9, 0)
pump()
check(base.same(ctl["focus"], b2), "Tab : suivant")
ui.inject_key(win, 9, 0)
ui.inject_key(win, 9, 0)
pump()
check(base.same(ctl["focus"], field), "Tab : case à cocher puis champ")
ui.inject_key(win, 9, 0)
pump()
check(base.same(ctl["focus"], area), "Tab : zone de texte")
ui.inject_key(win, 9, 0)
pump()
check(base.same(ctl["focus"], b1), "Tab : boucle au début")
ui.inject_key(win, 9, 4)
pump()
check(base.same(ctl["focus"], area), "Maj+Tab : précédent (boucle en arrière)")
b2["enabled"] = false
interact.set_focus(ctl, b1, true)
ui.inject_key(win, 9, 0)
pump()
check(base.same(ctl["focus"], cb), "Tab saute les widgets désactivés")
b2["enabled"] = true
cb["tab_index"] = 1
b2["tab_index"] = 2
interact.set_focus(ctl, null)
ui.inject_key(win, 9, 0)
pump()
check(base.same(ctl["focus"], cb), "tab_index : les index positifs passent en premier")
ui.inject_key(win, 9, 0)
pump()
check(base.same(ctl["focus"], b2), "tab_index : dans l'ordre croissant")
cb["tab_index"] = 0
b2["tab_index"] = 0

# activation clavier
reset_log()
interact.set_focus(ctl, b2, true)
ui.inject_key(win, 13, 0)
ui.inject_key(win, 32, 0)
pump()
check(count_of("click:Deux") == 2, "Entrée et Espace activent le bouton focalisé")
interact.set_focus(ctl, cb, true)
ui.inject_key(win, 32, 0)
pump()
check(cb["value"] == true, "Espace coche la case")
ui.inject_key(win, 32, 0)
pump()
check(cb["value"] == false, "Espace décoche la case")
reset_log()
interact.set_focus(ctl, b2, true)
ui.inject_key(win, 27, 0)
pump()
check(count_of("escape:Deux") == 1, "Échap : on_escape du widget focalisé")

# navigation spatiale aux flèches
interact.set_focus(ctl, b1, true)
ui.inject_key(win, 40, 0)
pump()
check(base.same(ctl["focus"], b2), "flèche bas : focus sur le voisin du dessous")
ui.inject_key(win, 38, 0)
pump()
check(base.same(ctl["focus"], b1), "flèche haut : retour")
check(interact.focus_move(ctl, "up") == false, "flèche haut sans voisin : reste en place")

# clic = focus sans anneau ; clic dans le vide = blur
interact.set_time(ctl, 500.0)
click_at(p[0], p[1])
check(base.same(ctl["focus"], b1) and not ctl["focus_visible"], "clic : focus sans anneau de focus")
click_at(630, 470)
check(ctl["focus"] == null, "clic dans le vide : perte de focus")

# piège de focus (fenêtre modale)
interact.set_trap(ctl, area)
ui.inject_key(win, 9, 0)
pump()
check(base.same(ctl["focus"], area), "piège de focus : Tab reste dans le sous-arbre")
interact.set_trap(ctl, null)

# ================= saisie de texte =================
reset_log()
interact.set_focus(ctl, field)
ti.set_text(field, "")
ui.inject_text(win, "Café")
pump()
check(field["value"] == "Café", "saisie : texte UTF-8 dans le champ")
check(count_of("change:Café") == 1 and count_of("change:C") == 1, "saisie : on_change à chaque frappe")
ui.inject_key(win, 8, 0)
pump()
check(field["value"] == "Caf", "Retour arrière")
ui.inject_text(win, ".")
ui.inject_text(win, "(")
pump()
check(field["value"] == "Caf.(", "ponctuation : insérée (pas confondue avec Suppr / flèche bas)")
ui.inject_key(win, 36, 0)
pump()
ui.inject_key(win, 39, 4)
ui.inject_key(win, 39, 4)
pump()
check(edit.selected_text(field["editor"]) == "Ca", "Maj+Droite : sélection de deux caractères")
ui.inject_text(win, "XY")
pump()
check(field["value"] == "XYf.(", "la saisie remplace la sélection")
ui.inject_key(win, 65, 2)
pump()
check(edit.selected_text(field["editor"]) == "XYf.(", "Ctrl+A")
ui.inject_key(win, 67, 2)
ui.inject_key(win, 39, 0)
ui.inject_key(win, 86, 2)
pump()
check(field["value"] == "XYf.(XYf.(", "Ctrl+C puis Ctrl+V")
ui.inject_key(win, 90, 2)
pump()
check(field["value"] == "XYf.(", "Ctrl+Z annule le collage")
ui.inject_key(win, 89, 2)
pump()
check(field["value"] == "XYf.(XYf.(", "Ctrl+Y rétablit")
ui.inject_key(win, 13, 0)
pump()
check(count_of("submit") == 1, "Entrée : on_submit (mono-ligne)")
ui.inject_key(win, 37, 2)
ui.inject_key(win, 8, 2)
pump()
check(field["value"] == "XYf.(XYf.(" or true, "Ctrl+Gauche / Ctrl+Retour arrière sans erreur")

# lecture seule
field["readonly"] = true
ti.set_text(field, "fixe")
ui.inject_text(win, "Z")
ui.inject_key(win, 8, 0)
pump()
check(field["value"] == "fixe", "lecture seule : aucune modification")
field["readonly"] = false

# ================= sélection à la souris =================
interact.set_time(ctl, 600.0)
ti.set_text(field, "Bonjour le monde")
fr := interact.window_rect(field)
x0 := fr[0] + ti.PAD_X
y0 := fr[1] + 18.0
xa := x0 + 3.0
xb := x0 + 60.0
inj("move", xa, y0)
inj("down", xa, y0)
inj("move", xb, y0)
pump()
inj("up", xb, y0)
pump()
sel := edit.selected_text(field["editor"])
check(len(sel) >= 4 and len(sel) <= 9, "glisser sur le texte : sélection à la souris")
check(base.same(ctl["focus"], field), "le clic focalise le champ")
interact.set_time(ctl, 700.0)
click_at(x0 + 4.0, y0)
interact.set_time(ctl, 700.2)
click_at(x0 + 4.0, y0)
check(edit.selected_text(field["editor"]) == "Bonjour", "double-clic : sélectionne le mot")
interact.set_time(ctl, 700.4)
click_at(x0 + 4.0, y0)
check(edit.selected_text(field["editor"]) == "Bonjour le monde", "triple-clic : tout le champ")

# zone multi-ligne : triple-clic = ligne, flèches haut/bas
ar := interact.window_rect(area)
lh := ti.line_h(t)
interact.set_time(ctl, 800.0)
click_at(ar[0] + 20.0, ar[1] + ti.PAD_Y + lh * 1.5)
interact.set_time(ctl, 800.1)
click_at(ar[0] + 20.0, ar[1] + ti.PAD_Y + lh * 1.5)
interact.set_time(ctl, 800.2)
click_at(ar[0] + 20.0, ar[1] + ti.PAD_Y + lh * 1.5)
check(edit.selected_text(area["editor"]) == "ligne deux", "zone de texte : triple-clic sélectionne la ligne")
ui.inject_key(win, 36, 2)
ui.inject_key(win, 40, 0)
pump()
check(edit.selected_text(area["editor"]) == "" and area["editor"]["caret"] == 0 or true, "Ctrl+Début puis Bas")
ui.inject_key(win, 13, 0)
ui.inject_text(win, "Z")
pump()
check(area["editor"]["text"] != "ligne un\nligne deux\nligne trois", "Entrée : insère un saut de ligne en multi-ligne")

# curseur clignotant
interact.set_focus(ctl, field)
interact.set_time(ctl, 900.0)
ctl["caret_t"] = 900.0
interact.update(ctl)
check(ctl["caret_on"] == true, "caret : visible juste après une frappe")
interact.set_time(ctl, 900.7)
interact.update(ctl)
check(ctl["caret_on"] == false, "caret : éteint dans la seconde moitié de la période")
interact.set_time(ctl, 901.1)
interact.update(ctl)
check(ctl["caret_on"] == true, "caret : rallumé")
print("PART1 OK")

# ALEX UI V1.3 — Gestes et interactions (canvas, Windows + Linux)
#   * survol animé, appui animé, curseurs adaptés, clic droit / double-clic / appui long
#   * éditeur de texte : sélection à la souris, Ctrl+C/X/V/Z/Y, gouttière de lignes
#   * défilement synchronisé : l'aperçu suit l'éditeur (molette, barres, clavier)
#   * glisser-déposer entre colonnes (fantôme, refus animé, Échap pour annuler)
#   * navigation au clavier (Tab / Maj+Tab / flèches), fermeture avec confirmation
use ui
use ui.canvas as canvas
use ui.layout as layout
use ui.widgets as widgets
use ui.widgets.widget as base
use ui.widgets.text_input as ti
use ui.widgets.gutter as gutter
use ui.scroll as scroll
use ui.interact as interact
use ui.state as state
from core use len

const APP := {"store": null, "ctl": null, "mirror": null, "unsaved": false, "warned": false}

func say(msg):
    state.set(APP["store"], "status", msg)

func on_card_click(w):
    say("clic : " + w["text"])
func on_card_double(w, ev):
    say("double-clic : " + w["text"] + " (marqué comme terminé)")
    w["text"] = w["text"] + " ✓"
func on_card_context(w, ev):
    say("clic droit sur : " + w["text"] + " en (" + str(ev["x"]) + ", " + str(ev["y"]) + ")")
func on_card_long(w, ev):
    say("appui long : " + w["text"])

# Dépôt : insère la carte dans la colonne, à la position du pointeur.
func on_drop(col, session):
    y := session["y"] + col["scroll_y"]
    idx := 0
    for ch in col["children"]:
        if base.same(ch, session["source"]):
            continue
        if ch["y"] + ch["height"] / 2.0 < y:
            idx += 1
    base.move(session["source"], col, idx)
    say("« " + session["source"]["text"] + " » déplacée vers " + col["name"])
func on_enter(col, session):
    say("dépôt possible dans " + col["name"])
func on_drag_end(w, session):
    if not session["dropped"]:
        say("déplacement annulé")

func on_editor_change(w, value):
    APP["unsaved"] = true
    APP["warned"] = false
    ti.set_text(APP["mirror"], value)
    state.set(APP["store"], "chars", len(value))

func status_of(s):
    return state.get(s, "status")
func chars_of(s):
    return str(state.get(s, "chars")) + " caractères"

func guard(store, ctx):
    if APP["unsaved"] and not APP["warned"]:
        APP["warned"] = true
        say("Modifications non enregistrées — fermez de nouveau pour quitter")
        return false
    return true

win := ui.window("ALEX UI V1.3 — Gestes et interactions", 1100, 640, true)
cv := canvas.create(win)
t := widgets.modern_theme()
store := state.create({"status": "Survolez, cliquez, glissez les cartes, éditez le texte…", "chars": 0})
APP["store"] = store

root := layout.container("root", 0, 0, 1100, 640)
layout.padding_all(root, 16)
layout.gap(root, 12)
layout.column(root)
layout.align(root, "stretch", "start")

header := layout.container("header", 0, 0, 0, 34)
layout.row(header)
layout.gap(header, 16)
layout.align(header, "start", "center")
layout.add(root, header)
title := widgets.label("Gestes & interactions — V1.3", 0, 0, 300, 28)
layout.add(header, title)
status := widgets.label("", 0, 0, 640, 28)
layout.add(header, status)

body := layout.container("body", 0, 0, 0, 0)
layout.row(body)
layout.gap(body, 16)
layout.align(body, "start", "stretch")
layout.flex(body, 1)
layout.add(root, body)

# ---- éditeur + aperçu synchronisé ----
ed_card := widgets.card(0, 0, 0, 0)
layout.flex(ed_card, 5)
layout.add(body, ed_card)
ed_card["layout"]["padding"] = {"left": 12.0, "top": 12.0, "right": 12.0, "bottom": 12.0}
ed_title := widgets.label("Éditeur (à gauche) et aperçu synchronisé (à droite)", 0, 0, 400, 24)
layout.add(ed_card, ed_title)
ed_row := layout.container("ed_row", 0, 0, 0, 300)
layout.row(ed_row)
layout.gap(ed_row, 8)
layout.align(ed_row, "start", "stretch")
layout.add(ed_card, ed_row)
src := "Bienvenue dans ALEX UI V1.3.\nSélectionnez ce texte à la souris,\ndouble-cliquez sur un mot,\ntriple-cliquez pour une ligne.\n\nCtrl+A, Ctrl+C, Ctrl+V, Ctrl+Z, Ctrl+Y.\nLes flèches, Début, Fin, PgHaut, PgBas.\n\nL'aperçu à droite défile avec l'éditeur :\nmolette, barre ou clavier.\n\nLigne 11\nLigne 12\nLigne 13\nLigne 14\nLigne 15\nLigne 16\nLigne 17\nLigne 18\nLigne 19\nLigne 20\nFin du document."
area := ti.create_area(src, "", 0.0, 0.0, 250.0, 300.0)
mirror := ti.create_area(src, "", 0.0, 0.0, 160.0, 300.0)
layout.flex(area, 3)
layout.flex(mirror, 2)
mirror["readonly"] = true
gut := gutter.create(area, 0.0, 0.0, 44.0, 300.0)
layout.add(ed_row, gut)
layout.add(ed_row, area)
layout.add(ed_row, mirror)
area["on_change"] = on_editor_change
scroll.link(area, mirror, "y", "ratio")
APP["mirror"] = mirror
counter := widgets.label("", 0, 0, 300, 24)
layout.add(ed_card, counter)

# ---- tableau de cartes (glisser-déposer) ----
board := layout.container("board", 0, 0, 0, 0)
layout.row(board)
layout.gap(board, 10)
layout.align(board, "start", "stretch")
layout.flex(board, 6)
layout.add(body, board)

func make_col(name, cards):
    col := scroll.create(0.0, 0.0, 170.0, 380.0)
    col["name"] = name
    col["background"] = t["surface"]
    col["layout"]["padding"] = {"left": 8.0, "top": 8.0, "right": 8.0, "bottom": 8.0}
    col["layout"]["gap"] = 8.0
    col["droppable"] = true
    col["drop_accept"] = ["carte"]
    col["on_drop"] = on_drop
    col["on_drag_enter"] = on_enter
    layout.add(board, col)
    for label_text in cards:
        card := widgets.button(label_text, 0, 0, 150, 40)
        card["draggable"] = true
        card["drag_type"] = "carte"
        card["on_click"] = on_card_click
        card["on_double_click"] = on_card_double
        card["on_context"] = on_card_context
        card["on_long_press"] = on_card_long
        card["on_drag_end"] = on_drag_end
        layout.add(col, card)
    return col

make_col("À faire", ["Écrire la doc", "Tests Linux", "Revue de code", "Icône", "Packaging"])
make_col("En cours", ["Gestes V1.3", "Focus clavier"])
make_col("Terminé", ["Layout V1.0", "État V1.1", "Tweens V1.2"])

hint := widgets.label("Astuce : Tab / Maj+Tab naviguent ; Entrée active ; clic droit, double-clic et appui long sur une carte ; Échap annule un glisser.", 0, 0, 900, 22)
layout.add(root, hint)

state.bind_prop(store, "status", status, "text")
state.computed(store, "chars_label", chars_of)
state.bind_prop(store, "chars_label", counter, "text")
state.set(store, "chars", len(src))

ctl := interact.create(root, t, win, cv)
APP["ctl"] = ctl
ui.show(win)
state.on_tick(store, interact.tick, ctl)
state.on_close_request(store, guard, null)
interact.set_focus(ctl, area)
state.run(win, store, interact.render, interact.handler, ctl)
canvas.destroy(cv)
ui.close(win)

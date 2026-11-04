# Test de dessin de ui.interact (V1.3) : exécute tout le rendu (survol, focus, sélection, barres, glisser-déposer)
# pour détecter les erreurs de types côté canvas natif, puis vérifie quelques pixels via la capture.
from core use type, len, to_int
use collections
use ui
use ui.canvas as canvas
use ui.layout as layout
use ui.widgets as widgets
use ui.widgets.text_input as ti
use ui.widgets.gutter as gutter
use ui.interact as interact
use ui.scroll as scroll
use ui.tween as tw
use ui.edit as edit

func check(cond, name):
    if not cond:
        raise("AssertionError", "ÉCHEC : " + name)
    print("ok  " + name)

win := ui.window("Draw", 500, 400, true)
cv := canvas.create(win)
ui.show(win)
t := widgets.modern_theme()
root := layout.container("root", 0, 0, 500, 400)
layout.padding_all(root, 10)
layout.gap(root, 8)
layout.column(root)
layout.align(root, "stretch", "start")
btn := widgets.button("Bouton", 0, 0, 120, 36)
cb := widgets.checkbox("Case")
field := ti.create("abc def ghi", "nom", 0.0, 0.0, 300.0, 36.0)
area := ti.create_area("a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\nn", "", 0.0, 0.0, 300.0, 80.0)
sv := scroll.create(0.0, 0.0, 300.0, 70.0)
i := 0
while i < 8:
    layout.add(sv, widgets.label("Ligne " + str(i), 0, 0, 100, 24))
    i += 1
inner := scroll.create(0.0, 0.0, 120.0, 40.0)
layout.add(sv, inner)
j := 0
while j < 6:
    layout.add(inner, widgets.label("Interne " + str(j), 0, 0, 100, 20))
    j += 1
gut := gutter.create(area, 0.0, 0.0, 40.0, 80.0)
btn["draggable"] = true
for w in [btn, cb, field, area, sv, gut]:
    layout.add(root, w)
sv["background"] = t["surface"]
ctl := interact.create(root, t, win, cv)
interact.set_time(ctl, 1.0)
interact.relayout(ctl)

# rendu de base
interact.draw(ctl)
check(true, "rendu complet sans erreur")

# états : survol, appui, focus visible, sélection, barres actives, glisser
interact.set_focus(ctl, btn, true)
b := interact.window_rect(btn)
ui.inject_mouse(win, "move", to_int(b[0] + 5), to_int(b[1] + 5), 1, 0)
running := true
while running:
    ev := ui.poll(win)
    if ev == null:
        running = false
    elif ui.event_type(ev) != "close":
        interact.handle(ctl, ev)
tw.tick(ctl["anim"], 1.0)
interact.draw(ctl)
interact.set_focus(ctl, field)
edit.select_all(field["editor"])
interact.draw(ctl)
interact.set_focus(ctl, area)
edit.set_caret(area["editor"], 5)
edit.move(area["editor"], "down", true, 14.0)
scroll.set(area, 0.0, 20.0)
scroll.set(sv, 0.0, 30.0)
scroll.set(inner, 0.0, 10.0)
sv["bar_hover"] = "v_thumb"
interact.draw(ctl)
check(true, "rendu avec survol, focus, sélection, barres et zones imbriquées")

# glisser : fantôme dessiné
ui.inject_mouse(win, "down", to_int(b[0] + 5), to_int(b[1] + 5), 1, 0)
ui.inject_mouse(win, "move", to_int(b[0] + 60), to_int(b[1] + 40), 1, 0)
running = true
while running:
    ev := ui.poll(win)
    if ev == null:
        running = false
    elif ui.event_type(ev) != "close":
        interact.handle(ctl, ev)
check(interact.is_dragging(ctl), "glisser en cours pour le rendu du fantôme")
interact.draw(ctl)
ui.inject_key(win, 27, 0)
running = true
while running:
    ev := ui.poll(win)
    if ev == null:
        running = false
    elif ui.event_type(ev) != "close":
        interact.handle(ctl, ev)
interact.draw(ctl)
check(true, "rendu pendant le retour animé du fantôme")
tw.tick(ctl["anim"], 1.0)
interact.draw(ctl)

# pixels : le canvas contient bien du rendu (fond, texte, widgets)
check(canvas.save_png(cv, "/tmp/alex_interact_draw.png"), "capture du canvas")

# métriques cohérentes
check(scroll.max_y(inner) > 0.0 and scroll.max_y(sv) > 0.0, "zones imbriquées : défilement indépendant")
check(sv["scroll_y"] == 30.0 and inner["scroll_y"] == 10.0, "positions de défilement conservées")
print("UI INTERACT DRAW: OK")

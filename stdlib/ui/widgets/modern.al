# ALEX UI V0.9 — Modern widgets facade
from core use len
use ui.widgets.widget as widget
use ui.widgets.theme as theme
use ui.widgets.button as button
use ui.widgets.label as label
use ui.widgets.card as card
use ui.widgets.checkbox as checkbox
use ui.widgets.text_field as text_field
use ui.widgets.progress as progress
use ui.layout as layout

const VERSION := "1.0.0"

func version():
    return VERSION
func layout_tree(root,width,height):
    return layout.perform(root,width,height)
func theme_modern():
    return theme.modern()
func button_new(text,x=0.0,y=0.0,width=120.0,height=40.0):
    return button.create(text,x,y,width,height)
func label_new(text,x=0.0,y=0.0,width=200.0,height=28.0):
    return label.create(text,x,y,width,height)
func card_new(x=0.0,y=0.0,width=280.0,height=160.0):
    return card.create(x,y,width,height)
func checkbox_new(text,checked=false,x=0.0,y=0.0,width=180.0,height=32.0):
    return checkbox.create(text,checked,x,y,width,height)
func text_field_new(value="",placeholder="",x=0.0,y=0.0,width=260.0,height=40.0):
    return text_field.create(value,placeholder,x,y,width,height)
func progress_new(value=0.0,x=0.0,y=0.0,width=240.0,height=8.0):
    return progress.create(value,x,y,width,height)

func dispatch(w,event):
    # Les enfants sont parcourus du dernier (dessiné au-dessus) au premier : l'enfant le plus
    # haut capte l'événement avant son parent. (Pas de référence en avant en ALEX : récursion directe.)
    if not w["visible"] or not w["enabled"]:
        return false
    kind := event["type"]
    handled := false
    i := len(w["children"]) - 1
    while i >= 0:
        if dispatch(w["children"][i],event):
            handled = true
            if kind != "pointer_move":
                return true
        i -= 1
    if kind == "pointer_move":
        # survol : tous les noeuds sont mis à jour (pas de court-circuit)
        w["hovered"] = widget.contains(w,event["x"],event["y"])
        return w["hovered"] or handled
    if kind == "pointer_down":
        if widget.contains(w,event["x"],event["y"]):
            w["pressed"] = true
            widget.focus(w)
            return true
    if kind == "pointer_up":
        hit := widget.contains(w,event["x"],event["y"])
        was := w["pressed"]
        w["pressed"] = false
        if hit and was:
            if w["kind"] == "checkbox":
                checkbox.toggle(w)
            if w["on_click"] != null:
                w["on_click"](w)
            return true
    return false

func draw_tree(root,c,t=null):
    # Dessine ce noeud selon son kind, puis descend dans ses enfants.
    # (Les draw() de chaque widget ne dessinent QUE le widget lui-même.)
    if t == null:
        t = theme.modern()
    if not root["visible"]:
        return
    kind := root["kind"]
    if kind == "button":
        button.draw(root,c,t)
    elif kind == "label":
        label.draw(root,c,t)
    elif kind == "card":
        card.draw(root,c,t)
    elif kind == "checkbox":
        checkbox.draw(root,c,t)
    elif kind == "text_field":
        text_field.draw(root,c,t)
    elif kind == "progress":
        progress.draw(root,c,t)
    for child in root["children"]:
        draw_tree(child,c,t)

# ALEX UI V0.9 — Base modern widget
from core use type, len
use ui.tween.interp as _interp
use collections
use ui.canvas as canvas
use ui.paint as paint

const _UID := {"n": 0}

# Identité d'un widget. NE JAMAIS comparer deux widgets avec == : la comparaison est structurelle et
# l'arbre contient des cycles (parent <-> enfants). Comparer leurs uid.
func same(a, b):
    if a == null or b == null:
        return a == null and b == null
    return a["uid"] == b["uid"]

func create(kind, x=0.0, y=0.0, width=120.0, height=40.0):
    _UID["n"] += 1
    # Tout widget est aussi un noeud de layout : les champs ci-dessous
    # sont requis par ui.layout.engine (measure/layout) pour N'IMPORTE
    # quel widget (button, card, label...), pas seulement les containers.
    return {
        "uid":_UID["n"], "kind":kind, "x":x, "y":y, "width":width, "height":height,
        # V1.3 — interaction (voir ui.interact)
        "focusable":null, "tab_index":0, "cursor":null, "hover_t":0.0, "press_t":0.0, "hover_anim":false,
        "draggable":false, "drag_data":null, "drag_type":null, "droppable":false, "drop_accept":null,
        "drop_hover":false, "drop_reject":false,
        "on_press":null, "on_release":null, "on_double_click":null, "on_context":null, "on_long_press":null,
        "on_hover":null, "on_hover_end":null, "on_wheel":null, "on_key":null, "on_escape":null,
        "on_drag_start":null, "on_drag":null, "on_drag_end":null, "on_drag_enter":null, "on_drag_over":null,
        "on_drag_leave":null, "on_drop":null, "on_scroll":null,
        "scroll_x":0.0, "scroll_y":0.0, "content_width":0.0, "content_height":0.0, "scroll_links":[],
        "visible":true, "enabled":true, "focused":false, "hovered":false,
        "pressed":false, "children":[], "parent":null,
        "radius":10.0, "opacity":1.0, "text":"", "value":null,
        "on_click":null, "on_change":null, "on_focus":null, "on_blur":null,
        "layout": {"type":"leaf",
                   "padding":{"left":0.0,"top":0.0,"right":0.0,"bottom":0.0},
                   "margin":{"left":0.0,"top":0.0,"right":0.0,"bottom":0.0},
                   "gap":0.0,
                   "alignment":{"horizontal":"start","vertical":"start"},
                   "direction":"column", "wrap":false},
        "flex":0.0, "flex_basis":null,
        "min_width":0.0, "min_height":0.0, "max_width":null, "max_height":null,
        "intrinsic_width":width, "intrinsic_height":height,
        "measured_width":width, "measured_height":height
    }

func add(parent, child):
    child["parent"] = parent
    collections.append(parent["children"], child)
    return child

# Mélange de deux couleurs (t dans [0, 1]).
func mix(a, b, t):
    return _interp.interpolate(a, b, t)

# [survol, appui] dans [0, 1] : valeurs animées par ui.interact (hover_anim), sinon booléens instantanés.
func visual_state(w):
    if w["hover_anim"]:
        return [w["hover_t"], w["press_t"]]
    hv := 0.0
    pv := 0.0
    if w["hovered"]:
        hv = 1.0
    if w["pressed"]:
        pv = 1.0
    return [hv, pv]

# Détache child de son parent actuel et l'insère dans new_parent (à la fin, ou à l'indice donné).
func move(child, new_parent, index=null):
    old := child["parent"]
    if old != null:
        kept := []
        for c in old["children"]:
            if c["uid"] != child["uid"]:
                collections.append(kept, c)
        old["children"] = kept
    if index == null or index >= len(new_parent["children"]):
        collections.append(new_parent["children"], child)
    else:
        collections.insert(new_parent["children"], index, child)
    child["parent"] = new_parent
    return child

func index_in_parent(child):
    p := child["parent"]
    if p == null:
        return -1
    i := 0
    for c in p["children"]:
        if c["uid"] == child["uid"]:
            return i
        i += 1
    return -1

func contains(widget, px, py):
    return widget["visible"] and px >= widget["x"] and py >= widget["y"] and px <= widget["x"] + widget["width"] and py <= widget["y"] + widget["height"]

func set_position(w, x, y):
    w["x"] = x
    w["y"] = y
    return w

func set_size(w, width, height):
    w["width"] = width
    w["height"] = height
    return w

func set_visible(w, value):
    w["visible"] = value
    return w

func set_enabled(w, value):
    w["enabled"] = value
    return w

func focus(w):
    w["focused"] = true
    if w["on_focus"] != null:
        w["on_focus"](w)
    return w

func blur(w):
    w["focused"] = false
    if w["on_blur"] != null:
        w["on_blur"](w)
    return w

func draw(w, c, theme):
    if not w["visible"]:
        return
    for child in w["children"]:
        draw(child, c, theme)

func _draw_children(w, c, theme):
    for child in w["children"]:
        draw(child, c, theme)

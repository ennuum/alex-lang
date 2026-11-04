from core use len, type, to_int
# ALEX STANDARD LIBRARY — ui.layout
# Shared layout primitives and validation.

use ui.widget as _widget

func _positive_int(value, name):
    if type(value) != "int":
        raise("TypeError", "ui.layout." + name + " : valeur doit être un int")
    if value <= 0:
        raise("ArgumentError", "ui.layout." + name + " : valeur strictement positive")

func _non_negative_int(value, name):
    if type(value) != "int":
        raise("TypeError", "ui.layout." + name + " : valeur doit être un int")
    if value < 0:
        raise("ArgumentError", "ui.layout." + name + " : valeur négative interdite")

func _children(children):
    if type(children) != "list":
        raise("TypeError", "ui.layout : children doit être une list")

func item(widget, width=100, height=30, flex=0, margin=0):
    if type(widget) != "int":
        raise("TypeError", "ui.layout.item() : widget doit être un handle int")
    if width == null:
        width = 100
    if height == null:
        height = 30
    if flex == null:
        flex = 0
    if margin == null:
        margin = 0
    _positive_int(width, "item.width")
    _positive_int(height, "item.height")
    _non_negative_int(flex, "item.flex")
    _non_negative_int(margin, "item.margin")
    return {"widget": widget, "width": width, "height": height, "flex": flex, "margin": margin}

func place(item_value, x, y, width, height):
    # Les widgets natifs travaillent en pixels entiers ; le calcul de layout peut produire des float.
    _widget.set_position(item_value["widget"], to_int(x), to_int(y))
    _widget.set_size(item_value["widget"], to_int(width), to_int(height))
    return null

func align_x(container_width, item_width, mode="start"):
    if mode == null:
        mode = "start"
    # Accepte une chaîne ("start"|"center"|"end"|"stretch") ou un objet d'alignement V1.0
    # ({"horizontal":..., "vertical":...}) tel que renvoyé par ui.alignment_center().
    if type(mode) == "dict":
        mode = mode["horizontal"]
    if mode == "stretch":
        mode = "start"
    if mode == "start":
        return 0
    if mode == "center":
        return (container_width - item_width) / 2
    if mode == "end":
        return container_width - item_width
    raise("ArgumentError", "ui.layout.align_x() : mode invalide")

func align_y(container_height, item_height, mode="start"):
    if mode == null:
        mode = "start"
    # Accepte une chaîne ("start"|"center"|"end"|"stretch") ou un objet d'alignement V1.0
    # ({"horizontal":..., "vertical":...}) tel que renvoyé par ui.alignment_center().
    if type(mode) == "dict":
        mode = mode["vertical"]
    if mode == "stretch":
        mode = "start"
    if mode == "start":
        return 0
    if mode == "center":
        return (container_height - item_height) / 2
    if mode == "end":
        return container_height - item_height
    raise("ArgumentError", "ui.layout.align_y() : mode invalide")

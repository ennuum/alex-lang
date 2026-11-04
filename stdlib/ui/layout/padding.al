from core use len, type
# Padding helpers.
func all(value):
    if type(value) != "int" or value < 0:
        raise("ArgumentError", "ui.padding.all() : valeur invalide")
    return [value, value, value, value]

func symmetric(horizontal=0, vertical=0):
    if horizontal == null:
        horizontal = 0
    if vertical == null:
        vertical = 0
    if type(horizontal) != "int" or type(vertical) != "int":
        raise("TypeError", "ui.padding.symmetric() : valeurs int requises")
    return [vertical, horizontal, vertical, horizontal]

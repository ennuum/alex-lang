from core use len, type
# Margin helpers. Layout engines currently consume the uniform margin field.
func all(value):
    if type(value) != "int" or value < 0:
        raise("ArgumentError", "ui.margin.all() : valeur invalide")
    return value

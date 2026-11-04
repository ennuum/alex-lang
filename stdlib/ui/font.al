from core use type, len
# ALEX STANDARD LIBRARY — ui.font V0.4

func font(family="Segoe UI", size=10, weight="normal"):
    if family == null:
        family = "Segoe UI"
    if size == null:
        size = 10
    if weight == null:
        weight = "normal"
    if type(family) != "str" or type(size) != "int" or type(weight) != "str":
        raise("TypeError", "ui.font() : family/size/weight invalides")
    if size <= 0:
        raise("ArgumentError", "ui.font() : size doit être positif")
    return {"family": family, "size": size, "weight": weight}

func normal(family="Segoe UI", size=10):
    return font(family, size, "normal")

func medium(family="Segoe UI", size=10):
    return font(family, size, "medium")

func semibold(family="Segoe UI", size=10):
    return font(family, size, "semibold")

func bold(family="Segoe UI", size=10):
    return font(family, size, "bold")

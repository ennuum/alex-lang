# ALEX UI V1.2 — Interpolation de valeurs animables
# Types supportés : nombre (int/float), couleur {"r","g","b"[,"a"]}, vecteur (list de nombres).
from core use type, len, clamp
use collections
use math as _math

func is_number(v):
    t := type(v)
    return t == "int" or t == "float"

func is_color(v):
    return type(v) == "dict" and collections.contains_key(v, "r") and collections.contains_key(v, "g") and collections.contains_key(v, "b")

func is_vector(v):
    if type(v) != "list" or len(v) == 0:
        return false
    for x in v:
        if not is_number(x):
            return false
    return true

# "number" | "color" | "vector" | null
func kind(v):
    if is_number(v):
        return "number"
    if is_color(v):
        return "color"
    if is_vector(v):
        return "vector"
    return null

func copy_value(v):
    k := kind(v)
    if k == "color":
        a := 255
        if collections.contains_key(v, "a"):
            a = v["a"]
        return {"r": v["r"], "g": v["g"], "b": v["b"], "a": a}
    if k == "vector":
        out := []
        for x in v:
            collections.append(out, x)
        return out
    return v

func _channel(a, b, t):
    return clamp(_math.floor(a + (b - a) * t + 0.5), 0, 255)

# Interpolation linéaire. t peut sortir de [0, 1] (back/elastic) : les canaux de couleur sont bornés à 0..255.
# t == 0 / t == 1 renvoient exactement les extrémités (pas d'erreur d'arrondi cumulée).
func interpolate(a, b, t):
    ka := kind(a)
    if ka == null or ka != kind(b):
        raise("TypeError", "ui.tween : valeurs non interpolables (nombre, couleur ou list de nombres de même type attendus)")
    if t == 1:
        return copy_value(b)
    if t == 0:
        return copy_value(a)
    if ka == "number":
        return a + (b - a) * t
    if ka == "color":
        aa := 255
        ba := 255
        if collections.contains_key(a, "a"):
            aa = a["a"]
        if collections.contains_key(b, "a"):
            ba = b["a"]
        return {"r": _channel(a["r"], b["r"], t), "g": _channel(a["g"], b["g"], t), "b": _channel(a["b"], b["b"], t), "a": _channel(aa, ba, t)}
    if len(a) != len(b):
        raise("ArgumentError", "ui.tween : les vecteurs doivent avoir la même taille")
    out := []
    i := 0
    while i < len(a):
        collections.append(out, a[i] + (b[i] - a[i]) * t)
        i += 1
    return out

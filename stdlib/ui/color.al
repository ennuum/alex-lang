from core use type, len
# ALEX STANDARD LIBRARY — ui.color V0.4
# Immutable-by-convention color descriptors. Hex format: #RRGGBB.

func color(value):
    if type(value) != "str":
        raise("TypeError", "ui.color() : value doit être une str")
    if value == "":
        raise("ArgumentError", "ui.color() : couleur vide")
    return {"value": value, "hex": value}

func _hex2(n):
    digits := "0123456789ABCDEF"
    return str(digits[n // 16]) + str(digits[n % 16])

func rgb(r, g, b):
    if type(r) != "int" or type(g) != "int" or type(b) != "int":
        raise("TypeError", "ui.color.rgb() : r, g et b doivent être des int")
    if r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255:
        raise("ArgumentError", "ui.color.rgb() : composantes hors intervalle 0..255")
    return {"r": r, "g": g, "b": b, "hex": "#" + _hex2(r) + _hex2(g) + _hex2(b)}

const TRANSPARENT := {"value": "transparent"}
const WHITE := {"value": "#FFFFFF", "hex": "#FFFFFF"}
const BLACK := {"value": "#000000", "hex": "#000000"}
const SLATE_950 := {"value": "#020617", "hex": "#020617"}
const SLATE_900 := {"value": "#0F172A", "hex": "#0F172A"}
const SLATE_800 := {"value": "#1E293B", "hex": "#1E293B"}
const SLATE_700 := {"value": "#334155", "hex": "#334155"}
const SLATE_600 := {"value": "#475569", "hex": "#475569"}
const SLATE_400 := {"value": "#94A3B8", "hex": "#94A3B8"}
const SLATE_200 := {"value": "#E2E8F0", "hex": "#E2E8F0"}
const SLATE_100 := {"value": "#F1F5F9", "hex": "#F1F5F9"}
const BLUE_600 := {"value": "#2563EB", "hex": "#2563EB"}
const BLUE_500 := {"value": "#3B82F6", "hex": "#3B82F6"}
# violet du logo d'ALEX : 600 (sur fond clair, texte blanc dessus), 400 (sur fond sombre)
const VIOLET_600 := {"value": "#6A1FE6", "hex": "#6A1FE6"}
const VIOLET_400 := {"value": "#A57CFF", "hex": "#A57CFF"}
const GREEN_500 := {"value": "#22C55E", "hex": "#22C55E"}
const RED_500 := {"value": "#EF4444", "hex": "#EF4444"}

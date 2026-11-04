# ALEX STANDARD LIBRARY — tui.style
#
# Styles de texte du terminal : couleurs (nom, numéro 0..255 de la palette, ou « #rrggbb ») et attributs.
# Un style est une chaîne de paramètres SGR (« 1;38;5;196 ») : comparer deux styles revient à comparer deux
# chaînes, et le tampon d'écran les stocke tels quels. "" est le style par défaut du terminal.
#
#   use tui.style as st
#   s := st.style("red", null, bold=true)
#   t := st.style("#ffaa00", "blue", underline=true)
#   st.ansi(s) + "texte" + st.RESET

from core use len, type
from collections use append, contains_key
use string as _s

const RESET := "\u001b[0m"

_NAMES := {"black": 0, "red": 1, "green": 2, "yellow": 3, "blue": 4, "magenta": 5, "cyan": 6, "white": 7, "gray": 8, "grey": 8, "bright_black": 8, "bright_red": 9, "bright_green": 10, "bright_yellow": 11, "bright_blue": 12, "bright_magenta": 13, "bright_cyan": 14, "bright_white": 15}

func _hexval(text):
    v := 0
    for c in _s.lower(text):
        d := _s.ord(c)
        if d >= 48 and d <= 57:
            v = v * 16 + d - 48
        elif d >= 97 and d <= 102:
            v = v * 16 + d - 87
        else:
            return -1
    return v

# Composantes [r, g, b] d'une couleur « #rrggbb » (ou « #rgb »), ou null.
func rgb_of(color):
    if type(color) != "str" or not _s.starts_with(color, "#"):
        return null
    h := _s.slice(color, 1)
    if len(h) == 3:
        h = str(h[0]) + str(h[0]) + str(h[1]) + str(h[1]) + str(h[2]) + str(h[2])
    if len(h) != 6:
        return null
    r := _hexval(_s.slice(h, 0, 2))
    g := _hexval(_s.slice(h, 2, 4))
    b := _hexval(_s.slice(h, 4, 6))
    if r < 0 or g < 0 or b < 0:
        return null
    return [r, g, b]

# Paramètres SGR d'une couleur ; base 30 (texte) ou 40 (fond).
func color_code(color, base):
    if color == null or color == "default":
        return ""
    if type(color) == "int":
        if color < 0 or color > 255:
            raise("ArgumentError", "tui.style : couleur 0..255 attendue")
        if color < 8:
            return str(base + color)
        if color < 16:
            return str(base + 60 + color - 8)
        return str(base + 8) + ";5;" + str(color)
    if type(color) != "str":
        raise("TypeError", "tui.style : couleur (nom, int ou « #rrggbb ») attendue")
    if contains_key(_NAMES, color):
        return color_code(_NAMES[color], base)
    rgb := rgb_of(color)
    if rgb == null:
        raise("ArgumentError", "tui.style : couleur inconnue '" + color + "'")
    return str(base + 8) + ";2;" + str(rgb[0]) + ";" + str(rgb[1]) + ";" + str(rgb[2])

# Style (chaîne SGR) d'après une couleur de texte, une couleur de fond et des attributs.
func style(fg=null, bg=null, bold=false, dim=false, italic=false, underline=false, reverse=false, strike=false):
    parts := []
    if bold:
        append(parts, "1")
    if dim:
        append(parts, "2")
    if italic:
        append(parts, "3")
    if underline:
        append(parts, "4")
    if reverse:
        append(parts, "7")
    if strike:
        append(parts, "9")
    f := color_code(fg, 30)
    if f != "":
        append(parts, f)
    b := color_code(bg, 40)
    if b != "":
        append(parts, b)
    return _s.join(";", parts)

# Combine deux styles (les paramètres de over s'ajoutent à ceux de base et l'emportent).
func merge(base, over):
    if base == "":
        return over
    if over == "":
        return base
    return base + ";" + over

# Séquence d'échappement qui applique le style (en partant du style par défaut).
func ansi(sgr):
    if sgr == "":
        return RESET
    return "\u001b[0;" + sgr + "m"

# Texte entouré du style puis du retour au style par défaut.
func paint(text, sgr):
    if sgr == "":
        return str(text)
    return ansi(sgr) + str(text) + RESET

# ---------------------------------------------------------------- réduction des couleurs
_CUBE := [0, 95, 135, 175, 215, 255]

func _nearest_cube(v):
    best := 0
    bd := 1000
    i := 0
    while i < 6:
        d := v - _CUBE[i]
        if d < 0:
            d = -d
        if d < bd:
            bd = d
            best = i
        i += 1
    return best

# Indice de la palette 256 couleurs le plus proche de [r, g, b].
func to_256(rgb):
    r := _nearest_cube(rgb[0])
    g := _nearest_cube(rgb[1])
    b := _nearest_cube(rgb[2])
    cube := 16 + 36 * r + 6 * g + b
    avg := (rgb[0] + rgb[1] + rgb[2]) // 3
    gray := (avg - 8) // 10
    if gray < 0:
        gray = 0
    if gray > 23:
        gray = 23
    gv := 8 + gray * 10
    dc := _dist(rgb, [_CUBE[r], _CUBE[g], _CUBE[b]])
    dg := _dist(rgb, [gv, gv, gv])
    if dg < dc:
        return 232 + gray
    return cube

func _dist(a, b):
    return (a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) + (a[2] - b[2]) * (a[2] - b[2])

_BASIC := [[0, 0, 0], [205, 0, 0], [0, 205, 0], [205, 205, 0], [0, 0, 238], [205, 0, 205], [0, 205, 205], [229, 229, 229], [127, 127, 127], [255, 0, 0], [0, 255, 0], [255, 255, 0], [92, 92, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255]]

func to_16(rgb):
    best := 0
    bd := -1
    i := 0
    while i < 16:
        d := _dist(rgb, _BASIC[i])
        if bd < 0 or d < bd:
            bd = d
            best = i
        i += 1
    return best

# Réécrit une chaîne SGR pour un terminal de depth couleurs ("truecolor", "256", "16", "none").
func downgrade(sgr, depth):
    if depth == "truecolor" or sgr == "":
        return sgr
    p := _s.split(sgr, ";")
    out := []
    i := 0
    while i < len(p):
        x := p[i]
        if (x == "38" or x == "48") and i + 1 < len(p):
            base := 30
            if x == "48":
                base = 40
            if p[i + 1] == "2" and i + 4 < len(p):
                rgb := [_s_int(p[i + 2]), _s_int(p[i + 3]), _s_int(p[i + 4])]
                if depth == "256":
                    append(out, x + ";5;" + str(to_256(rgb)))
                elif depth == "16":
                    append(out, color_code(to_16(rgb), base))
                i += 5
                continue
            if p[i + 1] == "5" and i + 2 < len(p):
                if depth == "256":
                    append(out, x + ";5;" + p[i + 2])
                elif depth == "16":
                    n := _s_int(p[i + 2])
                    if n >= 16:
                        n = to_16(_rgb_of_256(n))
                    append(out, color_code(n, base))
                i += 3
                continue
        if depth == "none":
            v := _s_int(x)
            if (v >= 30 and v <= 49) or (v >= 90 and v <= 107):
                i += 1
                continue
        append(out, x)
        i += 1
    return _s.join(";", out)

func _rgb_of_256(n):
    if n >= 232:
        g := 8 + (n - 232) * 10
        return [g, g, g]
    k := n - 16
    return [_CUBE[k // 36], _CUBE[(k // 6) % 6], _CUBE[k % 6]]

func _s_int(t):
    v := 0
    for c in t:
        v = v * 10 + _s.ord(c) - 48
    return v

# ---------------------------------------------------------------- vers le web
_WEB16 := [[0, 0, 0], [205, 49, 49], [13, 188, 121], [229, 229, 16], [36, 114, 200], [188, 63, 188], [17, 168, 205], [229, 229, 229], [102, 102, 102], [241, 76, 76], [35, 209, 139], [245, 245, 67], [59, 142, 234], [214, 112, 214], [41, 184, 219], [255, 255, 255]]

func _hex2(v):
    d := "0123456789abcdef"
    return str(d[(v // 16) % 16]) + str(d[v % 16])

func _css(rgb):
    return "#" + _hex2(rgb[0]) + _hex2(rgb[1]) + _hex2(rgb[2])

func _rgb_n(n):
    if n < 16:
        return _WEB16[n]
    return _rgb_of_256(n)

# Attributs d'un style SGR : {"fg": "#rrggbb" ou null, "bg", "bold", "dim", "italic", "underline", "reverse"}.
func decode(sgr):
    out := {"fg": null, "bg": null, "bold": false, "dim": false, "italic": false, "underline": false, "reverse": false}
    if sgr == "":
        return out
    p := _s.split(sgr, ";")
    i := 0
    while i < len(p):
        v := _s_int(p[i])
        if v == 0:
            out = decode("")
        elif v == 1:
            out["bold"] = true
        elif v == 2:
            out["dim"] = true
        elif v == 3:
            out["italic"] = true
        elif v == 4:
            out["underline"] = true
        elif v == 7:
            out["reverse"] = true
        elif (v == 38 or v == 48) and i + 1 < len(p):
            key := "fg" if v == 38 else "bg"
            if _s_int(p[i + 1]) == 2 and i + 4 < len(p):
                out[key] = _css([_s_int(p[i + 2]), _s_int(p[i + 3]), _s_int(p[i + 4])])
                i += 4
            elif _s_int(p[i + 1]) == 5 and i + 2 < len(p):
                out[key] = _css(_rgb_n(_s_int(p[i + 2])))
                i += 2
        elif v >= 30 and v <= 37:
            out["fg"] = _css(_WEB16[v - 30])
        elif v >= 90 and v <= 97:
            out["fg"] = _css(_WEB16[v - 90 + 8])
        elif v >= 40 and v <= 47:
            out["bg"] = _css(_WEB16[v - 40])
        elif v >= 100 and v <= 107:
            out["bg"] = _css(_WEB16[v - 100 + 8])
        i += 1
    return out

# ALEX STANDARD LIBRARY — web.css.borders
#
# Bordures, coins arrondis et contours : déclarations (dicts prêts pour StyleRule), analyse du raccourci
# border, anneau de focus accessible, séparateurs.
#
#   use web.css.borders as bd
#   bd.border("1px", "solid", "#ddd")              # {"border": "1px solid #ddd"}
#   bd.side("bottom", 2, "dashed", "red")          # {"border-bottom": "2px dashed red"}
#   bd.radius("8px")                               # {"border-radius": "8px"}
#   bd.radius_corners(top_left="1rem", top_right="1rem")   # coins supérieurs seulement
#   bd.pill(), bd.circle()
#   bd.focus_ring("#36c")                          # outline visible au clavier
#   bd.parse("thin dotted rgb(0 0 0 / 50%)")       # ("thin", "dotted", "rgb(0 0 0 / 50%)")
#
# Erreurs : CssValueError (style ou côté inconnu).

from core use len, type
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.units as _units
use web.css.color as _color

const STYLES := ["none", "hidden", "dotted", "dashed", "solid", "double", "groove", "ridge", "inset", "outset"]
const SIDES := ["top", "right", "bottom", "left", "block", "inline", "block-start", "block-end", "inline-start", "inline-end"]
const WIDTH_WORDS := ["thin", "medium", "thick"]

func _len(v):
    if type(v) == "int" or type(v) == "float":
        return str(v) + "px" if v != 0 else "0"
    return str(v)

func _value_of(width, style, color):
    if not (style in STYLES):
        _err.value_error("borders", "style de bordure inconnu « " + str(style) + " »")
    parts := [_len(width), style]
    if color != null:
        append(parts, str(color))
    return _s.join(" ", parts)

func border(width="1px", style="solid", color=null):
    return {"border": _value_of(width, style, color)}

func side(which, width="1px", style="solid", color=null):
    if not (which in SIDES):
        _err.value_error("borders.side", "côté inconnu « " + str(which) + " »")
    return {"border-" + which: _value_of(width, style, color)}

func none():
    return {"border": "0"}

func radius(a, b=null, c=null, d=null):
    parts := [_len(a)]
    for x in [b, c, d]:
        if x != null:
            append(parts, _len(x))
    return {"border-radius": _s.join(" ", parts)}

func radius_corners(top_left=null, top_right=null, bottom_right=null, bottom_left=null):
    d := {}
    if top_left != null:
        d["border-top-left-radius"] = _len(top_left)
    if top_right != null:
        d["border-top-right-radius"] = _len(top_right)
    if bottom_right != null:
        d["border-bottom-right-radius"] = _len(bottom_right)
    if bottom_left != null:
        d["border-bottom-left-radius"] = _len(bottom_left)
    return d

func pill():
    return {"border-radius": "9999px"}

func circle():
    return {"border-radius": "50%"}

func outline(width="2px", style="solid", color="currentcolor", offset=null):
    d := {"outline": _value_of(width, style, color)}
    if offset != null:
        d["outline-offset"] = _len(offset)
    return d

# Anneau de focus (à appliquer sur :focus-visible).
func focus_ring(color="#2563eb", width="2px", offset="2px"):
    return {"outline": _len(width) + " solid " + color, "outline-offset": _len(offset)}

# Anneau de focus par box-shadow (suit les coins arrondis, n'affecte pas la mise en page).
func focus_shadow(color="#2563eb", width="3px", gap_color="#fff", gap="2px"):
    return {"outline": "none", "box-shadow": "0 0 0 " + _len(gap) + " " + gap_color + ", 0 0 0 calc(" + _len(gap) + " + " + _len(width) + ") " + color}

# Séparateur horizontal (hr) discret.
func divider(color="#e5e7eb", width="1px"):
    return {"border": "0", "border-top": _len(width) + " solid " + color, "margin": "1rem 0"}

func collapse_table():
    return {"border-collapse": "collapse", "border-spacing": "0"}

# Raccourci border -> (largeur, style, couleur) ; null pour une composante absente.
func parse(text):
    w := null
    st := null
    c := null
    for it in _value.parse(str(text)).components:
        t := it.to_css()
        lt := _s.lower(t)
        if isinstance(it, _value.Token) and it.kind == _value.IDENT and lt in STYLES and st == null:
            st = lt
        elif isinstance(it, _value.Token) and it.kind == _value.IDENT and lt in WIDTH_WORDS and w == null:
            w = lt
        elif isinstance(it, _value.Token) and (it.kind == _value.DIMENSION or it.kind == _value.NUMBER) and w == null:
            w = t
        elif isinstance(it, _value.Function) and it.lower_name() in ["calc", "min", "max", "clamp"] and w == null:
            w = t
        elif c == null and _color.is_color(t):
            c = t
        else:
            _err.value_error("borders.parse", "composante inattendue « " + t + " » dans « " + str(text) + " »")
    return (w, st, c)

# Largeur en px d'une largeur de bordure (thin 1, medium 3, thick 5).
func width_px(width):
    w := _s.lower(_s.trim(str(width)))
    if w == "thin":
        return 1.0
    if w == "medium":
        return 3.0
    if w == "thick":
        return 5.0
    return _units.to_px(_units.parse(w))

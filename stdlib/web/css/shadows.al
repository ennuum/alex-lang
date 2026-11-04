# ALEX STANDARD LIBRARY — web.css.shadows
#
# Ombres : objet Shadow (box-shadow / text-shadow / drop-shadow()), analyse d'une liste d'ombres, échelle
# d'élévation, ombres douces en couches, halo.
#
#   use web.css.shadows as sh
#   s := sh.Shadow(0, 4, 12, 0, "rgb(0 0 0 / 15%)")
#   s.to_css()                       # 0 4px 12px rgb(0 0 0 / 15%)
#   sh.box([s, sh.Shadow(0, 1, 2, 0, "#0002")])   # {"box-shadow": "0 4px 12px …, 0 1px 2px #0002"}
#   sh.elevation(3)                  # {"box-shadow": "…"} (niveaux 0 à 5)
#   sh.layered(4, "0 0 0", 0.08)    # ombre douce en 4 couches
#   sh.parse("inset 0 1px 0 #fff, 2px 2px red")   # [Shadow(inset), Shadow]
#   sh.glow("#0af", 12)              # halo coloré
#   s.drop_shadow()                  # drop-shadow(0 4px 12px rgb(0 0 0 / 15%)) pour filter
#
# Erreurs : CssValueError (ombre mal formée).

from core use len, type, to_float
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.units as _units
use web.css.color as _color

func _len(v):
    if type(v) == "int" or type(v) == "float":
        return _units.format_number(v) + "px" if v != 0 else "0"
    return str(v)

class Shadow:
    func init(x=0, y=0, blur=0, spread=0, color=null, inset=false):
        self.x = x
        self.y = y
        self.blur = blur
        self.spread = spread
        self.color = color
        self.inset = inset

    func to_css(with_spread=true):
        parts := []
        if self.inset:
            append(parts, "inset")
        append(parts, _len(self.x))
        append(parts, _len(self.y))
        has_spread := with_spread and self.spread != 0 and self.spread != "0"
        if self.blur != 0 and self.blur != "0" or has_spread:
            append(parts, _len(self.blur))
        if has_spread:
            append(parts, _len(self.spread))
        if self.color != null:
            append(parts, str(self.color))
        return _s.join(" ", parts)

    func __str__():
        return self.to_css()

    # Pour filter: drop-shadow() (sans étalement ni inset).
    func drop_shadow():
        return "drop-shadow(" + Shadow(self.x, self.y, self.blur, 0, self.color).to_css(false) + ")"

    func with_color(c):
        return Shadow(self.x, self.y, self.blur, self.spread, c, self.inset)

    func scaled(k):
        return Shadow(_mul(self.x, k), _mul(self.y, k), _mul(self.blur, k), _mul(self.spread, k), self.color, self.inset)

func _mul(v, k):
    if type(v) == "int" or type(v) == "float":
        return v * k
    d := _units.parse(str(v))
    return _units.format_number(d.value * k) + d.unit

func _join(shadows, with_spread=true):
    parts := []
    for s in shadows:
        append(parts, s.to_css(with_spread) if isinstance(s, Shadow) else str(s))
    return _s.join(", ", parts)

func box(shadows):
    if isinstance(shadows, Shadow):
        return {"box-shadow": shadows.to_css()}
    return {"box-shadow": _join(shadows)}

func text(shadows):
    if isinstance(shadows, Shadow):
        return {"text-shadow": shadows.to_css(false)}
    return {"text-shadow": _join(shadows, false)}

func none():
    return {"box-shadow": "none"}

# Liste d'ombres depuis du texte (box-shadow ou text-shadow).
func parse(text):
    t := _s.trim(str(text))
    if _s.lower(t) == "none":
        return []
    out := []
    for group in _value.parse(t).split_commas():
        lengths := []
        col := null
        ins := false
        for it in group:
            if isinstance(it, _value.Token) and it.kind == _value.WHITESPACE:
                continue
            s := it.to_css()
            if isinstance(it, _value.Token) and it.is_ident("inset"):
                ins = true
            elif isinstance(it, _value.Token) and (it.kind == _value.DIMENSION or it.kind == _value.NUMBER):
                append(lengths, s)
            elif isinstance(it, _value.Function) and it.lower_name() in ["calc", "min", "max", "clamp"]:
                append(lengths, s)
            elif col == null and (_color.is_color(s) or (isinstance(it, _value.Function) and it.lower_name() in ["var", "color-mix", "light-dark"])):
                col = s
            else:
                _err.value_error("shadows.parse", "composante inattendue « " + s + " »")
        if len(lengths) < 2 or len(lengths) > 4:
            _err.value_error("shadows.parse", "ombre mal formée « " + _value.serialize(group) + " »")
        while len(lengths) < 4:
            append(lengths, "0")
        append(out, Shadow(_num_or(lengths[0]), _num_or(lengths[1]), _num_or(lengths[2]), _num_or(lengths[3]), col, ins))
    return out

func _num_or(t):
    d := _units.try_parse(t)
    if d != null and (d.unit == "px" or (d.unit == "" and to_float(d.value) == 0.0)):
        v := d.value
        return v
    return t

const _ELEVATIONS := [
    "none",
    "0 1px 2px rgb(0 0 0 / 5%)",
    "0 1px 3px rgb(0 0 0 / 10%), 0 1px 2px -1px rgb(0 0 0 / 10%)",
    "0 4px 6px -1px rgb(0 0 0 / 10%), 0 2px 4px -2px rgb(0 0 0 / 10%)",
    "0 10px 15px -3px rgb(0 0 0 / 10%), 0 4px 6px -4px rgb(0 0 0 / 10%)",
    "0 20px 25px -5px rgb(0 0 0 / 10%), 0 8px 10px -6px rgb(0 0 0 / 10%)"
]

# Élévation 0 (aucune) à 5.
func elevation(level):
    i := level
    if i < 0:
        i = 0
    if i >= len(_ELEVATIONS):
        i = len(_ELEVATIONS) - 1
    return {"box-shadow": _ELEVATIONS[i]}

func elevation_variables(prefix="--shadow-"):
    out := {}
    i := 0
    while i < len(_ELEVATIONS):
        out[prefix + str(i)] = _ELEVATIONS[i]
        i += 1
    return out

# Ombre douce en n couches (distances doublées à chaque couche) ; rgb : « r g b » ; alpha par couche.
func layered(n=4, rgb="0 0 0", alpha=0.07, base=1):
    items := []
    i := 0
    d := to_float(base)
    while i < n:
        append(items, Shadow(0, d, d * 2, 0, "rgb(" + rgb + " / " + _units.format_number(alpha) + ")"))
        d = d * 2
        i += 1
    return {"box-shadow": _join(items)}

func glow(color, radius=12, spread=0):
    return {"box-shadow": Shadow(0, 0, radius, spread, color).to_css()}

func inner(color="rgb(0 0 0 / 6%)", y=2, blur=4):
    return {"box-shadow": Shadow(0, y, blur, 0, color, true).to_css()}

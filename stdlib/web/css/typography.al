# ALEX STANDARD LIBRARY — web.css.typography
#
# Typographie : déclarations de police (dicts prêts pour StyleRule), piles de polices système, échelles
# modulaires, tailles fluides (clamp() calculé entre deux largeurs d'écran), troncature, coupure de lignes,
# longueur de ligne confortable.
#
#   use web.css.typography as ty
#   ty.font(ty.stack("system"), "1rem", 400, 1.5)
#   ty.scale(16, ty.MAJOR_THIRD, -2, 4)          # {-2: "0.64rem", -1: "0.8rem", 0: "1rem", 1: "1.25rem", ...}
#   ty.fluid(16, 24, 320, 1280)                  # clamp(1rem, 0.8333rem + 0.8333vw, 1.5rem)
#   ty.truncate()                                # une ligne avec « … »
#   ty.line_clamp(3)                             # trois lignes au plus
#   ty.weight("semibold")                        # 600
#
# Erreurs : CssValueError (pile ou graisse inconnue, bornes de fluid incohérentes).

from core use len, type, to_float
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.units as _units

const MINOR_SECOND := 1.067
const MAJOR_SECOND := 1.125
const MINOR_THIRD := 1.2
const MAJOR_THIRD := 1.25
const PERFECT_FOURTH := 1.333
const AUGMENTED_FOURTH := 1.414
const PERFECT_FIFTH := 1.5
const GOLDEN_RATIO := 1.618

const STACKS := {
    "system": "system-ui, -apple-system, \"Segoe UI\", Roboto, \"Helvetica Neue\", Arial, \"Noto Sans\", sans-serif, \"Apple Color Emoji\", \"Segoe UI Emoji\"",
    "sans": "ui-sans-serif, system-ui, sans-serif",
    "serif": "ui-serif, Georgia, Cambria, \"Times New Roman\", Times, serif",
    "mono": "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace",
    "humanist": "Seravek, \"Gill Sans Nova\", Ubuntu, Calibri, \"DejaVu Sans\", source-sans-pro, sans-serif",
    "geometric": "Avenir, Montserrat, Corbel, \"URW Gothic\", source-sans-pro, sans-serif",
    "old-style": "\"Iowan Old Style\", \"Palatino Linotype\", \"URW Palladio L\", P052, serif",
    "rounded": "ui-rounded, \"Hiragino Maru Gothic ProN\", Quicksand, Comfortaa, Manjari, \"Arial Rounded MT\", Calibri, source-sans-pro, sans-serif"
}

const WEIGHTS := {"thin": 100, "hairline": 100, "extralight": 200, "ultralight": 200, "light": 300, "normal": 400, "regular": 400, "medium": 500, "semibold": 600, "demibold": 600, "bold": 700, "extrabold": 800, "ultrabold": 800, "black": 900, "heavy": 900}

const GENERIC := ["serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui", "ui-serif", "ui-sans-serif", "ui-monospace", "ui-rounded", "math", "emoji", "fangsong"]

func stack(name):
    if name in STACKS:
        return STACKS[name]
    _err.value_error("typography.stack", "pile de polices inconnue « " + str(name) + " »")

# font-family depuis une liste de noms (guillemets ajoutés quand il le faut).
func family(names):
    if type(names) == "str":
        return names
    parts := []
    for n in names:
        t := _s.trim(str(n))
        if _s.contains(t, " ") and not _s.starts_with(t, "\"") and not (_s.lower(t) in GENERIC):
            t = "\"" + t + "\""
        append(parts, t)
    return _s.join(", ", parts)

func weight(name):
    if type(name) == "int":
        return name
    n := _s.lower(_s.replace(_s.replace(str(name), "-", ""), " ", ""))
    if n in WEIGHTS:
        return WEIGHTS[n]
    _err.value_error("typography.weight", "graisse inconnue « " + str(name) + " »")

func _len(v):
    if type(v) == "int" or type(v) == "float":
        return str(v) + "px"
    return str(v)

# Déclarations de police ; null : propriété omise.
func font(family_value=null, size=null, weight_value=null, line_height=null, style=null):
    d := {}
    if family_value != null:
        d["font-family"] = family(family_value)
    if size != null:
        d["font-size"] = _len(size)
    if weight_value != null:
        d["font-weight"] = str(weight(weight_value))
    if line_height != null:
        d["line-height"] = str(line_height)
    if style != null:
        d["font-style"] = style
    return d

func _rem(px, base):
    return _units.format_number(to_float(px) / to_float(base)) + "rem"

# Échelle modulaire : pas -> taille (rem par rapport à base px).
func scale(base=16, ratio=MAJOR_THIRD, low=-2, high=5, in_px=false):
    out := {}
    k := low
    while k <= high:
        v := to_float(base) * (to_float(ratio) ** k)
        out[k] = (_units.format_number(v) + "px") if in_px else _rem(v, base)
        k += 1
    return out

# Variables CSS d'une échelle : --step--2 … --step-5.
func scale_variables(base=16, ratio=MAJOR_THIRD, low=-2, high=5, prefix="--step-"):
    out := {}
    sc := scale(base, ratio, low, high)
    for k in keys(sc):
        out[prefix + str(k)] = sc[k]
    return out

# Taille fluide entre min_px (à min_vw px de large) et max_px (à max_vw px) : clamp(min, a + b·vw, max).
func fluid(min_px, max_px, min_vw=320, max_vw=1280, base=16):
    if to_float(max_vw) <= to_float(min_vw):
        _err.value_error("typography.fluid", "max_vw doit être supérieur à min_vw")
    slope := (to_float(max_px) - to_float(min_px)) / (to_float(max_vw) - to_float(min_vw))
    intercept := to_float(min_px) - slope * to_float(min_vw)
    lo := _rem(min_px if min_px <= max_px else max_px, base)
    hi := _rem(max_px if max_px >= min_px else min_px, base)
    pref := _rem(intercept, base) + " + " + _units.format_number(slope * 100.0) + "vw"
    if intercept < 0:
        pref = _units.format_number(slope * 100.0) + "vw - " + _rem(-intercept, base)
    return "clamp(" + lo + ", " + pref + ", " + hi + ")"

# Taille (px) qu'une valeur fluid donnerait à une largeur d'écran donnée.
func fluid_at(min_px, max_px, width, min_vw=320, max_vw=1280):
    w := to_float(width)
    if w <= to_float(min_vw):
        return to_float(min_px)
    if w >= to_float(max_vw):
        return to_float(max_px)
    t := (w - to_float(min_vw)) / (to_float(max_vw) - to_float(min_vw))
    return to_float(min_px) + (to_float(max_px) - to_float(min_px)) * t

func truncate():
    return {"overflow": "hidden", "text-overflow": "ellipsis", "white-space": "nowrap"}

func line_clamp(lines):
    return {"display": "-webkit-box", "-webkit-box-orient": "vertical", "-webkit-line-clamp": str(lines), "line-clamp": str(lines), "overflow": "hidden"}

# Largeur de lecture confortable (45 à 75 caractères).
func measure(chars=65):
    return {"max-width": str(chars) + "ch"}

func break_words():
    return {"overflow-wrap": "anywhere", "word-break": "normal", "hyphens": "auto"}

func balance():
    return {"text-wrap": "balance"}

func pretty():
    return {"text-wrap": "pretty"}

func uppercase(spacing="0.05em"):
    return {"text-transform": "uppercase", "letter-spacing": spacing}

func tabular_numbers():
    return {"font-variant-numeric": "tabular-nums"}

func smoothing():
    return {"-webkit-font-smoothing": "antialiased", "-moz-osx-font-smoothing": "grayscale"}

# Hauteur de ligne conseillée selon la taille (px) : plus serrée pour les grands titres.
func leading_for(size_px):
    s := to_float(size_px)
    if s >= 48:
        return 1.1
    if s >= 32:
        return 1.2
    if s >= 20:
        return 1.35
    return 1.5

# Styles de titres h1..h6 depuis une échelle : dict sélecteur -> déclarations.
func headings(base=16, ratio=MAJOR_THIRD, family_value=null, weight_value=700):
    out := {}
    lvl := 1
    while lvl <= 6:
        stp := 6 - lvl
        px := to_float(base) * (to_float(ratio) ** stp)
        d := font(family_value, _rem(px, base), weight_value, leading_for(px))
        out["h" + str(lvl)] = d
        lvl += 1
    return out

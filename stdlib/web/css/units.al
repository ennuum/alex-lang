# ALEX STANDARD LIBRARY — web.css.units
#
# Unités CSS (CSS Values and Units Level 4) : longueurs absolues (px, cm, mm, Q, in, pt, pc) et relatives (em,
# rem, ex, ch, lh, vw, vh, vmin, vmax, dvh, svw, cqw…), angles, durées, fréquences, résolutions, pourcentages,
# fractions de grille (fr). Dimension associe un nombre et une unité ; conversion entre unités compatibles,
# vers les pixels avec un contexte (taille de police, fenêtre).
#
#   use web.css.units as u
#   d := u.parse("1.5rem")            # Dimension(1.5, "rem")
#   str(d)                            # 1.5rem
#   u.to_px(d, u.Context(16, 16))     # 24.0
#   u.convert(u.parse("1in"), "cm")   # 2.54cm
#   u.convert(u.parse("90deg"), "rad")   # 1.5708rad
#   str(u.px(12)), str(u.percent(50)), str(u.ms(250))
#   u.format_number(0.50)             # 0.5
#
# Erreurs : CssValueError (texte non numérique, unités incompatibles).

from core use len, type, to_int, to_float
use string as _s
use web.css.css_errors as _err

const ABSOLUTE_LENGTHS := {"px": 1.0, "cm": 37.79527559055118, "mm": 3.7795275590551185, "q": 0.9448818897637796, "in": 96.0, "pt": 1.3333333333333333, "pc": 16.0}
const FONT_RELATIVE := ["em", "rem", "ex", "rex", "ch", "rch", "cap", "rcap", "ic", "ric", "lh", "rlh"]
const VIEWPORT := ["vw", "vh", "vi", "vb", "vmin", "vmax", "svw", "svh", "svi", "svb", "svmin", "svmax", "lvw", "lvh", "lvi", "lvb", "lvmin", "lvmax", "dvw", "dvh", "dvi", "dvb", "dvmin", "dvmax"]
const CONTAINER := ["cqw", "cqh", "cqi", "cqb", "cqmin", "cqmax"]
const ANGLES := {"deg": 1.0, "grad": 0.9, "rad": 57.29577951308232, "turn": 360.0}
const TIMES := {"s": 1000.0, "ms": 1.0}
const FREQUENCIES := {"hz": 1.0, "khz": 1000.0}
const RESOLUTIONS := {"dppx": 1.0, "x": 1.0, "dpi": 0.010416666666666666, "dpcm": 0.026458333333333334}
const FLEX := ["fr"]

# Écriture compacte d'un nombre : entiers sans « .0 », au plus 4 décimales, zéros finaux retirés.
func format_number(x):
    if type(x) == "int":
        return str(x)
    v := to_float(x)
    neg := v < 0
    if neg:
        v = -v
    n := to_int(v * 10000 + 0.5)
    whole := n // 10000
    frac := n % 10000
    out := str(whole)
    if frac != 0:
        f := str(frac)
        while len(f) < 4:
            f = "0" + f
        while _s.ends_with(f, "0"):
            f = f[0:len(f) - 1]
        out = out + "." + f
    if neg and out != "0":
        out = "-" + out
    return out

# Catégorie d'une unité : length, angle, time, frequency, resolution, percentage, flex, number ("" ), ou null.
func kind_of(unit):
    u := _s.lower(unit)
    if u == "":
        return "number"
    if u == "%":
        return "percentage"
    if u in ABSOLUTE_LENGTHS or u in FONT_RELATIVE or u in VIEWPORT or u in CONTAINER:
        return "length"
    if u in ANGLES:
        return "angle"
    if u in TIMES:
        return "time"
    if u in FREQUENCIES:
        return "frequency"
    if u in RESOLUTIONS:
        return "resolution"
    if u in FLEX:
        return "flex"
    return null

func is_known(unit):
    return kind_of(unit) != null

func is_length_unit(unit):
    return kind_of(unit) == "length"

func is_relative(unit):
    u := _s.lower(unit)
    return u in FONT_RELATIVE or u in VIEWPORT or u in CONTAINER or u == "%"

class Dimension:
    func init(value, unit=""):
        self.value = value
        self.unit = unit

    func kind():
        return kind_of(self.unit)

    func is_zero():
        return self.value == 0

    func to_css():
        return format_number(self.value) + self.unit

    func __str__():
        return self.to_css()

    func __eq__(other):
        return isinstance(other, Dimension) and other.value == self.value and _s.lower(other.unit) == _s.lower(self.unit)

    func with_value(v):
        return Dimension(v, self.unit)

    func __add__(other):
        if not isinstance(other, Dimension) or _s.lower(other.unit) != _s.lower(self.unit):
            _err.value_error("Dimension", "addition d'unités différentes (" + str(self) + " + " + str(other) + ") : utiliser calc()")
        return Dimension(self.value + other.value, self.unit)

    func __sub__(other):
        if not isinstance(other, Dimension) or _s.lower(other.unit) != _s.lower(self.unit):
            _err.value_error("Dimension", "soustraction d'unités différentes : utiliser calc()")
        return Dimension(self.value - other.value, self.unit)

    func __mul__(k):
        return Dimension(self.value * k, self.unit)

    func __truediv__(k):
        return Dimension(self.value / k, self.unit)

    func __neg__():
        return Dimension(-self.value, self.unit)

func _is_digit(c):
    return c >= '0' and c <= '9'

# Découpe « 12.5px » / « -3e2% » / « .5 » en (nombre, unité) ; null si ce n'est pas un nombre CSS.
func split_number(text):
    t := _s.trim(text)
    n := len(t)
    if n == 0:
        return null
    i := 0
    if t[i] == '+' or t[i] == '-':
        i += 1
    digits := 0
    while i < n and _is_digit(t[i]):
        i += 1
        digits += 1
    if i < n and t[i] == '.':
        i += 1
        while i < n and _is_digit(t[i]):
            i += 1
            digits += 1
    if digits == 0:
        return null
    if i < n and (t[i] == 'e' or t[i] == 'E'):
        j := i + 1
        if j < n and (t[j] == '+' or t[j] == '-'):
            j += 1
        if j < n and _is_digit(t[j]):
            while j < n and _is_digit(t[j]):
                j += 1
            i = j
    num_text := t[0:i]
    unit := t[i:n]
    for c in unit:
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '%'):
            return null
    if unit == "%" or unit == "" or not _s.contains(unit, "%"):
        v := to_float(num_text)
        if not _s.contains(num_text, ".") and not _s.contains(num_text, "e") and not _s.contains(num_text, "E"):
            v = to_int(num_text)
        return (v, unit)
    return null

# Dimension depuis un texte ; CssValueError s'il n'est pas un nombre suivi d'une unité connue (ou rien).
func parse(text):
    r := split_number(str(text))
    if r == null:
        _err.value_error("units.parse", "nombre CSS attendu (obtenu « " + str(text) + " »)")
    if r[1] != "" and not is_known(r[1]):
        _err.value_error("units.parse", "unité inconnue « " + r[1] + " » dans « " + str(text) + " »")
    return Dimension(r[0], _s.lower(r[1]) if r[1] != "Q" else "Q")

func try_parse(text):
    try:
        return parse(text)
    catch e:
        return null

func _factor(unit):
    u := _s.lower(unit)
    if u in ABSOLUTE_LENGTHS:
        return ABSOLUTE_LENGTHS[u]
    if u in ANGLES:
        return ANGLES[u]
    if u in TIMES:
        return TIMES[u]
    if u in FREQUENCIES:
        return FREQUENCIES[u]
    if u in RESOLUTIONS:
        return RESOLUTIONS[u]
    return null

# Conversion entre unités absolues d'une même catégorie (px <-> cm, deg <-> rad, s <-> ms...).
func convert(d, unit):
    a := _factor(d.unit)
    b := _factor(unit)
    if a == null or b == null or kind_of(d.unit) != kind_of(unit):
        _err.value_error("units.convert", "conversion impossible de " + str(d) + " en " + unit)
    return Dimension(d.value * a / b, unit)

# Contexte de résolution des unités relatives.
class Context:
    func init(font_size=16.0, root_font_size=16.0, viewport_width=1280.0, viewport_height=720.0, percent_base=null, container_width=null, container_height=null):
        self.font_size = font_size
        self.root_font_size = root_font_size
        self.viewport_width = viewport_width
        self.viewport_height = viewport_height
        self.percent_base = percent_base
        self.container_width = container_width if container_width != null else viewport_width
        self.container_height = container_height if container_height != null else viewport_height

# Longueur en pixels (float) dans le contexte ; CssValueError pour une unité non longueur.
func to_px(d, ctx=null):
    c := ctx if ctx != null else Context()
    u := _s.lower(d.unit)
    v := to_float(d.value)
    if u == "" and v == 0:
        return 0.0
    if u in ABSOLUTE_LENGTHS:
        return v * ABSOLUTE_LENGTHS[u]
    if u == "em":
        return v * c.font_size
    if u == "rem":
        return v * c.root_font_size
    if u == "ex" or u == "cap":
        return v * c.font_size * 0.5
    if u == "ch" or u == "ic":
        return v * c.font_size * 0.5
    if u == "lh":
        return v * c.font_size * 1.2
    if u == "rlh":
        return v * c.root_font_size * 1.2
    if u == "%":
        if c.percent_base == null:
            _err.value_error("units.to_px", "pourcentage sans base dans le contexte")
        return v * c.percent_base / 100.0
    if _s.ends_with(u, "vw") or _s.ends_with(u, "vi"):
        return v * c.viewport_width / 100.0
    if _s.ends_with(u, "vh") or _s.ends_with(u, "vb"):
        return v * c.viewport_height / 100.0
    if _s.ends_with(u, "vmin"):
        return v * (c.viewport_width if c.viewport_width < c.viewport_height else c.viewport_height) / 100.0
    if _s.ends_with(u, "vmax"):
        return v * (c.viewport_width if c.viewport_width > c.viewport_height else c.viewport_height) / 100.0
    if u == "cqw" or u == "cqi":
        return v * c.container_width / 100.0
    if u == "cqh" or u == "cqb":
        return v * c.container_height / 100.0
    if u == "cqmin":
        return v * (c.container_width if c.container_width < c.container_height else c.container_height) / 100.0
    if u == "cqmax":
        return v * (c.container_width if c.container_width > c.container_height else c.container_height) / 100.0
    _err.value_error("units.to_px", "pas une longueur : " + str(d))

# Durée en millisecondes.
func to_ms(d):
    return convert(d, "ms").value

# Angle en degrés.
func to_deg(d):
    return convert(d, "deg").value

# ---------------------------------------------------------------- constructeurs

func px(v):
    return Dimension(v, "px")

func em(v):
    return Dimension(v, "em")

func rem(v):
    return Dimension(v, "rem")

func percent(v):
    return Dimension(v, "%")

func vw(v):
    return Dimension(v, "vw")

func vh(v):
    return Dimension(v, "vh")

func fr(v):
    return Dimension(v, "fr")

func deg(v):
    return Dimension(v, "deg")

func ms(v):
    return Dimension(v, "ms")

func seconds(v):
    return Dimension(v, "s")

func ch(v):
    return Dimension(v, "ch")

# Texte d'une valeur de longueur : nombre -> px (0 sans unité), Dimension ou texte inchangés.
func length(v):
    if type(v) == "int" or type(v) == "float":
        if v == 0:
            return "0"
        return format_number(v) + "px"
    return str(v)

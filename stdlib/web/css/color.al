# ALEX STANDARD LIBRARY — web.css.color
#
# Couleurs CSS (CSS Color Level 4) : lecture de toutes les écritures courantes — #rgb, #rgba, #rrggbb,
# #rrggbbaa, rgb() / rgba() (virgules ou espaces, pourcentages, « / alpha »), hsl() / hsla(), hwb(), les 148 noms
# de couleurs, transparent — et calculs : éclaircir, assombrir, mélanger, saturer, inverser, niveaux de gris,
# luminance et contraste WCAG 2.
#
#   use web.css.color as col
#   c := col.parse("hsl(210 50% 40% / .8)")
#   c.to_hex()                        # #336699cc
#   str(c)                            # rgb(51 102 153 / 0.8)
#   col.parse("rebeccapurple").to_hex()   # #663399
#   col.parse("#336699").lighten(0.2).to_hex()
#   col.contrast_ratio(col.parse("#777"), col.parse("#fff"))   # 4.48
#   col.is_readable("#777", "#fff")   # false (AA texte normal : 4.5)
#   col.mix(col.parse("red"), col.parse("blue"), 0.5).to_hex()  # #800080
#
# Erreurs : CssValueError.

from core use len, type, to_int, to_float
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.units as _units

const _NAMED := "aliceblue:f0f8ff antiquewhite:faebd7 aqua:00ffff aquamarine:7fffd4 azure:f0ffff beige:f5f5dc bisque:ffe4c4 black:000000 blanchedalmond:ffebcd blue:0000ff blueviolet:8a2be2 brown:a52a2a burlywood:deb887 cadetblue:5f9ea0 chartreuse:7fff00 chocolate:d2691e coral:ff7f50 cornflowerblue:6495ed cornsilk:fff8dc crimson:dc143c cyan:00ffff darkblue:00008b darkcyan:008b8b darkgoldenrod:b8860b darkgray:a9a9a9 darkgreen:006400 darkgrey:a9a9a9 darkkhaki:bdb76b darkmagenta:8b008b darkolivegreen:556b2f darkorange:ff8c00 darkorchid:9932cc darkred:8b0000 darksalmon:e9967a darkseagreen:8fbc8f darkslateblue:483d8b darkslategray:2f4f4f darkslategrey:2f4f4f darkturquoise:00ced1 darkviolet:9400d3 deeppink:ff1493 deepskyblue:00bfff dimgray:696969 dimgrey:696969 dodgerblue:1e90ff firebrick:b22222 floralwhite:fffaf0 forestgreen:228b22 fuchsia:ff00ff gainsboro:dcdcdc ghostwhite:f8f8ff gold:ffd700 goldenrod:daa520 gray:808080 green:008000 greenyellow:adff2f grey:808080 honeydew:f0fff0 hotpink:ff69b4 indianred:cd5c5c indigo:4b0082 ivory:fffff0 khaki:f0e68c lavender:e6e6fa lavenderblush:fff0f5 lawngreen:7cfc00 lemonchiffon:fffacd lightblue:add8e6 lightcoral:f08080 lightcyan:e0ffff lightgoldenrodyellow:fafad2 lightgray:d3d3d3 lightgreen:90ee90 lightgrey:d3d3d3 lightpink:ffb6c1 lightsalmon:ffa07a lightseagreen:20b2aa lightskyblue:87cefa lightslategray:778899 lightslategrey:778899 lightsteelblue:b0c4de lightyellow:ffffe0 lime:00ff00 limegreen:32cd32 linen:faf0e6 magenta:ff00ff maroon:800000 mediumaquamarine:66cdaa mediumblue:0000cd mediumorchid:ba55d3 mediumpurple:9370db mediumseagreen:3cb371 mediumslateblue:7b68ee mediumspringgreen:00fa9a mediumturquoise:48d1cc mediumvioletred:c71585 midnightblue:191970 mintcream:f5fffa mistyrose:ffe4e1 moccasin:ffe4b5 navajowhite:ffdead navy:000080 oldlace:fdf5e6 olive:808000 olivedrab:6b8e23 orange:ffa500 orangered:ff4500 orchid:da70d6 palegoldenrod:eee8aa palegreen:98fb98 paleturquoise:afeeee palevioletred:db7093 papayawhip:ffefd5 peachpuff:ffdab9 peru:cd853f pink:ffc0cb plum:dda0dd powderblue:b0e0e6 purple:800080 rebeccapurple:663399 red:ff0000 rosybrown:bc8f8f royalblue:4169e1 saddlebrown:8b4513 salmon:fa8072 sandybrown:f4a460 seagreen:2e8b57 seashell:fff5ee sienna:a0522d silver:c0c0c0 skyblue:87ceeb slateblue:6a5acd slategray:708090 slategrey:708090 snow:fffafa springgreen:00ff7f steelblue:4682b4 tan:d2b48c teal:008080 thistle:d8bfd8 tomato:ff6347 turquoise:40e0d0 violet:ee82ee wheat:f5deb3 white:ffffff whitesmoke:f5f5f5 yellow:ffff00 yellowgreen:9acd32"

# Mots-clés de couleur qui ne sont pas des couleurs fixes.
const KEYWORDS := ["currentcolor", "inherit", "initial", "unset", "revert", "revert-layer"]

_names := [null]

func _table():
    if _names[0] == null:
        d := {}
        for item in _s.split(_NAMED, " "):
            c := _s.find(item, ":")
            d[item[0:c]] = item[c + 1:len(item)]
        _names[0] = d
    return _names[0]

func named_colors():
    return _table()

func _hexval(c):
    o := _s.ord(c)
    if o >= 48 and o <= 57:
        return o - 48
    if o >= 97 and o <= 102:
        return o - 87
    if o >= 65 and o <= 70:
        return o - 55
    return -1

func _clamp(v, lo, hi):
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v

func _round(v):
    return to_int(v + 0.5) if v >= 0 else -to_int(-v + 0.5)

func _hex2(n):
    digits := "0123456789abcdef"
    v := _clamp(_round(n), 0, 255)
    return str(digits[v >> 4]) + str(digits[v & 15])

class Color:
    # r, g, b : 0..255 (float accepté) ; a : 0..1.
    func init(r=0, g=0, b=0, a=1.0):
        self.r = _clamp(to_float(r), 0.0, 255.0)
        self.g = _clamp(to_float(g), 0.0, 255.0)
        self.b = _clamp(to_float(b), 0.0, 255.0)
        self.a = _clamp(to_float(a), 0.0, 1.0)

    func rgb_ints():
        return (_round(self.r), _round(self.g), _round(self.b))

    # « #rrggbb » (ou « #rrggbbaa » si transparente) ; short : « #rgb » quand c'est possible.
    func to_hex(short=false):
        out := "#" + _hex2(self.r) + _hex2(self.g) + _hex2(self.b)
        if self.a < 1.0:
            out = out + _hex2(self.a * 255)
        if short:
            ok := true
            i := 1
            while i < len(out):
                if out[i] != out[i + 1]:
                    ok = false
                i += 2
            if ok:
                s := "#"
                i = 1
                while i < len(out):
                    s = s + str(out[i])
                    i += 2
                return s
        return out

    # « rgb(r g b) » / « rgb(r g b / a) » (syntaxe moderne) ; legacy : « rgba(r, g, b, a) ».
    func to_rgb(legacy=false):
        t := self.rgb_ints()
        if legacy:
            if self.a < 1.0:
                return "rgba(" + str(t[0]) + ", " + str(t[1]) + ", " + str(t[2]) + ", " + _units.format_number(self.a) + ")"
            return "rgb(" + str(t[0]) + ", " + str(t[1]) + ", " + str(t[2]) + ")"
        out := "rgb(" + str(t[0]) + " " + str(t[1]) + " " + str(t[2])
        if self.a < 1.0:
            out = out + " / " + _units.format_number(self.a)
        return out + ")"

    # (teinte 0..360, saturation 0..100, luminosité 0..100).
    func hsl():
        r := self.r / 255.0
        g := self.g / 255.0
        b := self.b / 255.0
        mx := r if r > g and r > b else (g if g > b else b)
        mn := r if r < g and r < b else (g if g < b else b)
        l := (mx + mn) / 2.0
        h := 0.0
        s := 0.0
        d := mx - mn
        if d > 0.0:
            s = d / (1.0 - (2.0 * l - 1.0 if 2.0 * l - 1.0 >= 0 else 1.0 - 2.0 * l))
            if mx == r:
                h = 60.0 * (((g - b) / d) % 6.0)
            elif mx == g:
                h = 60.0 * ((b - r) / d + 2.0)
            else:
                h = 60.0 * ((r - g) / d + 4.0)
        if h < 0:
            h += 360.0
        return (h, s * 100.0, l * 100.0)

    func to_hsl():
        t := self.hsl()
        out := "hsl(" + _units.format_number(_round(t[0] * 10) / 10.0) + " " + _units.format_number(_round(t[1] * 10) / 10.0) + "% " + _units.format_number(_round(t[2] * 10) / 10.0) + "%"
        if self.a < 1.0:
            out = out + " / " + _units.format_number(self.a)
        return out + ")"

    # Écriture la plus courte : nom (si exact), #rgb, #rrggbb, ou rgb() avec alpha.
    func to_css():
        h := self.to_hex(true)
        if self.a >= 1.0:
            n := name_of(self)
            if n != null and len(n) < len(h):
                return n
            return h
        if self.a == 0 and self.r == 0 and self.g == 0 and self.b == 0:
            return "transparent"
        return self.to_rgb()

    func __str__():
        return self.to_rgb()

    func __eq__(other):
        if not isinstance(other, Color):
            return false
        return self.rgb_ints() == other.rgb_ints() and _round(self.a * 1000) == _round(other.a * 1000)

    func with_alpha(a):
        return Color(self.r, self.g, self.b, a)

    # Luminosité HSL augmentée de amount (0..1 : fraction de 100 %).
    func lighten(amount):
        t := self.hsl()
        return from_hsl(t[0], t[1], _clamp(t[2] + amount * 100.0, 0.0, 100.0), self.a)

    func darken(amount):
        return self.lighten(-amount)

    func saturate(amount):
        t := self.hsl()
        return from_hsl(t[0], _clamp(t[1] + amount * 100.0, 0.0, 100.0), t[2], self.a)

    func desaturate(amount):
        return self.saturate(-amount)

    func rotate_hue(degrees):
        t := self.hsl()
        return from_hsl((t[0] + degrees) % 360.0, t[1], t[2], self.a)

    func complement():
        return self.rotate_hue(180)

    func invert():
        return Color(255 - self.r, 255 - self.g, 255 - self.b, self.a)

    func grayscale():
        y := 0.2126 * self.r + 0.7152 * self.g + 0.0722 * self.b
        return Color(y, y, y, self.a)

    # Luminance relative WCAG 2 (0 noir .. 1 blanc).
    func luminance():
        return 0.2126 * _lin(self.r) + 0.7152 * _lin(self.g) + 0.0722 * _lin(self.b)

    func is_dark():
        return self.luminance() < 0.179

    # Noir ou blanc, selon ce qui contraste le mieux sur cette couleur de fond.
    func text_color():
        if contrast_ratio(self, Color(0, 0, 0)) >= contrast_ratio(self, Color(255, 255, 255)):
            return Color(0, 0, 0)
        return Color(255, 255, 255)

func _lin(c):
    v := c / 255.0
    if v <= 0.04045:
        return v / 12.92
    return ((v + 0.055) / 1.055) ** 2.4

# Rapport de contraste WCAG 2 entre deux couleurs (1..21), arrondi à 2 décimales.
func contrast_ratio(a, b):
    ca := parse(a) if type(a) == "str" else a
    cb := parse(b) if type(b) == "str" else b
    la := ca.luminance()
    lb := cb.luminance()
    hi := la if la > lb else lb
    lo := lb if la > lb else la
    r := (hi + 0.05) / (lo + 0.05)
    return _round(r * 100) / 100.0

# Lisibilité WCAG : level « AA » (4.5, grand texte 3) ou « AAA » (7, grand texte 4.5).
func is_readable(fg, bg, level="AA", large_text=false):
    r := contrast_ratio(fg, bg)
    if level == "AAA":
        return r >= (4.5 if large_text else 7.0)
    return r >= (3.0 if large_text else 4.5)

# Mélange : weight = part de b (0..1) ; alpha mélangée aussi.
func mix(a, b, weight=0.5):
    ca := parse(a) if type(a) == "str" else a
    cb := parse(b) if type(b) == "str" else b
    w := to_float(weight)
    return Color(ca.r + (cb.r - ca.r) * w, ca.g + (cb.g - ca.g) * w, ca.b + (cb.b - ca.b) * w, ca.a + (cb.a - ca.a) * w)

func _hue_to_rgb(p, q, t):
    tt := t
    if tt < 0:
        tt += 1.0
    if tt > 1:
        tt -= 1.0
    if tt < 1.0 / 6.0:
        return p + (q - p) * 6.0 * tt
    if tt < 0.5:
        return q
    if tt < 2.0 / 3.0:
        return p + (q - p) * (2.0 / 3.0 - tt) * 6.0
    return p

# Couleur depuis teinte (degrés), saturation et luminosité (0..100).
func from_hsl(h, s, l, a=1.0):
    hh := (to_float(h) % 360.0) / 360.0
    ss := _clamp(to_float(s), 0.0, 100.0) / 100.0
    ll := _clamp(to_float(l), 0.0, 100.0) / 100.0
    if ss == 0:
        return Color(ll * 255, ll * 255, ll * 255, a)
    q := ll * (1 + ss) if ll < 0.5 else ll + ss - ll * ss
    p := 2 * ll - q
    return Color(_hue_to_rgb(p, q, hh + 1.0 / 3.0) * 255, _hue_to_rgb(p, q, hh) * 255, _hue_to_rgb(p, q, hh - 1.0 / 3.0) * 255, a)

func from_hwb(h, w, bk, a=1.0):
    ww := to_float(w) / 100.0
    bb := to_float(bk) / 100.0
    if ww + bb >= 1:
        g := ww / (ww + bb) * 255
        return Color(g, g, g, a)
    base := from_hsl(h, 100, 50)
    f := 1 - ww - bb
    return Color(base.r * f + ww * 255, base.g * f + ww * 255, base.b * f + ww * 255, a)

# Nom CSS exact de la couleur (opaque), ou null.
func name_of(c):
    h := c.to_hex()
    if len(h) != 7:
        return null
    hx := h[1:7]
    t := _table()
    for k in t:
        if t[k] == hx:
            return k
    return null

func is_named(name):
    return _s.lower(name) in _table()

# ---------------------------------------------------------------- analyse

func _fail(text):
    _err.value_error("color.parse", "couleur invalide « " + str(text) + " »")

# Arguments d'une fonction de couleur : liste de str, et alpha (str ou null) ; virgules ou espaces + « / ».
func _args(inner):
    t := _s.trim(inner)
    alpha := null
    slash := _s.find(t, "/")
    if slash >= 0:
        alpha = _s.trim(t[slash + 1:len(t)])
        t = _s.trim(t[0:slash])
    parts := []
    if _s.contains(t, ","):
        for p in _s.split(t, ","):
            append(parts, _s.trim(p))
    else:
        for p in _s.split(t, " "):
            if _s.trim(p) != "":
                append(parts, _s.trim(p))
    if alpha == null and len(parts) == 4:
        alpha = parts[3]
        parts = parts[0:3]
    return (parts, alpha)

func _num(text, full, pct_scale=null):
    t := _s.trim(text)
    if t == "none":
        return 0.0
    if _s.ends_with(t, "%"):
        v := _units.split_number(t)
        if v == null:
            _fail(full)
        return to_float(v[0]) * (pct_scale if pct_scale != null else 1.0) / 100.0
    v := _units.split_number(t)
    if v == null:
        _fail(full)
    if v[1] == "deg" or v[1] == "":
        return to_float(v[0])
    if v[1] == "turn":
        return to_float(v[0]) * 360.0
    if v[1] == "rad":
        return to_float(v[0]) * 57.29577951308232
    if v[1] == "grad":
        return to_float(v[0]) * 0.9
    _fail(full)

func _alpha(text, full):
    if text == null:
        return 1.0
    return _clamp(_num(text, full, 1.0), 0.0, 1.0)

# Couleur depuis du texte CSS ; CssValueError si invalide. Les mots-clés currentcolor, inherit... ne sont pas des
# couleurs fixes : CssValueError (voir is_color pour un simple test).
func parse(text):
    if isinstance(text, Color):
        return text
    if type(text) != "str":
        _fail(text)
    t := _s.lower(_s.trim(text))
    if t == "transparent":
        return Color(0, 0, 0, 0)
    if _s.starts_with(t, "#"):
        h := t[1:len(t)]
        for c in h:
            if _hexval(c) < 0:
                _fail(text)
        n := len(h)
        if n == 3 or n == 4:
            a := 1.0 if n == 3 else _hexval(h[3]) * 17 / 255.0
            return Color(_hexval(h[0]) * 17, _hexval(h[1]) * 17, _hexval(h[2]) * 17, a)
        if n == 6 or n == 8:
            a := 1.0 if n == 6 else (_hexval(h[6]) * 16 + _hexval(h[7])) / 255.0
            return Color(_hexval(h[0]) * 16 + _hexval(h[1]), _hexval(h[2]) * 16 + _hexval(h[3]), _hexval(h[4]) * 16 + _hexval(h[5]), a)
        _fail(text)
    p := _s.find(t, "(")
    if p > 0 and _s.ends_with(t, ")"):
        fn := _s.trim(t[0:p])
        r := _args(t[p + 1:len(t) - 1])
        a := r[0]
        if len(a) != 3:
            _fail(text)
        if fn == "rgb" or fn == "rgba":
            return Color(_num(a[0], text, 255.0), _num(a[1], text, 255.0), _num(a[2], text, 255.0), _alpha(r[1], text))
        if fn == "hsl" or fn == "hsla":
            return from_hsl(_num(a[0], text), _num(a[1], text, 100.0), _num(a[2], text, 100.0), _alpha(r[1], text))
        if fn == "hwb":
            return from_hwb(_num(a[0], text), _num(a[1], text, 100.0), _num(a[2], text, 100.0), _alpha(r[1], text))
        _fail(text)
    tb := _table()
    if t in tb:
        return parse("#" + tb[t])
    _fail(text)

func try_parse(text):
    try:
        return parse(text)
    catch e:
        return null

# Vrai si le texte est une couleur CSS valide (mots-clés currentcolor, inherit... compris).
func is_color(text):
    if type(text) == "str" and _s.lower(_s.trim(text)) in KEYWORDS:
        return true
    return try_parse(text) != null

func rgb(r, g, b, a=1.0):
    return Color(r, g, b, a)

func hsl(h, s, l, a=1.0):
    return from_hsl(h, s, l, a)

# Nuancier de 10 teintes (50, 100…900) autour d'une couleur de base (500), comme les palettes des design systems.
func shades(base):
    c := parse(base) if type(base) == "str" else base
    t := c.hsl()
    levels := [(50, 95), (100, 90), (200, 80), (300, 70), (400, 60), (500, t[2]), (600, t[2] * 0.85), (700, t[2] * 0.7), (800, t[2] * 0.55), (900, t[2] * 0.4)]
    out := {}
    for lv in levels:
        out[lv[0]] = from_hsl(t[0], t[1], lv[1]).to_hex()
    return out

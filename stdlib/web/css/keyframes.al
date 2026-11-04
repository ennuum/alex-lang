# ALEX STANDARD LIBRARY — web.css.keyframes
#
# @keyframes : construction, sérialisation, lecture et interpolation des images clés (nombres, dimensions de même
# unité, couleurs, fonctions de même nom ; le reste change d'un coup à mi-chemin, comme en CSS).
#
#   use web.css.keyframes as kf
#   k := kf.Keyframes("apparition")
#   k.frame("from", {"opacity": 0, "transform": "translateY(8px)"})
#   k.frame("to", {"opacity": 1, "transform": "translateY(0)"})
#   k.to_css()                         # @keyframes apparition { from { opacity: 0; ... } to { ... } }
#   k.at(0.5)                          # {"opacity": "0.5", "transform": "translateY(4px)"}
#   kf.interpolate("#000", "#fff", 0.5)          # #808080
#   kf.interpolate("10px 0", "20px 4px", 0.25)   # 12.5px 1px
#   kf.fade_in("fondu")                # Keyframes prêtes à l'emploi : fade_in, fade_out, slide_in, spin, pulse...
#
# Erreurs : CssValueError (sélecteur d'image clé invalide, progression hors de 0..1).

from core use len, type, to_float
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.units as _units
use web.css.color as _color
use web.css.declaration as _decl
use web.css.css_rule as _rule

# « from » -> 0, « to » -> 1, « 25% » -> 0.25 ; nombre 0..1 accepté tel quel.
func parse_offset(text):
    if type(text) == "int" or type(text) == "float":
        v := to_float(text)
        if v > 1.0:
            v = v / 100.0
        if v < 0.0 or v > 1.0:
            _err.value_error("keyframes.parse_offset", "position hors de 0..100 % : " + str(text))
        return v
    t := _s.lower(_s.trim(str(text)))
    if t == "from":
        return 0.0
    if t == "to":
        return 1.0
    if _s.ends_with(t, "%"):
        try:
            v := to_float(t[0:len(t) - 1]) / 100.0
            if v >= 0.0 and v <= 1.0:
                return v
        catch e:
            pass
    _err.value_error("keyframes.parse_offset", "sélecteur d'image clé invalide « " + str(text) + " »")

func format_offset(v):
    if v == 0.0:
        return "from"
    if v == 1.0:
        return "to"
    return _units.format_number(v * 100.0) + "%"

class Frame:
    func init(offsets, declarations):
        self.offsets = offsets          # liste de nombres 0..1
        self.declarations = declarations

    func selector(compact=false):
        parts := []
        for o in self.offsets:
            append(parts, format_offset(o) if not compact else _compact_offset(o))
        return _s.join("," if compact else ", ", parts)

    func get(name):
        d := _decl.find(self.declarations, name)
        return d.value if d != null else null

    func to_css(fmt=null, level=0):
        f := fmt if fmt != null else _rule.Format()
        pad := _s.repeat(f.indent, level) if f.pretty else ""
        sp := "" if f.compact else " "
        return pad + self.selector(f.compact) + sp + _rule.write_block(self.declarations, [], f, level)

func _compact_offset(o):
    if o == 0.0:
        return "0%"
    if o == 1.0:
        return "to"
    return _units.format_number(o * 100.0) + "%"

class Keyframes:
    func init(name, frames=null, prefix=""):
        self.kind = "keyframes"
        self.name = str(name)
        self.prefix = prefix              # « -webkit- » éventuel
        self.frames = []
        self.line = null
        self.parent = null
        if frames != null:
            for k in keys(frames):
                self.frame(k, frames[k])

    # Ajoute une image clé ; offsets : « from », « 50% », 0.5 ou une liste ; declarations : dict, texte ou liste.
    func frame(offsets, declarations):
        offs := []
        if type(offsets) == "list" or type(offsets) == "tuple":
            for o in offsets:
                append(offs, parse_offset(o))
        elif type(offsets) == "str" and _s.contains(offsets, ","):
            for o in _s.split(offsets, ","):
                append(offs, parse_offset(o))
        else:
            append(offs, parse_offset(offsets))
        ds := declarations
        if type(declarations) == "dict":
            ds = _decl.from_dict(declarations)
        elif type(declarations) == "str":
            ds = _decl.parse_block(declarations)
        append(self.frames, Frame(offs, ds))
        return self

    # Images clés à plat, triées : liste de (position, dict propriété -> valeur).
    func stops():
        out := []
        for f in self.frames:
            for o in f.offsets:
                merged := false
                for s in out:
                    if s[0] == o:
                        for d in f.declarations:
                            s[1][d.property] = d.value
                        merged = true
                if not merged:
                    append(out, (o, _decl.to_dict(f.declarations)))
        i := 1
        while i < len(out):
            cur := out[i]
            j := i - 1
            while j >= 0 and out[j][0] > cur[0]:
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = cur
            i += 1
        return out

    func properties():
        seen := []
        for f in self.frames:
            for d in f.declarations:
                if not (d.property in seen):
                    append(seen, d.property)
        return seen

    # Valeurs à la progression t (0..1). base : dict des valeurs hors animation (images 0 % / 100 % implicites).
    # easing : fonction t -> t appliquée entre deux images (null : linéaire).
    func at(t, base=null, easing=null):
        if t < 0.0 or t > 1.0:
            _err.value_error("Keyframes.at", "progression hors de 0..1 : " + str(t))
        st := self.stops()
        out := {}
        for p in self.properties():
            pts := []
            for s in st:
                if p in s[1]:
                    append(pts, (s[0], s[1][p]))
            if base != null and p in base:
                if len(pts) == 0 or pts[0][0] > 0.0:
                    pts = [(0.0, str(base[p]))] + pts
                if pts[len(pts) - 1][0] < 1.0:
                    append(pts, (1.0, str(base[p])))
            if len(pts) == 0:
                continue
            if t <= pts[0][0]:
                out[p] = pts[0][1]
                continue
            if t >= pts[len(pts) - 1][0]:
                out[p] = pts[len(pts) - 1][1]
                continue
            i := 0
            while i + 1 < len(pts) and pts[i + 1][0] < t:
                i += 1
            a := pts[i]
            b := pts[i + 1]
            span := b[0] - a[0]
            local := 1.0 if span == 0 else (t - a[0]) / span
            if easing != null:
                local = easing(local)
            out[p] = interpolate(a[1], b[1], local)
        return out

    func copy():
        k := Keyframes(self.name, null, self.prefix)
        for f in self.frames:
            ds := []
            for d in f.declarations:
                append(ds, d.copy())
            append(k.frames, Frame(f.offsets + [], ds))
        return k

    func flatten():
        return self

    func flatten_in(parent_selector):
        return self

    func to_css(fmt=null, level=0):
        f := fmt if fmt != null else _rule.Format()
        pad := _s.repeat(f.indent, level) if f.pretty else ""
        head := "@" + self.prefix + "keyframes " + _value.escape_ident(self.name)
        if f.compact:
            inner := ""
            for fr in self.frames:
                inner = inner + fr.to_css(f, level + 1)
            return head + "{" + inner + "}"
        parts := []
        for fr in self.frames:
            append(parts, fr.to_css(f, level + 1))
        if f.pretty:
            return pad + head + " {\n" + _s.join("\n", parts) + "\n" + pad + "}"
        return head + " { " + _s.join(" ", parts) + " }"

    func __str__():
        return self.to_css()

# ---------------------------------------------------------------- interpolation

func _lerp(a, b, t):
    return a + (b - a) * t

func _as_color(item):
    if isinstance(item, _value.Token):
        if item.kind == _value.HASH or (item.kind == _value.IDENT and _color.is_named(item.value)):
            return _color.try_parse(item.to_css())
        return null
    if isinstance(item, _value.Function) and item.lower_name() in ["rgb", "rgba", "hsl", "hsla", "hwb"]:
        return _color.try_parse(item.to_css())
    return null

func _interp_item(a, b, t):
    ca := _as_color(a)
    cb := _as_color(b)
    if ca != null and cb != null:
        return _color.mix(ca, cb, t).to_css()
    if isinstance(a, _value.Token) and isinstance(b, _value.Token):
        if a.kind == _value.NUMBER and b.kind == _value.NUMBER:
            return _units.format_number(_lerp(to_float(a.value), to_float(b.value), t))
        if a.kind == _value.PERCENTAGE and b.kind == _value.PERCENTAGE:
            return _units.format_number(_lerp(to_float(a.value), to_float(b.value), t)) + "%"
        if a.kind == _value.DIMENSION and b.kind == _value.DIMENSION and _s.lower(a.unit) == _s.lower(b.unit):
            return _units.format_number(_lerp(to_float(a.value), to_float(b.value), t)) + a.unit
        if (a.kind == _value.DIMENSION or a.kind == _value.NUMBER) and (b.kind == _value.DIMENSION or b.kind == _value.NUMBER):
            # 0 sans unité contre une longueur : l'unité de l'autre côté.
            av := to_float(a.value)
            bv := to_float(b.value)
            if a.kind == _value.NUMBER and av == 0.0:
                return _units.format_number(_lerp(0.0, bv, t)) + b.unit
            if b.kind == _value.NUMBER and bv == 0.0:
                return _units.format_number(_lerp(av, 0.0, t)) + a.unit
        if a.to_css() == b.to_css():
            return a.to_css()
        return null
    if isinstance(a, _value.Function) and isinstance(b, _value.Function) and a.lower_name() == b.lower_name():
        inner := _interp_list(a.args, b.args, t)
        if inner == null:
            return null
        return a.name + "(" + inner + ")"
    if a.to_css() == b.to_css():
        return a.to_css()
    return null

func _interp_list(xs, ys, t):
    if len(xs) != len(ys):
        return null
    parts := []
    i := 0
    while i < len(xs):
        r := _interp_item(xs[i], ys[i], t)
        if r == null:
            return null
        append(parts, r)
        i += 1
    return _s.join("", parts)

# Valeur intermédiaire entre deux valeurs CSS (texte) à t (0..1) ; non interpolable : a avant 0.5, b ensuite.
func interpolate(a, b, t):
    sa := str(a)
    sb := str(b)
    if t <= 0.0:
        return sa
    if t >= 1.0:
        return sb
    r := _interp_list(_value.parse(sa).items, _value.parse(sb).items, t)
    if r == null:
        return sa if t < 0.5 else sb
    return r

func is_interpolable(a, b):
    return _interp_list(_value.parse(str(a)).items, _value.parse(str(b)).items, 0.5) != null

# ---------------------------------------------------------------- animations prêtes à l'emploi

func fade_in(name="fade-in"):
    return Keyframes(name).frame("from", {"opacity": "0"}).frame("to", {"opacity": "1"})

func fade_out(name="fade-out"):
    return Keyframes(name).frame("from", {"opacity": "1"}).frame("to", {"opacity": "0"})

# direction : "up", "down", "left", "right" (depuis où l'élément arrive).
func slide_in(name="slide-in", direction="up", distance="1rem"):
    d := str(distance)
    tr := "translateY(" + d + ")"
    if direction == "down":
        tr = "translateY(-" + d + ")"
    elif direction == "left":
        tr = "translateX(-" + d + ")"
    elif direction == "right":
        tr = "translateX(" + d + ")"
    return Keyframes(name).frame("from", {"opacity": "0", "transform": tr}).frame("to", {"opacity": "1", "transform": _zero(tr)})

func _zero(tr):
    i := _s.find(tr, "(")
    return tr[0:i] + "(0)"

func spin(name="spin"):
    return Keyframes(name).frame("from", {"transform": "rotate(0deg)"}).frame("to", {"transform": "rotate(360deg)"})

func pulse(name="pulse", scale=1.05):
    return Keyframes(name).frame(["0%", "100%"], {"transform": "scale(1)"}).frame("50%", {"transform": "scale(" + str(scale) + ")"})

func shake(name="shake", distance="4px"):
    d := str(distance)
    k := Keyframes(name)
    k.frame(["0%", "100%"], {"transform": "translateX(0)"})
    k.frame(["20%", "60%"], {"transform": "translateX(-" + d + ")"})
    k.frame(["40%", "80%"], {"transform": "translateX(" + d + ")"})
    return k

func bounce(name="bounce", height="12px"):
    k := Keyframes(name)
    k.frame(["0%", "100%"], {"transform": "translateY(0)"})
    k.frame("50%", {"transform": "translateY(-" + str(height) + ")"})
    return k

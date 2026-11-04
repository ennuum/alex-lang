# ALEX STANDARD LIBRARY — web.css.transforms
#
# Transformations : construction chaînée (translate, scale, rotate, skew, perspective, matrix), analyse d'une
# valeur transform, et calcul de la matrice affine 2D résultante (application à des points, inverse,
# décomposition) pour vérifier une mise en page ou un tracé.
#
#   use web.css.transforms as tf
#   t := tf.Transform().translate(10, 20).rotate(45).scale(2)
#   t.to_css()                           # translate(10px, 20px) rotate(45deg) scale(2)
#   t.declarations("center")             # {"transform": "…", "transform-origin": "center"}
#   m := tf.matrix_of("translate(10px, 0) scale(2)")
#   m.apply(5, 5)                        # (20.0, 10.0)
#   m.to_css()                           # matrix(2, 0, 0, 2, 10, 0)
#   tf.parse("rotate(.5turn) translateX(-50%)")   # [("rotate", ["0.5turn"]), ("translateX", ["-50%"])]
#   tf.matrix_of("rotate(90deg)").decompose()     # {"translate": (0, 0), "rotate": 90.0, "scale": (1, 1), ...}
#
# Erreurs : CssValueError (fonction de transformation inconnue, unité non convertible, matrice non inversible).

from core use len, type, to_float
from collections use append
use string as _s
use math as _math
use web.css.css_errors as _err
use web.css.value as _value
use web.css.units as _units

const FUNCTIONS := ["matrix", "matrix3d", "translate", "translate3d", "translatex", "translatey", "translatez", "scale", "scale3d", "scalex", "scaley", "scalez", "rotate", "rotate3d", "rotatex", "rotatey", "rotatez", "skew", "skewx", "skewy", "perspective"]

func _len(v):
    if type(v) == "int" or type(v) == "float":
        return _units.format_number(v) + "px" if v != 0 else "0"
    return str(v)

func _ang(v):
    if type(v) == "int" or type(v) == "float":
        return _units.format_number(v) + "deg"
    return str(v)

func _num(v):
    if type(v) == "int" or type(v) == "float":
        return _units.format_number(v)
    return str(v)

class Transform:
    func init():
        self.parts = []

    func add(text):
        append(self.parts, str(text))
        return self

    func translate(x, y=null):
        if y == null:
            return self.add("translate(" + _len(x) + ")")
        return self.add("translate(" + _len(x) + ", " + _len(y) + ")")

    func translate_x(x):
        return self.add("translateX(" + _len(x) + ")")

    func translate_y(y):
        return self.add("translateY(" + _len(y) + ")")

    func translate_3d(x, y, z):
        return self.add("translate3d(" + _len(x) + ", " + _len(y) + ", " + _len(z) + ")")

    func scale(x, y=null):
        if y == null:
            return self.add("scale(" + _num(x) + ")")
        return self.add("scale(" + _num(x) + ", " + _num(y) + ")")

    func scale_x(x):
        return self.add("scaleX(" + _num(x) + ")")

    func scale_y(y):
        return self.add("scaleY(" + _num(y) + ")")

    func rotate(angle):
        return self.add("rotate(" + _ang(angle) + ")")

    func rotate_x(angle):
        return self.add("rotateX(" + _ang(angle) + ")")

    func rotate_y(angle):
        return self.add("rotateY(" + _ang(angle) + ")")

    func skew(x, y=null):
        if y == null:
            return self.add("skew(" + _ang(x) + ")")
        return self.add("skew(" + _ang(x) + ", " + _ang(y) + ")")

    func perspective(d):
        return self.add("perspective(" + _len(d) + ")")

    func matrix(a, b, c, d, e, f):
        return self.add("matrix(" + _s.join(", ", [_num(a), _num(b), _num(c), _num(d), _num(e), _num(f)]) + ")")

    func to_css():
        if len(self.parts) == 0:
            return "none"
        return _s.join(" ", self.parts)

    func __str__():
        return self.to_css()

    func declarations(origin=null):
        d := {"transform": self.to_css()}
        if origin != null:
            d["transform-origin"] = origin
        return d

    func matrix2d(ctx=null):
        return matrix_of(self.to_css(), ctx)

# Fonctions d'une valeur transform : liste de (nom, [arguments texte]).
func parse(text):
    t := _s.trim(str(text))
    if _s.lower(t) == "none" or t == "":
        return []
    out := []
    for it in _value.parse(t).components:
        if not isinstance(it, _value.Function) or not (it.lower_name() in FUNCTIONS):
            _err.value_error("transforms.parse", "fonction de transformation inconnue « " + it.to_css() + " »")
        args := []
        for g in it.arg_groups():
            for x in g:
                if not (isinstance(x, _value.Token) and x.kind == _value.WHITESPACE):
                    append(args, x.to_css())
        append(out, (it.name, args))
    return out

func is_valid(text):
    try:
        parse(text)
        return true
    catch e:
        return false

# ---------------------------------------------------------------- matrice 2D

# Matrice affine [a c e; b d f; 0 0 1] (ordre CSS : matrix(a, b, c, d, e, f)).
class Matrix:
    func init(a=1.0, b=0.0, c=0.0, d=1.0, e=0.0, f=0.0):
        self.a = to_float(a)
        self.b = to_float(b)
        self.c = to_float(c)
        self.d = to_float(d)
        self.e = to_float(e)
        self.f = to_float(f)

    # Produit self × m (m appliquée d'abord).
    func multiply(m):
        return Matrix(self.a * m.a + self.c * m.b, self.b * m.a + self.d * m.b, self.a * m.c + self.c * m.d, self.b * m.c + self.d * m.d, self.a * m.e + self.c * m.f + self.e, self.b * m.e + self.d * m.f + self.f)

    func apply(x, y):
        fx := to_float(x)
        fy := to_float(y)
        return (_clean(self.a * fx + self.c * fy + self.e), _clean(self.b * fx + self.d * fy + self.f))

    func determinant():
        return self.a * self.d - self.b * self.c

    func is_identity():
        return _near(self.a, 1) and _near(self.b, 0) and _near(self.c, 0) and _near(self.d, 1) and _near(self.e, 0) and _near(self.f, 0)

    func inverse():
        det := self.determinant()
        if _near(det, 0):
            _err.value_error("Matrix.inverse", "matrice non inversible")
        return Matrix(self.d / det, -self.b / det, -self.c / det, self.a / det, (self.c * self.f - self.d * self.e) / det, (self.b * self.e - self.a * self.f) / det)

    # Translation, rotation (deg), échelle, cisaillement (deg).
    func decompose():
        sx := _math.sqrt(self.a * self.a + self.b * self.b)
        rot := _math.atan2(self.b, self.a) * 180.0 / _math.PI
        shear := 0.0
        sy := 0.0
        if sx != 0:
            shear = (self.a * self.c + self.b * self.d) / (sx * sx)
            sy = self.determinant() / sx
        return {"translate": (_clean(self.e), _clean(self.f)), "rotate": _clean(rot), "scale": (_clean(sx), _clean(sy)), "skew": _clean(_math.atan(shear) * 180.0 / _math.PI)}

    # Boîte englobante (x, y, largeur, hauteur) d'un rectangle transformé.
    func bounds(x, y, w, h):
        pts := [self.apply(x, y), self.apply(x + w, y), self.apply(x, y + h), self.apply(x + w, y + h)]
        minx := pts[0][0]
        maxx := pts[0][0]
        miny := pts[0][1]
        maxy := pts[0][1]
        for p in pts:
            if p[0] < minx:
                minx = p[0]
            if p[0] > maxx:
                maxx = p[0]
            if p[1] < miny:
                miny = p[1]
            if p[1] > maxy:
                maxy = p[1]
        return (minx, miny, _clean(maxx - minx), _clean(maxy - miny))

    func to_css():
        return "matrix(" + _s.join(", ", [_units.format_number(_clean(self.a)), _units.format_number(_clean(self.b)), _units.format_number(_clean(self.c)), _units.format_number(_clean(self.d)), _units.format_number(_clean(self.e)), _units.format_number(_clean(self.f))]) + ")"

    func __str__():
        return self.to_css()

func _near(a, b):
    return a - b < 0.000000001 and b - a < 0.000000001

func _clean(v):
    r := to_float(v)
    if _near(r, 0):
        return 0.0
    rounded := _math.round(r * 1000000.0) / 1000000.0
    return rounded

func identity():
    return Matrix()

func _px(text, ctx, base):
    t := _s.trim(text)
    d := _units.parse(t)
    if d.unit == "%":
        if base == null:
            _err.value_error("transforms.matrix_of", "pourcentage sans boîte de référence « " + t + " »")
        return to_float(d.value) * base / 100.0
    if d.unit == "":
        return to_float(d.value)
    return _units.to_px(d, ctx)

func _deg(text):
    t := _s.trim(text)
    d := _units.parse(t)
    if d.unit == "" and to_float(d.value) == 0.0:
        return 0.0
    return _units.to_deg(d)

func _scale_arg(text):
    t := _s.trim(text)
    if _s.ends_with(t, "%"):
        return to_float(t[0:len(t) - 1]) / 100.0
    return to_float(t)

func _rad(deg):
    return deg * _math.PI / 180.0

# Matrice 2D d'une valeur transform ; box : (largeur, hauteur) pour les pourcentages de translate.
func matrix_of(text, ctx=null, box=null):
    c := ctx if ctx != null else _units.Context()
    bw := to_float(box[0]) if box != null else null
    bh := to_float(box[1]) if box != null else null
    m := Matrix()
    for fn in parse(text):
        name := _s.lower(fn[0])
        a := fn[1]
        step := null
        if name == "translate" or name == "translate3d":
            step = Matrix(1, 0, 0, 1, _px(a[0], c, bw), _px(a[1], c, bh) if len(a) > 1 else 0.0)
        elif name == "translatex":
            step = Matrix(1, 0, 0, 1, _px(a[0], c, bw), 0)
        elif name == "translatey":
            step = Matrix(1, 0, 0, 1, 0, _px(a[0], c, bh))
        elif name == "translatez" or name == "perspective" or name == "rotatex" or name == "rotatey" or name == "scalez":
            step = Matrix()
        elif name == "scale" or name == "scale3d":
            sx := _scale_arg(a[0])
            step = Matrix(sx, 0, 0, _scale_arg(a[1]) if len(a) > 1 else sx, 0, 0)
        elif name == "scalex":
            step = Matrix(_scale_arg(a[0]), 0, 0, 1, 0, 0)
        elif name == "scaley":
            step = Matrix(1, 0, 0, _scale_arg(a[0]), 0, 0)
        elif name == "rotate" or name == "rotatez":
            r := _rad(_deg(a[0]))
            step = Matrix(_math.cos(r), _math.sin(r), -_math.sin(r), _math.cos(r), 0, 0)
        elif name == "skew":
            step = Matrix(1, _math.tan(_rad(_deg(a[1]))) if len(a) > 1 else 0.0, _math.tan(_rad(_deg(a[0]))), 1, 0, 0)
        elif name == "skewx":
            step = Matrix(1, 0, _math.tan(_rad(_deg(a[0]))), 1, 0, 0)
        elif name == "skewy":
            step = Matrix(1, _math.tan(_rad(_deg(a[0]))), 0, 1, 0, 0)
        elif name == "matrix":
            if len(a) != 6:
                _err.value_error("transforms.matrix_of", "matrix() attend 6 nombres")
            step = Matrix(to_float(a[0]), to_float(a[1]), to_float(a[2]), to_float(a[3]), to_float(a[4]), to_float(a[5]))
        else:
            _err.value_error("transforms.matrix_of", "« " + fn[0] + " » non pris en charge en 2D")
        m = m.multiply(step)
    return m

# Matrice tenant compte de transform-origin (ox, oy en px).
func matrix_with_origin(text, ox, oy, ctx=null, box=null):
    t := Matrix(1, 0, 0, 1, ox, oy)
    back := Matrix(1, 0, 0, 1, -to_float(ox), -to_float(oy))
    return t.multiply(matrix_of(text, ctx, box)).multiply(back)

# ---------------------------------------------------------------- raccourcis

func center_translate():
    return {"transform": "translate(-50%, -50%)"}

func flip_horizontal():
    return {"transform": "scaleX(-1)"}

func flip_vertical():
    return {"transform": "scaleY(-1)"}

func perspective_container(distance="800px", origin="center"):
    return {"perspective": _len(distance), "perspective-origin": origin}

func preserve_3d():
    return {"transform-style": "preserve-3d"}

func hide_backface():
    return {"backface-visibility": "hidden"}

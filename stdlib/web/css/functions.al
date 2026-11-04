# ALEX STANDARD LIBRARY — web.css.functions
#
# Fonctions CSS : construction (calc, min, max, clamp, url, attr, env, dégradés linéaires / radiaux / coniques)
# et évaluation des fonctions mathématiques (calc, min, max, clamp, abs, round...) en pixels dans un contexte
# (web.css.units.Context) — utile pour tester une mise en page ou calculer une typographie fluide.
#
#   use web.css.functions as fn
#   fn.calc("100% - 2rem")                         # calc(100% - 2rem)
#   fn.clamp("1rem", "2.5vw", "2rem")              # clamp(1rem, 2.5vw, 2rem)
#   fn.linear_gradient(["#fff", ("#000", "80%")], "to right")   # linear-gradient(to right, #fff, #000 80%)
#   fn.url("img/fond 1.png")                       # url("img/fond 1.png")
#   fn.evaluate("calc(100% - 2rem)", units.Context(16, 16, 1280, 720, 400))   # 368.0
#   fn.evaluate("clamp(16px, 2.5vw, 24px)", units.Context())                   # 24.0 (2.5vw = 32px)
#
# Erreurs : CssValueError (expression non évaluable : unités incompatibles, division par zéro, syntaxe).

from core use len, type, to_int, to_float
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.units as _units
use web.css.value as _value

const MATH_FUNCTIONS := ["calc", "min", "max", "clamp", "abs", "sign", "round", "mod", "rem", "sin", "cos", "tan", "sqrt", "pow", "hypot", "exp", "log"]

func is_math_function(name):
    return _s.lower(name) in MATH_FUNCTIONS

func _args(values):
    parts := []
    for v in values:
        if v != null:
            append(parts, str(v))
    return _s.join(", ", parts)

func calc(expression):
    return "calc(" + str(expression) + ")"

func min(a, b, c=null, d=null):
    return "min(" + _args([a, b, c, d]) + ")"

func max(a, b, c=null, d=null):
    return "max(" + _args([a, b, c, d]) + ")"

func clamp(minimum, preferred, maximum):
    return "clamp(" + str(minimum) + ", " + str(preferred) + ", " + str(maximum) + ")"

func url(path):
    return "url(" + _value.quote(path) + ")"

func attr(name, kind=null, fallback=null):
    inner := name
    if kind != null:
        inner = inner + " " + kind
    if fallback != null:
        inner = inner + ", " + str(fallback)
    return "attr(" + inner + ")"

func env(name, fallback=null):
    if fallback == null:
        return "env(" + name + ")"
    return "env(" + name + ", " + str(fallback) + ")"

# Arrêts de couleur : str (« red ») ou (couleur, position) / (couleur, début, fin).
func _stops(stops):
    parts := []
    for s in stops:
        if type(s) == "tuple" or type(s) == "list":
            items := []
            for x in s:
                append(items, str(x))
            append(parts, _s.join(" ", items))
        else:
            append(parts, str(s))
    return parts

func _gradient(name, head, stops):
    parts := []
    if head != null and head != "":
        append(parts, head)
    for p in _stops(stops):
        append(parts, p)
    return name + "(" + _s.join(", ", parts) + ")"

# direction : « to right », « 45deg »... (null : vers le bas).
func linear_gradient(stops, direction=null, repeating=false):
    return _gradient("repeating-linear-gradient" if repeating else "linear-gradient", direction, stops)

# shape : « circle », « ellipse closest-side »... ; position : « center », « 30% 40% ».
func radial_gradient(stops, shape=null, position=null, repeating=false):
    head := shape if shape != null else ""
    if position != null:
        head = _s.trim(head + " at " + position)
    return _gradient("repeating-radial-gradient" if repeating else "radial-gradient", head, stops)

func conic_gradient(stops, from_angle=null, position=null):
    head := ""
    if from_angle != null:
        head = "from " + str(from_angle)
    if position != null:
        head = _s.trim(head + " at " + position)
    return _gradient("conic-gradient", head, stops)

# ---------------------------------------------------------------- évaluation

# Valeur intermédiaire : (nombre, nature) ; nature « px » (longueur), « num » (sans unité), « deg », « ms ».
func _fail(msg):
    _err.value_error("functions.evaluate", msg)

class _Eval:
    func init(items, ctx):
        self.items = []
        for it in items:
            if not (isinstance(it, _value.Token) and it.kind == _value.WHITESPACE):
                append(self.items, it)
        self.i = 0
        self.ctx = ctx

    func peek():
        if self.i < len(self.items):
            return self.items[self.i]
        return null

    func expr():
        left := self.term()
        while true:
            t := self.peek()
            if t != null and isinstance(t, _value.Token) and (t.is_delim("+") or t.is_delim("-")):
                self.i += 1
                right := self.term()
                if left[1] != right[1]:
                    _fail("addition de natures différentes (" + left[1] + ", " + right[1] + ")")
                left = (left[0] + right[0], left[1]) if t.is_delim("+") else (left[0] - right[0], left[1])
            else:
                return left

    func term():
        left := self.factor()
        while true:
            t := self.peek()
            if t != null and isinstance(t, _value.Token) and (t.is_delim("*") or t.is_delim("/")):
                self.i += 1
                right := self.factor()
                if t.is_delim("*"):
                    if left[1] != "num" and right[1] != "num":
                        _fail("produit de deux grandeurs avec unités")
                    left = (left[0] * right[0], left[1] if left[1] != "num" else right[1])
                else:
                    if right[1] != "num":
                        _fail("division par une grandeur avec unité")
                    if right[0] == 0:
                        _fail("division par zéro")
                    left = (left[0] / right[0], left[1])
            else:
                return left

    func factor():
        t := self.peek()
        if t == null:
            _fail("expression incomplète")
        self.i += 1
        if isinstance(t, _value.Block) and t.open == "(":
            return _Eval(t.items, self.ctx).expr()
        if isinstance(t, _value.Function):
            return evaluate_function(t, self.ctx)
        if isinstance(t, _value.Token):
            if t.is_delim("-"):
                v := self.factor()
                return (-v[0], v[1])
            if t.kind == _value.NUMBER:
                return (to_float(t.value), "num")
            if t.kind == _value.PERCENTAGE:
                return (_units.to_px(_units.Dimension(t.value, "%"), self.ctx), "px")
            if t.kind == _value.DIMENSION:
                k := _units.kind_of(t.unit)
                d := _units.Dimension(t.value, _s.lower(t.unit))
                if k == "length":
                    return (_units.to_px(d, self.ctx), "px")
                if k == "angle":
                    return (_units.to_deg(d), "deg")
                if k == "time":
                    return (_units.to_ms(d), "ms")
                _fail("unité non prise en charge « " + t.unit + " »")
        _fail("élément inattendu « " + t.to_css() + " »")

func _eval_args(f, ctx):
    out := []
    for g in f.arg_groups():
        e := _Eval(g, ctx)
        v := e.expr()
        append(out, v)
    return out

# Évalue une fonction mathématique (Function de web.css.value) -> (nombre, nature).
func evaluate_function(f, ctx):
    name := f.lower_name()
    if name == "calc":
        return _Eval(f.args, ctx).expr()
    args := _eval_args(f, ctx)
    if len(args) == 0:
        _fail(name + "() sans argument")
    kind := args[0][1]
    for a in args:
        if a[1] != kind:
            _fail(name + "() : natures différentes")
    if name == "min" or name == "max":
        best := args[0][0]
        for a in args:
            if (name == "min" and a[0] < best) or (name == "max" and a[0] > best):
                best = a[0]
        return (best, kind)
    if name == "clamp":
        if len(args) != 3:
            _fail("clamp() attend 3 arguments")
        v := args[1][0]
        if v < args[0][0]:
            v = args[0][0]
        if v > args[2][0]:
            v = args[2][0]
        if args[0][0] > args[2][0]:
            v = args[0][0]
        return (v, kind)
    if name == "abs":
        return (args[0][0] if args[0][0] >= 0 else -args[0][0], kind)
    if name == "sign":
        x := args[0][0]
        return ((1.0 if x > 0 else (-1.0 if x < 0 else 0.0)), "num")
    if name == "round":
        step := args[1][0] if len(args) > 1 else 1.0
        return (to_float(to_int(args[0][0] / step + (0.5 if args[0][0] >= 0 else -0.5))) * step, kind)
    if name == "mod" or name == "rem":
        b := args[1][0]
        if b == 0:
            _fail("division par zéro")
        return (args[0][0] - b * to_int(args[0][0] / b), kind)
    if name == "sqrt":
        return (args[0][0] ** 0.5, kind)
    if name == "pow":
        return (args[0][0] ** args[1][0], kind)
    if name == "hypot":
        s := 0.0
        for a in args:
            s += a[0] * a[0]
        return (s ** 0.5, kind)
    _fail("fonction non évaluable « " + name + " »")

# Évalue une expression (« calc(100% - 2rem) », « 12px », « clamp(…) ») -> nombre (px pour une longueur, deg,
# ms, ou nombre pur).
func evaluate(text, ctx=null):
    c := ctx if ctx != null else _units.Context()
    v := _value.parse(text)
    if len(v.components) != 1 and not (len(v.components) > 1):
        _fail("expression vide")
    e := _Eval(v.items, c)
    r := e.expr()
    if e.peek() != null:
        _fail("texte en trop dans « " + str(text) + " »")
    return r[0]

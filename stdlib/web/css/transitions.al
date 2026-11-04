# ALEX STANDARD LIBRARY — web.css.transitions
#
# Transitions et fonctions d'accélération : construction et analyse de la propriété transition, ÉVALUATION
# des fonctions de temps (cubic-bezier() résolue numériquement, steps(), linear() par points, mots-clés ease…)
# et valeur intermédiaire d'une transition à un instant donné.
#
#   use web.css.transitions as tr
#   tr.transition(["opacity", "transform"], "200ms", "ease-out")
#   # {"transition": "opacity 200ms ease-out, transform 200ms ease-out"}
#   e := tr.easing("ease-in-out")
#   e.at(0.5)                                   # 0.5
#   tr.easing("cubic-bezier(0.34, 1.56, 0.64, 1)").at(0.5)   # > 1 (dépassement « ressort »)
#   tr.easing("steps(4, jump-end)").at(0.3)    # 0.25
#   tr.easing("linear(0, 0.25 75%, 1)").at(0.9)   # 0.7
#   t := tr.parse("opacity .3s ease-in 100ms")[0]
#   t.progress(250)                             # progression accélérée à 250 ms
#   t.value_at("0", "1", 250)                   # opacité interpolée
#
# Erreurs : CssValueError (fonction de temps ou transition invalide).

from core use len, type, to_float, to_int
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.units as _units
use web.css.keyframes as _kf

const NAMED := {"linear": (0.0, 0.0, 1.0, 1.0), "ease": (0.25, 0.1, 0.25, 1.0), "ease-in": (0.42, 0.0, 1.0, 1.0), "ease-out": (0.0, 0.0, 0.58, 1.0), "ease-in-out": (0.42, 0.0, 0.58, 1.0)}

# Courbes usuelles (à passer à easing() ou à utiliser telles quelles en CSS).
const EASE_OUT_QUART := "cubic-bezier(0.25, 1, 0.5, 1)"
const EASE_IN_OUT_CUBIC := "cubic-bezier(0.65, 0, 0.35, 1)"
const EASE_OUT_BACK := "cubic-bezier(0.34, 1.56, 0.64, 1)"
const EASE_OUT_EXPO := "cubic-bezier(0.16, 1, 0.3, 1)"
const EASE_IN_BACK := "cubic-bezier(0.36, 0, 0.66, -0.56)"

func _fail(msg):
    _err.value_error("transitions", msg)

class Easing:
    # kind : "cubic" (params x1 y1 x2 y2), "steps" (n, position), "linear" (liste de (sortie, entrée)).
    func init(kind, params, text):
        self.kind = kind
        self.params = params
        self.text = text

    func at(t):
        x := to_float(t)
        if self.kind == "cubic":
            return _cubic(self.params, x)
        if self.kind == "steps":
            return _steps(self.params[0], self.params[1], x)
        return _linear_points(self.params, x)

    func __call__(t):
        return self.at(t)

    func to_css():
        return self.text

    func __str__():
        return self.text

    # Échantillons (n + 1 points de 0 à 1) pour tracer la courbe.
    func samples(n=10):
        out := []
        i := 0
        while i <= n:
            append(out, self.at(i / n))
            i += 1
        return out

func _bez(p1, p2, t):
    # coordonnée d'une courbe de Bézier cubique de P0=0 à P3=1
    u := 1.0 - t
    return 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t

func _bez_d(p1, p2, t):
    u := 1.0 - t
    return 3.0 * u * u * p1 + 6.0 * u * t * (p2 - p1) + 3.0 * t * t * (1.0 - p2)

func _cubic(p, x):
    x1 := p[0]
    y1 := p[1]
    x2 := p[2]
    y2 := p[3]
    if x <= 0.0:
        if x1 > 0:
            return y1 / x1 * x
        if y1 == 0 and x2 > 0:
            return y2 / x2 * x
        return 0.0
    if x >= 1.0:
        if x2 < 1:
            return 1.0 + (y2 - 1.0) / (x2 - 1.0) * (x - 1.0)
        return 1.0
    # Newton puis dichotomie
    t := x
    i := 0
    while i < 8:
        err := _bez(x1, x2, t) - x
        if err < 0.0000001 and err > -0.0000001:
            return _bez(y1, y2, t)
        d := _bez_d(x1, x2, t)
        if d < 0.000001 and d > -0.000001:
            break
        t = t - err / d
        i += 1
    lo := 0.0
    hi := 1.0
    t = x
    i = 0
    while i < 60:
        v := _bez(x1, x2, t)
        if v - x < 0.0000001 and x - v < 0.0000001:
            break
        if v < x:
            lo = t
        else:
            hi = t
        t = (lo + hi) / 2.0
        i += 1
    return _bez(y1, y2, t)

func _floor(x):
    i := to_int(x)
    if to_float(i) > x:
        i -= 1
    return i

func _steps(n, position, x):
    jumps := n
    if position == "jump-none":
        jumps = n - 1
    elif position == "jump-both":
        jumps = n + 1
    step := _floor(x * n)
    if position == "jump-start" or position == "jump-both":
        step += 1
    if x >= 0 and step < 0:
        step = 0
    if x <= 1 and step > jumps:
        step = jumps
    if x >= 1.0:
        return 1.0
    return to_float(step) / jumps

func _linear_points(points, x):
    if x <= points[0][1]:
        return points[0][0]
    i := 1
    while i < len(points):
        a := points[i - 1]
        b := points[i]
        if x <= b[1]:
            span := b[1] - a[1]
            if span <= 0:
                return b[0]
            return a[0] + (b[0] - a[0]) * (x - a[1]) / span
        i += 1
    return points[len(points) - 1][0]

func cubic_bezier(x1, y1, x2, y2):
    if x1 < 0 or x1 > 1 or x2 < 0 or x2 > 1:
        _fail("cubic-bezier : x1 et x2 doivent être dans [0, 1]")
    text := "cubic-bezier(" + _s.join(", ", [_units.format_number(x1), _units.format_number(y1), _units.format_number(x2), _units.format_number(y2)]) + ")"
    return Easing("cubic", (to_float(x1), to_float(y1), to_float(x2), to_float(y2)), text)

func steps(n, position="jump-end"):
    pos := position
    if pos == "end":
        pos = "jump-end"
    elif pos == "start":
        pos = "jump-start"
    if not (pos in ["jump-start", "jump-end", "jump-none", "jump-both"]):
        _fail("position de steps() inconnue « " + str(position) + " »")
    if n < 1 or (pos == "jump-none" and n < 2):
        _fail("nombre de pas invalide pour steps()")
    text := "steps(" + str(n) + (")" if pos == "jump-end" else ", " + pos + ")")
    return Easing("steps", (n, pos), text)

# linear() : arrêts (sortie, position entre 0 et 1 ou null) ; positions manquantes réparties comme en CSS.
func linear_points(stops):
    pts := []
    for s in stops:
        if type(s) == "tuple" or type(s) == "list":
            append(pts, [to_float(s[0]), to_float(s[1]) if len(s) > 1 and s[1] != null else null])
        else:
            append(pts, [to_float(s), null])
    n := len(pts)
    if n < 2:
        _fail("linear() attend au moins deux points")
    if pts[0][1] == null:
        pts[0][1] = 0.0
    if pts[n - 1][1] == null:
        pts[n - 1][1] = 1.0
    i := 1
    while i < n:
        if pts[i][1] == null:
            j := i
            while pts[j][1] == null:
                j += 1
            a := pts[i - 1][1]
            b := pts[j][1]
            k := i
            while k < j:
                pts[k][1] = a + (b - a) * (k - i + 1) / (j - i + 1)
                k += 1
        if pts[i][1] < pts[i - 1][1]:
            pts[i][1] = pts[i - 1][1]
        i += 1
    out := []
    parts := []
    for p in pts:
        append(out, (p[0], p[1]))
        append(parts, _units.format_number(p[0]) + " " + _units.format_number(p[1] * 100.0) + "%")
    return Easing("linear", out, "linear(" + _s.join(", ", parts) + ")")

# Fonction de temps depuis du texte (mot-clé, cubic-bezier(), steps(), linear(), step-start, step-end).
func easing(text):
    if isinstance(text, Easing):
        return text
    t := _s.lower(_s.trim(str(text)))
    if t in NAMED:
        p := NAMED[t]
        if t == "linear":
            return Easing("linear", [(0.0, 0.0), (1.0, 1.0)], "linear")
        return Easing("cubic", p, t)
    if t == "step-start":
        e := steps(1, "jump-start")
        e.text = "step-start"
        return e
    if t == "step-end":
        e := steps(1, "jump-end")
        e.text = "step-end"
        return e
    v := _value.parse(t).components
    if len(v) != 1 or not isinstance(v[0], _value.Function):
        _fail("fonction de temps inconnue « " + str(text) + " »")
    f := v[0]
    groups := f.arg_groups()
    name := f.lower_name()
    if name == "cubic-bezier":
        if len(groups) != 4:
            _fail("cubic-bezier() attend 4 nombres")
        nums := []
        for g in groups:
            append(nums, to_float(_value.serialize(g)))
        return cubic_bezier(nums[0], nums[1], nums[2], nums[3])
    if name == "steps":
        n := to_int(_value.serialize(groups[0]))
        pos := "jump-end"
        if len(groups) > 1:
            pos = _s.trim(_value.serialize(groups[1]))
        return steps(n, pos)
    if name == "linear":
        stops := []
        for g in groups:
            items := []
            for x in g:
                if not (isinstance(x, _value.Token) and x.kind == _value.WHITESPACE):
                    append(items, x)
            if len(items) == 0:
                _fail("linear() : point vide")
            out_v := to_float(items[0].value)
            if len(items) == 1:
                append(stops, (out_v, null))
            else:
                k := 1
                while k < len(items):
                    append(stops, (out_v, to_float(items[k].value) / 100.0))
                    k += 1
        return linear_points(stops)
    _fail("fonction de temps inconnue « " + str(text) + " »")

func is_easing(text):
    try:
        easing(text)
        return true
    catch e:
        return false

# ---------------------------------------------------------------- transitions

func _time(v):
    if type(v) == "int" or type(v) == "float":
        return _units.format_number(v) + "ms"
    return str(v)

func _ms(text):
    d := _units.parse(_s.trim(str(text)))
    if d.unit == "" and to_float(d.value) == 0.0:
        return 0.0
    return _units.to_ms(d)

class Transition:
    func init(property="all", duration=0, timing="ease", delay=0, behavior=null):
        self.property = property
        self.duration = _ms(_time(duration))
        self.timing = easing(timing)
        self.delay = _ms(_time(delay))
        self.behavior = behavior          # "allow-discrete" éventuel

    func to_css():
        parts := [self.property, _units.format_number(self.duration) + "ms", self.timing.to_css()]
        if self.delay != 0:
            append(parts, _units.format_number(self.delay) + "ms")
        if self.behavior != null:
            append(parts, self.behavior)
        return _s.join(" ", parts)

    func __str__():
        return self.to_css()

    func end_time():
        return self.delay + self.duration

    # Progression accélérée (0..1, dépassements permis par la courbe) à elapsed ms depuis le changement.
    func progress(elapsed):
        e := to_float(elapsed) - self.delay
        if e <= 0:
            return 0.0
        if self.duration <= 0 or e >= self.duration:
            return 1.0
        return self.timing.at(e / self.duration)

    func value_at(start, end, elapsed):
        p := self.progress(elapsed)
        if p <= 0.0:
            return str(start)
        if p == 1.0:
            return str(end)
        return _kf.interpolate(start, end, p)

# Transitions d'une valeur de la propriété transition (« opacity .3s ease-in 100ms, transform 1s »).
func parse(text):
    t := _s.trim(str(text))
    if _s.lower(t) == "none" or t == "":
        return []
    out := []
    for group in _value.parse(t).split_commas():
        prop := null
        times := []
        timing := null
        behavior := null
        for it in group:
            if isinstance(it, _value.Token) and it.kind == _value.WHITESPACE:
                continue
            s := it.to_css()
            if isinstance(it, _value.Token) and it.kind == _value.DIMENSION and _units.kind_of(it.unit) == "time":
                append(times, s)
            elif isinstance(it, _value.Token) and it.kind == _value.NUMBER and to_float(it.value) == 0.0:
                append(times, "0s")
            elif isinstance(it, _value.Function) or (isinstance(it, _value.Token) and it.kind == _value.IDENT and (_s.lower(it.value) in NAMED or _s.lower(it.value) in ["step-start", "step-end"])):
                if timing != null:
                    _fail("deux fonctions de temps dans « " + _value.serialize(group) + " »")
                timing = s
            elif isinstance(it, _value.Token) and it.kind == _value.IDENT and _s.lower(it.value) in ["allow-discrete", "normal"]:
                behavior = _s.lower(it.value) if _s.lower(it.value) != "normal" else null
            elif isinstance(it, _value.Token) and it.kind == _value.IDENT and prop == null:
                prop = s
            else:
                _fail("élément inattendu « " + s + " » dans une transition")
        if len(times) > 2:
            _fail("plus de deux durées dans « " + _value.serialize(group) + " »")
        append(out, Transition(prop if prop != null else "all", times[0] if len(times) > 0 else 0, timing if timing != null else "ease", times[1] if len(times) > 1 else 0, behavior))
    return out

func is_valid(text):
    try:
        parse(text)
        return true
    catch e:
        return false

# Déclaration transition pour une ou plusieurs propriétés.
func transition(properties, duration="200ms", timing="ease", delay=null):
    props := properties if type(properties) == "list" else [properties]
    parts := []
    for p in props:
        s := str(p) + " " + _time(duration) + " " + easing(timing).to_css()
        if delay != null:
            s = s + " " + _time(delay)
        append(parts, s)
    return {"transition": _s.join(", ", parts)}

func none():
    return {"transition": "none"}

# Durée totale (ms) d'une liste de transitions (la plus longue fin).
func total_duration(text_or_list):
    items := parse(text_or_list) if type(text_or_list) == "str" else text_or_list
    best := 0.0
    for t in items:
        if t.end_time() > best:
            best = t.end_time()
    return best

# Désactive les mouvements pour les utilisateurs qui le demandent (règle à placer dans la feuille).
func reduced_motion_css():
    return "@media (prefers-reduced-motion: reduce) { *, *::before, *::after { animation-duration: 0.01ms !important; animation-iteration-count: 1 !important; transition-duration: 0.01ms !important; scroll-behavior: auto !important; } }"

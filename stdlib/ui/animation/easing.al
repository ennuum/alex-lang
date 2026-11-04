# ALEX STANDARD LIBRARY — ui.animation.easing V0.6
# Pure ALEX easing curves. Input t is normalized to [0,1].
# V1.2 : + elastic_*, circ_*, back_in_out, cubic-bezier (bezier), steps, evaluate(spec, t).
from core use type
use math as _math

func clamp01(t):
    if t < 0:
        return 0
    if t > 1:
        return 1
    return t

func linear(t):
    return clamp01(t)

func ease_in(t):
    t = clamp01(t)
    return t * t

func ease_out(t):
    t = clamp01(t)
    return 1 - (1 - t) * (1 - t)

func ease_in_out(t):
    t = clamp01(t)
    if t < 0.5:
        return 2 * t * t
    q := 1 - t
    return 1 - 2 * q * q

func smoothstep(t):
    t = clamp01(t)
    return t * t * (3 - 2 * t)

func smootherstep(t):
    t = clamp01(t)
    return t * t * t * (t * (t * 6 - 15) + 10)

func cubic_in(t):
    t = clamp01(t)
    return t * t * t

func cubic_out(t):
    t = clamp01(t)
    q := t - 1
    return q * q * q + 1

func cubic_in_out(t):
    t = clamp01(t)
    if t < 0.5:
        return 4 * t * t * t
    q := 2 * t - 2
    return 0.5 * q * q * q + 1

func quart_in(t):
    t = clamp01(t)
    return t * t * t * t

func quart_out(t):
    q := 1 - clamp01(t)
    return 1 - q * q * q * q

func quart_in_out(t):
    t = clamp01(t)
    if t < 0.5:
        return 8 * t * t * t * t
    q := 1 - t
    return 1 - 8 * q * q * q * q

func quint_in(t):
    t = clamp01(t)
    return t * t * t * t * t

func quint_out(t):
    q := 1 - clamp01(t)
    return 1 - q * q * q * q * q

func quint_in_out(t):
    t = clamp01(t)
    if t < 0.5:
        return 16 * t * t * t * t * t
    q := 1 - t
    return 1 - 16 * q * q * q * q * q

func sine_in(t):
    # Polynomial approximation: smooth and dependency-free.
    return ease_in_out(t)

func sine_out(t):
    return ease_out(t)

func sine_in_out(t):
    return smoothstep(t)

func expo_in(t):
    t = clamp01(t)
    if t == 0:
        return 0
    # Stable polynomial approximation without external math dependency.
    return t * t * t * t * t * t

func expo_out(t):
    t = clamp01(t)
    if t == 1:
        return 1
    q := 1 - t
    return 1 - q * q * q * q * q * q

func expo_in_out(t):
    return ease_in_out(t)

func back_out(t):
    t = clamp01(t)
    q := t - 1
    return q * q * ((1.7 + 1) * q + 1.7) + 1

func back_in(t):
    t = clamp01(t)
    return t * t * ((1.7 + 1) * t - 1.7)

func bounce_out(t):
    t = clamp01(t)
    if t < 0.3636:
        return 7.5625 * t * t
    if t < 0.7272:
        q := t - 0.5454
        return 7.5625 * q * q + 0.75
    if t < 0.9090:
        q := t - 0.8181
        return 7.5625 * q * q + 0.9375
    q := t - 0.9545
    return 7.5625 * q * q + 0.984375

func bounce_in(t):
    return 1 - bounce_out(1 - clamp01(t))

func bounce_in_out(t):
    t = clamp01(t)
    if t < 0.5:
        return bounce_in(t * 2) * 0.5
    return bounce_out(t * 2 - 1) * 0.5 + 0.5


# ---- V1.2 : courbes supplémentaires ----
const _C4 := 2.0943951023931953      # 2*pi/3
const _C5 := 1.3962634015954636      # 2*pi/4.5

func elastic_in(t):
    t = clamp01(t)
    if t == 0:
        return 0
    if t == 1:
        return 1
    return 0 - _math.pow(2.0, 10.0 * t - 10.0) * _math.sin((t * 10.0 - 10.75) * _C4)

func elastic_out(t):
    t = clamp01(t)
    if t == 0:
        return 0
    if t == 1:
        return 1
    return _math.pow(2.0, 0.0 - 10.0 * t) * _math.sin((t * 10.0 - 0.75) * _C4) + 1

func elastic_in_out(t):
    t = clamp01(t)
    if t == 0:
        return 0
    if t == 1:
        return 1
    if t < 0.5:
        return 0 - (_math.pow(2.0, 20.0 * t - 10.0) * _math.sin((20.0 * t - 11.125) * _C5)) / 2
    return (_math.pow(2.0, 10.0 - 20.0 * t) * _math.sin((20.0 * t - 11.125) * _C5)) / 2 + 1

func circ_in(t):
    t = clamp01(t)
    return 1 - _math.sqrt(1 - t * t)

func circ_out(t):
    t = clamp01(t)
    q := t - 1
    return _math.sqrt(1 - q * q)

func circ_in_out(t):
    t = clamp01(t)
    if t < 0.5:
        return (1 - _math.sqrt(1 - 4 * t * t)) / 2
    q := 2 * t - 2
    return (_math.sqrt(1 - q * q) + 1) / 2

func back_in_out(t):
    t = clamp01(t)
    c2 := 1.70158 * 1.525
    if t < 0.5:
        return (4 * t * t * ((c2 + 1) * 2 * t - c2)) / 2
    q := 2 * t - 2
    return (q * q * ((c2 + 1) * q + c2) + 2) / 2

# ---- courbes paramétrées : « spec » dict (pas de fermetures en ALEX) ----
# Équivalent CSS cubic-bezier(x1, y1, x2, y2) ; x1 et x2 doivent être dans [0, 1].
func bezier(x1, y1, x2, y2):
    if x1 < 0 or x1 > 1 or x2 < 0 or x2 > 1:
        raise("ArgumentError", "ui.animation.easing.bezier() : x1 et x2 doivent être dans [0, 1]")
    return {"kind": "bezier", "x1": x1 + 0.0, "y1": y1 + 0.0, "x2": x2 + 0.0, "y2": y2 + 0.0}

# Escalier en n marches. jump : "end" (défaut), "start", "both" ou "none" (comme CSS steps()).
func steps(n, jump="end"):
    if type(n) != "int" or n < 1:
        raise("ArgumentError", "ui.animation.easing.steps() : n doit être un int >= 1")
    if jump != "end" and jump != "start" and jump != "both" and jump != "none":
        raise("ArgumentError", "ui.animation.easing.steps() : jump invalide")
    return {"kind": "steps", "n": n, "jump": jump}

func _bez(a, b, c, s):
    # polynôme de Bézier à un axe, points de contrôle 0, a, b, 1
    u := 1 - s
    return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s

func _bez_slope(a, b, s):
    u := 1 - s
    return 3 * u * u * a + 6 * u * s * (b - a) + 3 * s * s * (1 - b)

func _bezier_eval(spec, t):
    if t <= 0:
        return 0
    if t >= 1:
        return 1
    x1 := spec["x1"]
    x2 := spec["x2"]
    # Newton-Raphson, repli par bissection (robuste pour les pentes quasi nulles)
    s := t
    i := 0
    while i < 6:
        err := _bez(x1, x2, 0, s) - t
        if err < 0.0000001 and err > -0.0000001:
            return _bez(spec["y1"], spec["y2"], 0, s)
        d := _bez_slope(x1, x2, s)
        if d < 0.000001:
            i = 99
        else:
            s = s - err / d
            i += 1
    lo := 0.0
    hi := 1.0
    s = t
    i = 0
    while i < 40:
        x := _bez(x1, x2, 0, s)
        if x < t:
            lo = s
        else:
            hi = s
        s = (lo + hi) / 2
        i += 1
    return _bez(spec["y1"], spec["y2"], 0, s)

func _steps_eval(spec, t):
    # Même définition que CSS steps() : jump-end / jump-start / jump-both / jump-none.
    n := spec["n"]
    t = clamp01(t)
    jump := spec["jump"]
    k := _math.floor(t * n)
    if jump == "start" or jump == "both":
        k += 1
    if t >= 1:
        k = n
        if jump == "both":
            k = n + 1
    if jump == "none":
        if n < 2:
            return clamp01(t)
        return clamp01(k / (n - 1))
    count := n
    if jump == "both":
        count = n + 1
    if k > count:
        k = count
    return k / count

func resolve(name):
    if name == null:
        name = "ease_out"
    if name == "linear":
        return linear
    if name == "ease_in":
        return ease_in
    if name == "ease_out":
        return ease_out
    if name == "ease_in_out":
        return ease_in_out
    if name == "smoothstep":
        return smoothstep
    if name == "smootherstep":
        return smootherstep
    if name == "cubic_in":
        return cubic_in
    if name == "cubic_out":
        return cubic_out
    if name == "cubic_in_out":
        return cubic_in_out
    if name == "quart_in":
        return quart_in
    if name == "quart_out":
        return quart_out
    if name == "quart_in_out":
        return quart_in_out
    if name == "quint_in":
        return quint_in
    if name == "quint_out":
        return quint_out
    if name == "quint_in_out":
        return quint_in_out
    if name == "sine_in":
        return sine_in
    if name == "sine_out":
        return sine_out
    if name == "sine_in_out":
        return sine_in_out
    if name == "expo_in":
        return expo_in
    if name == "expo_out":
        return expo_out
    if name == "expo_in_out":
        return expo_in_out
    if name == "back_in":
        return back_in
    if name == "back_out":
        return back_out
    if name == "bounce_in":
        return bounce_in
    if name == "bounce_out":
        return bounce_out
    if name == "bounce_in_out":
        return bounce_in_out
    if name == "elastic_in":
        return elastic_in
    if name == "elastic_out":
        return elastic_out
    if name == "elastic_in_out":
        return elastic_in_out
    if name == "circ_in":
        return circ_in
    if name == "circ_out":
        return circ_out
    if name == "circ_in_out":
        return circ_in_out
    if name == "back_in_out":
        return back_in_out
    raise("ArgumentError", "ui.animation.easing.resolve() : easing inconnue")

# Évalue une courbe : nom (str), fonction f(t), ou spec dict (bezier / steps).
# Les courbes de type back/elastic peuvent dépasser [0, 1] : c'est voulu (rebond / ressort).
func evaluate(spec, t):
    if spec == null:
        spec = "ease_out"
    ty := type(spec)
    if ty == "str":
        return resolve(spec)(t)
    if ty == "function":
        return spec(t)
    if ty == "dict":
        k := spec["kind"]
        if k == "bezier":
            return _bezier_eval(spec, t)
        if k == "steps":
            return _steps_eval(spec, t)
    raise("TypeError", "ui.animation.easing.evaluate() : easing invalide (nom, fonction ou bezier()/steps())")

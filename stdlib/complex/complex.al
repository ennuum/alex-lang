use math
from core use len, is_int, is_float
from collections use append

# ALEX STANDARD LIBRARY - complex
# Nombres complexes et fonctions élémentaires complexes. Pure ALEX, aucune dépendance native.
#
#   use complex
#   z := complex.new(3, 4)             # 3 + 4i
#   w := complex.mul(z, complex.I)     # -4 + 3i
#   print(complex.abs(z))              # 5.0
#   print(complex.to_string(complex.exp(complex.new(0, complex.PI))))
#
# REPRÉSENTATION
#   Un complexe est la liste [re, im] de deux flottants (représentation volontairement simple, stable et
#   directement sérialisable). Le langage ne surcharge pas les opérateurs : on utilise des fonctions libres
#   (add, mul, ...). Toutes les fonctions RENVOIENT une nouvelle liste et ne modifient jamais leurs arguments ;
#   les constantes ZERO, ONE et I ne doivent donc jamais être modifiées en place.
#   Les arguments « réels » (int ou float) sont acceptés partout : complex.add(z, 2) est valide.
#
# CONVENTIONS
#   - Branche principale : arg(z) dans ]-pi, pi], ln, sqrt, pow et les fonctions inverses suivent les mêmes
#     conventions que cmath (Python) et que la norme C99 hors des coupures.
#   - Les coupures sont traitées avec continuité par le haut sur l'axe réel (Im = +0).
#   - Erreurs : division par zéro -> ZeroDivisionError ; ln(0) -> ValueError ; argument non numérique -> TypeError.

const PI := 3.14159265358979323846
const ZERO := [0.0, 0.0]
const ONE := [1.0, 0.0]
const I := [0.0, 1.0]

# Convertit un réel (int/float) en complexe ; vérifie qu'une liste est bien un complexe.
func _c(z):
    if is_int(z) or is_float(z):
        return [z * 1.0, 0.0]
    if len(z) == 2:
        return z
    raise("TypeError", "complex : [re, im] ou nombre réel attendu")

# --- Construction et accès ---

# Complexe re + im*i.
func new(re_part, im_part=0.0):
    return [re_part * 1.0, im_part * 1.0]

# Complexe de module r et d'argument theta.
func from_polar(r, theta):
    return [r * math.cos(theta), r * math.sin(theta)]

func re(z):
    return _c(z)[0]

func im(z):
    return _c(z)[1]

# Vrai si z est une liste [re, im] de deux nombres.
func is_complex(z):
    if is_int(z) or is_float(z):
        return false
    return len(z) == 2 and (is_int(z[0]) or is_float(z[0])) and (is_int(z[1]) or is_float(z[1]))

# --- Opérations de base ---

func add(a, b):
    x := _c(a)
    y := _c(b)
    return [x[0] + y[0], x[1] + y[1]]

func sub(a, b):
    x := _c(a)
    y := _c(b)
    return [x[0] - y[0], x[1] - y[1]]

func mul(a, b):
    x := _c(a)
    y := _c(b)
    return [x[0] * y[0] - x[1] * y[1], x[0] * y[1] + x[1] * y[0]]

# Division par l'algorithme de Smith : évite les dépassements intermédiaires.
func div(a, b):
    x := _c(a)
    y := _c(b)
    c := y[0]
    d := y[1]
    if c == 0.0 and d == 0.0:
        raise("ZeroDivisionError", "complex.div : division par zéro")
    if math.abs(c) >= math.abs(d):
        r := d / c
        den := c + d * r
        return [(x[0] + x[1] * r) / den, (x[1] - x[0] * r) / den]
    r := c / d
    den := c * r + d
    return [(x[0] * r + x[1]) / den, (x[1] * r - x[0]) / den]

func neg(z):
    x := _c(z)
    return [0.0 - x[0], 0.0 - x[1]]

func conj(z):
    x := _c(z)
    return [x[0], 0.0 - x[1]]

# Produit par un réel.
func scale(z, k):
    x := _c(z)
    return [x[0] * k, x[1] * k]

# Inverse 1/z.
func inv(z):
    return div(ONE, z)

# Module |z| (sans dépassement intermédiaire).
func abs(z):
    x := _c(z)
    return math.hypot(x[0], x[1])

# Carré du module.
func abs2(z):
    x := _c(z)
    return x[0] * x[0] + x[1] * x[1]

# Argument principal, dans ]-pi, pi].
func arg(z):
    x := _c(z)
    return math.atan2(x[1], x[0])

# Forme polaire [module, argument].
func polar(z):
    return [abs(z), arg(z)]

func equals(a, b):
    x := _c(a)
    y := _c(b)
    return x[0] == y[0] and x[1] == y[1]

# Égalité approchée : |a - b| <= max(rel * max(|a|, |b|), abs_tol).
func is_close(a, b, rel_tol=0.000000001, abs_tol=0.0):
    d := abs(sub(a, b))
    scale_ := math.max(abs(a), abs(b))
    return d <= math.max(rel_tol * scale_, abs_tol)

# --- Puissances, racines, exponentielle, logarithme ---

func exp(z):
    x := _c(z)
    e := math.exp(x[0])
    return [e * math.cos(x[1]), e * math.sin(x[1])]

# Logarithme népérien principal.
func ln(z):
    x := _c(z)
    if x[0] == 0.0 and x[1] == 0.0:
        raise("ValueError", "complex.ln : logarithme de zéro")
    return [math.ln(abs(x)), math.atan2(x[1], x[0])]

# Logarithme en base b (complexe ou réel), branche principale.
func log(z, base=null):
    if base == null:
        return ln(z)
    return div(ln(z), ln(base))

# Racine carrée principale (partie réelle >= 0), stable numériquement.
func sqrt(z):
    x := _c(z)
    a := x[0]
    b := x[1]
    if a == 0.0 and b == 0.0:
        return [0.0, 0.0]
    m := math.hypot(a, b)
    if a >= 0.0:
        t := math.sqrt((m + a) / 2.0)
        return [t, b / (2.0 * t)]
    t := math.sqrt((m - a) / 2.0)
    return [math.abs(b) / (2.0 * t), math.copysign(t, b)]

# Puissance entière par exponentiation rapide (n peut être négatif).
func pow_int(z, n):
    if not is_int(n):
        raise("TypeError", "complex.pow_int : exposant entier attendu")
    if n < 0:
        return inv(pow_int(z, 0 - n))
    result := [1.0, 0.0]
    base := _c(z)
    base = [base[0], base[1]]
    e := n
    while e > 0:
        if e % 2 == 1:
            result = mul(result, base)
        e = e // 2
        if e > 0:
            base = mul(base, base)
    return result

# Puissance quelconque z^w = exp(w * ln z), branche principale. 0^w vaut 0 pour Re(w) > 0, 1 pour w = 0.
func pow(z, w):
    if is_int(w):
        return pow_int(z, w)
    x := _c(z)
    y := _c(w)
    if x[0] == 0.0 and x[1] == 0.0:
        if y[0] == 0.0 and y[1] == 0.0:
            return [1.0, 0.0]
        if y[0] > 0.0:
            return [0.0, 0.0]
        raise("ZeroDivisionError", "complex.pow : 0 élevé à une puissance de partie réelle <= 0")
    return exp(mul(y, ln(x)))

# Les n racines n-ièmes de z (liste de n complexes, la première est la racine principale).
func nth_roots(z, n):
    if not is_int(n) or n < 1:
        raise("ValueError", "complex.nth_roots : n doit être un entier >= 1")
    x := _c(z)
    r := abs(x)
    theta := arg(x)
    out := []
    if r == 0.0:
        k := 0
        while k < n:
            append(out, [0.0, 0.0])
            k += 1
        return out
    rho := r ** (1.0 / n)
    k := 0
    while k < n:
        append(out, from_polar(rho, (theta + 2.0 * PI * k) / n))
        k += 1
    return out

# Les n racines n-ièmes de l'unité.
func roots_of_unity(n):
    return nth_roots(ONE, n)

# --- Trigonométrie et hyperbolique ---

func sin(z):
    x := _c(z)
    return [math.sin(x[0]) * math.cosh(x[1]), math.cos(x[0]) * math.sinh(x[1])]

func cos(z):
    x := _c(z)
    return [math.cos(x[0]) * math.cosh(x[1]), 0.0 - math.sin(x[0]) * math.sinh(x[1])]

func tan(z):
    return div(sin(z), cos(z))

func sinh(z):
    x := _c(z)
    return [math.sinh(x[0]) * math.cos(x[1]), math.cosh(x[0]) * math.sin(x[1])]

func cosh(z):
    x := _c(z)
    return [math.cosh(x[0]) * math.cos(x[1]), math.sinh(x[0]) * math.sin(x[1])]

func tanh(z):
    return div(sinh(z), cosh(z))

# --- Fonctions inverses (branches principales) ---

func asinh(z):
    x := _c(z)
    return ln(add(x, sqrt(add(mul(x, x), ONE))))

func asin(z):
    # asin(z) = -i * asinh(i z)
    w := asinh(mul(I, _c(z)))
    return [w[1], 0.0 - w[0]]

func acos(z):
    s := asin(z)
    return [PI / 2.0 - s[0], 0.0 - s[1]]

func atanh(z):
    x := _c(z)
    return scale(sub(ln(add(ONE, x)), ln(sub(ONE, x))), 0.5)

func atan(z):
    # atan(z) = -i * atanh(i z)
    w := atanh(mul(I, _c(z)))
    return [w[1], 0.0 - w[0]]

func acosh(z):
    x := _c(z)
    return ln(add(x, mul(sqrt(add(x, ONE)), sqrt(sub(x, ONE)))))

# --- Agrégats ---

# Somme d'une liste de complexes.
func sum(items):
    acc := [0.0, 0.0]
    for z in items:
        acc = add(acc, z)
    return acc

# Produit d'une liste de complexes.
func prod(items):
    acc := [1.0, 0.0]
    for z in items:
        acc = mul(acc, z)
    return acc

# --- Affichage ---

# Représentation « a+bi » (15 chiffres significatifs, comme print).
func to_string(z):
    x := _c(z)
    sign := "+"
    imag := x[1]
    if imag < 0.0:
        sign = "-"
        imag = 0.0 - imag
    return f"{x[0]}{sign}{imag}i"

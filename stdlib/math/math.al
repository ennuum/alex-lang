from core use to_int, is_int

# ALEX STANDARD LIBRARY - math
# Pure ALEX implementation.
#
# This module deliberately uses only ALEX language primitives and core
# conversion/type helpers. Native C++ acceleration can replace individual
# functions later without changing this public API.

const PI := 3.14159265358979323846
const E := 2.71828182845904523536
const TAU := 6.28318530717958647692
const HALF_PI := 1.57079632679489661923
const LN2 := 0.69314718055994530942
const LN10 := 2.30258509299404568402
const EPSILON := 0.000000000001

# Valeurs non finies (le langage n'a pas de littéral inf/nan : elles naissent d'un
# débordement flottant). Comme en IEEE 754 : NAN != NAN.
const INF := 10.0 ** 400
const NAN := INF - INF

# --- Constantes de la réduction d'argument et des noyaux trigonométriques ---
# Provenance : fdlibm (e_rem_pio2.c, k_sin.c, k_cos.c), domaine public.
# pi/2 = _PIO2_1 + _PIO2_2 + _PIO2_3 + _PIO2_3T (erreur < 1e-48). Chaque partie _PIO2_k
# tient sur 33 bits : n * _PIO2_k est donc exact en flottant tant que |n| < 2^20.
# Le langage n'ayant pas de notation exponentielle, les valeurs sont écrites en décimal pur.
const _INV_PIO2 := 0.636619772367581382433
const _PIO2_1 := 1.57079632673412561417
const _PIO2_2 := 0.0000000000607710050630396597660
const _PIO2_2T := 0.00000000000000000000202226624879595063154
const _PIO2_3 := 0.00000000000000000000202226624871116645580
const _PIO2_3T := 0.0000000000000000000000000000000847842766036889956997
const _S1 := -0.166666666666666324348
const _S2 := 0.00833333333332248946124
const _S3 := -0.000198412698298579493134
const _S4 := 0.00000275573137070700676789
const _S5 := -0.0000000250507602534068634195
const _S6 := 0.000000000158969099521155010221
const _C1 := 0.0416666666666666019037
const _C2 := -0.00138888888888741095749
const _C3 := 0.0000248015872894767294178
const _C4 := -0.000000275573143513906633035
const _C5 := 0.00000000208757232129817482790
const _C6 := -0.0000000000113596475577881948265

func abs(x):
    if x < 0:
        return 0 - x
    return x

func min(a, b):
    if a < b:
        return a
    return b

func max(a, b):
    if a > b:
        return a
    return b

func min3(a, b, c):
    return min(min(a, b), c)

func max3(a, b, c):
    return max(max(a, b), c)

func clamp(x, low, high):
    if x < low:
        return low
    if x > high:
        return high
    return x

func sign(x):
    if x < 0:
        return -1
    if x > 0:
        return 1
    return 0

func is_even(n: int) -> bool:
    return n % 2 == 0

func is_odd(n: int) -> bool:
    return n % 2 != 0

func gcd(a: int, b: int) -> int:
    a = to_int(abs(a))
    b = to_int(abs(b))
    while b != 0:
        r := a % b
        a = b
        b = r
    return a

func lcm(a: int, b: int) -> int:
    a = to_int(a)
    b = to_int(b)
    if a == 0 or b == 0:
        return 0
    return abs(a // gcd(a, b) * b)

func factorial(n):
    n = to_int(n)
    if n < 0 or n > 20:
        return null
    result := 1
    i := 2
    while i <= n:
        result = result * i
        i = i + 1
    return result

func fibonacci(n):
    n = to_int(n)
    if n < 0 or n > 92:
        return null
    if n == 0:
        return 0
    if n == 1:
        return 1
    a := 0
    b := 1
    i := 2
    while i <= n:
        c := a + b
        a = b
        b = c
        i = i + 1
    return b

func floor(x):
    if x != x or x >= 9223372036854775807.0 or x <= -9223372036854775807.0:
        return x
    i := to_int(x)
    if x < i:
        return i - 1
    return i

func ceil(x):
    if x != x or x >= 9223372036854775807.0 or x <= -9223372036854775807.0:
        return x
    i := to_int(x)
    if x > i:
        return i + 1
    return i

func trunc(x):
    if x != x or x >= 9223372036854775807.0 or x <= -9223372036854775807.0:
        return x
    return to_int(x)

func round(x):
    if x != x or x >= 9223372036854775807.0 or x <= -9223372036854775807.0:
        return x
    if x >= 0:
        return floor(x + 0.5)
    return ceil(x - 0.5)

func sqrt(x: float):
    if x < 0:
        return null
    if x == 0:
        return 0
    if x != x or x == INF:
        return x
    # Normalisation : x = m * 4^k avec m dans [1, 4), donc sqrt(x) = sqrt(m) * 2^k.
    m := x
    k := 0
    while m >= 4:
        m = m / 4
        k = k + 1
    while m < 1:
        m = m * 4
        k = k - 1
    guess := (1 + m) / 2
    i := 0
    while i < 8:
        guess = 0.5 * (guess + m / guess)
        i = i + 1
    while k > 0:
        guess = guess * 2
        k = k - 1
    while k < 0:
        guess = guess / 2
        k = k + 1
    return guess

func cbrt(x: float) -> float:
    if x != x or x == INF or x == 0 - INF:
        return x
    if x == 0:
        return 0
    sign_value := 1
    value := x
    if x < 0:
        sign_value = -1
        value = 0 - x
    # Normalisation : value = m * 8^k avec m dans [1, 8), donc cbrt(value) = cbrt(m) * 2^k.
    m := value
    k := 0
    while m >= 8:
        m = m / 8
        k = k + 1
    while m < 1:
        m = m * 8
        k = k - 1
    guess := (1 + m) / 2
    i := 0
    while i < 12:
        guess = (2 * guess + m / (guess * guess)) / 3
        i = i + 1
    while k > 0:
        guess = guess * 2
        k = k - 1
    while k < 0:
        guess = guess / 2
        k = k + 1
    return sign_value * guess

# 2^n exact pour un entier n dans [-1000, 1000] (usage interne de ldexp).
func _pow2(n):
    m := n
    if n < 0:
        m = 0 - n
    result := 1.0
    factor := 2.0
    while m > 0:
        if m % 2 == 1:
            result = result * factor
        m = m // 2
        if m > 0:
            factor = factor * factor
    if n < 0:
        return 1.0 / result
    return result

# x * 2^i, calculé par blocs pour éviter les débordements intermédiaires.
func ldexp(x, i):
    if x != x or x == INF or x == 0 - INF or x == 0:
        return x * 1.0
    e := to_int(i)
    result := x * 1.0
    while e > 1000:
        result = result * _pow2(1000)
        e = e - 1000
        if result == INF or result == 0 - INF:
            return result
    while e < -1000:
        result = result * _pow2(-1000)
        e = e + 1000
        if result == 0:
            return result
    return result * _pow2(e)

func exp(x: float) -> float:
    if x == 0:
        return 1
    if x != x:
        return x
    # Au-delà de ces bornes le résultat déborde / sous-déborde : inutile de calculer.
    if x > 709.782712893384:
        return INF
    if x < -745.1332191019411:
        return 0.0

    # Réduction centrée : x = k * ln2 + r, k entier le plus proche, donc |r| <= ln2 / 2 (~0.347).
    # ln2 = ln2_hi + ln2_lo (constantes fdlibm) : k * ln2_hi est exact, l'erreur de réduction reste ~1e-16.
    k := round(x / LN2)
    r := (x - k * 0.693147180369123816490) - k * 0.000000000190821492927058770002

    # Série de Taylor de exp(r) évaluée par Horner, de l'intérieur vers l'extérieur
    # (|r| <= 0.347 : le terme r^17 / 17! est inférieur à 1e-20).
    total := 1.0
    i := 17
    while i >= 1:
        total = 1.0 + total * r / i
        i = i - 1

    if k == 0:
        return total
    # Mise à l'échelle exp(x) = total * 2^k en UNE multiplication exacte (ldexp) : pas de
    # boucle en O(k) ni de double arrondi lorsque le résultat est dénormalisé.
    return ldexp(total, k)

func ln(x: float):
    if x != x:
        return x
    if x <= 0:
        return null
    if x == INF:
        return x
    if x == 1:
        return 0

    # Reduce x by powers of 2, then use
    # ln(x) = 2 * (z + z^3/3 + z^5/5 + ...), z=(x-1)/(x+1).
    y := x
    k := 0
    while y > 2:
        y = y / 2
        k = k + 1
    while y < 0.5:
        y = y * 2
        k = k - 1

    z := (y - 1) / (y + 1)
    z2 := z * z
    term := z
    total := z
    n := 3
    while n <= 99:
        term = term * z2
        total = total + term / n
        n = n + 2

    return 2 * total + k * LN2


func pow(base, exponent):
    if exponent == 0:
        return 1
    if base == 0:
        if exponent < 0:
            return null
        return 0
    if exponent == to_int(exponent):
        n := to_int(exponent)
        negative := false
        if n < 0:
            negative = true
            n = 0 - n
        result := 1
        factor := base
        integer_base := is_int(base)
        while n > 0:
            if n % 2 == 1:
                # Garde exacte de débordement int64 (base entière) -> null.
                if integer_base and abs(factor) > 0 and abs(result) > 9223372036854775807 // abs(factor):
                    return null
                result = result * factor
            n = n // 2
            if n > 0:
                if integer_base and abs(factor) > 3037000499:
                    return null
                factor = factor * factor
        if negative:
            return 1 / result
        return result

    # For non-integer exponents use exp(y * ln(x)).
    if base < 0:
        return null
    return exp(exponent * ln(base))

func log(x, base):
    if x != x:
        return x
    if x <= 0 or base <= 0 or base == 1:
        return null
    return ln(x) / ln(base)

func log10(x: float):
    if x != x:
        return x
    if x <= 0:
        return null
    return ln(x) / LN10

# Réduit x modulo pi/2 : x = n * pi/2 + (y_hi + y_lo) avec |y_hi| <= pi/4.
# Renvoie [n % 4, y_hi, y_lo]. Précision pleine pour |x| < ~1,6e6 (n < 2^20) ; au-delà, une
# réduction préalable par TAU est appliquée (erreur absolue de l'ordre de |x| * 1e-16).
func _trig_reduce(x):
    t := x * 1.0
    if t > 1000000.0 or t < -1000000.0:
        t = t - floor(t / TAU) * TAU
    n := round(t * _INV_PIO2)
    fn := n * 1.0
    r := t - fn * _PIO2_1
    # Passes 2 et 3 : les parties suivantes de pi/2, avec récupération de l'erreur d'arrondi.
    t2 := r
    w := fn * _PIO2_2
    r = t2 - w
    w = fn * _PIO2_2T - ((t2 - r) - w)
    t2 = r
    w = fn * _PIO2_3
    r = t2 - w
    w = fn * _PIO2_3T - ((t2 - r) - w)
    y0 := r - w
    y1 := (r - y0) - w
    return [n % 4, y0, y1]

# sin(x + y) pour |x| <= pi/4, y = correction de queue (y << x).
func _sin_kernel(x, y):
    z := x * x
    v := z * x
    r := _S2 + z * (_S3 + z * (_S4 + z * (_S5 + z * _S6)))
    return x - ((z * (0.5 * y - v * r) - y) - v * _S1)

# cos(x + y) pour |x| <= pi/4.
func _cos_kernel(x, y):
    z := x * x
    r := z * (_C1 + z * (_C2 + z * (_C3 + z * (_C4 + z * (_C5 + z * _C6)))))
    if abs(x) < 0.3:
        return 1.0 - (0.5 * z - (z * r - x * y))
    # qx ~ z / 2 sur une grille de 1/256 : 1 - qx est exact et hz = z/2 - qx reste minuscule.
    qx := floor(z * 128.0) / 256.0
    hz := 0.5 * z - qx
    return (1.0 - qx) - (hz - (z * r - x * y))

func sin(x: float) -> float:
    if x != x:
        return x
    if x == INF or x == 0 - INF:
        return NAN
    p := _trig_reduce(x)
    q := p[0]
    if q == 0:
        return _sin_kernel(p[1], p[2])
    if q == 1:
        return _cos_kernel(p[1], p[2])
    if q == 2:
        return 0.0 - _sin_kernel(p[1], p[2])
    return 0.0 - _cos_kernel(p[1], p[2])

func cos(x: float) -> float:
    if x != x:
        return x
    if x == INF or x == 0 - INF:
        return NAN
    p := _trig_reduce(x)
    q := p[0]
    if q == 0:
        return _cos_kernel(p[1], p[2])
    if q == 1:
        return 0.0 - _sin_kernel(p[1], p[2])
    if q == 2:
        return 0.0 - _cos_kernel(p[1], p[2])
    return _sin_kernel(p[1], p[2])

# Renvoie null au voisinage d'un pôle (|cos(x)| < EPSILON), comme avant.
func tan(x: float):
    if x != x:
        return x
    if x == INF or x == 0 - INF:
        return NAN
    p := _trig_reduce(x)
    s := _sin_kernel(p[1], p[2])
    c := _cos_kernel(p[1], p[2])
    q := p[0]
    sx := s
    cx := c
    if q == 1:
        sx = c
        cx = 0.0 - s
    if q == 2:
        sx = 0.0 - s
        cx = 0.0 - c
    if q == 3:
        sx = 0.0 - c
        cx = s
    if abs(cx) < EPSILON:
        return null
    return sx / cx

func atan(x: float) -> float:
    if x == 0:
        return 0

    sign_value := 1
    y := x
    if x < 0:
        sign_value = -1
        y = 0 - x

    if y > 1:
        return sign_value * (HALF_PI - atan(1 / y))

    # atan(x) = x - x^3/3 + x^5/5 - ...
    # For x close to 1, transform with atan(x) = PI/4 + atan((x-1)/(x+1)).
    if y > 0.5:
        return sign_value * (0.78539816339744830962 + atan((y - 1) / (y + 1)))

    term := y
    total := y
    x2 := y * y
    n := 3
    subtract := true
    while n <= 99:
        term = term * x2
        if subtract:
            total = total - term / n
        else:
            total = total + term / n
        subtract = not subtract
        n = n + 2

    return sign_value * total

func atan2(y: float, x: float) -> float:
    if x > 0:
        return atan(y / x)
    if x < 0 and y >= 0:
        return atan(y / x) + PI
    if x < 0 and y < 0:
        return atan(y / x) - PI
    if x == 0 and y > 0:
        return HALF_PI
    if x == 0 and y < 0:
        return 0 - HALF_PI
    return 0

func asin(x: float):
    if x < -1 or x > 1:
        return null
    if x == 1:
        return HALF_PI
    if x == -1:
        return 0 - HALF_PI
    return atan(x / sqrt(1 - x * x))

func acos(x: float):
    if x < -1 or x > 1:
        return null
    return HALF_PI - asin(x)

func sinh(x: float) -> float:
    e1 := exp(x)
    e2 := exp(0 - x)
    return (e1 - e2) / 2

func cosh(x: float) -> float:
    e1 := exp(x)
    e2 := exp(0 - x)
    return (e1 + e2) / 2

func tanh(x: float) -> float:
    if x > 20:
        return 1.0
    if x < -20:
        return -1.0
    e1 := exp(x)
    e2 := exp(0 - x)
    return (e1 - e2) / (e1 + e2)

func radians(degrees: float) -> float:
    return degrees * PI / 180

func degrees(radians_value: float) -> float:
    return radians_value * 180 / PI

func is_close(a, b, tolerance = null):
    if tolerance == null:
        tolerance = EPSILON
    difference := abs(a - b)
    scale := max(1, max(abs(a), abs(b)))
    return difference <= tolerance * scale

func lerp(a, b, t):
    return a + (b - a) * t

func factorial_ratio(n, k):
    n = to_int(n)
    k = to_int(k)
    if n < 0 or k < 0 or k > n:
        return null
    if k == 0 or k == n:
        return 1
    if k > n - k:
        k = n - k
    result := 1
    i := 1
    while i <= k:
        num := n - k + i
        g := gcd(result, i)
        result = (result // g) * (num // (i // g))
        i = i + 1
    return result

func combinations(n, k):
    return factorial_ratio(n, k)

func permutations(n, k):
    n = to_int(n)
    k = to_int(k)
    if n < 0 or k < 0 or k > n:
        return null
    result := 1
    i := 0
    while i < k:
        if result > 9223372036854775807 // (n - i):
            return null
        result = result * (n - i)
        i = i + 1
    return result

func mean(a, b):
    return (a + b) / 2

func harmonic_mean(a, b):
    if a == 0 or b == 0:
        return 0
    return 2 * a * b / (a + b)

func geometric_mean(a, b):
    if a < 0 or b < 0:
        return null
    return sqrt(a * b)


# =============================================================================
# Priorité 1 : fonctions indispensables
# =============================================================================

# Prédicats sur les valeurs non finies.
func isnan(x: float) -> bool:
    return x != x

func isinf(x: float) -> bool:
    return x == INF or x == 0 - INF

func isfinite(x: float) -> bool:
    if x != x:
        return false
    return x != INF and x != 0 - INF

# Racine carrée entière : le plus grand r tel que r*r <= n. null si n < 0 ou non entier.
func isqrt(n):
    if not is_int(n):
        if n != n or n < 0 or n >= 9223372036854775807.0 or n != floor(n):
            return null
        n = to_int(n)
    if n < 0:
        return null
    if n < 2:
        return n
    r := to_int(sqrt(n))
    if r > 3037000499:
        r = 3037000499
    while r * r > n:
        r = r - 1
    while r < 3037000499 and (r + 1) * (r + 1) <= n:
        r = r + 1
    return r

func log2(x: float):
    if x != x:
        return x
    if x <= 0:
        return null
    if x == INF:
        return x
    y := x
    k := 0
    while y >= 2:
        y = y / 2
        k = k + 1
    while y < 1:
        y = y * 2
        k = k - 1
    if y == 1:
        return k + 0.0
    return k + ln(y) / LN2

# ln(1 + x) précis pour x proche de 0 (astuce de Kahan). null si x <= -1.
func log1p(x: float):
    if x != x:
        return x
    if x <= -1:
        return null
    if x == INF:
        return x
    u := 1 + x
    if u == 1:
        return x * 1.0
    return ln(u) * x / (u - 1)

# exp(x) - 1 précis pour x proche de 0.
func expm1(x: float) -> float:
    if x != x or x == INF:
        return x
    if x < -40:
        return -1.0
    if abs(x) < 1:
        term := x * 1.0
        total := term
        n := 2
        while n <= 30:
            term = term * x / n
            total = total + term
            n = n + 1
        return total
    return exp(x) - 1

func exp2(x: float) -> float:
    if x != x or x == INF:
        return x
    if x == 0 - INF:
        return 0.0
    if x >= 1024:
        return INF
    if x < -1075:
        return 0.0
    k := floor(x)
    f := x - k
    if f == 0:
        return ldexp(1.0, k)
    return ldexp(exp(f * LN2), k)

# Reste de la division tronquée (signe de x), exact. Renvoie null si x est infini ou y == 0.
func fmod(x, y):
    if x != x or y != y:
        return NAN
    if x == INF or x == 0 - INF or y == 0:
        return null
    if y == INF or y == 0 - INF:
        return x
    r := abs(x) % abs(y)
    if x < 0:
        if is_int(r):
            return 0 - r
        return r * -1.0
    return r

# Reste IEEE 754 : x - n*y avec n = entier le plus proche de x/y (égalité -> pair).
func remainder(x, y):
    if x != x or y != y:
        return NAN
    if x == INF or x == 0 - INF or y == 0:
        return null
    if y == INF or y == 0 - INF:
        return x
    ax := abs(x)
    ay := abs(y)
    r := ax % ay
    twice := r * 2
    if twice > ay:
        r = r - ay
    else:
        if twice == ay:
            q := (ax - r) / ay
            if q % 2 == 1:
                r = r - ay
    if x < 0:
        return 0 - r
    return r

# Partie fractionnaire et partie entière, sous la forme (fraction, entier), toutes deux float.
func modf(x):
    if x != x:
        return (x, x)
    if x == INF or x == 0 - INF:
        return (0.0, x)
    if abs(x) >= 4503599627370496.0:
        return (0.0, x * 1.0)
    ip := to_int(x) * 1.0
    return (x - ip, ip)

# |x| avec le signe de y (le zéro négatif est reconnu).
func copysign(x, y):
    magnitude := abs(x) * 1.0 + 0.0
    negative := y < 0
    if not negative and y == 0:
        negative = f"{y}" == "-0.0"
    if negative:
        return magnitude * -1.0
    return magnitude

# Décomposition x = m * 2^e avec 0.5 <= |m| < 1. Renvoie (m, e).
func frexp(x):
    if x != x or x == INF or x == 0 - INF or x == 0:
        return (x * 1.0, 0)
    m := abs(x) * 1.0
    e := 0
    while m >= 1:
        m = m / 2
        e = e + 1
    while m < 0.5:
        m = m * 2
        e = e - 1
    if x < 0:
        m = 0 - m
    return (m, e)

# =============================================================================
# Priorité 2 : calcul scientifique
# =============================================================================

# sqrt(x*x + y*y) sans débordement ni sous-dépassement intermédiaire.
func hypot(x: float, y: float) -> float:
    if x == INF or x == 0 - INF or y == INF or y == 0 - INF:
        return INF
    if x != x or y != y:
        return NAN
    a := abs(x) * 1.0
    b := abs(y) * 1.0
    big := max(a, b)
    if big == 0:
        return 0.0
    if big < 10.0 ** 150 and big > 10.0 ** -150:
        return sqrt(a * a + b * b)
    r := min(a, b) / big
    return big * sqrt(1 + r * r)

# Nombre d'éléments d'une liste ou d'un tuple (évite toute dépendance vers un autre module).
func _count(seq):
    n := 0
    for item in seq:
        n = n + 1
    return n

# Distance euclidienne entre deux points (listes ou tuples de même dimension). null si dimensions différentes.
func dist(p, q):
    n := _count(p)
    if n != _count(q):
        return null
    if n == 0:
        return 0.0
    diffs := []
    biggest := 0.0
    i := 0
    while i < n:
        d := abs(p[i] - q[i])
        if d == INF:
            return INF
        if d != d:
            return NAN
        __list_append(diffs, d)
        if d > biggest:
            biggest = d
        i = i + 1
    if biggest == 0:
        return 0.0
    total := 0.0
    if biggest < 10.0 ** 150 and biggest > 10.0 ** -150:
        # Plage sûre : somme directe des carrés (exacte pour les cas entiers usuels).
        for d2 in diffs:
            total = total + d2 * d2
        return sqrt(total)
    for d2 in diffs:
        ratio := d2 / biggest
        total = total + ratio * ratio
    return biggest * sqrt(total)

# Somme exacte (algorithme de Shewchuk, comme math.fsum de Python) : pas de perte par arrondis successifs.
func fsum(values):
    naive := 0.0
    non_finite := false
    for v in values:
        if v != v or v == INF or v == 0 - INF:
            non_finite = true
        naive = naive + v
    if non_finite:
        return naive
    partials := []
    for v in values:
        cur := v * 1.0
        kept := []
        for part in partials:
            big_one := cur
            small_one := part
            if abs(big_one) < abs(small_one):
                big_one = part
                small_one = cur
            s_hi := big_one + small_one
            s_lo := small_one - (s_hi - big_one)
            if s_lo != 0:
                __list_append(kept, s_lo)
            cur = s_hi
        __list_append(kept, cur)
        partials = kept
    n := _count(partials)
    if n == 0:
        return 0.0
    n = n - 1
    top := partials[n]
    err := 0.0
    while n > 0:
        prev_top := top
        n = n - 1
        next_part := partials[n]
        top = prev_top + next_part
        err = next_part - (top - prev_top)
        if err != 0:
            break
    # Correction d'arrondi vers le pair dans les cas d'égalité exacte.
    if n > 0 and ((err < 0 and partials[n - 1] < 0) or (err > 0 and partials[n - 1] > 0)):
        doubled := err * 2
        candidate := top + doubled
        if doubled == candidate - top:
            top = candidate
    return top

# Produit d'une séquence (1 si vide). Entiers : null si le résultat dépasse int64.
func prod(values):
    result := 1
    for v in values:
        if is_int(result) and is_int(v):
            if v != 0 and result != 0 and abs(result) > 9223372036854775807 // abs(v):
                return null
        result = result * v
    return result

# x*y + z avec un seul arrondi (produit exact par découpage de Veltkamp/Dekker, somme exacte par TwoSum).
func fma(x, y, z):
    fx := x * 1.0
    fy := y * 1.0
    fz := z * 1.0
    p := fx * fy
    limit := 10.0 ** 290
    if abs(fx) > limit or abs(fy) > limit or abs(fz) > limit or p == INF or p == 0 - INF or p != p or fz != fz:
        return p + fz
    cx := 134217729.0 * fx
    xh := cx - (cx - fx)
    xl := fx - xh
    cy := 134217729.0 * fy
    yh := cy - (cy - fy)
    yl := fy - yh
    p_err := ((xh * yh - p) + xh * yl + xl * yh) + xl * yl
    total := p + fz
    bb := total - p
    t_err := (p - (total - bb)) + (fz - bb)
    return total + (t_err + p_err)

# =============================================================================
# Priorité 3 : mathématiques avancées
# =============================================================================

# Fraction continue de erfc pour x >= 1.5 : erfc(x) = exp(-x^2) / (sqrt(pi) * K).
func _erfc_cf(x):
    t := x
    k := 120
    while k >= 1:
        t = x + (k / 2) / t
        k = k - 1
    return exp(0 - x * x) / (1.7724538509055159 * t)

func erf(x: float) -> float:
    if x != x:
        return x
    ax := abs(x)
    if ax == 0:
        return x * 1.0
    if ax >= 6:
        if x < 0:
            return -1.0
        return 1.0
    result := 0.0
    if ax > 2:
        result = 1.0 - _erfc_cf(ax)
    else:
        # erf(x) = 2/sqrt(pi) * exp(-x^2) * somme 2^n x^(2n+1) / (2n+1)!!  (termes tous positifs)
        term := ax
        total := ax
        n := 0
        while n < 300:
            term = term * 2 * ax * ax / (2 * n + 3)
            total = total + term
            n = n + 1
            if term < 0.00000000000000001 * total:
                break
        result = 1.1283791670955126 * exp(0 - ax * ax) * total
    if x < 0:
        return 0 - result
    return result

func erfc(x: float) -> float:
    if x != x:
        return x
    if x < 0:
        return 2.0 - erfc(0 - x)
    if x < 1.5:
        return 1.0 - erf(x)
    if x > 27:
        return 0.0
    return _erfc_cf(x)

# Somme de la série de Lanczos (g = 7, 9 coefficients) au point z1 = z - 1.
func _lanczos_sum(z1):
    a := 0.99999999999980993
    a = a + 676.5203681218851 / (z1 + 1)
    a = a - 1259.1392167224028 / (z1 + 2)
    a = a + 771.32342877765313 / (z1 + 3)
    a = a - 176.61502916214059 / (z1 + 4)
    a = a + 12.507343278686905 / (z1 + 5)
    a = a - 0.13857109526572012 / (z1 + 6)
    a = a + 0.0000099843695780195716 / (z1 + 7)
    a = a + 0.00000015056327351493116 / (z1 + 8)
    return a

# Fonction gamma. null aux pôles (0, -1, -2, ...) ; INF au-delà de 171.62.
func gamma(x: float):
    if x != x or x == INF:
        return x
    if x == 0 - INF:
        return null
    if x == floor(x):
        if x <= 0:
            return null
        if x > 171:
            return INF
        result := 1.0
        i := 2
        while i < x:
            result = result * i
            i = i + 1
        return result
    if x > 171.7:
        return INF
    if x < 0.5:
        # Formule des compléments : gamma(x) = pi / (sin(pi x) * gamma(1 - x)).
        s := sin(PI * fmod(x, 2.0))
        return PI / (s * gamma(1 - x))
    z1 := x - 1
    t := z1 + 7.5
    return 2.5066282746310002 * exp((z1 + 0.5) * ln(t) - t) * _lanczos_sum(z1)

# ln(|gamma(x)|). INF aux pôles.
func lgamma(x: float) -> float:
    if x != x:
        return x
    if x == INF or x == 0 - INF:
        return INF
    if x <= 0 and x == floor(x):
        return INF
    if x == 1 or x == 2:
        return 0.0
    if x < 0.5:
        s := abs(sin(PI * fmod(x, 2.0)))
        return ln(PI / s) - lgamma(1 - x)
    z1 := x - 1
    t := z1 + 7.5
    return 0.91893853320467274178 + (z1 + 0.5) * ln(t) - t + ln(_lanczos_sum(z1))

func acosh(x: float):
    if x != x or x == INF:
        return x
    if x < 1:
        return null
    if x > 100000000.0:
        return ln(x) + LN2
    t := x - 1
    return log1p(t + sqrt(2 * t + t * t))

func asinh(x: float) -> float:
    if x != x or x == INF or x == 0 - INF:
        return x
    ax := abs(x)
    r := 0.0
    if ax > 100000000.0:
        r = ln(ax) + LN2
    else:
        r = log1p(ax + ax * ax / (1 + sqrt(1 + ax * ax)))
    if x < 0:
        return 0 - r
    return r

# null si |x| >= 1.
func atanh(x: float):
    if x != x:
        return x
    ax := abs(x)
    if ax >= 1:
        return null
    r := 0.5 * log1p(2 * ax / (1 - ax))
    if x < 0:
        return 0 - r
    return r

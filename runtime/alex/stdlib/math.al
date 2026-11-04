from core use to_int, to_float
const PI := 3.14159265358979323846
const E := 2.71828182845904523536
const TAU := 6.28318530717958647692
const HALF_PI := 1.57079632679489661923
const LN2 := 0.69314718055994530942
const LN10 := 2.30258509299404568402
const EPSILON := 0.000000000001
const INF := __bits2f(9218868437227405312)
const NAN := INF - INF

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
const _HYPOT_BIG := __bits2f(6850974717710472879)
const _HYPOT_SMALL := __bits2f(2362753625475748981)

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

func lerp(a, b, t):
    return a + (b - a) * t

func is_even(n: int) -> bool:
    return n % 2 == 0

func is_odd(n: int) -> bool:
    return n % 2 != 0

func gcd(a: int, b: int) -> int:
    a = abs(a)
    b = abs(b)
    while b != 0:
        r := a % b
        a = b
        b = r
    return a

func lcm(a: int, b: int) -> int:
    if a == 0 or b == 0:
        return 0
    return abs(a // gcd(a, b) * b)

func factorial(n: int) -> int?:
    if n < 0 or n > 20:
        return null
    result := 1
    i := 2
    while i <= n:
        result = result * i
        i = i + 1
    return result

func fibonacci(n: int) -> int?:
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

func _finite(x: float, what: str):
    if x != x or x >= 9223372036854775807.0 or x <= -9223372036854775807.0:
        raise("ValueError", what + " : valeur non finie ou hors des entiers 64 bits")

func floor(x: float) -> int:
    _finite(x, "floor")
    i := to_int(x)
    if x < i:
        return i - 1
    return i

func ceil(x: float) -> int:
    _finite(x, "ceil")
    i := to_int(x)
    if x > i:
        return i + 1
    return i

func trunc(x: float) -> int:
    _finite(x, "trunc")
    return to_int(x)

func round(x: float) -> int:
    _finite(x, "round")
    if x >= 0:
        return floor(x + 0.5)
    return ceil(x - 0.5)

func sqrt(x: float) -> float:
    if x < 0:
        return NAN
    if x == 0:
        return 0.0
    if x != x or x == INF:
        return x
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
        return 0.0
    sign_value := 1
    value := x
    if x < 0:
        sign_value = -1
        value = 0 - x
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

func _pow2(n: int) -> float:
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

func ldexp(x: float, i: int) -> float:
    if x != x or x == INF or x == 0 - INF or x == 0:
        return x * 1.0
    e := i
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
        return 1.0
    if x != x:
        return x
    if x > 709.782712893384:
        return INF
    if x < -745.1332191019411:
        return 0.0
    k := round(x / LN2)
    r := (x - k * 0.693147180369123816490) - k * 0.000000000190821492927058770002
    total := 1.0
    i := 17
    while i >= 1:
        total = 1.0 + total * r / i
        i = i - 1
    if k == 0:
        return total
    return ldexp(total, k)

func ln(x: float) -> float:
    if x != x:
        return x
    if x <= 0:
        return NAN
    if x == INF:
        return x
    if x == 1:
        return 0.0
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

func pow(base: float, exponent: float) -> float:
    if exponent == 0:
        return 1.0
    if base == 0:
        if exponent < 0:
            return NAN
        return 0.0
    if exponent == to_int(exponent):
        n := to_int(exponent)
        negative := false
        if n < 0:
            negative = true
            n = 0 - n
        result := 1.0
        factor := base
        while n > 0:
            if n % 2 == 1:
                result = result * factor
            n = n // 2
            if n > 0:
                factor = factor * factor
        if negative:
            return 1 / result
        return result
    if base < 0:
        return NAN
    return exp(exponent * ln(base))

func log(x: float, base: float) -> float:
    if x != x:
        return x
    if x <= 0 or base <= 0 or base == 1:
        return NAN
    return ln(x) / ln(base)

func log10(x: float) -> float:
    if x != x:
        return x
    if x <= 0:
        return NAN
    return ln(x) / LN10

func log2(x: float) -> float:
    if x != x:
        return x
    if x <= 0:
        return NAN
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

func _trig_reduce(x: float) -> list[float]:
    t := x * 1.0
    if t > 1000000.0 or t < -1000000.0:
        t = t - to_float(floor(t / TAU)) * TAU
    n := round(t * _INV_PIO2)
    fn := n * 1.0
    r := t - fn * _PIO2_1
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
    return [to_float(n % 4), y0, y1]

func _sin_kernel(x: float, y: float) -> float:
    z := x * x
    v := z * x
    r := _S2 + z * (_S3 + z * (_S4 + z * (_S5 + z * _S6)))
    return x - ((z * (0.5 * y - v * r) - y) - v * _S1)

func _cos_kernel(x: float, y: float) -> float:
    z := x * x
    r := z * (_C1 + z * (_C2 + z * (_C3 + z * (_C4 + z * (_C5 + z * _C6)))))
    if abs(x) < 0.3:
        return 1.0 - (0.5 * z - (z * r - x * y))
    qx := floor(z * 128.0) / 256.0
    hz := 0.5 * z - qx
    return (1.0 - qx) - (hz - (z * r - x * y))

func sin(x: float) -> float:
    if x != x:
        return x
    if x == INF or x == 0 - INF:
        return NAN
    p := _trig_reduce(x)
    q := to_int(p[0])
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
    q := to_int(p[0])
    if q == 0:
        return _cos_kernel(p[1], p[2])
    if q == 1:
        return 0.0 - _sin_kernel(p[1], p[2])
    if q == 2:
        return 0.0 - _cos_kernel(p[1], p[2])
    return _sin_kernel(p[1], p[2])

func tan(x: float) -> float:
    if x != x:
        return x
    if x == INF or x == 0 - INF:
        return NAN
    p := _trig_reduce(x)
    s := _sin_kernel(p[1], p[2])
    c := _cos_kernel(p[1], p[2])
    q := to_int(p[0])
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
        return NAN
    return sx / cx

func atan(x: float) -> float:
    if x == 0:
        return 0.0
    sign_value := 1
    y := x
    if x < 0:
        sign_value = -1
        y = 0 - x
    if y > 1:
        return sign_value * (HALF_PI - atan(1 / y))
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
    return 0.0

func asin(x: float) -> float:
    if x < -1 or x > 1:
        return NAN
    if x == 1:
        return HALF_PI
    if x == -1:
        return 0 - HALF_PI
    return atan(x / sqrt(1 - x * x))

func acos(x: float) -> float:
    if x < -1 or x > 1:
        return NAN
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

func isnan(x: float) -> bool:
    return x != x

func isinf(x: float) -> bool:
    return x == INF or x == 0 - INF

func isfinite(x: float) -> bool:
    if x != x:
        return false
    return x != INF and x != 0 - INF

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
    if big < _HYPOT_BIG and big > _HYPOT_SMALL:
        return sqrt(a * a + b * b)
    r := min(a, b) / big
    return big * sqrt(1 + r * r)

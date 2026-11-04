use math
use array
use linalg
from core use len, is_int, is_float, is_list, is_function
from collections use append

# ALEX STANDARD LIBRARY - numeric
# Méthodes numériques : interpolation, polynômes, résolution d'équations, intégration. Pure ALEX.
#
#   use numeric
#   func f(x):
#       return math.cos(x) - x
#   print(numeric.brentq(f, 0.0, 1.0))                       # 0.7390851332151607
#   print(numeric.quad(math.sin, 0.0, numeric.PI)[0])        # 2.0
#   cs := numeric.CubicSpline([0.0, 1.0, 2.0, 3.0], [0.0, 1.0, 8.0, 27.0])
#   print(cs.eval(1.5), cs.derivative(1.5))
#   c := numeric.polyfit([0.0, 1.0, 2.0, 3.0], [1.0, 3.0, 7.0, 13.0], 2)   # coefficients, degré décroissant
#
# CONTENU
#   Interpolation  : interp, lagrange, CubicSpline (naturelle, "not-a-knot", serrée), PchipLike non fournie
#   Polynômes      : polyfit, polyval, polyder, polyint, polyadd, polymul, polyroots
#   Racines        : bisect, brentq, newton (avec ou sans dérivée), secant, fixed_point
#   Intégration    : quad (Gauss-Kronrod adaptative, bornes infinies), gauss_legendre, romberg,
#                    trapz, cumtrapz, simpson
#
# CONVENTIONS
#   - Une « fonction » est une fonction ALEX nommée f(x) ou f(x, p) (ou math.sin...). Le langage n'a pas de fermeture :
#     pour passer des paramètres, utilisez l'argument `args` (n'importe quelle valeur, souvent une liste) ;
#     la fonction est alors appelée f(x, args).
#   - Polynômes : liste/Array de coefficients par degrés DÉCROISSANTS ([a2, a1, a0] pour a2 x² + a1 x + a0), comme NumPy.
#   - Les racines complexes sont des listes [re, im] (compatibles avec le module complex).
#   - Erreurs : ValueError (arguments), ConvergenceError (non-convergence, intervalle sans changement de signe).
#   - quad renvoie [valeur, erreur estimée] et ne lève pas d'erreur si la tolérance n'est pas atteinte : vérifier l'erreur.

const PI := 3.14159265358979323846
const INF := 10.0 ** 400
const EPS := 0.0000000000000002220446049250313

# =====================================================================================================
# Utilitaires
# =====================================================================================================

func _abs(x):
    if x < 0:
        return 0.0 - x
    return x * 1.0

func _sign(x):
    if x > 0:
        return 1.0
    if x < 0:
        return -1.0
    return 0.0

func _call(f, x, args):
    if args == null:
        return f(x)
    return f(x, args)

func _floats(x, who):
    t := array.as_array(x)
    if len(t.shape) != 1:
        raise("ValueError", f"{who} : données 1-d attendues")
    out := []
    for v in t.data:
        append(out, v * 1.0)
    return out

func _is_scalar(x):
    return is_int(x) or is_float(x)

# =====================================================================================================
# Polynômes (coefficients par degrés décroissants)
# =====================================================================================================

# Évalue le polynôme en x (nombre, liste ou Array) par la méthode de Horner.
func polyval(coeffs, x):
    c := _floats(coeffs, "polyval")
    if _is_scalar(x):
        r := 0.0
        for a in c:
            r = r * x + a
        return r
    t := array.as_array(x)
    out := []
    for v in t.data:
        r := 0.0
        for a in c:
            r = r * v + a
        append(out, r)
    return array.wrap(_copy_int_list(t.shape), out)

func _copy_int_list(l):
    out := []
    for v in l:
        append(out, v)
    return out

# Ajustement polynomial de degré deg par moindres carrés. Renvoie les coefficients (Array, degré décroissant).
func polyfit(x, y, deg):
    xs := _floats(x, "polyfit")
    ys := _floats(y, "polyfit")
    n := len(xs)
    if len(ys) != n:
        raise("ValueError", "polyfit : x et y de longueurs différentes")
    if not is_int(deg) or deg < 0:
        raise("ValueError", "polyfit : degré entier >= 0 attendu")
    if n < deg + 1:
        raise("ValueError", "polyfit : pas assez de points pour ce degré")
    # centrage-mise à l'échelle pour conditionner la matrice de Vandermonde
    lo := array.min(xs)
    hi := array.max(xs)
    mid := 0.5 * (lo + hi)
    half := 0.5 * (hi - lo)
    if half == 0.0:
        half = 1.0
    rows := []
    for v in xs:
        u := (v - mid) / half
        row := []
        k := 0
        while k <= deg:
            append(row, 0.0)
            k = k + 1
        pw := 1.0
        k = deg
        while k >= 0:
            row[k] = pw
            pw = pw * u
            k = k - 1
        append(rows, row)
    V := array.from_list(rows)
    sol := linalg.lstsq(V, array.from_list(ys))[0]
    # retour aux coefficients en x : substitution u = (x - mid) / half par Horner sur polynômes
    cu := sol.data
    result := [cu[0]]
    i := 1
    while i < len(cu):
        # Horner : result = result * ((x - mid) / half) + cu[i]
        result = _padd(_pmul(result, [1.0 / half, 0.0 - mid / half]), [cu[i]])
        i = i + 1
    return array.wrap([len(result)], result)

func _strip(c):
    i := 0
    while i < len(c) - 1 and c[i] == 0.0:
        i = i + 1
    out := []
    while i < len(c):
        append(out, c[i])
        i = i + 1
    return out

# Somme de deux listes de coefficients SANS supprimer les zéros de tête (usage interne).
func _padd(x, y):
    n := len(x)
    if len(y) > n:
        n = len(y)
    out := []
    i := 0
    while i < n:
        u := 0.0
        v := 0.0
        if i >= n - len(x):
            u = x[i - (n - len(x))]
        if i >= n - len(y):
            v = y[i - (n - len(y))]
        append(out, u + v)
        i = i + 1
    return out

# Somme de deux polynômes ; les zéros de tête du résultat sont supprimés.
func polyadd(a, b):
    out := _strip(_padd(_floats(a, "polyadd"), _floats(b, "polyadd")))
    return array.wrap([len(out)], out)

# Produit de deux listes de coefficients SANS supprimer les zéros de tête (usage interne).
func _pmul(x, y):
    out := []
    i := 0
    while i < len(x) + len(y) - 1:
        append(out, 0.0)
        i = i + 1
    i = 0
    while i < len(x):
        j := 0
        while j < len(y):
            out[i + j] = out[i + j] + x[i] * y[j]
            j = j + 1
        i = i + 1
    return out

# Produit de deux polynômes ; les zéros de tête du résultat sont supprimés.
func polymul(a, b):
    x := _floats(a, "polymul")
    y := _floats(b, "polymul")
    if len(x) == 0 or len(y) == 0:
        raise("ValueError", "polymul : polynôme vide")
    out := _strip(_pmul(x, y))
    return array.wrap([len(out)], out)

# Dérivée d'ordre m du polynôme.
func polyder(coeffs, m=1):
    c := _floats(coeffs, "polyder")
    k := 0
    while k < m:
        n := len(c)
        if n <= 1:
            return array.wrap([1], [0.0])
        out := []
        i := 0
        while i < n - 1:
            append(out, c[i] * (n - 1 - i))
            i = i + 1
        c = out
        k = k + 1
    return array.wrap([len(c)], c)

# Primitive d'ordre m du polynôme, constante d'intégration k.
func polyint(coeffs, m=1, k=0.0):
    c := _floats(coeffs, "polyint")
    j := 0
    while j < m:
        n := len(c)
        out := []
        i := 0
        while i < n:
            append(out, c[i] / (n - i))
            i = i + 1
        append(out, k * 1.0)
        c = out
        j = j + 1
    return array.wrap([len(c)], c)

# Racines (réelles ou complexes) : liste de [re, im], via les valeurs propres de la matrice compagnon.
func polyroots(coeffs):
    c := _strip(_floats(coeffs, "polyroots"))
    if len(c) == 0:
        raise("ValueError", "polyroots : polynôme vide")
    zeros := 0
    while len(c) > 1 and c[len(c) - 1] == 0.0:
        c2 := []
        i := 0
        while i < len(c) - 1:
            append(c2, c[i])
            i = i + 1
        c = c2
        zeros = zeros + 1
    n := len(c) - 1
    roots := []
    if n >= 1:
        if n == 1:
            append(roots, [0.0 - c[1] / c[0], 0.0])
        else:
            M := array.zeros([n, n])
            j := 0
            while j < n:
                M.data[j] = 0.0 - c[j + 1] / c[0]
                j = j + 1
            i := 1
            while i < n:
                M.data[i * n + (i - 1)] = 1.0
                i = i + 1
            roots = linalg.eigvals(M)
    k := 0
    while k < zeros:
        append(roots, [0.0, 0.0])
        k = k + 1
    return roots

# =====================================================================================================
# Interpolation
# =====================================================================================================

# Indice i tel que xs[i] <= x < xs[i+1], borné à [0, n-2] (recherche dichotomique).
func _interval(xs, x):
    n := len(xs)
    lo := 0
    hi := n - 1
    while hi - lo > 1:
        mid := (lo + hi) // 2
        if xs[mid] <= x:
            lo = mid
        else:
            hi = mid
    return lo

func _check_increasing(xs, who):
    if len(xs) < 2:
        raise("ValueError", f"{who} : au moins 2 points")
    i := 1
    while i < len(xs):
        if not (xs[i] > xs[i - 1]):
            raise("ValueError", f"{who} : les abscisses doivent être strictement croissantes")
        i = i + 1

# Interpolation linéaire par morceaux (comme numpy.interp : valeurs constantes hors de [xp[0], xp[-1]]).
func interp(x, xp, fp, left=null, right=null):
    xs := _floats(xp, "interp")
    ys := _floats(fp, "interp")
    if len(xs) != len(ys):
        raise("ValueError", "interp : xp et fp de longueurs différentes")
    _check_increasing(xs, "interp")
    if _is_scalar(x):
        return _interp1(x, xs, ys, left, right)
    t := array.as_array(x)
    out := []
    for v in t.data:
        append(out, _interp1(v, xs, ys, left, right))
    return array.wrap(_copy_int_list(t.shape), out)

func _interp1(x, xs, ys, left, right):
    n := len(xs)
    if x < xs[0]:
        if left == null:
            return ys[0]
        return left * 1.0
    if x > xs[n - 1]:
        if right == null:
            return ys[n - 1]
        return right * 1.0
    if x == xs[n - 1]:
        return ys[n - 1]
    i := _interval(xs, x)
    t := (x - xs[i]) / (xs[i + 1] - xs[i])
    return ys[i] + t * (ys[i + 1] - ys[i])

# Polynôme d'interpolation de Lagrange (forme barycentrique, stable) évalué en x.
func lagrange(x, xp, fp):
    xs := _floats(xp, "lagrange")
    ys := _floats(fp, "lagrange")
    n := len(xs)
    if n != len(ys) or n < 1:
        raise("ValueError", "lagrange : xp et fp de même longueur >= 1 attendus")
    w := []
    i := 0
    while i < n:
        p := 1.0
        j := 0
        while j < n:
            if j != i:
                d := xs[i] - xs[j]
                if d == 0.0:
                    raise("ValueError", "lagrange : abscisses distinctes attendues")
                p = p * d
            j = j + 1
        append(w, 1.0 / p)
        i = i + 1
    if _is_scalar(x):
        return _bary(x, xs, ys, w)
    t := array.as_array(x)
    out := []
    for v in t.data:
        append(out, _bary(v, xs, ys, w))
    return array.wrap(_copy_int_list(t.shape), out)

func _bary(x, xs, ys, w):
    num := 0.0
    den := 0.0
    i := 0
    while i < len(xs):
        d := x - xs[i]
        if d == 0.0:
            return ys[i]
        c := w[i] / d
        num = num + c * ys[i]
        den = den + c
        i = i + 1
    return num / den

# Spline cubique d'interpolation. bc : "not-a-knot" (défaut, comme SciPy), "natural" ou "clamped"
# (pentes imposées aux extrémités par `slopes` = [pente gauche, pente droite]).
# Représentation par les dérivées secondes m aux nœuds ; évaluation, dérivées et intégrale exactes.
# Hors de [x0, xn] la spline prolonge le polynôme du dernier intervalle (extrapolation).
class CubicSpline:
    func init(x, y, bc="not-a-knot", slopes=null):
        xs := _floats(x, "CubicSpline")
        ys := _floats(y, "CubicSpline")
        if len(xs) != len(ys):
            raise("ValueError", "CubicSpline : x et y de longueurs différentes")
        _check_increasing(xs, "CubicSpline")
        self.x = xs
        self.y = ys
        self.m = _spline_moments(xs, ys, bc, slopes)

    func eval(t):
        if _is_scalar(t):
            return _spline_eval(self.x, self.y, self.m, t, 0)
        arr := array.as_array(t)
        out := []
        for v in arr.data:
            append(out, _spline_eval(self.x, self.y, self.m, v, 0))
        return array.wrap(_copy_int_list(arr.shape), out)

    func derivative(t, order=1):
        if order < 1 or order > 3:
            raise("ValueError", "CubicSpline.derivative : ordre 1, 2 ou 3")
        if _is_scalar(t):
            return _spline_eval(self.x, self.y, self.m, t, order)
        arr := array.as_array(t)
        out := []
        for v in arr.data:
            append(out, _spline_eval(self.x, self.y, self.m, v, order))
        return array.wrap(_copy_int_list(arr.shape), out)

    func integrate(a, b):
        return _spline_integral(self.x, self.y, self.m, a, b)

func _spline_moments(xs, ys, bc, slopes):
    n := len(xs)
    if n == 2:
        return [0.0, 0.0]
    h := []
    d := []
    i := 0
    while i < n - 1:
        append(h, xs[i + 1] - xs[i])
        append(d, (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]))
        i = i + 1
    if bc == "natural":
        if n == 3:
            return [0.0, 6.0 * (d[1] - d[0]) / (2.0 * (h[0] + h[1])), 0.0]
        sub := []
        dg := []
        sup := []
        rhs := []
        i = 1
        while i < n - 1:
            append(dg, 2.0 * (h[i - 1] + h[i]))
            append(rhs, 6.0 * (d[i] - d[i - 1]))
            if i > 1:
                append(sub, h[i - 1])
            if i < n - 2:
                append(sup, h[i])
            i = i + 1
        inner := linalg.solve_tridiagonal(sub, dg, sup, rhs).data
        return _wrap_ends(0.0, inner, 0.0)
    if bc == "clamped":
        if slopes == null or len(slopes) != 2:
            raise("ValueError", "CubicSpline : bc 'clamped' exige slopes=[pente gauche, pente droite]")
        sub := []
        dg := []
        sup := []
        rhs := []
        append(dg, 2.0 * h[0])
        append(sup, h[0])
        append(rhs, 6.0 * (d[0] - slopes[0]))
        i = 1
        while i < n - 1:
            append(sub, h[i - 1])
            append(dg, 2.0 * (h[i - 1] + h[i]))
            append(sup, h[i])
            append(rhs, 6.0 * (d[i] - d[i - 1]))
            i = i + 1
        append(sub, h[n - 2])
        append(dg, 2.0 * h[n - 2])
        append(rhs, 6.0 * (slopes[1] - d[n - 2]))
        return linalg.solve_tridiagonal(sub, dg, sup, rhs).data
    if bc != "not-a-knot":
        raise("ValueError", "CubicSpline : bc doit être 'not-a-knot', 'natural' ou 'clamped'")
    if n == 3:
        c := 2.0 * ((d[1] - d[0]) / (xs[2] - xs[0]))
        return [c, c, c]
    # not-a-knot : système dense n x n (continuité de la dérivée troisième en x1 et x_{n-2})
    A := array.zeros([n, n])
    rhs2 := []
    i = 0
    while i < n:
        append(rhs2, 0.0)
        i = i + 1
    A.data[0 * n + 0] = h[1]
    A.data[0 * n + 1] = 0.0 - (h[0] + h[1])
    A.data[0 * n + 2] = h[0]
    i = 1
    while i < n - 1:
        A.data[i * n + (i - 1)] = h[i - 1]
        A.data[i * n + i] = 2.0 * (h[i - 1] + h[i])
        A.data[i * n + (i + 1)] = h[i]
        rhs2[i] = 6.0 * (d[i] - d[i - 1])
        i = i + 1
    A.data[(n - 1) * n + (n - 3)] = h[n - 2]
    A.data[(n - 1) * n + (n - 2)] = 0.0 - (h[n - 3] + h[n - 2])
    A.data[(n - 1) * n + (n - 1)] = h[n - 3]
    return linalg.solve(A, array.from_list(rhs2)).data

func _wrap_ends(a, inner, b):
    out := [a]
    for v in inner:
        append(out, v)
    append(out, b)
    return out

# Évalue la spline (order=0) ou sa dérivée d'ordre 1, 2 ou 3 au point t.
func _spline_eval(xs, ys, m, t, order):
    i := _interval(xs, t)
    h := xs[i + 1] - xs[i]
    a := (xs[i + 1] - t)
    b := (t - xs[i])
    if order == 0:
        return m[i] * a * a * a / (6.0 * h) + m[i + 1] * b * b * b / (6.0 * h) + (ys[i] / h - m[i] * h / 6.0) * a + (ys[i + 1] / h - m[i + 1] * h / 6.0) * b
    if order == 1:
        return 0.0 - m[i] * a * a / (2.0 * h) + m[i + 1] * b * b / (2.0 * h) - (ys[i] / h - m[i] * h / 6.0) + (ys[i + 1] / h - m[i + 1] * h / 6.0)
    if order == 2:
        return m[i] * a / h + m[i + 1] * b / h
    return (m[i + 1] - m[i]) / h

# Primitive de la spline (intervalle i) en position t, relative à x_i.
func _piece_integral(xs, ys, m, i, t):
    h := xs[i + 1] - xs[i]
    b := t - xs[i]
    a := xs[i + 1] - t
    # ∫ de x_i à t de S ; S = m_i a³/(6h) + m_{i+1} b³/(6h) + c_i a + c_{i+1} b
    ci := ys[i] / h - m[i] * h / 6.0
    cj := ys[i + 1] / h - m[i + 1] * h / 6.0
    t1 := m[i] * (h * h * h * h - a * a * a * a) / (24.0 * h)
    t2 := m[i + 1] * b * b * b * b / (24.0 * h)
    t3 := ci * (h * h - a * a) / 2.0
    t4 := cj * b * b / 2.0
    return t1 + t2 + t3 + t4

func _spline_cum(xs, ys, m, t):
    n := len(xs)
    i := _interval(xs, t)
    total := 0.0
    k := 0
    while k < i:
        total = total + _piece_integral(xs, ys, m, k, xs[k + 1])
        k = k + 1
    return total + _piece_integral(xs, ys, m, i, t)

func _spline_integral(xs, ys, m, a, b):
    if a == b:
        return 0.0
    if b < a:
        return 0.0 - _spline_integral(xs, ys, m, b, a)
    return _spline_cum(xs, ys, m, b) - _spline_cum(xs, ys, m, a)

# =====================================================================================================
# Résolution d'équations f(x) = 0
# =====================================================================================================

# Bissection sur [a, b] (f(a) et f(b) de signes opposés). Renvoie la racine.
func bisect(f, a, b, tol=0.000000000001, maxiter=200, args=null):
    fa := _call(f, a, args)
    fb := _call(f, b, args)
    if fa == 0.0:
        return a * 1.0
    if fb == 0.0:
        return b * 1.0
    if _sign(fa) == _sign(fb):
        raise("ConvergenceError", "bisect : f(a) et f(b) doivent être de signes opposés")
    lo := a * 1.0
    hi := b * 1.0
    k := 0
    while k < maxiter:
        mid := 0.5 * (lo + hi)
        fm := _call(f, mid, args)
        if fm == 0.0 or 0.5 * _abs(hi - lo) < tol:
            return mid
        if _sign(fm) == _sign(fa):
            lo = mid
            fa = fm
        else:
            hi = mid
        k = k + 1
    raise("ConvergenceError", "bisect : nombre maximal d'itérations atteint")

# Méthode de Brent (racine encadrée, convergence superlinéaire, jamais pire que la bissection).
func brentq(f, a, b, tol=0.00000000000004, maxiter=200, args=null):
    fa := _call(f, a, args)
    fb := _call(f, b, args)
    if fa == 0.0:
        return a * 1.0
    if fb == 0.0:
        return b * 1.0
    if _sign(fa) == _sign(fb):
        raise("ConvergenceError", "brentq : f(a) et f(b) doivent être de signes opposés")
    xa := a * 1.0
    xb := b * 1.0
    xc := xa
    fc := fa
    d := xb - xa
    e := d
    k := 0
    while k < maxiter:
        if _sign(fb) == _sign(fc):
            xc = xa
            fc = fa
            d = xb - xa
            e = d
        if _abs(fc) < _abs(fb):
            xa = xb
            xb = xc
            xc = xa
            fa = fb
            fb = fc
            fc = fa
        tol1 := 2.0 * EPS * _abs(xb) + 0.5 * tol
        xm := 0.5 * (xc - xb)
        if _abs(xm) <= tol1 or fb == 0.0:
            return xb
        if _abs(e) >= tol1 and _abs(fa) > _abs(fb):
            s := fb / fa
            p := 0.0
            q := 0.0
            if xa == xc:
                p = 2.0 * xm * s
                q = 1.0 - s
            else:
                qq := fa / fc
                r := fb / fc
                p = s * (2.0 * xm * qq * (qq - r) - (xb - xa) * (r - 1.0))
                q = (qq - 1.0) * (r - 1.0) * (s - 1.0)
            if p > 0:
                q = 0.0 - q
            p = _abs(p)
            lim1 := 3.0 * xm * q - _abs(tol1 * q)
            lim2 := _abs(e * q)
            lim := lim1
            if lim2 < lim:
                lim = lim2
            if 2.0 * p < lim:
                e = d
                d = p / q
            else:
                d = xm
                e = d
        else:
            d = xm
            e = d
        xa = xb
        fa = fb
        if _abs(d) > tol1:
            xb = xb + d
        else:
            xb = xb + tol1 * _sign(xm)
        fb = _call(f, xb, args)
        k = k + 1
    raise("ConvergenceError", "brentq : nombre maximal d'itérations atteint")

# Newton-Raphson. Si fprime est null, méthode de la sécante (deux points de départ x0 et x0 * 1.0001 + 0.0001).
func newton(f, x0, fprime=null, tol=0.00000000000001, maxiter=100, args=null):
    if fprime == null:
        return secant(f, x0, x0 * 1.0001 + 0.0001, tol, maxiter, args)
    x := x0 * 1.0
    k := 0
    while k < maxiter:
        fx := _call(f, x, args)
        if fx == 0.0:
            return x
        dfx := _call(fprime, x, args)
        if dfx == 0.0:
            raise("ConvergenceError", "newton : dérivée nulle")
        step := fx / dfx
        x = x - step
        if x != x or _abs(x) > 10.0 ** 300:
            raise("ConvergenceError", "newton : l'itération diverge")
        if _abs(step) <= tol * (1.0 + _abs(x)):
            return x
        k = k + 1
    raise("ConvergenceError", "newton : nombre maximal d'itérations atteint")

func secant(f, x0, x1, tol=0.00000000000001, maxiter=100, args=null):
    p0 := x0 * 1.0
    p1 := x1 * 1.0
    q0 := _call(f, p0, args)
    q1 := _call(f, p1, args)
    k := 0
    while k < maxiter:
        if q1 == q0:
            if q1 == 0.0:
                return p1
            raise("ConvergenceError", "secant : pente nulle")
        p := p1 - q1 * (p1 - p0) / (q1 - q0)
        if p != p or _abs(p) > 10.0 ** 300:
            raise("ConvergenceError", "secant : l'itération diverge")
        if _abs(p - p1) <= tol * (1.0 + _abs(p)):
            return p
        p0 = p1
        q0 = q1
        p1 = p
        q1 = _call(f, p1, args)
        if q1 == 0.0:
            return p1
        k = k + 1
    raise("ConvergenceError", "secant : nombre maximal d'itérations atteint")

# Itération de point fixe x <- g(x) avec accélération d'Aitken (delta²). Convergence : |g(x) - x| <= tol (1 + |x|).
func fixed_point(g, x0, tol=0.0000000000001, maxiter=500, args=null):
    p0 := x0 * 1.0
    k := 0
    while k < maxiter:
        p1 := _call(g, p0, args)
        if p1 != p1 or _abs(p1) > 10.0 ** 300:
            raise("ConvergenceError", "fixed_point : l'itération diverge")
        if _abs(p1 - p0) <= tol * (1.0 + _abs(p0)):
            return p1
        p2 := _call(g, p1, args)
        if p2 != p2 or _abs(p2) > 10.0 ** 300:
            raise("ConvergenceError", "fixed_point : l'itération diverge")
        d := p2 - 2.0 * p1 + p0
        p := p2
        if d != 0.0:
            cand := p0 - (p1 - p0) * (p1 - p0) / d
            if cand == cand and _abs(cand) < 10.0 ** 300:
                p = cand
        p0 = p
        k = k + 1
    raise("ConvergenceError", "fixed_point : nombre maximal d'itérations atteint")

# =====================================================================================================
# Intégration
# =====================================================================================================

# Règle des trapèzes sur des échantillons y (abscisses x, ou pas régulier dx).
func trapz(y, x=null, dx=1.0):
    ys := _floats(y, "trapz")
    n := len(ys)
    if n < 2:
        return 0.0
    terms := []
    if x == null:
        i := 0
        while i < n - 1:
            append(terms, 0.5 * dx * (ys[i] + ys[i + 1]))
            i = i + 1
    else:
        xs := _floats(x, "trapz")
        if len(xs) != n:
            raise("ValueError", "trapz : x et y de longueurs différentes")
        i := 0
        while i < n - 1:
            append(terms, 0.5 * (xs[i + 1] - xs[i]) * (ys[i] + ys[i + 1]))
            i = i + 1
    return array.sum(array.wrap([len(terms)], terms))

# Intégrale cumulée par trapèzes (même longueur que y, première valeur 0).
func cumtrapz(y, x=null, dx=1.0):
    ys := _floats(y, "cumtrapz")
    n := len(ys)
    out := [0.0]
    acc := 0.0
    i := 0
    while i < n - 1:
        w := dx
        if x != null:
            xs := _floats(x, "cumtrapz")
            w = xs[i + 1] - xs[i]
        acc = acc + 0.5 * w * (ys[i] + ys[i + 1])
        append(out, acc)
        i = i + 1
    return array.wrap([n], out)

# Règle de Simpson composée sur des échantillons à pas régulier dx. Nombre pair d'échantillons : la dernière
# maille utilise la correction de Cartwright (5/12, 2/3, -1/12), comme SciPy.
func simpson(y, dx=1.0):
    ys := _floats(y, "simpson")
    n := len(ys)
    if n < 2:
        return 0.0
    if n == 2:
        return 0.5 * dx * (ys[0] + ys[1])
    m := n
    extra := 0.0
    if n % 2 == 0:
        m = n - 1
        extra = dx * (5.0 / 12.0 * ys[n - 1] + 2.0 / 3.0 * ys[n - 2] - 1.0 / 12.0 * ys[n - 3])
    terms := [ys[0] + ys[m - 1]]
    i := 1
    while i < m - 1:
        if i % 2 == 1:
            append(terms, 4.0 * ys[i])
        else:
            append(terms, 2.0 * ys[i])
        i = i + 1
    return dx / 3.0 * array.sum(array.wrap([len(terms)], terms)) + extra

# --- Gauss-Kronrod 15 points (7 points de Gauss) : constantes QUADPACK ---
const XGK := [0.9914553711208126392068546975263, 0.9491079123427585245261896840479, 0.8648644233597690727897127886409, 0.7415311855993944398638647732808, 0.5860872354676911302941448382587, 0.4058451513773971669066064120770, 0.2077849550078984676006894037732, 0.0]
const WGK := [0.02293532201052922496373200805897, 0.06309209262997855329070066318920, 0.1047900103222501838398763225415, 0.1406532597155259187451895905102, 0.1690047266392679028265834265986, 0.1903505780647854099132564024210, 0.2044329400752988924141619992346, 0.2094821410847278280129991748917]
const WG := [0.1294849661688696932706114326791, 0.2797053914892766679014677714238, 0.3818300505051189449503697754890, 0.4179591836734693877551020408163]

# Valeur de l'intégrande après changement de variable éventuel pour les bornes infinies.
# ctx = [f, args, mode, a0] ; mode 0 : direct ; 1 : [a0, +inf[ ; 2 : ]-inf, a0] ; 3 : ]-inf, +inf[.
func _qf(t, ctx):
    mode := ctx[2]
    if mode == 0:
        return _call(ctx[0], t, ctx[1])
    if mode == 1:
        u := 1.0 - t
        return _call(ctx[0], ctx[3] + t / u, ctx[1]) / (u * u)
    if mode == 2:
        u := 1.0 - t
        return _call(ctx[0], ctx[3] - t / u, ctx[1]) / (u * u)
    u := 1.0 - t * t
    return _call(ctx[0], t / u, ctx[1]) * (1.0 + t * t) / (u * u)

# Une application de G7/K15 sur [a, b] : renvoie [intégrale K15, erreur estimée].
func _gk15(ctx, a, b):
    c := 0.5 * (a + b)
    hl := 0.5 * (b - a)
    fc := _qf(c, ctx)
    resk := fc * WGK[7]
    resg := fc * WG[3]
    j := 0
    while j < 7:
        dx := hl * XGK[j]
        f1 := _qf(c - dx, ctx)
        f2 := _qf(c + dx, ctx)
        resk = resk + WGK[j] * (f1 + f2)
        if j % 2 == 1:
            resg = resg + WG[j // 2] * (f1 + f2)
        j = j + 1
    return [resk * hl, _abs((resk - resg) * hl)]

# Intégrale adaptative de f sur [a, b] (bornes infinies admises : utiliser INF / -INF).
# Renvoie [valeur, erreur estimée]. epsabs/epsrel : tolérances absolue et relative ; limit : nombre maximal de sous-intervalles.
func quad(f, a, b, args=null, epsabs=0.000000000001, epsrel=0.000000000001, limit=200):
    if a == b:
        return [0.0, 0.0]
    if b < a:
        r := quad(f, b, a, args, epsabs, epsrel, limit)
        return [0.0 - r[0], r[1]]
    ctx := [f, args, 0, 0.0]
    lo := a * 1.0
    hi := b * 1.0
    if a == 0.0 - INF and b == INF:
        ctx[2] = 3
        lo = -1.0
        hi = 1.0
    elif b == INF:
        ctx[2] = 1
        ctx[3] = a * 1.0
        lo = 0.0
        hi = 1.0
    elif a == 0.0 - INF:
        ctx[2] = 2
        ctx[3] = b * 1.0
        lo = 0.0
        hi = 1.0
    first := _gk15(ctx, lo, hi)
    ia := [lo]
    ib := [hi]
    iv := [first[0]]
    ie := [first[1]]
    total := first[0]
    err := first[1]
    k := 1
    while err > epsabs and err > epsrel * _abs(total) and k < limit:
        worst := 0
        i := 1
        while i < len(ie):
            if ie[i] > ie[worst]:
                worst = i
            i = i + 1
        m := 0.5 * (ia[worst] + ib[worst])
        left := _gk15(ctx, ia[worst], m)
        right := _gk15(ctx, m, ib[worst])
        old_b := ib[worst]
        ib[worst] = m
        iv[worst] = left[0]
        ie[worst] = left[1]
        append(ia, m)
        append(ib, old_b)
        append(iv, right[0])
        append(ie, right[1])
        total = array.sum(array.wrap([len(iv)], iv))
        err = array.sum(array.wrap([len(ie)], ie))
        k = k + 1
    return [total, err]

# Nœuds et poids de Gauss-Legendre à n points sur [-1, 1] : [liste des nœuds, liste des poids].
func gauss_legendre_nodes(n):
    if not is_int(n) or n < 1:
        raise("ValueError", "gauss_legendre : n entier >= 1 attendu")
    xs := []
    ws := []
    i := 0
    while i < n:
        append(xs, 0.0)
        append(ws, 0.0)
        i = i + 1
    m := (n + 1) // 2
    i = 0
    while i < m:
        z := math.cos(PI * (i + 0.75) / (n + 0.5))
        pp := 1.0
        it := 0
        while it < 100:
            p1 := 1.0
            p2 := 0.0
            j := 0
            while j < n:
                p3 := p2
                p2 = p1
                p1 = ((2.0 * j + 1.0) * z * p2 - j * p3) / (j + 1.0)
                j = j + 1
            pp = n * (z * p1 - p2) / (z * z - 1.0)
            z1 := z
            z = z1 - p1 / pp
            if _abs(z - z1) < 0.0000000000000003:
                break
            it = it + 1
        xs[i] = 0.0 - z
        xs[n - 1 - i] = z
        w := 2.0 / ((1.0 - z * z) * pp * pp)
        ws[i] = w
        ws[n - 1 - i] = w
        i = i + 1
    return [xs, ws]

# Quadrature de Gauss-Legendre à n points sur [a, b] (exacte pour les polynômes de degré <= 2n - 1).
func gauss_legendre(f, a, b, n=5, args=null):
    nw := gauss_legendre_nodes(n)
    c := 0.5 * (a + b)
    h := 0.5 * (b - a)
    terms := []
    i := 0
    while i < n:
        append(terms, nw[1][i] * _call(f, c + h * nw[0][i], args))
        i = i + 1
    return h * array.sum(array.wrap([n], terms))

# Intégration de Romberg (trapèzes + extrapolation de Richardson). Renvoie la valeur.
func romberg(f, a, b, tol=0.00000000000001, maxlevel=20, args=null):
    h := (b - a) * 1.0
    prev := [0.5 * h * (_call(f, a, args) + _call(f, b, args))]
    level := 1
    while level <= maxlevel:
        h = h / 2.0
        s := 0.0
        k := 1
        cnt := 2 ** (level - 1)
        while k <= cnt:
            s = s + _call(f, a + (2 * k - 1) * h, args)
            k = k + 1
        cur := [0.5 * prev[0] + h * s]
        j := 1
        while j <= level:
            pw := 4.0 ** j
            append(cur, (pw * cur[j - 1] - prev[j - 1]) / (pw - 1.0))
            j = j + 1
        if level >= 3 and _abs(cur[level] - prev[level - 1]) <= tol * (1.0 + _abs(cur[level])):
            return cur[level]
        prev = cur
        level = level + 1
    return prev[len(prev) - 1]

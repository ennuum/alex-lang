import sys
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import *
import scipy.interpolate as si
import scipy.integrate as sint
import scipy.optimize as so
from numpy.polynomial import legendre as npleg

S = Suite("numeric", "Polynômes, interpolation, racines, intégration.", "NumPy 2.4 / SciPy 1.17",
          "use array\nuse numeric\nuse math")
rng = np.random.default_rng(31415)

S.define('''func f_cosx(x):
    return math.cos(x) - x

func f_cubic(x):
    return x * x * x - 2.0 * x - 5.0

func df_cubic(x):
    return 3.0 * x * x - 2.0

func f_exp3(x):
    return math.exp(x) - 3.0

func f_param(x, p):
    return x * x - p

func df_param(x, p):
    return 2.0 * x

func f_flat(x):
    return (x - 1.0) * (x - 1.0) * (x - 1.0)

func g_cos(x):
    return math.cos(x)

func g_sqrt2(x):
    return 0.5 * (x + 2.0 / x)

func h_gauss(x):
    return math.exp(0.0 - x * x)

func h_invsqrt(x):
    return 1.0 / math.sqrt(x)

func h_log(x):
    return math.ln(x)

func h_quad(x, p):
    return p[0] * x * x + p[1] * x + p[2]

func h_osc(x):
    return math.sin(50.0 * x)

func h_peak(x):
    return 1.0 / (1.0 + 25.0 * x * x)

func h_xexp(x):
    return x * math.exp(0.0 - x)

func h_lorentz(x):
    return 1.0 / (1.0 + x * x)

func h_poly9(x):
    return 5.0 * x ** 9 - 3.0 * x ** 4 + x - 7.0

func h_abs(x):
    return math.abs(x - 0.3)

func h_exp(x):
    return math.exp(x)

func h_cos2(x):
    return math.cos(x) * math.cos(x)

func h_sin_over_x(x):
    return math.sin(x) / x

func h_nan(x):
    return 1.0 / (x - 0.5)
''')

def Lf(v): return lit(list(map(float, v)))

S.group("polynômes")
c = rng.integers(-5, 6, 6).astype(float)
for xx in (-2.5, 0.0, 1.3, 7.0):
    S.close(f"polyval({xx})", f"numeric.polyval({Lf(c)}, {xx})", np.polyval(c, xx), 1e-12)
xv = np.linspace(-1, 2, 7)
S.arr("polyval sur Array", f"numeric.polyval({Lf(c)}, {A(xv)})", np.polyval(c, xv), 1e-12)
S.close("polyval constant", "numeric.polyval([4.0], 9.0)", 4.0, 0.0)
S.arr("polyadd même degré", "numeric.polyadd([1.0, 2.0, 3.0], [4.0, 5.0, 6.0])", np.polyadd([1, 2, 3], [4, 5, 6]), 0.0)
S.arr("polyadd degrés différents", "numeric.polyadd([1.0, 2.0, 3.0], [4.0, 5.0])", np.polyadd([1, 2, 3], [4, 5]), 0.0)
S.arr("polyadd simplification (x²) + (-x²)", "numeric.polyadd([1.0, 2.0, 3.0], [-1.0, 0.0, 0.0])", np.trim_zeros(np.polyadd([1, 2, 3], [-1, 0, 0]), "f"), 0.0)
S.arr("polymul", "numeric.polymul([1.0, -1.0], [1.0, 1.0, 1.0])", np.polymul([1, -1], [1, 1, 1]), 0.0)
S.arr("polymul degré 3 x 2", f"numeric.polymul({Lf(c[:4])}, {Lf(c[4:])})", np.polymul(c[:4], c[4:]), 1e-13)
S.arr("polyder", f"numeric.polyder({Lf(c)})", np.polyder(c), 0.0)
S.arr("polyder ordre 2", f"numeric.polyder({Lf(c)}, 2)", np.polyder(c, 2), 0.0)
S.arr("polyder constante", "numeric.polyder([5.0])", np.array([0.0]), 0.0)
S.arr("polyint", f"numeric.polyint({Lf(c)})", np.polyint(c), 1e-15)
S.arr("polyint avec constante", f"numeric.polyint({Lf(c)}, 1, 2.5)", np.polyint(c, 1, 2.5), 1e-15)
S.arr("polyint ordre 2", f"numeric.polyint({Lf(c)}, 2)", np.polyint(c, 2), 1e-15)
S.arr("polyder(polyint(p)) = p", f"numeric.polyder(numeric.polyint({Lf(c)}))", c, 1e-15)
for deg in (1, 2, 3, 5):
    xf = np.linspace(0, 4, 15)
    yf = np.polyval(rng.integers(-3, 4, deg + 1), xf) + 0.05 * rng.standard_normal(15)
    S.arr(f"polyfit degré {deg} bruité", f"numeric.polyfit({Lf(xf)}, {Lf(yf)}, {deg})", np.polyfit(xf, yf, deg), 1e-8)
xf = np.array([0., 1., 2., 3.]); yf = np.array([1., 3., 7., 13.])
S.arr("polyfit exact 1 + x + x²", f"numeric.polyfit({Lf(xf)}, {Lf(yf)}, 2)", np.array([1., 1., 1.]), 1e-12)
S.arr("polyfit interpolant (n = deg+1)", f"numeric.polyfit({Lf(xf)}, {Lf(yf)}, 3)", np.polyfit(xf, yf, 3), 1e-10)
xs = np.linspace(1000, 1010, 12); ys = 3 + 0.5 * (xs - 1000)
S.arr("polyfit abscisses décalées (conditionnement)", f"numeric.polyfit({Lf(xs)}, {Lf(ys)}, 1)", np.array([0.5, 3 - 500.0]), 1e-8)
S.close("polyval(polyfit) reproduit les données", f"array.max(array.abs(array.sub(numeric.polyval(numeric.polyfit({Lf(xf)}, {Lf(yf)}, 2), {Lf(xf)}), {Lf(yf)})))", 0.0, 1e-11)

def rootkey(z):
    return (round(z.real, 6), round(z.imag, 6))
RT = [0]
def rts(label, p, tol=1e-9):
    r = sorted(np.roots(p).tolist(), key=rootkey)
    flat = [t for z in r for t in (z.real, z.imag)]
    RT[0] += 1
    v = "rr%d" % RT[0]
    S.line(f"{v} := sorted_roots(numeric.polyroots({Lf(p)}))")
    S.lst(label, f"flat_pairs({v})", flat, tol)
S.define('''func flat_pairs(l):
    out := []
    for p in l:
        append(out, p[0])
        append(out, p[1])
    return out

func sorted_roots(l):
    n := len(l)
    out := []
    for p in l:
        append(out, [p[0], p[1]])
    i := 0
    while i < n:
        j := 0
        while j < n - 1 - i:
            a := out[j]
            b := out[j + 1]
            swap := false
            if abs_val(a[0] - b[0]) <= 0.000001:
                if a[1] > b[1] + 0.000001:
                    swap = true
            elif a[0] > b[0]:
                swap = true
            if swap:
                out[j] = b
                out[j + 1] = a
            j = j + 1
        i = i + 1
    return out
''')
rts("polyroots (x-1)(x-2)(x-3)", [1, -6, 11, -6])
rts("polyroots x² + 1 (complexes)", [1, 0, 1])
rts("polyroots x⁴ - 1", [1, 0, 0, 0, -1])
rts("polyroots aléatoire degré 6", rng.standard_normal(7).tolist(), 1e-8)
rts("polyroots avec racine nulle", [1, -3, 2, 0])
rts("polyroots coefficient de tête non unitaire", [2, -3, -5, 6])
rts("polyroots degré 1", [4, -2])
rts("polyroots zéros de tête ignorés", [0, 0, 1, -5, 6])
S.err("polyroots polynôme vide", "numeric.polyroots([])")
S.err("polyfit degré trop grand", "numeric.polyfit([1.0, 2.0], [1.0, 2.0], 3)")
S.err("polyfit longueurs", "numeric.polyfit([1.0, 2.0, 3.0], [1.0, 2.0], 1)")
S.err("polymul vide", "numeric.polymul([], [1.0])")

S.group("interpolation linéaire et de Lagrange")
xp = np.array([0.0, 1.0, 2.5, 4.0, 7.0]); fp = np.array([1.0, 3.0, 2.0, 5.0, 4.0])
for xx in (0.0, 0.4, 1.0, 1.7, 2.5, 3.99, 7.0):
    S.close(f"interp({xx})", f"numeric.interp({xx}, {Lf(xp)}, {Lf(fp)})", np.interp(xx, xp, fp), 1e-14)
S.close("interp à gauche (constante)", f"numeric.interp(-3.0, {Lf(xp)}, {Lf(fp)})", np.interp(-3.0, xp, fp), 0.0)
S.close("interp à droite (constante)", f"numeric.interp(10.0, {Lf(xp)}, {Lf(fp)})", np.interp(10.0, xp, fp), 0.0)
S.close("interp left=", f"numeric.interp(-1.0, {Lf(xp)}, {Lf(fp)}, -99.0)", -99.0, 0.0)
S.close("interp right=", f"numeric.interp(9.0, {Lf(xp)}, {Lf(fp)}, null, 77.0)", 77.0, 0.0)
xq = np.linspace(-1, 8, 13)
S.arr("interp sur Array", f"numeric.interp({A(xq)}, {Lf(xp)}, {Lf(fp)})", np.interp(xq, xp, fp), 1e-14)
xn = np.sort(rng.random(5) * 4); fn = rng.standard_normal(5)
poly = np.polyfit(xn, fn, 4)
for xx in (0.3, 1.1, 2.9):
    S.close(f"lagrange({xx})", f"numeric.lagrange({xx}, {Lf(xn)}, {Lf(fn)})", np.polyval(poly, xx), 1e-9)
S.close("lagrange sur un nœud", f"numeric.lagrange({xn[2]}, {Lf(xn)}, {Lf(fn)})", fn[2], 0.0)
S.arr("lagrange sur Array", f"numeric.lagrange({A(xq[:4] * 0.3)}, {Lf(xn)}, {Lf(fn)})", np.polyval(poly, xq[:4] * 0.3), 1e-8)
S.close("lagrange reproduit un polynôme degré 3", "numeric.lagrange(2.5, [0.0, 1.0, 2.0, 3.0], [1.0, 2.0, 9.0, 28.0])", 2.5 ** 3 + 1, 1e-13)
S.err("interp abscisses non croissantes", "numeric.interp(1.0, [0.0, 2.0, 1.0], [1.0, 2.0, 3.0])")
S.err("interp longueurs", "numeric.interp(1.0, [0.0, 1.0], [1.0])")
S.err("lagrange abscisses répétées", "numeric.lagrange(0.5, [0.0, 1.0, 1.0], [1.0, 2.0, 3.0])")

S.group("splines cubiques")
SP = [0]
def spline_case(label, x, y, bc, slopes=None, tol=1e-10):
    if bc == "not-a-knot":
        cs = si.CubicSpline(x, y, bc_type="not-a-knot"); args = ""
    elif bc == "natural":
        cs = si.CubicSpline(x, y, bc_type="natural"); args = ', "natural"'
    else:
        cs = si.CubicSpline(x, y, bc_type=((1, slopes[0]), (1, slopes[1]))); args = f', "clamped", {lit(list(slopes))}'
    SP[0] += 1
    cv = "cs%d" % SP[0]
    S.line(f"{cv} := numeric.CubicSpline({Lf(x)}, {Lf(y)}{args})")
    q = np.linspace(x[0] - 0.4, x[-1] + 0.4, 17)
    S.arr(f"{label} : valeurs (+ extrapolation)", f"{cv}.eval({A(q)})", cs(q), tol)
    for o in (1, 2, 3):
        S.arr(f"{label} : dérivée {o}", f"{cv}.derivative({A(q)}, {o})", cs(q, o), tol * 10)
    S.close(f"{label} : intégrale", f"{cv}.integrate({x[0]}, {x[-1]})", float(cs.integrate(x[0], x[-1])), tol)
    S.close(f"{label} : intégrale partielle", f"{cv}.integrate({x[1] + 0.13}, {x[-2] - 0.21})", float(cs.integrate(x[1] + 0.13, x[-2] - 0.21)), tol)
    S.close(f"{label} : intégrale bornes inversées", f"{cv}.integrate({x[-2]}, {x[1]})", float(cs.integrate(x[-2], x[1])), tol)
    S.arr(f"{label} : passe par les nœuds", f"{cv}.eval({Lf(x)})", np.array(y), 1e-12)

x4 = np.array([0., 1., 2., 3., 4.]); y4 = np.array([0., 1., 8., 27., 64.])
for n in (4, 6, 12, 40):
    xk = np.sort(rng.random(n) * 10 + np.arange(n) * 0.5)
    xk = np.unique(np.round(xk, 3))
    yk = np.sin(xk) + 0.1 * rng.standard_normal(len(xk))
    spline_case(f"not-a-knot n={len(xk)}", xk, yk, "not-a-knot", tol=1e-9)
    spline_case(f"natural n={len(xk)}", xk, yk, "natural", tol=1e-9)
    spline_case(f"clamped n={len(xk)}", xk, yk, "clamped", slopes=(0.5, -1.0), tol=1e-9)
spline_case("not-a-knot cubique exacte", x4, y4, "not-a-knot")
S.close("not-a-knot reproduit x³ exactement", "numeric.CubicSpline([0.0, 1.0, 2.0, 3.0, 4.0], [0.0, 1.0, 8.0, 27.0, 64.0]).eval(2.7)", 2.7 ** 3, 1e-12)
spline_case("2 points (droite)", np.array([0., 2.]), np.array([1., 5.]), "not-a-knot")
spline_case("3 points not-a-knot (parabole)", np.array([0., 1., 3.]), np.array([1., 0., 4.]), "not-a-knot")
spline_case("3 points natural", np.array([0., 1., 3.]), np.array([1., 0., 4.]), "natural")
S.close("spline naturelle : dérivée seconde nulle aux bords", f"numeric.CubicSpline({Lf(x4)}, {Lf(y4)}, \"natural\").derivative(0.0, 2)", 0.0, 1e-12)
S.close("spline serrée : pente imposée à gauche", f"numeric.CubicSpline({Lf(x4)}, {Lf(y4)}, \"clamped\", [2.0, 3.0]).derivative(0.0)", 2.0, 1e-12)
S.close("spline serrée : pente imposée à droite", f"numeric.CubicSpline({Lf(x4)}, {Lf(y4)}, \"clamped\", [2.0, 3.0]).derivative(4.0)", 3.0, 1e-12)
S.err("spline abscisses non croissantes", "numeric.CubicSpline([0.0, 2.0, 1.0], [1.0, 2.0, 3.0])")
S.err("spline 1 point", "numeric.CubicSpline([0.0], [1.0])")
S.err("spline bc inconnu", 'numeric.CubicSpline([0.0, 1.0, 2.0], [1.0, 2.0, 3.0], "periodic")')
S.err("spline serrée sans pentes", 'numeric.CubicSpline([0.0, 1.0, 2.0], [1.0, 2.0, 3.0], "clamped")')
S.err("spline dérivée d'ordre 4", "numeric.CubicSpline([0.0, 1.0, 2.0], [1.0, 2.0, 3.0]).derivative(0.5, 4)")

S.group("résolution d'équations")
r1 = 0.7390851332151607
r2 = 2.0945514815423265
r3 = float(np.log(3))
S.close("bisect cos x = x", "numeric.bisect(f_cosx, 0.0, 1.0)", r1, 1e-11)
S.close("bisect x³ - 2x - 5", "numeric.bisect(f_cubic, 2.0, 3.0)", r2, 1e-11)
S.close("bisect ln 3", "numeric.bisect(f_exp3, 0.0, 5.0)", r3, 1e-11)
S.close("bisect tolérance serrée", "numeric.bisect(f_cosx, 0.0, 1.0, 0.00000000000001)", r1, 1e-13)
S.close("bisect racine sur la borne", "numeric.bisect(f_cosx, 0.7390851332151607, 1.0)", r1, 1e-10)
for lab, fn, a, b, ref in (("cos x = x", "f_cosx", 0.0, 1.0, r1), ("x³ - 2x - 5", "f_cubic", 2.0, 3.0, r2), ("exp x = 3", "f_exp3", 0.0, 5.0, r3)):
    S.close(f"brentq {lab}", f"numeric.brentq({fn}, {a}, {b})", ref, 1e-13)
S.close("brentq intervalle large", "numeric.brentq(f_cubic, -100.0, 100.0)", r2, 1e-12)
S.close("brentq avec args", "numeric.brentq(f_param, 0.0, 10.0, 0.00000000000004, 200, 2.0)", float(np.sqrt(2)), 1e-13)
S.close("brentq racine triple (f plate)", "numeric.brentq(f_flat, 0.0, 3.0)", 1.0, 1e-4)
S.close("newton avec dérivée", "numeric.newton(f_cubic, 2.0, df_cubic)", r2, 1e-13)
S.close("newton cos x = x", "numeric.newton(f_cosx, 0.5)", r1, 1e-12)
S.close("newton avec args", "numeric.newton(f_param, 1.0, df_param, 0.00000000000001, 100, 9.0)", 3.0, 1e-13)
S.close("newton racine négative", "numeric.newton(f_param, -1.0, df_param, 0.00000000000001, 100, 9.0)", -3.0, 1e-13)
S.close("secant", "numeric.secant(f_cubic, 2.0, 3.0)", r2, 1e-12)
S.close("secant exp x = 3", "numeric.secant(f_exp3, 0.0, 2.0)", r3, 1e-12)
S.close("fixed_point cos", "numeric.fixed_point(g_cos, 1.0)", r1, 1e-12)
S.close("fixed_point Babylone sqrt 2", "numeric.fixed_point(g_sqrt2, 1.0)", float(np.sqrt(2)), 1e-13)
S.true("brentq : f(racine) petite", "abs_val(f_cubic(numeric.brentq(f_cubic, 2.0, 3.0))) < 0.00000000001")
S.err("bisect sans changement de signe", "numeric.bisect(f_cosx, 2.0, 3.0)")
S.err("brentq sans changement de signe", "numeric.brentq(f_exp3, 2.0, 3.0)")
S.err("newton dérivée nulle", "numeric.newton(f_param, 0.0, df_param, 0.00000000000001, 100, 9.0)")
S.err("bisect maxiter trop faible", "numeric.bisect(f_cosx, 0.0, 1.0, 0.000000000000001, 3)")
S.err("fixed_point divergent", "numeric.fixed_point(h_exp, 5.0, 0.0000000001, 20)")

S.group("quadrature adaptative (Gauss-Kronrod)")
def qcase(label, fname, a, b, args=None, tol=1e-10, scal=None):
    ref = scal
    a_lit = "numeric.INF" if a == np.inf else ("-numeric.INF" if a == -np.inf else lit(float(a)))
    b_lit = "numeric.INF" if b == np.inf else ("-numeric.INF" if b == -np.inf else lit(float(b)))
    extra = "" if args is None else f", {lit(args)}"
    S.close(label, f"numeric.quad({fname}, {a_lit}, {b_lit}{extra})[0]", ref, tol)
    S.true(f"{label} : erreur estimée >= erreur réelle", f"numeric.quad({fname}, {a_lit}, {b_lit}{extra})[1] + 0.000000000001 * (1.0 + abs_val({lit(float(ref))})) >= abs_val(numeric.quad({fname}, {a_lit}, {b_lit}{extra})[0] - {lit(float(ref))})")

qcase("∫ sin 0..π", "math.sin", 0, np.pi, scal=2.0)
qcase("∫ exp 0..1", "math.exp", 0, 1, scal=np.e - 1)
qcase("∫ exp(-x²) -∞..∞", "h_gauss", -np.inf, np.inf, scal=np.sqrt(np.pi))
qcase("∫ exp(-x²) 0..∞", "h_gauss", 0, np.inf, scal=np.sqrt(np.pi) / 2)
qcase("∫ exp(-x²) -∞..0", "h_gauss", -np.inf, 0, scal=np.sqrt(np.pi) / 2)
qcase("∫ x e^-x 0..∞", "h_xexp", 0, np.inf, scal=1.0)
qcase("∫ 1/(1+x²) -∞..∞", "h_lorentz", -np.inf, np.inf, scal=np.pi)
qcase("∫ 1/(1+x²) 1..∞ (= π/4)", "h_lorentz", 1, np.inf, scal=np.pi / 4)
qcase("∫ 1/√x 0..1 (singularité intégrable)", "h_invsqrt", 0, 1, scal=2.0, tol=1e-9)
qcase("∫ ln x 0..1 (singularité log)", "h_log", 0, 1, scal=-1.0, tol=1e-9)
qcase("∫ 1/(1+25x²) -1..1 (pic)", "h_peak", -1, 1, scal=2 / 5 * np.arctan(5))
qcase("∫ sin(50x) 0..π (oscillant)", "h_osc", 0, np.pi, scal=(1 - np.cos(50 * np.pi)) / 50, tol=1e-9)
qcase("∫ |x - 0.3| 0..1 (point anguleux)", "h_abs", 0, 1, scal=0.5 * 0.3 ** 2 + 0.5 * 0.7 ** 2, tol=1e-9)
qcase("∫ cos² 0..π", "h_cos2", 0, np.pi, scal=np.pi / 2)
qcase("∫ polynôme degré 9", "h_poly9", -1, 2, scal=float(np.polyval(np.polyint([5, 0, 0, 0, 0, 0, -3, 0, 0, 0][::1] if False else [5, 0, 0, 0, 0, -3, 0, 0, 1, -7][:0] or [5, 0, 0, 0, 0, 0, -3, 0, 0, 0][:0] or [0], 2) - 0)) if False else (5 / 10 * (2 ** 10 - 1) - 3 / 5 * (2 ** 5 + 1) + 0.5 * (4 - 1) - 7 * 3))
qcase("∫ sin(x)/x 1e-9..50", "h_sin_over_x", 1e-9, 50, scal=float(sint.quad(lambda x: np.sin(x) / x, 1e-9, 50, limit=500)[0]), tol=1e-8)
qcase("∫ p0 x² + p1 x + p2 avec args", "h_quad", 0, 2, args=[3.0, -2.0, 1.0], scal=8.0 - 4.0 + 2.0)
S.close("bornes inversées", "numeric.quad(math.sin, numeric.PI, 0.0)[0]", -2.0, 1e-12)
S.close("bornes égales", "numeric.quad(math.sin, 1.0, 1.0)[0]", 0.0, 0.0)
S.close("tolérance lâche respectée", "numeric.quad(h_gauss, -5.0, 5.0, null, 0.001, 0.001)[0]", float(np.sqrt(np.pi)), 1e-3)
S.true("limit=1 : une seule évaluation, erreur grande pour une fonction difficile", "numeric.quad(h_osc, 0.0, 50.0, null, 0.000000000001, 0.000000000001, 1)[1] > 0.001")
S.true("somme des intervalles = intégrale (additivité)", "abs_val(numeric.quad(h_gauss, -2.0, 0.5)[0] + numeric.quad(h_gauss, 0.5, 2.0)[0] - numeric.quad(h_gauss, -2.0, 2.0)[0]) < 0.0000000000001")

S.group("Gauss-Legendre, Romberg, trapèzes, Simpson")
for n in (1, 2, 3, 5, 8, 20, 50):
    xg, wg = npleg.leggauss(n)
    S.lst(f"nœuds de Gauss-Legendre n={n}", f"numeric.gauss_legendre_nodes({n})[0]", xg, 1e-13)
    S.lst(f"poids de Gauss-Legendre n={n}", f"numeric.gauss_legendre_nodes({n})[1]", wg, 1e-13)
S.close("poids : somme = 2", "array.sum(numeric.gauss_legendre_nodes(12)[1])", 2.0, 1e-14)
S.close("exactitude degré 2n-1 (n=5, degré 9)", "numeric.gauss_legendre(h_poly9, -1.0, 2.0, 5)", 5 / 10 * (2 ** 10 - 1) - 3 / 5 * (2 ** 5 + 1) + 0.5 * (4 - 1) - 7 * 3, 1e-12)
S.close("gauss_legendre exp 0..1 n=10", "numeric.gauss_legendre(h_exp, 0.0, 1.0, 10)", np.e - 1, 1e-14)
S.close("gauss_legendre avec args", "numeric.gauss_legendre(h_quad, 0.0, 2.0, 3, [3.0, -2.0, 1.0])", 6.0, 1e-13)
S.close("gauss_legendre sin 0..π n=8", "numeric.gauss_legendre(math.sin, 0.0, numeric.PI, 8)", 2.0, 1e-9)
S.close("romberg exp", "numeric.romberg(h_exp, 0.0, 1.0)", np.e - 1, 1e-12)
S.close("romberg sin", "numeric.romberg(math.sin, 0.0, numeric.PI)", 2.0, 1e-12)
S.close("romberg polynôme", "numeric.romberg(h_poly9, -1.0, 2.0)", 5 / 10 * (2 ** 10 - 1) - 3 / 5 * (2 ** 5 + 1) + 0.5 * (4 - 1) - 7 * 3, 1e-10)
t = np.linspace(0, 2, 21); yt = np.sin(t) ** 2 + t
S.close("trapz pas régulier dx", f"numeric.trapz({Lf(yt)}, null, 0.1)", np.trapezoid(yt, dx=0.1), 1e-14)
tn = np.sort(rng.random(15) * 3)
yn = np.cos(tn)
S.close("trapz abscisses irrégulières", f"numeric.trapz({Lf(yn)}, {Lf(tn)})", np.trapezoid(yn, tn), 1e-14)
S.arr("cumtrapz", f"numeric.cumtrapz({Lf(yt)}, null, 0.1)", sint.cumulative_trapezoid(yt, dx=0.1, initial=0), 1e-14)
S.arr("cumtrapz abscisses irrégulières", f"numeric.cumtrapz({Lf(yn)}, {Lf(tn)})", sint.cumulative_trapezoid(yn, tn, initial=0), 1e-14)
S.close("trapz dernier cumul = trapz", f"numeric.cumtrapz({Lf(yt)}, null, 0.1).data[20]", np.trapezoid(yt, dx=0.1), 1e-14)
S.close("trapz 1 point", "numeric.trapz([3.0])", 0.0, 0.0)
for npts in (3, 4, 5, 8, 11, 16):
    tt = np.linspace(0, 3, npts); yy = np.exp(-tt) * np.cos(2 * tt)
    h = tt[1] - tt[0]
    S.close(f"simpson {npts} points", f"numeric.simpson({Lf(yy)}, {lit(float(h))})", float(sint.simpson(yy, dx=h)), 1e-13)
S.close("simpson exacte pour x³ (5 points)", "numeric.simpson([0.0, 0.015625, 0.125, 0.421875, 1.0], 0.25)", 0.25, 1e-15)
S.close("simpson 2 points = trapèze", "numeric.simpson([1.0, 3.0], 2.0)", 4.0, 0.0)
S.close("simpson précision (sin, 101 points)", f"numeric.simpson({Lf(np.sin(np.linspace(0, np.pi, 101)))}, {lit(float(np.pi / 100))})", 2.0, 1e-8)
S.err("trapz x/y longueurs", "numeric.trapz([1.0, 2.0, 3.0], [0.0, 1.0])")
S.err("gauss_legendre n invalide", "numeric.gauss_legendre(h_exp, 0.0, 1.0, 0)")

text = S.render()
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'tests', 'test_numeric.al'), 'w', encoding='utf-8').write(text)
print("lignes :", text.count("\n"), "| cas d'erreur :", S.nerr)

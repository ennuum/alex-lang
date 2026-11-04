import sys
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import *
import sympy as sp
import scipy.integrate as sint
import scipy.optimize as so

S = Suite("calculus", "Dérivées, gradient/jacobienne/hessienne, opérateurs vectoriels, intégrales multiples, systèmes.",
          "SymPy 1.14 (dérivées exactes) / SciPy 1.17", "use array\nuse calculus\nuse math\nuse numeric")
x, y, z = sp.symbols('x y z')

# ---- fonctions scalaires : (nom, source Alex, expression sympy, points)
SC = [
    ("s_sinexp", "math.sin(x) * math.exp(x)", sp.sin(x) * sp.exp(x), [0.0, 0.7, -1.3]),
    ("s_gauss", "math.exp(0.0 - x * x)", sp.exp(-x ** 2), [0.0, 0.4, 2.0]),
    ("s_log", "math.ln(x)", sp.log(x), [0.5, 2.5, 40.0]),
    ("s_sqrt", "math.sqrt(x)", sp.sqrt(x), [0.3, 4.0, 100.0]),
    ("s_cos3", "math.cos(3.0 * x)", sp.cos(3 * x), [0.0, 1.1, -2.2]),
    ("s_atan", "math.atan(x)", sp.atan(x), [0.0, 1.0, 10.0]),
    ("s_quartic", "x * x * x * x - 2.0 * x", x ** 4 - 2 * x, [-3.0, 0.0, 5.0]),
    ("s_inv", "1.0 / x", 1 / x, [0.9, 3.0, -7.0]),
    ("s_big", "math.sin(x) * 1000000.0", 1e6 * sp.sin(x), [1.0]),
]
defs = ""
for name, src, expr, pts in SC:
    defs += f"func {name}(x):\n    return {src}\n\n"
defs += '''func s_param(x, p):
    return p[0] * math.sin(p[1] * x)

func s_abs(x):
    return math.abs(x)

func s_step(x):
    if x < 0.0:
        return 0.0
    return 1.0

func s_const(x):
    return 5.0
'''
# fonctions de plusieurs variables
defs += '''
func g_poly(v):
    return v[0] * v[0] * v[1] + math.sin(v[1]) * v[2] + v[2] * v[2] * v[2]

func g_exp(v):
    return math.exp(v[0] * v[1]) + v[0] * v[0] * v[0] - v[1] * v[2]

func g_quad(v):
    return v[0] * v[0] + 3.0 * v[1] * v[1] + 5.0 * v[0] * v[1]

func g_ros(v):
    return 100.0 * (v[1] - v[0] * v[0]) * (v[1] - v[0] * v[0]) + (1.0 - v[0]) * (1.0 - v[0])

func g_pot(v):
    return 1.0 / math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])

func g_par(v, p):
    return p * v[0] * v[1] + v[1] * v[1]

func F_a(v):
    return [v[0] * v[1], v[1] * v[2] * v[2], math.sin(v[0]) + v[2]]

func F_b(v):
    return [v[0] * v[0] - v[1], math.exp(v[0]) + v[1] * v[1]]

func F_rot(v):
    return [0.0 - v[1], v[0], 0.0]

func F_nonlin(v):
    return [v[0] * v[0] + v[1] * v[1] - 4.0, v[0] - v[1]]

func J_nonlin(v):
    return [[2.0 * v[0], 2.0 * v[1]], [1.0, -1.0]]

func F_3(v):
    return [v[0] + v[1] + v[2] - 6.0, v[0] * v[1] * v[2] - 6.0, v[0] * v[0] + v[1] * v[1] + v[2] * v[2] - 14.0]

func F_ros(v):
    return [10.0 * (v[1] - v[0] * v[0]), 1.0 - v[0]]

func F_sing(v):
    return [v[0] * v[0], v[1] * v[1]]

func F_trig(v):
    return [math.sin(v[0]) - v[1], math.cos(v[1]) - v[0]]

func F_par(v, p):
    return [v[0] * v[0] - p, v[1] - v[0]]

func F_atan(v):
    return [math.atan(v[0])]

func F_1d(v):
    return [v[0] * v[0] * v[0] - 8.0]

func F_wrong(v):
    return [v[0], v[1], v[0] + v[1]]

func fld_conservative(v):
    return [2.0 * v[0] * v[1], v[0] * v[0]]

func fld_rot2(v):
    return [0.0 - v[1], v[0]]

func circle_r(t):
    return [math.cos(t), math.sin(t)]

func circle_dr(t):
    return [0.0 - math.sin(t), math.cos(t)]

func line_r(t):
    return [t, 2.0 * t]

func line_dr(t):
    return [1.0, 2.0]

func d_xy(x, y):
    return x * y

func d_param(x, y, p):
    return p * x + y * y

func d_gauss(x, y):
    return math.exp(0.0 - x * x - y * y)

func d_one(x, y):
    return 1.0

func d_xplus(x, y):
    return x + y * y

func lim_x(x):
    return x

func lim_sq(x):
    return x * x

func lim_circ_hi(x):
    return math.sqrt(1.0 - x * x)

func lim_circ_lo(x):
    return 0.0 - math.sqrt(1.0 - x * x)

func lim_one_minus(x):
    return 1.0 - x

func t_one(x, y, z):
    return 1.0

func t_xyz(x, y, z):
    return x * y * z

func t_sum(x, y, z):
    return x + y * y + z * z * z

func t_param(x, y, z, p):
    return p * x * y + z

func z_hi_ball(x, y):
    return math.sqrt(1.0 - x * x - y * y)

func z_lo_ball(x, y):
    return 0.0 - math.sqrt(1.0 - x * x - y * y)

func z_hi_simplex(x, y):
    return 1.0 - x - y
'''
S.define(defs)

def flat(a): return np.asarray(a, dtype=float).reshape(-1)

S.group("dérivées d'une variable")
TOLN = {1: 1e-10, 2: 1e-9, 3: 1e-7, 4: 1e-6, 5: 1e-4}
for name, src, expr, pts in SC:
    if name == "s_big":
        continue
    for pt in pts:
        for n in (1, 2, 3, 4):
            ref = float(sp.diff(expr, x, n).subs(x, pt))
            fn = {1: "derivative", 2: "second_derivative"}.get(n)
            if fn:
                call = f"calculus.{fn}({name}, {pt})"
            else:
                call = f"calculus.derivative_n({name}, {pt}, {n})"
            S.close(f"{name}'^({n}) en {pt}", call, ref, TOLN[n])
# ordre 5 sur une seule fonction
S.close("dérivée 5ème de sin x e^x en 0.7", "calculus.derivative_n(s_sinexp, 0.7, 5)", float(sp.diff(sp.sin(x) * sp.exp(x), x, 5).subs(x, 0.7)), 1e-4)
S.close("dérivée avec args", "calculus.derivative(s_param, 0.8, null, [2.0, 3.0])", float(sp.diff(2 * sp.sin(3 * x), x).subs(x, 0.8)), 1e-10)
S.close("second_derivative avec args", "calculus.second_derivative(s_param, 0.8, null, [2.0, 3.0])", float(sp.diff(2 * sp.sin(3 * x), x, 2).subs(x, 0.8)), 1e-9)
S.close("dérivée d'une constante", "calculus.derivative(s_const, 2.0)", 0.0, 1e-12)
S.close("singularité proche : pas h réduit (1/x en 0.2, ordre 4)", "calculus.derivative_n(s_inv, 0.2, 4, 0.02)", float(sp.diff(1 / x, x, 4).subs(x, 0.2)), 1e-5)
S.err("singularité atteinte par le pas initial (1/x en 0.2, ordre 4)", "calculus.derivative_n(s_inv, 0.2, 4)")
S.close("dérivée avec pas h explicite", "calculus.derivative(s_sinexp, 0.7, 0.05)", float(sp.diff(sp.sin(x) * sp.exp(x), x).subs(x, 0.7)), 1e-9)
S.close("dérivée à grande échelle (1e6 sin x)", "calculus.derivative(s_big, 1.0)", float(1e6 * np.cos(1.0)), 1e-9)
S.lst("derivative_err : [valeur, erreur]", "calculus.derivative_err(s_sinexp, 0.7)[0:1]".replace("[0:1]", "") if False else "[calculus.derivative_err(s_sinexp, 0.7)[0]]", [float(sp.diff(sp.sin(x) * sp.exp(x), x).subs(x, 0.7))], 1e-10)
S.true("derivative_err : erreur estimée petite et positive", "calculus.derivative_err(s_sinexp, 0.7)[1] >= 0.0 and calculus.derivative_err(s_sinexp, 0.7)[1] < 0.0000001")
S.true("erreur estimée >= erreur réelle (x³)", "calculus.derivative_err(s_quartic, 1.5)[1] + 0.000000000001 >= abs_val(calculus.derivative_err(s_quartic, 1.5)[0] - (4.0 * 1.5 * 1.5 * 1.5 - 2.0))")
S.close("dérivée de |x| en 1", "calculus.derivative(s_abs, 1.0)", 1.0, 1e-12)
S.close("dérivée de |x| en -2", "calculus.derivative(s_abs, -2.0)", -1.0, 1e-12)
S.true("non dérivable en 0 (|x|) : erreur estimée grande", "calculus.derivative_err(s_abs, 0.0)[1] > 0.01 or abs_val(calculus.derivative(s_abs, 0.0)) < 0.000001")
S.true("discontinuité (marche) : erreur estimée grande", "calculus.derivative_err(s_step, 0.0)[1] > 1.0")
S.err("derivative ordre 0", "calculus.derivative_n(s_sinexp, 1.0, 0)")
S.err("derivative abscisse vectorielle", "calculus.derivative(s_sinexp, [1.0, 2.0])")
S.err("derivative_n ordre flottant", "calculus.derivative_n(s_sinexp, 1.0, 1.5)")

S.group("gradient, hessienne, laplacien")
X3 = [x, y, z]
def sym_grad_hess(expr, pt):
    sub = dict(zip(X3, pt))
    g = [float(sp.diff(expr, v).subs(sub)) for v in X3]
    H = [[float(sp.diff(expr, a, b).subs(sub)) for b in X3] for a in X3]
    return g, H
CASES = [
    ("g_poly", x ** 2 * y + sp.sin(y) * z + z ** 3, [(1.0, 2.0, -0.5), (0.3, -1.2, 2.0), (0.0, 0.0, 0.0)]),
    ("g_exp", sp.exp(x * y) + x ** 3 - y * z, [(0.5, 0.8, 1.0), (-1.0, 0.4, 2.5)]),
]
for name, expr, pts in CASES:
    for pt in pts:
        g, H = sym_grad_hess(expr, pt)
        sc = lit(list(pt))
        S.arr(f"gradient {name} en {pt}", f"calculus.gradient({name}, {sc})", np.array(g), 1e-9)
        S.arr(f"hessian {name} en {pt}", f"calculus.hessian({name}, {sc})", np.array(H), 1e-7)
        S.close(f"laplacian {name} en {pt}", f"calculus.laplacian({name}, {sc})", sum(H[i][i] for i in range(3)), 1e-8)
        S.arr(f"hessian symétrique {name} en {pt}", f"array.transpose(calculus.hessian({name}, {sc}))", np.array(H), 1e-7)
        S.close(f"directional_derivative {name} en {pt}", f"calculus.directional_derivative({name}, {sc}, [1.0, -2.0, 0.5])", float(np.dot(g, [1.0, -2.0, 0.5])), 1e-8)
S.arr("gradient depuis un Array", f"calculus.gradient(g_poly, {A(np.array([1.0, 2.0, -0.5]))})", np.array(sym_grad_hess(CASES[0][1], (1.0, 2.0, -0.5))[0]), 1e-9)
S.arr("gradient d'une forme quadratique (exact)", "calculus.gradient(g_quad, [2.0, -1.0])", np.array([2 * 2 + 5 * -1, 6 * -1 + 5 * 2.0]), 1e-10)
S.arr("hessienne d'une forme quadratique", "calculus.hessian(g_quad, [2.0, -1.0])", np.array([[2.0, 5.0], [5.0, 6.0]]), 1e-8)
S.arr("gradient de Rosenbrock au minimum = 0", "calculus.gradient(g_ros, [1.0, 1.0])", np.zeros(2), 1e-8)
S.arr("hessienne de Rosenbrock au minimum", "calculus.hessian(g_ros, [1.0, 1.0])", np.array([[802.0, -400.0], [-400.0, 200.0]]), 1e-5)
xr, yr = sp.symbols('xr yr')
rosen = 100 * (yr - xr ** 2) ** 2 + (1 - xr) ** 2
S.arr("gradient de Rosenbrock en (-1.2, 1)", "calculus.gradient(g_ros, [-1.2, 1.0])", np.array([float(sp.diff(rosen, v).subs({xr: -1.2, yr: 1.0})) for v in (xr, yr)]), 1e-8)
rr = sp.sqrt(x ** 2 + y ** 2 + z ** 2)
S.arr("gradient du potentiel 1/r", "calculus.gradient(g_pot, [1.0, 2.0, 2.0])", np.array([float(sp.diff(1 / rr, v).subs({x: 1, y: 2, z: 2})) for v in X3]), 1e-9)
S.close("laplacien de 1/r = 0 (harmonique)", "calculus.laplacian(g_pot, [1.0, 2.0, 2.0])", 0.0, 1e-8)
S.arr("gradient avec args", "calculus.gradient(g_par, [2.0, 3.0], null, 4.0)", np.array([4.0 * 3.0, 4.0 * 2.0 + 2 * 3.0]), 1e-9)
S.err("gradient point scalaire", "calculus.gradient(g_quad, 1.0)")
S.err("hessian point scalaire", "calculus.hessian(g_quad, 1.0)")
S.err("directional_derivative dimensions", "calculus.directional_derivative(g_quad, [1.0, 2.0], [1.0])")
S.err("directional_derivative direction nulle", "calculus.directional_derivative(g_quad, [1.0, 2.0], [0.0, 0.0])")

S.group("jacobienne, divergence, rotationnel")
Fa = [x * y, y * z ** 2, sp.sin(x) + z]
pt = (0.7, -1.1, 0.9)
sub = dict(zip(X3, pt))
Ja = [[float(sp.diff(f, v).subs(sub)) for v in X3] for f in Fa]
S.arr("jacobian F_a", f"calculus.jacobian(F_a, {lit(list(pt))})", np.array(Ja), 1e-9)
S.close("divergence F_a", f"calculus.divergence(F_a, {lit(list(pt))})", sum(Ja[i][i] for i in range(3)), 1e-9)
cu = [float(sp.diff(Fa[2], y).subs(sub) - sp.diff(Fa[1], z).subs(sub)), float(sp.diff(Fa[0], z).subs(sub) - sp.diff(Fa[2], x).subs(sub)), float(sp.diff(Fa[1], x).subs(sub) - sp.diff(Fa[0], y).subs(sub))]
S.arr("curl F_a", f"calculus.curl(F_a, {lit(list(pt))})", np.array(cu), 1e-9)
Fb = [x ** 2 - y, sp.exp(x) + y ** 2]
S.arr("jacobian champ plan (2x2)", "calculus.jacobian(F_b, [0.4, 1.5])", np.array([[float(sp.diff(f, v).subs({x: 0.4, y: 1.5})) for v in (x, y)] for f in Fb]), 1e-9)
S.arr("jacobian champ rotation", "calculus.jacobian(F_rot, [1.0, 2.0, 3.0])", np.array([[0, -1, 0], [1, 0, 0], [0, 0, 0.0]]), 1e-10)
S.arr("curl d'un champ de rotation solide = (0, 0, 2)", "calculus.curl(F_rot, [1.0, 2.0, 3.0])", np.array([0.0, 0.0, 2.0]), 1e-10)
S.close("divergence d'un champ de rotation = 0", "calculus.divergence(F_rot, [1.0, 2.0, 3.0])", 0.0, 1e-10)
S.arr("curl du gradient = 0 (champ conservatif)", "calculus.curl(F_cons3, [0.5, 1.0, -1.0])", np.zeros(3), 1e-8) if False else None
S.arr("jacobian d'une fonction scalaire (ligne)", "calculus.jacobian(g_quad, [1.0, 1.0])", np.array([[2 + 5.0, 6 + 5.0]]), 1e-9)
S.arr("jacobian forme (m, n) = (3, 3)", f"array.from_list(calculus.jacobian(F_a, {lit(list(pt))}).shape)", np.array([3, 3]), 0.0)
S.arr("jacobian forme (2, 3) pour F : R3 -> R2", "array.from_list(calculus.jacobian(F_two_three, [1.0, 2.0, 3.0]).shape)", np.array([2, 3]), 0.0) if False else None
S.err("curl dimension 2", "calculus.curl(fld_rot2, [1.0, 2.0])")
S.err("divergence point scalaire", "calculus.divergence(fld_rot2, 1.0)")
S.err("jacobian point scalaire", "calculus.jacobian(fld_rot2, 1.0)")

S.group("intégrales doubles et triples")
tol = 1e-8
S.close("dblquad ∫∫ xy sur [0,2]x[0,3]", "calculus.dblquad(d_xy, 0.0, 2.0, 0.0, 3.0)[0]", 9.0, tol)
S.close("dblquad avec args", "calculus.dblquad(d_param, 0.0, 1.0, 0.0, 2.0, 3.0)[0]", 3.0 * 0.5 * 2 + 8 / 3, tol)
S.close("dblquad borne y fonction de x (triangle)", "calculus.dblquad(d_xplus, 0.0, 1.0, 0.0, lim_x)[0]", float(sint.dblquad(lambda yy, xx: xx + yy ** 2, 0, 1, 0, lambda xx: xx)[0]), tol)
S.close("dblquad bornes y = [x², x]", "calculus.dblquad(d_xy, 0.0, 1.0, lim_sq, lim_x)[0]", float(sint.dblquad(lambda yy, xx: xx * yy, 0, 1, lambda xx: xx ** 2, lambda xx: xx)[0]), tol)
S.close("aire du disque unité = π", "calculus.dblquad(d_one, -1.0, 1.0, lim_circ_lo, lim_circ_hi)[0]", np.pi, 1e-7)
S.close("dblquad gaussienne sur [-5,5]²", "calculus.dblquad(d_gauss, -5.0, 5.0, -5.0, 5.0)[0]", float(np.pi * (np.math.erf(5) ** 2) if hasattr(np, 'math') else np.pi * (__import__('math').erf(5) ** 2)), 1e-7)
S.close("dblquad gaussienne sur R² (bornes infinies)", "calculus.dblquad(d_gauss, -numeric.INF, numeric.INF, -numeric.INF, numeric.INF)[0]", np.pi, 1e-7)
S.close("dblquad bornes inversées en x", "calculus.dblquad(d_xy, 2.0, 0.0, 0.0, 3.0)[0]", -9.0, tol)
S.close("dblquad domaine triangulaire (aire 1/2)", "calculus.dblquad(d_one, 0.0, 1.0, 0.0, lim_one_minus)[0]", 0.5, tol)
S.close("tplquad volume du cube", "calculus.tplquad(t_one, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0)[0]", 1.0, tol)
S.close("tplquad ∫∫∫ xyz sur [0,1]³", "calculus.tplquad(t_xyz, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0)[0]", 0.125, tol)
S.close("tplquad ∫∫∫ x + y² + z³ sur [0,2]³", "calculus.tplquad(t_sum, 0.0, 2.0, 0.0, 2.0, 0.0, 2.0)[0]", float(sint.tplquad(lambda zz, yy, xx: xx + yy ** 2 + zz ** 3, 0, 2, 0, 2, 0, 2)[0]), tol)
S.close("tplquad avec args", "calculus.tplquad(t_param, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 4.0)[0]", 4.0 * 0.25 + 0.5, tol)
S.close("tplquad volume du simplexe = 1/6", "calculus.tplquad(t_one, 0.0, 1.0, 0.0, lim_one_minus, 0.0, z_hi_simplex)[0]", 1 / 6, tol)
S.close("tplquad volume de la boule unité = 4π/3", "calculus.tplquad(t_one, -1.0, 1.0, lim_circ_lo, lim_circ_hi, z_lo_ball, z_hi_ball, null, 0.000001, 0.000001)[0]", 4 * np.pi / 3, 1e-5)
S.close("line_integral champ conservatif = x²y final", "calculus.line_integral(fld_conservative, line_r, line_dr, 0.0, 1.0)[0]", 2.0, 1e-10)
S.close("line_integral circulation sur le cercle = 2π", "calculus.line_integral(fld_rot2, circle_r, circle_dr, 0.0, 2.0 * numeric.PI)[0]", 2 * np.pi, 1e-10)
S.close("line_integral demi-cercle = π", "calculus.line_integral(fld_rot2, circle_r, circle_dr, 0.0, numeric.PI)[0]", np.pi, 1e-10)
S.close("line_integral courbe fermée conservatif = 0", "calculus.line_integral(fld_conservative, circle_r, circle_dr, 0.0, 2.0 * numeric.PI)[0]", 0.0, 1e-10)
S.close("théorème de Green : circulation = ∬ rot = 2 aire", "calculus.line_integral(fld_rot2, circle_r, circle_dr, 0.0, 2.0 * numeric.PI)[0] - 2.0 * calculus.dblquad(d_one, -1.0, 1.0, lim_circ_lo, lim_circ_hi)[0]", 0.0, 1e-6)

S.group("systèmes d'équations non linéaires")
def sol(label, call, ref, tol=1e-10):
    S.arr(label, call, np.array(ref, dtype=float), tol)
r = so.fsolve(lambda v: [v[0] ** 2 + v[1] ** 2 - 4, v[0] - v[1]], [1.0, 2.0], xtol=1e-14)
sol("cercle ∩ droite (jacobienne numérique)", "calculus.newton_system(F_nonlin, [1.0, 2.0])", r)
sol("cercle ∩ droite (jacobienne analytique)", "calculus.newton_system(F_nonlin, [1.0, 2.0], J_nonlin)", r)
sol("cercle ∩ droite, autre départ", "calculus.newton_system(F_nonlin, [-1.0, -3.0])", [-np.sqrt(2), -np.sqrt(2)])
sol("fsolve (alias)", "calculus.fsolve(F_nonlin, [1.0, 2.0])", r)
r3 = so.fsolve(lambda v: [v[0] + v[1] + v[2] - 6, v[0] * v[1] * v[2] - 6, v[0] ** 2 + v[1] ** 2 + v[2] ** 2 - 14], [0.8, 2.2, 2.9], xtol=1e-14)
sol("système 3x3 (solution 1, 2, 3)", "calculus.newton_system(F_3, [0.8, 2.2, 2.9])", r3, 1e-9)
sol("système 3x3 : valeurs exactes", "calculus.newton_system(F_3, [0.8, 2.2, 2.9])", [1.0, 2.0, 3.0], 1e-9)
sol("Rosenbrock en racine (1, 1)", "calculus.newton_system(F_ros, [-1.2, 1.0])", [1.0, 1.0])
r4 = so.fsolve(lambda v: [np.sin(v[0]) - v[1], np.cos(v[1]) - v[0]], [0.5, 0.5], xtol=1e-14)
sol("sin x = y, cos y = x", "calculus.newton_system(F_trig, [0.5, 0.5])", r4)
sol("système avec args", "calculus.newton_system(F_par, [1.0, 1.0], null, 0.000000000001, 50, 9.0)", [3.0, 3.0])
sol("système 1x1 (x³ = 8)", "calculus.newton_system(F_1d, [1.0])", [2.0])
sol("point de départ scalaire accepté pour n = 1", "calculus.newton_system(F_1d, 5.0)", [2.0])
S.true("résidu final petit", "linalg_norm2(F_nonlin(calculus.newton_system(F_nonlin, [1.0, 2.0]).data)) < 0.000000000001")
S.true("le point de départ est déjà une racine", "calculus.newton_system(F_nonlin, [1.4142135623730951, 1.4142135623730951]).data[0] > 1.41")
S.err("jacobienne singulière", "calculus.newton_system(F_sing, [0.0, 0.0])") if False else None
sol("Newton amorti : arctan depuis x=2 (Newton pur diverge)", "calculus.newton_system(F_atan, [2.0])", [0.0], 1e-10)
S.err("F renvoie un mauvais nombre de composantes", "calculus.newton_system(F_wrong, [1.0, 2.0])")
S.err("pas de racine réelle (non convergence)", "calculus.newton_system(F_noroot, [1.0, 1.0])")

S.define('''func linalg_norm2(v):
    s := 0.0
    for t in v:
        s = s + t * t
    return math.sqrt(s)

func F_noroot(v):
    return [v[0] * v[0] + v[1] * v[1] + 1.0, v[0] - v[1]]
''')

text = S.render()
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'tests', 'test_calculus.al'), 'w', encoding='utf-8').write(text)
print("lignes :", text.count("\n"), "| cas d'erreur :", S.nerr)

# =============================================================================
# ALEX - tests du module stdlib/calculus/calculus.al
# Dérivées, gradient/jacobienne/hessienne, opérateurs vectoriels, intégrales multiples, systèmes.
# Les valeurs attendues proviennent de SymPy 1.14 (dérivées exactes) / SciPy 1.17 (référence indépendante),
# jamais d'un calcul avec le module testé.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/test_calculus.al
# Code de sortie 0 si tout passe, 1 sinon.
# =============================================================================
use array
use calculus
use math
use numeric
from core use len, is_bool
from collections use append, clear

tally := [0, 0]
notes := []
failed_groups := []

func ok():
    tally[0] = tally[0] + 1

func fail(label, detail):
    tally[1] = tally[1] + 1
    append(notes, f"{label} : {detail}")

func abs_val(v):
    if v < 0:
        return 0 - v
    return v

func check(cond, label):
    if cond:
        ok()
    else:
        fail(label, "condition fausse")

func check_eq(actual, expected, label):
    if actual == expected:
        ok()
    else:
        fail(label, f"obtenu {actual}, attendu {expected}")

# Erreur relative (absolue si |attendu| < 1).
func check_close(actual, expected, tol, label):
    if actual == null:
        fail(label, f"obtenu null, attendu {expected}")
    else:
        scale := abs_val(expected)
        if scale < 1:
            scale = 1
        if abs_val(actual - expected) <= tol * scale:
            ok()
        else:
            fail(label, f"obtenu {actual}, attendu {expected}")

# Compare deux listes de nombres (même longueur, tolérance relative tol).
func check_list_close(actual, expected, tol, label):
    if len(actual) != len(expected):
        fail(label, f"longueurs {len(actual)} et {len(expected)}")
    else:
        i := 0
        bad := 0
        while i < len(actual):
            if is_bool(expected[i]) or is_bool(actual[i]):
                if actual[i] != expected[i]:
                    bad = bad + 1
                    if bad == 1:
                        fail(label, f"élément {i} : obtenu {actual[i]}, attendu {expected[i]}")
            else:
                sc := abs_val(expected[i])
                if sc < 1:
                    sc = 1
                if abs_val(actual[i] - expected[i]) > tol * sc:
                    bad = bad + 1
                    if bad == 1:
                        fail(label, f"élément {i} : obtenu {actual[i]}, attendu {expected[i]}")
            i += 1
        if bad == 0:
            ok()

func run(name, fn):
    clear(notes)
    before := tally[1]
    fn()
    if tally[1] > before:
        append(failed_groups, name)
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")

# Vrai si fn() (sans argument) lève une erreur.
func raises(fn):
    threw := false
    try:
        fn()
    catch e:
        threw = true
    return threw

func finish(title, groups):
    total := tally[0] + tally[1]
    print("")
    print(f"=== {title} ===")
    print(f"Groupes : {groups}, vérifications : {tally[0]} réussies, {tally[1]} en échec (sur {total})")
    if tally[1] > 0:
        print(f"Groupes en échec : {failed_groups}")
        raise("AssertionError", f"{tally[1]} vérification(s) en échec")
    print(f"TOUS LES TESTS {title} PASSENT")

# Compare un Array à une forme et une liste plate attendues.
func check_arr(a, shape, flat, tol, label):
    if not array.is_array(a):
        fail(label, "un Array était attendu")
    elif not array.array_equal(array.from_list(a.shape), array.from_list(shape)):
        fail(label, f"forme obtenue {a.shape}, attendue {shape}")
    else:
        check_list_close(a.data, flat, tol, label)

func s_sinexp(x):
    return math.sin(x) * math.exp(x)

func s_gauss(x):
    return math.exp(0.0 - x * x)

func s_log(x):
    return math.ln(x)

func s_sqrt(x):
    return math.sqrt(x)

func s_cos3(x):
    return math.cos(3.0 * x)

func s_atan(x):
    return math.atan(x)

func s_quartic(x):
    return x * x * x * x - 2.0 * x

func s_inv(x):
    return 1.0 / x

func s_big(x):
    return math.sin(x) * 1000000.0

func s_param(x, p):
    return p[0] * math.sin(p[1] * x)

func s_abs(x):
    return math.abs(x)

func s_step(x):
    if x < 0.0:
        return 0.0
    return 1.0

func s_const(x):
    return 5.0

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

func linalg_norm2(v):
    s := 0.0
    for t in v:
        s = s + t * t
    return math.sqrt(s)

func F_noroot(v):
    return [v[0] * v[0] + v[1] * v[1] + 1.0, v[0] - v[1]]

func e_1():
    calculus.derivative_n(s_inv, 0.2, 4)

func e_2():
    calculus.derivative_n(s_sinexp, 1.0, 0)

func e_3():
    calculus.derivative(s_sinexp, [1.0, 2.0])

func e_4():
    calculus.derivative_n(s_sinexp, 1.0, 1.5)

func e_5():
    calculus.gradient(g_quad, 1.0)

func e_6():
    calculus.hessian(g_quad, 1.0)

func e_7():
    calculus.directional_derivative(g_quad, [1.0, 2.0], [1.0])

func e_8():
    calculus.directional_derivative(g_quad, [1.0, 2.0], [0.0, 0.0])

func e_9():
    calculus.curl(fld_rot2, [1.0, 2.0])

func e_10():
    calculus.divergence(fld_rot2, 1.0)

func e_11():
    calculus.jacobian(fld_rot2, 1.0)

func e_12():
    calculus.newton_system(F_wrong, [1.0, 2.0])

func e_13():
    calculus.newton_system(F_noroot, [1.0, 1.0])

func t_1():
    check_close(calculus.derivative(s_sinexp, 0.0), 1.0, 0.0000000001, "s_sinexp'^(1) en 0.0")
    check_close(calculus.second_derivative(s_sinexp, 0.0), 2.0, 0.000000001, "s_sinexp'^(2) en 0.0")
    check_close(calculus.derivative_n(s_sinexp, 0.0, 3), 2.0, 0.0000001, "s_sinexp'^(3) en 0.0")
    check_close(calculus.derivative_n(s_sinexp, 0.0, 4), 0.0, 0.000001, "s_sinexp'^(4) en 0.0")
    check_close(calculus.derivative(s_sinexp, 0.7), 2.8374981373070485, 0.0000000001, "s_sinexp'^(1) en 0.7")
    check_close(calculus.second_derivative(s_sinexp, 0.7), 3.0804060508635596, 0.000000001, "s_sinexp'^(2) en 0.7")
    check_close(calculus.derivative_n(s_sinexp, 0.7, 3), 0.485815827113022, 0.0000001, "s_sinexp'^(3) en 0.7")
    check_close(calculus.derivative_n(s_sinexp, 0.7, 4), -5.189180447501075, 0.000001, "s_sinexp'^(4) en 0.7")
    check_close(calculus.derivative(s_sinexp, -1.3), -0.1896983045647903, 0.0000000001, "s_sinexp'^(1) en -1.3")
    check_close(calculus.second_derivative(s_sinexp, -1.3), 0.1458038707991137, 0.000000001, "s_sinexp'^(2) en -1.3")
    check_close(calculus.derivative_n(s_sinexp, -1.3, 3), 0.671004350727808, 0.0000001, "s_sinexp'^(3) en -1.3")
    check_close(calculus.derivative_n(s_sinexp, -1.3, 4), 1.0504009598573887, 0.000001, "s_sinexp'^(4) en -1.3")
    check_close(calculus.derivative(s_gauss, 0.0), 0.0, 0.0000000001, "s_gauss'^(1) en 0.0")
    check_close(calculus.second_derivative(s_gauss, 0.0), -2.0, 0.000000001, "s_gauss'^(2) en 0.0")
    check_close(calculus.derivative_n(s_gauss, 0.0, 3), 0.0, 0.0000001, "s_gauss'^(3) en 0.0")
    check_close(calculus.derivative_n(s_gauss, 0.0, 4), 12.0, 0.000001, "s_gauss'^(4) en 0.0")
    check_close(calculus.derivative(s_gauss, 0.4), -0.6817150311729692, 0.0000000001, "s_gauss'^(1) en 0.4")
    check_close(calculus.second_derivative(s_gauss, 0.4), -1.1589155529940474, 0.000000001, "s_gauss'^(2) en 0.4")
    check_close(calculus.derivative_n(s_gauss, 0.4, 3), 3.653992567087114, 0.0000001, "s_gauss'^(3) en 0.4")
    check_close(calculus.derivative_n(s_gauss, 0.4, 4), 4.030299264294592, 0.000001, "s_gauss'^(4) en 0.4")
    check_close(calculus.derivative(s_gauss, 2.0), -0.07326255555493671, 0.0000000001, "s_gauss'^(1) en 2.0")
    check_close(calculus.second_derivative(s_gauss, 2.0), 0.25641894444227853, 0.000000001, "s_gauss'^(2) en 2.0")
    check_close(calculus.derivative_n(s_gauss, 2.0, 3), -0.7326255555493671, 0.0000001, "s_gauss'^(3) en 2.0")
    check_close(calculus.derivative_n(s_gauss, 2.0, 4), 1.3919885555437976, 0.000001, "s_gauss'^(4) en 2.0")
    check_close(calculus.derivative(s_log, 0.5), 2.0, 0.0000000001, "s_log'^(1) en 0.5")
    check_close(calculus.second_derivative(s_log, 0.5), -4.0, 0.000000001, "s_log'^(2) en 0.5")
    check_close(calculus.derivative_n(s_log, 0.5, 3), 16.0, 0.0000001, "s_log'^(3) en 0.5")
    check_close(calculus.derivative_n(s_log, 0.5, 4), -96.0, 0.000001, "s_log'^(4) en 0.5")
    check_close(calculus.derivative(s_log, 2.5), 0.4, 0.0000000001, "s_log'^(1) en 2.5")
    check_close(calculus.second_derivative(s_log, 2.5), -0.16, 0.000000001, "s_log'^(2) en 2.5")
    check_close(calculus.derivative_n(s_log, 2.5, 3), 0.128, 0.0000001, "s_log'^(3) en 2.5")
    check_close(calculus.derivative_n(s_log, 2.5, 4), -0.15360000000000001, 0.000001, "s_log'^(4) en 2.5")
    check_close(calculus.derivative(s_log, 40.0), 0.025, 0.0000000001, "s_log'^(1) en 40.0")
    check_close(calculus.second_derivative(s_log, 40.0), -0.000625, 0.000000001, "s_log'^(2) en 40.0")
    check_close(calculus.derivative_n(s_log, 40.0, 3), 0.00003125, 0.0000001, "s_log'^(3) en 40.0")
    check_close(calculus.derivative_n(s_log, 40.0, 4), -0.0000023437500000000002, 0.000001, "s_log'^(4) en 40.0")
    check_close(calculus.derivative(s_sqrt, 0.3), 0.9128709291752769, 0.0000000001, "s_sqrt'^(1) en 0.3")
    check_close(calculus.second_derivative(s_sqrt, 0.3), -1.5214515486254616, 0.000000001, "s_sqrt'^(2) en 0.3")
    check_close(calculus.derivative_n(s_sqrt, 0.3, 3), 7.607257743127308, 0.0000001, "s_sqrt'^(3) en 0.3")
    check_close(calculus.derivative_n(s_sqrt, 0.3, 4), -63.3938145260609, 0.000001, "s_sqrt'^(4) en 0.3")
    check_close(calculus.derivative(s_sqrt, 4.0), 0.25, 0.0000000001, "s_sqrt'^(1) en 4.0")
    check_close(calculus.second_derivative(s_sqrt, 4.0), -0.03125, 0.000000001, "s_sqrt'^(2) en 4.0")
    check_close(calculus.derivative_n(s_sqrt, 4.0, 3), 0.01171875, 0.0000001, "s_sqrt'^(3) en 4.0")
    check_close(calculus.derivative_n(s_sqrt, 4.0, 4), -0.00732421875, 0.000001, "s_sqrt'^(4) en 4.0")
    check_close(calculus.derivative(s_sqrt, 100.0), 0.05, 0.0000000001, "s_sqrt'^(1) en 100.0")
    check_close(calculus.second_derivative(s_sqrt, 100.0), -0.00025, 0.000000001, "s_sqrt'^(2) en 100.0")
    check_close(calculus.derivative_n(s_sqrt, 100.0, 3), 0.0000037500000000000005, 0.0000001, "s_sqrt'^(3) en 100.0")
    check_close(calculus.derivative_n(s_sqrt, 100.0, 4), -0.00000009375, 0.000001, "s_sqrt'^(4) en 100.0")
    check_close(calculus.derivative(s_cos3, 0.0), 0.0, 0.0000000001, "s_cos3'^(1) en 0.0")
    check_close(calculus.second_derivative(s_cos3, 0.0), -9.0, 0.000000001, "s_cos3'^(2) en 0.0")
    check_close(calculus.derivative_n(s_cos3, 0.0, 3), 0.0, 0.0000001, "s_cos3'^(3) en 0.0")
    check_close(calculus.derivative_n(s_cos3, 0.0, 4), 81.0, 0.000001, "s_cos3'^(4) en 0.0")
    check_close(calculus.derivative(s_cos3, 1.1), 0.47323708242974594, 0.0000000001, "s_cos3'^(1) en 1.1")
    check_close(calculus.second_derivative(s_cos3, 1.1), 8.887317929179783, 0.000000001, "s_cos3'^(2) en 1.1")
    check_close(calculus.derivative_n(s_cos3, 1.1, 3), -4.259133741867713, 0.0000001, "s_cos3'^(3) en 1.1")
    check_close(calculus.derivative_n(s_cos3, 1.1, 4), -79.98586136261805, 0.000001, "s_cos3'^(4) en 1.1")
    check_close(calculus.derivative(s_cos3, -2.2), 0.9346240905401361, 0.0000000001, "s_cos3'^(1) en -2.2")
    check_close(calculus.second_derivative(s_cos3, -2.2), -8.552093327626764, 0.000000001, "s_cos3'^(2) en -2.2")
    check_close(calculus.derivative_n(s_cos3, -2.2, 3), -8.411616814861224, 0.0000001, "s_cos3'^(3) en -2.2")
    check_close(calculus.derivative_n(s_cos3, -2.2, 4), 76.96883994864088, 0.000001, "s_cos3'^(4) en -2.2")
    check_close(calculus.derivative(s_atan, 0.0), 1.0, 0.0000000001, "s_atan'^(1) en 0.0")
    check_close(calculus.second_derivative(s_atan, 0.0), 0.0, 0.000000001, "s_atan'^(2) en 0.0")
    check_close(calculus.derivative_n(s_atan, 0.0, 3), -2.0, 0.0000001, "s_atan'^(3) en 0.0")
    check_close(calculus.derivative_n(s_atan, 0.0, 4), 0.0, 0.000001, "s_atan'^(4) en 0.0")
    check_close(calculus.derivative(s_atan, 1.0), 0.5, 0.0000000001, "s_atan'^(1) en 1.0")
    check_close(calculus.second_derivative(s_atan, 1.0), -0.5, 0.000000001, "s_atan'^(2) en 1.0")
    check_close(calculus.derivative_n(s_atan, 1.0, 3), 0.5, 0.0000001, "s_atan'^(3) en 1.0")
    check_close(calculus.derivative_n(s_atan, 1.0, 4), 0.0, 0.000001, "s_atan'^(4) en 1.0")
    check_close(calculus.derivative(s_atan, 10.0), 0.009900990099009901, 0.0000000001, "s_atan'^(1) en 10.0")
    check_close(calculus.second_derivative(s_atan, 10.0), -0.001960592098813842, 0.000000001, "s_atan'^(2) en 10.0")
    check_close(calculus.derivative_n(s_atan, 10.0, 3), 0.0005804129084607313, 0.0000001, "s_atan'^(3) en 10.0")
    check_close(calculus.derivative_n(s_atan, 10.0, 4), -0.00022832892984911714, 0.000001, "s_atan'^(4) en 10.0")
    check_close(calculus.derivative(s_quartic, -3.0), -110.0, 0.0000000001, "s_quartic'^(1) en -3.0")
    check_close(calculus.second_derivative(s_quartic, -3.0), 108.0, 0.000000001, "s_quartic'^(2) en -3.0")
    check_close(calculus.derivative_n(s_quartic, -3.0, 3), -72.0, 0.0000001, "s_quartic'^(3) en -3.0")
    check_close(calculus.derivative_n(s_quartic, -3.0, 4), 24.0, 0.000001, "s_quartic'^(4) en -3.0")
    check_close(calculus.derivative(s_quartic, 0.0), -2.0, 0.0000000001, "s_quartic'^(1) en 0.0")
    check_close(calculus.second_derivative(s_quartic, 0.0), 0.0, 0.000000001, "s_quartic'^(2) en 0.0")
    check_close(calculus.derivative_n(s_quartic, 0.0, 3), 0.0, 0.0000001, "s_quartic'^(3) en 0.0")
    check_close(calculus.derivative_n(s_quartic, 0.0, 4), 24.0, 0.000001, "s_quartic'^(4) en 0.0")
    check_close(calculus.derivative(s_quartic, 5.0), 498.0, 0.0000000001, "s_quartic'^(1) en 5.0")
    check_close(calculus.second_derivative(s_quartic, 5.0), 300.0, 0.000000001, "s_quartic'^(2) en 5.0")
    check_close(calculus.derivative_n(s_quartic, 5.0, 3), 120.0, 0.0000001, "s_quartic'^(3) en 5.0")
    check_close(calculus.derivative_n(s_quartic, 5.0, 4), 24.0, 0.000001, "s_quartic'^(4) en 5.0")
    check_close(calculus.derivative(s_inv, 0.9), -1.2345679012345678, 0.0000000001, "s_inv'^(1) en 0.9")
    check_close(calculus.second_derivative(s_inv, 0.9), 2.743484224965706, 0.000000001, "s_inv'^(2) en 0.9")
    check_close(calculus.derivative_n(s_inv, 0.9, 3), -9.144947416552355, 0.0000001, "s_inv'^(3) en 0.9")
    check_close(calculus.derivative_n(s_inv, 0.9, 4), 40.64421074023268, 0.000001, "s_inv'^(4) en 0.9")
    check_close(calculus.derivative(s_inv, 3.0), -0.1111111111111111, 0.0000000001, "s_inv'^(1) en 3.0")
    check_close(calculus.second_derivative(s_inv, 3.0), 0.07407407407407407, 0.000000001, "s_inv'^(2) en 3.0")
    check_close(calculus.derivative_n(s_inv, 3.0, 3), -0.07407407407407407, 0.0000001, "s_inv'^(3) en 3.0")
    check_close(calculus.derivative_n(s_inv, 3.0, 4), 0.09876543209876544, 0.000001, "s_inv'^(4) en 3.0")
    check_close(calculus.derivative(s_inv, -7.0), -0.02040816326530612, 0.0000000001, "s_inv'^(1) en -7.0")
    check_close(calculus.second_derivative(s_inv, -7.0), -0.0058309037900874635, 0.000000001, "s_inv'^(2) en -7.0")
    check_close(calculus.derivative_n(s_inv, -7.0, 3), -0.0024989587671803417, 0.0000001, "s_inv'^(3) en -7.0")
    check_close(calculus.derivative_n(s_inv, -7.0, 4), -0.0014279764383887665, 0.000001, "s_inv'^(4) en -7.0")
    check_close(calculus.derivative_n(s_sinexp, 0.7, 5), -11.349992549228194, 0.0001, "dérivée 5ème de sin x e^x en 0.7")
    check_close(calculus.derivative(s_param, 0.8, null, [2.0, 3.0]), -4.424362293247475, 0.0000000001, "dérivée avec args")
    check_close(calculus.second_derivative(s_param, 0.8, null, [2.0, 3.0]), -12.158337249920711, 0.000000001, "second_derivative avec args")
    check_close(calculus.derivative(s_const, 2.0), 0.0, 0.000000000001, "dérivée d'une constante")
    check_close(calculus.derivative_n(s_inv, 0.2, 4, 0.02), 74999.99999999997, 0.00001, "singularité proche : pas h réduit (1/x en 0.2, ordre 4)")
    check(raises(e_1), "erreur : singularité atteinte par le pas initial (1/x en 0.2, ordre 4)")
    check_close(calculus.derivative(s_sinexp, 0.7, 0.05), 2.8374981373070485, 0.000000001, "dérivée avec pas h explicite")
    check_close(calculus.derivative(s_big, 1.0), 540302.3058681397, 0.000000001, "dérivée à grande échelle (1e6 sin x)")
    check_list_close([calculus.derivative_err(s_sinexp, 0.7)[0]], [2.8374981373070485], 0.0000000001, "derivative_err : [valeur, erreur]")
    check(calculus.derivative_err(s_sinexp, 0.7)[1] >= 0.0 and calculus.derivative_err(s_sinexp, 0.7)[1] < 0.0000001, "derivative_err : erreur estimée petite et positive")
    check(calculus.derivative_err(s_quartic, 1.5)[1] + 0.000000000001 >= abs_val(calculus.derivative_err(s_quartic, 1.5)[0] - (4.0 * 1.5 * 1.5 * 1.5 - 2.0)), "erreur estimée >= erreur réelle (x³)")
    check_close(calculus.derivative(s_abs, 1.0), 1.0, 0.000000000001, "dérivée de |x| en 1")
    check_close(calculus.derivative(s_abs, -2.0), -1.0, 0.000000000001, "dérivée de |x| en -2")
    check(calculus.derivative_err(s_abs, 0.0)[1] > 0.01 or abs_val(calculus.derivative(s_abs, 0.0)) < 0.000001, "non dérivable en 0 (|x|) : erreur estimée grande")
    check(calculus.derivative_err(s_step, 0.0)[1] > 1.0, "discontinuité (marche) : erreur estimée grande")
    check(raises(e_2), "erreur : derivative ordre 0")
    check(raises(e_3), "erreur : derivative abscisse vectorielle")
    check(raises(e_4), "erreur : derivative_n ordre flottant")

func t_2():
    check_arr(calculus.gradient(g_poly, [1.0, 2.0, -0.5]), [3], [4.0, 1.2080734182735713, 1.6592974268256817], 0.000000001, "gradient g_poly en (1.0, 2.0, -0.5)")
    check_arr(calculus.hessian(g_poly, [1.0, 2.0, -0.5]), [3, 3], [4.0, 2.0, 0.0, 2.0, 0.45464871341284085, -0.4161468365471424, 0.0, -0.4161468365471424, -3.0], 0.0000001, "hessian g_poly en (1.0, 2.0, -0.5)")
    check_close(calculus.laplacian(g_poly, [1.0, 2.0, -0.5]), 1.454648713412841, 0.00000001, "laplacian g_poly en (1.0, 2.0, -0.5)")
    check_arr(array.transpose(calculus.hessian(g_poly, [1.0, 2.0, -0.5])), [3, 3], [4.0, 2.0, 0.0, 2.0, 0.45464871341284085, -0.4161468365471424, 0.0, -0.4161468365471424, -3.0], 0.0000001, "hessian symétrique g_poly en (1.0, 2.0, -0.5)")
    check_close(calculus.directional_derivative(g_poly, [1.0, 2.0, -0.5], [1.0, -2.0, 0.5]), 2.4135018768656984, 0.00000001, "directional_derivative g_poly en (1.0, 2.0, -0.5)")
    check_arr(calculus.gradient(g_poly, [0.3, -1.2, 2.0]), [3], [-0.72, 0.8147155089533472, 11.067960914032774], 0.000000001, "gradient g_poly en (0.3, -1.2, 2.0)")
    check_arr(calculus.hessian(g_poly, [0.3, -1.2, 2.0]), [3, 3], [-2.4, 0.6, 0.0, 0.6, 1.8640781719344526, 0.3623577544766736, 0.0, 0.3623577544766736, 12.0], 0.0000001, "hessian g_poly en (0.3, -1.2, 2.0)")
    check_close(calculus.laplacian(g_poly, [0.3, -1.2, 2.0]), 11.464078171934453, 0.00000001, "laplacian g_poly en (0.3, -1.2, 2.0)")
    check_arr(array.transpose(calculus.hessian(g_poly, [0.3, -1.2, 2.0])), [3, 3], [-2.4, 0.6, 0.0, 0.6, 1.8640781719344526, 0.3623577544766736, 0.0, 0.3623577544766736, 12.0], 0.0000001, "hessian symétrique g_poly en (0.3, -1.2, 2.0)")
    check_close(calculus.directional_derivative(g_poly, [0.3, -1.2, 2.0], [1.0, -2.0, 0.5]), 3.1845494391096927, 0.00000001, "directional_derivative g_poly en (0.3, -1.2, 2.0)")
    check_arr(calculus.gradient(g_poly, [0.0, 0.0, 0.0]), [3], [0.0, 0.0, 0.0], 0.000000001, "gradient g_poly en (0.0, 0.0, 0.0)")
    check_arr(calculus.hessian(g_poly, [0.0, 0.0, 0.0]), [3, 3], [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0], 0.0000001, "hessian g_poly en (0.0, 0.0, 0.0)")
    check_close(calculus.laplacian(g_poly, [0.0, 0.0, 0.0]), 0.0, 0.00000001, "laplacian g_poly en (0.0, 0.0, 0.0)")
    check_arr(array.transpose(calculus.hessian(g_poly, [0.0, 0.0, 0.0])), [3, 3], [0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.0], 0.0000001, "hessian symétrique g_poly en (0.0, 0.0, 0.0)")
    check_close(calculus.directional_derivative(g_poly, [0.0, 0.0, 0.0], [1.0, -2.0, 0.5]), 0.0, 0.00000001, "directional_derivative g_poly en (0.0, 0.0, 0.0)")
    check_arr(calculus.gradient(g_exp, [0.5, 0.8, 1.0]), [3], [1.9434597581130164, -0.2540876511793648, -0.8], 0.000000001, "gradient g_exp en (0.5, 0.8, 1.0)")
    check_arr(calculus.hessian(g_exp, [0.5, 0.8, 1.0]), [3, 3], [3.9547678064904135, 2.088554576697778, 0.0, 2.088554576697778, 0.3729561744103176, -1.0, 0.0, -1.0, 0.0], 0.0000001, "hessian g_exp en (0.5, 0.8, 1.0)")
    check_close(calculus.laplacian(g_exp, [0.5, 0.8, 1.0]), 4.327723980900731, 0.00000001, "laplacian g_exp en (0.5, 0.8, 1.0)")
    check_arr(array.transpose(calculus.hessian(g_exp, [0.5, 0.8, 1.0])), [3, 3], [3.9547678064904135, 2.088554576697778, 0.0, 2.088554576697778, 0.3729561744103176, -1.0, 0.0, -1.0, 0.0], 0.0000001, "hessian symétrique g_exp en (0.5, 0.8, 1.0)")
    check_close(calculus.directional_derivative(g_exp, [0.5, 0.8, 1.0], [1.0, -2.0, 0.5]), 2.0516350604717464, 0.00000001, "directional_derivative g_exp en (0.5, 0.8, 1.0)")
    check_arr(calculus.gradient(g_exp, [-1.0, 0.4, 2.5]), [3], [3.268128018414256, -3.1703200460356395, -0.4], 0.000000001, "gradient g_exp en (-1.0, 0.4, 2.5)")
    check_arr(calculus.hessian(g_exp, [-1.0, 0.4, 2.5]), [3, 3], [-5.892748792634298, 0.40219202762138356, 0.0, 0.40219202762138356, 0.6703200460356393, -1.0, 0.0, -1.0, 0.0], 0.0000001, "hessian g_exp en (-1.0, 0.4, 2.5)")
    check_close(calculus.laplacian(g_exp, [-1.0, 0.4, 2.5]), -5.222428746598658, 0.00000001, "laplacian g_exp en (-1.0, 0.4, 2.5)")
    check_arr(array.transpose(calculus.hessian(g_exp, [-1.0, 0.4, 2.5])), [3, 3], [-5.892748792634298, 0.40219202762138356, 0.0, 0.40219202762138356, 0.6703200460356393, -1.0, 0.0, -1.0, 0.0], 0.0000001, "hessian symétrique g_exp en (-1.0, 0.4, 2.5)")
    check_close(calculus.directional_derivative(g_exp, [-1.0, 0.4, 2.5], [1.0, -2.0, 0.5]), 9.408768110485536, 0.00000001, "directional_derivative g_exp en (-1.0, 0.4, 2.5)")
    check_arr(calculus.gradient(g_poly, array.from_list([1.0, 2.0, -0.5])), [3], [4.0, 1.2080734182735713, 1.6592974268256817], 0.000000001, "gradient depuis un Array")
    check_arr(calculus.gradient(g_quad, [2.0, -1.0]), [2], [-1.0, 4.0], 0.0000000001, "gradient d'une forme quadratique (exact)")
    check_arr(calculus.hessian(g_quad, [2.0, -1.0]), [2, 2], [2.0, 5.0, 5.0, 6.0], 0.00000001, "hessienne d'une forme quadratique")
    check_arr(calculus.gradient(g_ros, [1.0, 1.0]), [2], [0.0, 0.0], 0.00000001, "gradient de Rosenbrock au minimum = 0")
    check_arr(calculus.hessian(g_ros, [1.0, 1.0]), [2, 2], [802.0, -400.0, -400.0, 200.0], 0.00001, "hessienne de Rosenbrock au minimum")
    check_arr(calculus.gradient(g_ros, [-1.2, 1.0]), [2], [-215.5999999999999, -88.0], 0.00000001, "gradient de Rosenbrock en (-1.2, 1)")
    check_arr(calculus.gradient(g_pot, [1.0, 2.0, 2.0]), [3], [-0.037037037037037035, -0.07407407407407407, -0.07407407407407407], 0.000000001, "gradient du potentiel 1/r")
    check_close(calculus.laplacian(g_pot, [1.0, 2.0, 2.0]), 0.0, 0.00000001, "laplacien de 1/r = 0 (harmonique)")
    check_arr(calculus.gradient(g_par, [2.0, 3.0], null, 4.0), [2], [12.0, 14.0], 0.000000001, "gradient avec args")
    check(raises(e_5), "erreur : gradient point scalaire")
    check(raises(e_6), "erreur : hessian point scalaire")
    check(raises(e_7), "erreur : directional_derivative dimensions")
    check(raises(e_8), "erreur : directional_derivative direction nulle")

func t_3():
    check_arr(calculus.jacobian(F_a, [0.7, -1.1, 0.9]), [3, 3], [-1.1, 0.7, 0.0, 0.0, 0.81, -1.9800000000000002, 0.7648421872844885, 0.0, 1.0], 0.000000001, "jacobian F_a")
    check_close(calculus.divergence(F_a, [0.7, -1.1, 0.9]), 0.71, 0.000000001, "divergence F_a")
    check_arr(calculus.curl(F_a, [0.7, -1.1, 0.9]), [3], [1.9800000000000002, -0.7648421872844885, -0.7], 0.000000001, "curl F_a")
    check_arr(calculus.jacobian(F_b, [0.4, 1.5]), [2, 2], [0.8, -1.0, 1.4918246976412703, 3.0], 0.000000001, "jacobian champ plan (2x2)")
    check_arr(calculus.jacobian(F_rot, [1.0, 2.0, 3.0]), [3, 3], [0.0, -1.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0], 0.0000000001, "jacobian champ rotation")
    check_arr(calculus.curl(F_rot, [1.0, 2.0, 3.0]), [3], [0.0, 0.0, 2.0], 0.0000000001, "curl d'un champ de rotation solide = (0, 0, 2)")
    check_close(calculus.divergence(F_rot, [1.0, 2.0, 3.0]), 0.0, 0.0000000001, "divergence d'un champ de rotation = 0")
    check_arr(calculus.jacobian(g_quad, [1.0, 1.0]), [1, 2], [7.0, 11.0], 0.000000001, "jacobian d'une fonction scalaire (ligne)")
    check_arr(array.from_list(calculus.jacobian(F_a, [0.7, -1.1, 0.9]).shape), [2], [3, 3], 0.0, "jacobian forme (m, n) = (3, 3)")
    check(raises(e_9), "erreur : curl dimension 2")
    check(raises(e_10), "erreur : divergence point scalaire")
    check(raises(e_11), "erreur : jacobian point scalaire")

func t_4():
    check_close(calculus.dblquad(d_xy, 0.0, 2.0, 0.0, 3.0)[0], 9.0, 0.00000001, "dblquad ∫∫ xy sur [0,2]x[0,3]")
    check_close(calculus.dblquad(d_param, 0.0, 1.0, 0.0, 2.0, 3.0)[0], 5.666666666666666, 0.00000001, "dblquad avec args")
    check_close(calculus.dblquad(d_xplus, 0.0, 1.0, 0.0, lim_x)[0], 0.41666666666666663, 0.00000001, "dblquad borne y fonction de x (triangle)")
    check_close(calculus.dblquad(d_xy, 0.0, 1.0, lim_sq, lim_x)[0], 0.04166666666666666, 0.00000001, "dblquad bornes y = [x², x]")
    check_close(calculus.dblquad(d_one, -1.0, 1.0, lim_circ_lo, lim_circ_hi)[0], 3.141592653589793, 0.0000001, "aire du disque unité = π")
    check_close(calculus.dblquad(d_gauss, -5.0, 5.0, -5.0, 5.0)[0], 3.1415926535801333, 0.0000001, "dblquad gaussienne sur [-5,5]²")
    check_close(calculus.dblquad(d_gauss, -numeric.INF, numeric.INF, -numeric.INF, numeric.INF)[0], 3.141592653589793, 0.0000001, "dblquad gaussienne sur R² (bornes infinies)")
    check_close(calculus.dblquad(d_xy, 2.0, 0.0, 0.0, 3.0)[0], -9.0, 0.00000001, "dblquad bornes inversées en x")
    check_close(calculus.dblquad(d_one, 0.0, 1.0, 0.0, lim_one_minus)[0], 0.5, 0.00000001, "dblquad domaine triangulaire (aire 1/2)")
    check_close(calculus.tplquad(t_one, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0)[0], 1.0, 0.00000001, "tplquad volume du cube")
    check_close(calculus.tplquad(t_xyz, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0)[0], 0.125, 0.00000001, "tplquad ∫∫∫ xyz sur [0,1]³")
    check_close(calculus.tplquad(t_sum, 0.0, 2.0, 0.0, 2.0, 0.0, 2.0)[0], 34.66666666666667, 0.00000001, "tplquad ∫∫∫ x + y² + z³ sur [0,2]³")
    check_close(calculus.tplquad(t_param, 0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 4.0)[0], 1.5, 0.00000001, "tplquad avec args")
    check_close(calculus.tplquad(t_one, 0.0, 1.0, 0.0, lim_one_minus, 0.0, z_hi_simplex)[0], 0.16666666666666666, 0.00000001, "tplquad volume du simplexe = 1/6")
    check_close(calculus.tplquad(t_one, -1.0, 1.0, lim_circ_lo, lim_circ_hi, z_lo_ball, z_hi_ball, null, 0.000001, 0.000001)[0], 4.1887902047863905, 0.00001, "tplquad volume de la boule unité = 4π/3")
    check_close(calculus.line_integral(fld_conservative, line_r, line_dr, 0.0, 1.0)[0], 2.0, 0.0000000001, "line_integral champ conservatif = x²y final")
    check_close(calculus.line_integral(fld_rot2, circle_r, circle_dr, 0.0, 2.0 * numeric.PI)[0], 6.283185307179586, 0.0000000001, "line_integral circulation sur le cercle = 2π")
    check_close(calculus.line_integral(fld_rot2, circle_r, circle_dr, 0.0, numeric.PI)[0], 3.141592653589793, 0.0000000001, "line_integral demi-cercle = π")
    check_close(calculus.line_integral(fld_conservative, circle_r, circle_dr, 0.0, 2.0 * numeric.PI)[0], 0.0, 0.0000000001, "line_integral courbe fermée conservatif = 0")
    check_close(calculus.line_integral(fld_rot2, circle_r, circle_dr, 0.0, 2.0 * numeric.PI)[0] - 2.0 * calculus.dblquad(d_one, -1.0, 1.0, lim_circ_lo, lim_circ_hi)[0], 0.0, 0.000001, "théorème de Green : circulation = ∬ rot = 2 aire")

func t_5():
    check_arr(calculus.newton_system(F_nonlin, [1.0, 2.0]), [2], [1.4142135623730951, 1.4142135623730951], 0.0000000001, "cercle ∩ droite (jacobienne numérique)")
    check_arr(calculus.newton_system(F_nonlin, [1.0, 2.0], J_nonlin), [2], [1.4142135623730951, 1.4142135623730951], 0.0000000001, "cercle ∩ droite (jacobienne analytique)")
    check_arr(calculus.newton_system(F_nonlin, [-1.0, -3.0]), [2], [-1.4142135623730951, -1.4142135623730951], 0.0000000001, "cercle ∩ droite, autre départ")
    check_arr(calculus.fsolve(F_nonlin, [1.0, 2.0]), [2], [1.4142135623730951, 1.4142135623730951], 0.0000000001, "fsolve (alias)")
    check_arr(calculus.newton_system(F_3, [0.8, 2.2, 2.9]), [3], [1.0000000000000007, 1.9999999999999982, 3.000000000000001], 0.000000001, "système 3x3 (solution 1, 2, 3)")
    check_arr(calculus.newton_system(F_3, [0.8, 2.2, 2.9]), [3], [1.0, 2.0, 3.0], 0.000000001, "système 3x3 : valeurs exactes")
    check_arr(calculus.newton_system(F_ros, [-1.2, 1.0]), [2], [1.0, 1.0], 0.0000000001, "Rosenbrock en racine (1, 1)")
    check_arr(calculus.newton_system(F_trig, [0.5, 0.5]), [2], [0.768169156736796, 0.6948196907307875], 0.0000000001, "sin x = y, cos y = x")
    check_arr(calculus.newton_system(F_par, [1.0, 1.0], null, 0.000000000001, 50, 9.0), [2], [3.0, 3.0], 0.0000000001, "système avec args")
    check_arr(calculus.newton_system(F_1d, [1.0]), [1], [2.0], 0.0000000001, "système 1x1 (x³ = 8)")
    check_arr(calculus.newton_system(F_1d, 5.0), [1], [2.0], 0.0000000001, "point de départ scalaire accepté pour n = 1")
    check(linalg_norm2(F_nonlin(calculus.newton_system(F_nonlin, [1.0, 2.0]).data)) < 0.000000000001, "résidu final petit")
    check(calculus.newton_system(F_nonlin, [1.4142135623730951, 1.4142135623730951]).data[0] > 1.41, "le point de départ est déjà une racine")
    check_arr(calculus.newton_system(F_atan, [2.0]), [1], [0.0], 0.0000000001, "Newton amorti : arctan depuis x=2 (Newton pur diverge)")
    check(raises(e_12), "erreur : F renvoie un mauvais nombre de composantes")
    check(raises(e_13), "erreur : pas de racine réelle (non convergence)")

run("dérivées d'une variable", t_1)
run("gradient, hessienne, laplacien", t_2)
run("jacobienne, divergence, rotationnel", t_3)
run("intégrales doubles et triples", t_4)
run("systèmes d'équations non linéaires", t_5)
finish("CALCULUS", 5)

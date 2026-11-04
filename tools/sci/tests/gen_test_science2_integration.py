import sys
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import *

S = Suite("science2_integration", "Cohérence entre array, linalg, stats, numeric et calculus (Phase 2).",
          "formes closes et NumPy 2.4", "use array\nuse linalg\nuse stats\nuse numeric\nuse calculus\nuse math")
rng = np.random.default_rng(99)
S.define('''func nll(v, data):
    mu := v[0]
    sigma := v[1]
    s := 0.0
    for d in data:
        s = s + math.ln(sigma) + 0.5 * (d - mu) * (d - mu) / (sigma * sigma)
    return s

func pdf_std(x):
    return stats.norm_pdf(x)

func cdf_std(x):
    return stats.norm_cdf(x)

func sin_fn(x):
    return math.sin(x)

func lin_sys(v):
    return [3.0 * v[0] + v[1] - 9.0, v[0] - 2.0 * v[1] + 4.0]

func cube(x):
    return x * x * x - 3.0 * x + 1.0

func gamma_pdf_2(x):
    return stats.gamma_pdf(x, 2.0, 1.5)

func t_pdf_5(x):
    return stats.t_pdf(x, 5)

func chi2_pdf_4(x):
    return stats.chi2_pdf(x, 4)

func sq(x):
    return x * x
''')
data = np.round(rng.normal(3, 2, 40), 3)
xd = np.linspace(0, 5, 30); yd = 1.5 + 2.0 * xd - 0.3 * xd ** 2 + 0.01 * rng.standard_normal(30)

S.group("régression : polyfit, linregress, lstsq, ols")
S.line(f"xs := {lit(xd.tolist())}")
S.line(f"ys := {lit(yd.tolist())}")
S.line("lr := stats.linregress(xs, ys)")
S.line("pf := numeric.polyfit(xs, ys, 1)")
S.close("pente : polyfit = linregress", "pf.data[0] - lr[0]", 0.0, 1e-11)
S.close("ordonnée : polyfit = linregress", "pf.data[1] - lr[1]", 0.0, 1e-11)
S.line("ls := linalg.lstsq(array.stack([array.ones([30]), array.from_list(xs)], 1), ys)")
S.close("pente : lstsq = linregress", "ls[0].data[1]", float(np.polyfit(xd, yd, 1)[0]), 1e-10)
S.line("ol := stats.ols(array.from_list(xs), ys)")
S.close("pente : ols = linregress", "ol[0].data[1] - lr[0]", 0.0, 1e-10)
S.close("R² : ols = r²", "ol[1] - lr[2] * lr[2]", 0.0, 1e-10)
S.arr("polyfit degré 2 = NumPy", "numeric.polyfit(xs, ys, 2)", np.polyfit(xd, yd, 2), 1e-8)
S.close("résidus du polyfit : somme des carrés = lstsq", "array.sum(array.square(array.sub(numeric.polyval(numeric.polyfit(xs, ys, 1), xs), ys))) - ls[1]", 0.0, 1e-10)

S.group("lois de probabilité et intégration")
S.close("∫ N(0,1) sur R = 1", "numeric.quad(pdf_std, -numeric.INF, numeric.INF)[0]", 1.0, 1e-10)
S.close("∫ N(0,1) jusqu'à 1,96 = cdf(1,96)", "numeric.quad(pdf_std, -numeric.INF, 1.96)[0] - stats.norm_cdf(1.96)", 0.0, 1e-10)
S.close("∫ gamma(2, 1.5) sur [0,∞[ = 1", "numeric.quad(gamma_pdf_2, 0.0, numeric.INF)[0]", 1.0, 1e-9)
S.close("∫ Student(5) sur R = 1", "numeric.quad(t_pdf_5, -numeric.INF, numeric.INF)[0]", 1.0, 1e-9)
S.close("∫ khi-deux(4) jusqu'à 7 = cdf", "numeric.quad(chi2_pdf_4, 0.0, 7.0)[0] - stats.chi2_cdf(7.0, 4)", 0.0, 1e-10)
S.close("dérivée de la cdf normale = pdf", "calculus.derivative(cdf_std, 0.8) - stats.norm_pdf(0.8)", 0.0, 1e-10)
S.close("dérivée de la cdf de Student = pdf", "calculus.derivative(t_cdf_5, 1.3) - stats.t_pdf(1.3, 5)", 0.0, 1e-10)
S.close("norm_ppf inverse de norm_cdf (brentq)", "numeric.brentq(cdf_minus_p, -8.0, 8.0) - stats.norm_ppf(0.9)", 0.0, 1e-11)
S.close("moyenne d'une loi : ∫ x f(x) = 4 (gamma 2, 2)", "numeric.quad(gamma_mean_integrand, 0.0, numeric.INF)[0]", 3.0, 1e-8)
S.define('''func t_cdf_5(x):
    return stats.t_cdf(x, 5)

func cdf_minus_p(x):
    return stats.norm_cdf(x) - 0.9

func gamma_mean_integrand(x):
    return x * stats.gamma_pdf(x, 2.0, 1.5)
''')

S.group("maximum de vraisemblance (stats + calculus)")
mu_hat = float(np.mean(data)); sg_hat = float(np.std(data))
S.line(f"d := {lit(data.tolist())}")
g = "calculus.gradient(nll, [stats.mean(d), stats.std(d)], null, d)"
S.close("gradient du -log-vraisemblance nul au MLE (mu)", f"{g}.data[0]", 0.0, 1e-8)
S.close("gradient du -log-vraisemblance nul au MLE (sigma)", f"{g}.data[1]", 0.0, 1e-8)
n = len(data)
S.arr("hessienne au MLE = information observée", f"calculus.hessian(nll, [stats.mean(d), stats.std(d)], null, d)", np.array([[n / sg_hat ** 2, 0.0], [0.0, 2 * n / sg_hat ** 2]]), 1e-6)
S.close("erreur-type de la moyenne = 1/sqrt(H00) (sigma d'échantillon)", "stats.sem(d) - stats.std(d, 1) / math.sqrt(40.0)", 0.0, 1e-13)

S.group("statistiques multivariées (stats + linalg)")
M = rng.standard_normal((4, 60)); M[1] += 0.8 * M[0]; M[3] -= 0.5 * M[2]
S.line(f"M := {A(M)}")
S.line("C := stats.cov_matrix(M)")
S.close("trace de la covariance = somme des variances", "linalg.trace(C) - array.sum(array.from_list([stats.var(array.row(M, 0), 1), stats.var(array.row(M, 1), 1), stats.var(array.row(M, 2), 1), stats.var(array.row(M, 3), 1)]))", 0.0, 1e-12)
S.arr("valeurs propres de la covariance = NumPy", "linalg.eigvalsh(C)", np.linalg.eigvalsh(np.cov(M)), 1e-12)
S.line("Xc := array.transpose(array.sub(M, array.reshape(array.mean(M, 1), [4, 1])))")
S.line("sv := linalg.svdvals(Xc)")
S.arr("ACP : s²/(n-1) = valeurs propres (décroissant)", "array.div(array.square(sv), 59.0)", np.sort(np.linalg.eigvalsh(np.cov(M)))[::-1], 1e-11)
S.true("covariance définie positive", "linalg.is_positive_definite(C)")
S.close("det(C) = produit des valeurs propres", "linalg.det(C) - array.prod(linalg.eigvalsh(C))", 0.0, 1e-12)
S.arr("corr_matrix : diagonale unité", "array.diag(stats.corr_matrix(M))", np.ones(4), 1e-14)
S.close("cond(C) = λmax/λmin", "linalg.cond(C) - linalg.eigvalsh(C).data[3] / linalg.eigvalsh(C).data[0]", 0.0, 1e-8)

S.group("algèbre linéaire, équations et exponentielle de matrice")
S.arr("newton_system (système linéaire) = solve", "calculus.newton_system(lin_sys, [0.0, 0.0])", np.linalg.solve([[3., 1.], [1., -2.]], [9., -4.]), 1e-10)
S.arr("solve du même système", "linalg.solve([[3.0, 1.0], [1.0, -2.0]], [9.0, -4.0])", np.linalg.solve([[3., 1.], [1., -2.]], [9., -4.]), 1e-13)
S.line("J := calculus.jacobian(lin_sys, [1.0, 1.0])")
S.arr("jacobienne d'un système linéaire = sa matrice", "J", np.array([[3., 1.], [1., -2.]]), 1e-10)
t = 0.9
S.arr("expm(tJ) = rotation d'angle t", f"linalg.expm(array.mul([[0.0, -1.0], [1.0, 0.0]], {t}))", np.array([[np.cos(t), -np.sin(t)], [np.sin(t), np.cos(t)]]), 1e-14)
S.arr("expm(A) x0 résout x' = A x (oscillateur)", f"array.matmul(linalg.expm(array.mul([[0.0, 1.0], [-4.0, 0.0]], 0.7)), [1.0, 0.0])", np.array([np.cos(2 * 0.7), -2 * np.sin(2 * 0.7)]), 1e-13)
S.arr("racines du polynôme caractéristique = valeurs propres", "sorted_real_parts(numeric.polyroots([1.0, -7.0, 14.0, -8.0]))", np.array([1.0, 2.0, 4.0]), 1e-9)
S.define('''func sorted_real_parts(roots):
    out := []
    for r in roots:
        append(out, r[0])
    return array.sort(array.from_list(out))
''')
S.arr("valeurs propres de la matrice compagnon = racines", "sorted_real_parts(linalg.eigvals([[7.0, -14.0, 8.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]]))", np.array([1.0, 2.0, 4.0]), 1e-9)
S.close("racine de x³ - 3x + 1 : brentq = polyroots", "numeric.brentq(cube, 0.0, 1.0) - 0.34729635533386066", 0.0, 1e-12)

S.group("splines, dérivées et intégrales")
xk = np.linspace(0, math_pi := np.pi, 12)
S.line(f"xk := {lit(xk.tolist())}")
S.line("yk := array.sin(xk)")
S.line("cs := numeric.CubicSpline(xk, yk.data)")
S.close("spline de sin : valeur", "cs.eval(1.234)", float(np.sin(1.234)), 2e-5)
S.close("spline de sin : dérivée = cos", "cs.derivative(1.234)", float(np.cos(1.234)), 2e-4)
S.close("spline de sin : intégrale ≈ 2", "cs.integrate(0.0, numeric.PI)", 2.0, 2e-5)
S.close("intégrale de la spline = quad de la spline", "cs.integrate(0.4, 2.7) - numeric.quad(spl, 0.4, 2.7)[0]", 0.0, 1e-9)
S.close("dérivée de la spline = dérivée numérique de la spline", "cs.derivative(1.1) - calculus.derivative(spl, 1.1)", 0.0, 1e-8)
S.close("dérivée seconde de la spline (linéaire par morceaux) = dérivée numérique, pas intérieur à la maille", "cs.derivative(1.0, 2) - calculus.second_derivative(spl, 1.0, 0.02)", 0.0, 1e-6)
S.define('''func spl(x):
    return cs_global.eval(x)
''')
S.close("trapz sin (1001 pts) ≈ 2 ; simpson plus précis", "abs_val(numeric.simpson(array.sin(array.linspace(0.0, numeric.PI, 1001)).data, numeric.PI / 1000.0) - 2.0) / abs_val(numeric.trapz(array.sin(array.linspace(0.0, numeric.PI, 1001)).data, null, numeric.PI / 1000.0) - 2.0)", 0.0, 0.01)

text = S.render()
# variable globale pour la spline (pas de fermeture) : déclarée après les définitions
text = text.replace("func t_1():", "cs_global := numeric.CubicSpline(" + lit(np.linspace(0, np.pi, 12).tolist()) + ", array.sin(array.from_list(" + lit(np.linspace(0, np.pi, 12).tolist()) + ")).data)\n\nfunc t_1():", 1)
text = text.replace("    cs := numeric.CubicSpline(xk, yk.data)\n", "    cs := cs_global\n")
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'tests', 'test_science2_integration.al'), 'w', encoding='utf-8').write(text)
print("lignes :", text.count("\n"))

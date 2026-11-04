# =============================================================================
# ALEX - tests du module stdlib/science2_integration/science2_integration.al
# Cohérence entre array, linalg, stats, numeric et calculus (Phase 2).
# Les valeurs attendues proviennent de formes closes et NumPy 2.4 (référence indépendante),
# jamais d'un calcul avec le module testé.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/test_science2_integration.al
# Code de sortie 0 si tout passe, 1 sinon.
# =============================================================================
use array
use linalg
use stats
use numeric
use calculus
use math
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

func nll(v, data):
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

func t_cdf_5(x):
    return stats.t_cdf(x, 5)

func cdf_minus_p(x):
    return stats.norm_cdf(x) - 0.9

func gamma_mean_integrand(x):
    return x * stats.gamma_pdf(x, 2.0, 1.5)

func sorted_real_parts(roots):
    out := []
    for r in roots:
        append(out, r[0])
    return array.sort(array.from_list(out))

func spl(x):
    return cs_global.eval(x)


cs_global := numeric.CubicSpline([0.0, 0.28559933214452665, 0.5711986642890533, 0.8567979964335799, 1.1423973285781066, 1.4279966607226333, 1.7135959928671598, 1.9991953250116865, 2.284794657156213, 2.5703939893007397, 2.8559933214452666, 3.141592653589793], array.sin(array.from_list([0.0, 0.28559933214452665, 0.5711986642890533, 0.8567979964335799, 1.1423973285781066, 1.4279966607226333, 1.7135959928671598, 1.9991953250116865, 2.284794657156213, 2.5703939893007397, 2.8559933214452666, 3.141592653589793])).data)

func t_1():
    xs := [0.0, 0.1724137931034483, 0.3448275862068966, 0.5172413793103449, 0.6896551724137931, 0.8620689655172414, 1.0344827586206897, 1.206896551724138, 1.3793103448275863, 1.5517241379310347, 1.7241379310344829, 1.896551724137931, 2.0689655172413794, 2.241379310344828, 2.413793103448276, 2.586206896551724, 2.7586206896551726, 2.931034482758621, 3.1034482758620694, 3.2758620689655173, 3.4482758620689657, 3.620689655172414, 3.793103448275862, 3.9655172413793105, 4.137931034482759, 4.310344827586207, 4.482758620689656, 4.655172413793104, 4.827586206896552, 5.0]
    ys := [1.4959610514724415, 1.8506229438862878, 2.146503359008285, 2.466332521939097, 2.7395489324017013, 3.018162449602103, 3.244033025613273, 3.483777557099786, 3.696319897122851, 3.877856329022449, 4.056592902623718, 4.2098848874597445, 4.358527973876942, 4.482509704517238, 4.57675050299395, 4.66933331552702, 4.728426093288229, 4.779569035170096, 4.798253322878793, 4.820602027028398, 4.822630460660429, 4.809643064198018, 4.785120065681256, 4.716126800764688, 4.64003370478503, 4.5504469061729855, 4.422964901651424, 4.309639567531317, 4.154814698369097, 3.994262794197575]
    lr := stats.linregress(xs, ys)
    pf := numeric.polyfit(xs, ys, 1)
    check_close(pf.data[0] - lr[0], 0.0, 0.00000000001, "pente : polyfit = linregress")
    check_close(pf.data[1] - lr[1], 0.0, 0.00000000001, "ordonnée : polyfit = linregress")
    ls := linalg.lstsq(array.stack([array.ones([30]), array.from_list(xs)], 1), ys)
    check_close(ls[0].data[1], 0.4979754013333868, 0.0000000001, "pente : lstsq = linregress")
    ol := stats.ols(array.from_list(xs), ys)
    check_close(ol[0].data[1] - lr[0], 0.0, 0.0000000001, "pente : ols = linregress")
    check_close(ol[1] - lr[2] * lr[2], 0.0, 0.0000000001, "R² : ols = r²")
    check_arr(numeric.polyfit(xs, ys, 2), [3], [-0.2997789341067969, 1.996870071867372, 1.505895983707905], 0.00000001, "polyfit degré 2 = NumPy")
    check_close(array.sum(array.square(array.sub(numeric.polyval(numeric.polyfit(xs, ys, 1), xs), ys))) - ls[1], 0.0, 0.0000000001, "résidus du polyfit : somme des carrés = lstsq")

func t_2():
    check_close(numeric.quad(pdf_std, -numeric.INF, numeric.INF)[0], 1.0, 0.0000000001, "∫ N(0,1) sur R = 1")
    check_close(numeric.quad(pdf_std, -numeric.INF, 1.96)[0] - stats.norm_cdf(1.96), 0.0, 0.0000000001, "∫ N(0,1) jusqu'à 1,96 = cdf(1,96)")
    check_close(numeric.quad(gamma_pdf_2, 0.0, numeric.INF)[0], 1.0, 0.000000001, "∫ gamma(2, 1.5) sur [0,∞[ = 1")
    check_close(numeric.quad(t_pdf_5, -numeric.INF, numeric.INF)[0], 1.0, 0.000000001, "∫ Student(5) sur R = 1")
    check_close(numeric.quad(chi2_pdf_4, 0.0, 7.0)[0] - stats.chi2_cdf(7.0, 4), 0.0, 0.0000000001, "∫ khi-deux(4) jusqu'à 7 = cdf")
    check_close(calculus.derivative(cdf_std, 0.8) - stats.norm_pdf(0.8), 0.0, 0.0000000001, "dérivée de la cdf normale = pdf")
    check_close(calculus.derivative(t_cdf_5, 1.3) - stats.t_pdf(1.3, 5), 0.0, 0.0000000001, "dérivée de la cdf de Student = pdf")
    check_close(numeric.brentq(cdf_minus_p, -8.0, 8.0) - stats.norm_ppf(0.9), 0.0, 0.00000000001, "norm_ppf inverse de norm_cdf (brentq)")
    check_close(numeric.quad(gamma_mean_integrand, 0.0, numeric.INF)[0], 3.0, 0.00000001, "moyenne d'une loi : ∫ x f(x) = 4 (gamma 2, 2)")

func t_3():
    d := [3.165, 2.071, 3.101, 4.372, -0.514, 6.369, 2.084, 1.807, 0.906, 4.864, 4.35, 5.489, 4.786, 3.526, 3.657, 4.87, 1.245, 2.908, 3.764, 2.095, 4.443, 2.296, 4.346, 3.281, 3.925, -0.035, 1.279, 5.689, 3.356, 2.837, 4.927, 4.502, 2.906, 1.714, 6.922, 4.381, -0.144, 4.679, 4.537, 4.628]
    check_close(calculus.gradient(nll, [stats.mean(d), stats.std(d)], null, d).data[0], 0.0, 0.00000001, "gradient du -log-vraisemblance nul au MLE (mu)")
    check_close(calculus.gradient(nll, [stats.mean(d), stats.std(d)], null, d).data[1], 0.0, 0.00000001, "gradient du -log-vraisemblance nul au MLE (sigma)")
    check_arr(calculus.hessian(nll, [stats.mean(d), stats.std(d)], null, d), [2, 2], [13.546807355499155, 0.0, 0.0, 27.09361471099831], 0.000001, "hessienne au MLE = information observée")
    check_close(stats.sem(d) - stats.std(d, 1) / math.sqrt(40.0), 0.0, 0.0000000000001, "erreur-type de la moyenne = 1/sqrt(H00) (sigma d'échantillon)")

func t_4():
    M := array.from_list([[2.036301117437624, 1.8473727967541151, 0.9771522953659267, 0.543007430953947, 0.5035986246294768, -0.965118862301999, -1.2554508744429693, 0.33471993219360385, -0.4471932429602081, -0.7767197364921657, -0.08032239925586591, -0.07247309911058455, 0.1892233430503906, -0.7395996786002964, 0.017307909715080432, -1.2393075674663567, 1.2268322908637828, 1.519203680454561, -1.1043989801464928, 0.427307314303465, -0.22097442119104255, 0.11371542572807476, 0.06285244344475456, 1.1930882065047852, 0.5532716597450533, -0.8685173899176807, 0.080181498861998, -0.01756261021500492, -0.7982291043424057, 0.20433811797656493, -0.0227893422461982, 1.3592740135166907, -0.18787240672424627, 0.44099290783818174, -2.2478703435200544, -1.6776106800597885, 0.3272304519258087, 0.12904907466544088, 0.9088191909442948, -1.1522425892487587, -0.2848192560217445, -2.4923775375131645, -0.8365971034135913, -0.4333366357309742, -0.09690122373654823, -0.5547818918592373, 0.9541040611095484, -1.4478160675388965, -1.2830970120909861, 0.4603569742486016, -0.3791110582799781, 1.3365512350612998, 0.6891221265155556, 0.33266478425463064, -1.7140859351609357, -0.6176098299871197, 0.2679857705631532, -0.6438451519832749, 0.282144611996768, 0.2992914933158716], [0.7977881525119042, 0.36418028245122147, 1.7492174488130696, 0.48273263684612544, 0.4578608130661351, 0.18934238473984533, 0.7288457747465149, -2.5415754254836593, 1.096843206134055, 0.37677773225667055, -0.3600267563725784, 1.1216713192739065, 0.06788063494408902, 1.005436948687862, 1.153151122597869, -0.5789835998778603, 0.3589407428224447, 1.3027372767822636, -1.7590317729499225, -0.3601447476213594, 0.003009754866377834, -0.037127242058247856, -0.6169589566048236, 2.603555639401258, -0.11065383739625168, -0.7238574011256952, 0.06162418605433137, -2.2046899782655887, 1.9777837886571086, -0.41256661983007403, 0.7201282601773801, -1.063047349414059, -0.31808500030848713, -1.2860349679694223, -2.305966758400927, -0.07658751491414106, 1.0429487656924232, 0.723197929046473, 1.2277872615055356, -2.676918742904273, -1.3673679579421059, -1.4478993248640668, 0.6902558403201886, 0.1079556566704396, 0.4915740548059342, 0.10129464954273304, 1.46181050108073, -0.6773502402988507, -2.1317988309582185, 1.3410903733867374, -1.2050900406828329, -0.39984795945817453, 0.6800893853768838, -1.0678624250229487, -2.4529020340934604, -0.39232056659908265, -0.6080463880319842, -1.4047035226833762, 0.6816228177542873, 1.349823953886124], [0.7310893055581689, 0.8983072502683203, -1.4831765724138763, 0.6540635742377227, -0.013031121769306698, -0.7168441579606296, -0.30173109124264946, -0.3825615877848825, -1.0489907328214272, -1.9498243038154193, 0.37042264732081953, 0.2559244137362894, 1.3296450931246544, 1.1394941236925689, 0.18493780066614643, 0.8509535992723561, 1.5387743367444906, -0.6947899262380501, -0.26244370809270195, 0.26983054889583985, -1.3582490776030909, -1.0840985956159908, 0.6612512743893048, -0.43087797230723546, 0.4531951624560732, -0.1146102717957628, 1.2341099081587472, 0.27451118205949626, 0.13319664843919923, -0.27696227386773986, -1.0243603519203888, -1.5477663345965869, 2.667341336544985, 0.3151470595597514, 1.0298744873788546, -0.8841897743744551, 0.4701230061095244, 0.381848546415644, -0.8641217159633715, 2.0180541910199876, 1.492376087034972, -0.16053115860295825, 1.1175111038811083, 1.1862975352552152, 0.5910591660034069, 0.5411890837543263, 0.14587330428678436, 0.010899614666058148, -1.4343704870693252, -0.4250083981331064, 0.46592644513289805, -0.2472689805042551, 1.1057827099104818, 0.10071685113584257, -0.8349252381008445, -1.2487463483728576, -0.9250005002960514, -0.03480181222900226, -0.21331152270579018, -2.7195318181707417], [0.17700849116350093, 1.1436723861228324, 0.04766816223579917, 0.13804530816083527, -0.7652951841775937, 1.6605655527867222, -0.6468579945720746, 0.012321352582065903, 1.9639071841592384, 1.911175608789148, -0.500561266868249, 1.1083404897605944, -0.0245476787908101, 0.4948161515421178, 1.4439837394858448, 1.2081291308891406, -1.6574827427803198, -0.4853543259433164, 0.6606004967894082, -0.43407416914654473, -2.469699270832827, 1.5180734561147387, -1.5954368361876496, -0.08005731677109218, -0.9097460570527822, -0.29236719163585284, 0.007829847288580827, -1.946658107343515, -0.3811419129916808, -1.3978548671959816, 0.177382126975606, 1.0379309975166304, -0.3639534440458374, -0.3998022045623914, 1.9666228126445622, 1.373271487170738, 1.000932591522738, 0.5481968207166734, 0.17429160764205065, -1.4859013595535004, -1.6599644885334432, 0.1121289757434798, -3.6021002844473275, -1.079779001754838, -0.3275816845523311, -1.667095467794963, -1.145717250313914, 0.39874367001723016, 1.3230103479198474, 0.5235755421902218, -2.5072941351357554, 1.9811250647998293, -0.7863792072546775, 2.961515947451845, 0.37345701330515146, 1.162621909135014, 0.013650834238720044, 0.6524183005781048, 1.8241159825123199, 1.8473623700205395]])
    C := stats.cov_matrix(M)
    check_close(linalg.trace(C) - array.sum(array.from_list([stats.var(array.row(M, 0), 1), stats.var(array.row(M, 1), 1), stats.var(array.row(M, 2), 1), stats.var(array.row(M, 3), 1)])), 0.0, 0.000000000001, "trace de la covariance = somme des variances")
    check_arr(linalg.eigvalsh(C), [4], [0.5786283232646647, 0.7193264687874319, 1.731180748590118, 2.0456883184593035], 0.000000000001, "valeurs propres de la covariance = NumPy")
    Xc := array.transpose(array.sub(M, array.reshape(array.mean(M, 1), [4, 1])))
    sv := linalg.svdvals(Xc)
    check_arr(array.div(array.square(sv), 59.0), [4], [2.0456883184593035, 1.731180748590118, 0.7193264687874319, 0.5786283232646647], 0.00000000001, "ACP : s²/(n-1) = valeurs propres (décroissant)")
    check(linalg.is_positive_definite(C), "covariance définie positive")
    check_close(linalg.det(C) - array.prod(linalg.eigvalsh(C)), 0.0, 0.000000000001, "det(C) = produit des valeurs propres")
    check_arr(array.diag(stats.corr_matrix(M)), [4], [1.0, 1.0, 1.0, 1.0], 0.00000000000001, "corr_matrix : diagonale unité")
    check_close(linalg.cond(C) - linalg.eigvalsh(C).data[3] / linalg.eigvalsh(C).data[0], 0.0, 0.00000001, "cond(C) = λmax/λmin")

func t_5():
    check_arr(calculus.newton_system(lin_sys, [0.0, 0.0]), [2], [2.0, 3.0], 0.0000000001, "newton_system (système linéaire) = solve")
    check_arr(linalg.solve([[3.0, 1.0], [1.0, -2.0]], [9.0, -4.0]), [2], [2.0, 3.0], 0.0000000000001, "solve du même système")
    J := calculus.jacobian(lin_sys, [1.0, 1.0])
    check_arr(J, [2, 2], [3.0, 1.0, 1.0, -2.0], 0.0000000001, "jacobienne d'un système linéaire = sa matrice")
    check_arr(linalg.expm(array.mul([[0.0, -1.0], [1.0, 0.0]], 0.9)), [2, 2], [0.6216099682706644, -0.7833269096274834, 0.7833269096274834, 0.6216099682706644], 0.00000000000001, "expm(tJ) = rotation d'angle t")
    check_arr(array.matmul(linalg.expm(array.mul([[0.0, 1.0], [-4.0, 0.0]], 0.7)), [1.0, 0.0]), [2], [0.16996714290024104, -1.9708994599769203], 0.0000000000001, "expm(A) x0 résout x' = A x (oscillateur)")
    check_arr(sorted_real_parts(numeric.polyroots([1.0, -7.0, 14.0, -8.0])), [3], [1.0, 2.0, 4.0], 0.000000001, "racines du polynôme caractéristique = valeurs propres")
    check_arr(sorted_real_parts(linalg.eigvals([[7.0, -14.0, 8.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0]])), [3], [1.0, 2.0, 4.0], 0.000000001, "valeurs propres de la matrice compagnon = racines")
    check_close(numeric.brentq(cube, 0.0, 1.0) - 0.34729635533386066, 0.0, 0.000000000001, "racine de x³ - 3x + 1 : brentq = polyroots")

func t_6():
    xk := [0.0, 0.28559933214452665, 0.5711986642890533, 0.8567979964335799, 1.1423973285781066, 1.4279966607226333, 1.7135959928671598, 1.9991953250116865, 2.284794657156213, 2.5703939893007397, 2.8559933214452666, 3.141592653589793]
    yk := array.sin(xk)
    cs := cs_global
    check_close(cs.eval(1.234), 0.9438182093746337, 0.00002, "spline de sin : valeur")
    check_close(cs.derivative(1.234), 0.33046510807172985, 0.0002, "spline de sin : dérivée = cos")
    check_close(cs.integrate(0.0, numeric.PI), 2.0, 0.00002, "spline de sin : intégrale ≈ 2")
    check_close(cs.integrate(0.4, 2.7) - numeric.quad(spl, 0.4, 2.7)[0], 0.0, 0.000000001, "intégrale de la spline = quad de la spline")
    check_close(cs.derivative(1.1) - calculus.derivative(spl, 1.1), 0.0, 0.00000001, "dérivée de la spline = dérivée numérique de la spline")
    check_close(cs.derivative(1.0, 2) - calculus.second_derivative(spl, 1.0, 0.02), 0.0, 0.000001, "dérivée seconde de la spline (linéaire par morceaux) = dérivée numérique, pas intérieur à la maille")
    check_close(abs_val(numeric.simpson(array.sin(array.linspace(0.0, numeric.PI, 1001)).data, numeric.PI / 1000.0) - 2.0) / abs_val(numeric.trapz(array.sin(array.linspace(0.0, numeric.PI, 1001)).data, null, numeric.PI / 1000.0) - 2.0), 0.0, 0.01, "trapz sin (1001 pts) ≈ 2 ; simpson plus précis")

run("régression : polyfit, linregress, lstsq, ols", t_1)
run("lois de probabilité et intégration", t_2)
run("maximum de vraisemblance (stats + calculus)", t_3)
run("statistiques multivariées (stats + linalg)", t_4)
run("algèbre linéaire, équations et exponentielle de matrice", t_5)
run("splines, dérivées et intégrales", t_6)
finish("SCIENCE2_INTEGRATION", 6)

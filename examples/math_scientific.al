# Exemple : calcul scientifique avec les fonctions avancées de math
# (isqrt, fsum, prod, log1p, expm1, hypot, dist, fmod, remainder, modf, frexp, ldexp,
#  copysign, isnan/isinf/isfinite, fma, erf, gamma, lgamma, asinh/atanh)
# Lancer depuis la racine du projet : ./alex run examples/math_scientific.al
use math
use collections
use core

func expect(cond, message):
    if not cond:
        raise("AssertionError", message)

func expect_close(actual, expected, tol, label):
    d := actual - expected
    if d < 0:
        d = 0 - d
    if d > tol:
        raise("AssertionError", f"{label} : obtenu {actual}, attendu {expected}")

# --- 1. Nettoyage de données : nan / inf ------------------------------------
print("=== Valeurs non finies (isnan / isinf / isfinite) ===")
readings := [1.5, math.NAN, 2.5, math.INF, 0 - math.INF, 4.0]
clean := []
nan_count := 0
inf_count := 0
for v in readings:
    if math.isnan(v):
        nan_count += 1
    if math.isinf(v):
        inf_count += 1
    if math.isfinite(v):
        collections.append(clean, v)
print(f"{nan_count} NaN, {inf_count} infinis, {core.len(clean)} valeurs conservées : {clean}")
expect(nan_count == 1 and inf_count == 2 and core.len(clean) == 3, "tri des valeurs non finies")
expect(math.fsum(clean) == 8.0, "somme des valeurs saines")
expect(math.isinf(math.exp(1000)), "exp(1000) déborde en infini")
expect(math.isnan(math.INF - math.INF), "inf - inf = nan")

# --- 2. Sommes exactes et produits ------------------------------------------
print("")
print("=== fsum / prod ===")
naive := 0.0
for k in 0..10:
    naive = naive + 0.1
tenths := [0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]
print(f"somme naïve de dix 0.1 : {naive == 1.0}   fsum : {math.fsum(tenths) == 1.0}")
expect(naive != 1.0, "la somme naïve accumule l'erreur d'arrondi")
expect(math.fsum(tenths) == 1.0, "fsum est exacte")
expect(math.fsum([10.0 ** 100, 1.0, 0 - 10.0 ** 100]) == 1.0, "fsum survit à l'absorption catastrophique")
digits := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
print(f"10! = prod(1..10) = {math.prod(digits)}")
expect(math.prod(digits) == 3628800, "prod(1..10) = 10!")
expect(math.prod([]) == 1, "produit vide = 1")
expect(math.prod([2, 8, 4]) == 64, "prod([2, 8, 4])")
expect_close(math.pow(math.prod([2, 8, 4]), 1.0 / 3), 4.0, 0.000000000001, "moyenne géométrique par prod")

# --- 3. Précision près de zéro : log1p / expm1 ------------------------------
print("")
print("=== log1p / expm1 pour de très petits taux ===")
tiny := 0.0000000001
naive_log := math.ln(1 + tiny)
exact_log := math.log1p(tiny)
print(f"ln(1 + 1e-10) naïf = {naive_log}   log1p(1e-10) = {exact_log}")
expect_close(exact_log, 0.000000000099999999995, 0.0000000000000000000001, "log1p(1e-10)")
expect(math.abs(naive_log - exact_log) > 0.00000000000000000001, "le calcul naïf perd des chiffres")
expect_close(math.expm1(tiny), 0.000000000100000000005, 0.0000000000000000000001, "expm1(1e-10)")
# Intérêt journalier de 0.001 % : 365 jours composés, sans perte de précision.
daily := 0.00001
yearly := math.expm1(365 * math.log1p(daily))
print(f"rendement annuel de 0.001 %/jour composé = {yearly * 100} %")
expect_close(yearly, 0.003656, 0.000001, "rendement annuel")

# --- 4. Racine entière, triplets pythagoriciens ------------------------------
print("")
print("=== isqrt et hypot : triplets pythagoriciens (c <= 30) ===")
found := 0
for a in 1..30:
    for b in a + 1..30:
        c2 := a * a + b * b
        c := math.isqrt(c2)
        if c * c == c2 and c <= 30:
            found += 1
            expect(math.hypot(a, b) == c, f"hypot({a}, {b}) = {c}")
print(f"{found} triplets trouvés")
expect(found == 11, "11 triplets pythagoriciens avec c <= 30")
big := 999999999999999999
print(f"isqrt(10^18 - 1) = {math.isqrt(big)}  (floor(sqrt) flottant donnerait {math.floor(math.sqrt(big))})")
expect(math.isqrt(big) == 999999999, "isqrt est exacte sur les grands entiers")
expect(math.isqrt(1000000000000000000) == 1000000000, "isqrt(10^18)")

# --- 5. Distances sans débordement -------------------------------------------
print("")
print("=== hypot / dist ===")
d3 := math.dist([1, 2, 3], [4, 6, 15])
print(f"distance 3D = {d3}")
expect(d3 == 13.0, "dist en 3 dimensions")
huge := 3.0 * 10.0 ** 200
print(f"hypot(3e200, 4e200) / 1e200 = {math.hypot(huge, 4.0 * 10.0 ** 200) / 10.0 ** 200}   (x*x aurait débordé)")
expect_close(math.hypot(huge, 4.0 * 10.0 ** 200) / 10.0 ** 200, 5.0, 0.000000000000001, "hypot sans débordement")
expect(math.dist([1, 2], [1, 2, 3]) == null, "dimensions différentes -> null")

# --- 6. Angles : fmod et remainder --------------------------------------------
print("")
print("=== Normalisation d'angles ===")
angles := [725, -30, 270, 360, 0, 180]
for ang in angles:
    wrapped := math.fmod(ang, 360)
    if wrapped < 0:
        wrapped = wrapped + 360
    signed := math.remainder(ang, 360)
    print(f"{ang} degrés -> [0, 360) : {wrapped}    (-180, 180] : {signed}")
expect(math.fmod(725, 360) == 5, "fmod(725, 360)")
expect(math.fmod(-30, 360) == -30, "fmod garde le signe du dividende")
expect(math.remainder(270, 360) == -90, "remainder(270, 360) = -90")
expect(math.remainder(725, 360) == 5, "remainder(725, 360)")

# --- 7. Découpage d'un nombre : modf, frexp, ldexp, copysign -----------------
print("")
print("=== modf / frexp / ldexp / copysign ===")
hours := 7.75
parts := math.modf(hours)
print(f"{hours} h = {parts[1]} h {parts[0] * 60} min")
expect(parts[1] == 7.0 and parts[0] * 60 == 45.0, "7.75 h = 7 h 45 min")
neg := math.modf(-2.25)
expect(neg[0] == -0.25 and neg[1] == -2.0, "modf garde le signe")
decomposed := math.frexp(48)
print(f"48 = {decomposed[0]} * 2^{decomposed[1]}")
expect(decomposed[0] == 0.75 and decomposed[1] == 6, "frexp(48)")
expect(math.ldexp(decomposed[0], decomposed[1]) == 48.0, "ldexp inverse frexp")
expect(math.ldexp(1, 10) == 1024.0, "ldexp(1, 10)")
expect(math.exp2(10) == 1024.0 and math.exp2(-2) == 0.25, "exp2 exact sur les entiers")
expect(math.copysign(3, -0.5) == -3.0 and math.copysign(-3, 0.5) == 3.0, "copysign")

# --- 8. fma : ne pas perdre l'erreur d'arrondi -------------------------------
print("")
print("=== fma ===")
plain := 0.1 * 10 - 1
fused := math.fma(0.1, 10, -1)
print(f"0.1 * 10 - 1 = {plain}    fma(0.1, 10, -1) = {fused}")
expect(plain == 0.0, "l'expression naïve arrondit le produit")
expect(fused > 0.00000000000000005 and fused < 0.00000000000000006, "fma garde 5.55e-17")

# --- 9. Loi normale avec erf ---------------------------------------------------
print("")
print("=== Loi normale : règle 68-95-99.7 ===")
sqrt2 := math.sqrt(2)
p1 := math.erf(1 / sqrt2)
p2 := math.erf(2 / sqrt2)
p3 := math.erf(3 / sqrt2)
print(f"P(|X| <= 1 ecart-type) = {p1}\nP(|X| <= 2) = {p2}\nP(|X| <= 3) = {p3}")
expect_close(p1, 0.6826894921370859, 0.000000000001, "68 %")
expect_close(p2, 0.9544997361036416, 0.000000000001, "95 %")
expect_close(p3, 0.9973002039367398, 0.000000000001, "99.7 %")
cdf_one := 0.5 * (1 + math.erf(1 / sqrt2))
expect_close(cdf_one, 0.8413447460685429, 0.000000000001, "phi(1)")
expect_close(math.erf(0.7) + math.erfc(0.7), 1.0, 0.000000000000001, "erf + erfc = 1")
# Queue extrême : erfc garde sa précision relative là où 1 - erf donnerait 0.
tail := math.erfc(6)
print(f"erfc(6) = {tail}   (1 - erf(6) = {1 - math.erf(6)})")
expect_close(tail / 0.00000000000000002151973671249892, 1.0, 0.0000000000001, "erfc(6) en relatif")

# --- 10. Gamma et volumes de boules ------------------------------------------
print("")
print("=== gamma / lgamma ===")
expect_close(math.gamma(5), 24.0, 0.0000000000001, "gamma(5) = 4!")
expect_close(math.gamma(0.5) ** 2, math.PI, 0.000000000001, "gamma(1/2)^2 = pi")
expect_close(math.gamma(5.5), 52.34277778455352, 0.000000000001, "gamma(5.5)")
expect(math.gamma(0) == null and math.gamma(-3) == null, "gamma aux pôles = null")
# Volume de la boule unité en dimension n : pi^(n/2) / gamma(n/2 + 1)
dims := [2, 3, 4, 5, 7]
volumes := [3.141592653589793, 4.1887902047863905, 4.934802200544679, 5.263789013914325, 4.7247659703314016]
i := 0
for n in dims:
    vol := math.pow(math.PI, n / 2) / math.gamma(n / 2 + 1)
    print(f"volume de la boule unité en dimension {n} = {vol}")
    expect_close(vol, volumes[i], 0.000000000001, f"boule de dimension {n}")
    i += 1
# ln C(1000, 500) via lgamma, impossible avec des entiers 64 bits.
ln_binom := math.lgamma(1001) - 2 * math.lgamma(501)
print(f"ln C(1000, 500) = {ln_binom}   (C(1000,500) ~ 10^{ln_binom / math.LN10})")
expect_close(ln_binom, 689.4672615678512, 0.00000001, "ln C(1000, 500)")

# --- 11. Réciproques hyperboliques : addition relativiste des vitesses --------
print("")
print("=== atanh / asinh / acosh : rapidité relativiste ===")
v1 := 0.5
v2 := 0.5
rapidity := math.atanh(v1) + math.atanh(v2)
combined := math.tanh(rapidity)
print(f"0.5 c + 0.5 c = {combined} c  (et non 1.0 c)")
expect_close(combined, 0.8, 0.000000000000001, "addition relativiste des vitesses")
expect(math.atanh(1) == null, "atanh(1) hors domaine -> null")
expect_close(math.sinh(math.asinh(2.5)), 2.5, 0.000000000001, "sinh(asinh(x))")
expect_close(math.cosh(math.acosh(3.5)), 3.5, 0.000000000001, "cosh(acosh(x))")
expect_close(math.asinh(1), 0.881373587019543, 0.000000000000001, "asinh(1) = ln(1 + sqrt 2)")

print("")
print("OK : math_scientific")

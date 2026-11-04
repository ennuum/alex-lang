# Exemple : moyennes, normalisation, interpolation et échelles logarithmiques
# Lancer depuis la racine du projet : ./alex run examples/math_statistics.al
use math

func expect(cond, message):
    if not cond:
        raise("AssertionError", message)

# --- 1. Trois moyennes : arithmétique >= géométrique >= harmonique -----------
print("=== mean / geometric_mean / harmonic_mean ===")
pairs := [[1, 2], [3, 12], [5, 5], [2, 50], [10, 40]]
for p in pairs:
    am := math.mean(p[0], p[1])
    gm := math.geometric_mean(p[0], p[1])
    hm := math.harmonic_mean(p[0], p[1])
    print(f"({p[0]}, {p[1]}) : arith={am}  géom={gm}  harm={hm}")
    expect(am >= gm - 0.000000000001, f"AM >= GM pour {p}")
    expect(gm >= hm - 0.000000000001, f"GM >= HM pour {p}")
    expect(math.is_close(gm * gm, p[0] * p[1]), f"GM^2 = a*b pour {p}")
    expect(math.is_close(am * hm, gm * gm), f"AM * HM = GM^2 pour {p}")

# Vitesse moyenne aller-retour : 60 km/h à l'aller, 40 km/h au retour
average_speed := math.harmonic_mean(60, 40)
print(f"vitesse moyenne (60 km/h puis 40 km/h) = {average_speed} km/h")
expect(math.is_close(average_speed, 48.0), "moyenne harmonique 60/40 = 48")

# Croissance moyenne : +10 % puis +21 % => facteur moyen géométrique
growth := math.geometric_mean(1.10, 1.21)
print(f"croissance annuelle moyenne = {(growth - 1) * 100} %")
expect(math.is_close(growth, 1.1536897329871667), "croissance moyenne")
expect(math.is_close(growth * growth, 1.10 * 1.21), "le facteur moyen appliqué 2 fois redonne le total")
expect(math.geometric_mean(-4, 9) == null, "moyenne géométrique d'un négatif = null")

# --- 2. Normalisation min-max et interpolation linéaire ----------------------
print("")
print("=== Normalisation et lerp ===")
data := [12, 18, 25, 40, 7]
lo := data[0]
hi := data[0]
for v in data:
    lo = math.min(lo, v)
    hi = math.max(hi, v)
print(f"min={lo}  max={hi}")
for v in data:
    t := (v - lo) / (hi - lo)
    rebuilt := math.lerp(lo, hi, t)
    color := math.round(math.lerp(0, 255, t))
    print(f"valeur={v}  t={t}  niveau(0-255)={color}")
    expect(math.is_close(rebuilt, v), f"lerp reconstruit {v}")
expect(math.lerp(0, 10, 0.5) == 5, "lerp(0, 10, 0.5)")
expect(math.lerp(10, 20, 0.25) == 12.5, "lerp(10, 20, 0.25)")

# --- 3. Écrêtage de valeurs aberrantes (clamp) -------------------------------
print("")
print("=== clamp : écrêtage à [0, 100] ===")
measures := [-5, 12, 250, 47, 999]
total := 0
for m in measures:
    c := math.clamp(m, 0, 100)
    total += c
print(f"somme des mesures écrêtées = {total}")
expect(total == 0 + 12 + 100 + 47 + 100, "somme après écrêtage")

# --- 4. Finance : intérêts composés, continus, temps de doublement -----------
print("")
print("=== Intérêts ===")
capital := 1000
rate := 0.05
years := 10
compound := capital * math.pow(1 + rate, years)
continuous := capital * math.exp(rate * years)
doubling := math.ln(2) / math.ln(1 + rate)
print(f"1000 à 5 % pendant 10 ans : composé={compound}  continu={continuous}")
print(f"temps de doublement = {doubling} ans  (règle des 72 : {72 / 5})")
expect(math.is_close(compound, 1628.894626777442, 0.000000000001), "intérêts composés")
expect(math.is_close(continuous, 1648.7212707001282, 0.000000000001), "intérêts continus")
expect(math.is_close(doubling, 14.206699082890463, 0.000000000001), "temps de doublement")
expect(continuous > compound, "le continu dépasse le composé")

# --- 5. Échelles logarithmiques ----------------------------------------------
print("")
print("=== Décibels, pH, magnitude ===")
decibels := 10 * math.log10(1000)
ph := 0 - math.log10(0.0001)
octaves := math.log(1024, 2)
energy_ratio := math.pow(10, 1.5 * 2)
print(f"rapport de puissance 1000 = {decibels} dB")
print(f"pH d'une solution [H+] = 0.0001 mol/L : {ph}")
print(f"1024 = 2^{octaves}")
print(f"écart de 2 degrés de magnitude = facteur {energy_ratio} en énergie")
expect(math.is_close(decibels, 30.0), "1000x = 30 dB")
expect(math.is_close(ph, 4.0), "pH = 4")
expect(math.is_close(octaves, 10.0), "log2(1024) = 10")
expect(math.is_close(energy_ratio, 1000.0), "10^3 = 1000")

# --- 6. Comparaison de flottants ---------------------------------------------
print("")
print("=== is_close ===")
print(f"0.1 + 0.2 == 0.3 ? {0.1 + 0.2 == 0.3}    is_close(0.1 + 0.2, 0.3) ? {math.is_close(0.1 + 0.2, 0.3)}")
expect(math.is_close(0.1 + 0.2, 0.3), "is_close absorbe l'erreur d'arrondi")
expect(not math.is_close(1.0, 1.1), "1.0 et 1.1 sont différents")
expect(math.is_close(100, 105, 0.1), "tolérance relative de 10 %")

print("")
print("OK : math_statistics")

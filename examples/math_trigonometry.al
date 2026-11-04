# Exemple : trigonométrie, fonctions inverses, hyperboliques, résolution de triangle
# Lancer depuis la racine du projet : ./alex run examples/math_trigonometry.al
use math

func expect_close(actual, expected, tol, label):
    if actual == null:
        raise("AssertionError", f"{label} : obtenu null, attendu {expected}")
    d := actual - expected
    if d < 0:
        d = 0 - d
    if d > tol:
        raise("AssertionError", f"{label} : obtenu {actual}, attendu {expected}")

# Arrondi à 6 décimales pour l'affichage.
func r6(v):
    if v == null:
        return null
    return math.round(v * 1000000) / 1000000

# --- 1. Table des angles remarquables ----------------------------------------
print("=== Table sin / cos / tan (degrés) ===")
table := [0, 30, 45, 60, 90, 180]
for deg in table:
    x := math.radians(deg)
    print(f"{deg} degrés : sin={r6(math.sin(x))}  cos={r6(math.cos(x))}  tan={r6(math.tan(x))}")

expect_close(math.sin(math.radians(30)), 0.5, 0.000000000001, "sin(30)")
expect_close(math.cos(math.radians(60)), 0.5, 0.000000000001, "cos(60)")
expect_close(math.tan(math.radians(45)), 1.0, 0.000000000001, "tan(45)")
expect_close(math.sin(math.radians(45)), 0.7071067811865476, 0.000000000001, "sin(45)")
if math.tan(math.radians(90)) != null:
    raise("AssertionError", "tan(90 degrés) doit renvoyer null (asymptote)")

# --- 2. Identité de Pythagore : sin^2 + cos^2 = 1 ------------------------------
print("")
print("=== sin^2 + cos^2 = 1 sur 0..360 degrés ===")
deg := 0
while deg <= 360:
    x := math.radians(deg)
    total := math.sin(x) ** 2 + math.cos(x) ** 2
    expect_close(total, 1.0, 0.000000000001, f"identité de Pythagore à {deg} degrés")
    deg += 15
print("25 angles vérifiés")

# --- 3. Fonctions inverses ---------------------------------------------------
print("")
print("=== Fonctions inverses ===")
for x in [-1.2, -0.7, 0.0, 0.3, 1.0, 1.4]:
    expect_close(math.asin(math.sin(x)), x, 0.000000001, f"asin(sin({x}))")
    expect_close(math.atan(math.tan(x)), x, 0.000000001, f"atan(tan({x}))")
for x in [0.1, 1.0, 2.0, 3.0]:
    expect_close(math.acos(math.cos(x)), x, 0.000000001, f"acos(cos({x}))")
print(f"asin(1) = {math.asin(1)}  (pi/2 = {math.HALF_PI})")
print(f"acos(-1) = {math.acos(-1)}  (pi = {math.PI})")
print(f"atan(1) * 4 = {math.atan(1) * 4}")
expect_close(math.atan(1) * 4, math.PI, 0.000000000001, "4 * atan(1) = pi")
if math.asin(2) != null:
    raise("AssertionError", "asin(2) hors domaine doit renvoyer null")

# --- 4. Formules de l'angle double -------------------------------------------
print("")
print("=== Angle double ===")
for x in [0.2, 0.9, 1.3, 2.5, -0.8]:
    s := math.sin(x)
    c := math.cos(x)
    expect_close(math.sin(2 * x), 2 * s * c, 0.000000000001, f"sin(2x) pour x={x}")
    expect_close(math.cos(2 * x), c * c - s * s, 0.000000000001, f"cos(2x) pour x={x}")
print("sin(2x) = 2 sin(x) cos(x) et cos(2x) = cos^2 - sin^2 : OK")

# --- 5. Fonctions hyperboliques ----------------------------------------------
print("")
print("=== Hyperboliques : cosh^2 - sinh^2 = 1 et tanh = sinh / cosh ===")
for x in [-3, -1, 0, 0.5, 2, 3]:
    ch := math.cosh(x)
    sh := math.sinh(x)
    expect_close(ch * ch - sh * sh, 1.0, 0.000000001, f"cosh^2 - sinh^2 pour x={x}")
    expect_close(math.tanh(x), sh / ch, 0.000000000001, f"tanh = sinh/cosh pour x={x}")
print(f"sinh(1)={math.sinh(1)}  cosh(1)={math.cosh(1)}  tanh(1)={math.tanh(1)}")

# --- 6. Résolution d'un triangle (loi des cosinus) ---------------------------
print("")
print("=== Triangle a=7, b=10, angle C=60 degrés ===")
a := 7
b := 10
angle_c := 60
c := math.sqrt(a ** 2 + b ** 2 - 2 * a * b * math.cos(math.radians(angle_c)))
angle_a := math.degrees(math.acos((b ** 2 + c ** 2 - a ** 2) / (2 * b * c)))
angle_b := math.degrees(math.acos((a ** 2 + c ** 2 - b ** 2) / (2 * a * c)))
print(f"c = {c}")
print(f"A = {angle_a} degrés, B = {angle_b} degrés, C = {angle_c} degrés")
expect_close(c, 8.888194417315589, 0.000000001, "côté c")
expect_close(angle_a + angle_b + angle_c, 180.0, 0.000000001, "somme des angles")
# Loi des sinus : a / sin(A) = b / sin(B) = c / sin(C)
ratio_a := a / math.sin(math.radians(angle_a))
ratio_b := b / math.sin(math.radians(angle_b))
ratio_c := c / math.sin(math.radians(angle_c))
expect_close(ratio_a, ratio_b, 0.000000001, "loi des sinus a/b")
expect_close(ratio_b, ratio_c, 0.000000001, "loi des sinus b/c")

print("")
print("OK : math_trigonometry")

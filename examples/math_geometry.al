# Exemple : géométrie (cercle, sphère, Héron, distance, angles, polygones, polaire)
# Lancer depuis la racine du projet : ./alex run examples/math_geometry.al
use math

func expect_close(actual, expected, label):
    d := actual - expected
    if d < 0:
        d = 0 - d
    if d > 0.000000001:
        raise("AssertionError", f"{label} : obtenu {actual}, attendu {expected}")

# --- Cercle et sphère --------------------------------------------------------
print("=== Cercle et sphère ===")
r := 2.5
area := math.PI * r ** 2
circumference := math.TAU * r
print(f"cercle r={r} : aire={area}  circonférence={circumference}")
expect_close(area, 19.634954084936208, "aire du cercle")
expect_close(circumference, 15.707963267948966, "circonférence")

radius := 3
volume := 4 / 3 * math.PI * radius ** 3
surface := 4 * math.PI * radius ** 2
print(f"sphère r={radius} : volume={volume}  surface={surface}")
expect_close(volume, 113.09733552923254, "volume de la sphère")
expect_close(surface, 113.09733552923254, "surface de la sphère")

# --- Formule de Héron --------------------------------------------------------
print("")
print("=== Triangle 13-14-15 (Héron) ===")
a := 13
b := 14
c := 15
s := (a + b + c) / 2
triangle_area := math.sqrt(s * (s - a) * (s - b) * (s - c))
print(f"demi-périmètre={s}  aire={triangle_area}")
expect_close(triangle_area, 84.0, "aire de Héron")

# --- Distance euclidienne ----------------------------------------------------
print("")
print("=== Distance entre deux points ===")
dx := 4 - 1
dy := 6 - 2
dist := math.sqrt(dx ** 2 + dy ** 2)
print(f"distance((1,2),(4,6)) = {dist}")
expect_close(dist, 5.0, "distance 3-4-5")

# --- Angle d'un vecteur (atan2) ---------------------------------------------
print("")
print("=== Angle d'un vecteur en degrés ===")
vectors := [[1, 1], [-1, 1], [-1, -1], [1, -1], [0, 1], [0, -1]]
angles := [45.0, 135.0, -135.0, -45.0, 90.0, -90.0]
i := 0
for vec in vectors:
    angle := math.degrees(math.atan2(vec[1], vec[0]))
    print(f"vecteur ({vec[0]}, {vec[1]}) -> {angle} degrés")
    expect_close(angle, angles[i], f"angle du vecteur {i}")
    i += 1

# --- Coordonnées polaires <-> cartésiennes ----------------------------------
print("")
print("=== Polaire -> cartésien -> polaire ===")
radius_polar := 5
theta_deg := 53.13010235415598
theta := math.radians(theta_deg)
x := radius_polar * math.cos(theta)
y := radius_polar * math.sin(theta)
print(f"(r=5, {theta_deg} degrés) -> (x={x}, y={y})")
expect_close(x, 3.0, "x cartésien")
expect_close(y, 4.0, "y cartésien")
back_r := math.sqrt(x ** 2 + y ** 2)
back_theta := math.degrees(math.atan2(y, x))
expect_close(back_r, 5.0, "rayon retrouvé")
expect_close(back_theta, theta_deg, "angle retrouvé")

# --- Polygones réguliers inscrits dans un cercle de rayon 10 -----------------
print("")
print("=== Polygones réguliers (rayon circonscrit 10) ===")
R := 10
sides := [3, 4, 6, 8, 12, 360]
for n in sides:
    side := 2 * R * math.sin(math.PI / n)
    poly_area := n / 2 * R ** 2 * math.sin(math.TAU / n)
    print(f"n={n}  côté={side}  aire={poly_area}")
expect_close(2 * R * math.sin(math.PI / 6), 10.0, "côté de l'hexagone = rayon")
expect_close(6 / 2 * R ** 2 * math.sin(math.TAU / 6), 259.8076211353316, "aire de l'hexagone")
expect_close(4 / 2 * R ** 2 * math.sin(math.TAU / 4), 200.0, "aire du carré")
# Quand n grandit, l'aire tend vers celle du disque (pi * R^2).
disc := math.PI * R ** 2
big_poly := 360 / 2 * R ** 2 * math.sin(math.TAU / 360)
print(f"disque={disc}  polygone(360)={big_poly}  écart={disc - big_poly}")
if disc - big_poly < 0 or disc - big_poly > 0.02:
    raise("AssertionError", "le polygone à 360 côtés devrait approcher le disque")

print("")
print("OK : math_geometry")

# Exemple : physique (projectile, pendule, chute libre, désintégration, refroidissement, Kepler)
# Lancer depuis la racine du projet : ./alex run examples/math_physics.al
use math

func expect_close(actual, expected, tol, label):
    d := actual - expected
    if d < 0:
        d = 0 - d
    if d > tol:
        raise("AssertionError", f"{label} : obtenu {actual}, attendu {expected}")

g := 9.81

# --- 1. Tir d'un projectile --------------------------------------------------
print("=== Projectile : v0 = 20 m/s, angle 45 degrés ===")
v0 := 20
angle := math.radians(45)
flight_time := 2 * v0 * math.sin(angle) / g
range_x := v0 ** 2 * math.sin(2 * angle) / g
max_height := (v0 * math.sin(angle)) ** 2 / (2 * g)
print(f"durée du vol = {flight_time} s   portée = {range_x} m   hauteur max = {max_height} m")
expect_close(flight_time, 2.8832080782326095, 0.000000001, "durée du vol")
expect_close(range_x, 40.77471967380224, 0.000000001, "portée")
expect_close(max_height, 10.19367991845056, 0.000000001, "hauteur maximale")

# Trajectoire : on retombe au sol (y = 0) à la fin du vol, à x = portée.
step := 0
while step <= 4:
    t := flight_time * step / 4
    px := v0 * math.cos(angle) * t
    py := v0 * math.sin(angle) * t - 0.5 * g * t ** 2
    print(f"t={t}  x={px}  y={py}")
    step += 1
expect_close(v0 * math.cos(angle) * flight_time, range_x, 0.000000001, "x à l'atterrissage")
expect_close(v0 * math.sin(angle) * flight_time - 0.5 * g * flight_time ** 2, 0.0, 0.000000001, "y à l'atterrissage")

# La portée est maximale à 45 degrés et symétrique autour (30 <-> 60).
print("")
print("=== Portée selon l'angle ===")
best_angle := 0
best_range := 0
for deg in [15, 30, 45, 60, 75]:
    reach := v0 ** 2 * math.sin(math.radians(2 * deg)) / g
    print(f"{deg} degrés -> {reach} m")
    if reach > best_range:
        best_range = reach
        best_angle = deg
if best_angle != 45:
    raise("AssertionError", "la portée maximale doit être obtenue à 45 degrés")
range_30 := v0 ** 2 * math.sin(math.radians(60)) / g
range_60 := v0 ** 2 * math.sin(math.radians(120)) / g
expect_close(range_30, range_60, 0.000000001, "symétrie 30/60")

# --- 2. Pendule simple -------------------------------------------------------
print("")
print("=== Pendule simple T = 2 pi sqrt(L/g) ===")
period_1 := math.TAU * math.sqrt(1 / g)
period_quarter := math.TAU * math.sqrt(0.25 / g)
print(f"L = 1 m : T = {period_1} s    L = 0.25 m : T = {period_quarter} s")
expect_close(period_1, 2.0060666807106475, 0.000000001, "période L=1")
expect_close(period_1, 2 * period_quarter, 0.000000001, "quatre fois plus court => période divisée par 2")

# --- 3. Chute libre ----------------------------------------------------------
print("")
print("=== Chute libre depuis 45 m ===")
h := 45
impact_speed := math.sqrt(2 * g * h)
fall_time := math.sqrt(2 * h / g)
print(f"vitesse d'impact = {impact_speed} m/s   durée = {fall_time} s")
expect_close(impact_speed, 29.71363323459452, 0.000000001, "vitesse d'impact")
expect_close(fall_time, 3.0289126640769135, 0.000000001, "durée de chute")
expect_close(g * fall_time, impact_speed, 0.000000001, "v = g t")

# --- 4. Désintégration radioactive (carbone 14) ------------------------------
print("")
print("=== Carbone 14 (demi-vie 5730 ans) ===")
half_life := 5730
decay := math.LN2 / half_life
print(f"après une demi-vie : {math.exp(0 - decay * 5730)}   après deux : {math.exp(0 - decay * 11460)}")
expect_close(math.exp(0 - decay * 5730), 0.5, 0.000000000001, "une demi-vie")
expect_close(math.exp(0 - decay * 11460), 0.25, 0.000000000001, "deux demi-vies")
remaining := math.exp(0 - decay * 2000)
print(f"reste après 2000 ans : {remaining * 100} %")
expect_close(remaining, 0.7851062746234183, 0.000000000001, "reste après 2000 ans")
age := 0 - math.ln(0.3) / decay
print(f"âge d'un échantillon à 30 % de C14 : {age} ans")
expect_close(age, 9952.812854572363, 0.000000001, "datation")

# --- 5. Loi de refroidissement de Newton -------------------------------------
print("")
print("=== Café à 90 C dans une pièce à 20 C (k = 0.05 / min) ===")
t_env := 20
t_start := 90
k := 0.05
after_10 := t_env + (t_start - t_env) * math.exp(0 - k * 10)
minutes_to_40 := 0 - math.ln((40 - t_env) / (t_start - t_env)) / k
print(f"après 10 min : {after_10} C    temps pour atteindre 40 C : {minutes_to_40} min")
expect_close(after_10, 62.45714617988434, 0.000000001, "température après 10 min")
expect_close(minutes_to_40, 25.05525936990736, 0.000000001, "temps pour atteindre 40 C")

# --- 6. Troisième loi de Kepler : période de la Terre ------------------------
print("")
print("=== Kepler : période orbitale de la Terre ===")
semi_major_axis := 149600000000.0
gm_sun := 132712440018000000000.0
period_seconds := math.TAU * math.sqrt(math.pow(semi_major_axis, 3) / gm_sun)
period_days := period_seconds / 86400
print(f"période = {period_days} jours")
expect_close(period_days, 365.2646967083811, 0.0001, "période orbitale")

print("")
print("OK : math_physics")

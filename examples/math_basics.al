# Exemple : utilitaires numériques de base (abs, sign, arrondis, min/max, clamp, parité)
# Lancer depuis la racine du projet : ./alex run examples/math_basics.al
use math

func expect(cond, message):
    if not cond:
        raise("AssertionError", message)

# --- 1. Valeur absolue, signe et les quatre arrondis -------------------------
print("=== abs / sign / floor / ceil / round / trunc ===")
samples := [-3.7, -2.5, -0.4, 0.5, 2.5, 3.7]
for v in samples:
    print(f"x={v}  abs={math.abs(v)}  sign={math.sign(v)}  floor={math.floor(v)}  ceil={math.ceil(v)}  round={math.round(v)}  trunc={math.trunc(v)}")

expect(math.abs(-3.7) == 3.7, "abs(-3.7)")
expect(math.sign(-3.7) == -1, "sign(-3.7)")
expect(math.floor(-3.7) == -4, "floor arrondit vers -infini")
expect(math.ceil(-3.7) == -3, "ceil arrondit vers +infini")
expect(math.trunc(-3.7) == -3, "trunc coupe la partie décimale")
expect(math.round(2.5) == 3, "round(2.5) : demi vers l'infini")
expect(math.round(-2.5) == -3, "round(-2.5) : demi vers l'infini")
expect(math.round(2.4) == 2, "round(2.4)")

# --- 2. min / max / min3 / max3 sur des relevés de température ---------------
print("")
print("=== min / max sur des relevés ===")
temps := [21.5, 19.0, 25.3, 22.8, 18.4]
lowest := temps[0]
highest := temps[0]
for t in temps:
    lowest = math.min(lowest, t)
    highest = math.max(highest, t)
print(f"plus froid={lowest}  plus chaud={highest}  amplitude={highest - lowest}")
expect(lowest == 18.4, "minimum des relevés")
expect(highest == 25.3, "maximum des relevés")
expect(math.is_close(highest - lowest, 6.9), "amplitude thermique")

expect(math.min3(30, 10, 20) == 10, "min3")
expect(math.max3(30, 10, 20) == 30, "max3")
print(f"min3(30,10,20)={math.min3(30, 10, 20)}  max3(30,10,20)={math.max3(30, 10, 20)}")

# --- 3. clamp : un curseur de volume borné à [0, 100] ------------------------
print("")
print("=== clamp : curseur de volume [0, 100] ===")
raw_values := [-20, 0, 55, 100, 140]
expected := [0, 0, 55, 100, 100]
i := 0
for raw in raw_values:
    bounded := math.clamp(raw, 0, 100)
    print(f"brut={raw}  ->  borné={bounded}")
    expect(bounded == expected[i], f"clamp({raw}, 0, 100)")
    i += 1

# --- 4. Parité --------------------------------------------------------------
print("")
print("=== is_even / is_odd ===")
evens := 0
odds := 0
for n in 1..11:
    if math.is_even(n):
        evens += 1
    if math.is_odd(n):
        odds += 1
print(f"entre 1 et 10 : {evens} pairs, {odds} impairs")
expect(evens == 5, "5 nombres pairs entre 1 et 10")
expect(odds == 5, "5 nombres impairs entre 1 et 10")
expect(math.is_even(-4), "is_even(-4)")
expect(math.is_odd(-3), "is_odd(-3)")
expect(math.is_even(0), "0 est pair")

print("")
print("OK : math_basics")

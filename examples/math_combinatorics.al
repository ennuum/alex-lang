# Exemple : combinatoire (triangle de Pascal, arrangements, probabilités, binôme de Newton)
# Lancer depuis la racine du projet : ./alex run examples/math_combinatorics.al
use math

func expect(cond, message):
    if not cond:
        raise("AssertionError", message)

# --- 1. Triangle de Pascal ---------------------------------------------------
print("=== Triangle de Pascal (8 lignes) ===")
for n in 0..8:
    line := ""
    for k in 0..n + 1:
        line = line + f"{math.combinations(n, k)} "
    print(f"n={n} : {line}")
expect(math.combinations(5, 2) == 10, "C(5, 2)")
expect(math.combinations(7, 3) == 35, "C(7, 3)")

# --- 2. Propriétés du triangle -----------------------------------------------
print("")
print("=== Propriétés ===")
for n in 0..21:
    row_sum := 0
    for k in 0..n + 1:
        row_sum += math.combinations(n, k)
    expect(row_sum == math.pow(2, n), f"la somme de la ligne {n} vaut 2^{n}")
print("somme de la ligne n = 2^n pour n = 0..20 : OK")

for n in 1..31:
    for k in 0..n + 1:
        expect(math.combinations(n, k) == math.combinations(n, n - k), f"symétrie C({n}, {k})")
print("symétrie C(n, k) = C(n, n-k) pour n <= 30 : OK")

for n in 2..31:
    for k in 1..n:
        expect(math.combinations(n, k) == math.combinations(n - 1, k - 1) + math.combinations(n - 1, k), f"règle de Pascal C({n}, {k})")
print("règle de Pascal C(n,k) = C(n-1,k-1) + C(n-1,k) pour n <= 30 : OK")

# --- 3. Arrangements ---------------------------------------------------------
print("")
print("=== Arrangements P(n, k) ===")
print(f"P(10, 3) = {math.permutations(10, 3)}")
print(f"mots de 4 lettres distinctes : P(26, 4) = {math.permutations(26, 4)}")
expect(math.permutations(10, 3) == 720, "P(10, 3)")
expect(math.permutations(26, 4) == 358800, "P(26, 4)")
expect(math.permutations(5, 5) == math.factorial(5), "P(n, n) = n!")
expect(math.permutations(5, 0) == 1, "P(n, 0) = 1")
expect(math.permutations(3, 5) == null, "k > n : null")
# Lien entre arrangements et combinaisons : P(n, k) = C(n, k) * k!
for n in 0..13:
    for k in 0..n + 1:
        expect(math.permutations(n, k) == math.combinations(n, k) * math.factorial(k), f"P({n}, {k}) = C * k!")
print("P(n, k) = C(n, k) * k! pour n <= 12 : OK")

# --- 4. Probabilités classiques ----------------------------------------------
print("")
print("=== Probabilités ===")
lottery := math.combinations(49, 6)
poker := math.combinations(52, 5)
handshakes := math.combinations(20, 2)
print(f"loto 6 parmi 49 : 1 chance sur {lottery}")
print(f"mains de poker à 5 cartes : {poker}")
print(f"poignées de main dans un groupe de 20 : {handshakes}")
expect(lottery == 13983816, "C(49, 6)")
expect(poker == 2598960, "C(52, 5)")
expect(handshakes == 190, "C(20, 2)")
# Probabilité d'un carré (13 valeurs x 48 cartes restantes) parmi les mains de poker
four_of_a_kind := 13 * 48
probability := four_of_a_kind / poker
print(f"probabilité d'un carré : {probability}")
expect(math.is_close(probability, 0.00024009603841536616), "probabilité du carré")

# --- 5. Binôme de Newton -----------------------------------------------------
print("")
print("=== Binôme de Newton : (x + y)^n = somme de C(n,k) x^(n-k) y^k ===")
x := 2
y := 3
n := 6
expansion := 0
for k in 0..n + 1:
    expansion += math.combinations(n, k) * math.pow(x, n - k) * math.pow(y, k)
print(f"(2 + 3)^6 = {expansion}")
expect(expansion == 15625, "(2 + 3)^6 = 15625")
expect(expansion == math.pow(x + y, n), "développement = puissance directe")

xf := 1.5
yf := 0.5
expansion_f := 0.0
for k in 0..11:
    expansion_f += math.combinations(10, k) * math.pow(xf, 10 - k) * math.pow(yf, k)
print(f"(1.5 + 0.5)^10 = {expansion_f}")
expect(math.is_close(expansion_f, 1024.0), "(1.5 + 0.5)^10 = 1024")

# --- 6. Alias factorial_ratio ------------------------------------------------
expect(math.factorial_ratio(10, 4) == math.combinations(10, 4), "factorial_ratio = combinations")

print("")
print("OK : math_combinatorics")

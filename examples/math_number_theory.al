# Exemple : théorie des nombres (gcd, lcm, fractions, Fibonacci, factorielle, premiers, Collatz)
# Lancer depuis la racine du projet : ./alex run examples/math_number_theory.al
use math
use core
use collections

func expect(cond, message):
    if not cond:
        raise("AssertionError", message)

# --- 1. PGCD / PPCM ----------------------------------------------------------
print("=== gcd / lcm ===")
pairs := [[48, 18], [17, 5], [100, 75], [1071, 462], [12, 0]]
for p in pairs:
    print(f"gcd({p[0]}, {p[1]}) = {math.gcd(p[0], p[1])}    lcm({p[0]}, {p[1]}) = {math.lcm(p[0], p[1])}")
expect(math.gcd(48, 18) == 6, "gcd(48, 18)")
expect(math.gcd(1071, 462) == 21, "gcd(1071, 462)")
expect(math.lcm(4, 6) == 12, "lcm(4, 6)")
expect(math.gcd(-12, 18) == 6, "gcd accepte les négatifs")
expect(math.gcd(0, 0) == 0, "gcd(0, 0)")

# PPCM des nombres de 1 à 10 : plus petit nombre divisible par chacun d'eux.
smallest := 1
for n in 1..11:
    smallest = math.lcm(smallest, n)
print(f"ppcm(1..10) = {smallest}")
expect(smallest == 2520, "ppcm(1..10) = 2520")

# --- 2. Réduction de fractions -----------------------------------------------
print("")
print("=== Fractions réduites ===")
fractions := [[84, 126], [10, 25], [7, 13], [100, 10]]
reduced_expected := [[2, 3], [2, 5], [7, 13], [10, 1]]
i := 0
for f in fractions:
    g := math.gcd(f[0], f[1])
    num := f[0] // g
    den := f[1] // g
    print(f"{f[0]}/{f[1]} = {num}/{den}")
    expect(num == reduced_expected[i][0] and den == reduced_expected[i][1], f"réduction de {f[0]}/{f[1]}")
    i += 1

# --- 3. Fibonacci et nombre d'or ---------------------------------------------
print("")
print("=== Fibonacci ===")
line := ""
for n in 0..15:
    line = line + f"{math.fibonacci(n)} "
print(line)
expect(math.fibonacci(10) == 55, "fibonacci(10)")
expect(math.fibonacci(50) == 12586269025, "fibonacci(50)")
expect(math.fibonacci(92) == 7540113804746346429, "fibonacci(92), le plus grand tenant sur 64 bits")
golden := (1 + math.sqrt(5)) / 2
ratio := math.fibonacci(41) / math.fibonacci(40)
print(f"fib(41)/fib(40) = {ratio}   nombre d'or = {golden}")
expect(math.is_close(ratio, golden), "fib(n+1)/fib(n) tend vers le nombre d'or")

# --- 4. Factorielle ----------------------------------------------------------
print("")
print("=== Factorielle ===")
for n in [0, 1, 5, 10, 20]:
    print(f"{n}! = {math.factorial(n)}")
expect(math.factorial(10) == 3628800, "10!")
expect(math.factorial(20) == 2432902008176640000, "20!")
expect(math.factorial(-3) == null, "factorielle d'un négatif = null")
# Approximation de Stirling : n! ~ sqrt(2 pi n) (n/e)^n
stirling := math.sqrt(math.TAU * 10) * math.pow(10 / math.E, 10)
ratio_stirling := stirling / math.factorial(10)
print(f"Stirling(10) / 10! = {ratio_stirling}")
expect(ratio_stirling > 0.99 and ratio_stirling < 1.0, "Stirling sous-estime de moins de 1 %")

# --- 5. Nombres premiers (essai de division jusqu'à sqrt(n)) -----------------
print("")
print("=== Nombres premiers ===")

func is_prime(n):
    if n < 2:
        return false
    if n == 2:
        return true
    if math.is_even(n):
        return false
    limit := math.floor(math.sqrt(n))
    d := 3
    while d <= limit:
        if n % d == 0:
            return false
        d += 2
    return true

primes := []
for n in 2..60:
    if is_prime(n):
        collections.append(primes, n)
print(f"premiers < 60 : {primes}")
expect(core.len(primes) == 17, "17 nombres premiers sous 60")
expect(primes[16] == 59, "le dernier premier sous 60 est 59")
expect(is_prime(97), "97 est premier")
expect(not is_prime(91), "91 = 7 x 13")
expect(is_prime(7919), "7919 est le 1000e nombre premier")
expect(is_prime(1000000007), "1000000007 est premier")
expect(not is_prime(1000000008), "1000000008 est pair")

# --- 6. Nombres parfaits -----------------------------------------------------
print("")
print("=== Nombres parfaits <= 500 ===")
perfect := []
for n in 2..501:
    total := 1
    d := 2
    while d * d <= n:
        if n % d == 0:
            total += d
            other := n // d
            if other != d:
                total += other
        d += 1
    if total == n:
        collections.append(perfect, n)
print(f"nombres parfaits : {perfect}")
expect(perfect[0] == 6 and perfect[1] == 28 and perfect[2] == 496, "6, 28 et 496")

# --- 7. Suite de Collatz (is_even) -------------------------------------------
print("")
print("=== Collatz depuis 27 ===")
n := 27
steps := 0
peak := n
while n != 1:
    if math.is_even(n):
        n = n // 2
    else:
        n = 3 * n + 1
    steps += 1
    peak = math.max(peak, n)
print(f"27 atteint 1 en {steps} étapes, sommet = {peak}")
expect(steps == 111, "111 étapes")
expect(peak == 9232, "sommet 9232")

print("")
print("OK : math_number_theory")

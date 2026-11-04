# Fonctions : récursion, récursion mutuelle, défauts, arguments nommés, globales, bool/str.
counter := 0

func bump(step: int = 1):
    counter += step

func is_even(n: int) -> bool:
    if n == 0:
        return true
    return is_odd(n - 1)

func is_odd(n: int) -> bool:
    if n == 0:
        return false
    return is_even(n - 1)

func ack(m: int, n: int) -> int:
    if m == 0:
        return n + 1
    if n == 0:
        return ack(m - 1, 1)
    return ack(m - 1, ack(m, n - 1))

func gcd(a: int, b: int) -> int:
    while b != 0:
        t := b
        b = a % b
        a = t
    return a

func describe(name: str, loud: bool = false) -> str:
    if loud:
        return "BONJOUR"
    return name

func collatz(n: int) -> int:
    steps := 0
    while n != 1:
        if n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps

bump()
bump(5)
bump(step=10)
print(counter)
print(is_even(10), is_odd(7), is_even(7))
print(ack(2, 3))
print(gcd(1071, 462))
print(describe("monde"))
print(describe(loud=true, name="x"))
print(collatz(27))
best := 0
best_n := 0
for n in 1..10000:
    c := collatz(n)
    if c > best:
        best = c
        best_n = n
print(best_n, best)

func nothing():
    return

nothing()
print("fin")

# Plus de 6 arguments : les suivants passent par la pile.
func many(a: int, b: int, c: int, d: int, e: int, f: int, g: int, h: int, i: float, j: str) -> str:
    return str(a - b + c * d - e + f * g - h) + " " + str(i) + " " + j
print(many(1, 2, 3, 4, 5, 6, 7, 8, 2.5, "fin"))
func many_rec(n: int, a: int, b: int, c: int, d: int, e: int, f: int, g: int) -> int:
    if n == 0:
        return a + b + c + d + e + f + g
    return many_rec(n - 1, b, c, d, e, f, g, a + n)
print(many_rec(20, 1, 2, 3, 4, 5, 6, 7))
k := 1000
seven := (a: int, b: int, c: int, d: int, e: int, f: int, g: int) => a * 1000000 + b * 100000 + c * 10000 + d * 1000 + e * 100 + f * 10 + g + k
print(seven(1, 2, 3, 4, 5, 6, 7))

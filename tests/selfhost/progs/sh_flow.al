# Fermetures, boucles, try / finally à travers break / continue / return, exceptions typées, spread.
func counter():
    n := 0
    func inc(step=1):
        n += step
        return n
    return inc

c := counter()
c()
c(5)
print(c())

func adders():
    out := []
    for i in 0..3:
        out.append((x) => x + i)
    return out
print([f(10) for f in adders()])

func search(xs, target):
    for i, x in enumerate(xs):
        try:
            if x == target:
                return i
            if x < 0:
                continue
            if x > 100:
                break
        finally:
            print("vu", x)
    else:
        return -1
    return -2

print(search([1, -2, 3], 3))
print(search([1, 200, 3], 3))
print(search([1, 2], 9))

func risky(k):
    try:
        if k == 0:
            raise("ValueError", "zéro")
        if k == 1:
            return [1][5]
        return 10 // k
    catch ValueError as e:
        return "valeur: " + str(e)
    catch (IndexError, KeyError):
        return "index"
    finally:
        print("fin", k)

for k in [0, 1, 2]:
    print(risky(k))

def_args := [1, 2, 3]
func total(a, b, c=0, *rest):
    return a + b + c + sum(rest)
print(total(*def_args))
print(total(1, 2, 3, 4, *[5, 6]))
d := {"a": 1, **{"b": 2, "c": 3}}
print(d)
print([*def_args, 4, *[5]])
w := 0
while w < 10:
    w += 3
    if w == 6:
        continue
else:
    print("while fini", w)
x := 7
x **= 2
x //= 3
x <<= 1
print(x, x if x > 10 else -x, not (x in [1, 2]), 3 not in [1, 2])
print(f"total={total(1, 2)} ok {x} {[i * 2 for i in 0..3]}")

# Fonctions sans annotations : une version native par combinaison de types d'arguments (comme le typage
# graduel de la VM, mais résolu à la compilation).
from collections use append
func biggest(a, b):
    if a > b:
        return a
    return b

func describe(x, label = "valeur"):
    return label + " = " + str(x)

func total(xs):
    t := 0
    for x in xs:
        t += x
    return t

func show(x):
    print("->", x)

func fact(n) -> int:
    if n <= 1:
        return 1
    return n * fact(n - 1)

print(biggest(3, 7), biggest(2.5, -1.0), biggest("abc", "abd"))
print(describe(42), describe(1.5, "pi approx"), describe([1, 2], label = "liste"))
print(total([1, 2, 3, 4]), total([10, 20]))
show(true)
show("texte")
print(fact(10))
items: list[int] := []
for i in 0..5:
    append(items, biggest(i, 2))
print(items)

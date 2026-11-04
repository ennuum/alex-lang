# Tuples : littéraux hétérogènes, index constant, itération (homogène), égalité structurelle, affichage.
from core use len
from collections use append
t := (1, "a", 2.5)
print(t)
print(t[0] + 1, t[1] + "b", t[2] * 2.0)
print(len(t))
u := (1, "a", 2.5)
print(t == u, t != u, (1, 2) == (1, 3), (1, 2.0) == (1, 2), (1, "a") == (1, 2))
for x in (4, 5, 6):
    print(x)
func divmod(a: int, b: int) -> tuple[int, int]:
    return (a // b, a % b)
p := divmod(17, 5)
print(p, p[0] * 5 + p[1])
q: tuple[int, str] := (1, "z")
print(q)
nested := ((1, 2), [3, 4], (true, null))
print(nested, nested[0][1], nested[1][0])
print(str(t), f"<{t}>")
pairs: list[tuple[str, int]] := []
append(pairs, ("un", 1))
append(pairs, ("deux", 2))
total := 0
for pr in pairs:
    total += pr[1]
    print(pr[0])
print(total, pairs)
k := 2
trip := (10, 20, 30)
print(trip[k], trip[k - 2])
if trip:
    print("vrai")
print((1, (2, 3)) == (1, (2, 3)))

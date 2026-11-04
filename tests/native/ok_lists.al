# Listes typées : littéraux, index, affectation, append, len, for (longueur relue), affichage, imbrication.
from core use len
from collections use append
xs := [3, 1, 4, 1, 5]
print(xs, len(xs), xs[0], xs[4])
xs[1] = 10
xs[2] += 5
print(xs)
ys: list[int] := []
for i in 0..10:
    append(ys, i * i)
print(ys, len(ys))
fs := [1.5, 2.0, 0.1 + 0.2]
print(fs)
words := ["un", "deux"]
append(words, "trois")
print(words, words[2])
grid := [[1, 2], [3]]
append(grid[1], 4)
append(grid, [])
print(grid, len(grid[2]))
flags := [true, false]
print(flags)
seen := [1]
for v in seen:
    if v < 5:
        append(seen, v + 1)
print(seen)
func total(values: list[int]) -> int:
    t := 0
    for v in values:
        t += v
    return t
func doubled(values: list[int]) -> list[int]:
    out: list[int] := []
    for v in values:
        append(out, 2 * v)
    return out
print(total(ys), doubled([1, 2, 3]))
big: list[int] := []
for i in 0..100000:
    append(big, i)
print(len(big), big[99999], total(big))
if ys:
    print("non vide")

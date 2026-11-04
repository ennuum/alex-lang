# Compréhensions de liste et de dict (boucles imbriquées, filtres, captures par des lambdas).
from collections use keys
from core use len
sq := [i * i for i in 0..6]
print(sq)
evens := [x for x in sq if x % 2 == 0]
print(evens)
pairs := [i * 10 + j for i in 1..4 for j in 0..i if (i + j) % 2 == 1]
print(pairs)
words := ["alpha", "beta", "gamma"]
lens := {w: len(w) for w in words}
print(lens)
inv := {v: k for k in keys(lens) for v in [lens[k]]}
print(inv)
fs := [() => i * 100 for i in 0..3]
for f in fs:
    print(f())
nested := [[j for j in 0..i] for i in 0..4]
print(nested)
floats: list[float] := [x / 2 for x in [1, 2, 3]]
print(floats)
empty := [x for x in [1, 2, 3] if x > 5]
print(empty, len(empty))

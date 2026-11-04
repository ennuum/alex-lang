# dict[K, V] : littéraux, lecture/écriture, ordre d'insertion, suppression, keys/values/get, for, imbrication.
from core use len
from collections use keys, values, get, contains_key, remove, set, append
d := {"b": 1, "a": 2}
print(d, len(d), d["a"])
d["c"] = 3
d["b"] = 10
d["a"] += 5
print(d, keys(d), values(d))
print(get(d, "zz"), get(d, "a"), contains_key(d, "c"), contains_key(d, "q"))
remove(d, "a")
print(d, len(d))
set(d, "a", 99)
print(d)
for k in d:
    print(k, d[k])
counts: dict[str, int] := {}
for w in ["le", "chat", "le", "chien", "le", "chat"]:
    if contains_key(counts, w):
        counts[w] += 1
    else:
        counts[w] = 1
print(counts)
byid: dict[int, list[str]] := {}
for i in 0..6:
    k := i % 3
    if not contains_key(byid, k):
        byid[k] = []
    append(byid[k], "e" + str(i))
print(byid)
fk := {1.5: "x", 0.0: "zéro"}
print(fk[1.5], fk[-0.0], fk)
big: dict[int, int] := {}
for i in 0..20000:
    big[i * 7] = i
for i in 0..10000:
    remove(big, i * 14)
total := 0
for k in big:
    total += big[k]
print(len(big), total, big[7], get(big, 14))
flags := {true: "oui", false: "non"}
print(flags[true], flags)
empty: dict[str, float] := {}
if empty:
    print("faux")
print(empty, len(empty))

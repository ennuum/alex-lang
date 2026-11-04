# Démo du module functional (ALEX pur) : ./alex run examples/functional_demo.al
use functional
from core use len
from functional use map, filter, reduce, seq, pipe

carres := map([1, 2, 3, 4, 5], x => x * x)
print(carres)                                              # [1, 4, 9, 16, 25]
print(reduce(filter(carres, x => x % 2 == 1), (a, b) => a + b, 0))   # 35

# Chaînage fluide
print(seq([5, 3, 8, 1, 9]).filter(x => x > 2).map(x => x * 10).sort_by(null, true).to_list())

# Tri stable par clé, regroupement, fréquences
gens := [("Ana", 31), ("Bob", 25), ("Cléa", 31), ("Dan", 25)]
print(functional.sort_by(gens, p => p[1]))
print(functional.group_by(gens, p => p[1]))
print(functional.frequencies(["a", "b", "a", "c", "a"]))

# Combinateurs
inc := functional.partial((a, b) => a + b, 1)
double := x => x * 2
print(pipe(5, [inc, double, x => x - 3]))                  # 9
print(functional.curry2((a, b) => a * b)(6)(7))            # 42

# Mémoïsation : fib(80) instantané
box := [null]
func fib(n):
    if n < 2:
        return n
    return box[0](n - 1) + box[0](n - 2)
box[0] = functional.memoize(fib)
print(box[0](80))

# Combinatoire
print(functional.combinations(["a", "b", "c"], 2))
print(len(functional.permutations([1, 2, 3, 4])))

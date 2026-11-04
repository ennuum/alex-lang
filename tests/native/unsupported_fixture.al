# Constructions hors du sous-ensemble natif : toutes signalées d'un coup (test-native).
func untyped(n):
    if n > 0:
        return n
    return "négatif"
u := untyped(2)
x: float := 3
g := (n) => n + 1
mixed := [1, 2.5]
q := []
p := 2.0 ** 3
t := (1, "a")
k := 1
v := t[k]
enum Shape:
    Circle(radius)
match Shape.Circle(1.0):
    Shape.Circle(r):
        print(r)
func later(xs: list[int]) -> int:
    func inner(k) -> int:
        return k
    return inner(xs[0])
z := await 42

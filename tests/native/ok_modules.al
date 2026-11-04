# Modules : use / use ... as / from ... use, initialisation unique dans l'ordre des dépendances.
use natmod.shapes
use natmod.counter as c
from natmod.shapes use Rect, square, UNIT
from natmod.counter use total

print("début")
r := Rect(2, 3)
s := shapes.square(4)
t := square(5)
print(r.describe(), s.area(), t.area())
print(shapes.scaled(r), UNIT, shapes.UNIT)
print(shapes.created, c.ticks, total())
c.tick()
print(c.total(), total())
f := shapes.scaled
print(f(t))
items: list[Rect] := [r, s, t]
sum := 0
for it in items:
    sum += it.area()
print(sum, isinstance(t, Rect))

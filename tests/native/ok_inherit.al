# Héritage et interfaces : champs hérités, redéfinition, super, répartition dynamique, isinstance,
# listes d'interface, affichage de la classe dynamique.
from collections use append
interface Shape:
    func area() -> float
    func name() -> str

class Base implements Shape:
    label: str := "base"
    func init(label: str):
        self.label = label
    func area() -> float:
        return 0.0
    func name() -> str:
        return "Base(" + self.label + ")"
    func describe() -> str:
        return self.name() + " aire=" + str(self.area())

class Rect extends Base:
    w: float := 0.0
    h: float := 0.0
    func init(label: str, w: float, h: float):
        super.init(label)
        self.w = w
        self.h = h
    func area() -> float:
        return self.w * self.h
    func name() -> str:
        return "Rect(" + self.label + ")"

class Square extends Rect:
    func init(label: str, side: float):
        super.init(label, side, side)
    func name() -> str:
        return "Carré/" + super.name()

class Circle implements Shape:
    r: float := 1.0
    func area() -> float:
        return 3.0 * self.r * self.r
    func name() -> str:
        return "Cercle"

shapes: list[Shape] := [Base("b"), Rect("r", 2.0, 3.0), Square("s", 1.5), Circle()]
total := 0.0
for sh in shapes:
    print(sh.name(), sh.area(), sh)
    total += sh.area()
print(total)
b: Base := Square("x", 2.0)
print(b.describe(), b.label, isinstance(b, Rect), isinstance(b, Square), isinstance(b, Circle))
r := Rect("seul", 1.0, 4.0)
print(r.describe(), r.w, isinstance(r, Shape))
items: list[Base] := []
append(items, Rect("a", 1.0, 1.0))
append(items, Base("z"))
for it in items:
    print(it.describe())
func biggest(xs: list[Shape]) -> Shape?:
    best: Shape? := null
    best_area := -1.0
    for x in xs:
        if x.area() > best_area:
            best = x
            best_area = x.area()
    return best
w := biggest(shapes)
if w != null:
    print("plus grande :", w.name())

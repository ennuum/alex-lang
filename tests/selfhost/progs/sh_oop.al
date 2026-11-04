# Classes, héritage, interfaces, super, champs typés, struct, enum et match.
interface Shape:
    func area()

class Base implements Shape:
    name: str := "base"
    count := 0
    func init(n):
        self.n = n
    func area():
        return 0
    func describe():
        return f"{self.name}#{self.n} aire={self.area()}"

class Square extends Base:
    func init(n, side=2):
        super.init(n)
        self.side = side
        self.name = "carré"
    func area():
        return self.side * self.side

struct Point:
    x: int := 0
    y: int := 0
    func init(x, y=5):
        self.x = x
        self.y = y
    func norm1():
        return abs(self.x) + abs(self.y)

enum Op:
    Add(a, b)
    Neg(a)
    Zero

func eval(op):
    match op:
        Op.Add(a, b):
            return a + b
        Op.Neg(a):
            return -a
        Op.Zero:
            return 0

shapes := [Base(1), Square(2, side=3), Square(3)]
for s in shapes:
    print(s.describe())
    print(isinstance(s, Shape))
p := Point(-3)
print(p.norm1())
print(Point(y=1, x=2).norm1())
print([eval(o) for o in [Op.Add(2, 3), Op.Neg(4), Op.Zero]])
match [1, (2, 3)]:
    [1, (a, b)] if a < b:
        print("liste", a, b)
    _:
        print("autre")
for v in [3, 15, 42, "x"]:
    match v:
        0..10:
            print("petit")
        10..20:
            print("moyen")
        "x":
            print("chaîne")
        n:
            print("grand", n)

# Structs et classes (sans héritage) : champs typés, init, méthodes, objets dans des listes.
from collections use append
from core use len
struct Point:
    x: float := 0.0
    y: float := 0.0
    func init(x: float, y: float):
        self.x = x
        self.y = y
    func norm2() -> float:
        return self.x * self.x + self.y * self.y
    func moved(dx: float) -> Point:
        return Point(self.x + dx, self.y)

class Counter:
    count: int := 0
    label: str := "c"
    func bump(step: int = 1):
        self.count += step
    func describe() -> str:
        return f"{self.label}={self.count}"

p := Point(3.0, 4.0)
print(p.x, p.y, p.norm2(), p.moved(1.5).x, p)
c := Counter()
c.bump()
c.bump(5)
c.label = "total"
print(c.count, c.describe())
pts: list[Point] := []
for i in 0..4:
    append(pts, Point(1.0 * i, 2.0))
s := 0.0
for q in pts:
    s += q.norm2()
print(s, len(pts))
class Node:
    value: int := 0
    children: list[Node] := []
    func init(value: int):
        self.value = value
        self.children = []
    func add(child: Node):
        append(self.children, child)
    func sum() -> int:
        t := self.value
        for ch in self.children:
            t += ch.sum()
        return t
root := Node(1)
a := Node(2)
a.add(Node(3))
root.add(a)
root.add(Node(4))
print(root.sum())

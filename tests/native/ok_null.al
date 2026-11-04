# null et types nullables : T?, raffinement après `if x != null`, `x == null` + sortie anticipée, `while`.
from core use len
from collections use get

func find(xs: list[int], v: int) -> int?:
    i := 0
    for y in xs:
        if y == v:
            return i
        i += 1
    return null

func describe(x: int?) -> str:
    if x == null:
        return "rien"
    return "valeur " + str(x + 1)

class Node:
    value: int := 0
    next: Node? := null
    func init(value: int):
        self.value = value

r := find([4, 5, 6], 5)
print(r, find([1], 9), describe(r), describe(null))
if r != null:
    print(r * 10)
else:
    print("absent")
name: str? := null
print(name, name == null, name != null)
name = "Alex"
if name != null:
    print(len(name), name)
if name:
    print("vrai")
head: Node? := null
for i in 0..5:
    n := Node(i)
    n.next = head
    head = n
total := 0
cur := head
while cur != null:
    total += cur.value
    cur = cur.next
print(total)
scores := {"a": 1.5}
s := get(scores, "a")
t := get(scores, "b")
print(s, t)
if s != null:
    print(s * 2.0)
f: float? := 2.5
print(f, f != null, 1 == null)
x: int? := 0
if x:
    print("faux")
else:
    print("0 et null sont faux")
func first(xs: list[str]) -> str?:
    if len(xs) == 0:
        return null
    return xs[0]
print(first([]), first(["un"]))

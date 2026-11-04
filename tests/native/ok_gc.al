# Ramasse-miettes : beaucoup de déchets (chaînes, listes, objets), des structures vivantes qui doivent
# survivre intactes à de nombreuses collectes, un grand objet (> 32 Kio).
from core use len
from collections use append

class Node:
    value: int := 0
    label: str := ""
    next: list[Node] := []
    func init(value: int):
        self.value = value
        self.label = "n" + str(value)
        self.next = []

func churn(rounds: int) -> int:
    total := 0
    for r in 0..rounds:
        s := "x" + str(r) + "-" + str(r * 2)
        tmp := [r, r + 1, r + 2]
        total += len(s) + tmp[2]
    return total

keep: list[Node] := []
for i in 0..2000:
    n := Node(i)
    if i > 0:
        append(n.next, keep[i - 1])
    append(keep, n)
print(churn(300000))
big: list[int] := []
for i in 0..20000:
    append(big, i * 3)
print(churn(300000))
check := 0
node := keep[1999]
steps := 0
while len(node.next) > 0:
    check += node.value
    node = node.next[0]
    steps += 1
print(steps, check, node.label, keep[1234].label, big[19999], len(big))
words: list[str] := []
for i in 0..50000:
    append(words, "mot" + str(i))
print(words[0], words[49999], len(words))
print(churn(300000))
print(words[25000], keep[7].label)

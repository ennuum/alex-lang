# Compréhensions de liste et de dictionnaire (docs/COMPREHENSIONS.md)
from core use len

func main():
    print([x * x for x in 0..6])
    print([x for x in 0..20 if x % 3 == 0])
    print([(a, b) for a in 0..3 for b in a..3])
    words := ["alpha", "be", "gamma", "pi"]
    lengths := {w: len(w) for w in words}
    print(len({w: 1 for w in words if len(w) > 2}))
    print(lengths["gamma"])
    fs := [() => i * 10 for i in 0..3]
    print([f() for f in fs])

main()

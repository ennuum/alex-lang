# Contrôle : if/elif/else, while, for sur intervalle, break/continue, ternaire, and/or en court-circuit.
func trace(label: str, v: int) -> int:
    print(label)
    return v

func classify(n: int) -> str:
    if n < 0:
        return "négatif"
    elif n == 0:
        return "zéro"
    elif n < 10:
        return "petit"
    else:
        return "grand"

for k in -2..12:
    if k % 4 == 1:
        print(classify(k))

total := 0
i := 0
while true:
    i += 1
    if i > 100:
        break
    if i % 3 == 0:
        continue
    total += i
print(total)

for j in 5..2:
    print("jamais")
for j in 0..3:
    j = 100
    print(j)

n := 0
for a in 0..10:
    for b in 0..10:
        if b > a:
            break
        n += a * b
print(n)

print(1 if total > 1000 else 2)
print(trace("gauche", 0) and trace("droite", 1))
print(trace("gauche", 3) and trace("droite", 4))
print(trace("gauche", 5) or trace("droite", 6))
print(trace("gauche", 0) or trace("droite", 7))
print(true and false, false or true)

count := 0
while count < 3:
    count += 1
else_like := count * 10
print(else_like)

# Exceptions : raise / catch typés / finally (chemin normal, exception, return, break, continue),
# erreurs d'exécution rattrapées, relance, propagation à travers des appels.
from collections use append
from core use len

func risky(k: int) -> int:
    if k == 0:
        return 10 // k
    if k == 1:
        xs := [1, 2]
        return xs[5]
    if k == 2:
        d := {"a": 1}
        return d["zz"]
    if k == 3:
        raise("MonErreur", "perso " + str(k))
    if k == 4:
        raise("message seul")
    return k * 100

func classify(k: int) -> str:
    try:
        v := risky(k)
        return "ok " + str(v)
    catch ZeroDivisionError as e:
        return "zéro : " + e.message
    catch IndexError, KeyError as e:
        return e.type + " : " + e.message
    catch MonErreur as e:
        return "perso : " + e.message
    catch e:
        return "autre : " + str(e)

for k in 0..6:
    print(classify(k))

log: list[str] := []
func with_finally(k: int) -> int:
    try:
        append(log, "corps " + str(k))
        if k == 1:
            return 1
        if k == 2:
            raise("Stop", "arrêt")
        append(log, "fin du corps")
    finally:
        append(log, "finally " + str(k))
    return 0

for k in 0..3:
    try:
        print(with_finally(k))
    catch Stop as e:
        print("Stop rattrapé : " + e.message)
print(log)

steps: list[int] := []
for i in 0..6:
    try:
        if i == 1:
            continue
        if i == 4:
            break
        append(steps, i)
    finally:
        append(steps, 100 + i)
print(steps)

func rethrow() -> str:
    try:
        try:
            raise("A", "a")
        catch B as e:
            return "jamais"
    catch A as e:
        return "A propagé à travers une clause non correspondante : " + e.message
    return "?"
print(rethrow())

func nested(depth: int) -> int:
    if depth == 0:
        raise("Profond", "fond atteint")
    return nested(depth - 1) + 1
try:
    nested(50)
catch Profond as e:
    print(e)

count := 0
total := 0
while count < 1000:
    try:
        total += 100 // (count % 4)
    catch ZeroDivisionError:
        total += 1
    count += 1
print(total)

func value_kept() -> int:
    x := 1
    try:
        x = 5
        raise("E", "e")
    catch E:
        return x
    return -1
print(value_kept())

try:
    try:
        raise("Interne", "i")
    finally:
        print("finally interne")
catch e:
    print("relance après finally : " + e.type)
try:
    raise("Re", "première")
catch e:
    try:
        raise(e)
    catch Re as again:
        print("relancé : " + again.message)

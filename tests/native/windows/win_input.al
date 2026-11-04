# Exécutable Windows : input() sans le CR des fins de ligne CRLF (console, fichiers Windows).
from core use len
n := 0
while true:
    l := input()
    if l == "fin":
        break
    n += 1
    print(str(n) + ":[" + l + "]" + str(len(l)))

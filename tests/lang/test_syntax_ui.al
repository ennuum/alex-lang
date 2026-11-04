# Ajouts au langage pour les interfaces : échappements \xHH, \u{...}, \uXXXX, \e ; virgule finale dans les
# listes, dictionnaires, tuples, appels et paramètres ; core.arity.

from core use len, arity
from collections use append
use string as s

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

check_eq([s.ord("\x1b"[0]), s.ord("\e"[0]), s.ord('\e'), len("\e[0m")], [27, 27, 27, 4], "\\x1b, \\e, caractère '\\e'")
check_eq(["\x41\x42", "é", "\u{1F600}", s.ord("\u{1F600}"[0])], ["AB", "é", "😀", 128512], "\\xHH, \\uXXXX, \\u{...}")
check_eq(f"{1}\x20{2}", "1 2", "échappement dans une f-string")

func f(a, b,):
    return a + b

l := [
    1,
    2,
]
d := {
    "a": 1,
    "b": 2,
}
check_eq([l, d["b"], f(1, 2,), (1, 2,)], [[1, 2], 2, 3, (1, 2)], "virgule finale")

class C:
    func m(x, y=2):
        return x

check_eq([arity((a, b) => a), arity(C().m), arity(() => 1), arity(3)], [[2, 2], [1, 2], [0, 0], null], "core.arity")

print(f"syntaxe : {stats[0]} vérifications OK, {stats[1]} échec(s)")
for n in notes:
    print("  ÉCHEC " + n)
if stats[1] > 0:
    raise("TestError", "test_syntax_ui : échecs")

# Types graduels (docs/TYPES.md) : programmes bien typés et vérifications à l'exécution.
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_types.al
from collections use append
from core use len, to_u8, to_i8, to_u32
use string

failures := []
func check(cond, label):
    if cond:
        print("ok   " + label)
    else:
        print("ÉCHEC " + label)
        append(failures, label)

func type_error(f) -> str:
    try:
        f()
    catch TypeError as e:
        return e.message
    return ""

class Shape:
    func area() -> float:
        return 0.0

class Rect extends Shape:
    w: float := 0.0
    h: float := 0.0
    func init(w: float, h: float):
        self.w = w
        self.h = h
    func area() -> float:
        return self.w * self.h

func total_area(shapes: list[Shape]) -> float:
    t: float := 0
    for s in shapes:
        t += s.area()
    return t

func index_of(xs: list[str], x: str) -> int?:
    i: int := 0
    for v in xs:
        if v == x:
            return i
        i += 1
    return null

func apply(f: func(int) -> int, v: int) -> int:
    return f(v)

func untyped(v):
    return v

# --- programmes bien typés ---
check(total_area([Rect(2.0, 3.0), Rect(1, 1)]) == 7.0, "sous-classe acceptée pour la classe parente, int -> float")
check(index_of(["a", "b"], "b") == 1 and index_of([], "z") == null, "type de retour nullable")
check(apply((n) => n * 10, 4) == 40, "type fonction")
octet: u8 := 255
check(octet == 255, "littéral dans les bornes de u8")
ratio: float := 3
check(ratio == 3, "int accepté pour float")
const LIMIT: i64 := 10
check(LIMIT == 10, "constante annotée (i64 = int)")
names: dict[str, int] := {"a": 1}
check(names["a"] == 1, "dict[str, int]")

# --- vérifications à l'exécution (valeurs venant de code non typé) ---
func double(n: int) -> int:
    return n * 2
func lie() -> int:
    return untyped("pas un int")
func forgets() -> int:
    untyped(0)
func small(b: u8) -> u8:
    return b
func needs_shape(s: Shape) -> float:
    return s.area()

check(type_error(() => double(untyped("x"))) == "paramètre 'n' de double : attendu int, obtenu str", "paramètre")
check(type_error(() => lie()) == "valeur de retour de lie : attendu int, obtenu str", "retour explicite")
check(type_error(() => forgets()) == "valeur de retour de forgets : attendu int, obtenu null", "retour implicite (null)")
check(string.contains(type_error(() => small(untyped(256))), "hors bornes 0..255"), "entier dimensionné hors bornes")
check(type_error(() => needs_shape(untyped(Rect(1, 2)))) == "", "instance de sous-classe acceptée à l'exécution")
check(type_error(() => needs_shape(untyped("x"))) != "", "chaîne refusée pour une classe")

count: int := 0
func bump(v):
    count = v
check(type_error(() => bump("trop")) == "variable 'count' : attendu int, obtenu str", "réaffectation d'une globale annotée")
func local_var():
    s: str := "a"
    s = untyped(1)
check(type_error(() => local_var()) == "variable 's' : attendu str, obtenu int", "réaffectation d'une locale annotée")

# --- conteneurs : vérification profonde, puis écritures contrôlées ---
func sum_ints(xs: list[int]) -> int:
    t: int := 0
    for x in xs:
        t += x
    return t
mixed := untyped([1, 2, "trois"])
check(type_error(() => sum_ints(mixed)) == "paramètre 'xs' de sum_ints : attendu list[int], obtenu list (élément 2 : str)", "élément invalide détecté")
ints := untyped([1, 2, 3])
check(sum_ints(ints) == 6, "liste conforme acceptée")
check(type_error(() => append(ints, "x")) == "élément ajouté : attendu int, obtenu str", "liste marquée : ajout contrôlé")
func set_first(l, v):
    l[0] = v
check(type_error(() => set_first(ints, 1.5)) == "élément de liste : attendu int, obtenu float", "liste marquée : affectation contrôlée")
append(ints, 4)
check(sum_ints(ints) == 10, "ajout conforme accepté")
func wants_strs(xs: list[str]) -> int:
    return len(xs)
check(type_error(() => wants_strs(ints)) == "paramètre 'xs' de wants_strs : attendu list[str], obtenu list (liste de int)", "liste marquée int refusée pour list[str]")
func by_name(m: dict[str, int]) -> int:
    return m["a"]
scores := untyped({"a": 1})
check(by_name(scores) == 1, "dict conforme")
func put(d, k, v):
    d[k] = v
check(type_error(() => put(scores, "b", "x")) == "valeur de dict : attendu int, obtenu str", "dict marqué : valeur contrôlée")
grid := untyped([[1], [2, "z"]])
func cells(g: list[list[int]]) -> int:
    return len(g)
check(type_error(() => cells(grid)) == "paramètre 'g' de cells : attendu list[list[int]], obtenu list (élément 1 : list (élément 1 : str))", "imbrication vérifiée")

# --- entiers dimensionnés ---
level: u8 := 250
func bump_level(n: int) -> int:
    return level + n
check(bump_level(5) == 255, "u8 + int dans les bornes")
check(type_error(() => bump_level(10)) == "débordement de u8 : attendu u8, obtenu int 260 (hors bornes 0..255)", "débordement détecté")
check(to_u8(260) == 4 and to_i8(200) == -56 and to_u32(-1) == 4294967295, "conversions modulo 2^n")

# --- champs annotés ---
class Account:
    balance: int := 0
acc := Account()
func set_balance(a, v):
    a.balance = v
check(type_error(() => set_balance(acc, "beaucoup")) == "champ 'balance' : attendu int, obtenu str", "champ annoté contrôlé à l'exécution")
acc.note = "libre"
check(acc.note == "libre", "champ non déclaré : libre")

# --- raffinement des nullables (if x != null, sortie anticipée, while, affectation) ---
func position(xs: list[str], who: str) -> int?:
    i: int := 0
    for v in xs:
        if v == who:
            return i
        i += 1
    return null
func next_index(xs: list[str], who: str) -> int:
    p: int? := position(xs, who)
    if p == null:
        return -1
    return p + 1
check(next_index(["a", "b"], "b") == 2 and next_index(["a"], "z") == -1, "raffinement après sortie anticipée")
class Cell:
    value: int := 0
    next: Cell? := null
func chain_sum(start: Cell?) -> int:
    total: int := 0
    cur: Cell? := start
    while cur != null:
        total += cur.value
        cur = cur.next
    return total
c1 := Cell()
c1.value = 2
c2 := Cell()
c2.value = 5
c1.next = c2
check(chain_sum(c1) == 7 and chain_sum(null) == 0, "raffinement dans while, affectation d'un T? (le raffinement cesse)")
func label(n: int?) -> str:
    if n != null:
        return "n" + str(n * 2)
    else:
        return "aucun"
check(label(4) == "n8" and label(null) == "aucun", "raffinement dans if / else")

# --- code non annoté : inchangé ---
func dyn(x):
    y := x
    y = "texte"
    return y
check(dyn(1) == "texte", "variables non annotées : dynamiques (any)")

if len(failures) > 0:
    raise("TestFailure", str(len(failures)) + " vérification(s) en échec")
print("test_types : toutes les vérifications passent")

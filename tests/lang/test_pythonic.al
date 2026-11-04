# =============================================================================
# ALEX - fonctionnalités « à la Python » :
#   1. opérateur in / not in ;      2. tranches et indices négatifs ;
#   3. séquences : +, * ;           4. littéraux flottants à exposant ;
#   5. déstructuration ;            6. assert, del.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_pythonic.al
# =============================================================================
from core use len
from collections use append, clear

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check_raises(fn, kind, label):
    raised := ""
    try:
        fn()
    catch e:
        raised = e.type
    check_eq(raised, kind, label)

func run(name, fn):
    clear(notes)
    before := stats[1]
    fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [ok]     {name}")

func t_in():
    check_eq(2 in [1, 2, 3], true, "in liste")
    check_eq(5 in [1, 2, 3], false, "in liste absent")
    check_eq(5 not in [1, 2, 3], true, "not in")
    check_eq("a" in {"a": 1}, true, "in dict (clé)")
    check_eq(1 in {"a": 1}, false, "in dict (pas les valeurs)")
    check_eq("ell" in "hello", true, "in chaîne")
    check_eq('e' in "hello", true, "caractère in chaîne")
    check_eq("z" not in "hello", true, "not in chaîne")
    check_eq(2 in (1, 2), true, "in tuple")
    check_eq([1, 2] in [[1, 2], [3]], true, "in liste de listes")
    check_eq([x for x in [1, 2, 3, 4] if x not in [2, 3]], [1, 4], "filtre not in")
    check_eq(1 + 1 in [2], true, "priorité : arithmétique avant in")
    check_eq(not 3 in [1], true, "not (3 in [1])")
    check_raises(() => 1 in 5, "TypeError", "in sur un entier")

func t_tranches():
    x := [10, 20, 30, 40, 50]
    check_eq(x[1:3], [20, 30], "x[1:3]")
    check_eq(x[:2], [10, 20], "x[:2]")
    check_eq(x[3:], [40, 50], "x[3:]")
    check_eq(x[:], x, "x[:]")
    check_eq(x[::2], [10, 30, 50], "x[::2]")
    check_eq(x[::-1], [50, 40, 30, 20, 10], "x[::-1]")
    check_eq(x[-2:], [40, 50], "x[-2:]")
    check_eq(x[:-1], [10, 20, 30, 40], "x[:-1]")
    check_eq(x[10:], [], "borne hors limites")
    check_eq(x[1:100], [20, 30, 40, 50], "fin tronquée")
    check_eq(x[4:1:-1], [50, 40, 30], "pas négatif")
    check_eq("hello"[1:3], "el", "chaîne")
    check_eq("héllo"[1:3], "él", "chaîne Unicode")
    check_eq("hello"[::-1], "olleh", "chaîne inversée")
    check_eq((1, 2, 3)[1:], (2, 3), "tuple")
    y := x[1:3]
    y[0] = 99
    check_eq(x[1], 20, "la tranche est une copie")
    check_raises(() => x[::0], "ValueError", "pas nul")
    check_raises(() => x["a":2], "TypeError", "borne non entière")

func t_negatifs():
    x := [1, 2, 3]
    check_eq(x[-1], 3, "x[-1]")
    check_eq(x[-3], 1, "x[-3]")
    x[-1] = 9
    check_eq(x, [1, 2, 9], "x[-1] = …")
    check_eq("abc"[-1], 'c', "chaîne [-1]")
    check_eq((1, 2)[-2], 1, "tuple [-2]")
    check_raises(() => x[-4], "IndexError", "x[-4]")
    check_raises(() => "abc"[-4], "IndexError", "chaîne [-4]")

func t_sequences():
    check_eq([1, 2] + [3], [1, 2, 3], "liste + liste")
    check_eq((1,) + (2, 3), (1, 2, 3), "tuple + tuple")
    check_eq([0] * 3, [0, 0, 0], "liste * n")
    check_eq(2 * [1, 2], [1, 2, 1, 2], "n * liste")
    check_eq("ab" * 3, "ababab", "chaîne * n")
    check_eq("ab" * 0, "", "chaîne * 0")
    check_eq("ab" * -1, "", "chaîne * négatif")
    a := [1]
    b := a + [2]
    check_eq(a, [1], "l'opérande n'est pas modifié")
    check_eq(len(b), 2, "longueur du résultat")
    check_raises(() => plus([1], (2,)), "TypeError", "liste + tuple")

func t_flottants():
    check_eq(1e3, 1000.0, "1e3")
    check_eq(2.5e-2, 0.025, "2.5e-2")
    check_eq(1E2, 100.0, "1E2")
    check_eq(6e+2, 600.0, "6e+2")
    check_eq(1e3 + 1, 1001.0, "arithmétique")

func t_destructuration():
    a, b := (1, 2)
    check_eq([a, b], [1, 2], "a, b := tuple")
    a, b = b, a
    check_eq([a, b], [2, 1], "échange")
    x, *rest := [1, 2, 3, 4]
    check_eq([x, rest], [1, [2, 3, 4]], "x, *rest")
    *init, last := [1, 2, 3]
    check_eq([init, last], [[1, 2], 3], "*init, last")
    p, *mid, q := (1, 2, 3, 4, 5)
    check_eq([p, mid, q], [1, (2, 3, 4), 5], "p, *mid, q")
    l := [10, 20]
    l[0], l[1] = l[1], l[0]
    check_eq(l, [20, 10], "échange d'éléments")
    u, v := divmod_like(7, 2)
    check_eq([u, v], [3, 1], "retour multiple")
    total := 0
    for i, c in [[1, 10], [2, 20]]:
        total += i * c
    check_eq(total, 50, "for i, c in …")
    check_raises(() => unpack3([1, 2]), "ValueError", "trop peu de valeurs")
    check_raises(() => unpack3([1, 2, 3, 4]), "ValueError", "trop de valeurs")

func plus(a, b):
    return a + b

func divmod_like(a, b):
    return a // b, a % b

func unpack3(seq):
    a, b, c := seq
    return a

func t_assert_del():
    assert 1 + 1 == 2
    assert true, "jamais levé"
    check_raises(() => check_assert(false), "AssertionError", "assert faux")
    d := {"a": 1, "b": 2}
    del d["a"]
    check_eq(d, {"b": 2}, "del dict")
    l := [1, 2, 3, 4]
    del l[-1]
    del l[0]
    check_eq(l, [2, 3], "del liste")
    check_raises(() => del_missing({"a": 1}), "KeyError", "del clé absente")

func check_assert(c):
    assert c, "message perso"

func del_missing(d):
    del d["zz"]

func va_total(*xs):
    s := 0
    for x in xs:
        s += x
    return s

func va_f(a, b = 10, *rest):
    return [a, b, len(rest)]

func va_rest(p, *rest):
    return rest

struct VaBox:
    func init(*items):
        self.items = items
    func count():
        return len(self.items)

func t_variadic():
    check_eq(va_total(), 0, "variadique vide")
    check_eq(va_total(1, 2, 3), 6, "variadique 3 args")
    xs := [4, 5, 6]
    check_eq(va_total(*xs), 15, "spread d'appel")
    check_eq(va_total(1, *xs, 100), 116, "spread au milieu")
    check_eq(va_total(*(1, 2), *[3]), 6, "spread tuple + liste")
    check_eq(va_f(1), [1, 10, 0], "fixes + défaut + rest vide")
    check_eq(va_f(1, 2, 3, 4), [1, 2, 2], "rest rempli")
    check_eq(va_f(*[1, 2, 3, 4, 5]), [1, 2, 3], "spread sur fixes et rest")
    check_eq(va_rest(1, 2, 3), [2, 3], "rest est une liste")
    check_eq([0, *xs, 9], [0, 4, 5, 6, 9], "liste avec spread")
    check_eq((0, *xs), (0, 4, 5, 6), "tuple avec spread")
    check_eq(len([*"ab"]), 2, "spread de chaîne")
    d := {"a": 1}
    e := {**d, "b": 2, **{"a": 5}}
    check_eq(e["a"], 5, "dict ** (écrase)")
    check_eq(e["b"], 2, "dict ** (ajout)")
    check_eq(VaBox(1, 2, 3).count(), 3, "constructeur variadique")
    h := va_rest
    check_eq(h(1, *xs), [4, 5, 6], "variadique via variable")
    lam := (*a) => len(a)
    check_eq(lam(1, 2, 3), 3, "lambda variadique")
    dyn := va_f
    check_raises(() => dyn(), "ArgumentError", "arité minimale variadique")

func t_syntaxe_diverse():
    x := 5
    check_eq(1 < x < 10, true, "comparaison chaînée vraie")
    check_eq(1 < x < 3, false, "comparaison chaînée fausse")
    check_eq(0 <= x == 5, true, "chaîne mixte <= ==")
    check_eq(0 < x < 10 < 20, true, "chaîne de 3 comparaisons")
    check_eq(x in [1, 5] and 1 < x < 9, true, "chaîne dans une conjonction")
    s := """a
  b "q"
c"""
    check_eq(len(s), 11, "chaîne triple guillemets")
    n := 3
    check_eq(f"""v={n}
w""", "v=3\nw", "f-string triple")
    r := []
    for i in 0..3:
        if i == 9:
            break
    else:
        r.append("range-else")
    for i in [1, 2]:
        if i == 2:
            break
    else:
        r.append("NON")
    for i in [1]:
        pass
    else:
        r.append("liste-else")
    k := 0
    while k < 2:
        k += 1
    else:
        r.append("while-else")
    while true:
        break
    else:
        r.append("NON2")
    check_eq(r, ["range-else", "liste-else", "while-else"], "for/while-else")

class Vec:
    func init(x, y):
        self.x = x
        self.y = y
    func __add__(o):
        return Vec(self.x + o.x, self.y + o.y)
    func __sub__(o):
        return Vec(self.x - o.x, self.y - o.y)
    func __mul__(k):
        return Vec(self.x * k, self.y * k)
    func __rmul__(k):
        return Vec(self.x * k, self.y * k)
    func __neg__():
        return Vec(0 - self.x, 0 - self.y)
    func __eq__(o):
        return self.x == o.x and self.y == o.y
    func __lt__(o):
        return self.x < o.x
    func __str__():
        return f"Vec({self.x}, {self.y})"
    func __len__():
        return 2
    func __contains__(v):
        return v == self.x or v == self.y
    func __getitem__(i):
        if i == 0:
            return self.x
        if i == 1:
            return self.y
        raise("IndexError", "hors limites")
    func __setitem__(i, v):
        if i == 0:
            self.x = v
        else:
            self.y = v
    func __call__(a):
        return a + self.x

class Ressource:
    func init(journal, nom):
        self.journal = journal
        self.nom = nom
    func __enter__():
        self.journal.append("entrée " + self.nom)
        return self
    func __exit__(a, b, c):
        self.journal.append("sortie " + self.nom)

func decore_x2(fn):
    func enveloppe(x):
        return fn(x) * 2
    return enveloppe

@decore_x2
func plus_un(x):
    return x + 1

func avec_return(journal):
    with Ressource(journal, "R") as r:
        return r.nom

func t_surcharge():
    a := Vec(1, 2)
    b := Vec(10, 20)
    check_eq(str(a + b), "Vec(11, 22)", "__add__")
    check_eq(str(b - a), "Vec(9, 18)", "__sub__")
    check_eq(str(a * 3), "Vec(3, 6)", "__mul__")
    check_eq(str(3 * a), "Vec(3, 6)", "__rmul__")
    check_eq(str(-a), "Vec(-1, -2)", "__neg__")
    check_eq(a == Vec(1, 2), true, "__eq__")
    check_eq(a != Vec(1, 2), false, "!= dérivé de __eq__")
    check_eq(a != b, true, "!= vrai")
    check_eq(a < b, true, "__lt__")
    check_eq(b < a, false, "__lt__ faux")
    check_eq(len(a), 2, "__len__")
    check_eq(2 in a, true, "__contains__")
    check_eq(5 in a, false, "__contains__ faux")
    check_eq(a[1], 2, "__getitem__")
    a[1] = 99
    check_eq(a[1], 99, "__setitem__")
    check_eq(a(100), 101, "__call__")
    check_eq(f"{a}", "Vec(1, 99)", "__str__ dans f-string")
    total := 0
    for v in a:
        total += v
    check_eq(total, 100, "itération par __getitem__")
    check_raises(() => a[5], "IndexError", "__getitem__ lève")

func t_with_decorateurs():
    j := []
    with Ressource(j, "A") as r:
        j.append("corps " + r.nom)
    check_eq(j, ["entrée A", "corps A", "sortie A"], "with")
    j2 := []
    check_eq(avec_return(j2), "R", "with + return")
    check_eq(j2, ["entrée R", "sortie R"], "with : sortie garantie sur return")
    check_eq(plus_un(3), 8, "décorateur")

func t_ensembles():
    a := {1, 2, 3}
    b := set([3, 4])
    check_eq(len(a), 3, "len ensemble")
    check_eq(3 in a, true, "in ensemble")
    check_eq(9 in a, false, "in ensemble faux")
    check_eq(sorted(a | b), [1, 2, 3, 4], "union")
    check_eq(sorted(a & b), [3], "intersection")
    check_eq(sorted(a - b), [1, 2], "différence")
    check_eq(sorted(a ^ b), [1, 2, 4], "différence symétrique")
    a.add(10)
    a.discard(1)
    check_eq(sorted(a), [2, 3, 10], "add / discard")
    check_eq({1, 2} == {2, 1}, true, "égalité")
    check_eq({1} <= {1, 2}, true, "sous-ensemble")
    check_eq({1, 2} >= {3}, false, "sur-ensemble")
    check_eq(sorted({x * 2 for x in [1, 2, 2]}), [2, 4], "compréhension d'ensemble")
    check_eq(len(set()), 0, "ensemble vide")
    check_eq(str({1}), "{1}", "str ensemble")
    check_eq(sorted(list({5, 6})), [5, 6], "list(ensemble)")
    check_raises(() => a.remove(404), "KeyError", "remove absent")
    check_eq(type({}), "dict", "{} reste un dict")

print("== fonctionnalités à la Python ==")
run("in / not in", t_in)
run("tranches", t_tranches)
run("indices négatifs", t_negatifs)
run("séquences + et *", t_sequences)
run("flottants à exposant", t_flottants)
run("déstructuration", t_destructuration)
run("assert et del", t_assert_del)
run("variadiques et spread", t_variadic)
run("syntaxe diverse", t_syntaxe_diverse)
run("surcharge d'opérateurs", t_surcharge)
run("with et décorateurs", t_with_decorateurs)
run("ensembles", t_ensembles)
print(f"{stats[0]} vérifications réussies, {stats[1]} échec(s)")
if stats[1] > 0:
    raise("AssertionError", "test_pythonic : échecs")

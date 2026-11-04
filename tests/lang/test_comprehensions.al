# =============================================================================
# ALEX - tests des compréhensions de liste et de dictionnaire :
#   1. liste : élément, filtres, plusieurs filtres, ordre de production ;
#   2. clauses `for` imbriquées, dépendantes, mélangées aux `if` ;
#   3. dictionnaire : clés calculées, écrasement, itération d'un dict ;
#   4. portée : pas de fuite, masquage, itérable évalué avant la variable ;
#   5. fraîcheur : nouvelle collection à chaque évaluation, itérable évalué une fois ;
#   6. fermetures : une variable fraîche par tour, self dans une méthode ;
#   7. exceptions, imbrication, récursion, f-strings, textes multi-lignes.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_comprehensions.al
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

func check_raises(fn, label):
    raised := false
    try:
        fn()
    catch e:
        raised = true
    check_eq(raised, true, label)

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

# --- 1. liste ----------------------------------------------------------------
func t_liste():
    check_eq([x * x for x in 0..5], [0, 1, 4, 9, 16], "carrés")
    check_eq([x for x in 0..10 if x % 2 == 0], [0, 2, 4, 6, 8], "filtre")
    check_eq([x for x in 0..20 if x % 2 == 0 if x % 3 == 0], [0, 6, 12, 18], "deux filtres")
    check_eq([x for x in 0..20 if x % 2 == 0 and x % 3 == 0], [0, 6, 12, 18], "filtre and")
    check_eq([x for x in 0..0], [], "intervalle vide")
    check_eq([x for x in [1, 2, 3] if x > 5], [], "tout filtré")
    check_eq(len([c for c in "abc"]), 3, "chaîne : un Char par tour")
    check_eq([x + 1 for x in [10, 20, 30]], [11, 21, 31], "liste source")
    check_eq([x for x in (1, 2, 3)], [1, 2, 3], "tuple source")
    check_eq([x if x > 0 else 0 for x in [-2, 3, -1, 4]], [0, 3, 0, 4], "ternaire dans l'élément")
    check_eq([x for x in [3, 1, 2]], [3, 1, 2], "ordre conservé")
    check_eq(len([0 for x in 0..1000]), 1000, "grand volume")

# --- 2. imbrication de clauses -------------------------------------------------
func t_clauses():
    check_eq([(a, b) for a in 0..2 for b in 0..2], [(0, 0), (0, 1), (1, 0), (1, 1)], "produit")
    check_eq([(a, b) for a in 0..3 for b in a..3], [(0, 0), (0, 1), (0, 2), (1, 1), (1, 2), (2, 2)], "borne dépendante")
    check_eq([a * 10 + b for a in 0..3 if a != 1 for b in 0..2], [0, 1, 20, 21], "if entre deux for")
    check_eq([a + b for a in 0..3 for b in 0..3 if a != b if a < b], [1, 2, 3], "for puis deux if")
    matrix := [[1, 2], [3, 4], [5, 6]]
    check_eq([v for row in matrix for v in row], [1, 2, 3, 4, 5, 6], "aplatir")
    check_eq([[v * 2 for v in row] for row in matrix], [[2, 4], [6, 8], [10, 12]], "compréhension imbriquée")

# --- 3. dictionnaire -----------------------------------------------------------
func t_dict():
    d := {k: k * k for k in 0..4}
    check_eq(len(d), 4, "taille")
    check_eq(d[3], 9, "valeur")
    e := {"a": 1, "b": 2, "c": 3}
    check_eq({k: e[k] * 10 for k in e}["b"], 20, "itération d'un dict (clés)")
    check_eq(len({k: e[k] for k in e if e[k] > 1}), 2, "dict filtré")
    check_eq({x % 3: x for x in 0..9}[0], 6, "dernier écrase")
    check_eq(len({x % 3: x for x in 0..9}), 3, "clés uniques")
    check_eq(len({a * 10 + b: 0 for a in 0..3 for b in 0..3}), 9, "dict à deux for")
    check_eq(len({k: 1 for k in 0..0}), 0, "dict vide")
    check_eq({f"{k}": [k] for k in 1..3}["2"], [2], "valeur composite")

# --- 4. portée -----------------------------------------------------------------
func t_portee():
    x := "dehors"
    r := [x for x in 0..3]
    check_eq(x, "dehors", "la variable ne fuit pas")
    check_eq(r, [0, 1, 2], "résultat")
    xs := [1, 2, 3]
    check_eq([xs for xs in xs], [1, 2, 3], "for xs in xs lit l'itérable englobant")
    check_eq([x for x in [x, x]], ["dehors", "dehors"], "itérable évalué avant la variable")
    i := 3
    check_eq([i for i in i..5], [3, 4], "for i in i..n : borne = i englobant")
    n := 2
    check_eq([n for n in 0..n], [0, 1], "for n in 0..n : borne = n englobant")
    check_eq([x * y for x in 1..3 for x in 1..3 for y in [x]], [1, 4, 1, 4], "même nom réutilisé (le plus interne gagne)")
    total := 0
    for k in [1, 2]:
        total = total + len([j for j in 0..k])
    check_eq(total, 3, "dans une boucle for")
    z := 10
    w := [z + q for q in 0..2]
    check_eq(w, [10, 11], "variable englobante lue")

# --- 5. fraîcheur et évaluation ------------------------------------------------
func t_fraicheur():
    out := []
    for k in 0..3:
        append(out, [k for k in 0..2])
    out[0][0] = 99
    check_eq(out[1][0], 0, "une liste neuve par évaluation")
    check_eq(out[0], [99, 1], "mutation locale")
    calls := [0]
    func source():
        calls[0] = calls[0] + 1
        return [1, 2, 3]
    r := [x for x in source() if x > 1]
    check_eq(calls[0], 1, "itérable évalué une seule fois")
    seen := []
    func spy(v):
        append(seen, v)
        return v
    [spy(a) for a in 0..3 if spy(a * 10) > 0]
    check_eq(seen, [0, 10, 1, 20, 2], "filtre avant élément, élément omis si filtre faux")

# --- 6. fermetures -------------------------------------------------------------
class Boite:
    func init(k):
        self.k = k
    func multiplier(xs):
        return [x * self.k for x in xs]
    func dict_of(xs):
        return {x: x + self.k for x in xs}

func t_fermetures():
    fs := [() => i for i in 0..3]
    check_eq([f() for f in fs], [0, 1, 2], "une variable fraîche par tour")
    base := 100
    gs := [(v) => v + base + i for i in 0..2]
    check_eq(gs[1](1), 102, "capture d'une variable englobante")
    base = 200
    check_eq(gs[0](0), 200, "capture par référence")
    b := Boite(3)
    check_eq(b.multiplier([1, 2, 3]), [3, 6, 9], "self dans une compréhension")
    check_eq(b.dict_of([1, 2])[2], 5, "self dans une compréhension de dict")
    counters := [(() => j * 2) for j in 0..3 if j != 1]
    check_eq([c() for c in counters], [0, 4], "fermetures filtrées")

# --- 7. divers -----------------------------------------------------------------
func boom(v):
    if v == 2:
        raise("ValueError", "deux")
    return v

func fact_list(n):
    if n == 0:
        return [1]
    return [n * v for v in fact_list(n - 1)]

func t_divers():
    check_raises(() => [boom(v) for v in 0..4], "exception dans l'élément")
    check_raises(() => [v for v in 0..4 if boom(v) > 0], "exception dans le filtre")
    caught := []
    try:
        [boom(v) for v in 0..4]
    catch e:
        append(caught, "pris")
    check_eq(caught, ["pris"], "catch englobant")
    check_eq(fact_list(5), [120], "récursion")
    s := f"{[v + 1 for v in 0..3]}"
    check_eq(s, "[1, 2, 3]", "dans une f-string")
    multi := [
        v * 2
        for v in 0..6
        if v % 2 == 1
    ]
    check_eq(multi, [2, 6, 10], "écriture sur plusieurs lignes")
    dm := {
        k: k + 1
        for k in 0..3
    }
    check_eq(len(dm), 3, "dict sur plusieurs lignes")
    check_eq(len([[a, b] for a in 0..3 for b in 0..3]), 9, "liste de listes")

run("liste", t_liste)
run("clauses imbriquées", t_clauses)
run("dictionnaire", t_dict)
run("portée", t_portee)
run("fraîcheur", t_fraicheur)
run("fermetures", t_fermetures)
run("divers", t_divers)

total := stats[0] + stats[1]
print("")
print("=== COMPRÉHENSIONS ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total})")
if stats[1] > 0:
    raise("AssertionError", f"{stats[1]} vérification(s) en échec")
print("TOUS LES TESTS COMPRÉHENSIONS PASSENT")

# Conformité du runtime (docs/RUNTIME.md) vu d'ALEX : valeurs, exceptions, modèle mémoire, limites.
# Chaque groupe cite les règles qu'il vérifie (V = Value, E = exceptions, M = mémoire, L = limites).

from core use len, type
from collections use append, keys, clear

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

# Type de l'exception levée par f(), ou "ok".
func err_type(f):
    try:
        f()
    catch e:
        return e.type
    return "ok"

func run(name, fn):
    before := stats[1]
    fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")
    clear(notes)

func zero():
    return 0

func zerof():
    return 0.0

# --- V : valeurs ----------------------------------------------------------------

func t_values():
    # V-arith : ADD/SUB/MUL des int bouclent modulo 2^64 ; / donne un float ; // et % arrondissent vers -inf.
    check_eq(9223372036854775807 + 1, -9223372036854775807 - 1, "V-arith : int + déborde en bouclant")
    check_eq(5 / 2, 2.5, "V-arith : int / int -> float")
    check_eq(-7 // 2, -4, "V-arith : // plancher")
    check_eq(-7 % 3, 2, "V-arith : % signe du diviseur (3)")
    check_eq(7 % -3, -2, "V-arith : % signe du diviseur (-3)")
    check_eq(2 ** 10, 1024, "V-arith : ** entier")
    check_eq(2 ** -1, 0.5, "V-arith : exposant négatif -> float")
    check_eq(err_type(() => 1 / zero()), "ZeroDivisionError", "V-arith : int / 0")
    check_eq(err_type(() => 1 // zero()), "ZeroDivisionError", "V-arith : int // 0")
    check_eq(err_type(() => 1 % zero()), "ZeroDivisionError", "V-arith : int % 0")
    check_eq(err_type(() => 1.0 / zerof()), "ZeroDivisionError", "V-arith : float / 0.0 lève (pas d'inf)")
    check_eq(err_type(() => 3 << 64), "TypeError", "V-arith : décalage >= 64")
    # V-eq : égalité.
    check(1 == 1.0, "V-eq : 1 == 1.0")
    check(not (9007199254740993 == 9007199254740992.0), "V-eq : exacte au-delà de 2^53")
    check([1, [2, "a"]] == [1, [2, "a"]], "V-eq : listes structurelles")
    check({"a": 1} == {"a": 1.0}, "V-eq : dict structurel, valeurs 1 == 1.0")
    check(not ([1, 2] == (1, 2)), "V-eq : list != tuple")
    check("ab" == "ab", "V-eq : str par contenu")
    f := () => 1
    g := () => 1
    check(f == f and not (f == g), "V-eq : fonctions par identité")
    # V-hash : clés de dict.
    d := {}
    d[1] = "a"
    d[1.0] = "b"
    check_eq(len(d), 1, "V-hash : 1 et 1.0 sont la MÊME clé")
    check_eq(d[1], "b", "V-hash : dernière écriture")
    d[(1, "x")] = 7
    check_eq(d[(1, "x")], 7, "V-hash : tuple comme clé")
    check_eq(err_type(bad_key_list), "TypeError", "V-hash : list non hashable")
    check_eq(err_type(bad_key_dict), "TypeError", "V-hash : dict non hashable")
    # V-truth : cinq valeurs falsy.
    falsy := [false, null, 0, 0.0, ""]
    for v in falsy:
        check(not v, f"V-truth : falsy {v}")
    for v in [true, 1, "0", [], {}, (1, 2), -1, 0.1]:
        check(bool_of(v), f"V-truth : truthy {v}")
    # V-type : noms de types.
    check_eq([type(1), type(1.5), type("s"), type(true), type(null), type([1]), type({}), type((1, 2))],
             ["int", "float", "str", "bool", "null", "list", "dict", "tuple"], "V-type : noms")

func bad_key_list():
    k := [1]
    d := {}
    d[k] = 2

func bad_key_dict():
    k := {}
    d := {}
    d[k] = 2

func bool_of(v):
    if v:
        return true
    return false

# --- M : modèle mémoire ------------------------------------------------------------

func mutate(l):
    append(l, 99)

func rebind(l):
    l = [0]
    return l

func make_counter():
    n := 0
    func inc():
        n = n + 1
        return n
    return inc

func t_memory_model():
    # M-alias : les collections sont partagées par référence ; les scalaires et str sont des valeurs.
    a := [1, 2]
    b := a
    mutate(b)
    check_eq(a, [1, 2, 99], "M-alias : mutation visible par tous les alias")
    c := rebind(a)
    check_eq(a, [1, 2, 99], "M-alias : réaffecter un paramètre ne change pas l'appelant")
    check_eq(c, [0], "M-alias : valeur retournée")
    s1 := "abc"
    s2 := s1
    s1 = s1 + "d"
    check_eq(s2, "abc", "M-alias : str immuable")
    d := {"k": [1]}
    e := d
    append(e["k"], 2)
    check_eq(d["k"], [1, 2], "M-alias : dict et valeurs partagés")
    # M-cycle : une structure peut se contenir ; l'affichage termine.
    cyc := []
    append(cyc, cyc)
    check_eq(str(cyc), "[[...]]", "M-cycle : affichage fini")
    cyc2 := []
    append(cyc2, cyc2)
    check_eq(err_type(() => cyc == cyc2), "RecursionError", "M-cycle : égalité de deux cycles distincts -> RecursionError")
    check(cyc == cyc, "M-cycle : identité")
    # M-closure : capture PAR RÉFÉRENCE (cellule partagée), y compris après le retour de la fonction déclarante.
    c1 := make_counter()
    c2 := make_counter()
    c1()
    c1()
    check_eq(c1(), 3, "M-closure : l'état survit à l'appel déclarant")
    check_eq(c2(), 1, "M-closure : chaque fermeture a sa propre cellule")
    fs := []
    for i in [0, 1, 2]:
        append(fs, () => i * 10)
    check_eq([fs[0](), fs[1](), fs[2]()], [0, 10, 20], "M-closure : une cellule fraîche par itération")
    # M-eval : évaluation des arguments de gauche à droite.
    order := []
    func mark(x):
        append(order, x)
        return x
    func three(a, b, c):
        return a + b + c
    three(mark(1), mark(2), mark(3))
    check_eq(order, [1, 2, 3], "M-eval : gauche à droite")

# --- E : exceptions -------------------------------------------------------------------

# Valeur non typée : `1 + "a"` écrit en littéral serait refusé à la compilation (TypeCheckError).
func untyped_text():
    return "a"

func thrower(kind):
    if kind == "zero":
        return 1 // zero()
    if kind == "index":
        return [1][5]
    if kind == "key":
        return {"a": 1}["b"]
    if kind == "type":
        return 1 + untyped_text()
    if kind == "raise":
        raise("MonErreur", "détail")
    return null

func t_exceptions_codes():
    # E-code : type de l'exception = nom du code runtime ; raise(type, msg) accepte n'importe quel nom.
    check_eq(err_type(() => thrower("zero")), "ZeroDivisionError", "E-code : ZeroDivisionError")
    check_eq(err_type(() => thrower("index")), "IndexError", "E-code : IndexError")
    check_eq(err_type(() => thrower("key")), "KeyError", "E-code : KeyError")
    check_eq(err_type(() => thrower("type")), "TypeError", "E-code : TypeError")
    check_eq(err_type(() => thrower("raise")), "MonErreur", "E-code : type libre via raise")
    try:
        thrower("raise")
    catch e:
        check_eq(e.message, "détail", "E-code : message")
        check_eq(str(e), "MonErreur: détail", "E-code : affichage « type: message »")
    check_eq(err_type(() => raise(1, "x")), "TypeError", "E-code : raise exige des str")
    check_eq(err_type(() => raise("T", 2)), "TypeError", "E-code : raise exige un message str")
    check_eq(err_type(() => 5()), "TypeError", "E-code : appeler un non-fonction")

func inner_unwind():
    thrower("zero")
    return "pas atteint"

func middle_unwind():
    inner_unwind()
    return "pas atteint"

func catcher():
    try:
        middle_unwind()
        return "pas atteint"
    catch e:
        return "capturé " + e.type

func t_exceptions_unwind():
    # E-unwind : l'exception remonte les frames jusqu'au handler le plus proche.
    check_eq(catcher(), "capturé ZeroDivisionError", "E-unwind : à travers 3 frames")
    # E-nest : le handler le plus interne reçoit en premier ; une exception levée DANS un catch passe au suivant.
    out := []
    try:
        try:
            try:
                raise("A", "1")
            catch e1:
                append(out, "c1:" + e1.type)
                raise("B", "2")
        catch e2:
            append(out, "c2:" + e2.type)
            raise("C", "3")
    catch e3:
        append(out, "c3:" + e3.type)
    check_eq(out, ["c1:A", "c2:B", "c3:C"], "E-nest : cascade de rethrow")
    # E-pass : sans exception, le catch n'est pas exécuté et le handler est retiré (TRY_END).
    ran := [false]
    try:
        x := 1
    catch e4:
        ran[0] = true
    check(not ran[0], "E-pass : catch ignoré sans exception")
    check_eq(err_type(() => thrower("raise")), "MonErreur", "E-pass : l'exception suivante n'est pas avalée par un handler retiré")
    # E-stack : la pile d'opérandes est purgée à la reprise (expression partielle abandonnée).
    r := [1, 2, 3, 4]
    v := null
    try:
        v = [10, 20, thrower("zero"), 40]
    catch e5:
        v = "purgé"
    check_eq(v, "purgé", "E-stack : valeur partielle abandonnée")
    check_eq(r, [1, 2, 3, 4], "E-stack : état voisin intact")

func loop_break_then_raise():
    while true:
        try:
            break
        catch e:
            return "handler périmé (break)"
    raise("X", "après la boucle")

func loop_continue_then_raise():
    i := 0
    while i < 2:
        i = i + 1
        try:
            continue
        catch e:
            return "handler périmé (continue)"
    raise("Y", "après la boucle")

func nested_break_then_raise():
    for i in [1, 2, 3]:
        try:
            try:
                break
            catch e:
                return "périmé interne"
        catch e2:
            return "périmé externe"
    raise("Z", "après la boucle")

func for_break_in_catch():
    for i in [1, 2]:
        try:
            raise("Q", "q")
        catch e:
            break
    raise("W", "après")

func wrap(f):
    try:
        f()
    catch e:
        return "dehors " + e.type
    return "ok"

func t_exceptions_handlers():
    # E7 : break/continue qui sortent d'un try désinstallent son handler.
    check_eq(wrap(loop_break_then_raise), "dehors X", "E7 : break hors d'un try")
    check_eq(wrap(loop_continue_then_raise), "dehors Y", "E7 : continue hors d'un try")
    check_eq(wrap(nested_break_then_raise), "dehors Z", "E7 : break hors de deux try imbriqués")
    check_eq(wrap(for_break_in_catch), "dehors W", "E7 : break dans un catch")

func ret_in_try():
    try:
        return 1
    catch e:
        return 2

func after_return_raises():
    ret_in_try()
    raise("R", "x")

func t_exceptions_return():
    # E-return : return dans un try détruit le frame et son handler.
    check_eq(wrap(after_return_raises), "dehors R", "E-return : pas de handler résiduel")
    check_eq(ret_in_try(), 1, "E-return : valeur retournée")

func lam_raises():
    return () => thrower("raise")

func t_exceptions_lambda():
    # E-closure : une exception levée dans une fermeture traverse son appelant comme dans une fonction.
    f := lam_raises()
    check_eq(err_type(f), "MonErreur", "E-closure : lambda")
    # E-top : une lambda sans paramètre déclarée au niveau supérieur ne remplace pas le programme (cf. mergeModules).
    check(top_lambda() == 7, "E-top : lambda de haut niveau appelable")

top_lambda := () => 7

# --- L : limites ------------------------------------------------------------------------

func rec(n):
    return rec(n + 1)

func rec_ok(n):
    if n == 0:
        return "fond"
    return rec_ok(n - 1)

func t_limits():
    # L-depth : récursion infinie -> RecursionError capturable ; la VM reste utilisable ensuite.
    check_eq(err_type(() => rec(0)), "RecursionError", "L-depth : RecursionError")
    check_eq(rec_ok(20000), "fond", "L-depth : 20000 niveaux licites")
    check_eq(rec_ok(5), "fond", "L-depth : la VM est saine après l'erreur")
    # L-oom : mémoire insuffisante -> MemoryError capturable.
    check_eq(err_type(huge), "MemoryError", "L-oom : allocation démesurée")

use string as _str

func huge():
    return _str.repeat("abcdefgh", 100000000000)

func main():
    run("V : valeurs (arithmétique, égalité, hachage, vérité)", t_values)
    run("M : modèle mémoire (alias, cycles, fermetures)", t_memory_model)
    run("E : codes et types d'exceptions", t_exceptions_codes)
    run("E : désenroulage, imbrication, pile", t_exceptions_unwind)
    run("E : handlers après break/continue/return", t_exceptions_handlers)
    run("E : return dans try", t_exceptions_return)
    run("E : exceptions et fermetures", t_exceptions_lambda)
    run("L : limites (profondeur, mémoire)", t_limits)

main()
print(f"runtime : {stats[0]} vérifications OK, {stats[1]} échec(s)")
if stats[1] > 0:
    raise("AssertionError", "test_runtime : échecs")

# =============================================================================
# ALEX - tests des fonctions imbriquées, des lambdas et des fermetures :
#   1. trois syntaxes de lambda, arité, valeurs par défaut, appel immédiat ;
#   2. capture PAR RÉFÉRENCE : état partagé, compteurs indépendants ;
#   3. une variable fraîche par itération de boucle ;
#   4. hissage des fonctions imbriquées, récursion directe et mutuelle ;
#   5. imbrication sur plusieurs niveaux, noms identiques sans collision ;
#   6. self / super, match, catch, paramètres ;
#   7. fermetures à travers un module importé.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_closures.al
# =============================================================================
from collections use append, clear
from closure_fixture use make_counter, scaler, twice
use closure_fixture as cf

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
        print(f"  [OK]     {name}")

class Account:
    total := 0
    func init(start):
        self.total = start
    func adder():
        return x => self.total + x
    func bumper():
        func bump(d):
            self.total = self.total + d
            return self.total
        return bump

class Savings extends Account:
    func describe():
        return "compte"

class Premium extends Savings:
    func describe():
        f := () => super.describe() + " premium"
        return f()

# --- 1. Lambdas -------------------------------------------------------------

func t_lambda_forms():
    add := (a, b) => a + b
    sq := x => x * x
    k := func(x) => x + 100
    zero := () => 7
    check_eq(add(2, 3), 5, "(a, b) => ...")
    check_eq(sq(7), 49, "x => ...")
    check_eq(k(1), 101, "func(x) => ...")
    check_eq(zero(), 7, "() => ...")
    check_eq((x => x * 2)(21), 42, "appel immédiat")
    check_eq(((x, y) => x - y)(10, 4), 6, "appel immédiat à deux paramètres")

func t_lambda_defaults_arity():
    f := (x, y = 10) => x + y
    check_eq(f(1), 11, "défaut utilisé")
    check_eq(f(1, 2), 3, "défaut remplacé")
    check_raises(() => f(), "trop peu d'arguments")
    check_raises(() => f(1, 2, 3), "trop d'arguments")

func t_lambda_body_extent():
    cond := n => "neg" if n < 0 else "pos"
    check_eq(cond(-1), "neg", "corps conditionnel (négatif)")
    check_eq(cond(1), "pos", "corps conditionnel (positif)")
    pair := [x => x + 1, x => x * 2]
    check_eq(pair[0](1) + pair[1](5), 12, "lambdas séparées par une virgule")
    check_eq((x => x)(1) == 1, true, "groupement d'une lambda")

func t_lambda_is_value():
    f := x => x
    g := x => x
    check_eq(f == f, true, "identité d'une fermeture")
    check_eq(f == g, false, "deux lambdas distinctes")
    check_eq(f"{f}", "<function <lambda>>", "affichage")

# --- 2. Capture par référence ---------------------------------------------------

func t_shared_state():
    n := 0
    func inc():
        n += 1
        return n
    func get():
        return n
    inc()
    inc()
    check_eq(get(), 2, "deux fermetures partagent la même variable")
    n = 10
    check_eq(inc(), 11, "l'affectation de la fonction englobante est vue par la fermeture")

func t_independent_counters():
    c := make_counter_local(0)
    d := make_counter_local(100)
    c()
    c()
    check_eq(c(), 3, "premier compteur")
    check_eq(d(), 101, "second compteur indépendant")

func make_counter_local(start):
    n := start
    func tick():
        n = n + 1
        return n
    return tick

func t_capture_parameter():
    func late(p):
        f := () => p
        p = p + 1
        return f()
    check_eq(late(1), 2, "le paramètre capturé est lu à l'appel, pas à la création")

func t_capture_global():
    g := 1
    # `g` est ici local ; la lambda de haut niveau ci-dessous capture une VRAIE globale.
    check_eq(global_reader(), global_value, "lecture d'une globale")
    check_eq(g, 1, "local intact")

global_value := 5
global_reader := () => global_value

# --- 3. Boucles -----------------------------------------------------------------------

func t_loop_range():
    fns := []
    for i in 0..3:
        append(fns, () => i * 10)
    out := []
    for f in fns:
        append(out, f())
    check_eq(out, [0, 10, 20], "for a..b : une variable par itération")

func t_loop_iterable():
    gs := []
    for it in ["a", "b", "c"]:
        append(gs, () => it)
    check_eq([gs[0](), gs[1](), gs[2]()], ["a", "b", "c"], "for x in liste : une variable par itération")

func t_loop_while_block_var():
    ws := []
    k := 0
    while k < 3:
        j := k
        append(ws, () => j)
        k = k + 1
    check_eq([ws[0](), ws[1](), ws[2]()], [0, 1, 2], "variable de bloc d'un while : une cellule par itération")

# --- 4. Hissage et récursion ----------------------------------------------------------

func t_hoist_call_before_decl():
    y := 5
    r := helper()
    func helper():
        return y + 1
    check_eq(r, 6, "appel avant la déclaration")
    y = 10
    check_eq(helper(), 11, "la variable est partagée, pas copiée")

func t_hoist_early_read_error():
    check_raises(() => early(), "lecture d'une variable pas encore déclarée")
    z := 1
    func early():
        return z
    check_eq(early(), 1, "une fois déclarée, la lecture réussit")

func t_recursion():
    func fib(k):
        if k < 2:
            return k
        return fib(k - 1) + fib(k - 2)
    check_eq(fib(15), 610, "récursion directe d'une fonction imbriquée")
    fact := null
    fact = n => 1 if n <= 1 else n * fact(n - 1)
    check_eq(fact(6), 720, "récursion d'une lambda via une variable")

func t_mutual_recursion():
    func is_even(m):
        if m == 0:
            return true
        return is_odd(m - 1)
    func is_odd(m):
        if m == 0:
            return false
        return is_even(m - 1)
    check_eq(is_even(10), true, "récursion mutuelle (pair)")
    check_eq(is_odd(7), true, "récursion mutuelle (impair)")

# --- 5. Imbrication, noms ----------------------------------------------------------

func t_deep():
    a := 1
    func l1():
        b := 2
        func l2():
            c := 3
            return () => a + b + c
        return l2()
    check_eq(l1()(), 6, "capture à travers trois niveaux")

func t_curry():
    adder := a1 => (b1 => (c1 => a1 + b1 + c1))
    check_eq(adder(1)(2)(3), 6, "lambdas imbriquées")

func name_clash_a():
    func helper():
        return "a"
    return helper()

func name_clash_b():
    func helper():
        return "b"
    return helper()

func t_same_name_no_clash():
    check_eq(name_clash_a(), "a", "helper de a")
    check_eq(name_clash_b(), "b", "helper de b")

func t_named_args_nested():
    func f(x, y = 5):
        return x * 10 + y
    check_eq(f(1), 15, "défaut d'une fonction imbriquée")
    check_eq(f(1, y = 2), 12, "argument nommé")
    check_eq(f(y = 3, x = 4), 43, "arguments nommés dans le désordre")

func t_higher_order():
    check_eq(twice(x => x + 3)(1), 7, "fonction d'ordre supérieur")
    check_eq(compose(x => x + 1, x => x * 2)(5), 11, "composition")
    check_eq(apply_n(v => v * 2, 5, 1), 32, "application répétée")

func compose(f, g):
    return x => f(g(x))

func apply_n(f, n, x):
    r := x
    for i in 0..n:
        r = f(r)
    return r

func t_shadowing():
    x := 1
    seen := 0
    if true:
        y := x + 1
        g := () => x + y
        x := 50
        seen = g()
    check_eq(seen, 3, "la lambda voit la variable englobante, pas celle déclarée plus bas")
    check_eq(x, 1, "la variable du bloc interne ne fuit pas")

# --- 6. self, super, match, catch --------------------------------------------------------

func t_self_capture():
    a := Account(5)
    check_eq(a.adder()(3), 8, "lambda capturant self")
    b := a.bumper()
    b(2)
    check_eq(b(3), 10, "fonction imbriquée modifiant self")

func t_super_in_lambda():
    check_eq(Premium(0).describe(), "compte premium", "super dans une lambda")

func pick(v):
    match v:
        1:
            return () => "un"
        other:
            return () => other

func t_match_capture():
    check_eq(pick(1)(), "un", "motif littéral")
    check_eq(pick(42)(), 42, "motif liaison capturé")

func t_catch_capture():
    fs := []
    for n in 0..2:
        try:
            raise("Err", f"boom {n}")
        catch e:
            append(fs, () => e)
    check_eq(len_of(fs), 2, "une fermeture par catch")
    check_eq(fs[0]() == fs[1](), false, "chaque catch garde SON erreur")

func len_of(l):
    c := 0
    for x in l:
        c = c + 1
    return c

# --- 7. Modules --------------------------------------------------------------------------------

func t_module():
    c1 := make_counter(10)
    c1()
    check_eq(c1(), 12, "compteur importé")
    check_eq(scaler(2)(21), 42, "lambda renvoyée par un module")
    check_eq(cf.twice(scaler(2))(3), 12, "accès qualifié")
    check_eq(cf.make_counter(0)(), 1, "compteur neuf à chaque appel")

run("formes de lambda", t_lambda_forms)
run("lambda : défauts et arité", t_lambda_defaults_arity)
run("lambda : étendue du corps", t_lambda_body_extent)
run("lambda : valeur de première classe", t_lambda_is_value)
run("état partagé", t_shared_state)
run("compteurs indépendants", t_independent_counters)
run("capture d'un paramètre", t_capture_parameter)
run("capture d'une globale", t_capture_global)
run("boucle for a..b", t_loop_range)
run("boucle for x in liste", t_loop_iterable)
run("variable de bloc dans while", t_loop_while_block_var)
run("hissage : appel avant déclaration", t_hoist_call_before_decl)
run("hissage : lecture trop tôt", t_hoist_early_read_error)
run("récursion", t_recursion)
run("récursion mutuelle", t_mutual_recursion)
run("imbrication profonde", t_deep)
run("lambdas imbriquées", t_curry)
run("mêmes noms sans collision", t_same_name_no_clash)
run("arguments nommés (imbriquée)", t_named_args_nested)
run("ordre supérieur", t_higher_order)
run("masquage", t_shadowing)
run("self", t_self_capture)
run("super", t_super_in_lambda)
run("match", t_match_capture)
run("catch", t_catch_capture)
run("module importé", t_module)

total := stats[0] + stats[1]
print("")
print("=== FERMETURES ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total})")
if stats[1] > 0:
    raise("AssertionError", f"{stats[1]} vérification(s) en échec")
print("TOUS LES TESTS FERMETURES PASSENT")

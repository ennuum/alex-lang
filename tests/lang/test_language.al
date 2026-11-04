# =============================================================================
# ALEX - tests des fonctionnalités du langage :
#   1. hissage des déclarations (ordre des fonctions, récursion mutuelle) ;
#   2. struct et enum exportés entre fichiers (from-use et accès qualifié) ;
#   3. arguments nommés vers une fonction ou un constructeur importé (y compris « module.f(x=1) »).
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_language.al
# =============================================================================
from lang_fixture_shapes use Vec, Counter, Bare, Color, make_vec, norm2, color_name, power, is_even
use lang_fixture_shapes
use lang_fixture_shapes as sh
from collections use append, clear

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

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

# --- 1. Hissage ------------------------------------------------------------
# Ces appels précèdent la déclaration des fonctions : seul le hissage les permet.

func t_hoisting():
    check_eq(later(), 42, "appel avant déclaration")
    check_eq(ping(10), "fin ping", "récursion mutuelle ping/pong")
    check_eq(even_local(8), true, "même/impair local pair")
    check_eq(even_local(7), false, "même/impair local impair")
    check_eq(read_const_declared_below(), 7, "une fonction lit un const déclaré plus bas")
    check_eq(build_point(3).twice(), 6, "struct déclarée plus bas, utilisée plus haut")
    check_eq(is_even(10), true, "récursion mutuelle dans un module importé")
    check_eq(lang_fixture_shapes.is_odd(7), true, "idem, accès qualifié")

func later():
    return helper_defined_after() + 2

func helper_defined_after():
    return 40

func ping(n):
    if n == 0:
        return "fin ping"
    return pong(n - 1)

func pong(n):
    if n == 0:
        return "fin pong"
    return ping(n - 1)

func even_local(n):
    if n == 0:
        return true
    return odd_local(n - 1)

func odd_local(n):
    if n == 0:
        return false
    return even_local(n - 1)

func read_const_declared_below():
    return LATE_CONST

LATE_CONST := 7

func build_point(a):
    return Doubler(a)

struct Doubler:
    func init(v):
        self.v = v
    func twice():
        return self.v * 2

# --- 2. struct / enum exportés ----------------------------------------------

func t_struct_import():
    a := Vec(3, 4)
    check_eq(a.x, 3, "champ x")
    check_eq(a.y, 4, "champ y")
    check_eq(a.dot(Vec(1, 2)), 11, "méthode dot")
    check_eq(Vec(5).y, 0.0, "valeur par défaut de init")
    check_eq(a.scaled(2).x, 6, "méthode qui construit une Vec")
    check_eq(norm2(a), 25, "fonction du module recevant une Vec")
    check_eq(make_vec(1).dot(make_vec(1)), 5.0, "fonction du module construisant une Vec")
    c := Counter()
    c.bump()
    check_eq(c.bump(5), 6, "état d'instance conservé")
    check_eq(Counter(10).bump(), 11, "init avec argument")
    check_eq(Bare().tag(), "bare", "struct sans init")
    check_eq(str(Vec(1, 2)), "<Vec instance>", "affichage sans préfixe de module")

func t_struct_qualified():
    v := lang_fixture_shapes.Vec(3, 4)
    check_eq(v.dot(sh.Vec(1, 1)), 7, "module.Vec(...)")
    check_eq(sh.Counter(2).bump(3), 5, "alias.Counter(...)")
    check_eq(lang_fixture_shapes.norm2(v), 25, "module.fonction")
    # Un objet créé par le module et un créé ici ont le même type : méthodes interchangeables.
    check_eq(norm2(lang_fixture_shapes.make_vec(3, 4)), 25.0, "types identiques")

func t_enum_import():
    check_eq(color_name(Color.Red), "rouge", "variante sans charge")
    check_eq(color_name(Color.Rgb(1, 2, 3)), "rgb(1,2,3)", "variante avec charge")
    check_eq(color_name(Color.Green), "autre", "variante non listée")
    check_eq(lang_fixture_shapes.color_name(lang_fixture_shapes.Color.Red), "rouge", "module.Enum.Variante")
    check_eq(color_name(sh.Color.Rgb(7, 8, 9)), "rgb(7,8,9)", "alias.Enum.Variante(...)")
    check_eq(sh.color_name(Color.Green), "autre", "enum local vs fonction qualifiée")

# --- 3. Arguments nommés ----------------------------------------------------

func t_named_args():
    check_eq(power(2), 4, "défauts")
    check_eq(power(2, offset=1), 5, "nommé, défaut intermédiaire conservé")
    check_eq(power(exp=3, base=2), 8, "ordre libre")
    check_eq(power(2, 3, offset=4), 12, "positionnels puis nommé")
    check_eq(lang_fixture_shapes.power(3, offset=1), 10, "module.f(x=...)")
    check_eq(sh.power(offset=2, base=2, exp=4), 18, "alias.f(x=...)")
    v := Vec(y=2.0, x=1.0)
    check_eq(v.x, 1.0, "constructeur importé : x nommé")
    check_eq(v.y, 2.0, "constructeur importé : y nommé")
    check_eq(sh.Vec(y=5, x=1).y, 5, "alias.Struct(x=...)")
    check_eq(Counter(start=7).bump(), 8, "constructeur : défaut remplacé")
    check_eq(make_vec(b=4.0, a=3).dot(make_vec(1, 1)), 7.0, "make_vec(b=, a=)")

run("hissage des déclarations", t_hoisting)
run("struct importée (from-use)", t_struct_import)
run("struct accès qualifié", t_struct_qualified)
run("enum importé", t_enum_import)
run("arguments nommés importés / qualifiés", t_named_args)

total := stats[0] + stats[1]
print("")
print("=== LANGAGE ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total})")
if stats[1] > 0:
    raise("AssertionError", f"{stats[1]} vérification(s) en échec")
print("TOUS LES TESTS LANGAGE PASSENT")

# Test du langage — orienté objet (class, extends, super, implements, isinstance).
#
# Couvre :
#   1. classes, constructeur, champs par défaut, méthodes ;
#   2. héritage, redéfinition, super (chaîne sur plusieurs niveaux), constructeur hérité ;
#   3. interfaces et isinstance ;
#   4. polymorphisme (méthode redéfinie appelée via une méthode héritée) ;
#   5. classes, interfaces et héritage exportés entre modules (from-use, accès qualifié).

from oop_fixture_zoo use Animal, Cat, Speaker, make_cat
use oop_fixture_zoo as zoo
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

interface Shape:
    func area()
    func scale(k)

class Base:
    kind := "base"
    count := 0
    func init(x):
        self.x = x
        self.count = self.count + 1
    func value():
        return self.x
    func twice():
        return self.value() * 2
    func name():
        return "Base"

class Mid extends Base:
    func init(x, y):
        super.init(x)
        self.y = y
    func value():
        return super.value() + self.y
    func name():
        return "Mid>" + super.name()

class Leaf extends Mid:
    kind := "leaf"
    func name():
        return "Leaf>" + super.name()

class Square implements Shape:
    func init(side):
        self.side = side
    func area():
        return self.side * self.side
    func scale(k):
        return Square(self.side * k)

class NoCtor:
    func hello():
        return "hi"

# Déclarée APRÈS son usage dans t_hoisting : le registre est rempli avant toute instruction.
func t_hoisting():
    check_eq(Late(2).double(), 4, "classe utilisable avant sa déclaration")

class Late:
    func init(n):
        self.n = n
    func double():
        return self.n * 2

func t_basics():
    b := Base(5)
    check_eq(b.value(), 5, "méthode simple")
    check_eq(b.kind, "base", "champ par défaut")
    check_eq(b.count, 1, "champ par défaut modifié par init")
    b.x = 9
    check_eq(b.value(), 9, "affectation de champ")
    check_eq(NoCtor().hello(), "hi", "classe sans constructeur")
    check_eq(Base(1).count, 1, "chaque instance a ses propres champs")

func t_inheritance():
    m := Mid(10, 3)
    check_eq(m.value(), 13, "redéfinition + super.value()")
    check_eq(m.twice(), 26, "méthode héritée appelle la redéfinition (polymorphisme)")
    check_eq(m.name(), "Mid>Base", "super.name()")
    check_eq(m.kind, "base", "champ par défaut hérité")
    check_eq(m.count, 1, "init de la base exécuté via super.init")
    l := Leaf(1, 2)
    check_eq(l.name(), "Leaf>Mid>Base", "super sur trois niveaux")
    check_eq(l.value(), 3, "méthode héritée de deux niveaux")
    check_eq(l.kind, "leaf", "champ par défaut redéfini")
    check_eq(l.count, 1, "constructeur hérité de Mid")

func t_isinstance():
    l := Leaf(1, 2)
    check_eq(isinstance(l, Leaf), true, "type exact")
    check_eq(isinstance(l, Mid), true, "parent direct")
    check_eq(isinstance(l, Base), true, "ancêtre")
    check_eq(isinstance(Base(1), Leaf), false, "pas de remontée inverse")
    check_eq(isinstance(5, Base), false, "valeur non-instance")
    check_eq(isinstance(Square(2), Shape), true, "interface implémentée")
    check_eq(isinstance(l, Shape), false, "interface non implémentée")

func t_interface():
    s := Square(3)
    check_eq(s.area(), 9, "méthode d'interface")
    check_eq(s.scale(2).area(), 36, "méthode d'interface renvoyant une instance")

func t_modules():
    a := Animal("Rex")
    check_eq(a.label(), "Rex:...", "classe importée")
    check_eq(a.legs, 4, "champ par défaut d'une classe importée")
    c := Cat("Tom")
    check_eq(c.label(), "Tom:miaou", "méthode héritée d'un module, redéfinition appliquée")
    check_eq(make_cat("Mia").label(), "Mia:miaou", "instance créée dans le module")
    check_eq(zoo.Cat("Zed").label(), "Zed:miaou", "constructeur qualifié")
    check_eq(isinstance(c, Animal), true, "isinstance sur ancêtre importé")
    check_eq(isinstance(c, Speaker), true, "interface importée, héritée via la base")
    check_eq(isinstance(a, Cat), false, "pas de remontée inverse (importé)")
    check_eq(isinstance(c, zoo.Animal), true, "isinstance avec type qualifié alias.Type")
    check_eq(isinstance(c, zoo.Speaker), true, "isinstance avec interface qualifiée")
    check_eq(isinstance(a, zoo.Cat), false, "isinstance qualifié : pas de remontée inverse")
    check_eq(isinstance(7, zoo.Animal), false, "isinstance qualifié sur une non-instance")

# Sous-classe locale d'une classe importée : constructeur et champs hérités du module.
class Lion extends Animal:
    func speak():
        return "ROAR " + super.speak()

func t_extend_imported():
    lion := Lion("Leo")
    check_eq(lion.label(), "Leo:ROAR ...", "extends d'une classe importée + super")
    check_eq(lion.legs, 4, "champ par défaut hérité d'un module")
    check_eq(isinstance(lion, Animal), true, "isinstance ancêtre importé")
    check_eq(isinstance(lion, Speaker), true, "interface héritée d'un module")

run("hissage des classes", t_hoisting)
run("classes de base", t_basics)
run("héritage et super", t_inheritance)
run("isinstance", t_isinstance)
run("interfaces", t_interface)
run("classes exportées", t_modules)
run("extends d'une classe importée", t_extend_imported)

total := stats[0] + stats[1]
print("")
print("=== ORIENTÉ OBJET ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total})")
if stats[1] > 0:
    raise("AssertionError", f"{stats[1]} vérification(s) en échec")
print("TOUS LES TESTS ORIENTÉ OBJET PASSENT")

# Démonstration de l'orienté objet en ALEX : class, extends, super, implements, isinstance.
#
#   alexc run examples/oop_demo.al

# Une interface est un contrat : des signatures sans corps. Une classe qui `implements` une interface
# DOIT fournir chaque méthode (vérifié à l'analyse, avant toute exécution).
interface Shape:
    func area()
    func describe()

# Classe de base : champs par défaut (`nom := valeur`), constructeur `init`, méthodes.
class Polygon implements Shape:
    sides := 0
    registry_name := "polygon"

    func init(name):
        self.name = name

    func area():
        return 0

    # Polymorphisme : `self.area()` appelle la redéfinition de la classe réelle, pas celle de Polygon.
    func describe():
        return self.name + " (" + self.registry_name + ") : aire " + str(self.area())

class Rect extends Polygon:
    sides := 4
    registry_name := "rect"

    func init(name, w, h):
        super.init(name)        # constructeur de la classe de base
        self.w = w
        self.h = h

    func area():
        return self.w * self.h

class Square extends Rect:
    # Pas de `init` propre : celui de Rect est hérité, on adapte donc les paramètres via une fabrique.
    func describe():
        return "[carré] " + super.describe()     # super.describe() = Polygon.describe, qui rappelle Square.area

func make_square(side):
    return Square("sq", side, side)

shapes := [Polygon("vide"), Rect("r", 3, 4), make_square(5)]
for s in shapes:
    print(s.describe())

print("--- isinstance")
sq := make_square(2)
print(isinstance(sq, Square))      # true  : type exact
print(isinstance(sq, Polygon))     # true  : ancêtre
print(isinstance(sq, Shape))       # true  : interface implémentée par un ancêtre
print(isinstance(Rect("r", 1, 1), Square))  # false : pas de remontée inverse
print(isinstance(42, Polygon))     # false : pas une instance

# Fixture du test OOP : classes, héritage et interfaces EXPORTÉS vers un autre module.

interface Speaker:
    func speak()

class Animal implements Speaker:
    legs := 4
    func init(name):
        self.name = name
    func speak():
        return "..."
    func label():
        return self.name + ":" + self.speak()

# Classe sans constructeur propre : celui d'Animal doit s'appliquer (arité vérifiée côté importeur).
class Cat extends Animal:
    func speak():
        return "miaou"

func make_cat(name):
    return Cat(name)

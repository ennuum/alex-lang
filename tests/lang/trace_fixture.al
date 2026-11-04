# Fixture de test-trace : exception NON capturée traversant méthode, lambda et fonction.
# Sortie attendue sur stderr : voir la cible test-trace du Makefile.
class Calc:
    func div(a, b):
        f := (x) => a // x
        return f(b)

func run():
    c := Calc()
    return c.div(1, 0)

run()

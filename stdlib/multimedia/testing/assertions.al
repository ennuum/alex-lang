# ALEX STANDARD LIBRARY — multimedia.testing.assertions
#
# Vérifications pour les tests multimédias, au format des suites du dépôt (« <nom> : N OK, M échecs ») :
# conditions, égalité approchée, échantillons, octets, images, erreurs attendues.
#
#   use multimedia.testing.assertions as ta
#   t := ta.Checker("mon module")
#   t.check(x == 3, "valeur")
#   t.near(rms, 0.707, 0.01, "efficace")
#   t.samples_near(sortie, attendu, 0.001, "filtre")
#   t.raises("CorruptDataError", () => dec.decode(octets), "fichier tronqué")
#   r := t.attempt(() => charger(), "chargement")       # Result ; l'échec compte comme un échec du test
#   t.summary()                                          # imprime « mon module : N OK, M échecs »

from core use len, to_int
use multimedia.core.result as res

func max_byte_difference(a, b):
    if len(a) != len(b):
        return 256
    m := 0
    for k in 0..len(a):
        d := a[k] - b[k]
        if d < 0:
            d = -d
        if d > m:
            m = d
    return m

func max_sample_difference(a, b):
    if len(a) != len(b):
        return 1e9
    m := 0.0
    for k in 0..len(a):
        d := a[k] - b[k]
        if d < 0:
            d = -d
        if d > m:
            m = d
    return m

func near(a, b, eps):
    d := a - b
    if d < 0:
        d = -d
    return d <= eps

class Checker:
    func init(name):
        self.name = name
        self.ok = 0
        self.ko = 0
        self.failures = []

    func check(cond, label):
        if cond:
            self.ok += 1
        else:
            self.ko += 1
            self.failures = self.failures + [label]
            print("ÉCHEC " + label)
        return cond

    func near(a, b, eps, label):
        return self.check(near(a, b, eps), label + " (" + str(a) + " au lieu de " + str(b) + ")")

    func equal(a, b, label):
        return self.check(a == b, label + " (" + str(a) + " au lieu de " + str(b) + ")")

    func samples_near(a, b, eps, label):
        d := max_sample_difference(a, b)
        return self.check(d <= eps, label + " (écart " + str(d) + ")")

    func bytes_equal(a, b, label):
        return self.check(max_byte_difference(a, b) == 0, label)

    func images_equal(a, b, label, tolerance=0):
        same := a.width == b.width and a.height == b.height and a.mode == b.mode and max_byte_difference(a.pixels, b.pixels) <= tolerance
        return self.check(same, label)

    # fn() doit lever une erreur de type `kind`.
    func raises(kind, fn, label):
        got := null
        try:
            fn()
        catch e:
            got = e.type
        return self.check(got == kind, label + " (attendu " + kind + ", obtenu " + str(got) + ")")

    func attempt(fn, label):
        r := res.attempt(fn)
        if not r.ok:
            self.check(false, label + " : " + str(r.error_type) + " " + str(r.error_message))
        return r

    func summary():
        print(self.name + " : " + str(self.ok) + " OK, " + str(self.ko) + " échecs")
        return self.ko == 0

# ALEX STANDARD LIBRARY — functional.lambda
#
# Fabriques de petites fonctions (comme le module operator de Python). Les lambdas d'ALEX ne contiennent
# qu'une expression ; ces fabriques couvrent les cas courants sans en écrire.
#
#   use functional.lambda as L
#   print(functional.map([1, 2, 3], L.mul(10)))              # [10, 20, 30]
#   adultes := functional.filter(gens, L.key_ge("age", 18))   # dict["age"] >= 18
#   noms := functional.map(gens, L.key("nom"))
#   points := functional.map(objets, L.field("x"))            # champ d'instance
#   longs := functional.filter(mots, L.compose_pred(L.gt(3), L.length()))
#   print(L.both(L.gt(0), L.lt(10))(5))                       # true
#
# Arithmétique : add sub mul div mod pow neg  (add(3) -> x + 3 ; sub(3) -> x - 3)
# Comparaison  : eq ne lt le gt ge between is_in
# Logique      : not_ both either all_of any_of
# Accès        : key(k) key_or(k, d) index(i) field(nom) call_method(nom, *args) length()
# Valeurs      : is_null is_not_null is_type(t) truthy
#
# Erreurs : AttributeError (champ ou méthode absents), TypeError.

from core use len, type
use _native_reflect as _r

func add(n):
    return (x) => x + n

func sub(n):
    return (x) => x - n

func mul(n):
    return (x) => x * n

func div(n):
    return (x) => x / n

func floordiv(n):
    return (x) => x // n

func mod(n):
    return (x) => x % n

func pow(n):
    return (x) => x ** n

func neg():
    return (x) => -x

func eq(v):
    return (x) => x == v

func ne(v):
    return (x) => not (x == v)

func lt(v):
    return (x) => x < v

func le(v):
    return (x) => x <= v

func gt(v):
    return (x) => x > v

func ge(v):
    return (x) => x >= v

func between(lo, hi):
    return (x) => x >= lo and x <= hi

func is_in(values):
    return (x) => x in values

func not_(p):
    return (*args) => not p(*args)

func both(p, q):
    return (x) => p(x) and q(x)

func either(p, q):
    return (x) => p(x) or q(x)

func all_of(*preds):
    func g(x):
        for p in preds:
            if not p(x):
                return false
        return true
    return g

func any_of(*preds):
    func g(x):
        for p in preds:
            if p(x):
                return true
        return false
    return g

# p(f(x)) : prédicat appliqué à une projection.
func compose_pred(p, f):
    return (x) => p(f(x))

func key(k):
    return (d) => d[k]

func key_or(k, default=null):
    return (d) => d[k] if k in d else default

func key_eq(k, v):
    return (d) => d[k] == v

func key_ge(k, v):
    return (d) => d[k] >= v

func index(i):
    return (xs) => xs[i]

func first():
    return (xs) => xs[0]

func last():
    return (xs) => xs[len(xs) - 1]

func length():
    return (x) => len(x)

# Champ d'une instance, par son nom (réflexion).
func field(name):
    return (o) => _r.get_field(o, name)

func field_eq(name, v):
    return (o) => _r.get_field(o, name) == v

# Appelle la méthode name(*args) de l'objet reçu.
func call_method(name, *args):
    func g(o):
        m := _r.method(o, name)
        if type(m) == "null":
            raise("AttributeError", "'" + _r.display_name(_r.type_name(o)) + "' n'a pas de méthode '" + name + "'")
        return m(*args)
    return g

func is_null():
    return (x) => type(x) == "null"

func is_not_null():
    return (x) => type(x) != "null"

func is_type(t):
    return (x) => type(x) == t

func truthy():
    return (x) => true if x else false

func identity():
    return (x) => x

func constant(v):
    return (*args) => v

# (a, b) -> a + b, etc. : opérateurs binaires pour reduce.
func plus():
    return (a, b) => a + b

func times():
    return (a, b) => a * b

func minimum():
    return (a, b) => a if a <= b else b

func maximum():
    return (a, b) => a if a >= b else b

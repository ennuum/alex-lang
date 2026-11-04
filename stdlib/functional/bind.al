# ALEX STANDARD LIBRARY — functional.bind
#
# Liaison d'arguments, à la std::bind (C++) : on fixe certains arguments et on laisse des ESPACES RÉSERVÉS
# (_1, _2, ...) que rempliront les arguments de l'appel. Les arguments supplémentaires de l'appel sont
# ajoutés à la fin.
#
#   use functional.bind as b
#   diff := (a, b2) => a - b2
#   moins_dix := b.bind(diff, b._1, 10)        # x -> x - 10
#   dix_moins := b.bind(diff, 10, b._1)        # x -> 10 - x
#   inverse := b.bind(diff, b._2, b._1)        # (x, y) -> y - x
#   print(moins_dix(25), dix_moins(3), inverse(1, 5))   # 15 7 4
#   ajoute := b.bind_front(ajouter, panier)    # (article) -> ajouter(panier, article)
#   compter := b.bind_method(compteur, "add")  # méthode liée à un objet, par son nom
#
# Erreurs : BindError (espace réservé sans argument correspondant), TypeError, AttributeError.

from core use len, type
from collections use append
use _native_reflect as _r
use functional.functional_errors as _e

class Placeholder:
    func init(n):
        self.n = n

    func __str__():
        return "_" + str(self.n)

const _MAX := 9

_1 := Placeholder(1)
_2 := Placeholder(2)
_3 := Placeholder(3)
_4 := Placeholder(4)
_5 := Placeholder(5)
_6 := Placeholder(6)
_7 := Placeholder(7)
_8 := Placeholder(8)
_9 := Placeholder(9)

# Espace réservé numéro n (1..9).
func placeholder(n):
    if type(n) != "int" or n < 1 or n > _MAX:
        _e.invalid("bind.placeholder", "numéro 1.." + str(_MAX) + " attendu")
    return [_1, _2, _3, _4, _5, _6, _7, _8, _9][n - 1]

func is_placeholder(v):
    return isinstance(v, Placeholder)

class Bound:
    func init(f, bound):
        _e.need_fn("bind", f)
        self.fn = f
        self.bound = bound
        hi := 0
        for v in bound:
            if isinstance(v, Placeholder) and v.n > hi:
                hi = v.n
        self.required = hi

    func call(*args):
        if len(args) < self.required:
            raise(_e.BIND, "bind : " + str(self.required) + " argument(s) attendu(s) pour les espaces réservés, " + str(len(args)) + " reçu(s)")
        final := []
        used := 0
        for v in self.bound:
            if isinstance(v, Placeholder):
                append(final, args[v.n - 1])
                if v.n > used:
                    used = v.n
            else:
                append(final, v)
        i := used
        while i < len(args):
            append(final, args[i])
            i += 1
        return self.fn(*final)

    func __call__(*args):
        return self.call(*args)

    func __str__():
        parts := ""
        i := 0
        for v in self.bound:
            if i > 0:
                parts += ", "
            parts += str(v)
            i += 1
        return "<bind(" + parts + ")>"

func bind(f, *args):
    b := Bound(f, args)
    return (*call_args) => b.call(*call_args)

# Objet Bound (introspection : .fn, .bound, .required).
func bound(f, *args):
    return Bound(f, args)

func bind_front(f, *first):
    _e.need_fn("bind_front", f)
    return (*rest) => f(*first, *rest)

func bind_back(f, *last):
    _e.need_fn("bind_back", f)
    return (*rest) => f(*rest, *last)

# Méthode `name` de obj, liée (comme obj.name, mais le nom est une valeur).
func bind_method(obj, name, *first):
    m := _r.method(obj, name)
    if type(m) == "null":
        raise("AttributeError", "bind_method : '" + _r.display_name(_r.type_name(obj)) + "' n'a pas de méthode '" + name + "'")
    if len(first) == 0:
        return m
    return (*rest) => m(*first, *rest)

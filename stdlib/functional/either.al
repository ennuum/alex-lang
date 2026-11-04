# ALEX STANDARD LIBRARY — functional.either
#
# Either : une valeur de l'un de deux côtés — Left (par convention : l'échec, l'alternative) ou Right
# (le succès, « right » = correct). Les transformations ne s'appliquent qu'au côté Right, un Left traverse
# la chaîne intact : on enchaîne des étapes qui peuvent échouer sans exceptions.
# (future.result.Result est le pendant orienté erreurs typées ; Either est plus général : le Left porte
# n'importe quelle valeur.)
#
#   use functional.either as ei
#   func parse_age(s):
#       if not s.isdigit():
#           return ei.left("pas un nombre : " + s)
#       return ei.right(int(s))
#   r := parse_age("42").map((n) => n + 1).filter_or((n) => n < 150, "âge improbable")
#   print(r.fold((err) => "erreur " + err, (v) => "âge " + str(v)))     # âge 43
#   print(ei.try_call(diviser, 1, 0))          # Left({type: ZeroDivisionError, message: ...})
#   print(ei.sequence([ei.right(1), ei.right(2)]))   # Right([1, 2])
#
# Erreurs : EitherError (left() sur un Right, right() sur un Left), TypeError.

from core use type
from collections use append
use functional.functional_errors as _e

class Either:
    func init(is_right, value):
        self._right = is_right
        self._value = value

    func is_left():
        return not self._right

    func is_right():
        return self._right

    func left():
        if self._right:
            raise(_e.EITHER, "Either.left : valeur du côté Right")
        return self._value

    func right():
        if not self._right:
            raise(_e.EITHER, "Either.right : valeur du côté Left (" + str(self._value) + ")")
        return self._value

    func get_or_else(default):
        if self._right:
            return self._value
        return default

    func map(f):
        if self._right:
            return Either(true, f(self._value))
        return self

    func map_left(f):
        if self._right:
            return self
        return Either(false, f(self._value))

    func bimap(on_left, on_right):
        if self._right:
            return Either(true, on_right(self._value))
        return Either(false, on_left(self._value))

    # f doit rendre un Either.
    func flat_map(f):
        if not self._right:
            return self
        r := f(self._value)
        if not isinstance(r, Either):
            raise("TypeError", "Either.flat_map : la fonction doit rendre un Either")
        return r

    # Right gardé si pred(valeur), sinon Left(left_value).
    func filter_or(pred, left_value):
        if self._right and not pred(self._value):
            return Either(false, left_value)
        return self

    func fold(on_left, on_right):
        if self._right:
            return on_right(self._value)
        return on_left(self._value)

    func swap():
        return Either(not self._right, self._value)

    # Right : sa valeur ; Left : or_else(valeur gauche).
    func recover(f):
        if self._right:
            return self
        return Either(true, f(self._value))

    func if_right(f):
        if self._right:
            f(self._value)
        return self

    func if_left(f):
        if not self._right:
            f(self._value)
        return self

    func to_list():
        if self._right:
            return [self._value]
        return []

    func __eq__(other):
        if not isinstance(other, Either):
            return false
        return self._right == other._right and self._value == other._value

    func __str__():
        if self._right:
            return "Right(" + str(self._value) + ")"
        return "Left(" + str(self._value) + ")"

func left(value):
    return Either(false, value)

func right(value):
    return Either(true, value)

# Right(f(*args)), ou Left({"type", "message"}) si f lève une erreur.
func try_call(f, *args):
    _e.need_fn("either.try_call", f)
    try:
        return Either(true, f(*args))
    catch e:
        return Either(false, {"type": e.type, "message": e.message})

# Right(valeur) si cond, sinon Left(left_value).
func cond(condition, right_value, left_value):
    if condition:
        return Either(true, right_value)
    return Either(false, left_value)

# Liste d'Either -> Right(liste des valeurs) ou le premier Left.
func sequence(items):
    out := []
    for e in items:
        if e.is_left():
            return e
        append(out, e.right())
    return Either(true, out)

# [lefts, rights]
func partition(items):
    ls := []
    rs := []
    for e in items:
        if e.is_left():
            append(ls, e.left())
        else:
            append(rs, e.right())
    return [ls, rs]

func lefts(items):
    return partition(items)[0]

func rights(items):
    return partition(items)[1]

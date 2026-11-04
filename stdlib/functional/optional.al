# ALEX STANDARD LIBRARY — functional.optional
#
# Optional : une valeur PRÉSENTE ou ABSENTE, explicitement (au lieu d'un null qui circule sans le dire).
# Inspiré de java.util.Optional / std::optional ; chaînable sans tests de null à chaque étape.
#
#   use functional.optional as opt
#   o := opt.of_nullable(chercher(id))          # Optional vide si null
#   nom := o.map((u) => u["nom"]).filter((n) => n != "").or_else("anonyme")
#   o.if_present((u) => print(u))
#   v := opt.of(5).flat_map((x) => opt.of(x * 2)).get()   # 10
#   opt.empty().get()                           # EmptyOptionalError
#   print(opt.first_present([opt.empty(), opt.of(3)]))    # Optional(3)
#
# Une valeur présente peut elle-même valoir null avec of_value(null) (rare) ; of(null) l'interdit.
# Erreurs : EmptyOptionalError (get / or_raise sur vide), TypeError, ArgumentError (of(null)).

from core use type
from collections use append
use functional.functional_errors as _e

class Optional:
    func init(present=false, value=null):
        self._present = present
        self._value = value

    func is_present():
        return self._present

    func is_empty():
        return not self._present

    func get():
        if not self._present:
            raise(_e.EMPTY_OPTIONAL, "Optional.get : aucune valeur")
        return self._value

    func or_else(default):
        if self._present:
            return self._value
        return default

    func or_else_get(f):
        if self._present:
            return self._value
        return f()

    # Valeur, ou lève (error_type, message).
    func or_raise(error_type=_e.EMPTY_OPTIONAL, message="valeur absente"):
        if not self._present:
            raise(error_type, message)
        return self._value

    # Optional de f(valeur) ; un résultat null donne un Optional vide.
    func map(f):
        if not self._present:
            return self
        return of_nullable(f(self._value))

    # f doit rendre un Optional.
    func flat_map(f):
        if not self._present:
            return self
        r := f(self._value)
        if not isinstance(r, Optional):
            raise("TypeError", "Optional.flat_map : la fonction doit rendre un Optional")
        return r

    func filter(pred):
        if self._present and pred(self._value):
            return self
        return empty()

    # self s'il est présent, sinon l'Optional rendu par f().
    func or_optional(f):
        if self._present:
            return self
        return f()

    func if_present(f):
        if self._present:
            f(self._value)

    func if_present_or_else(f, otherwise):
        if self._present:
            f(self._value)
        else:
            otherwise()

    func contains(v):
        return self._present and self._value == v

    func to_list():
        if self._present:
            return [self._value]
        return []

    func __eq__(other):
        if not isinstance(other, Optional):
            return false
        if self._present != other._present:
            return false
        return not self._present or self._value == other._value

    func __str__():
        if self._present:
            return "Optional(" + str(self._value) + ")"
        return "Optional.empty"

_EMPTY := Optional(false, null)

func empty():
    return _EMPTY

# Valeur présente (null refusé).
func of(value):
    if type(value) == "null":
        raise("ArgumentError", "optional.of : valeur null (utiliser of_nullable)")
    return Optional(true, value)

func of_nullable(value):
    if type(value) == "null":
        return _EMPTY
    return Optional(true, value)

# Présent même si value est null.
func of_value(value):
    return Optional(true, value)

# Premier Optional présent de la liste (ou vide).
func first_present(options):
    for o in options:
        if o.is_present():
            return o
    return _EMPTY

# Valeurs des Optional présents.
func values(options):
    out := []
    for o in options:
        if o.is_present():
            append(out, o.get())
    return out

# f(x) en Optional : vide si f lève une erreur ou rend null.
func attempt(f, *args):
    try:
        return of_nullable(f(*args))
    catch e:
        return _EMPTY

# Clé d'un dict en Optional.
func get_key(d, key):
    if key in d:
        return Optional(true, d[key])
    return _EMPTY

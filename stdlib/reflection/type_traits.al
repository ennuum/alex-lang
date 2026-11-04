# ALEX STANDARD LIBRARY — reflection.type_traits
#
# Prédicats sur les valeurs et leurs types (dans l'esprit de <type_traits>) : ce qu'une valeur EST et ce
# qu'elle SAIT FAIRE (hachage, comparaison, itération, opérateurs).
#
#   use reflection.type_traits as tt
#   print(tt.is_integral(3), tt.is_floating(2.5), tt.is_numeric("3"))     # true true false
#   print(tt.is_hashable([1]), tt.is_hashable((1, 2)))                    # false true
#   print(tt.is_iterable("abc"), tt.has_len(ma_pile), tt.is_comparable(1, 2.0))
#   print(tt.supports(vec, "__add__"), tt.implements(liste, "Collection"))
#   print(tt.category(x))     # "number" "text" "sequence" "mapping" "callable" "object" "null" "bool"
#
# Erreurs : aucune (les prédicats ne lèvent pas).

from core use len, type, hash
use _native_reflect as _r
use reflection.type_info as _ti

func is_null(v):
    return type(v) == "null"

func is_bool(v):
    return type(v) == "bool"

func is_integral(v):
    t := type(v)
    return t == "int" or t == "byte"

func is_floating(v):
    return type(v) == "float"

func is_numeric(v):
    return is_integral(v) or is_floating(v)

func is_string(v):
    t := type(v)
    return t == "str" or t == "char"

func is_sequence(v):
    t := type(v)
    return t == "list" or t == "tuple" or t == "str"

func is_mapping(v):
    return type(v) == "dict"

func is_callable(v):
    if type(v) == "function":
        return true
    return _r.is_instance(v) and _r.method_arity(_r.type_name(v), "__call__") != null

func is_instance(v):
    return _r.is_instance(v)

func is_primitive(v):
    t := type(v)
    return t == "int" or t == "float" or t == "bool" or t == "str" or t == "char" or t == "byte" or t == "null"

func is_container(v):
    t := type(v)
    return t == "list" or t == "tuple" or t == "dict" or (_r.is_instance(v) and has_len(v))

func is_immutable(v):
    t := type(v)
    return is_primitive(v) or t == "tuple"

func is_hashable(v):
    try:
        hash(v)
        return true
    catch e:
        return false

# Les deux valeurs se comparent-elles avec < ?
func is_comparable(a, b):
    try:
        x := a < b
        return true
    catch e:
        return false

func has_method(v, name):
    return _r.is_instance(v) and _r.method_arity(_r.type_name(v), name) != null

func has_len(v):
    t := type(v)
    if t == "list" or t == "tuple" or t == "dict" or t == "str":
        return true
    return has_method(v, "__len__")

func is_iterable(v):
    t := type(v)
    if t == "list" or t == "tuple" or t == "dict" or t == "str":
        return true
    return has_method(v, "__getitem__") or has_method(v, "to_list")

# L'objet redéfinit-il l'égalité (__eq__) ?
func is_equatable(v):
    return not _r.is_instance(v) or has_method(v, "__eq__")

# Méthode spéciale d'opérateur présente (« __add__ », « __lt__ »...) ?
func supports(v, special):
    t := type(v)
    if not _r.is_instance(v):
        if special == "__add__":
            return t == "int" or t == "float" or t == "str" or t == "list" or t == "tuple"
        if special == "__lt__" or special == "__le__" or special == "__gt__" or special == "__ge__":
            return t == "int" or t == "float" or t == "str" or t == "char"
        if special == "__len__" or special == "__getitem__" or special == "__contains__":
            return t == "list" or t == "tuple" or t == "dict" or t == "str"
        return false
    return has_method(v, special)

# v est-il une instance du type (ou interface) nommé ?
func implements(v, type_name):
    if not _r.is_instance(v):
        return type(v) == type_name
    return _ti.type_of(v).is_subtype_of(type_name)

func same_type(a, b):
    if _r.is_instance(a) and _r.is_instance(b):
        return _r.type_name(a) == _r.type_name(b)
    return type(a) == type(b)

# Catégorie grossière d'une valeur.
func category(v):
    t := type(v)
    if t == "null":
        return "null"
    if t == "bool":
        return "bool"
    if is_numeric(v):
        return "number"
    if is_string(v):
        return "text"
    if t == "list" or t == "tuple":
        return "sequence"
    if t == "dict":
        return "mapping"
    if t == "function":
        return "callable"
    if t == "future" or t == "task":
        return "future"
    return "object"

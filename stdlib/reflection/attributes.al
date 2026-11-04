# ALEX STANDARD LIBRARY — reflection.attributes
#
# Métadonnées attachées aux types, à leurs champs et méthodes, et aux fonctions (équivalent des attributs
# C# / annotations Java, qu'ALEX n'a pas en syntaxe). On les déclare une fois, on les lit par réflexion.
#
#   use reflection.attributes as attr
#   attr.set_type("Utilisateur", "table", "users")
#   attr.set_field("Utilisateur", "email", "unique", true)
#   attr.set_method("Utilisateur", "sauver", "transactionnel", true)
#   print(attr.get_type(u, "table"))                   # objet OU nom de type accepté
#   print(attr.fields_with("Utilisateur", "unique"))   # ["email"]
#
#   @attr.tag("route", "/accueil")                     # décorateur sur une fonction
#   func accueil():
#       return "…"
#   print(attr.of_function(accueil)["route"])          # "/accueil"
#
# Les types sont identifiés par leur nom COURT (comme écrit dans le code).
# Erreurs : KeyError (attribut absent et pas de défaut), TypeError.

from core use len, type
from collections use append
use _native_reflect as _r

_types := {}       # type -> {clé: valeur}
_fields := {}      # type -> {champ -> {clé: valeur}}
_methods := {}     # type -> {méthode -> {clé: valeur}}
_funcs := {}       # nom qualifié de fonction -> {clé: valeur}

const _NONE := "\u0000<aucun>"

func _type_key(target):
    if type(target) == "str":
        return target
    if _r.is_instance(target):
        return _r.display_name(_r.type_name(target))
    raise("TypeError", "attributes : nom de type ou instance attendu (obtenu '" + type(target) + "')")

func _bucket(table, k):
    if not (k in table):
        table[k] = {}
    return table[k]

func _read(d, key, default, what):
    if key in d:
        return d[key]
    if type(default) == "str" and default == _NONE:
        raise("KeyError", "attributes : attribut '" + key + "' absent pour " + what)
    return default

func set_type(target, key, value=true):
    _bucket(_types, _type_key(target))[key] = value

func get_type(target, key, default=_NONE):
    k := _type_key(target)
    return _read(_bucket(_types, k), key, default, k)

func type_attributes(target):
    return _bucket(_types, _type_key(target))

func set_field(target, field, key, value=true):
    _bucket(_bucket(_fields, _type_key(target)), field)[key] = value

func get_field(target, field, key, default=_NONE):
    k := _type_key(target)
    return _read(_bucket(_bucket(_fields, k), field), key, default, k + "." + field)

func field_attributes(target, field):
    return _bucket(_bucket(_fields, _type_key(target)), field)

func set_method(target, method, key, value=true):
    _bucket(_bucket(_methods, _type_key(target)), method)[key] = value

func get_method(target, method, key, default=_NONE):
    k := _type_key(target)
    return _read(_bucket(_bucket(_methods, k), method), key, default, k + "." + method + "()")

func method_attributes(target, method):
    return _bucket(_bucket(_methods, _type_key(target)), method)

func has_type(target, key):
    return key in _bucket(_types, _type_key(target))

# Champs du type portant l'attribut key.
func fields_with(target, key):
    t := _bucket(_fields, _type_key(target))
    return [f for f in t if key in t[f]]

func methods_with(target, key):
    t := _bucket(_methods, _type_key(target))
    return [m for m in t if key in t[m]]

# Types portant l'attribut key.
func types_with(key):
    return [t for t in _types if key in _types[t]]

# ---------------------------------------------------------------- fonctions

func _fn_key(f):
    if type(f) != "function":
        raise("TypeError", "attributes : fonction attendue (obtenu '" + type(f) + "')")
    return _r.function_name(f)

func set_function(f, key, value=true):
    _bucket(_funcs, _fn_key(f))[key] = value
    return f

func of_function(f):
    return _bucket(_funcs, _fn_key(f))

func get_function(f, key, default=_NONE):
    return _read(_bucket(_funcs, _fn_key(f)), key, default, "la fonction " + _fn_key(f))

# Décorateur : @tag("clé", valeur) au-dessus d'une func.
func tag(key, value=true):
    return (f) => set_function(f, key, value)

# Fonctions décorées portant key (noms internes).
func functions_with(key):
    return [k for k in _funcs if key in _funcs[k]]

# Efface tout (tests).
func clear():
    for d in [_types, _fields, _methods, _funcs]:
        for k in [x for x in d]:
            del d[k]

# ALEX STANDARD LIBRARY — reflection
#
# Réflexion et métadonnées : examiner et manipuler les objets d'après les NOMS de leurs types, champs et
# méthodes, à l'exécution. S'appuie sur le module natif _native_reflect (registre des classes de la VM).
#
#   use reflection
#   print(reflection.class_name(compte))               # "Compte"
#   print(reflection.fields(compte))                   # ["solde", "titulaire"]
#   reflection.set(compte, "solde", 0)
#   print(reflection.call(compte, "deposer", 50))
#   print(reflection.is_instance_of(compte, "Serializable"))
#   print(reflection.describe(compte))                 # Compte { solde: 50, titulaire: "Ada" }
#   d := reflection.inspect(compte)                    # dict complet : type, base, interfaces, champs, méthodes
#
# Sous-modules : type_info (TypeInfo), field_info (FieldInfo, to_dict/from_dict), method_info (MethodInfo,
# call/bound), type_traits (prédicats), type_registry (fabriques par nom), attributes (métadonnées).
#
# Limites : une classe n'est pas une valeur (on la désigne par son nom) ; les paramètres des méthodes ne
# sont connus que par leur nombre (arité), pas leurs noms ; seuls les types du programme en cours sont vus.
# Erreurs : voir reflection.reflection_errors.

from core use len, type
from collections use append
use _native_reflect as _r
use reflection.type_info as _ti
use reflection.field_info as _fi
use reflection.method_info as _mi
use reflection.type_traits as _tt

func type_of(v):
    return _ti.type_of(v)

func type_named(name):
    return _ti.type_named(name)

# Nom court de la classe d'une instance (ou nom du type natif).
func class_name(v):
    if _r.is_instance(v):
        return _r.display_name(_r.type_name(v))
    return type(v)

func full_class_name(v):
    if _r.is_instance(v):
        return _r.type_name(v)
    return type(v)

func fields(obj, include_private=true):
    return _fi.names(obj, include_private)

func methods(target, include_private=true):
    return _mi.names(target, include_private)

func has_field(obj, name):
    return _r.is_instance(obj) and _r.has_field(obj, name)

func has_method(obj, name):
    return _tt.has_method(obj, name)

func get(obj, name, default="\u0000<aucun>"):
    return _fi.get(obj, name, default)

func set(obj, name, value):
    _fi.set(obj, name, value)

func call(obj, name, *args):
    return _mi.call(obj, name, *args)

func bound(obj, name):
    return _mi.bound(obj, name)

# Instance du type ou de l'interface nommé(e) (nom court ou complet).
func is_instance_of(v, type_name):
    return _tt.implements(v, type_name)

func to_dict(obj, include_private=false, deep=false):
    return _fi.to_dict(obj, include_private, deep)

func from_dict(obj, d, only_existing=false):
    return _fi.from_dict(obj, d, only_existing)

func _show(v):
    if type(v) == "str":
        return "\"" + v + "\""
    if _r.is_instance(v):
        return "<" + class_name(v) + ">"
    return str(v)

# Une ligne lisible : « Type { champ: valeur, ... } » (champs publics).
func describe(obj):
    if not _r.is_instance(obj):
        return type(obj) + " " + _show(obj)
    parts := ""
    first := true
    for n in _fi.names(obj, false):
        if not first:
            parts += ", "
        parts += n + ": " + _show(_r.get_field(obj, n))
        first = false
    return class_name(obj) + " { " + parts + " }"

# Description complète (dict) d'une valeur.
func inspect(v):
    t := _ti.type_of(v)
    d := t.to_dict()
    d["category"] = _tt.category(v)
    if _r.is_instance(v):
        d["fields"] = _fi.to_dict(v, true)
    return d

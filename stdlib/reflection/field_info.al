# ALEX STANDARD LIBRARY — reflection.field_info
#
# Champs d'une INSTANCE, par leur nom : lister, lire, écrire, copier, convertir en dict et inversement.
# (Les champs ALEX sont dynamiques : chaque instance porte les siens ; une même classe peut en avoir de
# différents selon les instances.)
#
#   use reflection.field_info as fi
#   for f in fi.fields(point):
#       print(f.name, f.type, f.value)            # x int 3 ...
#   fi.set(point, "x", 10)
#   print(fi.get(point, "x"), fi.has(point, "z"))  # 10 false
#   d := fi.to_dict(utilisateur)                   # champs publics (sans « _ ») ; deep=true : récursif
#   fi.from_dict(Utilisateur(""), {"nom": "Ada"})
#   print(fi.equals(a, b))                         # mêmes champs, mêmes valeurs
#
# Erreurs : ReflectionError (pas une instance), AttributeError (champ absent), TypeError.

from core use len, type
from collections use append
use string as _s
use _native_reflect as _r
use reflection.reflection_errors as _e

class FieldInfo:
    func init(owner_type, name, value):
        self.owner = _r.display_name(owner_type)
        self.name = name
        self.value = value
        self.type = type(value)
        if self.type == "instance":
            self.type = _r.display_name(_r.type_name(value))

    func is_private():
        return _s.starts_with(self.name, "_")

    func __str__():
        return self.owner + "." + self.name + ": " + self.type

func _need(fn, obj):
    if not _r.is_instance(obj):
        _e.not_instance(fn, obj)

func names(obj, include_private=true):
    _need("field_info.names", obj)
    out := []
    for n in _r.fields(obj):
        if include_private or not _s.starts_with(n, "_"):
            append(out, n)
    return out

func fields(obj, include_private=true):
    _need("field_info.fields", obj)
    tn := _r.type_name(obj)
    return [FieldInfo(tn, n, _r.get_field(obj, n)) for n in names(obj, include_private)]

func has(obj, name):
    _need("field_info.has", obj)
    return _r.has_field(obj, name)

func get(obj, name, default="\u0000<aucun>"):
    _need("field_info.get", obj)
    if not _r.has_field(obj, name):
        if type(default) == "str" and default == "\u0000<aucun>":
            _e.no_field("field_info.get", _r.display_name(_r.type_name(obj)), name)
        return default
    return _r.get_field(obj, name)

func set(obj, name, value):
    _need("field_info.set", obj)
    _r.set_field(obj, name, value)

func remove(obj, name):
    _need("field_info.remove", obj)
    return _r.remove_field(obj, name)

func _plain(v, deep, depth):
    if depth > 64:
        raise("ReflectionError", "field_info.to_dict : imbrication trop profonde (cycle ?)")
    t := type(v)
    if deep and t == "instance":
        return to_dict(v, false, true, depth + 1)
    if deep and t == "list":
        return [_plain(x, deep, depth + 1) for x in v]
    if deep and t == "dict":
        out := {}
        for k in v:
            out[k] = _plain(v[k], deep, depth + 1)
        return out
    return v

# Champs -> dict. include_private=false : sans les noms commençant par « _ ». deep : instances imbriquées
# converties aussi.
func to_dict(obj, include_private=false, deep=false, depth=0):
    _need("field_info.to_dict", obj)
    d := {}
    for n in names(obj, include_private):
        d[n] = _plain(_r.get_field(obj, n), deep, depth)
    return d

# Copie les clés de d dans les champs de obj ; only_existing=true : ignore les clés sans champ.
func from_dict(obj, d, only_existing=false):
    _need("field_info.from_dict", obj)
    for k in d:
        if only_existing and not _r.has_field(obj, k):
            continue
        _r.set_field(obj, k, d[k])
    return obj

# Copie les champs de src dans dst (superficielle) ; renvoie le nombre de champs copiés.
func copy_fields(src, dst, include_private=true):
    n := 0
    for name in names(src, include_private):
        _r.set_field(dst, name, _r.get_field(src, name))
        n += 1
    return n

# Mêmes noms de champs, valeurs égales (==) — indépendamment d'un éventuel __eq__ des objets.
func equals(a, b, include_private=true):
    if not _r.is_instance(a) or not _r.is_instance(b):
        return false
    if _r.type_name(a) != _r.type_name(b):
        return false
    na := names(a, include_private)
    nb := names(b, include_private)
    if na != nb:
        return false
    for n in na:
        if not (_r.get_field(a, n) == _r.get_field(b, n)):
            return false
    return true

# Champs différents entre a et b : [[nom, valeur_a, valeur_b], ...] (null pour un champ absent).
func diff(a, b):
    out := []
    seen := {}
    for n in names(a) + names(b):
        if n in seen:
            continue
        seen[n] = true
        va := null
        vb := null
        if _r.has_field(a, n):
            va = _r.get_field(a, n)
        if _r.has_field(b, n):
            vb = _r.get_field(b, n)
        if not (va == vb):
            append(out, [n, va, vb])
    return out

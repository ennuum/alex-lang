# ALEX STANDARD LIBRARY — reflection.method_info
#
# Méthodes d'un type ou d'un objet, par leur nom : lister (héritage compris), connaître l'arité, appeler,
# obtenir une méthode liée.
#
#   use reflection.method_info as mi
#   for m in mi.methods(compte):
#       print(m.name, m.arity_min, m.declared_in)
#   print(mi.call(compte, "deposer", 100))         # appel par nom
#   f := mi.bound(compte, "solde")                  # méthode liée (fonction)
#   print(f())
#   print(mi.has_method(compte, "retirer"), mi.special_methods(compte))   # true [__str__, ...]
#
# Erreurs : AttributeError (méthode absente), ReflectionError (pas une instance), ArgumentError (arité).

from core use len, type
from collections use append
use string as _s
use _native_reflect as _r
use reflection.reflection_errors as _e
use reflection.type_info as _ti

class MethodInfo:
    func init(type_full, name, declared_in):
        self.name = name
        self.owner = _r.display_name(type_full)
        self.declared_in = _r.display_name(declared_in)
        a := _r.method_arity(type_full, name)
        self.arity_min = a[0]
        self.arity_max = a[1]

    func is_special():
        return _s.starts_with(self.name, "__") and _s.ends_with(self.name, "__")

    func is_private():
        return _s.starts_with(self.name, "_") and not self.is_special()

    func is_constructor():
        return self.name == "init"

    func is_inherited():
        return self.owner != self.declared_in

    # Nombre d'arguments acceptable ?
    func accepts(n):
        return n >= self.arity_min and n <= self.arity_max

    func __str__():
        return self.owner + "." + self.name + "/" + str(self.arity_min)

func _full(target):
    if type(target) == "str":
        return _ti.resolve(target)
    if not _r.is_instance(target):
        _e.not_instance("method_info", target)
    return _r.type_name(target)

# MethodInfo de toutes les méthodes (héritées comprises) d'un objet ou d'un type (nom).
func methods(target, include_private=true):
    full := _full(target)
    t := _ti.TypeInfo(full, "instance")
    out := []
    seen := {}
    for owner in [t] + t.bases():
        for m in _r.methods(owner.full_name):
            if m in seen:
                continue
            seen[m] = true
            mi := MethodInfo(full, m, owner.full_name)
            if include_private or not mi.is_private():
                append(out, mi)
    return out

func names(target, include_private=true):
    return [m.name for m in methods(target, include_private)]

func has_method(target, name):
    return _r.method_arity(_full(target), name) != null

func get(target, name):
    full := _full(target)
    for m in methods(full):
        if m.name == name:
            return m
    _e.no_method("method_info.get", _r.display_name(full), name)

# Méthode liée à obj (fonction appelable) ; AttributeError si absente.
func bound(obj, name):
    if not _r.is_instance(obj):
        _e.not_instance("method_info.bound", obj)
    f := _r.method(obj, name)
    if type(f) == "null":
        _e.no_method("method_info.bound", _r.display_name(_r.type_name(obj)), name)
    return f

# obj.name(*args), avec contrôle d'arité au message clair.
func call(obj, name, *args):
    f := bound(obj, name)
    a := _r.method_arity(_r.type_name(obj), name)
    if len(args) < a[0] or len(args) > a[1]:
        raise("ArgumentError", "method_info.call : " + name + " attend " + str(a[0]) + ".." + str(a[1]) + " argument(s), " + str(len(args)) + " reçu(s)")
    return f(*args)

# Comme call, mais avec une liste d'arguments.
func apply(obj, name, args):
    return call(obj, name, *args)

func special_methods(target):
    return [m.name for m in methods(target) if m.is_special()]

func public_methods(target):
    return [m.name for m in methods(target, false) if not m.is_special() and m.name != "init"]

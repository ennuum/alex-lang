# ALEX STANDARD LIBRARY — reflection.type_info
#
# Description d'un TYPE à l'exécution : nom, genre, héritage, interfaces, méthodes. Les types utilisateur
# (struct, class) portent un nom COMPLET (qualifié par leur module, ex. « $mod…::ArrayList ») et un nom
# COURT (« ArrayList ») ; les types natifs (int, str, list...) n'ont que leur nom.
#
#   use reflection.type_info as ti
#   t := ti.type_of(ma_liste_chainee)
#   print(t.name, t.kind)                 # LinkedList instance
#   print(t.base_names())                 # chaîne d'héritage (noms courts), du parent à la racine
#   print(t.interface_names())            # interfaces, héritées comprises
#   print(t.has_method("add"), t.method_names()[:3])
#   print(ti.type_of(42).kind, ti.type_of([1]).is_builtin())   # int true
#   print(t.is_subtype_of("Collection"))  # par nom court ou complet
#
# Erreurs : UnknownTypeError, AmbiguousTypeError, TypeError.

from core use len, type
from collections use append
use _native_reflect as _r
use reflection.reflection_errors as _e

const BUILTINS := ["int", "float", "bool", "str", "char", "byte", "null", "list", "dict", "tuple", "function",
                   "future", "task", "exception"]

func short_name(full):
    return _r.display_name(full)

# Noms complets correspondant à un nom court ou complet.
func resolve_all(name):
    out := []
    for t in all_type_names():
        if t == name or short_name(t) == name:
            append(out, t)
    return out

# Nom complet d'un type d'après son nom court ; UnknownTypeError / AmbiguousTypeError.
func resolve(name):
    c := resolve_all(name)
    if len(c) == 0:
        _e.unknown("type_info.resolve", name)
    if len(c) > 1:
        _e.ambiguous("type_info.resolve", name, c)
    return c[0]

# Tous les types connus : classes, structs à méthodes, et interfaces déclarées par ces classes.
func all_type_names():
    seen := {}
    out := []
    for t in _r.types():
        if not (t in seen):
            seen[t] = true
            append(out, t)
        info := _r.class_info(t)
        if info != null:
            for i in info["interfaces"]:
                if not (i in seen):
                    seen[i] = true
                    append(out, i)
    return out

class TypeInfo:
    func init(full_name, kind):
        self.full_name = full_name
        self.name = short_name(full_name)
        self.kind = kind          # "instance" (struct/class/interface) ou le nom du type natif

    func is_builtin():
        return self.kind != "instance"

    func _info():
        if self.is_builtin():
            return null
        return _r.class_info(self.full_name)

    # Déclaré avec `class` (et non `struct`).
    func is_class():
        i := self._info()
        return i != null and i["is_class"]

    # Interface : connue seulement comme cible d'un `implements`.
    func is_interface():
        if self.is_builtin():
            return false
        return self._info() == null and len(_r.methods(self.full_name)) == 0

    func base():
        i := self._info()
        if i == null or i["base"] == null:
            return null
        return TypeInfo(i["base"], "instance")

    # Chaîne des parents (TypeInfo), du parent direct à la racine.
    func bases():
        out := []
        b := self.base()
        guard := 0
        while b != null and guard < 256:
            append(out, b)
            b = b.base()
            guard += 1
        return out

    func base_names():
        return [b.name for b in self.bases()]

    # Interfaces déclarées par ce type et ses parents (noms complets, sans doublon).
    func interfaces():
        out := []
        seen := {}
        chain := [self] + self.bases()
        for t in chain:
            i := t._info()
            if i != null:
                for x in i["interfaces"]:
                    if not (x in seen):
                        seen[x] = true
                        append(out, x)
        return out

    func interface_names():
        return [short_name(x) for x in self.interfaces()]

    # Méthodes déclarées par ce type seulement.
    func own_method_names():
        if self.is_builtin():
            return []
        return _r.methods(self.full_name)

    # Méthodes disponibles (héritées comprises), triées.
    func method_names():
        if self.is_builtin():
            return []
        seen := {}
        out := []
        for t in [self] + self.bases():
            for m in _r.methods(t.full_name):
                if not (m in seen):
                    seen[m] = true
                    append(out, m)
        return _sorted(out)

    func has_method(name):
        if self.is_builtin():
            return false
        return _r.method_arity(self.full_name, name) != null

    # [min, max] d'arguments de la méthode (sans self) ; null si absente.
    func method_arity(name):
        if self.is_builtin():
            return null
        return _r.method_arity(self.full_name, name)

    # Type parent, interface implémentée, ou lui-même — par nom court ou complet.
    func is_subtype_of(other):
        if self.is_builtin():
            return other == self.kind
        for cand in resolve_all(other):
            if _r.is_subtype(self.full_name, cand):
                return true
        return false

    # Sous-types connus (directs et indirects).
    func subtypes():
        out := []
        for t in _r.types():
            if t != self.full_name and _r.is_subtype(t, self.full_name):
                append(out, TypeInfo(t, "instance"))
        return out

    func to_dict():
        b := self.base()
        bn := null
        if b != null:
            bn = b.name
        return {"name": self.name, "full_name": self.full_name, "kind": self.kind, "base": bn,
                "interfaces": self.interface_names(), "methods": self.method_names()}

    func __eq__(other):
        return isinstance(other, TypeInfo) and other.full_name == self.full_name

    func __str__():
        return "<type " + self.name + ">"

func _sorted(xs):
    out := xs[:]
    i := 1
    while i < len(out):
        v := out[i]
        j := i - 1
        while j >= 0 and out[j] > v:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = v
        i += 1
    return out

# TypeInfo d'une valeur.
func type_of(value):
    t := type(value)
    if t == "instance":
        return TypeInfo(_r.type_name(value), "instance")
    return TypeInfo(t, t)

# TypeInfo d'un type d'après son nom (court ou complet ; nom de type natif accepté).
func type_named(name):
    for b in BUILTINS:
        if b == name:
            return TypeInfo(name, name)
    return TypeInfo(resolve(name), "instance")

func all_types():
    return [TypeInfo(t, "instance") for t in all_type_names()]

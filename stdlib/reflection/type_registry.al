# ALEX STANDARD LIBRARY — reflection.type_registry
#
# Registre de types : créer des objets à partir d'un NOM (désérialisation, greffons, configuration).
# En ALEX, une classe n'est pas une valeur : on enregistre une FABRIQUE (fonction qui construit l'objet)
# sous le nom du type, avec des métadonnées. Le registre interroge aussi les types connus de la VM.
#
#   use reflection.type_registry as treg
#   reg := treg.TypeRegistry()
#   reg.register("Point", (x, y) => Point(x, y), {"version": 2})
#   p := reg.create("Point", 1, 2)
#   print(reg.names(), reg.meta("Point")["version"])
#   reg.alias("Pt", "Point")
#   print(reg.type_name_of(p))                       # "Point"
#   print(treg.subtypes_of("Collection"))            # tous les types qui implémentent Collection
#   treg.default().register("Cercle", (r) => Cercle(r))     # registre global du programme
#
# Erreurs : UnknownTypeError (nom non enregistré), ReflectionError (doublon sans replace), TypeError.

from core use len, type
from collections use append
use _native_reflect as _r
use reflection.reflection_errors as _e
use reflection.type_info as _ti

class TypeRegistry:
    func init():
        self._factories = {}
        self._meta = {}
        self._aliases = {}

    func _canon(name):
        if name in self._aliases:
            return self._aliases[name]
        return name

    # Enregistre factory(*args) -> objet sous name. replace=false : doublon refusé.
    func register(name, factory, meta=null, replace=false):
        if type(name) != "str" or name == "":
            raise("TypeError", "TypeRegistry.register : nom (str non vide) attendu")
        if type(factory) != "function":
            raise("TypeError", "TypeRegistry.register : la fabrique doit être une fonction")
        if name in self._factories and not replace:
            raise(_e.REFLECTION, "TypeRegistry.register : '" + name + "' déjà enregistré")
        self._factories[name] = factory
        m := meta
        if m == null:
            m = {}
        self._meta[name] = m
        return name

    func unregister(name):
        n := self._canon(name)
        if not (n in self._factories):
            return false
        del self._factories[n]
        del self._meta[n]
        for a in [k for k in self._aliases]:
            if self._aliases[a] == n:
                del self._aliases[a]
        return true

    func alias(alias_name, name):
        if not (name in self._factories):
            _e.unknown("TypeRegistry.alias", name)
        self._aliases[alias_name] = name

    func contains(name):
        return self._canon(name) in self._factories

    func create(name, *args):
        n := self._canon(name)
        if not (n in self._factories):
            _e.unknown("TypeRegistry.create", name)
        return self._factories[n](*args)

    # Construit à partir d'un dict {"type": nom, "args": [...]} (ou "kwargs" ignoré).
    func create_from(spec):
        args := []
        if "args" in spec:
            args = spec["args"]
        return self.create(spec["type"], *args)

    func factory(name):
        n := self._canon(name)
        if not (n in self._factories):
            _e.unknown("TypeRegistry.factory", name)
        return self._factories[n]

    func meta(name):
        n := self._canon(name)
        if not (n in self._meta):
            _e.unknown("TypeRegistry.meta", name)
        return self._meta[n]

    func names():
        return [k for k in self._factories]

    func size():
        return len(self._factories)

    # Nom enregistré correspondant au type d'un objet (nom court de sa classe), ou null.
    func type_name_of(obj):
        if not _r.is_instance(obj):
            return null
        short := _r.display_name(_r.type_name(obj))
        if short in self._factories:
            return short
        if short in self._aliases:
            return self._aliases[short]
        return null

    # Noms enregistrés dont les métadonnées vérifient pred(meta).
    func find(pred):
        return [k for k in self._factories if pred(self._meta[k])]

_global := [null]

func default():
    if _global[0] == null:
        _global[0] = TypeRegistry()
    return _global[0]

func register(name, factory, meta=null):
    return default().register(name, factory, meta)

func create(name, *args):
    return default().create(name, *args)

# Types de la VM (noms courts), triés.
func known_types():
    out := [_r.display_name(t) for t in _ti.all_type_names()]
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

# Types de la VM qui étendent ou implémentent name (noms courts).
func subtypes_of(name):
    return [s.name for s in _ti.type_named(name).subtypes()]

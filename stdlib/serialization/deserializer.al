# ALEX STANDARD LIBRARY — serialization.deserializer
#
# Deserializer : reconstruit des valeurs ALEX à partir de données simples produites par serializer (dicts
# marqués "__type__"). En ALEX une classe n'est pas une valeur : on enregistre, pour chaque type, une
# FABRIQUE sans argument (l'objet est créé puis ses champs sont remplis) ou un DÉCODEUR (données -> objet).
#
#   use serialization.deserializer as des
#   d := des.Deserializer()
#   d.register("Point", () => Point(0, 0))                     # champs x, y remplis ensuite
#   d.register_decoder("Date", (data) => date.parse(data["iso"]))
#   p := d.from_data({"__type__": "Point", "x": 1, "y": 2})
#   print(p.x, p.y)
#   d2 := des.Deserializer(reg)                                # ou un reflection.type_registry.TypeRegistry
#
# Une classe peut définir from_data(données) (méthode d'instance) : appelée sur l'objet neuf, elle remplace
# le remplissage automatique des champs.
# strict=true : un type inconnu lève DeserializationError ; sinon le dict est laissé tel quel.
# Erreurs : DeserializationError.

from core use len, type
from collections use append
from builtins use tuple
use _native_reflect as _r
use serialization.serialization_errors as _e

class Deserializer:
    func init(registry=null, type_field="__type__", strict=true, max_depth=128):
        self.registry = registry
        self.type_field = type_field
        self.strict = strict
        self.max_depth = max_depth
        self._factories = {}
        self._decoders = {}

    func register(type_name, factory):
        if type(factory) != "function":
            raise("TypeError", "Deserializer.register : fabrique (fonction sans argument) attendue")
        self._factories[type_name] = factory
        return self

    func register_decoder(type_name, decoder):
        if type(decoder) != "function":
            raise("TypeError", "Deserializer.register_decoder : fonction attendue")
        self._decoders[type_name] = decoder
        return self

    func knows(type_name):
        if type_name in self._factories or type_name in self._decoders:
            return true
        return self.registry != null and self.registry.contains(type_name)

    func from_data(data):
        return self._conv(data, "", 0)

    func _conv(v, path, depth):
        if depth > self.max_depth:
            _e.cannot_deserialize(path, "profondeur maximale dépassée")
        t := type(v)
        if t == "list":
            return [self._conv(v[i], path + "[" + str(i) + "]", depth + 1) for i in 0..len(v)]
        if t != "dict":
            return v
        if "__tuple__" in v and len(v) == 1:
            items := [self._conv(x, path, depth + 1) for x in v["__tuple__"]]
            return tuple(items)
        if self.type_field != null and self.type_field != "" and self.type_field in v:
            return self._object(v, path, depth)
        out := {}
        for k in v:
            out[k] = self._conv(v[k], path + "." + str(k), depth + 1)
        return out

    func _object(v, path, depth):
        name := v[self.type_field]
        fields := {}
        for k in v:
            if k != self.type_field:
                fields[k] = self._conv(v[k], path + "." + str(k), depth + 1)
        if name in self._decoders:
            if len(fields) == 1 and "value" in fields:
                return self._decoders[name](fields["value"])
            return self._decoders[name](fields)
        obj := null
        if name in self._factories:
            obj = self._factories[name]()
        elif self.registry != null and self.registry.contains(name):
            obj = self.registry.create(name)
        else:
            if self.strict:
                _e.cannot_deserialize(path, "type inconnu '" + str(name) + "' (register / register_decoder)")
            return fields
        if not _r.is_instance(obj):
            _e.cannot_deserialize(path, "la fabrique de '" + str(name) + "' n'a pas rendu d'instance")
        hook := _r.method(obj, "from_data")
        if hook != null:
            r := hook(fields)
            if r != null:
                return r
            return obj
        for k in fields:
            _r.set_field(obj, k, fields[k])
        return obj

func deserializer(registry=null, strict=true):
    return Deserializer(registry, "__type__", strict)

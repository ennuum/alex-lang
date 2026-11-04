# ALEX STANDARD LIBRARY — serialization.serializer
#
# Serializer : convertit n'importe quelle valeur ALEX en DONNÉES SIMPLES (null, bool, int, float, str, listes,
# dicts à clés texte) — la forme commune que les formats (JSON, XML, CSV, binaire, MessagePack) savent
# écrire. Les instances deviennent des dicts de leurs champs publics, marqués de leur type (champ "__type__")
# pour pouvoir être reconstruites par serialization.deserializer.
#
#   use serialization.serializer as ser
#   s := ser.Serializer()
#   d := s.to_data(Point(1, 2))                    # {"__type__": "Point", "x": 1, "y": 2}
#   s.register("Date", (dt) => {"iso": dt.iso()})  # représentation sur mesure d'un type
#   print(s.to_data([Point(0, 0), (1, 2)]))        # listes, tuples (en listes), dicts, imbrication
#
# Une classe peut aussi définir to_data() (rend des données simples) : elle est alors utilisée.
# Options : type_field ("" : pas de marquage), include_private (champs « _x »), passthrough (noms de types
# laissés tels quels, ex. Binary pour les formats binaires), keep_tuples (tuples marqués
# {"__tuple__": [...]}), string_keys (clés non texte converties par str ; sinon SerializationError).
# Erreurs : SerializationError (fonction, futur, cycle, profondeur > max_depth, clé non texte).

from core use len, type
from collections use append
use _native_reflect as _r
use collections._util as _u
use serialization.serialization_errors as _e

class Serializer:
    func init(type_field="__type__", include_private=false, keep_tuples=false, string_keys=false, max_depth=128, passthrough=null):
        self.passthrough = passthrough
        if self.passthrough == null:
            self.passthrough = []
        self.type_field = type_field
        self.include_private = include_private
        self.keep_tuples = keep_tuples
        self.string_keys = string_keys
        self.max_depth = max_depth
        self._encoders = {}

    # encoder(objet) -> données simples, pour les instances de type_name (nom court de la classe).
    func register(type_name, encoder):
        if type(encoder) != "function":
            raise("TypeError", "Serializer.register : fonction attendue")
        self._encoders[type_name] = encoder
        return self

    func to_data(value):
        return self._conv(value, "", 0, {})

    func _conv(v, path, depth, active):
        if depth > self.max_depth:
            _e.cannot_serialize(path, "profondeur maximale " + str(self.max_depth) + " dépassée")
        t := type(v)
        if t == "null" or t == "bool" or t == "int" or t == "float" or t == "str":
            return v
        if t == "char" or t == "byte":
            return str(v)
        if t == "list":
            return [self._conv(v[i], path + "[" + str(i) + "]", depth + 1, active) for i in 0..len(v)]
        if t == "tuple":
            items := []
            i := 0
            for x in v:
                append(items, self._conv(x, path + "[" + str(i) + "]", depth + 1, active))
                i += 1
            if self.keep_tuples:
                return {"__tuple__": items}
            return items
        if t == "dict":
            out := {}
            for k in v:
                key := k
                if type(k) != "str":
                    if not self.string_keys:
                        _e.cannot_serialize(path, "clé non texte " + str(k) + " (option string_keys)")
                    key = str(k)
                out[key] = self._conv(v[k], path + "." + key, depth + 1, active)
            return out
        if t == "instance":
            ident := _u.identity(v)
            if ident in active:
                _e.cannot_serialize(path, "référence circulaire")
            active[ident] = true
            try:
                return self._instance(v, path, depth, active)
            finally:
                del active[ident]
        _e.cannot_serialize(path, "type '" + t + "' non sérialisable")

    func _instance(v, path, depth, active):
        name := _r.display_name(_r.type_name(v))
        for p in self.passthrough:
            if p == name:
                return v
        data := null
        if name in self._encoders:
            data = self._encoders[name](v)
        elif _r.method(v, "to_data") != null:
            data = v.to_data()
        else:
            data = {}
            for f in _r.fields(v):
                if not self.include_private and (len(f) > 0 and f[0] == '_'):
                    continue
                data[f] = _r.get_field(v, f)
        conv := self._conv(data, path, depth + 1, active)
        if self.type_field == null or self.type_field == "":
            return conv
        if type(conv) == "dict":
            out := {self.type_field: name}
            for k in conv:
                out[k] = conv[k]
            return out
        return {self.type_field: name, "value": conv}

_default := [null]

func default():
    if _default[0] == null:
        _default[0] = Serializer()
    return _default[0]

func to_data(value):
    return default().to_data(value)

# Données simples sans marquage de type (pour un format destiné à d'autres programmes).
func plain(value):
    return Serializer("").to_data(value)

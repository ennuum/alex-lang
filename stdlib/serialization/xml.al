# ALEX STANDARD LIBRARY — serialization.xml
#
# Objets ALEX <-> XML. Une valeur devient un élément :
#   null -> <nom type="null"/>      bool/int/float -> <nom type="int">42</nom>      str -> <nom>texte</nom>
#   liste -> <nom type="list"><item>…</item>…</nom>   dict -> <nom type="dict"><clé>…</clé>…</nom>
#   instance -> <nom type="Classe"><champ>…</champ>…</nom>
# Les noms de clés qui ne sont pas des noms XML valides passent par <entry key="…">.
#
#   use serialization.xml as sx
#   t := sx.dumps(Point(1, 2), "point")
#   # <point type="Point"><x type="int">1</x><y type="int">2</y></point>
#   c := sx.Codec()
#   c.register("Point", () => Point(0, 0))
#   p := c.loads(t)
#   print(sx.dumps({"a": [1, 2]}, "racine", true))     # indenté
#
# Erreurs : XMLError (texte invalide), DeserializationError (type inconnu, valeur illisible).

from core use len, type, to_int, to_float
from collections use append
use xml as _x
use serialization.serializer as _ser
use serialization.deserializer as _des
use serialization.serialization_errors as _e

func _valid_name(k):
    if type(k) != "str" or k == "":
        return false
    c := k[0]
    if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'):
        return false
    for ch in k:
        if not ((ch >= 'a' and ch <= 'z') or (ch >= 'A' and ch <= 'Z') or (ch >= '0' and ch <= '9') or ch == '_' or ch == '-' or ch == '.'):
            return false
    return true

# Données simples (sortie de serializer) -> élément XML.
func to_element(data, name="value", type_field="__type__"):
    t := type(data)
    if t == "null":
        return _x.element(name, {"type": "null"})
    if t == "bool":
        v := "false"
        if data:
            v = "true"
        return _x.element(name, {"type": "bool"}, [v])
    if t == "int" or t == "float":
        return _x.element(name, {"type": t}, [str(data)])
    if t == "str":
        return _x.element(name, {}, [data])
    if t == "list":
        return _x.element(name, {"type": "list"}, [to_element(x, "item", type_field) for x in data])
    if t == "dict":
        kind := "dict"
        children := []
        for k in data:
            if type_field != null and k == type_field:
                kind = data[k]
                continue
            if _valid_name(k):
                append(children, to_element(data[k], k, type_field))
            else:
                e := to_element(data[k], "entry", type_field)
                e["attrs"]["key"] = str(k)
                append(children, e)
        return _x.element(name, {"type": kind}, children)
    _e.cannot_serialize(name, "type '" + t + "' non représentable en XML")

# Élément XML -> données simples (instances sous forme de dicts marqués).
func from_element(node, type_field="__type__"):
    kind := _x.attr(node, "type", "str")
    if kind == "null":
        return null
    if kind == "str":
        return _x.text(node)
    if kind == "bool":
        return _x.text(node) == "true"
    if kind == "int":
        return to_int(_x.text(node))
    if kind == "float":
        return to_float(_x.text(node))
    if kind == "list":
        return [from_element(c, type_field) for c in _x.children(node)]
    out := {}
    if kind != "dict" and type_field != null:
        out[type_field] = kind
    for c in _x.children(node):
        key := c["tag"]
        if key == "entry" and "key" in c["attrs"]:
            key = c["attrs"]["key"]
        out[key] = from_element(c, type_field)
    return out

func dumps(value, root="value", pretty=false, typed=true):
    data := null
    if typed:
        data = _ser.to_data(value)
    else:
        data = _ser.plain(value)
    el := to_element(data, root)
    if pretty:
        return _x.pretty(el)
    return _x.stringify(el)

func loads(text):
    return from_element(_x.parse(text))

class Codec:
    func init(strict=true, registry=null):
        self.serializer = _ser.Serializer()
        self.deserializer = _des.Deserializer(registry, "__type__", strict)

    func register(type_name, factory):
        self.deserializer.register(type_name, factory)
        return self

    func dumps(value, root="value", pretty=false):
        el := to_element(self.serializer.to_data(value), root)
        if pretty:
            return _x.pretty(el)
        return _x.stringify(el)

    func loads(text):
        return self.deserializer.from_data(from_element(_x.parse(text)))

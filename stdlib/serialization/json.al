# ALEX STANDARD LIBRARY — serialization.json
#
# Objets ALEX <-> JSON : le module json traite les données simples ; celui-ci y ajoute les instances (via
# serializer / deserializer), les fichiers, les lignes JSON (JSON Lines) et la validation par schéma.
#
#   use serialization.json as sj
#   texte := sj.dumps(Commande(42, [Ligne("stylo", 2)]))       # instances comprises (« __type__ »)
#   d := sj.Codec()
#   d.register("Commande", () => Commande(0, []))
#   d.register("Ligne", () => Ligne("", 0))
#   c := d.loads(texte)                                          # Commande reconstruite
#   d.dump_file("commande.json", c)
#   print(sj.dumps({"a": 1}, false, 2))                          # sans marquage de type, indenté
#   lignes := sj.dumps_lines([{"n": 1}, {"n": 2}])               # « {"n":1}\n{"n":2}\n »
#   print(sj.loads_lines(lignes))
#
# Erreurs : SerializationError, DeserializationError, JSONError (texte invalide), ValidationError (schéma).

from core use len, type
from collections use append
use string as _s
use json as _json
use io as _io
use serialization.serializer as _ser
use serialization.deserializer as _des

class Codec:
    func init(type_field="__type__", strict=true, indent=null, registry=null):
        self.serializer = _ser.Serializer(type_field)
        self.deserializer = _des.Deserializer(registry, type_field, strict)
        self.indent = indent
        self.schema = null

    func register(type_name, factory, encoder=null):
        self.deserializer.register(type_name, factory)
        if encoder != null:
            self.serializer.register(type_name, encoder)
        return self

    func register_decoder(type_name, decoder, encoder=null):
        self.deserializer.register_decoder(type_name, decoder)
        if encoder != null:
            self.serializer.register(type_name, encoder)
        return self

    # Schéma (serialization.schema) vérifié à la lecture.
    func with_schema(schema):
        self.schema = schema
        return self

    func dumps(value):
        return _json.stringify(self.serializer.to_data(value), self.indent)

    func loads(text):
        data := _json.parse(text)
        if self.schema != null:
            self.schema.check(data)
        return self.deserializer.from_data(data)

    func dump_file(path, value):
        _io.write_file(path, self.dumps(value) + "\n")

    func load_file(path):
        return self.loads(_io.read_file(path))

func dumps(value, typed=true, indent=null):
    if typed:
        return _json.stringify(_ser.to_data(value), indent)
    return _json.stringify(_ser.plain(value), indent)

# Données simples (types non reconstruits : dicts marqués « __type__ » laissés tels quels).
func loads(text):
    return _json.parse(text)

func pretty(value, typed=true):
    return dumps(value, typed, 2)

# JSON Lines : une valeur par ligne.
func dumps_lines(values, typed=false):
    out := []
    for v in values:
        append(out, dumps(v, typed))
    if len(out) == 0:
        return ""
    return _s.join("\n", out) + "\n"

func loads_lines(text):
    out := []
    for line in _s.split(text, "\n"):
        if _s.trim(line) != "":
            append(out, _json.parse(line))
    return out

func append_line(path, value, typed=false):
    _io.append_file(path, dumps(value, typed) + "\n")

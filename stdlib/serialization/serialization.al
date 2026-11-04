# ALEX STANDARD LIBRARY — serialization
#
# Sérialisation : transformer des valeurs ALEX (instances comprises) en texte ou en octets, et inversement,
# dans plusieurs formats, avec reconstruction des objets et validation par schéma.
#
#   use serialization
#   serialization.register("Point", () => Point(0, 0))      # pour reconstruire les Point
#   t := serialization.dumps(Point(1, 2))                    # JSON par défaut
#   p := serialization.loads(t)                              # Point(1, 2)
#   b := serialization.dumps([p], "msgpack")                 # json | xml | binary | msgpack
#   print(serialization.loads(b, "msgpack")[0].x)
#   print(serialization.formats())
#
# Sous-modules : serializer (valeurs -> données simples), deserializer (données -> valeurs), json, xml, csv,
# binary (format ALXB), message_pack (MessagePack standard), schema (validation), serialization_errors.
# Erreurs : SerializationError, DeserializationError, FormatError, ValidationError.

use serialization.serializer as _ser
use serialization.deserializer as _des
use serialization.json as _json
use serialization.xml as _xml
use serialization.binary as _bin
use serialization.message_pack as _mp

const FORMATS := ["json", "xml", "binary", "msgpack"]

_des_default := [null]

func deserializer():
    if _des_default[0] == null:
        _des_default[0] = _des.Deserializer(null, "__type__", false)
    return _des_default[0]

# Fabrique sans argument pour reconstruire type_name ; encoder facultatif (objet -> données simples).
func register(type_name, factory, encoder=null):
    deserializer().register(type_name, factory)
    if encoder != null:
        _ser.default().register(type_name, encoder)

func register_decoder(type_name, decoder):
    deserializer().register_decoder(type_name, decoder)

func formats():
    return FORMATS[:]

func _need(fmt):
    for f in FORMATS:
        if f == fmt:
            return
    raise("ArgumentError", "serialization : format inconnu '" + str(fmt) + "' (json, xml, binary, msgpack)")

func to_data(value):
    return _ser.to_data(value)

func from_data(data):
    return deserializer().from_data(data)

func dumps(value, format="json"):
    _need(format)
    if format == "json":
        return _json.dumps(value)
    if format == "xml":
        return _xml.dumps(value)
    if format == "binary":
        return _bin.dumps(value)
    return _mp.dumps(value)

func loads(data, format="json"):
    _need(format)
    raw := null
    if format == "json":
        raw = _json.loads(data)
    elif format == "xml":
        raw = _xml.loads(data)
    elif format == "binary":
        raw = _bin.loads(data)
    else:
        raw = _mp.loads(data)
    return deserializer().from_data(raw)

# Copie profonde par aller-retour en données simples (instances recréées par leurs fabriques).
func deep_copy(value):
    return from_data(to_data(value))

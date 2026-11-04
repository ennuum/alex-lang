# ALEX STANDARD LIBRARY — serialization.serialization_errors
#
# Erreurs de la sérialisation :
#   SerializationError    valeur impossible à convertir (fonction, futur, cycle, clé non texte en JSON...)
#   DeserializationError  données incohérentes avec le format ou le type annoncé, type inconnu (mode strict)
#   ValidationError       données qui ne respectent pas un schéma (serialization.schema)
#   FormatError           octets / texte mal formés (binaire, MessagePack, en-tête invalide)
#
#   use serialization.serialization_errors as se

const SERIALIZATION := "SerializationError"
const DESERIALIZATION := "DeserializationError"
const VALIDATION := "ValidationError"
const FORMAT := "FormatError"

func kinds():
    return [SERIALIZATION, DESERIALIZATION, VALIDATION, FORMAT]

func is_serialization_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func cannot_serialize(path, what):
    raise(SERIALIZATION, "sérialisation" + _at(path) + " : " + what)

func cannot_deserialize(path, what):
    raise(DESERIALIZATION, "désérialisation" + _at(path) + " : " + what)

func bad_format(fmt, what):
    raise(FORMAT, fmt + " : " + what)

func _at(path):
    if path == "" or path == null:
        return ""
    return " (" + path + ")"

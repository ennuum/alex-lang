# ALEX STANDARD LIBRARY — reflection.reflection_errors
#
# Erreurs de la réflexion :
#   UnknownTypeError    aucun type de ce nom dans le programme
#   AmbiguousTypeError  nom court partagé par plusieurs modules (préciser le nom complet)
#   AttributeError      champ ou méthode absent
#   ReflectionError     opération impossible (pas une instance, fabrique absente...)
#
#   use reflection.reflection_errors as re

const UNKNOWN_TYPE := "UnknownTypeError"
const AMBIGUOUS := "AmbiguousTypeError"
const REFLECTION := "ReflectionError"

func unknown(fn, name):
    raise(UNKNOWN_TYPE, fn + " : type inconnu '" + name + "'")

func ambiguous(fn, name, candidates):
    raise(AMBIGUOUS, fn + " : nom '" + name + "' ambigu (" + str(len_of(candidates)) + " types : préciser le nom complet)")

func len_of(xs):
    n := 0
    for x in xs:
        n += 1
    return n

func not_instance(fn, v):
    raise(REFLECTION, fn + " : instance attendue")

func no_method(fn, type_name, name):
    raise("AttributeError", fn + " : '" + type_name + "' n'a pas de méthode '" + name + "'")

func no_field(fn, type_name, name):
    raise("AttributeError", fn + " : '" + type_name + "' n'a pas de champ '" + name + "'")

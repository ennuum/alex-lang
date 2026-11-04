# ALEX STANDARD LIBRARY — functional.functional_errors
#
# Erreurs de la programmation fonctionnelle :
#   EmptyOptionalError   get() sur un Optional vide
#   EitherError          lecture du mauvais côté d'un Either (left() sur un Right, right() sur un Left)
#   BindError            appel d'une fonction liée sans assez d'arguments pour ses espaces réservés
#   FunctionalError      autre usage invalide (composition vide, arité impossible...)
#   TypeError            fonction attendue
#
#   use functional.functional_errors as fe
#   fe.need_fn("compose", f)

from core use type

const EMPTY_OPTIONAL := "EmptyOptionalError"
const EITHER := "EitherError"
const BIND := "BindError"
const INVALID := "FunctionalError"

func need_fn(fn, f, label="la fonction"):
    if type(f) != "function":
        raise("TypeError", fn + " : " + label + " doit être une fonction (obtenu '" + type(f) + "')")

func need_fns(fn, fns):
    i := 0
    for f in fns:
        if type(f) != "function":
            raise("TypeError", fn + " : l'élément " + str(i) + " n'est pas une fonction (obtenu '" + type(f) + "')")
        i += 1

func invalid(fn, message):
    raise(INVALID, fn + " : " + message)

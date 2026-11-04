# ALEX STANDARD LIBRARY — algorithm.algorithm_errors
#
# Erreurs des algorithmes :
#   EmptySequenceError   opération sans résultat sur une séquence vide (min, max, mean...)
#   UnsortedError        entrée qui devait être triée et ne l'est pas (vérification demandée par check=true)
#   AlgorithmError       paramètre invalide (k hors limites, taille nulle...)
#   TypeError            séquence ou fonction attendue
#
#   use algorithm.algorithm_errors as ae
#   ae.need_list("sort", xs)

from core use type

const EMPTY := "EmptySequenceError"
const UNSORTED := "UnsortedError"
const INVALID := "AlgorithmError"

func empty(fn):
    raise(EMPTY, fn + " : séquence vide")

func unsorted(fn, i):
    raise(UNSORTED, fn + " : séquence non triée (position " + str(i) + ")")

func invalid(fn, message):
    raise(INVALID, fn + " : " + message)

func need_list(fn, xs):
    if type(xs) != "list":
        raise("TypeError", fn + " : liste attendue (obtenu '" + type(xs) + "')")

func need_fn(fn, f, label="la fonction"):
    if f != null and type(f) != "function":
        raise("TypeError", fn + " : " + label + " doit être une fonction (obtenu '" + type(f) + "')")

func need_int(fn, v, label):
    if type(v) != "int":
        raise("TypeError", fn + " : " + label + " doit être un int (obtenu '" + type(v) + "')")

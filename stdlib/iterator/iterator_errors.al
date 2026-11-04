# ALEX STANDARD LIBRARY — iterator.iterator_errors
#
# Erreurs des itérateurs :
#   StopIteration   next() sur un itérateur épuisé (has_next() aurait rendu false)
#   IteratorError   usage invalide : itérable non reconnu, pas négatif, taille de fenêtre nulle...
#   IndexError      levée par __getitem__ en fin de parcours : c'est le signal d'arrêt de `for x in it`
#
#   use iterator.iterator_errors as ie
#   try:
#       it.next()
#   catch StopIteration:
#       ...

from core use type

const STOP := "StopIteration"
const INVALID := "IteratorError"

func stop(fn):
    raise(STOP, fn + " : itérateur épuisé")

func invalid(fn, message):
    raise(INVALID, fn + " : " + message)

func need_fn(fn, f, label="la fonction"):
    if type(f) != "function":
        raise("TypeError", fn + " : " + label + " doit être une fonction (obtenu '" + type(f) + "')")

func need_int(fn, v, label):
    if type(v) != "int":
        raise("TypeError", fn + " : " + label + " doit être un int (obtenu '" + type(v) + "')")

func need_positive(fn, v, label):
    need_int(fn, v, label)
    if v < 1:
        invalid(fn, label + " doit être >= 1 (obtenu " + str(v) + ")")

func need_non_negative(fn, v, label):
    need_int(fn, v, label)
    if v < 0:
        invalid(fn, label + " doit être >= 0 (obtenu " + str(v) + ")")

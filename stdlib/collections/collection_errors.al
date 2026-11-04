# ALEX STANDARD LIBRARY — collections.collection_errors
#
# Erreurs communes aux collections de collections.* : noms de types, messages homogènes et vérifications
# d'arguments partagées. Toutes les collections lèvent par ces fonctions, ce qui garantit des messages
# identiques d'une structure à l'autre.
#
#   use collections.collection_errors as ce
#   ce.empty("Stack.pop")                     # EmptyCollectionError : « Stack.pop : collection vide »
#   ce.check_index("ArrayList.get", i, n)     # IndexError si i hors de 0..n-1
#
# Types d'erreurs :
#   EmptyCollectionError   retrait / lecture dans une collection vide
#   IndexError             position hors limites
#   KeyError               clé absente (tables associatives)
#   CapacityError          collection bornée pleine
#   ConcurrentModificationError   collection modifiée pendant un parcours par itérateur
#   TypeError, ArgumentError      argument invalide

from core use type

const EMPTY := "EmptyCollectionError"
const INDEX := "IndexError"
const KEY := "KeyError"
const CAPACITY := "CapacityError"
const CONCURRENT := "ConcurrentModificationError"

# Tous les types d'erreurs propres aux collections.
func kinds():
    return [EMPTY, INDEX, KEY, CAPACITY, CONCURRENT]

func empty(fn):
    raise(EMPTY, fn + " : collection vide")

func full(fn, capacity):
    raise(CAPACITY, fn + " : capacité atteinte (" + str(capacity) + " éléments)")

func missing_key(fn, key):
    raise(KEY, fn + " : clé absente " + _show(key))

func modified(fn):
    raise(CONCURRENT, fn + " : la collection a été modifiée pendant le parcours")

func need_int(fn, v, label="la position"):
    if type(v) != "int":
        raise("TypeError", fn + " : " + label + " doit être un int (obtenu '" + type(v) + "')")

# Position valide dans 0..size-1 (les positions négatives comptent depuis la fin) ; renvoie la position réelle.
func check_index(fn, i, size):
    need_int(fn, i)
    j := i
    if j < 0:
        j = size + j
    if j < 0 or j >= size:
        raise(INDEX, fn + " : position " + str(i) + " hors limites (taille " + str(size) + ")")
    return j

# Position d'insertion valide dans 0..size (négative : depuis la fin).
func check_insert_index(fn, i, size):
    need_int(fn, i)
    j := i
    if j < 0:
        j = size + j + 1
    if j < 0 or j > size:
        raise(INDEX, fn + " : position d'insertion " + str(i) + " hors limites (taille " + str(size) + ")")
    return j

func check_capacity(fn, capacity):
    if capacity == null:
        return
    if type(capacity) != "int":
        raise("TypeError", fn + " : capacité int ou null attendue (obtenu '" + type(capacity) + "')")
    if capacity < 1:
        raise("ArgumentError", fn + " : capacité >= 1 attendue (obtenu " + str(capacity) + ")")

func need_callable(fn, f, label="la fonction"):
    if f != null and type(f) != "function" and type(f) != "native":
        raise("TypeError", fn + " : " + label + " doit être une fonction (obtenu '" + type(f) + "')")

func _show(v):
    if type(v) == "str":
        return "\"" + v + "\""
    return str(v)

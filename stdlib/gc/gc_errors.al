# ALEX STANDARD LIBRARY — gc.gc_errors
#
# Erreurs du pilotage du ramasse-miettes :
#   GcConfigError   réglage invalide (seuil < 1, intervalle de stress négatif, préréglage inconnu)
#   GcRootError     racine inconnue ou déjà retirée (gc.gc_roots)
#   TypeError       valeur du mauvais type
#
#   use gc.gc_errors as ge

from core use type

const CONFIG := "GcConfigError"
const ROOT := "GcRootError"

func config(fn, message):
    raise(CONFIG, fn + " : " + message)

func root(fn, message):
    raise(ROOT, fn + " : " + message)

func need_int(fn, v, label, minimum):
    if type(v) != "int":
        raise("TypeError", fn + " : " + label + " doit être un int (obtenu '" + type(v) + "')")
    if v < minimum:
        config(fn, label + " doit être >= " + str(minimum) + " (obtenu " + str(v) + ")")

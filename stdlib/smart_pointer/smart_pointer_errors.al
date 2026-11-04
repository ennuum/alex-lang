# ALEX STANDARD LIBRARY — smart_pointer.smart_pointer_errors
#
# Erreurs des pointeurs intelligents :
#   NullPointerError   accès à la valeur d'un pointeur vide (jamais initialisé, reset(), release())
#   OwnershipError     usage d'un pointeur dont la propriété a été déplacée (move) ou relâchée (drop)
#   ExpiredError       lock_or_raise() sur un WeakPtr dont la valeur a été détruite
#   DeleterError       un suppresseur (deleter) a levé une erreur : la valeur est tout de même considérée
#                      comme détruite (pas de seconde tentative)
#
#   use smart_pointer.smart_pointer_errors as spe

from core use type

const NULL_POINTER := "NullPointerError"
const OWNERSHIP := "OwnershipError"
const EXPIRED := "ExpiredError"
const DELETER := "DeleterError"

func null_pointer(fn):
    raise(NULL_POINTER, fn + " : pointeur vide")

func moved(fn):
    raise(OWNERSHIP, fn + " : la propriété a été déplacée ou relâchée (utilisation après move/drop)")

func expired(fn):
    raise(EXPIRED, fn + " : la valeur pointée a été détruite")

func need_deleter(fn, d):
    if d != null and type(d) != "function":
        raise("TypeError", fn + " : le suppresseur doit être une fonction (obtenu '" + type(d) + "')")

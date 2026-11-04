# ALEX STANDARD LIBRARY — algorithm._common (interne)
#
# Ordre partagé par tous les algorithmes : clé key(x) facultative, comparateur cmp(a, b) -> int facultatif,
# reverse. Une liste vers laquelle convertir tout itérable usuel.

from core use type
from collections use append
use algorithm.algorithm_errors as _e

# -1 / 0 / 1 entre a et b.
func compare(a, b, key=null, cmp=null):
    if key != null:
        a = key(a)
        b = key(b)
    if cmp != null:
        r := cmp(a, b)
        if r < 0:
            return -1
        if r > 0:
            return 1
        return 0
    if a < b:
        return -1
    if b < a:
        return 1
    return 0

# Fonction (a, b) -> bool « a strictement avant b » pour key / cmp / reverse.
func less(key=null, cmp=null, reverse=false):
    if reverse:
        return (a, b) => compare(b, a, key, cmp) < 0
    return (a, b) => compare(a, b, key, cmp) < 0

func as_list(xs, fn):
    t := type(xs)
    if t == "list":
        return xs
    if t == "tuple" or t == "str":
        out := []
        for x in xs:
            append(out, x)
        return out
    if t == "instance":
        try:
            return xs.to_list()
        catch AttributeError:
            pass
    raise("TypeError", fn + " : séquence attendue (obtenu '" + t + "')")

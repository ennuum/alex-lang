# ALEX STANDARD LIBRARY — algorithm.min_max
#
# Extrema d'une séquence, avec key / cmp :
#   min / max                élément (EmptySequenceError si vide, sauf default fourni)
#   minmax                   [min, max] en une passe (~1,5 n comparaisons)
#   argmin / argmax          position (première en cas d'égalité)
#   min_k / max_k            les k plus petits / grands, triés
#   clamp(v, lo, hi)         borne une valeur
#   range_of(xs)             max - min
#
#   use algorithm.min_max as mm
#   print(mm.minmax([4, 9, 1, 7]))               # [1, 9]
#   print(mm.argmax(["aa", "b", "cccc"], (s) => len(s)))   # 2
#   print(mm.max([], null, null, 0))             # 0 (default)
#   print(mm.clamp(15, 0, 10))                   # 10
#
# Erreurs : EmptySequenceError, AlgorithmError (clamp lo > hi), TypeError.

from core use len, type
use algorithm._common as _c
use algorithm.algorithm_errors as _e
use algorithm.sort as _sort

const _NO_DEFAULT := "\u0000<pas de défaut>"

func _extreme(fn, xs, key, cmp, default, want_max):
    l := _c.as_list(xs, fn)
    if len(l) == 0:
        if type(default) == "str" and default == _NO_DEFAULT:
            _e.empty(fn)
        return default
    best := 0
    i := 1
    while i < len(l):
        c := _c.compare(l[i], l[best], key, cmp)
        if (want_max and c > 0) or (not want_max and c < 0):
            best = i
        i += 1
    return best

func min(xs, key=null, cmp=null, default=_NO_DEFAULT):
    i := _extreme("min", xs, key, cmp, default, false)
    if type(i) != "int" or len(_c.as_list(xs, "min")) == 0:
        return i
    return _c.as_list(xs, "min")[i]

func max(xs, key=null, cmp=null, default=_NO_DEFAULT):
    i := _extreme("max", xs, key, cmp, default, true)
    if type(i) != "int" or len(_c.as_list(xs, "max")) == 0:
        return i
    return _c.as_list(xs, "max")[i]

func argmin(xs, key=null, cmp=null):
    return _extreme("argmin", xs, key, cmp, _NO_DEFAULT, false)

func argmax(xs, key=null, cmp=null):
    return _extreme("argmax", xs, key, cmp, _NO_DEFAULT, true)

# [min, max] en comparant les éléments deux à deux.
func minmax(xs, key=null, cmp=null):
    l := _c.as_list(xs, "minmax")
    n := len(l)
    if n == 0:
        _e.empty("minmax")
    lo := l[0]
    hi := l[0]
    i := 1
    if n % 2 == 0:
        if _c.compare(l[1], l[0], key, cmp) < 0:
            lo = l[1]
        else:
            hi = l[1]
        i = 2
    while i + 1 < n:
        a := l[i]
        b := l[i + 1]
        if _c.compare(b, a, key, cmp) < 0:
            tmp := a
            a = b
            b = tmp
        if _c.compare(a, lo, key, cmp) < 0:
            lo = a
        if _c.compare(b, hi, key, cmp) >= 0:
            hi = b
        i += 2
    return [lo, hi]

# Positions [argmin, argmax].
func argminmax(xs, key=null, cmp=null):
    return [argmin(xs, key, cmp), argmax(xs, key, cmp)]

func min_k(xs, k, key=null, cmp=null):
    _e.need_int("min_k", k, "k")
    l := _c.as_list(xs, "min_k")[:]
    if k >= len(l):
        return _sort.sort(l, key, false, cmp)
    if k <= 0:
        return []
    return _sort.partial_sort(l, k, key, false, cmp)[:k]

func max_k(xs, k, key=null, cmp=null):
    _e.need_int("max_k", k, "k")
    l := _c.as_list(xs, "max_k")[:]
    if k >= len(l):
        return _sort.sort(l, key, true, cmp)
    if k <= 0:
        return []
    return _sort.partial_sort(l, k, key, true, cmp)[:k]

func clamp(v, lo, hi):
    if hi < lo:
        _e.invalid("clamp", "borne basse " + str(lo) + " > borne haute " + str(hi))
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v

func range_of(xs):
    r := minmax(xs)
    return r[1] - r[0]

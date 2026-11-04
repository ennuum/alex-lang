# ALEX STANDARD LIBRARY — algorithm.binary_search
#
# Recherche dichotomique sur une liste TRIÉE (selon key / cmp), en O(log n) :
#   lower_bound(xs, v)     première position où v pourrait être inséré en restant trié (avant les égaux)
#   upper_bound(xs, v)     idem après les égaux
#   equal_range(xs, v)     [lower, upper]
#   binary_search(xs, v)   position d'un élément égal, ou -1
#   contains(xs, v)
#   insort(xs, v)          insère en gardant l'ordre (après les égaux) ; insort_left : avant
#   first_true(lo, hi, p)  plus petit i de [lo, hi) tel que p(i) — p monotone (faux... puis vrai...) ; hi sinon
#   exponential_search     pour une liste très longue où la cible est près du début
#
#   use algorithm.binary_search as bs
#   xs := [1, 3, 3, 3, 7]
#   print(bs.lower_bound(xs, 3), bs.upper_bound(xs, 3))   # 1 4
#   print(bs.binary_search(xs, 7))                         # 4
#   bs.insort(xs, 5)                                       # [1, 3, 3, 3, 5, 7]
#   print(bs.first_true(0, 100, (i) => i * i >= 50))       # 8
#
# La recherche se fait sur la clé : avec key, comparer value à key(x) (value est déjà une clé). check=true
# vérifie que la liste est triée (O(n)) et lève UnsortedError sinon.
# Erreurs : TypeError, UnsortedError.

from core use len, type
from collections use insert
use algorithm._common as _c
use algorithm.algorithm_errors as _e

func _k(x, key):
    if key == null:
        return x
    return key(x)

func _verify(fn, xs, key, cmp):
    i := 1
    while i < len(xs):
        if _c.compare(_k(xs[i], key), _k(xs[i - 1], key), null, cmp) < 0:
            _e.unsorted(fn, i)
        i += 1

func lower_bound(xs, value, key=null, cmp=null, lo=0, hi=null, check=false):
    l := _c.as_list(xs, "lower_bound")
    if check:
        _verify("lower_bound", l, key, cmp)
    if hi == null:
        hi = len(l)
    while lo < hi:
        mid := (lo + hi) // 2
        if _c.compare(_k(l[mid], key), value, null, cmp) < 0:
            lo = mid + 1
        else:
            hi = mid
    return lo

func upper_bound(xs, value, key=null, cmp=null, lo=0, hi=null, check=false):
    l := _c.as_list(xs, "upper_bound")
    if check:
        _verify("upper_bound", l, key, cmp)
    if hi == null:
        hi = len(l)
    while lo < hi:
        mid := (lo + hi) // 2
        if _c.compare(value, _k(l[mid], key), null, cmp) < 0:
            hi = mid
        else:
            lo = mid + 1
    return lo

func equal_range(xs, value, key=null, cmp=null):
    return [lower_bound(xs, value, key, cmp), upper_bound(xs, value, key, cmp)]

# Nombre d'éléments égaux à value.
func count_equal(xs, value, key=null, cmp=null):
    r := equal_range(xs, value, key, cmp)
    return r[1] - r[0]

func binary_search(xs, value, key=null, cmp=null, check=false):
    l := _c.as_list(xs, "binary_search")
    i := lower_bound(l, value, key, cmp, 0, null, check)
    if i < len(l) and _c.compare(_k(l[i], key), value, null, cmp) == 0:
        return i
    return -1

func contains(xs, value, key=null, cmp=null):
    return binary_search(xs, value, key, cmp) >= 0

# Insère value après les éléments égaux ; renvoie la position.
func insort(xs, value, key=null, cmp=null):
    _e.need_list("insort", xs)
    i := upper_bound(xs, _k(value, key), key, cmp)
    insert(xs, i, value)
    return i

func insort_left(xs, value, key=null, cmp=null):
    _e.need_list("insort_left", xs)
    i := lower_bound(xs, _k(value, key), key, cmp)
    insert(xs, i, value)
    return i

# Plus petit i de [lo, hi) tel que pred(i) (pred monotone) ; hi si aucun.
func first_true(lo, hi, pred):
    _e.need_fn("first_true", pred, "le prédicat")
    while lo < hi:
        mid := (lo + hi) // 2
        if pred(mid):
            hi = mid
        else:
            lo = mid + 1
    return lo

# Plus grand i de [lo, hi) tel que pred(i) (pred vrai... puis faux) ; lo - 1 si aucun.
func last_true(lo, hi, pred):
    return first_true(lo, hi, (i) => not pred(i)) - 1

# Recherche de la racine d'une fonction croissante sur [lo, hi] à eps près (dichotomie réelle).
func bisect_real(f, lo, hi, eps=0.000000001, max_iter=200):
    a := lo * 1.0
    b := hi * 1.0
    fa := f(a)
    if fa == 0:
        return a
    k := 0
    while b - a > eps and k < max_iter:
        m := (a + b) / 2
        fm := f(m)
        if fm == 0:
            return m
        if (fm < 0) == (fa < 0):
            a = m
            fa = fm
        else:
            b = m
        k += 1
    return (a + b) / 2

func exponential_search(xs, value, key=null, cmp=null):
    l := _c.as_list(xs, "exponential_search")
    n := len(l)
    if n == 0:
        return -1
    bound := 1
    while bound < n and _c.compare(_k(l[bound], key), value, null, cmp) < 0:
        bound = bound * 2
    lo := bound // 2
    hi := bound + 1
    if hi > n:
        hi = n
    i := lower_bound(l, value, key, cmp, lo, hi)
    if i < n and _c.compare(_k(l[i], key), value, null, cmp) == 0:
        return i
    return -1

# ALEX STANDARD LIBRARY — algorithm.reduce
#
# Réductions et sommes préfixes :
#   reduce(xs, f, init)          f(f(f(init, x0), x1), ...) ; sans init : à partir du premier élément
#   fold_left / fold_right
#   accumulate / prefix_sum      sommes partielles inclusives (ou f) ; exclusive_scan : décalées de un
#   inner_product(a, b)          somme des a[i] * b[i] (ou opérations données)
#   sum / product / mean / count_by / sum_by
#   kahan_sum                    somme flottante compensée (erreur d'arrondi minimale)
#
#   use algorithm.reduce as rd
#   print(rd.reduce([1, 2, 3, 4], (a, x) => a * x))     # 24
#   print(rd.prefix_sum([1, 2, 3]))                     # [1, 3, 6]
#   print(rd.exclusive_scan([1, 2, 3]))                 # [0, 1, 3]
#   print(rd.inner_product([1, 2, 3], [4, 5, 6]))       # 32
#   print(rd.fold_right([1, 2, 3], (x, acc) => x - acc, 0))   # 2  (1 - (2 - (3 - 0)))
#
# Erreurs : EmptySequenceError (reduce sans init sur vide, mean), AlgorithmError (tailles), TypeError.

from core use len, type
from collections use append
use algorithm._common as _c
use algorithm.algorithm_errors as _e

const _NONE := "\u0000<aucune valeur initiale>"

func _no_init(v):
    return type(v) == "str" and v == _NONE

func reduce(xs, f, init=_NONE):
    _e.need_fn("reduce", f)
    l := _c.as_list(xs, "reduce")
    i := 0
    acc := init
    if _no_init(init):
        if len(l) == 0:
            _e.empty("reduce")
        acc = l[0]
        i = 1
    while i < len(l):
        acc = f(acc, l[i])
        i += 1
    return acc

func fold_left(xs, f, init):
    return reduce(xs, f, init)

# f(x, acc) de la droite vers la gauche.
func fold_right(xs, f, init):
    l := _c.as_list(xs, "fold_right")
    acc := init
    i := len(l) - 1
    while i >= 0:
        acc = f(l[i], acc)
        i -= 1
    return acc

# Résultats intermédiaires de reduce (inclusifs).
func accumulate(xs, f=null, init=_NONE):
    l := _c.as_list(xs, "accumulate")
    out := []
    has := not _no_init(init)
    acc := init
    for x in l:
        if not has:
            acc = x
            has = true
        elif f == null:
            acc = acc + x
        else:
            acc = f(acc, x)
        append(out, acc)
    return out

func prefix_sum(xs):
    return accumulate(xs)

# [init, init + x0, init + x0 + x1, ...] sans le total final.
func exclusive_scan(xs, init=0, f=null):
    l := _c.as_list(xs, "exclusive_scan")
    out := []
    acc := init
    for x in l:
        append(out, acc)
        if f == null:
            acc = acc + x
        else:
            acc = f(acc, x)
    return out

# Somme de mul(a[i], b[i]) combinée par add (par défaut : + et *).
func inner_product(a, b, init=0, add=null, mul=null):
    la := _c.as_list(a, "inner_product")
    lb := _c.as_list(b, "inner_product")
    if len(la) != len(lb):
        _e.invalid("inner_product", "tailles différentes (" + str(len(la)) + " et " + str(len(lb)) + ")")
    acc := init
    i := 0
    while i < len(la):
        p := 0
        if mul == null:
            p = la[i] * lb[i]
        else:
            p = mul(la[i], lb[i])
        if add == null:
            acc = acc + p
        else:
            acc = add(acc, p)
        i += 1
    return acc

func sum(xs, start=0):
    acc := start
    for x in _c.as_list(xs, "sum"):
        acc = acc + x
    return acc

func sum_by(xs, f):
    acc := 0
    for x in _c.as_list(xs, "sum_by"):
        acc = acc + f(x)
    return acc

func product(xs, start=1):
    acc := start
    for x in _c.as_list(xs, "product"):
        acc = acc * x
    return acc

func mean(xs):
    l := _c.as_list(xs, "mean")
    if len(l) == 0:
        _e.empty("mean")
    return kahan_sum(l) / len(l)

# Somme compensée de Kahan-Babuška (Neumaier).
func kahan_sum(xs):
    s := 0.0
    c := 0.0
    for x in _c.as_list(xs, "kahan_sum"):
        t := s + x
        if _abs(s) >= _abs(x):
            c += (s - t) + x
        else:
            c += (x - t) + s
        s = t
    return s + c

func _abs(x):
    if x < 0:
        return -x
    return x

# dict clé -> nombre d'éléments.
func count_by(xs, key):
    d := {}
    for x in _c.as_list(xs, "count_by"):
        k := key(x)
        if k in d:
            d[k] += 1
        else:
            d[k] = 1
    return d

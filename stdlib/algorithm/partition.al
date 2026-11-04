# ALEX STANDARD LIBRARY — algorithm.partition
#
# Partitions selon un prédicat :
#   partition(xs, pred)          EN PLACE : les vrais devant ; renvoie le point de partition (non stable)
#   stable_partition(xs, pred)   en place, ordre relatif conservé
#   partition_copy(xs, pred)     [vrais, faux] (nouvelles listes)
#   is_partitioned(xs, pred)     tous les vrais avant tous les faux ?
#   partition_point(xs, pred)    première position fausse d'une liste partitionnée (dichotomie)
#   three_way_partition(xs, pivot)   drapeau hollandais : [< pivot | == pivot | > pivot], renvoie [lt, gt]
#   split_by(xs, pred)           découpe aux éléments séparateurs
#
#   use algorithm.partition as pa
#   xs := [1, 2, 3, 4, 5, 6]
#   k := pa.stable_partition(xs, (x) => x % 2 == 0)     # xs = [2, 4, 6, 1, 3, 5], k = 3
#   print(pa.partition_copy([1, 2, 3], (x) => x > 1))    # [[2, 3], [1]]
#   print(pa.three_way_partition([3, 1, 2, 3, 5, 2], 3)) # [3, 5]  (xs : [1, 2, 2, 3, 3, 5] à l'ordre près)
#
# Erreurs : TypeError.

from core use len, type
from collections use append
use algorithm._common as _c
use algorithm.algorithm_errors as _e

func partition(xs, pred):
    _e.need_list("partition", xs)
    _e.need_fn("partition", pred, "le prédicat")
    k := 0
    i := 0
    while i < len(xs):
        if pred(xs[i]):
            tmp := xs[i]
            xs[i] = xs[k]
            xs[k] = tmp
            k += 1
        i += 1
    return k

func stable_partition(xs, pred):
    _e.need_list("stable_partition", xs)
    yes := []
    no := []
    for x in xs:
        if pred(x):
            append(yes, x)
        else:
            append(no, x)
    i := 0
    for x in yes:
        xs[i] = x
        i += 1
    for x in no:
        xs[i] = x
        i += 1
    return len(yes)

func partition_copy(xs, pred):
    yes := []
    no := []
    for x in _c.as_list(xs, "partition_copy"):
        if pred(x):
            append(yes, x)
        else:
            append(no, x)
    return [yes, no]

func is_partitioned(xs, pred):
    seen_false := false
    for x in _c.as_list(xs, "is_partitioned"):
        if pred(x):
            if seen_false:
                return false
        else:
            seen_false = true
    return true

func partition_point(xs, pred):
    l := _c.as_list(xs, "partition_point")
    lo := 0
    hi := len(l)
    while lo < hi:
        mid := (lo + hi) // 2
        if pred(l[mid]):
            lo = mid + 1
        else:
            hi = mid
    return lo

# En place : < pivot, puis == pivot, puis > pivot. Renvoie [début des égaux, début des plus grands].
func three_way_partition(xs, pivot, key=null, cmp=null):
    _e.need_list("three_way_partition", xs)
    lt := 0
    i := 0
    gt := len(xs)
    while i < gt:
        k := xs[i]
        if key != null:
            k = key(k)
        c := _c.compare(k, pivot, null, cmp)
        if c < 0:
            tmp := xs[i]
            xs[i] = xs[lt]
            xs[lt] = tmp
            lt += 1
            i += 1
        elif c > 0:
            gt -= 1
            tmp := xs[i]
            xs[i] = xs[gt]
            xs[gt] = tmp
        else:
            i += 1
    return [lt, gt]

# Découpe xs aux éléments pour lesquels is_sep(x) est vrai (séparateurs exclus).
func split_by(xs, is_sep, keep_empty=false):
    out := []
    cur := []
    for x in _c.as_list(xs, "split_by"):
        if is_sep(x):
            if keep_empty or len(cur) > 0:
                append(out, cur)
            cur = []
        else:
            append(cur, x)
    if keep_empty or len(cur) > 0:
        append(out, cur)
    return out

# Groupes de voisins de même clé : [[clé, [éléments]], ...] (comme itertools.groupby).
func group_runs(xs, key=null):
    out := []
    for x in _c.as_list(xs, "group_runs"):
        k := x
        if key != null:
            k = key(x)
        if len(out) > 0 and out[len(out) - 1][0] == k:
            append(out[len(out) - 1][1], x)
        else:
            append(out, [k, [x]])
    return out

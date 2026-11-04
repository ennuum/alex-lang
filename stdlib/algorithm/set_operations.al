# ALEX STANDARD LIBRARY — algorithm.set_operations
#
# Opérations ensemblistes sur des listes TRIÉES (fusion linéaire, O(n + m), multiensembles respectés
# comme std::set_union : un élément présent 2 fois d'un côté et 3 de l'autre apparaît 3 fois dans l'union) :
#   merge, set_union, set_intersection, set_difference, set_symmetric_difference, includes
# et leurs équivalents pour listes QUELCONQUES de valeurs hachables (ordre de première apparition) :
#   union, intersection, difference, symmetric_difference, is_subset, distinct
# plus : cartesian_product, power_set.
#
#   use algorithm.set_operations as so
#   print(so.set_union([1, 3, 5], [2, 3, 4]))          # [1, 2, 3, 4, 5]
#   print(so.set_intersection([1, 2, 2, 3], [2, 2, 5]))   # [2, 2]
#   print(so.includes([1, 2, 3, 4], [2, 4]))           # true
#   print(so.union([3, 1], [1, 2]))                    # [3, 1, 2]
#   print(so.cartesian_product([1, 2], "ab"))          # [[1, a], [1, b], [2, a], [2, b]]
#
# Erreurs : TypeError, UnsortedError (check=true sur une entrée non triée), AlgorithmError (power_set > 20).

from core use len, type
from collections use append
use algorithm._common as _c
use algorithm.algorithm_errors as _e

func _sorted_input(fn, xs, key, cmp, check):
    l := _c.as_list(xs, fn)
    if check:
        i := 1
        while i < len(l):
            if _c.compare(l[i], l[i - 1], key, cmp) < 0:
                _e.unsorted(fn, i)
            i += 1
    return l

# Fusion stable de deux listes triées.
func merge(a, b, key=null, cmp=null, check=false):
    la := _sorted_input("merge", a, key, cmp, check)
    lb := _sorted_input("merge", b, key, cmp, check)
    out := []
    i := 0
    j := 0
    while i < len(la) and j < len(lb):
        if _c.compare(lb[j], la[i], key, cmp) < 0:
            append(out, lb[j])
            j += 1
        else:
            append(out, la[i])
            i += 1
    while i < len(la):
        append(out, la[i])
        i += 1
    while j < len(lb):
        append(out, lb[j])
        j += 1
    return out

func set_union(a, b, key=null, cmp=null, check=false):
    la := _sorted_input("set_union", a, key, cmp, check)
    lb := _sorted_input("set_union", b, key, cmp, check)
    out := []
    i := 0
    j := 0
    while i < len(la) and j < len(lb):
        c := _c.compare(la[i], lb[j], key, cmp)
        if c < 0:
            append(out, la[i])
            i += 1
        elif c > 0:
            append(out, lb[j])
            j += 1
        else:
            append(out, la[i])
            i += 1
            j += 1
    while i < len(la):
        append(out, la[i])
        i += 1
    while j < len(lb):
        append(out, lb[j])
        j += 1
    return out

func set_intersection(a, b, key=null, cmp=null, check=false):
    la := _sorted_input("set_intersection", a, key, cmp, check)
    lb := _sorted_input("set_intersection", b, key, cmp, check)
    out := []
    i := 0
    j := 0
    while i < len(la) and j < len(lb):
        c := _c.compare(la[i], lb[j], key, cmp)
        if c < 0:
            i += 1
        elif c > 0:
            j += 1
        else:
            append(out, la[i])
            i += 1
            j += 1
    return out

func set_difference(a, b, key=null, cmp=null, check=false):
    la := _sorted_input("set_difference", a, key, cmp, check)
    lb := _sorted_input("set_difference", b, key, cmp, check)
    out := []
    i := 0
    j := 0
    while i < len(la):
        if j >= len(lb):
            append(out, la[i])
            i += 1
            continue
        c := _c.compare(la[i], lb[j], key, cmp)
        if c < 0:
            append(out, la[i])
            i += 1
        elif c > 0:
            j += 1
        else:
            i += 1
            j += 1
    return out

func set_symmetric_difference(a, b, key=null, cmp=null, check=false):
    la := _sorted_input("set_symmetric_difference", a, key, cmp, check)
    lb := _sorted_input("set_symmetric_difference", b, key, cmp, check)
    out := []
    i := 0
    j := 0
    while i < len(la) and j < len(lb):
        c := _c.compare(la[i], lb[j], key, cmp)
        if c < 0:
            append(out, la[i])
            i += 1
        elif c > 0:
            append(out, lb[j])
            j += 1
        else:
            i += 1
            j += 1
    while i < len(la):
        append(out, la[i])
        i += 1
    while j < len(lb):
        append(out, lb[j])
        j += 1
    return out

# Tout élément de b (avec multiplicité) figure-t-il dans a ? (deux listes triées)
func includes(a, b, key=null, cmp=null, check=false):
    la := _sorted_input("includes", a, key, cmp, check)
    lb := _sorted_input("includes", b, key, cmp, check)
    i := 0
    j := 0
    while j < len(lb):
        if i >= len(la):
            return false
        c := _c.compare(la[i], lb[j], key, cmp)
        if c < 0:
            i += 1
        elif c > 0:
            return false
        else:
            i += 1
            j += 1
    return true

# ---------------------------------------------------------------- listes quelconques (valeurs hachables)

func distinct(xs):
    seen := {}
    out := []
    for x in _c.as_list(xs, "distinct"):
        if not (x in seen):
            seen[x] = true
            append(out, x)
    return out

func union(a, b):
    return distinct(_c.as_list(a, "union") + _c.as_list(b, "union"))

func intersection(a, b):
    sb := {}
    for x in _c.as_list(b, "intersection"):
        sb[x] = true
    return [x for x in distinct(a) if x in sb]

func difference(a, b):
    sb := {}
    for x in _c.as_list(b, "difference"):
        sb[x] = true
    return [x for x in distinct(a) if not (x in sb)]

func symmetric_difference(a, b):
    return difference(a, b) + difference(b, a)

func is_subset(a, b):
    sb := {}
    for x in _c.as_list(b, "is_subset"):
        sb[x] = true
    for x in _c.as_list(a, "is_subset"):
        if not (x in sb):
            return false
    return true

func is_disjoint(a, b):
    return len(intersection(a, b)) == 0

func cartesian_product(a, b):
    lb := _c.as_list(b, "cartesian_product")
    out := []
    for x in _c.as_list(a, "cartesian_product"):
        for y in lb:
            append(out, [x, y])
    return out

# Tous les sous-ensembles (2^n, n <= 20), du plus petit au plus grand masque.
func power_set(xs):
    l := _c.as_list(xs, "power_set")
    n := len(l)
    if n > 20:
        _e.invalid("power_set", str(n) + " éléments : 2^" + str(n) + " sous-ensembles, trop (max 20)")
    out := []
    m := 0
    while m < (1 << n):
        sub := []
        i := 0
        while i < n:
            if ((m >> i) & 1) == 1:
                append(sub, l[i])
            i += 1
        append(out, sub)
        m += 1
    return out

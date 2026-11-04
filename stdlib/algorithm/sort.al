# ALEX STANDARD LIBRARY — algorithm.sort
#
# Tris EN PLACE sur une liste, tous paramétrables par key (clé), cmp (comparateur -> int) et reverse :
#   sort           tri fusion STABLE (O(n log n)) — le tri par défaut
#   quick_sort     tri rapide à pivot médian de trois, introspectif (repli tas au-delà de 2 log n niveaux)
#   heap_sort      O(n log n) garanti, sans mémoire supplémentaire, non stable
#   insertion_sort stable, idéal pour les petites listes ou presque triées
#   shell_sort     suite de Ciura
#   counting_sort  entiers dans un intervalle restreint, O(n + plage)
#   radix_sort     entiers positifs ou négatifs, base 256
#   natural_sort   chaînes « humaines » : "fichier2" avant "fichier10"
# et : sorted (copie triée), is_sorted, is_sorted_until, partial_sort, nth_element (sélection), argsort.
#
#   use algorithm.sort as srt
#   xs := [5, 2, 9, 1]
#   srt.sort(xs)                                  # [1, 2, 5, 9]
#   srt.sort(gens, (p) => p["age"], true)         # par âge décroissant, stable
#   srt.natural_sort(["f10", "f2", "f1"])         # ["f1", "f2", "f10"]
#   print(srt.nth_element([7, 1, 5, 3], 1))       # 3 (2e plus petit)
#   print(srt.argsort([30, 10, 20]))              # [1, 2, 0]
#
# Erreurs : TypeError (liste attendue, éléments non comparables), AlgorithmError (k hors limites).

from core use len, type, to_int
from collections use append
use string as _s
use algorithm._common as _c
use algorithm.algorithm_errors as _e

func _check(fn, xs, key, cmp):
    _e.need_list(fn, xs)
    _e.need_fn(fn, key, "key")
    _e.need_fn(fn, cmp, "cmp")

# ---------------------------------------------------------------- fusion (stable)

func _merge_sort(xs, lo, hi, tmp, lt):
    if hi - lo <= 16:
        _insertion(xs, lo, hi, lt)
        return
    mid := (lo + hi) // 2
    _merge_sort(xs, lo, mid, tmp, lt)
    _merge_sort(xs, mid, hi, tmp, lt)
    if not lt(xs[mid], xs[mid - 1]):
        return
    i := lo
    while i < mid:
        tmp[i] = xs[i]
        i += 1
    i = lo
    j := mid
    k := lo
    while i < mid and j < hi:
        if lt(xs[j], tmp[i]):
            xs[k] = xs[j]
            j += 1
        else:
            xs[k] = tmp[i]
            i += 1
        k += 1
    while i < mid:
        xs[k] = tmp[i]
        i += 1
        k += 1

func _insertion(xs, lo, hi, lt):
    i := lo + 1
    while i < hi:
        v := xs[i]
        j := i - 1
        while j >= lo and lt(v, xs[j]):
            xs[j + 1] = xs[j]
            j -= 1
        xs[j + 1] = v
        i += 1

# Tri stable en place (renvoie la liste pour chaîner).
func sort(xs, key=null, reverse=false, cmp=null):
    _check("sort", xs, key, cmp)
    n := len(xs)
    if n < 2:
        return xs
    if key != null:
        # Clés calculées une seule fois (décoration).
        dec := [[key(xs[i]), i, xs[i]] for i in 0..n]
        lt := _c.less(null, cmp, reverse)
        _merge_sort(dec, 0, n, [null] * n, (a, b) => lt(a[0], b[0]))
        i := 0
        while i < n:
            xs[i] = dec[i][2]
            i += 1
        return xs
    _merge_sort(xs, 0, n, [null] * n, _c.less(null, cmp, reverse))
    return xs

# Copie triée (la liste d'origine ne change pas). Accepte tuple, str, collection.
func sorted(xs, key=null, reverse=false, cmp=null):
    return sort(_c.as_list(xs, "sorted")[:], key, reverse, cmp)

func insertion_sort(xs, key=null, reverse=false, cmp=null):
    _check("insertion_sort", xs, key, cmp)
    _insertion(xs, 0, len(xs), _c.less(key, cmp, reverse))
    return xs

# ---------------------------------------------------------------- rapide (introspectif)

func _sift(xs, lo, start, end, lt):
    root := start
    while true:
        child := 2 * (root - lo) + 1 + lo
        if child >= end:
            return
        if child + 1 < end and lt(xs[child], xs[child + 1]):
            child += 1
        if lt(xs[root], xs[child]):
            tmp := xs[root]
            xs[root] = xs[child]
            xs[child] = tmp
            root = child
        else:
            return

func _heap_range(xs, lo, hi, lt):
    n := hi - lo
    start := lo + n // 2 - 1
    while start >= lo:
        _sift(xs, lo, start, hi, lt)
        start -= 1
    end := hi - 1
    while end > lo:
        tmp := xs[lo]
        xs[lo] = xs[end]
        xs[end] = tmp
        _sift(xs, lo, lo, end, lt)
        end -= 1

func _median3(xs, a, b, c, lt):
    if lt(xs[a], xs[b]):
        if lt(xs[b], xs[c]):
            return b
        if lt(xs[a], xs[c]):
            return c
        return a
    if lt(xs[a], xs[c]):
        return a
    if lt(xs[b], xs[c]):
        return c
    return b

func _partition(xs, lo, hi, lt):
    m := _median3(xs, lo, (lo + hi - 1) // 2, hi - 1, lt)
    pivot := xs[m]
    xs[m] = xs[hi - 1]
    xs[hi - 1] = pivot
    store := lo
    i := lo
    while i < hi - 1:
        if lt(xs[i], pivot):
            tmp := xs[i]
            xs[i] = xs[store]
            xs[store] = tmp
            store += 1
        i += 1
    xs[hi - 1] = xs[store]
    xs[store] = pivot
    return store

func _intro(xs, lo, hi, depth, lt):
    while hi - lo > 16:
        if depth == 0:
            _heap_range(xs, lo, hi, lt)
            return
        depth -= 1
        p := _partition(xs, lo, hi, lt)
        # Récursion sur la plus petite moitié : pile en O(log n).
        if p - lo < hi - p - 1:
            _intro(xs, lo, p, depth, lt)
            lo = p + 1
        else:
            _intro(xs, p + 1, hi, depth, lt)
            hi = p
    _insertion(xs, lo, hi, lt)

func _log2(n):
    k := 0
    while n > 1:
        n = n // 2
        k += 1
    return k

func quick_sort(xs, key=null, reverse=false, cmp=null):
    _check("quick_sort", xs, key, cmp)
    _intro(xs, 0, len(xs), 2 * _log2(len(xs) + 1), _c.less(key, cmp, reverse))
    return xs

func heap_sort(xs, key=null, reverse=false, cmp=null):
    _check("heap_sort", xs, key, cmp)
    _heap_range(xs, 0, len(xs), _c.less(key, cmp, reverse))
    return xs

func shell_sort(xs, key=null, reverse=false, cmp=null):
    _check("shell_sort", xs, key, cmp)
    lt := _c.less(key, cmp, reverse)
    gaps := [701, 301, 132, 57, 23, 10, 4, 1]
    n := len(xs)
    for g in gaps:
        i := g
        while i < n:
            v := xs[i]
            j := i
            while j >= g and lt(v, xs[j - g]):
                xs[j] = xs[j - g]
                j -= g
            xs[j] = v
            i += 1
    return xs

# ---------------------------------------------------------------- entiers

func _need_ints(fn, xs):
    for x in xs:
        if type(x) != "int":
            raise("TypeError", fn + " : entiers attendus (trouvé '" + type(x) + "')")

# Tri par comptage : entiers dont la plage max - min reste raisonnable (max_range).
func counting_sort(xs, reverse=false, max_range=10000000):
    _e.need_list("counting_sort", xs)
    if len(xs) < 2:
        return xs
    _need_ints("counting_sort", xs)
    lo := xs[0]
    hi := xs[0]
    for x in xs:
        if x < lo:
            lo = x
        if x > hi:
            hi = x
    if hi - lo + 1 > max_range:
        _e.invalid("counting_sort", "plage " + str(hi - lo + 1) + " trop grande (max_range " + str(max_range) + ")")
    counts := [0] * (hi - lo + 1)
    for x in xs:
        counts[x - lo] += 1
    k := 0
    if reverse:
        v := hi - lo
        while v >= 0:
            c := counts[v]
            while c > 0:
                xs[k] = v + lo
                k += 1
                c -= 1
            v -= 1
    else:
        v := 0
        while v <= hi - lo:
            c := counts[v]
            while c > 0:
                xs[k] = v + lo
                k += 1
                c -= 1
            v += 1
    return xs

func _radix_pos(xs):
    if len(xs) < 2:
        return xs
    mx := 0
    for x in xs:
        if x > mx:
            mx = x
    shift := 0
    cur := xs
    while (mx >> shift) > 0:
        buckets := [[] for _b in 0..256]
        for x in cur:
            append(buckets[(x >> shift) & 255], x)
        nxt := []
        for b in buckets:
            for x in b:
                append(nxt, x)
        cur = nxt
        shift += 8
    return cur

# Tri par base (256), stable ; entiers de tout signe.
func radix_sort(xs, reverse=false):
    _e.need_list("radix_sort", xs)
    _need_ints("radix_sort", xs)
    neg := [-x for x in xs if x < 0]
    pos := [x for x in xs if x >= 0]
    neg = _radix_pos(neg)
    pos = _radix_pos(pos)
    out := [-x for x in neg[::-1]] + pos
    if reverse:
        out = out[::-1]
    i := 0
    while i < len(out):
        xs[i] = out[i]
        i += 1
    return xs

# ---------------------------------------------------------------- tri naturel

func _is_digit(c):
    return c >= '0' and c <= '9'

# Découpe "img12b" en ["img", 12, "b"] (chiffres -> nombres).
func natural_key(s, ignore_case=true):
    text := str(s)
    if ignore_case:
        text = _s.lower(text)
    parts := []
    cur := ""
    num := false
    for c in text:
        d := _is_digit(c)
        if cur != "" and d != num:
            if num:
                append(parts, [1, to_int(cur), ""])
            else:
                append(parts, [0, 0, cur])
            cur = ""
        num = d
        cur += str(c)
    if cur != "":
        if num:
            append(parts, [1, to_int(cur), ""])
        else:
            append(parts, [0, 0, cur])
    return parts

func _natural_cmp(a, b):
    i := 0
    while i < len(a) and i < len(b):
        x := a[i]
        y := b[i]
        if x[0] != y[0]:
            # Nombre avant texte.
            return y[0] - x[0]
        if x[0] == 1:
            if x[1] != y[1]:
                return x[1] - y[1]
        else:
            if x[2] < y[2]:
                return -1
            if x[2] > y[2]:
                return 1
        i += 1
    return len(a) - len(b)

func natural_sort(xs, reverse=false, ignore_case=true):
    _e.need_list("natural_sort", xs)
    return sort(xs, (s) => natural_key(s, ignore_case), reverse, _natural_cmp)

# ---------------------------------------------------------------- prédicats et sélection

func is_sorted(xs, key=null, reverse=false, cmp=null):
    return is_sorted_until(xs, key, reverse, cmp) == len(_c.as_list(xs, "is_sorted"))

# Longueur du plus long préfixe trié.
func is_sorted_until(xs, key=null, reverse=false, cmp=null):
    l := _c.as_list(xs, "is_sorted_until")
    lt := _c.less(key, cmp, reverse)
    i := 1
    while i < len(l):
        if lt(l[i], l[i - 1]):
            return i
        i += 1
    return len(l)

# Les k premiers (dans l'ordre) en tête de liste ; le reste dans un ordre quelconque.
func partial_sort(xs, k, key=null, reverse=false, cmp=null):
    _check("partial_sort", xs, key, cmp)
    _e.need_int("partial_sort", k, "k")
    if k < 0 or k > len(xs):
        _e.invalid("partial_sort", "k = " + str(k) + " hors de 0.." + str(len(xs)))
    if k == 0:
        return xs
    lt := _c.less(key, cmp, reverse)
    _quickselect(xs, 0, len(xs), k - 1, lt)
    head := xs[:k]
    _merge_sort(head, 0, k, [null] * k, lt)
    i := 0
    while i < k:
        xs[i] = head[i]
        i += 1
    return xs

func _quickselect(xs, lo, hi, k, lt):
    while hi - lo > 1:
        p := _partition(xs, lo, hi, lt)
        if k == p:
            return
        if k < p:
            hi = p
        else:
            lo = p + 1

# k-ième plus petit (0 = minimum) ; réordonne la liste (sélection en O(n) moyen).
func nth_element(xs, k, key=null, reverse=false, cmp=null):
    _check("nth_element", xs, key, cmp)
    _e.need_int("nth_element", k, "k")
    if k < 0 or k >= len(xs):
        _e.invalid("nth_element", "k = " + str(k) + " hors de 0.." + str(len(xs) - 1))
    _quickselect(xs, 0, len(xs), k, _c.less(key, cmp, reverse))
    return xs[k]

# Positions qui trieraient la liste (stable) ; la liste n'est pas modifiée.
func argsort(xs, key=null, reverse=false, cmp=null):
    l := _c.as_list(xs, "argsort")
    idx := [i for i in 0..len(l)]
    if key == null:
        return sort(idx, (i) => l[i], reverse, cmp)
    return sort(idx, (i) => key(l[i]), reverse, cmp)

# Applique un ordre de positions (résultat d'argsort) : nouvelle liste.
func apply_order(xs, order):
    return [xs[i] for i in order]

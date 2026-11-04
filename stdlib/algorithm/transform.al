# ALEX STANDARD LIBRARY — algorithm.transform
#
# Transformations de séquences. Les fonctions « _in_place » modifient la liste reçue ; les autres
# rendent une NOUVELLE liste.
#   transform / transform_in_place   f(x)
#   transform2(a, b, f)              f(a[i], b[i])
#   fill / generate / iota           remplissages
#   replace / replace_if             substitutions
#   remove / remove_if / erase       retraits (nouvelle liste / en place)
#   unique / unique_in_place         retire les répétitions CONSÉCUTIVES (std::unique)
#   rotate / reverse_in_place / swap_ranges
#   shuffle / sample                 aléatoire reproductible (graine)
#   adjacent_difference, flatten, chunk, interleave, repeat_each
#
#   use algorithm.transform as tr
#   print(tr.transform([1, 2, 3], (x) => x * 10))       # [10, 20, 30]
#   print(tr.iota(5, 1))                                 # [1, 2, 3, 4, 5]
#   print(tr.rotate([1, 2, 3, 4], 1))                    # [2, 3, 4, 1]
#   print(tr.unique([1, 1, 2, 2, 1]))                    # [1, 2, 1]
#   print(tr.shuffle([1, 2, 3, 4], 42))                  # même graine : même ordre
#   print(tr.adjacent_difference([1, 4, 9]))             # [1, 3, 5]
#
# Erreurs : TypeError, AlgorithmError (tailles différentes, taille de paquet nulle).

from core use len, type
from collections use append, pop
use random as _rnd
use algorithm._common as _c
use algorithm.algorithm_errors as _e

func transform(xs, f):
    _e.need_fn("transform", f)
    return [f(x) for x in _c.as_list(xs, "transform")]

func transform_in_place(xs, f):
    _e.need_list("transform_in_place", xs)
    i := 0
    while i < len(xs):
        xs[i] = f(xs[i])
        i += 1
    return xs

func transform2(a, b, f):
    la := _c.as_list(a, "transform2")
    lb := _c.as_list(b, "transform2")
    if len(la) != len(lb):
        _e.invalid("transform2", "tailles différentes (" + str(len(la)) + " et " + str(len(lb)) + ")")
    return [f(la[i], lb[i]) for i in 0..len(la)]

# Avec la position : f(i, x).
func transform_indexed(xs, f):
    l := _c.as_list(xs, "transform_indexed")
    return [f(i, l[i]) for i in 0..len(l)]

func fill(xs, value, start=0, stop=null):
    _e.need_list("fill", xs)
    if stop == null:
        stop = len(xs)
    i := start
    while i < stop:
        xs[i] = value
        i += 1
    return xs

# n valeurs f(), ou f(i) si f prend un paramètre (with_index=true).
func generate(n, f, with_index=false):
    _e.need_int("generate", n, "n")
    out := []
    i := 0
    while i < n:
        if with_index:
            append(out, f(i))
        else:
            append(out, f())
        i += 1
    return out

# n valeurs start, start + step...
func iota(n, start=0, step=1):
    _e.need_int("iota", n, "n")
    return [start + i * step for i in 0..n]

func replace(xs, old, new):
    return [new if x == old else x for x in _c.as_list(xs, "replace")]

func replace_if(xs, pred, new):
    return [new if pred(x) else x for x in _c.as_list(xs, "replace_if")]

func remove(xs, value):
    return [x for x in _c.as_list(xs, "remove") if not (x == value)]

func remove_if(xs, pred):
    return [x for x in _c.as_list(xs, "remove_if") if not pred(x)]

# Retire en place les x tels que pred(x) ; renvoie le nombre retiré.
func erase_if(xs, pred):
    _e.need_list("erase_if", xs)
    k := 0
    i := 0
    n := len(xs)
    while i < n:
        if not pred(xs[i]):
            xs[k] = xs[i]
            k += 1
        i += 1
    removed := n - k
    while len(xs) > k:
        pop(xs)
    return removed

func erase(xs, value):
    return erase_if(xs, (x) => x == value)

func unique(xs, key=null):
    l := _c.as_list(xs, "unique")
    out := []
    i := 0
    while i < len(l):
        if i == 0:
            append(out, l[i])
        else:
            a := l[i - 1]
            b := l[i]
            if key != null:
                a = key(a)
                b = key(b)
            if not (a == b):
                append(out, l[i])
        i += 1
    return out

func unique_in_place(xs, key=null):
    _e.need_list("unique_in_place", xs)
    u := unique(xs, key)
    i := 0
    while i < len(u):
        xs[i] = u[i]
        i += 1
    while len(xs) > len(u):
        pop(xs)
    return xs

# Décalage à gauche de k (k négatif : à droite) ; nouvelle liste.
func rotate(xs, k):
    l := _c.as_list(xs, "rotate")
    n := len(l)
    if n == 0:
        return []
    k = k % n
    return l[k:] + l[:k]

func rotate_in_place(xs, k):
    _e.need_list("rotate_in_place", xs)
    r := rotate(xs, k)
    i := 0
    while i < len(r):
        xs[i] = r[i]
        i += 1
    return xs

func reverse_in_place(xs, start=0, stop=null):
    _e.need_list("reverse_in_place", xs)
    if stop == null:
        stop = len(xs)
    i := start
    j := stop - 1
    while i < j:
        tmp := xs[i]
        xs[i] = xs[j]
        xs[j] = tmp
        i += 1
        j -= 1
    return xs

# Échange a[i] et b[i] pour i < n (n : la plus courte).
func swap_ranges(a, b):
    _e.need_list("swap_ranges", a)
    _e.need_list("swap_ranges", b)
    n := len(a)
    if len(b) < n:
        n = len(b)
    i := 0
    while i < n:
        tmp := a[i]
        a[i] = b[i]
        b[i] = tmp
        i += 1
    return n

func _gen(seed):
    if seed == null:
        return null
    return _rnd.new(seed)

# Permutation aléatoire (Fisher-Yates) ; même seed => même résultat. Nouvelle liste.
func shuffle(xs, seed=null):
    l := _c.as_list(xs, "shuffle")[:]
    g := _gen(seed)
    i := len(l) - 1
    while i > 0:
        j := _rnd.randbelow(i + 1, g)
        tmp := l[i]
        l[i] = l[j]
        l[j] = tmp
        i -= 1
    return l

# k éléments distincts tirés sans remise, dans l'ordre du tirage.
func sample(xs, k, seed=null):
    l := _c.as_list(xs, "sample")
    _e.need_int("sample", k, "k")
    if k < 0 or k > len(l):
        _e.invalid("sample", "k = " + str(k) + " hors de 0.." + str(len(l)))
    return shuffle(l, seed)[:k]

# [x0, x1 - x0, x2 - x1, ...] (ou f(courant, précédent)).
func adjacent_difference(xs, f=null):
    l := _c.as_list(xs, "adjacent_difference")
    out := []
    i := 0
    while i < len(l):
        if i == 0:
            append(out, l[0])
        elif f == null:
            append(out, l[i] - l[i - 1])
        else:
            append(out, f(l[i], l[i - 1]))
        i += 1
    return out

func flatten(xs, depth=1):
    out := []
    for x in _c.as_list(xs, "flatten"):
        if type(x) == "list" and depth > 0:
            for y in flatten(x, depth - 1):
                append(out, y)
        else:
            append(out, x)
    return out

func chunk(xs, n):
    _e.need_int("chunk", n, "la taille")
    if n < 1:
        _e.invalid("chunk", "taille de paquet >= 1 attendue")
    return _chunks(_c.as_list(xs, "chunk"), n)

func _chunks(l, n):
    out := []
    i := 0
    while i < len(l):
        append(out, l[i:i + n])
        i += n
    return out

func interleave(a, b):
    la := _c.as_list(a, "interleave")
    lb := _c.as_list(b, "interleave")
    out := []
    i := 0
    while i < len(la) or i < len(lb):
        if i < len(la):
            append(out, la[i])
        if i < len(lb):
            append(out, lb[i])
        i += 1
    return out

func repeat_each(xs, n):
    out := []
    for x in _c.as_list(xs, "repeat_each"):
        k := 0
        while k < n:
            append(out, x)
            k += 1
    return out

func copy_if(xs, pred):
    return [x for x in _c.as_list(xs, "copy_if") if pred(x)]

# ALEX STANDARD LIBRARY — algorithm.search
#
# Recherche linéaire dans une séquence (liste, tuple, str, collection) :
#   find / find_if / find_last / find_last_if     position ou -1
#   count / count_if
#   search(xs, motif)          première occurrence d'une sous-séquence (Knuth-Morris-Pratt, O(n + m))
#   find_all(xs, motif)        toutes les occurrences (chevauchantes ou non)
#   adjacent_find              première paire de voisins égaux (ou vérifiant pred)
#   mismatch                   première position où deux séquences diffèrent
#   starts_with / ends_with / contains_all / contains_any / index_where
#
#   use algorithm.search as se
#   print(se.find([4, 7, 9], 7))                         # 1
#   print(se.search([1, 2, 3, 1, 2, 3], [2, 3]))         # 1
#   print(se.find_all("abababa", "aba"))                 # [0, 2, 4]
#   print(se.find_all("abababa", "aba", false))          # [0, 4]
#   print(se.mismatch([1, 2, 3], [1, 2, 4]))             # 2
#
# Erreurs : TypeError.

from core use len, type
from collections use append
use algorithm._common as _c
use algorithm.algorithm_errors as _e

func find(xs, value, start=0):
    l := _c.as_list(xs, "find")
    i := start
    while i < len(l):
        if l[i] == value:
            return i
        i += 1
    return -1

func find_if(xs, pred, start=0):
    _e.need_fn("find_if", pred, "le prédicat")
    l := _c.as_list(xs, "find_if")
    i := start
    while i < len(l):
        if pred(l[i]):
            return i
        i += 1
    return -1

func find_if_not(xs, pred):
    return find_if(xs, (x) => not pred(x))

func find_last(xs, value):
    l := _c.as_list(xs, "find_last")
    i := len(l) - 1
    while i >= 0:
        if l[i] == value:
            return i
        i -= 1
    return -1

func find_last_if(xs, pred):
    l := _c.as_list(xs, "find_last_if")
    i := len(l) - 1
    while i >= 0:
        if pred(l[i]):
            return i
        i -= 1
    return -1

# Premier élément vérifiant pred (default sinon).
func first_where(xs, pred, default=null):
    i := find_if(xs, pred)
    if i < 0:
        return default
    return _c.as_list(xs, "first_where")[i]

# Positions de tous les éléments vérifiant pred.
func index_where(xs, pred):
    l := _c.as_list(xs, "index_where")
    return [i for i in 0..len(l) if pred(l[i])]

func count(xs, value):
    n := 0
    for x in _c.as_list(xs, "count"):
        if x == value:
            n += 1
    return n

func count_if(xs, pred):
    n := 0
    for x in _c.as_list(xs, "count_if"):
        if pred(x):
            n += 1
    return n

func _failure(p):
    m := len(p)
    f := [0] * m
    k := 0
    i := 1
    while i < m:
        while k > 0 and not (p[i] == p[k]):
            k = f[k - 1]
        if p[i] == p[k]:
            k += 1
        f[i] = k
        i += 1
    return f

# Positions des occurrences de pattern dans xs (KMP). overlapping=false : occurrences disjointes.
func find_all(xs, pattern, overlapping=true):
    l := _c.as_list(xs, "find_all")
    p := _c.as_list(pattern, "find_all")
    out := []
    m := len(p)
    if m == 0:
        return [i for i in 0..(len(l) + 1)]
    f := _failure(p)
    k := 0
    i := 0
    while i < len(l):
        while k > 0 and not (l[i] == p[k]):
            k = f[k - 1]
        if l[i] == p[k]:
            k += 1
        if k == m:
            append(out, i - m + 1)
            if overlapping:
                k = f[k - 1]
            else:
                k = 0
        i += 1
    return out

# Première occurrence de la sous-séquence pattern ; -1 si absente.
func search(xs, pattern):
    l := _c.as_list(xs, "search")
    p := _c.as_list(pattern, "search")
    m := len(p)
    if m == 0:
        return 0
    f := _failure(p)
    k := 0
    i := 0
    while i < len(l):
        while k > 0 and not (l[i] == p[k]):
            k = f[k - 1]
        if l[i] == p[k]:
            k += 1
        if k == m:
            return i - m + 1
        i += 1
    return -1

# Première position de n éléments consécutifs égaux à value.
func search_n(xs, n, value):
    l := _c.as_list(xs, "search_n")
    run := 0
    i := 0
    while i < len(l):
        if l[i] == value:
            run += 1
            if run == n:
                return i - n + 1
        else:
            run = 0
        i += 1
    return -1

# Première position i telle que xs[i] == xs[i + 1] (ou pred(xs[i], xs[i + 1])).
func adjacent_find(xs, pred=null):
    l := _c.as_list(xs, "adjacent_find")
    i := 0
    while i + 1 < len(l):
        if pred == null:
            if l[i] == l[i + 1]:
                return i
        elif pred(l[i], l[i + 1]):
            return i
        i += 1
    return -1

# Première position où a et b diffèrent ; -1 si identiques (même longueur comprise).
func mismatch(a, b):
    la := _c.as_list(a, "mismatch")
    lb := _c.as_list(b, "mismatch")
    i := 0
    while i < len(la) and i < len(lb):
        if not (la[i] == lb[i]):
            return i
        i += 1
    if len(la) == len(lb):
        return -1
    return i

func starts_with(xs, prefix):
    l := _c.as_list(xs, "starts_with")
    p := _c.as_list(prefix, "starts_with")
    if len(p) > len(l):
        return false
    i := 0
    while i < len(p):
        if not (l[i] == p[i]):
            return false
        i += 1
    return true

func ends_with(xs, suffix):
    l := _c.as_list(xs, "ends_with")
    p := _c.as_list(suffix, "ends_with")
    off := len(l) - len(p)
    if off < 0:
        return false
    i := 0
    while i < len(p):
        if not (l[off + i] == p[i]):
            return false
        i += 1
    return true

func contains(xs, value):
    return find(xs, value) >= 0

func contains_all(xs, values):
    for v in _c.as_list(values, "contains_all"):
        if find(xs, v) < 0:
            return false
    return true

func contains_any(xs, values):
    for v in _c.as_list(values, "contains_any"):
        if find(xs, v) >= 0:
            return true
    return false

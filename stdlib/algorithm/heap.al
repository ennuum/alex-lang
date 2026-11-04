# ALEX STANDARD LIBRARY — algorithm.heap
#
# Tas binaire DANS une liste ordinaire (comme heapq de Python / std::make_heap de C++) : xs[0] est le plus
# petit (max=true : le plus grand). La liste reste une liste, utilisable telle quelle ; pour un objet file de
# priorité complet, voir collections.priority_queue.
#   heapify, heap_push, heap_pop, heap_peek, heap_replace, heap_push_pop, is_heap, heap_sort,
#   n_smallest, n_largest, merge_sorted
#
#   use algorithm.heap as hp
#   h := [5, 1, 8, 3]
#   hp.heapify(h)
#   hp.heap_push(h, 0)
#   print(hp.heap_pop(h), hp.heap_pop(h))        # 0 1
#   m := [2, 9, 4]
#   hp.heapify(m, null, true)                    # tas max
#   print(hp.heap_pop(m, null, true))            # 9
#   print(hp.n_largest([4, 1, 7, 3], 2))         # [7, 4]
#
# Tous les appels sur un même tas doivent utiliser la même key / le même max.
# Erreurs : EmptySequenceError, TypeError.

from core use len, type
from collections use append, pop
use algorithm._common as _c
use algorithm.algorithm_errors as _e

func _order(key, max):
    if max:
        return (a, b) => _c.compare(a, b, key, null) > 0
    return (a, b) => _c.compare(a, b, key, null) < 0

func _lt(a, b, key, max):
    c := _c.compare(a, b, key, null)
    if max:
        return c > 0
    return c < 0

func _up(h, i, lt):
    while i > 0:
        p := (i - 1) // 2
        if lt(h[i], h[p]):
            tmp := h[i]
            h[i] = h[p]
            h[p] = tmp
            i = p
        else:
            return

func _down(h, i, n, lt):
    while true:
        l := 2 * i + 1
        r := l + 1
        best := i
        if l < n and lt(h[l], h[best]):
            best = l
        if r < n and lt(h[r], h[best]):
            best = r
        if best == i:
            return
        tmp := h[i]
        h[i] = h[best]
        h[best] = tmp
        i = best

func heapify(h, key=null, max=false):
    _e.need_list("heapify", h)
    i := len(h) // 2 - 1
    while i >= 0:
        _down(h, i, len(h), _order(key, max))
        i -= 1
    return h

func heap_push(h, value, key=null, max=false):
    _e.need_list("heap_push", h)
    append(h, value)
    _up(h, len(h) - 1, _order(key, max))

func heap_pop(h, key=null, max=false):
    _e.need_list("heap_pop", h)
    if len(h) == 0:
        _e.empty("heap_pop")
    top := h[0]
    last := pop(h)
    if len(h) > 0:
        h[0] = last
        _down(h, 0, len(h), _order(key, max))
    return top

func heap_peek(h):
    if len(h) == 0:
        _e.empty("heap_peek")
    return h[0]

# Retire le sommet puis ajoute value (taille constante).
func heap_replace(h, value, key=null, max=false):
    if len(h) == 0:
        _e.empty("heap_replace")
    top := h[0]
    h[0] = value
    _down(h, 0, len(h), _order(key, max))
    return top

# Ajoute value puis retire le sommet.
func heap_push_pop(h, value, key=null, max=false):
    if len(h) > 0 and _lt(h[0], value, key, max):
        top := h[0]
        h[0] = value
        _down(h, 0, len(h), _order(key, max))
        return top
    return value

func is_heap(h, key=null, max=false):
    i := 1
    while i < len(h):
        if _lt(h[i], h[(i - 1) // 2], key, max):
            return false
        i += 1
    return true

# Tri par tas : nouvelle liste croissante (max=true : décroissante).
func heap_sort(xs, key=null, max=false):
    h := _c.as_list(xs, "heap_sort")[:]
    heapify(h, key, max)
    out := []
    while len(h) > 0:
        append(out, heap_pop(h, key, max))
    return out

func n_smallest(xs, n, key=null):
    h := _c.as_list(xs, "n_smallest")[:]
    heapify(h, key)
    out := []
    while len(out) < n and len(h) > 0:
        append(out, heap_pop(h, key))
    return out

func n_largest(xs, n, key=null):
    h := _c.as_list(xs, "n_largest")[:]
    heapify(h, key, true)
    out := []
    while len(out) < n and len(h) > 0:
        append(out, heap_pop(h, key, true))
    return out

# Fusion de k listes triées (stable : à clé égale, la liste de plus petit rang d'abord).
func merge_sorted(lists, key=null):
    lt := (a, b) => a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])
    h := []
    i := 0
    while i < len(lists):
        if len(lists[i]) > 0:
            v := lists[i][0]
            k := v
            if key != null:
                k = key(v)
            append(h, [k, i, 0])
            _up(h, len(h) - 1, lt)
        i += 1
    out := []
    while len(h) > 0:
        top := h[0]
        last := pop(h)
        if len(h) > 0:
            h[0] = last
            _down(h, 0, len(h), lt)
        src := lists[top[1]]
        append(out, src[top[2]])
        nxt := top[2] + 1
        if nxt < len(src):
            v := src[nxt]
            k := v
            if key != null:
                k = key(v)
            append(h, [k, top[1], nxt])
            _up(h, len(h) - 1, lt)
    return out

# ALEX STANDARD LIBRARY — algorithm
#
# Algorithmes génériques sur les séquences, dans l'esprit de <algorithm> (C++) et d'itertools/heapq/bisect
# (Python). Tous acceptent une clé (key), un comparateur (cmp) et, pour les tris, reverse.
#
#   use algorithm
#   xs := [5, 3, 8, 1]
#   algorithm.sort(xs)                             # tri stable en place
#   print(algorithm.binary_search(xs, 5))          # 2
#   print(algorithm.minmax(xs))                    # [1, 8]
#   print(algorithm.reduce(xs, (a, x) => a + x))   # 17
#
# Sous-modules
#   algorithm.sort            sort sorted quick_sort heap_sort insertion_sort shell_sort counting_sort radix_sort
#                             natural_sort is_sorted partial_sort nth_element argsort
#   algorithm.search          find find_if count search (KMP) find_all adjacent_find mismatch starts_with...
#   algorithm.binary_search   lower_bound upper_bound equal_range binary_search insort first_true bisect_real
#   algorithm.min_max         min max minmax argmin argmax min_k max_k clamp
#   algorithm.transform       transform fill generate iota replace remove unique rotate shuffle sample...
#   algorithm.reduce          reduce fold_left fold_right accumulate prefix_sum inner_product kahan_sum mean
#   algorithm.partition       partition stable_partition partition_point three_way_partition split_by
#   algorithm.set_operations  set_union set_intersection set_difference includes merge union cartesian_product
#   algorithm.heap            heapify heap_push heap_pop heap_sort n_smallest n_largest merge_sorted
#
# Ce module rassemble les fonctions les plus courantes (raccourcis vers les sous-modules).
# Erreurs : voir algorithm.algorithm_errors.

use algorithm.sort as _sort
use algorithm.search as _search
use algorithm.binary_search as _bs
use algorithm.min_max as _mm
use algorithm.transform as _tr
use algorithm.reduce as _rd
use algorithm.partition as _pa
use algorithm.set_operations as _so
use algorithm.heap as _hp

const VERSION := "1.0.0"

func sort(xs, key=null, reverse=false, cmp=null):
    return _sort.sort(xs, key, reverse, cmp)

func sorted(xs, key=null, reverse=false, cmp=null):
    return _sort.sorted(xs, key, reverse, cmp)

func is_sorted(xs, key=null, reverse=false, cmp=null):
    return _sort.is_sorted(xs, key, reverse, cmp)

func nth_element(xs, k, key=null):
    return _sort.nth_element(xs, k, key)

func argsort(xs, key=null, reverse=false):
    return _sort.argsort(xs, key, reverse)

func find(xs, value):
    return _search.find(xs, value)

func find_if(xs, pred):
    return _search.find_if(xs, pred)

func count_if(xs, pred):
    return _search.count_if(xs, pred)

func search(xs, pattern):
    return _search.search(xs, pattern)

func lower_bound(xs, value, key=null):
    return _bs.lower_bound(xs, value, key)

func upper_bound(xs, value, key=null):
    return _bs.upper_bound(xs, value, key)

func binary_search(xs, value, key=null):
    return _bs.binary_search(xs, value, key)

func insort(xs, value, key=null):
    return _bs.insort(xs, value, key)

func min(xs, key=null):
    return _mm.min(xs, key)

func max(xs, key=null):
    return _mm.max(xs, key)

func minmax(xs, key=null):
    return _mm.minmax(xs, key)

func argmin(xs, key=null):
    return _mm.argmin(xs, key)

func argmax(xs, key=null):
    return _mm.argmax(xs, key)

func clamp(v, lo, hi):
    return _mm.clamp(v, lo, hi)

func transform(xs, f):
    return _tr.transform(xs, f)

func unique(xs, key=null):
    return _tr.unique(xs, key)

func rotate(xs, k):
    return _tr.rotate(xs, k)

func shuffle(xs, seed=null):
    return _tr.shuffle(xs, seed)

func iota(n, start=0, step=1):
    return _tr.iota(n, start, step)

func reduce(xs, f, init="\u0000<aucune valeur initiale>"):
    return _rd.reduce(xs, f, init)

func accumulate(xs, f=null):
    return _rd.accumulate(xs, f)

func inner_product(a, b):
    return _rd.inner_product(a, b)

func partition(xs, pred):
    return _pa.partition(xs, pred)

func stable_partition(xs, pred):
    return _pa.stable_partition(xs, pred)

func set_union(a, b):
    return _so.set_union(a, b)

func set_intersection(a, b):
    return _so.set_intersection(a, b)

func set_difference(a, b):
    return _so.set_difference(a, b)

func merge(a, b, key=null):
    return _so.merge(a, b, key)

func heapify(h, key=null, max=false):
    return _hp.heapify(h, key, max)

func n_largest(xs, n, key=null):
    return _hp.n_largest(xs, n, key)

func n_smallest(xs, n, key=null):
    return _hp.n_smallest(xs, n, key)

# Tests : algorithm.* (sort, search, binary_search, min_max, transform, reduce, partition, set_operations, heap).
from core use len, type
from collections use append
use check as t
use random
use algorithm
use algorithm.sort as srt
use algorithm.search as se
use algorithm.binary_search as bs
use algorithm.min_max as mm
use algorithm.transform as tr
use algorithm.reduce as rd
use algorithm.partition as pa
use algorithm.set_operations as so
use algorithm.heap as hp

func rand_list(n, seed):
    g := random.new(seed)
    return [random.randbelow(1000, g) - 500 for i in 0..n]

func ascending(xs):
    i := 1
    while i < len(xs):
        if xs[i] < xs[i - 1]:
            return false
        i += 1
    return true

# ---------------------------------------------------------------- sort
ref := sorted(rand_list(300, 1))
for name in ["sort", "quick", "heap", "insertion", "shell", "radix", "counting"]:
    xs := rand_list(300, 1)
    if name == "sort":
        srt.sort(xs)
    elif name == "quick":
        srt.quick_sort(xs)
    elif name == "heap":
        srt.heap_sort(xs)
    elif name == "insertion":
        srt.insertion_sort(xs)
    elif name == "shell":
        srt.shell_sort(xs)
    elif name == "radix":
        srt.radix_sort(xs)
    else:
        srt.counting_sort(xs)
    t.eq(xs, ref, "tri " + name)
desc := rand_list(50, 3)
srt.quick_sort(desc, null, true)
t.check(ascending(desc[::-1]), "quick_sort décroissant")
people := [{"n": "a", "age": 30}, {"n": "b", "age": 20}, {"n": "c", "age": 30}, {"n": "d", "age": 20}]
srt.sort(people, (p) => p["age"])
t.eq([p["n"] for p in people], ["b", "d", "a", "c"], "stable avec key")
srt.sort(people, (p) => p["age"], true)
t.eq([p["n"] for p in people], ["a", "c", "b", "d"], "stable décroissant")
t.eq(srt.natural_sort(["f10", "f2", "F1", "f1b"]), ["F1", "f1b", "f2", "f10"], "natural_sort")
t.eq(srt.nth_element([7, 1, 5, 3], 1), 3, "nth_element")
t.eq(srt.argsort([30, 10, 20]), [1, 2, 0], "argsort")
t.eq(srt.partial_sort([9, 4, 7, 1, 8, 2], 3)[:3], [1, 2, 4], "partial_sort")
t.check(srt.is_sorted([1, 2, 2, 5]), "is_sorted")
t.eq(srt.is_sorted_until([1, 3, 2, 4]), 2, "is_sorted_until")
t.eq(srt.sorted((3, 1, 2)), [1, 2, 3], "sorted tuple")
t.eq(srt.sort([3, 1, 2], null, false, (a, b) => b - a), [3, 2, 1], "cmp")
big := rand_list(3000, 7)
srt.quick_sort(big)
t.check(ascending(big), "quick_sort 3000")
same := [5] * 500
srt.quick_sort(same)
t.eq(len(same), 500, "quick_sort valeurs égales")
sorted_in := [i for i in 0..2000]
srt.quick_sort(sorted_in)
t.check(ascending(sorted_in), "quick_sort entrée déjà triée")
t.raises(() => srt.counting_sort([0, 100000000]), "AlgorithmError", "counting_sort plage")
t.raises(() => srt.sort("abc"), "TypeError", "sort sur str")

# ---------------------------------------------------------------- search
t.eq(se.find([4, 7, 9], 7), 1, "find")
t.eq(se.search([1, 2, 3, 1, 2, 3], [2, 3]), 1, "search")
t.eq(se.search([1, 2], [3]), -1, "search absent")
t.eq(se.find_all("abababa", "aba"), [0, 2, 4], "find_all chevauchant")
t.eq(se.find_all("abababa", "aba", false), [0, 4], "find_all disjoint")
t.eq(se.mismatch([1, 2, 3], [1, 2, 4]), 2, "mismatch")
t.eq(se.mismatch([1, 2], [1, 2]), -1, "mismatch identiques")
t.eq(se.adjacent_find([1, 2, 2, 3]), 1, "adjacent_find")
t.eq(se.search_n([1, 0, 0, 0, 1], 3, 0), 1, "search_n")
t.check(se.starts_with([1, 2, 3], [1, 2]) and se.ends_with("hello", "llo"), "starts/ends_with")
t.eq(se.count_if([1, 2, 3, 4], (x) => x > 2), 2, "count_if")
t.eq(se.find_last([1, 2, 1], 1), 2, "find_last")
t.eq(se.index_where([5, 1, 5], (x) => x == 5), [0, 2], "index_where")

# ---------------------------------------------------------------- binary_search
xs := [1, 3, 3, 3, 7]
t.eq(bs.lower_bound(xs, 3), 1, "lower_bound")
t.eq(bs.upper_bound(xs, 3), 4, "upper_bound")
t.eq(bs.equal_range(xs, 3), [1, 4], "equal_range")
t.eq(bs.binary_search(xs, 7), 4, "binary_search")
t.eq(bs.binary_search(xs, 4), -1, "binary_search absent")
bs.insort(xs, 5)
t.eq(xs, [1, 3, 3, 3, 5, 7], "insort")
t.eq(bs.first_true(0, 100, (i) => i * i >= 50), 8, "first_true")
t.eq(bs.last_true(0, 100, (i) => i * i <= 50), 7, "last_true")
r := bs.bisect_real((x) => x * x - 2, 0, 2)
t.check(r > 1.41421 and r < 1.41422, "bisect_real")
t.raises(() => bs.binary_search([3, 1, 2], 1, null, null, true), "UnsortedError", "check")
recs := [{"k": 1}, {"k": 4}, {"k": 9}]
t.eq(bs.lower_bound(recs, 4, (r) => r["k"]), 1, "lower_bound key")
t.eq(bs.exponential_search([i * 2 for i in 0..1000], 1500), 750, "exponential_search")

# ---------------------------------------------------------------- min_max
t.eq(mm.minmax([4, 9, 1, 7]), [1, 9], "minmax")
t.eq(mm.minmax([4, 9, 1]), [1, 9], "minmax impair")
t.eq(mm.argmax(["aa", "b", "cccc"], (s) => len(s)), 2, "argmax")
t.eq(mm.min([3, 1, 2]), 1, "min")
t.eq(mm.max([], null, null, 0), 0, "max défaut")
t.raises(() => mm.min([]), "EmptySequenceError", "min vide")
t.eq(mm.clamp(15, 0, 10), 10, "clamp")
t.eq(mm.min_k([5, 1, 4, 2, 3], 2), [1, 2], "min_k")
t.eq(mm.max_k([5, 1, 4, 2, 3], 2), [5, 4], "max_k")
t.eq(mm.range_of([3, 9, 4]), 6, "range_of")

# ---------------------------------------------------------------- transform
t.eq(tr.transform([1, 2, 3], (x) => x * 10), [10, 20, 30], "transform")
t.eq(tr.iota(5, 1), [1, 2, 3, 4, 5], "iota")
t.eq(tr.rotate([1, 2, 3, 4], 1), [2, 3, 4, 1], "rotate")
t.eq(tr.rotate([1, 2, 3, 4], -1), [4, 1, 2, 3], "rotate négatif")
t.eq(tr.unique([1, 1, 2, 2, 1]), [1, 2, 1], "unique")
t.eq(tr.shuffle([1, 2, 3, 4, 5], 42), tr.shuffle([1, 2, 3, 4, 5], 42), "shuffle reproductible")
t.eq(sorted(tr.shuffle([1, 2, 3, 4, 5], 7)), [1, 2, 3, 4, 5], "shuffle permutation")
t.eq(tr.adjacent_difference([1, 4, 9]), [1, 3, 5], "adjacent_difference")
er := [1, 2, 3, 4, 5]
t.eq(tr.erase_if(er, (x) => x % 2 == 0), 2, "erase_if")
t.eq(er, [1, 3, 5], "erase_if en place")
t.eq(tr.flatten([1, [2, [3]]], 2), [1, 2, 3], "flatten")
t.eq(tr.chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]], "chunk")
t.eq(tr.interleave([1, 3], [2, 4, 6]), [1, 2, 3, 4, 6], "interleave")
t.eq(len(tr.sample([1, 2, 3, 4], 2, 1)), 2, "sample")
t.raises(() => tr.transform2([1], [1, 2], (a, b) => a), "AlgorithmError", "transform2 tailles")
t.eq(tr.replace([1, 2, 1], 1, 0), [0, 2, 0], "replace")
t.eq(tr.generate(3, (i) => i * i, true), [0, 1, 4], "generate")

# ---------------------------------------------------------------- reduce
t.eq(rd.reduce([1, 2, 3, 4], (a, x) => a * x), 24, "reduce")
t.eq(rd.reduce([], (a, x) => a + x, 7), 7, "reduce init")
t.raises(() => rd.reduce([], (a, x) => a + x), "EmptySequenceError", "reduce vide")
t.eq(rd.prefix_sum([1, 2, 3]), [1, 3, 6], "prefix_sum")
t.eq(rd.exclusive_scan([1, 2, 3]), [0, 1, 3], "exclusive_scan")
t.eq(rd.inner_product([1, 2, 3], [4, 5, 6]), 32, "inner_product")
t.eq(rd.fold_right([1, 2, 3], (x, acc) => x - acc, 0), 2, "fold_right")
t.eq(rd.mean([1, 2, 3, 4]), 2.5, "mean")
t.eq(rd.kahan_sum([0.1] * 10), 1.0, "kahan_sum")
t.eq(rd.count_by(["a", "bb", "c"], (s) => len(s))[1], 2, "count_by")
t.eq(rd.accumulate([1, 2, 3], (a, x) => a * x), [1, 2, 6], "accumulate f")

# ---------------------------------------------------------------- partition
ps := [1, 2, 3, 4, 5, 6]
t.eq(pa.stable_partition(ps, (x) => x % 2 == 0), 3, "stable_partition point")
t.eq(ps, [2, 4, 6, 1, 3, 5], "stable_partition ordre")
up := [1, 2, 3, 4, 5, 6]
k := pa.partition(up, (x) => x > 3)
t.check(k == 3 and pa.is_partitioned(up, (x) => x > 3), "partition")
t.eq(pa.partition_point([2, 4, 6, 1, 3], (x) => x % 2 == 0), 3, "partition_point")
tw := [3, 1, 2, 3, 5, 2]
b3 := pa.three_way_partition(tw, 3)
t.eq(b3, [3, 5], "three_way bornes")
t.eq(sorted(tw[:3]), [1, 2, 2], "three_way <")
t.eq(tw[3:5], [3, 3], "three_way ==")
t.eq(pa.partition_copy([1, 2, 3], (x) => x > 1), [[2, 3], [1]], "partition_copy")
t.eq(pa.split_by([1, 0, 2, 3, 0, 0, 4], (x) => x == 0), [[1], [2, 3], [4]], "split_by")
t.eq(pa.group_runs([1, 1, 2, 1]), [[1, [1, 1]], [2, [2]], [1, [1]]], "group_runs")

# ---------------------------------------------------------------- set_operations
t.eq(so.set_union([1, 3, 5], [2, 3, 4]), [1, 2, 3, 4, 5], "set_union")
t.eq(so.set_intersection([1, 2, 2, 3], [2, 2, 5]), [2, 2], "set_intersection multi")
t.eq(so.set_difference([1, 2, 3, 4], [2, 4]), [1, 3], "set_difference")
t.eq(so.set_symmetric_difference([1, 2, 3], [2, 3, 4]), [1, 4], "set_symmetric_difference")
t.check(so.includes([1, 2, 3, 4], [2, 4]), "includes")
t.check(not so.includes([1, 2, 3], [2, 2]), "includes multiplicité")
t.eq(so.merge([1, 4], [2, 3, 5]), [1, 2, 3, 4, 5], "merge")
t.eq(so.union([3, 1], [1, 2]), [3, 1, 2], "union non triée")
t.eq(so.intersection([3, 1, 2], [2, 3]), [3, 2], "intersection non triée")
t.eq(so.difference([3, 1, 2], [2]), [3, 1], "difference non triée")
t.eq(len(so.cartesian_product([1, 2], [3, 4, 5])), 6, "cartesian_product")
t.eq(len(so.power_set([1, 2, 3])), 8, "power_set")
t.raises(() => so.set_union([2, 1], [1], null, null, true), "UnsortedError", "check trié")

# ---------------------------------------------------------------- heap
h := [5, 1, 8, 3]
hp.heapify(h)
t.check(hp.is_heap(h), "heapify")
hp.heap_push(h, 0)
t.eq(hp.heap_pop(h), 0, "heap_pop")
t.eq(hp.heap_pop(h), 1, "heap_pop 2")
m := [2, 9, 4]
hp.heapify(m, null, true)
t.eq(hp.heap_pop(m, null, true), 9, "tas max")
t.eq(hp.n_largest([4, 1, 7, 3], 2), [7, 4], "n_largest")
t.eq(hp.n_smallest([4, 1, 7, 3], 2), [1, 3], "n_smallest")
t.eq(hp.heap_sort([3, 1, 2]), [1, 2, 3], "heap_sort")
t.eq(hp.merge_sorted([[1, 4], [2, 5], [3]]), [1, 2, 3, 4, 5], "merge_sorted")
t.eq(hp.heap_push_pop([1, 5], 0), 0, "heap_push_pop")
t.raises(() => hp.heap_pop([]), "EmptySequenceError", "heap_pop vide")

# ---------------------------------------------------------------- façade
f := [3, 1, 2]
algorithm.sort(f)
t.eq(f, [1, 2, 3], "algorithm.sort")
t.eq(algorithm.reduce(f, (a, x) => a + x), 6, "algorithm.reduce")
t.eq(algorithm.binary_search(f, 2), 1, "algorithm.binary_search")

t.summary("algorithm")

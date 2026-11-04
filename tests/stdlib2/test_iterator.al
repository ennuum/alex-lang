# Tests : iterator.* (Iterator, Iter, map_iterator, filter, enumerate, zip, range, erreurs).
from core use len, type
from collections use append
use check as t
use iterator
use iterator.map_iterator as mi
use iterator.filter as flt
use iterator.enumerate as en
use iterator.zip as z
use iterator.range as rg
use iterator.iterator_errors as ie
from iterator._base use Iterator

class Countdown extends Iterator:
    func init(n):
        super.init()
        self.n = n
    func _fetch():
        if self.n <= 0:
            return false
        self._item = self.n
        self.n -= 1
        return true

func is_prime(n):
    if n < 2:
        return false
    d := 2
    while d * d <= n:
        if n % d == 0:
            return false
        d += 1
    return true

t.eq(iterator.iter([1, 2, 3, 4, 5, 6]).filter((x) => x % 2 == 0).map((x) => x * x).to_list(), [4, 16, 36], "pipeline")
seen := []
for p in iterator.iter("ab").enumerate(1):
    append(seen, str(p[0]) + str(p[1]))
t.eq(seen, ["1a", "2b"], "for + enumerate")
t.eq(iterator.count(2).filter(is_prime).take(5).to_list(), [2, 3, 5, 7, 11], "infini + take")
fib := iterator.successors([0, 1], (p) => [p[1], p[0] + p[1]]).map((p) => p[0]).take(8).to_list()
t.eq(fib, [0, 1, 1, 2, 3, 5, 8, 13], "successors")
t.eq(iterator.iter([3, 1, 2]).sorted().to_list(), [1, 2, 3], "sorted")
t.eq(Countdown(3).to_list(), [3, 2, 1], "itérateur personnalisé")
cd := Countdown(2)
t.eq(cd.peek(), 2, "peek")
t.eq(cd.next(), 2, "next après peek")
t.eq(cd.next(), 1, "next")
t.check(not cd.has_next(), "épuisé")
t.raises(() => cd.next(), "StopIteration", "StopIteration")
t.eq(cd.next_or(9), 9, "next_or")
s := 0
for x in Countdown(4):
    s += x
t.eq(s, 10, "for sur Iterator")
st := [0]
func produce():
    st[0] += 1
    if st[0] > 3:
        return null
    return st[0]
t.eq(iterator.from_function(produce).to_list(), [1, 2, 3], "from_function")
t.eq(iterator.unfold(1, (x) => null if x > 16 else [x, x * 2]).to_list(), [1, 2, 4, 8, 16], "unfold")
t.eq(iterator.repeat("x", 3).to_list(), ["x", "x", "x"], "repeat")
t.eq(iterator.iter([1, 2]).cycle(3).to_list(), [1, 2, 1, 2, 1, 2], "cycle borné")
t.eq(iterator.cycle([1, 2]).take(5).to_list(), [1, 2, 1, 2, 1], "cycle infini")
t.eq(iterator.iter([1, 2, 3, 4, 5]).chunks(2).to_list(), [[1, 2], [3, 4], [5]], "chunks")
t.eq(iterator.iter([1, 2, 3, 4]).windows(3).to_list(), [[1, 2, 3], [2, 3, 4]], "windows")
t.eq(iterator.iter([1, 2, 3]).pairwise().to_list(), [[1, 2], [2, 3]], "pairwise")
t.eq(iterator.iter([1, 2, 3]).zip("ab").to_list(), [[1, 'a'], [2, 'b']], "zip méthode")
t.eq(iterator.iter([1]).chain([2], [3]).to_list(), [1, 2, 3], "chain méthode")
t.eq(iterator.iter([1, 2, 3, 4]).reduce((a, x) => a + x, 0), 10, "reduce")
t.eq(iterator.of(4, 9, 2).max(), 9, "max")
t.eq(iterator.of("aaa", "b", "cc").min((x) => len(x)), "b", "min key")
t.eq(iterator.of(1, 2, 3).join("-"), "1-2-3", "join")
t.eq(iterator.of(1, 2, 3, 4).partition((x) => x > 2), [[3, 4], [1, 2]], "partition")
t.eq(iterator.of(1, 2, 3).nth(1), 2, "nth")
t.eq(iterator.of(1, 2, 3).last(), 3, "last")
t.check(iterator.of(1, 2).equals([1, 2]), "equals")
t.check(not iterator.of(1, 2).equals([1, 2, 3]), "equals longueur")
t.eq(iterator.of(1, 2, 3).any((x) => x > 2), true, "any")
t.eq(iterator.of(1, 2, 3).all((x) => x > 2), false, "all")
t.eq(iterator.of(["a", 1], ["b", 2]).to_dict()["b"], 2, "to_dict")
t.eq(iterator.of(1, 2, 3, 4).group_by((x) => x % 2)[0], [2, 4], "group_by")
t.eq(iterator.of(5, 6, 7).find_index((x) => x == 6), 1, "find_index")
t.eq(iterator.iter({"k": 1, "j": 2}).to_list(), ["k", "j"], "dict -> clés")
t.eq(iterator.iter((1, 2)).count(), 2, "tuple")

# map_iterator
t.eq(mi.StarMapIterator([[1, 2], [3, 4]], (a, b) => a + b).to_list(), [3, 7], "star_map")
t.eq(mi.FlatMapIterator([1, 2], (x) => [x, x * 10]).to_list(), [1, 10, 2, 20], "flat_map")
t.eq(mi.flatten([[1], [], [2, 3]]).to_list(), [1, 2, 3], "flatten")
t.eq(mi.ScanIterator([1, 2, 3], (a, x) => a + x, 0).to_list(), [1, 3, 6], "scan")
log := []
mi.inspect([1, 2], (x) => append(log, x)).to_list()
t.eq(log, [1, 2], "inspect")
calls := [0]
func sq(x):
    calls[0] += 1
    return x * x
lazy := mi.map([1, 2, 3, 4], sq)
lazy.next()
t.eq(calls[0], 1, "paresseux : un seul calcul")

# filter
t.eq(flt.filter([0, 1, "", "a", null]).to_list(), [1, "a"], "filter sans prédicat")
t.eq(flt.reject([1, 2, 3], (x) => x == 2).to_list(), [1, 3], "reject")
t.eq(flt.filter_map([1, 2, 3], (x) => x * 2 if x != 2 else null).to_list(), [2, 6], "filter_map")
t.eq(flt.TakeWhileIterator([1, 2, 5, 1], (x) => x < 3).to_list(), [1, 2], "take_while")
t.eq(flt.skip_while([1, 2, 5, 1], (x) => x < 3).to_list(), [5, 1], "skip_while")
t.eq(flt.skip([1, 2, 3], 2).to_list(), [3], "skip")
t.eq(flt.step_by([0, 1, 2, 3, 4, 5, 6], 3).to_list(), [0, 3, 6], "step_by")
t.eq(flt.DedupIterator([1, 1, 2, 1]).to_list(), [1, 2, 1], "dedup")
t.eq(flt.UniqueIterator([1, 1, 2, 1]).to_list(), [1, 2], "unique")
t.eq(flt.unique(["a", "B", "A"], (x) => x.lower()).to_list(), ["a", "B"], "unique key")
t.raises(() => flt.take([1], -1), "IteratorError", "take négatif")
t.raises(() => flt.step_by([1], 0), "IteratorError", "pas nul")

# enumerate
t.eq(en.indexed("xy").to_list(), [[0, 'x'], [1, 'y']], "indexed")
t.eq(en.positions([5, 2, 5], (x) => x == 5), [0, 2], "positions")
t.eq(en.Enumerate(["a", "b"], 10, 5).to_list(), [[10, "a"], [15, "b"]], "start/step")

# zip
t.eq(z.zip([1, 2, 3], "ab").to_list(), [[1, 'a'], [2, 'b']], "zip")
t.eq(z.zip_longest([1], [7, 8], 0).to_list(), [[1, 7], [0, 8]], "zip_longest")
t.eq(z.zip_with([1, 2], [10, 20], (a, b) => a + b).to_list(), [11, 22], "zip_with")
t.eq(z.interleave([1, 2, 3], ["a"]).to_list(), [1, "a", 2, 3], "interleave")
t.eq(z.unzip([[1, "a"], [2, "b"]]), [[1, 2], ["a", "b"]], "unzip")
t.raises(() => z.Zip([]), "IteratorError", "zip vide")

# range
r := rg.Range(0, 10, 3)
t.eq(r.to_list(), [0, 3, 6, 9], "range")
t.eq(r.size(), 4, "size")
t.check(r.contains(6) and not r.contains(7), "contains")
t.eq(r.get(-1), 9, "get négatif")
t.eq(r.index_of(9), 3, "index_of")
t.eq(rg.Range(5).to_list(), [0, 1, 2, 3, 4], "Range(stop)")
t.eq(rg.Range(5, 0, -2).to_list(), [5, 3, 1], "pas négatif")
t.eq(rg.Range(0, 1, 0.25).to_list(), [0, 0.25, 0.5, 0.75], "flottants")
t.eq(rg.Range(0, 1, 0.25).size(), 4, "size flottante")
t.eq(rg.Range(0, 10, 3).reversed().to_list(), [9, 6, 3, 0], "reversed")
t.eq(rg.Range(1, 101).sum(), 5050, "sum")
t.eq(rg.linspace(0, 1, 5), [0.0, 0.25, 0.5, 0.75, 1.0], "linspace")
t.eq(rg.count(10).take_list(3), [10, 11, 12], "count")
t.eq(rg.Range(3, 3).size(), 0, "vide")
t.eq(len(rg.Range(0, 7, 2)), 4, "__len__")
xs := []
for x in rg.Range(2, 5):
    append(xs, x)
t.eq(xs, [2, 3, 4], "for sur Range")
t.raises(() => rg.Range(0, 5, 0), "IteratorError", "pas nul")
t.raises(() => rg.Range(0, 5).get(5), "IndexError", "get hors limites")
t.raises(() => rg.Range("a"), "TypeError", "borne non numérique")
t.eq(iterator.range(0, 6, 2).to_list(), [0, 2, 4], "iterator.range")

# erreurs propagées dans un for (plus de fin silencieuse)
func bad(x):
    if x == 3:
        raise("ValueError", "trois")
    return x
func loop_bad():
    for x in mi.map([1, 2, 3, 4], bad):
        pass
t.raises(loop_bad, "ValueError", "erreur propagée par for")
t.raises(() => iterator.iter(5), "IteratorError", "itérable invalide")

t.summary("iterator")

# ALEX STANDARD LIBRARY — iterator
#
# Itérateurs paresseux et composables. ALEX n'a pas de `yield` : un itérateur est un objet qui produit ses
# éléments à la demande (has_next / next), qu'on enchaîne en pipeline sans construire de listes
# intermédiaires, et qu'on peut parcourir avec `for`.
#
#   use iterator
#   r := iterator.iter([1, 2, 3, 4, 5, 6]).filter((x) => x % 2 == 0).map((x) => x * x).to_list()   # [4, 16, 36]
#   for p in iterator.iter("abc").enumerate(1):
#       print(p[0], p[1])
#   premiers := iterator.count(2).filter(est_premier).take(5).to_list()        # suite infinie, bornée par take
#   fib := iterator.successors([0, 1], (p) => [p[1], p[0] + p[1]]).map((p) => p[0]).take(8).to_list()
#   lignes := iterator.from_function(() => fichier.read_line())               # jusqu'à null
#   print(iterator.iter([3, 1, 2]).sorted().to_list())                        # [1, 2, 3]
#
# Organisation
#   iterator._base          protocole Iterator (has_next, next, peek) + consommateurs
#   iterator.map_iterator   map, star_map, flat_map, flatten, inspect, scan
#   iterator.filter         filter, reject, filter_map, take(_while), skip(_while), step_by, dedup, unique
#   iterator.enumerate      enumerate, indexed, positions
#   iterator.zip            zip, zip_longest, zip_with, chain, interleave, unzip
#   iterator.range          Range (progression réutilisable), count, linspace
#   iterator (ce module)    Iter : enveloppe fluide de tout cela + sources (iter, of, repeat, cycle...)
#
# Écrire son propre itérateur : étendre Iterator (from iterator._base use Iterator), appeler super.init(),
# redéfinir _fetch() : placer l'élément dans self._item et rendre true, ou rendre false à la fin.
#
# Attention : un itérateur se CONSOMME. Le parcourir deux fois ne rend les éléments qu'une fois ; utiliser
# to_list(), ou repartir d'une source réutilisable (liste, Range).
#
# Erreurs : StopIteration (next sur itérateur épuisé), IteratorError, TypeError.

from core use len, type
from collections use append
from builtins use sorted
from iterator._base use Iterator
use iterator._base as _b
use iterator.iterator_errors as _e
use iterator.map_iterator as _m
use iterator.filter as _f
use iterator.enumerate as _en
use iterator.zip as _z
use iterator.range as _r

# ---------------------------------------------------------------- adaptateurs internes

class _Chunks extends Iterator:
    func init(src, n):
        super.init()
        self._src = src
        self._n = n

    func _fetch():
        if not self._src.has_next():
            return false
        self._item = self._src.take_list(self._n)
        return true

class _Windows extends Iterator:
    func init(src, n):
        super.init()
        self._src = src
        self._n = n
        self._win = []

    func _fetch():
        if len(self._win) == 0:
            self._win = self._src.take_list(self._n)
            if len(self._win) < self._n:
                return false
        else:
            if not self._src.has_next():
                return false
            self._win = self._win[1:] + [self._src.next()]
        self._item = self._win[:]
        return true

class _Cycle extends Iterator:
    func init(src, times):
        super.init()
        self._src = src
        self._saved = []
        self._replay = false
        self._k = 0
        self._times = times
        self._round = 1

    func _fetch():
        if self._times != null and self._times < 1:
            return false
        if not self._replay:
            if self._src.has_next():
                v := self._src.next()
                append(self._saved, v)
                self._item = v
                return true
            self._replay = true
            self._k = 0
            self._round = 2
            if self._times != null and self._round > self._times:
                return false
        if len(self._saved) == 0:
            return false
        if self._k >= len(self._saved):
            self._k = 0
            self._round += 1
            if self._times != null and self._round > self._times:
                return false
        self._item = self._saved[self._k]
        self._k += 1
        return true

class _Repeat extends Iterator:
    func init(value, times):
        super.init()
        self._v = value
        self._left = times

    func _fetch():
        if self._left != null:
            if self._left <= 0:
                return false
            self._left -= 1
        self._item = self._v
        return true

class _Successors extends Iterator:
    func init(first, f):
        super.init()
        self._next = first
        self._f = f
        self._started = false
        self._has = true

    func _fetch():
        if not self._has:
            return false
        if self._started:
            self._next = self._f(self._next)
        self._started = true
        if type(self._next) == "null":
            self._has = false
            return false
        self._item = self._next
        return true

# step(état) -> [valeur, nouvel état] ou null (fin).
class _Unfold extends Iterator:
    func init(seed, step):
        super.init()
        self._state = seed
        self._step = step

    func _fetch():
        r := self._step(self._state)
        if type(r) == "null":
            return false
        self._item = r[0]
        self._state = r[1]
        return true

# ---------------------------------------------------------------- enveloppe fluide

class Iter extends Iterator:
    func init(source):
        super.init()
        self._src = _b.from_iterable(source, "iterator.iter")

    func _fetch():
        if not self._src.has_next():
            return false
        self._item = self._src.next()
        return true

    func map(f):
        return Iter(_m.MapIterator(self, f))

    func star_map(f):
        return Iter(_m.StarMapIterator(self, f))

    func flat_map(f):
        return Iter(_m.FlatMapIterator(self, f))

    func flatten():
        return Iter(_m.FlattenIterator(self))

    func inspect(f):
        return Iter(_m.InspectIterator(self, f))

    func scan(f, init):
        return Iter(_m.ScanIterator(self, f, init))

    func filter(pred=null):
        return Iter(_f.FilterIterator(self, pred))

    func reject(pred):
        return Iter(_f.RejectIterator(self, pred))

    func filter_map(f):
        return Iter(_f.FilterMapIterator(self, f))

    func take(n):
        return Iter(_f.TakeIterator(self, n))

    func skip(n):
        return Iter(_f.SkipIterator(self, n))

    func take_while(pred):
        return Iter(_f.TakeWhileIterator(self, pred))

    func skip_while(pred):
        return Iter(_f.SkipWhileIterator(self, pred))

    func step_by(step):
        return Iter(_f.StepIterator(self, step))

    func dedup(key=null):
        return Iter(_f.DedupIterator(self, key))

    func unique(key=null):
        return Iter(_f.UniqueIterator(self, key))

    func enumerate(start=0):
        return Iter(_en.Enumerate(self, start))

    func zip(*others):
        return Iter(_z.Zip([self, *others]))

    func zip_with(other, f):
        return Iter(_z.ZipWith([self, other], f))

    func chain(*others):
        return Iter(_z.Chain([self, *others]))

    func interleave(other):
        return Iter(_z.Interleave([self, other]))

    # Paquets de n éléments (le dernier peut être plus court).
    func chunks(n):
        _e.need_positive("Iter.chunks", n, "la taille")
        return Iter(_Chunks(self, n))

    # Fenêtres glissantes de n éléments.
    func windows(n):
        _e.need_positive("Iter.windows", n, "la taille")
        return Iter(_Windows(self, n))

    # Répète la séquence (times null : sans fin).
    func cycle(times=null):
        return Iter(_Cycle(self, times))

    # Paires d'éléments consécutifs [a, b].
    func pairwise():
        return self.windows(2)

    # Matérialise et trie (consommation complète).
    func sorted(key=null, reverse=false):
        return Iter(sorted(self.to_list(), key, reverse))

    func reversed():
        return Iter(self.to_list()[::-1])

    func __str__():
        return "<Iter>"

# ---------------------------------------------------------------- sources

func iter(source):
    if isinstance(source, Iter):
        return source
    return Iter(source)

func of(*items):
    return Iter(items)

func empty():
    return Iter([])

func once(value):
    return Iter([value])

# value, value, ... (times fois, ou sans fin).
func repeat(value, times=null):
    return Iter(_Repeat(value, times))

# start, start + step, ... sans fin.
func count(start=0, step=1):
    return Iter(_r.count(start, step))

func range(start, stop=null, step=1):
    return Iter(_r.Range(start, stop, step).iter())

# first, f(first), f(f(first))... jusqu'à ce que f rende null.
func successors(first, f):
    _e.need_fn("iterator.successors", f)
    return Iter(_Successors(first, f))

# Appelle f() jusqu'à sentinel (null par défaut).
func from_function(f, sentinel=null):
    return Iter(_b.FunctionIterator(f, sentinel))

# step(état) -> [valeur, état suivant], ou null pour finir.
func unfold(seed, step):
    _e.need_fn("iterator.unfold", step)
    return Iter(_Unfold(seed, step))

func chain(*sources):
    return Iter(_z.Chain(sources))

func zip(*sources):
    return Iter(_z.Zip(sources))

func enumerate(source, start=0):
    return Iter(_en.Enumerate(source, start))

func cycle(source, times=null):
    return Iter(_Cycle(_b.from_iterable(source, "iterator.cycle"), times))

func is_iterator(v):
    return isinstance(v, Iterator)

# Liste de tout itérable (liste copiée, Iterator consommé...).
func to_list(source):
    return _b.from_iterable(source, "iterator.to_list").to_list()

# ALEX STANDARD LIBRARY — iterator.zip
#
# Combinaisons d'itérables, paresseuses :
#   Zip(sources)                 [a0, b0], [a1, b1]... ; s'arrête au plus court
#   ZipLongest(sources, fill)    va jusqu'au plus long, complète avec fill
#   ZipWith(sources, f)          f(a, b, ...) au lieu d'une liste
#   Chain(sources)               un itérable après l'autre
#   Interleave(sources)          a0, b0, a1, b1... (s'arrête quand tous sont épuisés)
#   unzip(paires)                [[a0, a1...], [b0, b1...]]
#
#   use iterator.zip as z
#   print(z.zip([1, 2, 3], "ab").to_list())                 # [[1, a], [2, b]]
#   print(z.zip_longest([1], [7, 8], 0).to_list())          # [[1, 7], [0, 8]]
#   print(z.zip_with([1, 2], [10, 20], (a, b) => a + b).to_list())   # [11, 22]
#   print(z.chain([1], [2, 3]).to_list())                   # [1, 2, 3]
#   print(z.unzip([[1, "a"], [2, "b"]]))                    # [[1, 2], [a, b]]
#
# Erreurs : IteratorError (aucune source, itérable non reconnu), TypeError.

from core use len, type
from collections use append
from iterator._base use Iterator
use iterator._base as _b
use iterator.iterator_errors as _e

func _sources(fn, sources):
    if len(sources) == 0:
        _e.invalid(fn, "au moins une source attendue")
    return [_b.from_iterable(s, fn) for s in sources]

class Zip extends Iterator:
    func init(sources):
        super.init()
        self._its = _sources("Zip", sources)

    func _fetch():
        for it in self._its:
            if not it.has_next():
                return false
        self._item = [it.next() for it in self._its]
        return true

class ZipLongest extends Iterator:
    func init(sources, fill=null):
        super.init()
        self._its = _sources("ZipLongest", sources)
        self._fill = fill

    func _fetch():
        any_left := false
        for it in self._its:
            if it.has_next():
                any_left = true
        if not any_left:
            return false
        row := []
        for it in self._its:
            if it.has_next():
                append(row, it.next())
            else:
                append(row, self._fill)
        self._item = row
        return true

class ZipWith extends Zip:
    func init(sources, f):
        super.init(sources)
        _e.need_fn("ZipWith", f)
        self._f = f

    func _fetch():
        for it in self._its:
            if not it.has_next():
                return false
        args := [it.next() for it in self._its]
        self._item = self._f(*args)
        return true

class Chain extends Iterator:
    func init(sources):
        super.init()
        self._its = [_b.from_iterable(s, "Chain") for s in sources]
        self._k = 0

    func _fetch():
        while self._k < len(self._its):
            it := self._its[self._k]
            if it.has_next():
                self._item = it.next()
                return true
            self._k += 1
        return false

class Interleave extends Iterator:
    func init(sources):
        super.init()
        self._its = _sources("Interleave", sources)
        self._k = 0

    func _fetch():
        tries := 0
        n := len(self._its)
        while tries < n:
            it := self._its[self._k]
            self._k = (self._k + 1) % n
            if it.has_next():
                self._item = it.next()
                return true
            tries += 1
        return false

func zip(*sources):
    return Zip(sources)

func zip_longest(a, b, fill=null):
    return ZipLongest([a, b], fill)

func zip_with(a, b, f):
    return ZipWith([a, b], f)

func chain(*sources):
    return Chain(sources)

func interleave(*sources):
    return Interleave(sources)

# Inverse de zip : liste de lignes -> liste de colonnes.
func unzip(rows):
    it := _b.from_iterable(rows, "unzip")
    cols := []
    first := true
    while it.has_next():
        row := it.next()
        if first:
            for v in row:
                append(cols, [])
            first = false
        i := 0
        for v in row:
            if i < len(cols):
                append(cols[i], v)
            i += 1
    return cols

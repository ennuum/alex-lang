# ALEX STANDARD LIBRARY — iterator.map_iterator
#
# Transformations paresseuses : chaque élément n'est calculé qu'au moment où il est demandé.
#
#   MapIterator(source, f)        f(x)
#   StarMapIterator(source, f)    f(*x) : chaque élément est une liste/un tuple d'arguments
#   FlatMapIterator(source, f)    aplatit les itérables rendus par f(x)
#   FlattenIterator(source)       aplatit un niveau
#   InspectIterator(source, f)    appelle f(x) pour son effet, rend x inchangé (journalisation, débogage)
#   ScanIterator(source, f, init) accumulations successives (comme functional.scan, mais paresseux)
#
#   use iterator.map_iterator as mi
#   carres := mi.MapIterator([1, 2, 3], (x) => x * x)
#   print(carres.to_list())                                   # [1, 4, 9]
#   print(mi.StarMapIterator([[1, 2], [3, 4]], (a, b) => a + b).to_list())   # [3, 7]
#   print(mi.FlatMapIterator([1, 2], (x) => [x, x * 10]).to_list())           # [1, 10, 2, 20]
#   print(mi.ScanIterator([1, 2, 3], (a, x) => a + x, 0).to_list())          # [1, 3, 6]
#
# Erreurs : TypeError (fonction attendue), IteratorError (itérable non reconnu).

from core use type
from iterator._base use Iterator
use iterator._base as _b
use iterator.iterator_errors as _e

class MapIterator extends Iterator:
    func init(source, f):
        super.init()
        _e.need_fn("MapIterator", f)
        self._src = _b.from_iterable(source, "MapIterator")
        self._f = f

    func _fetch():
        if not self._src.has_next():
            return false
        self._item = self._f(self._src.next())
        return true

class StarMapIterator extends Iterator:
    func init(source, f):
        super.init()
        _e.need_fn("StarMapIterator", f)
        self._src = _b.from_iterable(source, "StarMapIterator")
        self._f = f

    func _fetch():
        if not self._src.has_next():
            return false
        args := self._src.next()
        self._item = self._f(*args)
        return true

class FlatMapIterator extends Iterator:
    func init(source, f=null):
        super.init()
        if f != null:
            _e.need_fn("FlatMapIterator", f)
        self._src = _b.from_iterable(source, "FlatMapIterator")
        self._f = f
        self._inner = null

    func _fetch():
        while true:
            if self._inner != null and self._inner.has_next():
                self._item = self._inner.next()
                return true
            if not self._src.has_next():
                return false
            v := self._src.next()
            if self._f != null:
                v = self._f(v)
            self._inner = _b.from_iterable(v, "FlatMapIterator")

class FlattenIterator extends FlatMapIterator:
    func init(source):
        super.init(source, null)

class InspectIterator extends Iterator:
    func init(source, f):
        super.init()
        _e.need_fn("InspectIterator", f)
        self._src = _b.from_iterable(source, "InspectIterator")
        self._f = f

    func _fetch():
        if not self._src.has_next():
            return false
        v := self._src.next()
        self._f(v)
        self._item = v
        return true

class ScanIterator extends Iterator:
    func init(source, f, init):
        super.init()
        _e.need_fn("ScanIterator", f)
        self._src = _b.from_iterable(source, "ScanIterator")
        self._f = f
        self._acc = init

    func _fetch():
        if not self._src.has_next():
            return false
        self._acc = self._f(self._acc, self._src.next())
        self._item = self._acc
        return true

func map(source, f):
    return MapIterator(source, f)

func star_map(source, f):
    return StarMapIterator(source, f)

func flat_map(source, f):
    return FlatMapIterator(source, f)

func flatten(source):
    return FlattenIterator(source)

func inspect(source, f):
    return InspectIterator(source, f)

func scan(source, f, init):
    return ScanIterator(source, f, init)

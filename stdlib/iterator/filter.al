# ALEX STANDARD LIBRARY — iterator.filter
#
# Sélections paresseuses :
#   FilterIterator(source, pred)      garde les x tels que pred(x)  (pred null : valeurs vraies)
#   RejectIterator(source, pred)      écarte les x tels que pred(x)
#   FilterMapIterator(source, f)      f(x) ; garde les résultats non null
#   TakeWhileIterator / SkipWhileIterator
#   TakeIterator(source, n) / SkipIterator(source, n)
#   StepIterator(source, step)        un élément sur step
#   DedupIterator(source, key)        retire les répétitions CONSÉCUTIVES
#   UniqueIterator(source, key)       retire tout doublon (mémorise les clés vues, valeurs hachables)
#
#   use iterator.filter as flt
#   pairs := flt.FilterIterator([1, 2, 3, 4], (x) => x % 2 == 0).to_list()     # [2, 4]
#   print(flt.TakeWhileIterator([1, 2, 5, 1], (x) => x < 3).to_list())       # [1, 2]
#   print(flt.DedupIterator([1, 1, 2, 1]).to_list())                         # [1, 2, 1]
#   print(flt.UniqueIterator([1, 1, 2, 1]).to_list())                        # [1, 2]
#
# Erreurs : TypeError, IteratorError (n négatif, pas nul).

from core use type
from iterator._base use Iterator
use iterator._base as _b
use iterator.iterator_errors as _e

class FilterIterator extends Iterator:
    func init(source, pred=null):
        super.init()
        if pred != null:
            _e.need_fn("FilterIterator", pred, "le prédicat")
        self._src = _b.from_iterable(source, "FilterIterator")
        self._p = pred

    func _keep(v):
        if self._p == null:
            if v:
                return true
            return false
        return self._p(v)

    func _fetch():
        while self._src.has_next():
            v := self._src.next()
            if self._keep(v):
                self._item = v
                return true
        return false

class RejectIterator extends FilterIterator:
    func init(source, pred):
        super.init(source, pred)

    func _keep(v):
        return not self._p(v)

class FilterMapIterator extends Iterator:
    func init(source, f):
        super.init()
        _e.need_fn("FilterMapIterator", f)
        self._src = _b.from_iterable(source, "FilterMapIterator")
        self._f = f

    func _fetch():
        while self._src.has_next():
            v := self._f(self._src.next())
            if type(v) != "null":
                self._item = v
                return true
        return false

class TakeWhileIterator extends Iterator:
    func init(source, pred):
        super.init()
        _e.need_fn("TakeWhileIterator", pred, "le prédicat")
        self._src = _b.from_iterable(source, "TakeWhileIterator")
        self._p = pred
        self._stop = false

    func _fetch():
        if self._stop or not self._src.has_next():
            return false
        v := self._src.next()
        if not self._p(v):
            self._stop = true
            return false
        self._item = v
        return true

class SkipWhileIterator extends Iterator:
    func init(source, pred):
        super.init()
        _e.need_fn("SkipWhileIterator", pred, "le prédicat")
        self._src = _b.from_iterable(source, "SkipWhileIterator")
        self._p = pred
        self._skipping = true

    func _fetch():
        while self._src.has_next():
            v := self._src.next()
            if self._skipping and self._p(v):
                continue
            self._skipping = false
            self._item = v
            return true
        return false

class TakeIterator extends Iterator:
    func init(source, n):
        super.init()
        _e.need_non_negative("TakeIterator", n, "n")
        self._src = _b.from_iterable(source, "TakeIterator")
        self._left = n

    func _fetch():
        if self._left <= 0 or not self._src.has_next():
            return false
        self._left -= 1
        self._item = self._src.next()
        return true

class SkipIterator extends Iterator:
    func init(source, n):
        super.init()
        _e.need_non_negative("SkipIterator", n, "n")
        self._src = _b.from_iterable(source, "SkipIterator")
        self._skip = n

    func _fetch():
        while self._skip > 0 and self._src.has_next():
            self._src.next()
            self._skip -= 1
        if not self._src.has_next():
            return false
        self._item = self._src.next()
        return true

# Premier élément, puis un sur step.
class StepIterator extends Iterator:
    func init(source, step):
        super.init()
        _e.need_positive("StepIterator", step, "le pas")
        self._src = _b.from_iterable(source, "StepIterator")
        self._step = step
        self._first = true

    func _fetch():
        if not self._first:
            k := 1
            while k < self._step and self._src.has_next():
                self._src.next()
                k += 1
        self._first = false
        if not self._src.has_next():
            return false
        self._item = self._src.next()
        return true

class DedupIterator extends Iterator:
    func init(source, key=null):
        super.init()
        self._src = _b.from_iterable(source, "DedupIterator")
        self._key = key
        self._has_prev = false
        self._prev = null

    func _fetch():
        while self._src.has_next():
            v := self._src.next()
            k := v
            if self._key != null:
                k = self._key(v)
            if self._has_prev and k == self._prev:
                continue
            self._has_prev = true
            self._prev = k
            self._item = v
            return true
        return false

class UniqueIterator extends Iterator:
    func init(source, key=null):
        super.init()
        self._src = _b.from_iterable(source, "UniqueIterator")
        self._key = key
        self._seen = {}

    func _fetch():
        while self._src.has_next():
            v := self._src.next()
            k := v
            if self._key != null:
                k = self._key(v)
            if k in self._seen:
                continue
            self._seen[k] = true
            self._item = v
            return true
        return false

func filter(source, pred=null):
    return FilterIterator(source, pred)

func reject(source, pred):
    return RejectIterator(source, pred)

func filter_map(source, f):
    return FilterMapIterator(source, f)

func take_while(source, pred):
    return TakeWhileIterator(source, pred)

func skip_while(source, pred):
    return SkipWhileIterator(source, pred)

func take(source, n):
    return TakeIterator(source, n)

func skip(source, n):
    return SkipIterator(source, n)

func step_by(source, step):
    return StepIterator(source, step)

func dedup(source, key=null):
    return DedupIterator(source, key)

func unique(source, key=null):
    return UniqueIterator(source, key)

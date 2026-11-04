# ALEX STANDARD LIBRARY — iterator.enumerate
#
# Enumerate : associe à chaque élément sa position, paresseusement : rend des paires [position, élément].
#
#   use iterator.enumerate as en
#   for p in en.Enumerate(["a", "b"], 1):
#       print(p[0], p[1])                 # 1 a, puis 2 b
#   print(en.indexed("xy").to_list())     # [[0, x], [1, y]]
#   print(en.positions([5, 2, 5], (x) => x == 5))   # [0, 2]
#
# Erreurs : TypeError (départ non entier), IteratorError.

from core use type
from collections use append
from iterator._base use Iterator
use iterator._base as _b
use iterator.iterator_errors as _e

class Enumerate extends Iterator:
    func init(source, start=0, step=1):
        super.init()
        _e.need_int("Enumerate", start, "le départ")
        _e.need_int("Enumerate", step, "le pas")
        self._src = _b.from_iterable(source, "Enumerate")
        self._i = start
        self._step = step

    func _fetch():
        if not self._src.has_next():
            return false
        self._item = [self._i, self._src.next()]
        self._i += self._step
        return true

func enumerate(source, start=0):
    return Enumerate(source, start)

func indexed(source):
    return Enumerate(source, 0)

# Positions (à partir de 0) des éléments vérifiant pred, en liste.
func positions(source, pred):
    out := []
    e := Enumerate(source)
    while e.has_next():
        p := e.next()
        if pred(p[1]):
            append(out, p[0])
    return out

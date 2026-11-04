# ALEX STANDARD LIBRARY — iterator.range
#
# Progressions arithmétiques PARESSEUSES (aucune liste construite) : entiers ou flottants, pas positif ou
# négatif ; count() donne une progression sans fin. La forme `a..b` d'ALEX n'existe que dans un `for` ; Range est une valeur
# que l'on peut passer, interroger (len, contains, get) et réutiliser (iter() rend un nouvel itérateur).
#
#   use iterator.range as rg
#   r := rg.Range(0, 10, 3)
#   print(r.to_list(), r.size(), r.contains(6), r.get(-1))   # [0, 3, 6, 9] 4 true 9
#   for x in rg.Range(5, 0, -2):
#       print(x)                                              # 5 3 1
#   print(rg.Range(0, 1, 0.25).to_list())                     # [0, 0.25, 0.5, 0.75]
#   print(rg.linspace(0, 1, 5))                               # [0.0, 0.25, 0.5, 0.75, 1.0]
#   c := rg.count(10)                                         # 10, 11, 12... (infini)
#   print(c.take_list(3))                                     # [10, 11, 12]
#
# Erreurs : IteratorError (pas nul), TypeError (bornes non numériques), IndexError (get hors limites).

from core use len, type, to_int
from collections use append
from iterator._base use Iterator
use iterator.iterator_errors as _e

func _num(fn, v, label):
    t := type(v)
    if t != "int" and t != "float":
        raise("TypeError", fn + " : " + label + " doit être un nombre (obtenu '" + t + "')")

class RangeIterator extends Iterator:
    func init(start, stop, step):
        super.init()
        self._start = start
        self._stop = stop
        self._step = step
        self._k = 0

    func _fetch():
        v := self._start + self._k * self._step
        if self._stop != null:
            if self._step > 0 and v >= self._stop:
                return false
            if self._step < 0 and v <= self._stop:
                return false
        self._item = v
        self._k += 1
        return true

class Range:
    # Range(stop) : 0..stop ; Range(start, stop[, step]). Progression sans fin : count().
    func init(start, stop=null, step=1):
        if stop == null:
            stop = start
            start = 0
        _num("Range", start, "le départ")
        _num("Range", stop, "la fin")
        _num("Range", step, "le pas")
        if step == 0:
            _e.invalid("Range", "pas nul")
        self.start = start
        self.stop = stop
        self.step = step

    func size():
        span := self.stop - self.start
        if (self.step > 0 and span <= 0) or (self.step < 0 and span >= 0):
            return 0
        return _ceil(span / self.step)

    func is_empty():
        return self.size() == 0

    func get(i):
        _e.need_int("Range.get", i, "la position")
        n := self.size()
        j := i
        if j < 0:
            j = n + j
        if j < 0 or j >= n:
            raise("IndexError", "Range.get : position " + str(i) + " hors limites (taille " + str(n) + ")")
        return self.start + j * self.step

    func first():
        return self.get(0)

    func last():
        return self.get(-1)

    func contains(v):
        t := type(v)
        if t != "int" and t != "float":
            return false
        if self.step > 0:
            if v < self.start or v >= self.stop:
                return false
        else:
            if v > self.start or v <= self.stop:
                return false
        q := (v - self.start) / self.step
        return q == _floor(q)

    # Position de v dans la progression, -1 si absent.
    func index_of(v):
        if not self.contains(v):
            return -1
        return _floor((v - self.start) / self.step)

    func reversed():
        n := self.size()
        if n == 0:
            return Range(self.start, self.start, -self.step)
        return Range(self.get(-1), self.start - self.step, -self.step)

    func iter():
        return RangeIterator(self.start, self.stop, self.step)

    func to_list():
        return self.iter().to_list()

    func sum():
        n := self.size()
        if n == 0:
            return 0
        return n * (self.start + self.get(-1)) / 2

    func __len__():
        return self.size()

    func __contains__(v):
        return self.contains(v)

    func __getitem__(i):
        return self.get(i)

    func __eq__(other):
        if not isinstance(other, Range):
            return false
        return self.start == other.start and self.stop == other.stop and self.step == other.step

    func __str__():
        if self.step == 1:
            return "Range(" + str(self.start) + ", " + str(self.stop) + ")"
        return "Range(" + str(self.start) + ", " + str(self.stop) + ", " + str(self.step) + ")"

func _floor(x):
    f := to_int(x)
    if f > x:
        f -= 1
    return f

func _ceil(x):
    f := to_int(x)
    if f < x:
        f += 1
    return f

func range(start, stop=null, step=1):
    return Range(start, stop, step)

# start, start+step, ... sans fin.
func count(start=0, step=1):
    return RangeIterator(start, null, step)

# n valeurs régulièrement espacées de start à stop (inclus).
func linspace(start, stop, n):
    _e.need_positive("linspace", n, "n")
    if n == 1:
        return [start * 1.0]
    out := []
    step := (stop - start) / (n - 1.0)
    i := 0
    while i < n:
        append(out, start + i * step)
        i += 1
    out[n - 1] = stop * 1.0
    return out

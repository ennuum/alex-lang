# ALEX STANDARD LIBRARY — collections.deque
#
# Deque : file à double entrée sur tampon circulaire. Ajout et retrait aux deux bouts en O(1) amorti, accès
# par position en O(1). Bornée si max_len est donné : un ajout dans une deque pleine ÉJECTE l'élément du bout
# opposé (comme collections.deque de Python), ce qui en fait un historique glissant.
#
#   use collections.deque as dq
#   d := dq.Deque([1, 2, 3])
#   d.push_front(0)
#   d.push_back(4)                     # 0 1 2 3 4
#   d.rotate(2)                        # 3 4 0 1 2
#   print(d.pop_front(), d.pop_back()) # 3 2
#   h := dq.Deque(null, 3)             # les 3 derniers seulement
#   for x in [1, 2, 3, 4, 5]:
#       h.push_back(x)
#   print(h.to_list())                 # [3, 4, 5]
#
# Erreurs : EmptyCollectionError, IndexError, TypeError, ArgumentError.

from core use len, type
from collections use append
from collections.list use Collection, Sequence
use collections.list as _list
use collections.collection_errors as _e
use collections._util as _u

class Deque implements Collection, Sequence:
    func init(items=null, max_len=null):
        _e.check_capacity("Deque", max_len)
        self.max_len = max_len
        self._buf = [null] * 8
        self._head = 0
        self._n = 0
        for x in _u.to_list(items, "Deque"):
            self.push_back(x)

    func size():
        return self._n

    func is_empty():
        return self._n == 0

    func is_full():
        return self.max_len != null and self._n >= self.max_len

    func _cap():
        return len(self._buf)

    func _grow():
        old := self._buf
        cap := len(old)
        nb := [null] * (cap * 2)
        i := 0
        while i < self._n:
            nb[i] = old[(self._head + i) % cap]
            i += 1
        self._buf = nb
        self._head = 0

    func _phys(i):
        return (self._head + i) % len(self._buf)

    func push_back(value):
        if self.max_len != null and self._n >= self.max_len:
            self.pop_front()
        if self._n == len(self._buf):
            self._grow()
        self._buf[self._phys(self._n)] = value
        self._n += 1

    func push_front(value):
        if self.max_len != null and self._n >= self.max_len:
            self.pop_back()
        if self._n == len(self._buf):
            self._grow()
        self._head = (self._head - 1 + len(self._buf)) % len(self._buf)
        self._buf[self._head] = value
        self._n += 1

    func pop_front():
        if self._n == 0:
            _e.empty("Deque.pop_front")
        v := self._buf[self._head]
        self._buf[self._head] = null
        self._head = (self._head + 1) % len(self._buf)
        self._n -= 1
        return v

    func pop_back():
        if self._n == 0:
            _e.empty("Deque.pop_back")
        p := self._phys(self._n - 1)
        v := self._buf[p]
        self._buf[p] = null
        self._n -= 1
        return v

    func peek_front():
        if self._n == 0:
            _e.empty("Deque.peek_front")
        return self._buf[self._head]

    func peek_back():
        if self._n == 0:
            _e.empty("Deque.peek_back")
        return self._buf[self._phys(self._n - 1)]

    func get(index):
        return self._buf[self._phys(_e.check_index("Deque.get", index, self._n))]

    func set(index, value):
        p := self._phys(_e.check_index("Deque.set", index, self._n))
        old := self._buf[p]
        self._buf[p] = value
        return old

    func extend_back(items):
        for x in _u.to_list(items, "Deque.extend_back"):
            self.push_back(x)

    # Ajoute chaque élément devant (l'ordre final est donc inversé, comme extendleft).
    func extend_front(items):
        for x in _u.to_list(items, "Deque.extend_front"):
            self.push_front(x)

    # n > 0 : décale vers la droite (le dernier passe devant) ; n < 0 : vers la gauche.
    func rotate(n=1):
        _e.need_int("Deque.rotate", n, "le décalage")
        if self._n <= 1:
            return
        k := n % self._n
        i := 0
        while i < k:
            self.push_front(self.pop_back())
            i += 1

    func contains(value):
        return self.index_of(value) >= 0

    func index_of(value):
        i := 0
        while i < self._n:
            if self._buf[self._phys(i)] == value:
                return i
            i += 1
        return -1

    func count(value):
        c := 0
        i := 0
        while i < self._n:
            if self._buf[self._phys(i)] == value:
                c += 1
            i += 1
        return c

    func remove(value):
        i := self.index_of(value)
        if i < 0:
            return false
        items := self.to_list()
        self.clear()
        k := 0
        while k < len(items):
            if k != i:
                self.push_back(items[k])
            k += 1
        return true

    func reverse():
        items := self.to_list()
        self.clear()
        i := len(items) - 1
        while i >= 0:
            self.push_back(items[i])
            i -= 1

    func clear():
        self._buf = [null] * 8
        self._head = 0
        self._n = 0

    func to_list():
        out := []
        i := 0
        while i < self._n:
            append(out, self._buf[self._phys(i)])
            i += 1
        return out

    func copy():
        return Deque(self.to_list(), self.max_len)

    func hash_code():
        return _u.hash_of(self.to_list())

    func __eq__(other):
        return isinstance(other, Deque) and _list.equals(self, other)

    func __len__():
        return self._n

    func __contains__(value):
        return self.contains(value)

    func __getitem__(i):
        if type(i) == "int" and (i >= self._n or i < -self._n):
            raise("IndexError", "Deque : position " + str(i) + " hors limites")
        return self.get(i)

    func __setitem__(i, value):
        self.set(i, value)

    func __str__():
        return "Deque[" + _u.join_items(self.to_list()) + "]"

func of(*items):
    return Deque(items)

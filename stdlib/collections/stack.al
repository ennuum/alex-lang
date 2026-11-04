# ALEX STANDARD LIBRARY — collections.stack
#
# Stack : pile LIFO (dernier entré, premier sorti), éventuellement bornée.
#
#   use collections.stack as st
#   s := st.Stack()
#   s.push(1)
#   s.push(2)
#   print(s.peek(), s.pop(), s.size())       # 2 2 1
#   print(s.try_pop(), s.try_pop())           # 1 null
#   b := st.Stack(null, 2)                    # capacité 2 : un troisième push lève CapacityError
#
# Le parcours (for, to_list) va du SOMMET vers le fond.
# Erreurs : EmptyCollectionError (pop, peek), CapacityError (push dans une pile pleine).

from core use len, type
from collections use append, pop
from collections.list use Collection
use collections.list as _list
use collections.collection_errors as _e
use collections._util as _u

class Stack implements Collection:
    # items : du fond vers le sommet (le dernier est au sommet).
    func init(items=null, capacity=null):
        _e.check_capacity("Stack", capacity)
        self.capacity = capacity
        self._items = []
        for x in _u.to_list(items, "Stack"):
            self.push(x)

    func size():
        return len(self._items)

    func is_empty():
        return len(self._items) == 0

    func is_full():
        return self.capacity != null and len(self._items) >= self.capacity

    func push(value):
        if self.is_full():
            _e.full("Stack.push", self.capacity)
        append(self._items, value)
        return self

    func push_all(items):
        for x in _u.to_list(items, "Stack.push_all"):
            self.push(x)

    func pop():
        if len(self._items) == 0:
            _e.empty("Stack.pop")
        return pop(self._items)

    # pop sans erreur : default si la pile est vide.
    func try_pop(default=null):
        if len(self._items) == 0:
            return default
        return pop(self._items)

    func peek():
        if len(self._items) == 0:
            _e.empty("Stack.peek")
        return self._items[len(self._items) - 1]

    func try_peek(default=null):
        if len(self._items) == 0:
            return default
        return self._items[len(self._items) - 1]

    # Élément à la profondeur depth (0 = sommet).
    func peek_at(depth):
        n := len(self._items)
        _e.check_index("Stack.peek_at", depth, n)
        return self._items[n - 1 - depth]

    # Dépile n éléments (sommet d'abord).
    func pop_many(n):
        _e.need_int("Stack.pop_many", n, "le nombre")
        if n > len(self._items):
            raise("EmptyCollectionError", "Stack.pop_many : " + str(n) + " demandés, " + str(len(self._items)) + " présents")
        out := []
        i := 0
        while i < n:
            append(out, pop(self._items))
            i += 1
        return out

    # Distance du sommet à la première occurrence de value (0 = sommet) ; -1 si absente.
    func search(value):
        i := len(self._items) - 1
        while i >= 0:
            if self._items[i] == value:
                return len(self._items) - 1 - i
            i -= 1
        return -1

    func contains(value):
        return self.search(value) >= 0

    func clear():
        self._items = []

    # Du sommet vers le fond.
    func to_list():
        return self._items[::-1]

    func copy():
        s := Stack(null, self.capacity)
        s._items = self._items[:]
        return s

    func __eq__(other):
        return isinstance(other, Stack) and _list.equals(self, other)

    func __len__():
        return len(self._items)

    func __contains__(value):
        return self.contains(value)

    func __getitem__(i):
        return self.peek_at(i)

    func __str__():
        return "Stack[" + _u.join_items(self.to_list()) + "]"

func of(*items):
    return Stack(items)

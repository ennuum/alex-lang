# ALEX STANDARD LIBRARY — collections.tree_set
#
# TreeSet : ensemble TRIÉ sans doublon, sur collections.tree_map (AVL). Ajout, retrait, recherche en
# O(log n) ; parcours dans l'ordre ; requêtes d'ordre (floor, ceiling, intervalle).
#
#   use collections.tree_set as ts
#   s := ts.TreeSet([5, 1, 3, 1])
#   print(s.to_list())                       # [1, 3, 5]
#   print(s.first(), s.last(), s.ceiling(2)) # 1 5 3
#   print(s.range(2, 6))                     # [3, 5]
#   print(s.union(ts.TreeSet([2])).to_list())   # [1, 2, 3, 5]
#
# Erreurs : EmptyCollectionError, TypeError (éléments non comparables).

from core use len, type
from collections use append
from collections.list use Collection
use collections.tree_map as _tm
use collections.collection_errors as _e
use collections._util as _u

class TreeSet implements Collection:
    func init(items=null, cmp=null):
        self._cmp = cmp
        self._m = _tm.TreeMap(null, cmp)
        if items != null:
            for x in _u.to_list(items, "TreeSet"):
                self._m.put(x, true)

    func size():
        return self._m.size()

    func is_empty():
        return self._m.size() == 0

    func add(value):
        if self._m.contains_key(value):
            return false
        self._m.put(value, true)
        return true

    func add_all(items):
        n := 0
        for x in _u.to_list(items, "TreeSet.add_all"):
            if self.add(x):
                n += 1
        return n

    func remove(value):
        if not self._m.contains_key(value):
            return false
        self._m.remove(value)
        return true

    func contains(value):
        return self._m.contains_key(value)

    func first():
        return self._m.first_key()

    func last():
        return self._m.last_key()

    func pop_first():
        return self._m.pop_first()[0]

    func pop_last():
        return self._m.pop_last()[0]

    func floor(value):
        return self._m.floor_key(value)

    func ceiling(value):
        return self._m.ceiling_key(value)

    func lower(value):
        return self._m.lower_key(value)

    func higher(value):
        return self._m.higher_key(value)

    # Éléments dans [lo, hi) (inclusive=true : [lo, hi]).
    func range(lo=null, hi=null, inclusive=false):
        return [p[0] for p in self._m.range(lo, hi, inclusive)]

    func head_set(hi):
        return TreeSet(self.range(null, hi), self._cmp)

    func tail_set(lo):
        return TreeSet(self.range(lo, null), self._cmp)

    func union(other):
        out := TreeSet(self.to_list(), self._cmp)
        out.add_all(_u.to_list(other, "TreeSet.union"))
        return out

    func intersection(other):
        o := _as_tree(other, self._cmp)
        return TreeSet([x for x in self.to_list() if o.contains(x)], self._cmp)

    func difference(other):
        o := _as_tree(other, self._cmp)
        return TreeSet([x for x in self.to_list() if not o.contains(x)], self._cmp)

    func is_subset(other):
        o := _as_tree(other, self._cmp)
        for x in self.to_list():
            if not o.contains(x):
                return false
        return true

    func clear():
        self._m.clear()

    func to_list():
        return self._m.keys()

    func to_list_descending():
        return self._m.keys()[::-1]

    func copy():
        return TreeSet(self.to_list(), self._cmp)

    func __eq__(other):
        return isinstance(other, TreeSet) and self.size() == other.size() and self.is_subset(other)

    func __len__():
        return self._m.size()

    func __contains__(value):
        return self._m.contains_key(value)

    func __getitem__(i):
        return self._m.keys()[i]

    func __str__():
        return "TreeSet{" + _u.join_items(self.to_list()) + "}"

func _as_tree(other, cmp):
    if isinstance(other, TreeSet):
        return other
    return TreeSet(other, cmp)

func of(*items):
    return TreeSet(items)

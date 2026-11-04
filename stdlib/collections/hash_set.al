# ALEX STANDARD LIBRARY — collections.hash_set
#
# HashSet : ensemble sans doublon, ordonné par insertion, sur collections.hash_map. Accepte toute valeur
# hachable ET les instances (hash_code() / __eq__, sinon identité) — ce que le set natif refuse.
#
#   use collections.hash_set as hs
#   a := hs.HashSet([1, 2, 3])
#   b := hs.HashSet([3, 4])
#   print(a.union(b).to_list())          # [1, 2, 3, 4]
#   print(a.intersection(b).to_list())   # [3]
#   print(a.difference(b).to_list())     # [1, 2]
#   print(a.is_subset(hs.HashSet([1, 2, 3, 9])))   # true
#   a.add(2)                             # false : déjà présent
#   for x in a:
#       print(x)
#
# Erreurs : KeyError (remove_or_raise), EmptyCollectionError (pop), TypeError.

from core use len, type
from collections use append
from collections.list use Collection
use collections.hash_map as _hm
use collections.collection_errors as _e
use collections._util as _u

class HashSet implements Collection:
    func init(items=null):
        self._m = _hm.HashMap()
        if items != null:
            for x in _u.to_list(items, "HashSet"):
                self._m.put(x, true)

    func size():
        return self._m.size()

    func is_empty():
        return self._m.size() == 0

    # Ajoute ; false si déjà présent.
    func add(value):
        if self._m.contains_key(value):
            return false
        self._m.put(value, true)
        return true

    func add_all(items):
        n := 0
        for x in _u.to_list(items, "HashSet.add_all"):
            if self.add(x):
                n += 1
        return n

    # Retire ; false si absent.
    func remove(value):
        if not self._m.contains_key(value):
            return false
        self._m.remove(value)
        return true

    func remove_or_raise(value):
        if not self.remove(value):
            _e.missing_key("HashSet.remove", value)

    func discard(value):
        self.remove(value)

    # Retire et renvoie le plus ancien élément.
    func pop():
        if self._m.size() == 0:
            _e.empty("HashSet.pop")
        v := self._m.keys()[0]
        self._m.remove(v)
        return v

    func contains(value):
        return self._m.contains_key(value)

    func clear():
        self._m.clear()

    func union(other):
        out := self.copy()
        for x in _items_of(other):
            out.add(x)
        return out

    func intersection(other):
        o := _as_set(other)
        out := HashSet()
        for x in self._m.keys():
            if o.contains(x):
                out.add(x)
        return out

    func difference(other):
        o := _as_set(other)
        out := HashSet()
        for x in self._m.keys():
            if not o.contains(x):
                out.add(x)
        return out

    func symmetric_difference(other):
        o := _as_set(other)
        out := self.difference(o)
        for x in o.to_list():
            if not self.contains(x):
                out.add(x)
        return out

    func is_subset(other):
        o := _as_set(other)
        for x in self._m.keys():
            if not o.contains(x):
                return false
        return true

    func is_superset(other):
        return _as_set(other).is_subset(self)

    func is_disjoint(other):
        o := _as_set(other)
        for x in self._m.keys():
            if o.contains(x):
                return false
        return true

    func retain_if(pred):
        for x in self._m.keys():
            if not pred(x):
                self._m.remove(x)

    func filter(pred):
        return HashSet([x for x in self._m.keys() if pred(x)])

    func map(f):
        return HashSet([f(x) for x in self._m.keys()])

    func to_list():
        return self._m.keys()

    func copy():
        return HashSet(self._m.keys())

    func hash_code():
        # Indépendant de l'ordre : somme des hachages.
        h := 0
        for x in self._m.keys():
            h = (h + _u.hash_of(x)) & 0x3fffffffffffffff
        return h

    func __eq__(other):
        return isinstance(other, HashSet) and other.size() == self.size() and self.is_subset(other)

    func __len__():
        return self._m.size()

    func __contains__(value):
        return self._m.contains_key(value)

    func __getitem__(i):
        return self._m.keys()[i]

    func __or__(other):
        return self.union(other)

    func __and__(other):
        return self.intersection(other)

    func __sub__(other):
        return self.difference(other)

    func __xor__(other):
        return self.symmetric_difference(other)

    func __str__():
        return "HashSet{" + _u.join_items(self._m.keys()) + "}"

func _items_of(other):
    if isinstance(other, HashSet):
        return other.to_list()
    return _u.to_list(other, "HashSet")

func _as_set(other):
    if isinstance(other, HashSet):
        return other
    return HashSet(other)

func of(*items):
    return HashSet(items)

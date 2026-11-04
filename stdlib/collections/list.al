# ALEX STANDARD LIBRARY — collections.list
#
# Contrats communs des collections et liste immuable.
#
#   Collection   size is_empty contains clear to_list   (toutes les collections de collections.*)
#   Sequence     get set size to_list                   (collections indexées : ArrayList, Vector, LinkedList, Deque)
#   ImmutableList  liste figée : lecture, recherche, tranches ; toute modification lève TypeError.
#
#   use collections.list as lst
#   l := lst.ImmutableList([3, 1, 2])
#   print(l.get(0), l.size(), l.sorted().to_list())     # 3  3  [1, 2, 3]
#   print(lst.is_collection(l), lst.equals(l, [3, 1, 2])) # true true
#   for x in l:
#       print(x)
#
# Les collections exposent aussi __len__ (len(c)), __contains__ (x in c) et __str__ (print(c)). Les
# collections indexées exposent __getitem__ : `for x in c` les parcourt dans l'ordre.
#
# Erreurs : IndexError, TypeError (modification d'une liste immuable), EmptyCollectionError.

from core use len, type
from collections use append
from builtins use sorted
use collections.collection_errors as _e
use collections._util as _u

interface Collection:
    func size()
    func is_empty()
    func contains(value)
    func clear()
    func to_list()

interface Sequence:
    func get(index)
    func set(index, value)
    func size()
    func to_list()

class ImmutableList implements Collection, Sequence:
    func init(items=null):
        self._items = _u.to_list(items, "ImmutableList")

    func size():
        return len(self._items)

    func is_empty():
        return len(self._items) == 0

    func contains(value):
        for x in self._items:
            if x == value:
                return true
        return false

    func get(index):
        return self._items[_e.check_index("ImmutableList.get", index, len(self._items))]

    func first():
        if len(self._items) == 0:
            _e.empty("ImmutableList.first")
        return self._items[0]

    func last():
        if len(self._items) == 0:
            _e.empty("ImmutableList.last")
        return self._items[len(self._items) - 1]

    func index_of(value):
        i := 0
        while i < len(self._items):
            if self._items[i] == value:
                return i
            i += 1
        return -1

    func slice(start, stop=null):
        if stop == null:
            stop = len(self._items)
        return ImmutableList(self._items[start:stop])

    func sorted(key=null, reverse=false):
        return ImmutableList(sorted(self._items, key, reverse))

    # Nouvelle liste avec value ajoutée (l'originale ne change pas).
    func with_appended(value):
        out := self._items[:]
        append(out, value)
        return ImmutableList(out)

    # Nouvelle liste où la position index vaut value.
    func with_set(index, value):
        j := _e.check_index("ImmutableList.with_set", index, len(self._items))
        out := self._items[:]
        out[j] = value
        return ImmutableList(out)

    func set(index, value):
        raise("TypeError", "ImmutableList.set : liste immuable (utiliser with_set)")

    func clear():
        raise("TypeError", "ImmutableList.clear : liste immuable")

    func to_list():
        return self._items[:]

    func hash_code():
        return _u.hash_of(self._items)

    func __eq__(other):
        t := type(other)
        if t != "instance" and t != "list" and t != "tuple":
            return false
        return equals(self, other)

    func __len__():
        return len(self._items)

    func __contains__(value):
        return self.contains(value)

    func __getitem__(i):
        return self._items[i]

    func __str__():
        return "ImmutableList[" + _u.join_items(self._items) + "]"

# Vrai si v est une collection de collections.* (implémente Collection).
func is_collection(v):
    return isinstance(v, Collection)

func is_sequence(v):
    return isinstance(v, Sequence)

# Nombre d'éléments d'une collection, d'une liste, d'un tuple, d'un dict ou d'une str.
func size_of(c):
    if isinstance(c, Collection):
        return c.size()
    return len(c)

# Même contenu, dans le même ordre (collections, listes, tuples, str...).
func equals(a, b):
    la := _u.to_list(a, "list.equals")
    lb := _u.to_list(b, "list.equals")
    if len(la) != len(lb):
        return false
    i := 0
    while i < len(la):
        if not (la[i] == lb[i]):
            return false
        i += 1
    return true

func of(*items):
    return ImmutableList(items)

func to_str(c, name="List"):
    return name + "[" + _u.join_items(_u.to_list(c, "list.to_str")) + "]"

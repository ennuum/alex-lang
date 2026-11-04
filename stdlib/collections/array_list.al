# ALEX STANDARD LIBRARY — collections.array_list
#
# ArrayList : liste dynamique indexée (accès O(1), ajout en fin O(1) amorti, insertion/suppression O(n)),
# avec compteur de modifications pour détecter les modifications pendant un parcours par itérateur.
#
#   use collections.array_list as al
#   l := al.ArrayList([5, 3])
#   l.add(8)
#   l.add_at(0, 1)                    # [1, 5, 3, 8]
#   l.remove(3)                       # true
#   l.sort()                          # [1, 5, 8]
#   print(l.get(-1), l.index_of(5))   # 8 1
#   it := l.iterator()
#   while it.has_next():
#       print(it.next())
#
# Erreurs : IndexError, EmptyCollectionError, ConcurrentModificationError, TypeError.

from core use len, type
from collections use append, insert, pop
from builtins use sorted
use collections.list as _list
from collections.list use Collection, Sequence
use collections.collection_errors as _e
use collections._util as _u

class ArrayListIterator:
    func init(owner):
        self._owner = owner
        self._i = 0
        self._last = -1
        self._mods = owner._mods

    func _check():
        if self._mods != self._owner._mods:
            _e.modified("ArrayList.iterator")

    func has_next():
        return self._i < len(self._owner._items)

    func next():
        self._check()
        if self._i >= len(self._owner._items):
            raise("IndexError", "ArrayList.iterator : plus d'élément")
        self._last = self._i
        self._i += 1
        return self._owner._items[self._last]

    # Retire le dernier élément rendu par next() (sans invalider l'itérateur).
    func remove():
        self._check()
        if self._last < 0:
            raise("InvalidStateError", "ArrayList.iterator.remove : next() n'a pas été appelé")
        pop(self._owner._items, self._last)
        self._owner._mods += 1
        self._mods = self._owner._mods
        self._i = self._last
        self._last = -1

class ArrayList implements Collection, Sequence:
    func init(items=null):
        self._items = _u.to_list(items, "ArrayList")
        self._mods = 0

    func size():
        return len(self._items)

    func is_empty():
        return len(self._items) == 0

    func add(value):
        append(self._items, value)
        self._mods += 1
        return self

    func add_all(items):
        for x in _u.to_list(items, "ArrayList.add_all"):
            append(self._items, x)
        self._mods += 1
        return self

    func add_at(index, value):
        j := _e.check_insert_index("ArrayList.add_at", index, len(self._items))
        insert(self._items, j, value)
        self._mods += 1
        return self

    func get(index):
        return self._items[_e.check_index("ArrayList.get", index, len(self._items))]

    # Remplace ; renvoie l'ancienne valeur.
    func set(index, value):
        j := _e.check_index("ArrayList.set", index, len(self._items))
        old := self._items[j]
        self._items[j] = value
        return old

    func first():
        if len(self._items) == 0:
            _e.empty("ArrayList.first")
        return self._items[0]

    func last():
        if len(self._items) == 0:
            _e.empty("ArrayList.last")
        return self._items[len(self._items) - 1]

    func remove_at(index):
        j := _e.check_index("ArrayList.remove_at", index, len(self._items))
        self._mods += 1
        return pop(self._items, j)

    # Retire la première occurrence de value ; false si absente.
    func remove(value):
        i := self.index_of(value)
        if i < 0:
            return false
        pop(self._items, i)
        self._mods += 1
        return true

    # Retire les éléments vérifiant pred ; renvoie leur nombre.
    func remove_if(pred):
        _e.need_callable("ArrayList.remove_if", pred)
        kept := []
        for x in self._items:
            if not pred(x):
                append(kept, x)
        n := len(self._items) - len(kept)
        if n > 0:
            self._items = kept
            self._mods += 1
        return n

    func pop_last():
        if len(self._items) == 0:
            _e.empty("ArrayList.pop_last")
        self._mods += 1
        return pop(self._items)

    func contains(value):
        return self.index_of(value) >= 0

    func index_of(value):
        i := 0
        n := len(self._items)
        while i < n:
            if self._items[i] == value:
                return i
            i += 1
        return -1

    func last_index_of(value):
        i := len(self._items) - 1
        while i >= 0:
            if self._items[i] == value:
                return i
            i -= 1
        return -1

    func clear():
        self._items = []
        self._mods += 1

    func sub_list(start, stop=null):
        if stop == null:
            stop = len(self._items)
        if start < 0 or stop > len(self._items) or start > stop:
            raise("IndexError", "ArrayList.sub_list : bornes " + str(start) + ".." + str(stop) + " invalides (taille " + str(len(self._items)) + ")")
        return ArrayList(self._items[start:stop])

    # Tri stable en place.
    func sort(key=null, reverse=false):
        self._items = sorted(self._items, key, reverse)
        self._mods += 1
        return self

    func reverse():
        self._items = self._items[::-1]
        self._mods += 1
        return self

    func map(f):
        return ArrayList([f(x) for x in self._items])

    func filter(pred):
        return ArrayList([x for x in self._items if pred(x)])

    func for_each(f):
        for x in self._items:
            f(x)

    func swap(i, j):
        a := _e.check_index("ArrayList.swap", i, len(self._items))
        b := _e.check_index("ArrayList.swap", j, len(self._items))
        tmp := self._items[a]
        self._items[a] = self._items[b]
        self._items[b] = tmp

    func iterator():
        return ArrayListIterator(self)

    func copy():
        return ArrayList(self._items)

    func to_list():
        return self._items[:]

    func hash_code():
        return _u.hash_of(self._items)

    func __eq__(other):
        return isinstance(other, ArrayList) and _list.equals(self, other)

    func __len__():
        return len(self._items)

    func __contains__(value):
        return self.contains(value)

    func __getitem__(i):
        return self._items[i]

    func __setitem__(i, value):
        self.set(i, value)

    func __str__():
        return "ArrayList[" + _u.join_items(self._items) + "]"

func of(*items):
    return ArrayList(items)

func with_size(n, fill=null):
    _e.need_int("array_list.with_size", n, "la taille")
    return ArrayList([fill] * n)

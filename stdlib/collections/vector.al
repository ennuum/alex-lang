# ALEX STANDARD LIBRARY — collections.vector
#
# Vector : tableau dynamique à CAPACITÉ explicite, dans l'esprit de std::vector (C++) : la mémoire réservée
# (capacity) est distincte de la taille (size) ; reserve() pré-alloue, shrink_to_fit() rend l'excédent.
# Les cases réservées non utilisées valent null et ne sont jamais visibles.
#
#   use collections.vector as vec
#   v := vec.Vector()
#   v.reserve(100)
#   v.push_back(1)
#   v.push_back(2)
#   v.insert(1, 9)                     # [1, 9, 2]
#   print(v.front(), v.back(), v.at(1), v.size(), v.capacity())   # 1 2 9 3 100
#   v.resize(5, 0)                     # [1, 9, 2, 0, 0]
#   v.erase(0, 2)                      # [2, 0, 0]
#
# Croissance : la capacité double quand elle est atteinte (ajout en fin O(1) amorti).
# Erreurs : IndexError (at, erase, insert), EmptyCollectionError (front, back, pop_back), TypeError, ArgumentError.

from core use len, type
from collections use append
from builtins use sorted
from collections.list use Collection, Sequence
use collections.list as _list
use collections.collection_errors as _e
use collections._util as _u

class Vector implements Collection, Sequence:
    func init(items=null, capacity=0):
        data := _u.to_list(items, "Vector")
        _e.need_int("Vector", capacity, "la capacité")
        self._n = len(data)
        cap := capacity
        if cap < self._n:
            cap = self._n
        if cap > self._n:
            data = data + [null] * (cap - self._n)
        self._data = data

    func size():
        return self._n

    func is_empty():
        return self._n == 0

    func capacity():
        return len(self._data)

    func _grow(min_cap):
        cap := len(self._data)
        if cap >= min_cap:
            return
        new_cap := cap * 2
        if new_cap < 4:
            new_cap = 4
        if new_cap < min_cap:
            new_cap = min_cap
        self._data = self._data + [null] * (new_cap - cap)

    # Réserve au moins n cases (ne réduit jamais).
    func reserve(n):
        _e.need_int("Vector.reserve", n, "la capacité")
        if n < 0:
            raise("ArgumentError", "Vector.reserve : capacité négative")
        self._grow(n)

    # Ramène la capacité à la taille.
    func shrink_to_fit():
        self._data = self._data[:self._n]

    func push_back(value):
        if self._n == len(self._data):
            self._grow(self._n + 1)
        self._data[self._n] = value
        self._n += 1

    func pop_back():
        if self._n == 0:
            _e.empty("Vector.pop_back")
        self._n -= 1
        v := self._data[self._n]
        self._data[self._n] = null
        return v

    func front():
        if self._n == 0:
            _e.empty("Vector.front")
        return self._data[0]

    func back():
        if self._n == 0:
            _e.empty("Vector.back")
        return self._data[self._n - 1]

    # Accès borné (position négative : depuis la fin).
    func at(index):
        return self._data[_e.check_index("Vector.at", index, self._n)]

    func get(index):
        return self.at(index)

    func set(index, value):
        j := _e.check_index("Vector.set", index, self._n)
        old := self._data[j]
        self._data[j] = value
        return old

    # Insère value avant la position index (index = size : en fin).
    func insert(index, value):
        j := _e.check_insert_index("Vector.insert", index, self._n)
        if self._n == len(self._data):
            self._grow(self._n + 1)
        k := self._n
        while k > j:
            self._data[k] = self._data[k - 1]
            k -= 1
        self._data[j] = value
        self._n += 1

    # Retire les positions start..stop-1 (stop absent : la seule position start).
    func erase(start, stop=null):
        a := _e.check_index("Vector.erase", start, self._n)
        b := a + 1
        if stop != null:
            _e.need_int("Vector.erase", stop, "la fin")
            b = stop
            if b < a or b > self._n:
                raise("IndexError", "Vector.erase : fin " + str(stop) + " hors limites")
        count := b - a
        k := a
        while k + count < self._n:
            self._data[k] = self._data[k + count]
            k += 1
        while k < self._n:
            self._data[k] = null
            k += 1
        self._n -= count
        return count

    # Change la taille : tronque, ou complète avec fill.
    func resize(n, fill=null):
        _e.need_int("Vector.resize", n, "la taille")
        if n < 0:
            raise("ArgumentError", "Vector.resize : taille négative")
        if n > len(self._data):
            self._grow(n)
        k := self._n
        while k < n:
            self._data[k] = fill
            k += 1
        k = n
        while k < self._n:
            self._data[k] = null
            k += 1
        self._n = n

    # Remplace tout le contenu par count copies de value.
    func assign(count, value):
        self._data = [value] * count
        self._n = count

    func contains(value):
        return self.find(value) >= 0

    func find(value):
        i := 0
        while i < self._n:
            if self._data[i] == value:
                return i
            i += 1
        return -1

    func clear():
        k := 0
        while k < self._n:
            self._data[k] = null
            k += 1
        self._n = 0

    func swap(other):
        d := self._data
        n := self._n
        self._data = other._data
        self._n = other._n
        other._data = d
        other._n = n

    func sort(key=null, reverse=false):
        s := sorted(self._data[:self._n], key, reverse)
        i := 0
        while i < self._n:
            self._data[i] = s[i]
            i += 1

    # Copie des éléments utilisés (équivalent de data()).
    func data():
        return self._data[:self._n]

    func to_list():
        return self._data[:self._n]

    func copy():
        return Vector(self.to_list(), len(self._data))

    func hash_code():
        return _u.hash_of(self.to_list())

    func __eq__(other):
        return isinstance(other, Vector) and _list.equals(self, other)

    func __len__():
        return self._n

    func __contains__(value):
        return self.contains(value)

    func __getitem__(i):
        if type(i) == "int" and (i >= self._n or i < -self._n):
            raise("IndexError", "Vector : position " + str(i) + " hors limites")
        return self.at(i)

    func __setitem__(i, value):
        self.set(i, value)

    func __str__():
        return "Vector[" + _u.join_items(self.to_list()) + "]"

func of(*items):
    return Vector(items)

func filled(n, value=null):
    v := Vector()
    v.assign(n, value)
    return v

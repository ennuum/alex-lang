# ALEX STANDARD LIBRARY — collections.tree_map
#
# TreeMap : table associative TRIÉE par clé, sur arbre AVL équilibré. Insertion, recherche et suppression en
# O(log n) ; parcours dans l'ordre des clés ; requêtes d'ordre (plus petite clé >= x, intervalle...).
# L'ordre est celui de < sur les clés, ou d'un comparateur cmp(a, b) -> int négatif / 0 / positif.
#
#   use collections.tree_map as tm
#   m := tm.TreeMap()
#   m.put(30, "c")
#   m.put(10, "a")
#   m[20] = "b"
#   print(m.keys())                         # [10, 20, 30]
#   print(m.first_key(), m.last_key())      # 10 30
#   print(m.floor_key(25), m.ceiling_key(25))   # 20 30
#   print(m.range(10, 30))                  # [[10, a], [20, b]]   (borne haute exclue)
#   m.pop_first()                           # [10, a]
#   par_nom := tm.TreeMap(null, (a, b) => len(a) - len(b))     # ordre par longueur
#
# Erreurs : KeyError, EmptyCollectionError, TypeError (clés non comparables).

from core use len, type
from collections use append
from collections.list use Collection
use collections.collection_errors as _e
use collections._util as _u

class _TNode:
    func init(key, value):
        self.key = key
        self.value = value
        self.left = null
        self.right = null
        self.height = 1

func _h(n):
    if n == null:
        return 0
    return n.height

func _fix(n):
    a := _h(n.left)
    b := _h(n.right)
    if a > b:
        n.height = a + 1
    else:
        n.height = b + 1

func _rot_right(y):
    x := y.left
    y.left = x.right
    x.right = y
    _fix(y)
    _fix(x)
    return x

func _rot_left(x):
    y := x.right
    x.right = y.left
    y.left = x
    _fix(x)
    _fix(y)
    return y

func _balance(n):
    _fix(n)
    bf := _h(n.left) - _h(n.right)
    if bf > 1:
        if _h(n.left.left) < _h(n.left.right):
            n.left = _rot_left(n.left)
        return _rot_right(n)
    if bf < -1:
        if _h(n.right.right) < _h(n.right.left):
            n.right = _rot_right(n.right)
        return _rot_left(n)
    return n

class TreeMap implements Collection:
    func init(entries=null, cmp=null):
        _e.need_callable("TreeMap", cmp, "cmp")
        self._root = null
        self._n = 0
        self._cmp = cmp
        self._added = false
        if entries != null:
            self.put_all(entries)

    func _c(a, b):
        try:
            return _u.compare(a, b, self._cmp)
        catch e:
            if e.type == "TypeError":
                raise("TypeError", "TreeMap : clés non comparables (" + _u.show(a) + ", " + _u.show(b) + ")")
            raise(e)

    func size():
        return self._n

    func is_empty():
        return self._n == 0

    func _insert(n, key, value, out):
        if n == null:
            self._added = true
            return _TNode(key, value)
        c := self._c(key, n.key)
        if c < 0:
            n.left = self._insert(n.left, key, value, out)
        elif c > 0:
            n.right = self._insert(n.right, key, value, out)
        else:
            out[0] = n.value
            n.value = value
            return n
        return _balance(n)

    # Associe ; renvoie l'ancienne valeur (null si nouvelle clé).
    func put(key, value):
        out := [null]
        self._added = false
        self._root = self._insert(self._root, key, value, out)
        if self._added:
            self._n += 1
        return out[0]

    func put_all(entries):
        if type(entries) == "dict":
            for k in entries:
                self.put(k, entries[k])
        elif isinstance(entries, TreeMap):
            for p in entries.items():
                self.put(p[0], p[1])
        else:
            for p in _u.to_list(entries, "TreeMap.put_all"):
                self.put(p[0], p[1])

    func _node(key):
        n := self._root
        while n != null:
            c := self._c(key, n.key)
            if c == 0:
                return n
            if c < 0:
                n = n.left
            else:
                n = n.right
        return null

    func get(key, default=null):
        n := self._node(key)
        if n == null:
            return default
        return n.value

    func get_or_raise(key):
        n := self._node(key)
        if n == null:
            _e.missing_key("TreeMap.get", key)
        return n.value

    func contains_key(key):
        return self._node(key) != null

    func contains(key):
        return self._node(key) != null

    func _min_node(n):
        while n.left != null:
            n = n.left
        return n

    func _delete(n, key, out):
        if n == null:
            return null
        c := self._c(key, n.key)
        if c < 0:
            n.left = self._delete(n.left, key, out)
        elif c > 0:
            n.right = self._delete(n.right, key, out)
        else:
            out[0] = true
            out[1] = n.value
            if n.left == null:
                return n.right
            if n.right == null:
                return n.left
            m := self._min_node(n.right)
            n.key = m.key
            n.value = m.value
            sub := [false, null]
            n.right = self._delete(n.right, m.key, sub)
        return _balance(n)

    # Retire ; renvoie la valeur (default si absente).
    func remove(key, default=null):
        out := [false, null]
        self._root = self._delete(self._root, key, out)
        if not out[0]:
            return default
        self._n -= 1
        return out[1]

    func first_key():
        if self._root == null:
            _e.empty("TreeMap.first_key")
        return self._min_node(self._root).key

    func last_key():
        if self._root == null:
            _e.empty("TreeMap.last_key")
        n := self._root
        while n.right != null:
            n = n.right
        return n.key

    func first_entry():
        k := self.first_key()
        return [k, self.get(k)]

    func last_entry():
        k := self.last_key()
        return [k, self.get(k)]

    func pop_first():
        e := self.first_entry()
        self.remove(e[0])
        return e

    func pop_last():
        e := self.last_entry()
        self.remove(e[0])
        return e

    # Plus grande clé <= key (null si aucune).
    func floor_key(key):
        n := self._root
        best := null
        found := false
        while n != null:
            c := self._c(key, n.key)
            if c == 0:
                return n.key
            if c < 0:
                n = n.left
            else:
                best = n.key
                found = true
                n = n.right
        if found:
            return best
        return null

    # Plus petite clé >= key.
    func ceiling_key(key):
        n := self._root
        best := null
        while n != null:
            c := self._c(key, n.key)
            if c == 0:
                return n.key
            if c > 0:
                n = n.right
            else:
                best = n.key
                n = n.left
        return best

    # Plus grande clé < key.
    func lower_key(key):
        n := self._root
        best := null
        while n != null:
            if self._c(n.key, key) < 0:
                best = n.key
                n = n.right
            else:
                n = n.left
        return best

    # Plus petite clé > key.
    func higher_key(key):
        n := self._root
        best := null
        while n != null:
            if self._c(n.key, key) > 0:
                best = n.key
                n = n.left
            else:
                n = n.right
        return best

    func _walk(n, out):
        # Parcours infixe itératif (pas de récursion profonde).
        stack := []
        cur := n
        while cur != null or len(stack) > 0:
            while cur != null:
                append(stack, cur)
                cur = cur.left
            cur = stack[len(stack) - 1]
            stack = stack[:len(stack) - 1]
            append(out, cur)
            cur = cur.right

    func _nodes():
        out := []
        self._walk(self._root, out)
        return out

    func keys():
        return [n.key for n in self._nodes()]

    func values():
        return [n.value for n in self._nodes()]

    func items():
        return [[n.key, n.value] for n in self._nodes()]

    # Paires de clés dans [lo, hi) (hi_inclusive=true : [lo, hi]) ; lo ou hi null : non borné.
    func range(lo=null, hi=null, hi_inclusive=false):
        out := []
        self._range(self._root, lo, hi, hi_inclusive, out)
        return out

    func _range(n, lo, hi, inc, out):
        if n == null:
            return
        go_left := lo == null or self._c(lo, n.key) < 0
        if go_left:
            self._range(n.left, lo, hi, inc, out)
        ok_lo := lo == null or self._c(n.key, lo) >= 0
        ok_hi := hi == null or self._c(n.key, hi) < 0 or (inc and self._c(n.key, hi) == 0)
        if ok_lo and ok_hi:
            append(out, [n.key, n.value])
        go_right := hi == null or self._c(n.key, hi) < 0
        if go_right:
            self._range(n.right, lo, hi, inc, out)

    # Sous-table des clés dans [lo, hi).
    func sub_map(lo, hi):
        return TreeMap(self.range(lo, hi), self._cmp)

    func head_map(hi):
        return TreeMap(self.range(null, hi), self._cmp)

    func tail_map(lo):
        return TreeMap(self.range(lo, null), self._cmp)

    func height():
        return _h(self._root)

    func clear():
        self._root = null
        self._n = 0

    func for_each(f):
        for n in self._nodes():
            f(n.key, n.value)

    func to_list():
        return self.items()

    func copy():
        return TreeMap(self.items(), self._cmp)

    func __eq__(other):
        if not isinstance(other, TreeMap) or other.size() != self._n:
            return false
        a := self.items()
        b := other.items()
        i := 0
        while i < len(a):
            if not (a[i][0] == b[i][0]) or not (a[i][1] == b[i][1]):
                return false
            i += 1
        return true

    func __len__():
        return self._n

    func __contains__(key):
        return self.contains_key(key)

    func __getitem__(key):
        return self.get_or_raise(key)

    func __setitem__(key, value):
        self.put(key, value)

    func __str__():
        out := "TreeMap{"
        first := true
        for p in self.items():
            if not first:
                out += ", "
            out += _u.show(p[0]) + ": " + _u.show(p[1])
            first = false
        return out + "}"

func of(*pairs):
    return TreeMap(pairs)

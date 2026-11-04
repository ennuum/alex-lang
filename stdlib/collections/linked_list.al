# ALEX STANDARD LIBRARY — collections.linked_list
#
# LinkedList : liste doublement chaînée. Ajout et retrait aux deux bouts en O(1), insertion/retrait au
# milieu en O(1) une fois le nœud atteint (curseur ListCursor). L'accès par position parcourt depuis le bout
# le plus proche ; un parcours séquentiel (for, get(i), get(i + 1)...) réutilise la dernière position visitée,
# donc `for x in liste` reste linéaire.
#
#   use collections.linked_list as ll
#   l := ll.LinkedList([2, 3])
#   l.add_first(1)
#   l.add_last(4)                        # 1 <-> 2 <-> 3 <-> 4
#   print(l.remove_first(), l.peek_last())   # 1 4
#   c := l.cursor()                       # sur le premier nœud
#   c.move_next()
#   c.insert_after(9)                     # 2 <-> 3 <-> 9 <-> 4
#   c.remove()                            # retire 3
#   l.reverse()
#
# Erreurs : EmptyCollectionError, IndexError, InvalidStateError (curseur hors liste).

from core use len, type
from collections use append
from collections.list use Collection, Sequence
use collections.list as _list
use collections.collection_errors as _e
use collections._util as _u

class ListNode:
    func init(value):
        self.value = value
        self.prev = null
        self.next = null
        self.owner = 0   # identité de la liste propriétaire (0 : aucune)

class LinkedList implements Collection, Sequence:
    func init(items=null):
        self._id = _u.new_id()
        self._head = null
        self._tail = null
        self._n = 0
        self._cache_node = null
        self._cache_index = -1
        for x in _u.to_list(items, "LinkedList"):
            self.add_last(x)

    func _touch():
        self._cache_node = null
        self._cache_index = -1

    func size():
        return self._n

    func is_empty():
        return self._n == 0

    func add_first(value):
        node := ListNode(value)
        node.owner = self._id
        node.next = self._head
        if self._head != null:
            self._head.prev = node
        self._head = node
        if self._tail == null:
            self._tail = node
        self._n += 1
        self._touch()
        return node

    func add_last(value):
        node := ListNode(value)
        node.owner = self._id
        node.prev = self._tail
        if self._tail != null:
            self._tail.next = node
        self._tail = node
        if self._head == null:
            self._head = node
        self._n += 1
        self._touch()
        return node

    func add(value):
        self.add_last(value)
        return self

    func push(value):
        self.add_first(value)

    func pop():
        return self.remove_first()

    func _unlink(node):
        if node.prev != null:
            node.prev.next = node.next
        else:
            self._head = node.next
        if node.next != null:
            node.next.prev = node.prev
        else:
            self._tail = node.prev
        node.prev = null
        node.next = null
        node.owner = 0
        self._n -= 1
        self._touch()
        return node.value

    func remove_first():
        if self._head == null:
            _e.empty("LinkedList.remove_first")
        return self._unlink(self._head)

    func remove_last():
        if self._tail == null:
            _e.empty("LinkedList.remove_last")
        return self._unlink(self._tail)

    func peek_first():
        if self._head == null:
            _e.empty("LinkedList.peek_first")
        return self._head.value

    func peek_last():
        if self._tail == null:
            _e.empty("LinkedList.peek_last")
        return self._tail.value

    func first_node():
        return self._head

    func last_node():
        return self._tail

    func _node_at(index):
        j := _e.check_index("LinkedList", index, self._n)
        # Parcours séquentiel : repartir du nœud mémorisé.
        if self._cache_node != null:
            if j == self._cache_index:
                return self._cache_node
            if j == self._cache_index + 1:
                self._cache_node = self._cache_node.next
                self._cache_index = j
                return self._cache_node
        node := null
        if j < self._n / 2:
            node = self._head
            k := 0
            while k < j:
                node = node.next
                k += 1
        else:
            node = self._tail
            k := self._n - 1
            while k > j:
                node = node.prev
                k -= 1
        self._cache_node = node
        self._cache_index = j
        return node

    func get(index):
        return self._node_at(index).value

    func set(index, value):
        node := self._node_at(index)
        old := node.value
        node.value = value
        return old

    func insert(index, value):
        j := _e.check_insert_index("LinkedList.insert", index, self._n)
        if j == 0:
            return self.add_first(value)
        if j == self._n:
            return self.add_last(value)
        return self.insert_before(self._node_at(j), value)

    func insert_before(node, value):
        self._own(node, "insert_before")
        if node.prev == null:
            return self.add_first(value)
        n := ListNode(value)
        n.owner = self._id
        n.prev = node.prev
        n.next = node
        node.prev.next = n
        node.prev = n
        self._n += 1
        self._touch()
        return n

    func insert_after(node, value):
        self._own(node, "insert_after")
        if node.next == null:
            return self.add_last(value)
        return self.insert_before(node.next, value)

    func _own(node, fn):
        if node == null or not isinstance(node, ListNode) or node.owner != self._id:
            raise("InvalidStateError", "LinkedList." + fn + " : nœud n'appartenant pas à cette liste")

    func remove_node(node):
        self._own(node, "remove_node")
        return self._unlink(node)

    func remove_at(index):
        return self._unlink(self._node_at(index))

    # Retire la première occurrence ; false si absente.
    func remove(value):
        node := self.find_node(value)
        if node == null:
            return false
        self._unlink(node)
        return true

    func find_node(value):
        node := self._head
        while node != null:
            if node.value == value:
                return node
            node = node.next
        return null

    func index_of(value):
        node := self._head
        i := 0
        while node != null:
            if node.value == value:
                return i
            node = node.next
            i += 1
        return -1

    func contains(value):
        return self.find_node(value) != null

    func clear():
        node := self._head
        while node != null:
            nxt := node.next
            node.prev = null
            node.next = null
            node.owner = 0
            node = nxt
        self._head = null
        self._tail = null
        self._n = 0
        self._touch()

    func reverse():
        node := self._head
        while node != null:
            nxt := node.next
            node.next = node.prev
            node.prev = nxt
            node = nxt
        tmp := self._head
        self._head = self._tail
        self._tail = tmp
        self._touch()
        return self

    # Déplace tous les éléments de other à la fin de cette liste (O(1)) ; other devient vide.
    func splice(other):
        if other._id == self._id or other._n == 0:
            return
        node := other._head
        while node != null:
            node.owner = self._id
            node = node.next
        if self._tail == null:
            self._head = other._head
        else:
            self._tail.next = other._head
            other._head.prev = self._tail
        self._tail = other._tail
        self._n += other._n
        other._head = null
        other._tail = null
        other._n = 0
        other._touch()
        self._touch()

    func cursor(at_end=false):
        if at_end:
            return ListCursor(self, self._tail)
        return ListCursor(self, self._head)

    func to_list():
        out := []
        node := self._head
        while node != null:
            append(out, node.value)
            node = node.next
        return out

    func to_list_reversed():
        out := []
        node := self._tail
        while node != null:
            append(out, node.value)
            node = node.prev
        return out

    func copy():
        return LinkedList(self.to_list())

    func hash_code():
        return _u.hash_of(self.to_list())

    func __eq__(other):
        return isinstance(other, LinkedList) and _list.equals(self, other)

    func __len__():
        return self._n

    func __contains__(value):
        return self.contains(value)

    func __getitem__(i):
        if type(i) == "int" and (i >= self._n or i < -self._n):
            raise("IndexError", "LinkedList : position " + str(i) + " hors limites")
        return self.get(i)

    func __str__():
        return "LinkedList[" + _u.join_items(self.to_list(), " <-> ") + "]"

# Curseur : position sur un nœud, déplaçable, qui insère et retire autour de lui en O(1).
class ListCursor:
    func init(owner, node):
        self.list = owner
        self.node = node

    func valid():
        return self.node != null and self.node.owner == self.list._id

    func _need(fn):
        if not self.valid():
            raise("InvalidStateError", "ListCursor." + fn + " : curseur hors de la liste")

    func value():
        self._need("value")
        return self.node.value

    func set(value):
        self._need("set")
        self.node.value = value

    func move_next():
        self._need("move_next")
        self.node = self.node.next
        return self.node != null

    func move_prev():
        self._need("move_prev")
        self.node = self.node.prev
        return self.node != null

    func insert_before(value):
        self._need("insert_before")
        self.list.insert_before(self.node, value)

    func insert_after(value):
        self._need("insert_after")
        self.list.insert_after(self.node, value)

    # Retire le nœud courant ; le curseur passe au suivant (ou au précédent en fin de liste).
    func remove():
        self._need("remove")
        nxt := self.node.next
        if nxt == null:
            nxt = self.node.prev
        v := self.list.remove_node(self.node)
        self.node = nxt
        return v

func of(*items):
    return LinkedList(items)

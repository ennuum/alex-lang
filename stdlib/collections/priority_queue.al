# ALEX STANDARD LIBRARY — collections.priority_queue
#
# PriorityQueue : file de priorité sur tas binaire. push / pop en O(log n), peek en O(1).
# Par défaut le PLUS PETIT sort en premier (tas min) ; max=true inverse. La priorité vient de l'élément
# lui-même, de key(élément) ou d'un comparateur cmp(a, b) -> int. À priorité égale, l'ordre d'arrivée est
# conservé (stable).
#
#   use collections.priority_queue as pq
#   q := pq.PriorityQueue()
#   q.push(5)
#   q.push(1)
#   q.push(3)
#   print(q.pop(), q.pop())                       # 1 3
#   t := pq.PriorityQueue(null, (t) => t["prio"], true)    # tâche la plus prioritaire d'abord
#   t.push({"nom": "a", "prio": 2})
#   q2 := pq.PriorityQueue()
#   q2.push_with_priority("urgent", 0)            # priorité séparée de la valeur
#   print(pq.n_smallest([5, 1, 4, 2], 2))         # [1, 2]
#
# Erreurs : EmptyCollectionError, TypeError.

from core use len, type
from collections use append, pop
from collections.list use Collection
use collections.collection_errors as _e
use collections._util as _u

class PriorityQueue implements Collection:
    func init(items=null, key=null, max=false, cmp=null):
        _e.need_callable("PriorityQueue", key, "key")
        _e.need_callable("PriorityQueue", cmp, "cmp")
        self._key = key
        self._max = max
        self._cmp = cmp
        self._heap = []     # entrées [priorité, numéro d'arrivée, valeur]
        self._seq = 0
        for x in _u.to_list(items, "PriorityQueue"):
            self.push(x)

    func _prio(value):
        if self._key != null:
            return self._key(value)
        return value

    # a passe avant b ?
    func _before(a, b):
        c := _u.compare(a[0], b[0], self._cmp)
        if self._max:
            c = -c
        if c != 0:
            return c < 0
        return a[1] < b[1]

    func _up(i):
        h := self._heap
        while i > 0:
            p := (i - 1) // 2
            if self._before(h[i], h[p]):
                tmp := h[i]
                h[i] = h[p]
                h[p] = tmp
                i = p
            else:
                break

    func _down(i):
        h := self._heap
        n := len(h)
        while true:
            l := 2 * i + 1
            r := l + 1
            best := i
            if l < n and self._before(h[l], h[best]):
                best = l
            if r < n and self._before(h[r], h[best]):
                best = r
            if best == i:
                break
            tmp := h[i]
            h[i] = h[best]
            h[best] = tmp
            i = best

    func size():
        return len(self._heap)

    func is_empty():
        return len(self._heap) == 0

    func push(value):
        self.push_with_priority(value, self._prio(value))

    func push_with_priority(value, priority):
        append(self._heap, [priority, self._seq, value])
        self._seq += 1
        self._up(len(self._heap) - 1)

    func pop():
        if len(self._heap) == 0:
            _e.empty("PriorityQueue.pop")
        return self._pop_entry()[2]

    func _pop_entry():
        h := self._heap
        top := h[0]
        last := pop(h)
        if len(h) > 0:
            h[0] = last
            self._down(0)
        return top

    # [valeur, priorité] du prochain élément, retiré.
    func pop_with_priority():
        if len(self._heap) == 0:
            _e.empty("PriorityQueue.pop_with_priority")
        e := self._pop_entry()
        return [e[2], e[0]]

    func try_pop(default=null):
        if len(self._heap) == 0:
            return default
        return self._pop_entry()[2]

    func peek():
        if len(self._heap) == 0:
            _e.empty("PriorityQueue.peek")
        return self._heap[0][2]

    func peek_priority():
        if len(self._heap) == 0:
            _e.empty("PriorityQueue.peek_priority")
        return self._heap[0][0]

    # Ajoute puis retire (plus efficace que push + pop).
    func push_pop(value):
        entry := [self._prio(value), self._seq, value]
        self._seq += 1
        if len(self._heap) == 0 or self._before(entry, self._heap[0]):
            return value
        top := self._heap[0]
        self._heap[0] = entry
        self._down(0)
        return top[2]

    # Retire le prochain puis ajoute value.
    func replace(value):
        if len(self._heap) == 0:
            _e.empty("PriorityQueue.replace")
        top := self._heap[0]
        self._heap[0] = [self._prio(value), self._seq, value]
        self._seq += 1
        self._down(0)
        return top[2]

    # Retire la première occurrence de value (O(n)) ; false si absente.
    func remove(value):
        i := 0
        h := self._heap
        while i < len(h):
            if h[i][2] == value:
                last := pop(h)
                if i < len(h):
                    h[i] = last
                    self._down(i)
                    self._up(i)
                return true
            i += 1
        return false

    # Change la priorité de value (première occurrence) ; false si absente.
    func update_priority(value, priority):
        if not self.remove(value):
            return false
        self.push_with_priority(value, priority)
        return true

    func contains(value):
        for e in self._heap:
            if e[2] == value:
                return true
        return false

    func clear():
        self._heap = []

    # Éléments dans l'ordre de sortie (la file n'est pas modifiée).
    func to_sorted_list():
        c := self.copy()
        out := []
        while c.size() > 0:
            append(out, c.pop())
        return out

    # Éléments dans l'ordre interne du tas (non trié).
    func to_list():
        return [e[2] for e in self._heap]

    func copy():
        q := PriorityQueue(null, self._key, self._max, self._cmp)
        q._heap = [e[:] for e in self._heap]
        q._seq = self._seq
        return q

    func merge(other):
        for e in other._heap:
            self.push_with_priority(e[2], e[0])

    func __len__():
        return len(self._heap)

    func __contains__(value):
        return self.contains(value)

    func __str__():
        return "PriorityQueue[" + _u.join_items(self.to_sorted_list()) + "]"

func n_smallest(items, n, key=null):
    q := PriorityQueue(items, key)
    out := []
    while len(out) < n and q.size() > 0:
        append(out, q.pop())
    return out

func n_largest(items, n, key=null):
    q := PriorityQueue(items, key, true)
    out := []
    while len(out) < n and q.size() > 0:
        append(out, q.pop())
    return out

# Fusionne des listes déjà triées en une liste triée (k-way merge).
func merge_sorted(lists, key=null):
    q := PriorityQueue(null, null, false)
    i := 0
    while i < len(lists):
        if len(lists[i]) > 0:
            v := lists[i][0]
            k := v
            if key != null:
                k = key(v)
            q.push_with_priority([i, 0], k)
        i += 1
    out := []
    while q.size() > 0:
        pos := q.pop()
        src := lists[pos[0]]
        append(out, src[pos[1]])
        nxt := pos[1] + 1
        if nxt < len(src):
            v := src[nxt]
            k := v
            if key != null:
                k = key(v)
            q.push_with_priority([pos[0], nxt], k)
    return out

# ALEX STANDARD LIBRARY — multimedia.pipeline.backpressure
#
# Files BORNÉES entre les nœuds d'un pipeline. Quand une file est pleine :
#   « block »        le producteur est mis en attente (le planificateur ne le fait plus avancer) — défaut ;
#   « drop_oldest »  l'élément le plus ancien est jeté (flux en direct : on garde le plus récent) ;
#   « drop_newest »  le nouvel élément est jeté ;
#   « error »        LimitError.
# Les fins de flux (eos) ne sont jamais jetées.
#
#   use multimedia.pipeline.backpressure as bp
#   q := bp.BoundedQueue(8, "drop_oldest")
#   q.push(trame)                    # true si accepté
#   x := q.pop()                     # null si vide
#   print(q.stats())                 # {"capacity": 8, "size": 3, "dropped": 2, "pushed": ..., "high_water": ...}
#
# Erreurs : FormatError (capacité, politique), LimitError (politique « error »).

from core use len, type
from collections use append
use multimedia.core.errors as merr

const POLICIES := ["block", "drop_oldest", "drop_newest", "error"]

func _is_eos(item):
    if item == null or type(item) != "instance":
        return false
    try:
        return item.eos
    catch e:
        return false

class BoundedQueue:
    func init(capacity=16, policy="block"):
        if type(capacity) != "int" or capacity <= 0:
            merr.fail(merr.FORMAT, "capacité de file invalide : " + str(capacity))
        if not (policy in POLICIES):
            merr.fail(merr.FORMAT, "politique de contre-pression inconnue : " + str(policy))
        self.capacity = capacity
        self.policy = policy
        self._items = []
        self._head = 0
        self.dropped = 0
        self.pushed = 0
        self.popped = 0
        self.high_water = 0
        self.closed = false

    func size():
        return len(self._items) - self._head

    func is_empty():
        return self.size() == 0

    func is_full():
        return self.size() >= self.capacity

    # Le producteur peut-il écrire sans perte ni attente ?
    func can_accept():
        return not self.is_full() or self.policy == "drop_oldest" or self.policy == "drop_newest"

    func _compact():
        if self._head > 64 and self._head * 2 > len(self._items):
            self._items = [self._items[k] for k in self._head..len(self._items)]
            self._head = 0

    func push(item):
        if self.is_full() and not _is_eos(item):
            if self.policy == "block":
                return false
            if self.policy == "error":
                merr.fail(merr.LIMIT, "file pleine (" + str(self.capacity) + " éléments)")
            if self.policy == "drop_newest":
                self.dropped += 1
                return false
            # drop_oldest : jette le plus ancien qui n'est pas une fin de flux
            k := self._head
            while k < len(self._items) and _is_eos(self._items[k]):
                k += 1
            if k < len(self._items):
                rest := [self._items[j] for j in self._head..len(self._items) if j != k]
                self._items = rest
                self._head = 0
                self.dropped += 1
        append(self._items, item)
        self.pushed += 1
        if self.size() > self.high_water:
            self.high_water = self.size()
        return true

    func peek():
        if self.is_empty():
            return null
        return self._items[self._head]

    func pop():
        if self.is_empty():
            return null
        x := self._items[self._head]
        self._items[self._head] = null
        self._head += 1
        self.popped += 1
        self._compact()
        return x

    func clear():
        n := self.size()
        self._items = []
        self._head = 0
        return n

    func stats():
        return {"capacity": self.capacity, "policy": self.policy, "size": self.size(), "dropped": self.dropped,
                "pushed": self.pushed, "popped": self.popped, "high_water": self.high_water}

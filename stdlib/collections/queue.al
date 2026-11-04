# ALEX STANDARD LIBRARY — collections.queue
#
# Queue : file FIFO (premier entré, premier sorti), éventuellement bornée, sur tampon circulaire.
# Deux styles d'API, comme java.util.Queue :
#   enqueue / dequeue / front   lèvent une erreur (CapacityError, EmptyCollectionError)
#   offer / poll / peek         rendent false / null
#
#   use collections.queue as q
#   f := q.Queue()
#   f.enqueue("a")
#   f.enqueue("b")
#   print(f.dequeue(), f.size())     # a 1
#   bornee := q.Queue(null, 2)
#   bornee.offer(1)
#   bornee.offer(2)
#   print(bornee.offer(3))           # false : pleine
#   print(q.Queue().poll())          # null
#
# Pour une file partagée entre fils ou tâches, voir ipc.channel, channel et thread.
# Erreurs : EmptyCollectionError, CapacityError.

from core use len, type
from collections use append
from collections.list use Collection
use collections.list as _list
use collections.deque as _dq
use collections.collection_errors as _e
use collections._util as _u

class Queue implements Collection:
    func init(items=null, capacity=null):
        _e.check_capacity("Queue", capacity)
        self.capacity = capacity
        self._d = _dq.Deque()
        for x in _u.to_list(items, "Queue"):
            self.enqueue(x)

    func size():
        return self._d.size()

    func is_empty():
        return self._d.size() == 0

    func is_full():
        return self.capacity != null and self._d.size() >= self.capacity

    func remaining():
        if self.capacity == null:
            return null
        return self.capacity - self._d.size()

    func enqueue(value):
        if self.is_full():
            _e.full("Queue.enqueue", self.capacity)
        self._d.push_back(value)
        return self

    func offer(value):
        if self.is_full():
            return false
        self._d.push_back(value)
        return true

    func dequeue():
        if self._d.size() == 0:
            _e.empty("Queue.dequeue")
        return self._d.pop_front()

    func poll(default=null):
        if self._d.size() == 0:
            return default
        return self._d.pop_front()

    func front():
        if self._d.size() == 0:
            _e.empty("Queue.front")
        return self._d.peek_front()

    func peek(default=null):
        if self._d.size() == 0:
            return default
        return self._d.peek_front()

    func back():
        if self._d.size() == 0:
            _e.empty("Queue.back")
        return self._d.peek_back()

    # Retire jusqu'à max éléments (tous si null) dans l'ordre d'arrivée.
    func drain(max=null):
        out := []
        while self._d.size() > 0 and (max == null or len(out) < max):
            append(out, self._d.pop_front())
        return out

    func contains(value):
        return self._d.contains(value)

    func clear():
        self._d.clear()

    func to_list():
        return self._d.to_list()

    func copy():
        return Queue(self.to_list(), self.capacity)

    func __eq__(other):
        return isinstance(other, Queue) and _list.equals(self, other)

    func __len__():
        return self._d.size()

    func __contains__(value):
        return self._d.contains(value)

    func __getitem__(i):
        return self._d.__getitem__(i)

    func __str__():
        return "Queue[" + _u.join_items(self.to_list()) + "]"

func of(*items):
    return Queue(items)

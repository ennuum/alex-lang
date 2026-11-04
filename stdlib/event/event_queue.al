# ALEX STANDARD LIBRARY — event.event_queue
#
# Files d'événements :
#   - EventQueue : dans un fil, entre tâches async — priorités (la plus haute sort d'abord, FIFO à priorité
#     égale), fusion (post_unique remplace un événement du même type encore en attente : redimensionnement,
#     rafraîchissement), retrait sans attendre (poll), attente async (get), capacité bornée.
#   - ThreadEventQueue : entre FILS (thread) ; les événements y passent sous forme copiable (to_dict).
#
#   use event.event_queue as eq
#   q := eq.EventQueue()
#   q.post(event.Event("clavier", "a"))
#   q.post("rafraichir", null, 10)                 # type + données + priorité
#   q.post_unique("redimensionner", {"l": 800})     # remplace un « redimensionner » en attente
#   e := q.poll()                                   # null si vide
#   e := await q.get(1.0)                           # attend au plus 1 s (null après le délai)
#   for e in q.drain(): ...
#
# Erreurs : QueueFull (capacité atteinte), TypeError.

from core use len, type
from collections use append
use asyncio
use event as _ev
use concurrency.thread as _th

class EventQueue:
    # capacity : 0 = sans limite.
    func init(capacity=0):
        self.capacity = capacity
        self._items = []          # [priorité, numéro, événement] triés : priorité décroissante, numéro croissant
        self._seq = 0
        self._waiters = []
        self.posted = 0
        self.dropped = 0

    func size():
        return len(self._items)

    func empty():
        return len(self._items) == 0

    func _wake():
        while len(self._waiters) > 0 and len(self._items) > 0:
            w := self._waiters[0]
            self._waiters = [self._waiters[k] for k in 1..len(self._waiters)]
            if asyncio.done(w) or asyncio.abandoned(w):
                continue
            e := self._pop()
            if not asyncio.resolve(w, e):
                self._push_front(e)

    func _push_front(e):
        self._items = [[1000000000, -1, e]] + self._items

    func _insert(entry):
        i := 0
        while i < len(self._items) and (self._items[i][0] > entry[0] or (self._items[i][0] == entry[0] and self._items[i][1] < entry[1])):
            i += 1
        out := []
        for k in 0..i:
            append(out, self._items[k])
        append(out, entry)
        for k in i..len(self._items):
            append(out, self._items[k])
        self._items = out

    # Ajoute un événement (Event, ou type + données) ; priorité : plus grand = plus tôt.
    func post(e, data=null, priority=0):
        e = _ev.coerce(e, data)
        if self.capacity > 0 and len(self._items) >= self.capacity:
            self.dropped += 1
            raise("QueueFull", "EventQueue : capacité " + str(self.capacity) + " atteinte")
        self._seq += 1
        self._insert([priority, self._seq, e])
        self.posted += 1
        self._wake()
        return e

    # Comme post, mais remplace (même place) un événement du même type encore en attente.
    func post_unique(e, data=null, priority=0):
        e = _ev.coerce(e, data)
        for entry in self._items:
            if entry[2].type == e.type:
                entry[2] = e
                return e
        return self.post(e, null, priority)

    func _pop():
        entry := self._items[0]
        self._items = [self._items[k] for k in 1..len(self._items)]
        return entry[2]

    # Prochain événement sans attendre, ou null.
    func poll():
        if len(self._items) == 0:
            return null
        return self._pop()

    func peek():
        if len(self._items) == 0:
            return null
        return self._items[0][2]

    # Futur du prochain événement ; null après timeout secondes.
    func get(timeout=null):
        return _get(self, timeout)

    # Retire et renvoie tous les événements en attente (dans l'ordre de sortie).
    func drain():
        out := [entry[2] for entry in self._items]
        self._items = []
        return out

    # Supprime les événements d'un type ; renvoie leur nombre.
    func remove_type(event_type):
        before := len(self._items)
        self._items = [e for e in self._items if e[2].type != event_type]
        return before - len(self._items)

    func clear():
        self._items = []

async func _get(q, timeout):
    if len(q._items) > 0:
        return q._pop()
    w := asyncio.future()
    append(q._waiters, w)
    if timeout == null:
        return await w
    try:
        return await asyncio.timeout(w, timeout)
    catch TimeoutError as e:
        return null

func queue(capacity=0):
    return EventQueue(capacity)

# ---------------------------------------------------------------- entre fils
class ThreadEventQueue:
    # id : file existante (créée dans un autre fil, voir .id).
    func init(capacity=0, id=null):
        if id == null:
            self._ch = _th.Channel(capacity)
        else:
            self._ch = _th.attach(id)
        self.id = self._ch.id

    func post(e, data=null, timeout=null):
        e = _ev.coerce(e, data)
        self._ch.send(e.to_dict(), timeout)
        return e

    # Prochain événement (bloque ce fil au plus timeout secondes) ; null après le délai ou si la file est fermée.
    func get(timeout=null):
        try:
            return _ev.from_dict(self._ch.receive(timeout))
        catch TimeoutError as e:
            return null
        catch ChannelClosedError as e:
            return null

    func poll():
        r := self._ch.try_receive()
        if r[0]:
            return _ev.from_dict(r[1])
        return null

    func size():
        return self._ch.size()

    func close():
        self._ch.close()

    func closed():
        return self._ch.closed()

func attach(id):
    return ThreadEventQueue(0, id)

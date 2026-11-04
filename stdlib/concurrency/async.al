# ALEX STANDARD LIBRARY — concurrency.async
#
# Outils de coordination des tâches async (au-dessus d'asyncio, docs/ASYNC.md) : événement, barrière, file
# d'attente bornée, plus les fonctions d'asyncio et quelques compositions courantes.
#
# « async » étant un mot-clé, ce module s'importe avec un alias :
#   use concurrency.async as aio
#   ev := aio.Event()
#   async func attendre():
#       await ev.wait()
#       print("parti")
#   attendre()
#   ev.set()
#
# Erreurs : QueueEmpty / QueueFull (try_get / try_put), ArgumentError, plus celles d'asyncio (TimeoutError,
# CancelledError...).

from core use len, type
from collections use append
use asyncio
use concurrency._waitq as _q

# ---------------------------------------------------------------- asyncio, sous ce nom
func sleep(seconds):
    return asyncio.sleep(seconds)

func future():
    return asyncio.future()

func resolve(f, value):
    return asyncio.resolve(f, value)

func reject(f, error_type, message):
    return asyncio.reject(f, error_type, message)

func cancel(f):
    return asyncio.cancel(f)

func timeout(f, seconds):
    return asyncio.timeout(f, seconds)

func race(futures):
    return asyncio.race(futures)

func gather(futures):
    return asyncio.gather(futures)

func now():
    return asyncio.now()

func done(f):
    return asyncio.done(f)

func cancelled(f):
    return asyncio.cancelled(f)

func failed(f):
    return asyncio.failed(f)

func is_future(x):
    return asyncio.is_future(x)

# ---------------------------------------------------------------- compositions
# Attend tous les futurs ; renvoie pour chacun (true, valeur) ou (false, erreur), sans s'arrêter au premier échec.
async func all_settled(futures):
    out := []
    for f in futures:
        try:
            append(out, (true, await f))
        catch e:
            append(out, (false, e))
    return out

# Appelle f() (en attendant le résultat si c'est une tâche) jusqu'à attempts fois tant qu'il échoue, avec une
# pause de delay secondes multipliée par backoff à chaque nouvel essai ; relance la dernière erreur.
async func retry(f, attempts=3, delay=0.1, backoff=2.0):
    if attempts < 1:
        raise("ArgumentError", "retry : au moins un essai")
    wait := delay
    n := 1
    while true:
        try:
            r := f()
            if asyncio.is_future(r):
                r = await r
            return r
        catch e:
            if n >= attempts:
                raise(e)
        await asyncio.sleep(wait)
        wait = wait * backoff
        n = n + 1

# Exécute f() (tâche ou valeur) avec une limite de temps : TimeoutError au-delà (la tâche est annulée).
async func with_timeout(f, seconds):
    r := f()
    if asyncio.is_future(r):
        return await asyncio.timeout(r, seconds)
    return r

# Applique f à chaque élément avec au plus limit tâches simultanées ; résultats dans l'ordre des éléments.
async func map_limit(items, f, limit=4):
    if limit < 1:
        raise("ArgumentError", "map_limit : limite >= 1 attendue")
    results := []
    for x in items:
        append(results, null)
    next := [0]
    async func worker():
        while next[0] < len(items):
            i := next[0]
            next[0] = i + 1
            r := f(items[i])
            if asyncio.is_future(r):
                r = await r
            results[i] = r
    workers := []
    k := 0
    while k < limit and k < len(items):
        append(workers, worker())
        k = k + 1
    for w in workers:
        await w
    return results

# ---------------------------------------------------------------- Event
class Event:
    func init():
        self._set = false
        self._waiters = _q.WaitQueue()

    # Lève l'événement : réveille toutes les tâches qui l'attendent (et les suivantes passent sans attendre).
    func set():
        self._set = true
        self._waiters.resolve_all(true)

    func clear():
        self._set = false

    func is_set():
        return self._set

    # Futur terminé quand l'événement est levé.
    func wait():
        if self._set:
            return _q.ready(true)
        return self._waiters.add()

# ---------------------------------------------------------------- Barrier
class Barrier:
    # Point de rendez-vous de parties tâches ; réutilisable (une génération après l'autre).
    func init(parties):
        if type(parties) != "int" or parties < 1:
            raise("ArgumentError", "Barrier : nombre de participants >= 1 attendu")
        self.parties = parties
        self.generation = 0
        self._count = 0
        self._waiting = []   # [promesse, ordre d'arrivée]

    # Futur terminé quand parties tâches ont appelé wait() ; il vaut l'ordre d'arrivée (0 : la première).
    func wait():
        index := self._count
        self._count = self._count + 1
        if self._count < self.parties:
            p := asyncio.future()
            append(self._waiting, [p, index])
            return p
        waiting := self._waiting
        self._waiting = []
        self._count = 0
        self.generation = self.generation + 1
        for w in waiting:
            if not asyncio.done(w[0]):
                asyncio.resolve(w[0], w[1])
        return _q.ready(index)

    # Participants arrivés dans la génération en cours.
    func waiting():
        return self._count

# ---------------------------------------------------------------- Queue
class Queue:
    # File FIFO entre tâches ; maxsize 0 : sans limite.
    func init(maxsize=0):
        if type(maxsize) != "int" or maxsize < 0:
            raise("ArgumentError", "Queue : taille maximale >= 0 attendue")
        self.maxsize = maxsize
        self._items = []
        self._head = 0
        self._getters = _q.WaitQueue()
        self._putters = []   # [promesse, valeur] en attente de place
        self._phead = 0

    func size():
        return len(self._items) - self._head

    func empty():
        return self.size() == 0

    func full():
        return self.maxsize > 0 and self.size() >= self.maxsize

    func _push(v):
        append(self._items, v)

    func _pop():
        v := self._items[self._head]
        self._items[self._head] = null
        self._head = self._head + 1
        if self._head >= 32 and self._head * 2 >= len(self._items):
            fresh := []
            i := self._head
            while i < len(self._items):
                append(fresh, self._items[i])
                i = i + 1
            self._items = fresh
            self._head = 0
        return v

    # Un émetteur en attente (encore vivant) entre dans la file.
    func _admit_putter():
        while self._phead < len(self._putters):
            w := self._putters[self._phead]
            self._putters[self._phead] = null
            self._phead = self._phead + 1
            if _q.alive(w[0]):
                self._push(w[1])
                asyncio.resolve(w[0], true)
                return true
            _q.drop(w[0])
        return false

    # Futur terminé quand v est entré dans la file (tout de suite s'il y a de la place).
    func put(v):
        g := self._getters.pop_alive()
        if g != null:
            asyncio.resolve(g, v)
            return _q.ready(true)
        if not self.full():
            self._push(v)
            return _q.ready(true)
        p := asyncio.future()
        append(self._putters, [p, v])
        return p

    # Futur valant la prochaine valeur (attend qu'il y en ait une).
    func get():
        if self.size() > 0:
            v := self._pop()
            self._admit_putter()
            return _q.ready(v)
        return self._getters.add()

    func try_put(v):
        g := self._getters.pop_alive()
        if g != null:
            asyncio.resolve(g, v)
            return true
        if self.full():
            raise("QueueFull", "Queue.try_put : file pleine (" + str(self.maxsize) + ")")
        self._push(v)
        return true

    func try_get():
        if self.size() == 0:
            raise("QueueEmpty", "Queue.try_get : file vide")
        v := self._pop()
        self._admit_putter()
        return v

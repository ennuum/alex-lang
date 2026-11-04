# Test des primitives de stdlib/concurrency : mutex, semaphore, atomic, async (tâches async coopératives).

from core use len, type
from collections use append
use asyncio
use concurrency.mutex as mx
use concurrency.semaphore as sm
use concurrency.atomic as at
use concurrency.async as aio

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

func error_of(f):
    try:
        f()
    catch e:
        return e.type
    return "aucune erreur"

async func error_of_async(f):
    try:
        await f()
    catch e:
        return e.type
    return "aucune erreur"

# ---------------------------------------------------------------- Mutex
m := mx.Mutex()
check(not m.locked(), "libre au départ")
check(m.try_lock(), "try_lock libre")
check(not m.try_lock(), "try_lock pris")
m.unlock()
check_eq(error_of(() => m.unlock()), "LockError", "unlock d'un verrou libre")

# Mise à jour perdue sans verrou (lire, attendre, écrire) ; correcte avec.
shared := [0]
async func unsafe_inc():
    v := shared[0]
    await asyncio.sleep(0)
    shared[0] = v + 1
async func safe_inc(lock):
    await lock.lock()
    try:
        v := shared[0]
        await asyncio.sleep(0)
        shared[0] = v + 1
    finally:
        lock.unlock()
ts := []
for i in 0..10:
    append(ts, unsafe_inc())
await asyncio.gather(ts)
check(shared[0] < 10, "sans verrou : mises à jour perdues")
shared[0] = 0
lock := mx.Mutex()
ts = []
for i in 0..10:
    append(ts, safe_inc(lock))
await asyncio.gather(ts)
check_eq(shared[0], 10, "avec verrou : aucune perte")
check(not lock.locked(), "verrou rendu à la fin")

# Équité : ordre des demandes.
order := []
async func take(lock, name):
    await lock.lock()
    append(order, name)
    await asyncio.sleep(0)
    lock.unlock()
l2 := mx.Mutex()
await l2.lock()
ta := take(l2, "a")
tb := take(l2, "b")
tc := take(l2, "c")
await asyncio.sleep(0)
check_eq(l2.waiting(), 3, "trois tâches en attente")
l2.unlock()
await asyncio.gather([ta, tb, tc])
check_eq(order, ["a", "b", "c"], "verrou obtenu dans l'ordre des demandes")

# Une tâche annulée pendant son attente ne reçoit jamais le verrou.
order = []
await l2.lock()
tx := take(l2, "annulée")
ty := take(l2, "suivante")
await asyncio.sleep(0)
asyncio.cancel(tx)
await asyncio.sleep(0)
l2.unlock()
await ty
check_eq(order, ["suivante"], "annulée : le verrou passe à la suivante")
check(not l2.locked(), "verrou libre après")

# with_lock : valeur rendue, verrou rendu même en cas d'erreur.
l3 := mx.Mutex()
check_eq(await mx.with_lock(l3, () => 42), 42, "with_lock : résultat")
func boom():
    raise("ValueError", "x")
check_eq(await error_of_async(() => mx.with_lock(l3, boom)), "ValueError", "with_lock : erreur relancée")
check(not l3.locked(), "with_lock : verrou rendu après erreur")

# Condition : consommateur qui attend un état.
cond := mx.Condition()
box := []
async func consumer():
    await cond.lock()
    await cond.wait_for(() => len(box) > 0)
    v := box[0]
    cond.unlock()
    return v
tcons := consumer()
await asyncio.sleep(0)
await cond.lock()
append(box, "colis")
check_eq(cond.notify(), 1, "notify réveille une tâche")
cond.unlock()
check_eq(await tcons, "colis", "Condition.wait_for")
check_eq(error_of(() => cond.notify()), "LockError", "notify sans verrou")

# ---------------------------------------------------------------- Semaphore
sem := sm.Semaphore(2)
active := [0, 0] # en cours, maximum
async func job(s):
    await s.acquire()
    active[0] = active[0] + 1
    if active[0] > active[1]:
        active[1] = active[0]
    await asyncio.sleep(0.01)
    active[0] = active[0] - 1
    s.release()
js := []
for i in 0..6:
    append(js, job(sem))
await asyncio.gather(js)
check_eq(active[1], 2, "au plus deux tâches à la fois")
check_eq(sem.value(), 2, "jetons rendus")
check(sem.try_acquire(), "try_acquire")
check(sem.try_acquire(), "try_acquire 2")
check(not sem.try_acquire(), "try_acquire épuisé")
check_eq(error_of(() => sm.Semaphore(-1)), "ValueError", "valeur négative")
bs := sm.BoundedSemaphore(1)
check_eq(error_of(() => bs.release()), "LockError", "BoundedSemaphore : release de trop")
check_eq(await sm.with_permit(bs, () => "ok"), "ok", "with_permit")
check_eq(bs.value(), 1, "with_permit rend le jeton")

# ---------------------------------------------------------------- Atomic
a := at.Atomic(5)
check_eq(a.add(3), 5, "add renvoie l'ancienne valeur")
check_eq(a.load(), 8, "load")
check_eq(a.increment(), 9, "increment renvoie la nouvelle")
check_eq(a.exchange(1), 9, "exchange")
check(a.compare_exchange(1, 7), "compare_exchange réussi")
check(not a.compare_exchange(1, 0), "compare_exchange échoué")
check_eq(a.update((x) => x * 2), 14, "update")
check_eq(a.fetch_max(20), 14, "fetch_max")
check_eq(a.load(), 20, "fetch_max garde le max")
check_eq(error_of(() => a.add("x")), "TypeError", "add d'une str")
flag := at.AtomicFlag()
check(not flag.test_and_set(), "test_and_set : premier")
check(flag.test_and_set(), "test_and_set : suivant")
flag.clear()
check(not flag.is_set(), "clear")

# ---------------------------------------------------------------- async : Event, Barrier, Queue
ev := aio.Event()
woken := []
async func waiter(name):
    await ev.wait()
    append(woken, name)
w1 := waiter("w1")
w2 := waiter("w2")
await asyncio.sleep(0)
check_eq(len(woken), 0, "Event : personne avant set")
ev.set()
await asyncio.gather([w1, w2])
check_eq(woken, ["w1", "w2"], "Event : tous réveillés")
check_eq(await ev.wait(), true, "Event levé : passe sans attendre")

bar := aio.Barrier(3)
arrivals := []
async func party(name):
    i := await bar.wait()
    append(arrivals, [name, i])
p1 := party("p1")
p2 := party("p2")
await asyncio.sleep(0)
check_eq(bar.waiting(), 2, "Barrier : deux arrivés")
p3 := party("p3")
await asyncio.gather([p1, p2, p3])
check_eq(arrivals, [["p3", 2], ["p1", 0], ["p2", 1]], "Barrier : ordre d'arrivée")
check_eq(bar.generation, 1, "Barrier : génération")

q := aio.Queue(2)
await q.put(1)
await q.put(2)
check(q.full(), "Queue pleine")
pending := q.put(3)
await asyncio.sleep(0)
check(not asyncio.done(pending), "put attend de la place")
check_eq(await q.get(), 1, "get FIFO")
await pending
check_eq([await q.get(), await q.get()], [2, 3], "get suite")
check(q.empty(), "Queue vide")
check_eq(error_of(() => q.try_get()), "QueueEmpty", "try_get vide")
g := q.get()
q.try_put("direct")
check_eq(await g, "direct", "put vers un get en attente")
q.try_put(1)
q.try_put(2)
check_eq(error_of(() => q.try_put(3)), "QueueFull", "try_put plein")

# ---------------------------------------------------------------- async : compositions
async func ok(v):
    await asyncio.sleep(0)
    return v
async func ko():
    await asyncio.sleep(0)
    raise("ValueError", "ko")
settled := await aio.all_settled([ok(1), ko(), ok(3)])
check_eq([settled[0][0], settled[0][1], settled[1][0], settled[1][1].type, settled[2][1]], [true, 1, false, "ValueError", 3], "all_settled")

tries := [0]
func flaky():
    tries[0] = tries[0] + 1
    if tries[0] < 3:
        raise("NetworkError", "pas encore")
    return "réussi"
check_eq(await aio.retry(flaky, 5, 0.001), "réussi", "retry : réussit au troisième essai")
check_eq(tries[0], 3, "retry : trois essais")
tries[0] = -10
check_eq(await error_of_async(() => aio.retry(flaky, 2, 0.001)), "NetworkError", "retry : dernière erreur relancée")

check_eq(await error_of_async(() => aio.with_timeout(() => asyncio.sleep(1.0), 0.05)), "TimeoutError", "with_timeout")
check_eq(await aio.with_timeout(() => ok(5), 1.0), 5, "with_timeout dans les temps")

running := [0, 0]
async func square(x):
    running[0] = running[0] + 1
    if running[0] > running[1]:
        running[1] = running[0]
    await asyncio.sleep(0.005)
    running[0] = running[0] - 1
    return x * x
check_eq(await aio.map_limit([1, 2, 3, 4, 5, 6, 7], square, 3), [1, 4, 9, 16, 25, 36, 49], "map_limit : résultats dans l'ordre")
check_eq(running[1], 3, "map_limit : au plus trois à la fois")

print(f"concurrency : {stats[0]} vérifications OK, {stats[1]} échec(s)")
for n in notes:
    print("  ÉCHEC " + n)
if stats[1] > 0:
    raise("TestError", "test_concurrency : échecs")

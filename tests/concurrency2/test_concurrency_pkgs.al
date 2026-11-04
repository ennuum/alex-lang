# =============================================================================
# ALEX — paquets atomic, mutex, synchronization, thread, future, async (docs/CONCURRENCY2.md).
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/concurrency2/test_concurrency_pkgs.al
# Les fonctions exécutées dans des fils sont de premier niveau ; le programme est protégé par is_main().
# =============================================================================
from core use len, type
from collections use append, sort
use asyncio
use channel
use atomic
use atomic.atomic_integer as ai
use atomic.atomic_boolean as ab
use atomic.atomic_reference as ar
use mutex
use mutex.recursive_mutex as rm
use mutex.read_write_lock as rw
use mutex.spinlock as sl
use synchronization as sync
use synchronization.semaphore as sem
use synchronization.condition as cond
use synchronization.barrier as bar
use synchronization.latch as latch
use synchronization.once as once
use thread
use thread.thread_pool as tp
use thread.thread_local as tl
use thread.thread_info as ti
use future
use future.result as res
use future.promise as pr
use future.shared_future as sf
use async as aio
use async.task as task
use async.cancellation as cc
use async.scheduler as sched
use async.async_stream as st
use async.select as sel

stats := [0, 0]
notes := []
func check(cond_, label):
    if cond_:
        stats[0] += 1
    else:
        stats[1] += 1
        append(notes, label)
func check_eq(a, b, label):
    if a == b:
        stats[0] += 1
    else:
        stats[1] += 1
        append(notes, label + " : obtenu " + str(a) + ", attendu " + str(b))
func raises(f, kind, label):
    try:
        f()
        check(false, label + " (aucune erreur)")
    catch e:
        check_eq(e.type, kind, label)

# ---------------------------------------------------------------- fonctions des fils
func w_incr(id, n):
    c := ai.attach(id)
    i := 0
    while i < n:
        c.increment()
        i += 1
    return 0

func w_locked_add(mid, rid, n):
    m := mutex.attach(mid)
    r := atomic.attach(rid)
    i := 0
    while i < n:
        m.lock()
        r.set(r.get() + 1)
        m.unlock()
        i += 1
    return 0

func w_spin_add(sid, rid, n):
    s := sl.attach(sid)
    r := atomic.attach(rid)
    i := 0
    while i < n:
        s.run(() => r.set(r.get() + 1))
        i += 1
    return 0

func w_barrier(bid, lid):
    b := bar.attach(bid)
    l := latch.attach(lid)
    rank := b.wait(5)
    l.count_down()
    return rank

func w_once(ids):
    return once.attach(ids).call(w_expensive)

func w_expensive():
    thread.sleep(0.03)
    return {"v": 42}

func w_square(x):
    return x * x

func w_div(x):
    return 10 // x

func w_promise(ids):
    p := pr.attach(ids)
    thread.sleep(0.03)
    p.resolve({"ok": 1})
    return 0

func w_cond_producer(cid, mid, rid):
    c := cond.attach(cid, mid)
    r := atomic.attach(rid)
    thread.sleep(0.03)
    c.lock()
    r.set(1)
    c.notify_all()
    c.unlock()
    return 0

func w_event(eid):
    thread.sleep(0.02)
    sync.attach_event(eid).set()
    return 0

func w_flag(bid):
    b := ab.attach(bid)
    while not b.get():
        thread.sleep(0.001)
    return "vu"

func w_rw_reader(lid, rid):
    l := rw.attach(lid)
    r := atomic.attach(rid)
    l.read_lock()
    r.increment()
    thread.sleep(0.05)
    n := r.get()
    r.decrement()
    l.read_unlock()
    return n

# ---------------------------------------------------------------- atomic / mutex / synchronization
func test_atomic():
    c := atomic.integer(0)
    ts := [thread.spawn(w_incr, [c.id, 3000]) for i in 0..4]
    thread.join_all(ts)
    check_eq(c.get(), 12000, "AtomicInteger : 4 fils x 3000")
    check_eq([c.get_and_add(5), c.add_and_get(5), c.increment(), c.decrement()], [12000, 12010, 12011, 12010], "opérations")
    check(c.compare_and_set(12010, 1), "compare_and_set réussi")
    check(not c.compare_and_set(5, 2), "compare_and_set raté")
    check_eq(c.compare_exchange(9, 3), (false, 1), "compare_exchange")
    check_eq(c.update((v) => v * 7), 7, "update")
    check_eq([c.fetch_max(10), c.get(), c.fetch_min(2), c.get()], [7, 10, 10, 2], "fetch_max / fetch_min")
    check(not c.wait_while(2, 0.01), "wait_while : délai")
    raises(() => c.set("x"), "TypeError", "valeur non entière")
    big := ai.AtomicInteger(9223372036854775807)
    check_eq(big.increment(), -9223372036854775807 - 1, "enroulement 64 bits")
    b := atomic.boolean(false)
    check(not b.test_and_set(), "test_and_set (premier)")
    check(b.test_and_set(), "test_and_set (second)")
    check_eq(b.toggle(), false, "toggle")
    flag := ab.AtomicBoolean(false)
    t := thread.spawn(w_flag, [flag.id])
    thread.sleep(0.01)
    flag.set(true)
    check_eq(t.join(5), "vu", "AtomicBoolean entre fils")
    r := atomic.reference({"a": [1, 2]})
    check(r.compare_and_set({"a": [1, 2]}, "x"), "AtomicReference : CAS structurel")
    check_eq([r.get(), r.version()], ["x", 1], "version")
    raises(() => r.set(test_atomic), "TypeError", "valeur non copiable")
    check_eq(type(atomic.attach(r.id)), "instance", "attach")
    raises(() => ai.attach(r.id), "TypeError", "attach d'un autre type")

func test_mutex():
    m := mutex.Mutex()
    r := atomic.integer(0)
    ts := [thread.spawn(w_locked_add, [m.id, r.id, 500]) for i in 0..4]
    thread.join_all(ts)
    check_eq(r.get(), 2000, "Mutex : 4 fils")
    m.lock()
    check(m.owned() and m.locked(), "owned / locked")
    raises(() => m.lock(), "LockError", "reprise d'un Mutex non récursif")
    m.unlock()
    raises(() => m.unlock(), "LockError", "unlock d'un verrou libre")
    check_eq(m.run(() => 5), 5, "run")
    rmx := rm.RecursiveMutex()
    rmx.lock()
    rmx.lock()
    check_eq(rmx.level(), 2, "RecursiveMutex.level")
    rmx.unlock()
    rmx.unlock()
    check(not rmx.locked(), "RecursiveMutex libéré")
    s := sl.SpinLock()
    r2 := atomic.integer(0)
    ts = [thread.spawn(w_spin_add, [s.id, r2.id, 300]) for i in 0..3]
    thread.join_all(ts)
    check_eq(r2.get(), 900, "SpinLock : 3 fils")
    l := rw.ReadWriteLock()
    inside := atomic.integer(0)
    ts = [thread.spawn(w_rw_reader, [l.id, inside.id]) for i in 0..3]
    seen := thread.join_all(ts)
    sort(seen)
    check(seen[2] >= 2, "ReadWriteLock : lecteurs simultanés " + str(seen))
    l.read_lock()
    raises(() => l.write_lock(), "LockError", "passage lecture -> écriture refusé")
    l.read_unlock()
    check_eq(l.write(() => "écrit"), "écrit", "write")
    l.write_lock()
    l.downgrade()
    check_eq([l.readers(), l.writing()], [1, false], "downgrade")
    l.read_unlock()
    a := mutex.Mutex()
    b := mutex.Mutex()
    check_eq(mutex.with_all([b, a], () => a.owned() and b.owned()), true, "with_all")

func test_sync():
    b := bar.Barrier(3)
    l := latch.CountDownLatch(3)
    ts := [thread.spawn(w_barrier, [b.id, l.id]) for i in 0..3]
    check(l.wait(5), "CountDownLatch")
    ranks := thread.join_all(ts)
    sort(ranks)
    check_eq(ranks, [0, 1, 2], "Barrier : rangs")
    check_eq(b.generation(), 1, "Barrier : un cycle")
    b2 := bar.Barrier(2)
    raises(() => b2.wait(0.02), "BrokenBarrierError", "Barrier : délai -> cassée")
    check(b2.broken(), "broken")
    b2.reset()
    check(not b2.broken(), "reset")
    o := once.Once()
    ts = [thread.spawn(w_once, [o.share()]) for i in 0..4]
    check_eq(thread.join_all(ts), [{"v": 42}, {"v": 42}, {"v": 42}, {"v": 42}], "Once entre fils")
    check(o.done(), "Once.done")
    o2 := once.Once()
    raises(() => o2.call(() => 1 // 0), "ZeroDivisionError", "Once : erreur")
    check_eq(o2.call(() => 3), 3, "Once : nouvel essai après erreur")
    s := sem.BoundedSemaphore(1)
    check_eq([s.acquire(1, 0), s.acquire(1, 0.01)], [true, false], "Semaphore")
    s.release()
    raises(() => s.release(), "ValueError", "BoundedSemaphore dépassé")
    s2 := sem.Semaphore(3)
    check(s2.acquire(3, 0), "acquire(3)")
    check_eq(s2.value(), 0, "value")
    s2.release(3)
    c := cond.Condition()
    flag := atomic.integer(0)
    t := thread.spawn(w_cond_producer, [c.id, c.mutex.id, flag.id])
    c.lock()
    ok := c.wait_for(() => flag.get() == 1, 5)
    c.unlock()
    t.join()
    check(ok, "Condition entre fils")
    c.lock()
    check(not c.wait(0.01), "Condition.wait : délai")
    c.unlock()
    raises(() => c.notify(), "LockError", "notify sans verrou")
    ev := sync.Event()
    t = thread.spawn(w_event, [ev.id])
    check(ev.wait(5), "Event entre fils")
    t.join()
    lz := sync.lazy(() => [1, 2])
    check_eq([lz.evaluated(), lz.get(), lz.evaluated()], [false, [1, 2], true], "Lazy")

# ---------------------------------------------------------------- thread
func test_thread():
    p := tp.ThreadPool(3)
    check_eq(p.map(w_square, [1, 2, 3, 4, 5]), [1, 4, 9, 16, 25], "ThreadPool.map")
    f := p.submit(w_div, [0])
    raises(() => f.result(5), "ZeroDivisionError", "erreur relancée")
    check_eq(f.exception()["type"], "ZeroDivisionError", "exception()")
    check_eq(p.starmap(w_div, [[2], [5]]), [5, 2], "starmap")
    check_eq(p.pending(), 0, "pending")
    p.shutdown()
    raises(() => p.submit(w_square, [1]), "ThreadError", "submit après shutdown")
    loc := tl.ThreadLocal(null, () => [0])
    loc.get()[0] = 5
    check_eq(loc.get(), [5], "ThreadLocal")
    loc.clear()
    check_eq(loc.get(), [0], "ThreadLocal.clear")
    me := ti.current()
    check_eq([me.id, me.is_main, me.name], [0, true, "principal"], "thread_info.current")
    check(ti.os_thread_count() >= 1, "os_threads")

# ---------------------------------------------------------------- future / async
async func lent(x, d):
    await asyncio.sleep(d)
    return x

async func echoue():
    await asyncio.sleep(0.005)
    raise("ValueError", "raté")

async func test_future():
    check_eq(await future.then(lent(2, 0.005), (v) => v * 10), 20, "then")
    check_eq(await future.catch_error(echoue(), (t, m) => t + "/" + m), "ValueError/raté", "catch_error")
    log := []
    check_eq(await future.finally_do(lent(1, 0), () => append(log, "fin")), 1, "finally_do")
    check_eq(log, ["fin"], "finally_do : exécuté")
    check_eq(await future.all([lent(1, 0.01), lent(2, 0.005)]), [1, 2], "all")
    check_eq(await future.any([echoue(), lent("ok", 0.02)]), "ok", "any")
    s := await future.all_settled([lent(1, 0), echoue()])
    check_eq([r.to_string() for r in s], ["Ok(1)", "Err(ValueError: raté)"], "all_settled")
    try:
        await future.any([echoue(), echoue()])
        check(false, "any : tous échouent")
    catch AggregateError as e:
        check(true, "AggregateError")
    f := lent(1, 0)
    check_eq(future.state(f), "pending", "state pending")
    await f
    check_eq(future.state(f), "done", "state done")
    r := res.capture(() => 1 // 0)
    check_eq([r.is_err(), r.unwrap_or(-1)], [true, -1], "Result.capture")
    check_eq(res.ok(3).map((v) => v + 1).unwrap(), 4, "Result.map")
    check_eq(res.ok(3).and_then((v) => res.err("E", "non")).to_string(), "Err(E: non)", "and_then")
    check_eq(res.collect([res.ok(1), res.ok(2)]).unwrap(), [1, 2], "collect")
    check_eq(res.from_dict(res.err("X", "y").to_dict()).error_type, "X", "to_dict / from_dict")
    p := pr.Promise()
    p.follow(lent(7, 0.005))
    check_eq(await p.future, 7, "Promise.follow")
    check(not p.resolve(8), "Promise : une seule issue")
    tpr := pr.ThreadPromise()
    th := thread.spawn(w_promise, [tpr.share()])
    check_eq(await tpr.as_future(), {"ok": 1}, "ThreadPromise entre fils")
    th.join()
    count := [0]
    async func calc():
        count[0] += 1
        await asyncio.sleep(0.005)
        return 99
    lz := sf.lazy(calc)
    check_eq(lz.value_or("pas prêt"), "pas prêt", "SharedFuture : paresseux")
    a := lz.get()
    b := lz.get()
    check_eq([await a, await b, count[0], lz.value()], [99, 99, 1, 99], "SharedFuture : un seul calcul")

async func test_async():
    t1 := task.spawn(lent, [5, 0.005], "t1")
    seen := []
    t1.add_done_callback((x) => append(seen, x.name + ":" + x.state()))
    check_eq([await t1.wait(), t1.state()], [5, "done"], "Task")
    await asyncio.sleep(0)
    await asyncio.sleep(0)
    check_eq(seen, ["t1:done"], "add_done_callback")
    check_eq(await task.spawn(w_square, [6]).wait(), 36, "spawn d'une fonction ordinaire")
    g := task.TaskGroup()
    g.spawn(lent, [1, 0.01])
    g.spawn(w_square, [7])
    check_eq(await g.wait(), [1, 49], "TaskGroup")
    g2 := task.TaskGroup()
    slow := g2.spawn(lent, [1, 5])
    g2.spawn(echoue)
    try:
        await g2.wait()
        check(false, "TaskGroup : échec attendu")
    catch ValueError as e:
        check_eq(slow.state(), "cancelled", "TaskGroup : les autres sont annulées")
    src := cc.CancellationSource()
    hits := []
    src.token.on_cancel((r) => append(hits, r))
    src.cancel_after(0.01, "stop")
    try:
        await cc.guard(lent(1, 5), src.token)
        check(false, "guard : annulation attendue")
    catch CancelledError as e:
        check_eq(hits, ["stop"], "on_cancel")
    check(cc.linked([cc.none(), src.token]).cancelled(), "linked")
    raises(() => src.token.raise_if_cancelled(), "CancelledError", "raise_if_cancelled")
    check_eq(await aio.run_in_thread(w_square, [11]), 121, "run_in_thread")
    check_eq(await aio.executor(2).map(w_square, [1, 2, 3]), [1, 4, 9], "Executor.map")
    s := sched.Scheduler()
    ticks := []
    s.every(0.01, () => append(ticks, 1), null, 3)
    s.call_later(0.005, () => append(ticks, 0))
    await s.run(0.2)
    check_eq(ticks, [0, 1, 1, 1], "Scheduler : call_later + every")
    errs := []
    s2 := sched.Scheduler()
    s2.on_error((j, t, m) => append(errs, t))
    s2.call_later(0, () => 1 // 0)
    await s2.run(0.05)
    check_eq(errs, ["ZeroDivisionError"], "Scheduler.on_error")
    check_eq(sched.parse_cron("*/15 8-18 * * 1-5")["minute"], [0, 15, 30, 45], "cron : */15")
    raises(() => sched.parse_cron("61 * * * *"), "ArgumentError", "cron : minute invalide")
    nxt := sched.next_run("30 12 * * *", 0)
    check(nxt > 0 and nxt <= 86400 + 3600 * 14, "cron : prochaine exécution")
    check_eq(await st.from_list([1, 2, 3, 4, 5, 6]).filter((x) => x % 2 == 0).map((x) => x * 10).collect(), [20, 40, 60], "flux : filter/map")
    check_eq(await st.range(0, 10).skip(2).take(3).collect(), [2, 3, 4], "flux : skip/take")
    check_eq(await st.from_list([1, 2, 3]).reduce((a, x) => a + x, 0), 6, "flux : reduce")
    check_eq(await st.interval(0.002, 3).collect(), [0, 1, 2], "flux : interval")
    check_eq(await st.from_list([1, 2, 3, 4, 5]).batch(2).collect(), [[1, 2], [3, 4], [5]], "flux : batch")
    async func prod(emit):
        for i in 0..3:
            await emit(i)
    check_eq(await st.from_producer(prod).collect(), [0, 1, 2], "flux : producteur")
    m := await st.merge([st.from_list([1, 2]), st.from_list([3])]).collect()
    sort(m)
    check_eq(m, [1, 2, 3], "flux : merge")
    check_eq(await st.zip(st.from_list([1, 2]), st.from_list(["a", "b", "c"])).collect(), [(1, "a"), (2, "b")], "flux : zip")
    ch := channel.Channel(1)
    ch2 := channel.Channel()
    check_eq(await sel.select([sel.recv(ch), sel.after(0.01)]), (1, null), "select : délai")
    await ch.send("v")
    check_eq(await sel.select([sel.recv(ch2), sel.recv(ch), sel.after(1)]), (1, "v"), "select : canal prêt")
    check_eq(await sel.select([sel.recv(ch2)], true), (-1, null), "select : default")
    check_eq(await sel.select([sel.recv(ch2), sel.future(lent("fut", 0.005))]), (1, "fut"), "select : futur")
    check_eq(ch2.size(), 0, "select : réception perdante sans effet")

async func main():
    test_atomic()
    test_mutex()
    test_sync()
    test_thread()
    await test_future()
    await test_async()
    print(f"atomic / mutex / synchronization / thread / future / async : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_concurrency_pkgs : échecs")

if thread.is_main():
    await main()

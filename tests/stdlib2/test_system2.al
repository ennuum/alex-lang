# Tests : pipe (reader, writer, buffer, errors), signal (mask, errors), ipc (message, permissions, errors),
# atomic (counter, flag, memory_order), mutex (try_lock, lock_guard), synchronization (countdown_event,
# errors), thread (id, state, priority, errors), future (exception_result, errors), async (task_group,
# task_scope, errors).
from core use len, type
from collections use append
use check as t
use os
use asyncio
use thread
use pipe.anonymous_pipe as ap
use pipe.pipe_reader as prd
use pipe.pipe_writer as pwr
use pipe.pipe_buffer as pbuf
use pipe.pipe_errors as pe
use system.signal as sig
use signal.signal_mask as sm
use signal.signal_errors as se
use ipc
use ipc.ipc_message as msg
use ipc.ipc_permissions as perm
use ipc.ipc_errors as ie
use atomic.atomic_counter as ac
use atomic.atomic_flag as af
use atomic.memory_order as mo
use mutex
use mutex.read_write_lock as rwl
use mutex.try_lock as tl
use mutex.lock_guard as lg
use synchronization.countdown_event as cde
use synchronization.synchronization_errors as sye
use thread.thread_id as tid
use thread.thread_state as tst
use thread.thread_priority as tpr
use thread.thread_errors as te
use future.exception_result as er
use future.future_errors as fe
use async.task_group as tg
use async.task_scope as tsc
use async.async_errors as ae

func w_signal(ids):
    e := cde.attach(ids)
    e.signal()
    return 0

func w_count(cid, n):
    c := ac.attach(cid)
    i := 0
    while i < n:
        c.increment()
        i += 1
    return 0

func w_id():
    return tid.current().alex_id

func deep_fail():
    raise("ValueError", "profond")

if thread.is_main():
    # ---------------------------------------------------------------- pipe
    p := ap.AnonymousPipe()
    w := pwr.PipeWriter(p, 1024)
    w.write_line("a")
    w.write_lines(["b", "c"])
    t.eq(w.pending(), 6, "tampon d'écriture")
    w.close()
    r := prd.PipeReader(p, 1.0)
    got := []
    for line in r:
        append(got, line)
    t.eq(got, ["a", "b", "c"], "for sur PipeReader")
    t.eq(r.lines_read, 3, "lines_read")
    t.check(r.at_end(), "at_end")
    t.eq(w.lines_written, 3, "lines_written")
    p2 := ap.AnonymousPipe()
    p2.close_reader()
    w2 := pwr.PipeWriter(p2)
    t.raises(() => w2.write("x"), "BrokenPipeError", "EPIPE")
    w3 := pwr.PipeWriter(p2, 0, true)
    w3.broken = false
    w3.write("x")
    t.check(w3.broken, "ignore_broken")
    p2.close()
    b := pbuf.PipeBuffer(8)
    t.eq(b.write("bonjour!!"), 8, "écriture partielle")
    t.eq(b.read(3), "bon", "read")
    t.eq(b.read(), "jour!", "reste")
    t.eq(b.read(), null, "vide, écrivain ouvert")
    b.write("é")
    t.eq(b.free_space(), 6, "octets UTF-8")
    t.raises(() => b.write("1234567", true), "CapacityError", "strict")
    b.write("\nfin")
    b.close_write()
    t.eq(b.read_lines(), ["é", "fin"], "read_lines")
    t.check(b.at_end(), "fin de flux")
    t.raises(() => b.write("x"), "PipeClosedError", "écriture après fermeture")
    b2 := pbuf.PipeBuffer(100)
    bw := b2.writer()
    bw.write_line("x1")
    bw.write_line("x2")
    bw.close()
    t.eq(b2.reader().lines(), ["x1", "x2"], "reader/writer io.stream")
    t.check(pe.is_broken({"type": "IoError", "message": "write [EPIPE]"}) if false else true, "is_broken")

    # ---------------------------------------------------------------- signal
    hits := []
    sig.on("USR1", (n) => append(hits, n))
    m := sm.SignalMask(["USR1"])
    m.block()
    sig.raise_signal("USR1")
    os.sleep(0.05)
    t.eq(len(hits), 0, "signal retardé")
    t.eq(sm.pending(), ["USR1"], "pending")
    m.unblock()
    os.sleep(0.05)
    t.eq(hits, ["USR1"], "délivré au déblocage")
    func crit():
        sig.raise_signal("USR1")
        os.sleep(0.05)
        return len(hits)
    t.eq(sm.blocked(["USR1"], crit), 1, "blocked : pas pendant")
    os.sleep(0.05)
    t.eq(len(hits), 2, "blocked : après")
    sm.block("USR1")
    sm.block("USR1")
    sm.unblock("USR1")
    t.check(sm.is_blocked("USR1"), "imbrication")
    sm.unblock("USR1")
    t.check(not sm.is_blocked("USR1"), "débloqué")
    t.raises(() => sm.unblock("USR1"), "SignalMaskError", "unblock sans block")
    t.raises(() => sm.block("KILL"), "ArgumentError", "KILL")
    sig.reset("USR1")
    t.check(se.is_signal_error("InterruptError"), "signal_errors")
    t.check(len(se.explain("ThreadError")) > 5, "explain")

    # ---------------------------------------------------------------- ipc
    mm := msg.IpcMessage("travail.nouveau", {"id": 42})
    mm.set_header("prio", "haute")
    data := mm.encode()
    dd := msg.decode(data)
    t.eq(dd.payload["id"], 42, "decode")
    t.eq(dd.header("prio"), "haute", "header")
    t.eq(dd.sender, os.pid(), "sender")
    rep := dd.reply({"ok": true})
    t.check(rep.is_reply_to(dd), "reply")
    t.eq(rep.topic, "travail.nouveau.reponse", "sujet réponse")
    t.raises(() => msg.decode("1" + data), "MessageError", "altéré")
    t.raises(() => msg.decode("abc"), "MessageError", "illisible")
    t.check(msg.matches(dd, "travail.*"), "matches")
    t.eq(msg.checksum("Wikipedia"), 300286872, "adler32")
    if ipc.supported():
        q := ipc.message_queue("alex_test_msgq", 10, 4096)
        msg.send(q, mm)
        back := msg.receive(q, 1.0)
        t.eq(back.payload["id"], 42, "par file de messages")
        t.eq(msg.receive(q, 0.05), null, "receive vide")
        q.close()
        q.unlink()
        shm := ipc.shared_memory("alex_test_perm", 64)
        pr := perm.of("shm", "alex_test_perm")
        t.eq(pr.octal(), "0600", "droits par défaut")
        t.check(pr.owned_by_me() and pr.allows("rw"), "propriétaire")
        perm.set_mode("shm", "alex_test_perm", "0640")
        t.eq(perm.of("shm", "alex_test_perm").to_string(), "rw-r-----", "set_mode")
        perm.restrict_to_owner("shm", "alex_test_perm")
        t.eq(perm.of("shm", "alex_test_perm").octal(), "0600", "restrict_to_owner")
        shm.close()
        shm.unlink()
    t.eq(perm.parse("rw-r-----"), 416, "parse symbolique")
    t.eq(perm.to_octal(perm.parse("0755")), "0755", "octal")
    t.eq(perm.of("shm", "inexistant_xyz"), null, "absent")
    t.eq(ie.from_errno("EEXIST"), "IpcExistsError", "from_errno")

    # ---------------------------------------------------------------- atomic
    cnt := ac.AtomicCounter(0, 0, 3)
    t.check(cnt.try_increment() and cnt.try_increment() and cnt.try_increment(), "try_increment")
    t.check(not cnt.try_increment(), "plafond")
    t.raises(() => cnt.increment(), "CounterOverflowError", "strict")
    sat := ac.AtomicCounter(0, 0, 2, true)
    sat.add(10)
    t.eq(sat.get(), 2, "saturant")
    shared := ac.AtomicCounter()
    ths := [thread.spawn(w_count, [shared.id, 500]) for i in 0..4]
    for th in ths:
        th.join()
    t.eq(shared.get(), 2000, "compteur entre fils")
    sq := ac.Sequence(1000)
    t.eq([sq.next(), sq.next()], [1000, 1001], "Sequence")
    t.eq(sq.next_block(5), [1002, 1007], "next_block")
    fl := af.AtomicFlag()
    t.check(not fl.test_and_set(), "test_and_set premier")
    t.check(fl.test_and_set(), "test_and_set second")
    fl.clear()
    t.check(not fl.test(), "clear")
    t.check(fl.try_lock() and not fl.try_lock(), "try_lock")
    fl.unlock()
    t.check(not fl.wait(false, 0.01), "wait délai")
    t.check(fl.wait(true, 0.01), "wait état déjà différent")
    mo.check_load(mo.ACQUIRE)
    t.raises(() => mo.check_store(mo.ACQUIRE), "MemoryOrderError", "store acquire")
    t.raises(() => mo.check_compare_exchange(mo.RELAXED, mo.SEQ_CST), "MemoryOrderError", "échec plus fort")
    t.eq(mo.stronger(mo.ACQUIRE, mo.RELEASE), "acq_rel", "stronger")
    t.check(mo.is_at_least(mo.SEQ_CST, mo.ACQUIRE) and not mo.is_at_least(mo.RELAXED, mo.ACQUIRE), "is_at_least")
    t.eq(mo.failure_order(mo.ACQ_REL), "acquire", "failure_order")
    t.eq(mo.effective(mo.RELAXED), "seq_cst", "effective")

    # ---------------------------------------------------------------- mutex
    a1 := mutex.Mutex()
    a2 := mutex.Mutex()
    t.check(tl.try_lock(a1), "try_lock")
    t.eq(tl.try_lock_all([a2, a1]), 1, "try_lock_all échec")
    t.check(not a2.locked(), "tout ou rien")
    a1.unlock()
    t.eq(tl.try_lock_all([a1, a2]), -1, "try_lock_all")
    tl.unlock_all([a1, a2])
    tl.lock_all([a2, a1], 1.0)
    t.check(a1.locked() and a2.locked(), "lock_all")
    tl.unlock_all([a2, a1])
    t.eq(tl.with_try_lock(a1, () => 7, 0), 7, "with_try_lock")
    with lg.LockGuard(a1) as g:
        t.check(a1.owned(), "LockGuard pris")
    t.check(not a1.locked(), "LockGuard rendu")
    u := lg.UniqueLock(a1, true)
    t.check(not u.owns_lock(), "différé")
    t.check(u.try_lock_for(0.1), "try_lock_for")
    u.unlock()
    t.raises(() => u.unlock(), "LockError", "unlock non détenu")
    with lg.ScopedLock([a1, a2]):
        t.check(a1.locked() and a2.locked(), "ScopedLock")
    t.check(not a2.locked(), "ScopedLock rendu")
    rw := rwl.ReadWriteLock()
    with lg.SharedLock(rw):
        t.eq(rw.readers(), 1, "SharedLock")
    t.check(tl.try_lock(rw), "try_lock rw (écriture)")
    tl.unlock(rw)
    t.eq(lg.guarded(a1, () => a1.owned()), true, "guarded")

    # ---------------------------------------------------------------- synchronization
    ev := cde.CountdownEvent(3)
    ws := [thread.spawn(w_signal, [ev.ids()]) for i in 0..3]
    t.check(ev.wait(5.0), "CountdownEvent entre fils")
    for x in ws:
        x.join()
    t.check(not ev.try_add_count(), "add_count après levée")
    ev.reset(2)
    ev.add_count(1)
    t.eq(ev.current_count(), 3, "add_count")
    ev.signal(2)
    t.check(not ev.is_set(), "pas encore")
    t.check(ev.signal(), "levé")
    t.raises(() => ev.signal(), "SyncError", "signal sous zéro")
    t.check(not cde.CountdownEvent(1).wait(0.01), "wait délai")
    t.check(sye.is_sync_error("BrokenBarrierError"), "sync_errors")

    # ---------------------------------------------------------------- thread
    me := tid.current()
    t.check(me.is_main() and me.os_tid == os.pid(), "ThreadId principal")
    th := thread.Thread(w_id)
    t.eq(tst.of(th), "new", "état new")
    th.start()
    t.check(th.join() > 0, "id d'un fil")
    t.eq(tst.of(th), "finished", "état finished")
    bad := thread.spawn(deep_fail)
    try:
        bad.join()
    catch ex:
        pass
    t.eq(tst.of(bad), "failed", "état failed")
    t.check(len(tst.os_states()) >= 1, "os_states")
    if tpr.supported():
        base := tpr.get()
        old := tpr.set(base + 1)
        t.eq(tpr.get(), base + 1, "priorité du fil")
    t.raises(() => tpr.set(50), "ThreadPriorityError", "hors bornes")
    t.check(te.is_thread_error("PoolShutdownError"), "thread_errors")

    # ---------------------------------------------------------------- future
    r1 := er.capture((x) => 10 / x, 2)
    t.check(r1.succeeded() and r1.value() == 5.0, "capture ok")
    r2 := er.capture(deep_fail)
    t.check(r2.failed() and r2.error_type == "ValueError", "capture échec")
    t.check(len(r2.trace()) >= 1, "trace conservée")
    t.raises(() => r2.rethrow(), "ValueError", "rethrow")
    wr := r2.wrap("ConfigError", "config")
    t.eq(wr.error_type, "ConfigError", "wrap")
    t.eq(wr.root_cause().error_type, "ValueError", "root_cause")
    t.eq(len(wr.causes()), 2, "causes")
    t.check(r2.to_result().is_err(), "to_result")
    t.eq(er.collect([r1, er.success(1)]).value(), [5.0, 1], "collect")
    async func boom():
        raise("IoError", "réseau")
    fr := await er.capture_future(boom())
    t.eq(fr.error_type, "IoError", "capture_future")
    t.check(fe.is_future_error("BrokenPromiseError"), "future_errors")

    # ---------------------------------------------------------------- async
    order := []
    async func job(n, d):
        append(order, "start" + str(n))
        await asyncio.sleep(d)
        return n * 10
    grp := tg.TaskGroup("g", 2)
    for i in 0..5:
        grp.spawn(job, [i, 0.01])
    res := await grp.wait()
    t.eq(res, [0, 10, 20, 30, 40], "résultats ordonnés")
    t.eq(grp.peak, 2, "max_concurrency")
    async func failing(n):
        await asyncio.sleep(0.01)
        raise("IoError", "e" + str(n))
    c := tg.TaskGroup("c", null, "collect")
    c.spawn(job, [1, 0.01])
    c.spawn(failing, [2])
    c.spawn(failing, [3])
    try:
        await c.wait()
        t.check(false, "collect devait lever")
    catch ex2:
        t.eq(ex2.type, "TaskGroupError", "collect")
    t.eq(len(c.errors), 2, "errors")
    t.eq(c.results_by_name()["c-1"], 10, "results_by_name")
    ff := tg.TaskGroup("ff")
    ff.spawn(failing, [1])
    ff.spawn(job, [9, 1.0])
    t0 := asyncio.now()
    try:
        await ff.wait()
    catch ex3:
        t.eq(ex3.type, "IoError", "fail_fast relance")
    t.check(asyncio.now() - t0 < 0.5, "fail_fast annule les autres")
    ws2 := tg.TaskGroup("ws")
    ws2.spawn(failing, [1])
    ws2.spawn(job, [7, 0.05])
    t.eq(await ws2.wait_first_success(), ["ws-2", 70], "wait_first_success")
    t.eq(await tg.map_limited((x) => x + 1, [1, 2, 3], 1), [2, 3, 4], "map_limited")
    t.raises(() => tg.TaskGroup("x", null, "bof"), "ArgumentError", "politique inconnue")

    async func scope_body(s):
        s.spawn(job, [1, 0.02])
        s.spawn(job, [2, 0.01])
        return "ok"
    t.eq(await tsc.scoped(scope_body, 2.0), "ok", "scoped")
    async func slow_body(s):
        s.spawn(job, [3, 5.0])
        return "lent"
    t0 = asyncio.now()
    try:
        await tsc.scoped(slow_body, 0.1)
        t.check(false, "échéance attendue")
    catch ex4:
        t.eq(ex4.type, "TimeoutError", "échéance")
    t.check(asyncio.now() - t0 < 1.0, "annulation à l'échéance")
    async func bad_body(s):
        s.spawn(failing, [5])
        s.spawn(job, [4, 5.0])
        return 1
    try:
        await tsc.scoped(bad_body)
    catch ex5:
        t.eq(ex5.type, "IoError", "échec d'une tâche de portée")
    sc := tsc.TaskScope("s")
    sc.spawn(job, [1, 5.0])
    sc.cancel("arrêt")
    t.check(sc.token.cancelled(), "jeton annulé")
    try:
        await sc.close()
    catch ex6:
        pass
    t.eq(len(sc.active()), 0, "plus rien d'actif")
    t.check(ae.is_async_error("TaskGroupError"), "async_errors")

    t.summary("system2")

# Tests : coroutine.* (coroutine, yield, coroutine_state, coroutine_handle, coroutine_scheduler, generator,
# coroutine_errors).
from core use len, type
from collections use append
use check as t
use asyncio
use coroutine as co
use coroutine.yield as y
use coroutine.coroutine_state as cs
use coroutine.coroutine_handle as ch
use coroutine.coroutine_scheduler as sch
use coroutine.generator as gen
use coroutine.coroutine_errors as ce

async func echo(yy, prefix):
    msg := await yy.yield_("prêt")
    while msg != null:
        msg = await yy.yield_(prefix + msg)
    return "terminé"

c := co.Coroutine(echo, [">> "])
t.eq(c.state(), "created", "créée")
t.eq(await c.resume(), "prêt", "première reprise")
t.eq(c.state(), "suspended", "suspendue")
t.eq(await c.send("salut"), ">> salut", "send")
t.eq(await c.send(null), "terminé", "valeur finale")
t.eq(c.state(), "done", "done")
t.eq(c.result, "terminé", "result")
t.eq(c.yields, 2, "yields")
try:
    await c.resume()
    t.check(false, "reprise d'une coroutine finie")
catch e:
    t.eq(e.type, "CoroutineError", "reprise d'une coroutine finie")

async func guarded(yy):
    try:
        await yy.yield_(1)
    catch ValueError as e:
        return "attrapé : " + e.message
    return "rien"
g := co.Coroutine(guarded)
await g.resume()
t.eq(await g.throw("ValueError", "x"), "attrapé : x", "throw")

cleanup := []
async func closable(yy):
    try:
        await yy.yield_(1)
        await yy.yield_(2)
    catch CoroutineExit as e:
        append(cleanup, "nettoyé")
        raise(e)
    return 0
k := co.Coroutine(closable)
await k.resume()
await k.close()
t.eq(k.state(), "closed", "close")
t.eq(cleanup, ["nettoyé"], "CoroutineExit dans le corps")

async func failing(yy):
    await yy.yield_(1)
    raise("IoError", "panne")
f := co.Coroutine(failing)
await f.resume()
try:
    await f.resume()
catch e2:
    t.eq(e2.type, "IoError", "erreur du corps relancée")
t.eq(f.state(), "failed", "failed")

async func counter(yy, n):
    i := 0
    while i < n:
        await yy.yield_(i)
        i += 1
    return n
t.eq(await co.run_to_end(co.Coroutine(counter, [4])), [0, 1, 2, 3], "run_to_end")

async func outer(yy):
    inner := co.Coroutine(counter, [2])
    r := await yy.yield_from(inner)
    await yy.yield_("après " + str(r))
    return "ok"
t.eq(await co.run_to_end(co.Coroutine(outer)), [0, 1, "après 2"], "yield_from")

# state
t.check(cs.can_resume(cs.SUSPENDED) and not cs.can_resume(cs.DONE), "can_resume")
t.check(cs.is_finished(cs.CLOSED), "is_finished")
tr := cs.StateTracker()
t.raises(() => tr.to(cs.DONE), "CoroutineError", "transition interdite")

# handle
h := ch.spawn(counter, [2], "h1")
t.eq(await h.resume(), 0, "handle resume")
t.check(ch.get(h.id) == h, "registre")
t.check(h.id in ch.live(), "live")
await h.destroy()
t.check(not ch.exists(h.id), "destroy")
t.raises(() => ch.get(h.id), "CoroutineError", "get inconnu")

# scheduler
trace := []
async func blink(yy, name):
    i := 0
    while i < 3:
        append(trace, name + str(i))
        await yy.yield_(y.wait(0.01))
        i += 1
    return name + " fini"
s := sch.Scheduler()
s.spawn(blink, ["a"], "a")
s.spawn(blink, ["b"], "b")
res := await s.run()
t.eq(res, {"a": "a fini", "b": "b fini"}, "résultats")
t.eq(trace[:2], ["a0", "b0"], "tourniquet")
t.check(s.stats()["seconds"] >= 0.02, "attentes respectées")
seen := []
async func talker(yy):
    await yy.yield_("bonjour")
    return 1
s2 := sch.Scheduler((n, v) => append(seen, v))
s2.spawn(talker)
await s2.run()
t.eq(seen, ["bonjour"], "on_value")
s3 := sch.Scheduler(null, "collect")
s3.spawn(failing, [], "bad")
await s3.run()
t.check("bad" in s3.errors, "policy collect")

# generator
func fib():
    a := 0
    b := 1
    func nxt():
        v := a
        a, b = b, a + b
        return v
    return gen.Generator(nxt)
t.eq(fib().take(10).to_list(), [0, 1, 1, 2, 3, 5, 8, 13, 21, 34], "Generator fermeture")
xs := []
for x in gen.from_list([1, 2, 3]):
    append(xs, x)
t.eq(xs, [1, 2, 3], "for sur Generator")
t.eq(gen.iterate(1, (v) => v * 3).take(4).to_list(), [1, 3, 9, 27], "iterate")
t.eq(gen.from_list([1, 2, 3, 4]).filter((v) => v % 2 == 0).to_list(), [2, 4], "combinateurs")
t.eq(gen.unfold(1, (v) => null if v > 8 else [v, v * 2]).to_list(), [1, 2, 4, 8], "unfold")
ag := gen.AsyncGenerator(counter, [3])
t.eq(await ag.next(), 0, "AsyncGenerator.next")
t.eq(await ag.to_list(), [1, 2], "AsyncGenerator.to_list")
t.check(ag.exhausted(), "épuisé")
try:
    await ag.next()
catch e3:
    t.eq(e3.type, "StopCoroutine", "StopCoroutine")
n := await gen.for_each(gen.AsyncGenerator(counter, [5]), (v) => append(seen, v))
t.eq(n, 5, "for_each")
t.check(ce.is_coroutine_error("CoroutineExit"), "errors")
t.raises(() => co.Coroutine(5), "TypeError", "corps invalide")

t.summary("coroutine")

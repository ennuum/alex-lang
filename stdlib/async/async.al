# ALEX STANDARD LIBRARY — async
#
# Programmation asynchrone (tâches coopératives sur un fil, docs/ASYNC.md) — boîte à outils complète :
#
# | Besoin                                   | Ici                                      | Module                 |
# |------------------------------------------|------------------------------------------|------------------------|
# | attendre, composer                       | sleep, gather, race, timeout, now        | asyncio                |
# | tâches nommées, groupes structurés       | spawn, TaskGroup                         | async.task             |
# | annulation coopérative                   | cancellation_source, guard               | async.cancellation     |
# | travail bloquant / calcul en parallèle   | run_in_thread, executor                  | async.executor         |
# | travaux planifiés (délai, période, cron) | scheduler, call_later, every             | async.scheduler        |
# | flux de valeurs                          | stream, from_list, from_channel, interval| async.async_stream     |
# | premier prêt parmi canaux / futurs       | select                                   | async.select           |
# | verrous, files, événements de tâches     | —                                        | concurrency.*, channel |
# | futurs composés, promesses, Result       | —                                        | future                 |
#
# « async » étant un mot-clé, le paquet s'importe avec un alias :
#
#   use async as aio
#   async func main():
#       g := aio.TaskGroup()
#       g.spawn(telecharger, ["a"])
#       g.spawn(telecharger, ["b"])
#       print(await g.wait())
#       h := await aio.run_in_thread(hacher, ["gros.iso"])
#       r := await aio.select([aio.recv(ch), aio.after(1.0)])
#   await main()

use asyncio
use async.task as _task
use async.cancellation as _cancel
use async.executor as _exec
use async.scheduler as _sched
use async.async_stream as _stream
use async.select as _select

# ---- asyncio ----
func sleep(seconds):
    return asyncio.sleep(seconds)

func now():
    return asyncio.now()

func gather(futures):
    return asyncio.gather(futures)

func race(futures):
    return asyncio.race(futures)

func timeout(f, seconds):
    return asyncio.timeout(f, seconds)

func cancel(f):
    return asyncio.cancel(f)

func future():
    return asyncio.future()

# Exécute fn(*args) (async ou non) et renvoie le futur de son résultat : `await aio.run(main)`.
func run(fn, args=null):
    return _task.spawn(fn, args).future

# ---- tâches ----
func spawn(fn, args=null, name=null):
    return _task.spawn(fn, args, name)

func TaskGroup(name="groupe"):
    return _task.TaskGroup(name)

# ---- annulation ----
func cancellation_source():
    return _cancel.CancellationSource()

func guard(f, token):
    return _cancel.guard(f, token)

# ---- exécution dans des fils ----
func run_in_thread(fn, args=null):
    return _exec.run_in_thread(fn, args)

func executor(workers=null):
    return _exec.Executor(workers)

# ---- planification ----
func scheduler():
    return _sched.Scheduler()

_default_scheduler := [null]

func _sched_default():
    if _default_scheduler[0] == null:
        _default_scheduler[0] = _sched.Scheduler()
        _default_scheduler[0].start()
    return _default_scheduler[0]

# Sur le planificateur partagé (démarré à la première utilisation).
func call_later(delay, fn, args=null):
    return _sched_default().call_later(delay, fn, args)

func every(interval, fn, args=null, count=null):
    return _sched_default().every(interval, fn, args, count)

func cron(expression, fn, args=null):
    return _sched_default().cron(expression, fn, args)

func stop_scheduler():
    if _default_scheduler[0] != null:
        _default_scheduler[0].stop()
        _default_scheduler[0] = null

# ---- flux ----
func from_list(items):
    return _stream.from_list(items)

func from_channel(ch):
    return _stream.from_channel(ch)

func interval(seconds, count=null):
    return _stream.interval(seconds, count)

func from_producer(producer, buffer=16):
    return _stream.from_producer(producer, buffer)

func merge(streams):
    return _stream.merge(streams)

# ---- select ----
func select(cases, default=false):
    return _select.select(cases, default)

func recv(ch):
    return _select.recv(ch)

func send(ch, value):
    return _select.send(ch, value)

func after(seconds):
    return _select.after(seconds)

func on_future(f):
    return _select.future(f)

# ALEX STANDARD LIBRARY — async.task
#
# Tâches asynchrones nommées et groupes de tâches (concurrence STRUCTURÉE).
#
#   use async.task as task
#   t := task.spawn(telecharger, [url], "dl-1")   # Task : nom, état, annulation, rappels
#   t.add_done_callback((tache) => print(tache.name, tache.state()))
#   print(await t.wait())                          # résultat (ou relance l'erreur)
#
#   g := task.TaskGroup()
#   for u in urls:
#       g.spawn(telecharger, [u])
#   resultats := await g.wait()        # tous les résultats ; au premier échec, les autres sont ANNULÉS et
#                                      # l'erreur est relancée
#
# spawn accepte une async func (sa tâche est reprise) ou une fonction ordinaire (exécutée au prochain tour de
# boucle). Une Task enveloppe un futur asyncio (t.future) : asyncio.timeout(t.future, 2) etc. s'appliquent.
#
# Erreurs : celles des tâches ; InvalidStateError (result avant la fin) ; CancelledError.

from core use len, type
from collections use append
use asyncio

_counter := [0]

# Exécute fn(*args) au prochain tour de boucle ; si c'est une async func, attend sa tâche (et l'annule si la
# tâche enveloppante est annulée : l'annulation n'est pas propagée automatiquement par asyncio).
async func _run_plain(fn, args):
    await asyncio.sleep(0)
    v := _call(fn, args)
    if not asyncio.is_future(v):
        return v
    inner := v
    try:
        return await inner
    catch CancelledError as e:
        asyncio.cancel(inner)
        raise(e.type, e.message)

func _call(fn, args):
    n := len(args)
    if n == 0:
        return fn()
    if n == 1:
        return fn(args[0])
    if n == 2:
        return fn(args[0], args[1])
    if n == 3:
        return fn(args[0], args[1], args[2])
    if n == 4:
        return fn(args[0], args[1], args[2], args[3])
    if n == 5:
        return fn(args[0], args[1], args[2], args[3], args[4])
    if n == 6:
        return fn(args[0], args[1], args[2], args[3], args[4], args[5])
    raise("ArgumentError", "task.spawn : 6 arguments au plus")

func _ignore(e):
    return null

async func _settle(fut):
    try:
        await fut
    catch e:
        return

class Task:
    func init(future, name=null):
        if name == null:
            _counter[0] += 1
            name = "tâche-" + str(_counter[0])
        self.future = future
        self.name = name
        self.created = asyncio.now()
        self._callbacks = []
        self._watching = false

    func done():
        return asyncio.done(self.future)

    func cancelled():
        return asyncio.cancelled(self.future)

    func failed():
        return asyncio.failed(self.future)

    # pending | done | failed | cancelled
    func state():
        if not asyncio.done(self.future):
            return "pending"
        if asyncio.cancelled(self.future):
            return "cancelled"
        if asyncio.failed(self.future):
            return "failed"
        return "done"

    func cancel():
        return asyncio.cancel(self.future)

    # Futur du résultat (await t.wait()).
    func wait():
        return self.future

    # Résultat d'une tâche réussie, sans attendre ; InvalidStateError sinon.
    func result():
        if self.state() != "done":
            raise("InvalidStateError", "Task.result : la tâche " + self.name + " est " + self.state())
        return asyncio.result(self.future)

    # fn(tâche) quand la tâche se termine (tout de suite si c'est déjà le cas, au prochain tour de boucle).
    func add_done_callback(fn):
        append(self._callbacks, fn)
        if not self._watching:
            self._watching = true
            _watch(self)
        return self

async func _watch(t):
    try:
        await t.future
    catch e:
        _ignore(e)
    cbs := t._callbacks
    t._callbacks = []
    t._watching = false
    for cb in cbs:
        cb(t)

# Démarre fn(*args) comme tâche ; renvoie une Task.
func spawn(fn, args=null, name=null):
    if args == null:
        args = []
    return Task(_run_plain(fn, args), name)

# Enveloppe un futur existant.
func wrap(future, name=null):
    return Task(future, name)

class TaskGroup:
    func init(name="groupe"):
        self.name = name
        self.tasks = []
        self._closed = false

    func spawn(fn, args=null, name=null):
        if self._closed:
            raise("InvalidStateError", "TaskGroup.spawn : groupe déjà attendu")
        t := spawn(fn, args, name)
        append(self.tasks, t)
        return t

    func add(future, name=null):
        t := Task(future, name)
        append(self.tasks, t)
        return t

    func cancel_all():
        for t in self.tasks:
            t.cancel()

    # Résultats dans l'ordre. Au premier échec, annule les tâches restantes puis relance l'erreur.
    func wait():
        self._closed = true
        return _group_wait(self)

    func pending():
        return len([t for t in self.tasks if not t.done()])

async func _group_wait(g):
    out := []
    remaining := [t for t in g.tasks]
    while len(remaining) > 0:
        first := asyncio.race([t.future for t in remaining])
        await _settle(first)
        still := []
        for t in remaining:
            if t.done():
                if t.failed() or t.cancelled():
                    for o in remaining:
                        if not o.done():
                            o.cancel()
                    for o in remaining:
                        await _settle(o.future)
                    await t.future
            else:
                append(still, t)
        remaining = still
    for t in g.tasks:
        append(out, t.result())
    return out

# Exécute toutes les fonctions en concurrence (groupe) ; résultats dans l'ordre.
func run_all(fns):
    g := TaskGroup()
    for f in fns:
        g.spawn(f)
    return g.wait()

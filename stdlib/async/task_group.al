# ALEX STANDARD LIBRARY — async.task_group
#
# Groupe de tâches asynchrones à POLITIQUE configurable (complète async.task.TaskGroup) :
#   max_concurrency   au plus N tâches en cours ; les suivantes attendent leur tour (file d'attente)
#   policy            "fail_fast" (défaut) : au premier échec, les autres sont annulées et l'erreur relancée ;
#                     "collect" : toutes vont au bout ; s'il y a des échecs, TaskGroupError résume (détail :
#                     g.errors) ; "ignore" : les échecs sont notés (g.errors), les résultats valent null
#   wait_any          premier résultat, quelle que soit la tâche
#   wait_first_success  premier SUCCÈS (les échecs sont tolérés tant qu'il reste des tâches)
#
#   use async.task_group as tg
#   g := tg.TaskGroup("téléchargements", 4, "collect")    # 4 à la fois
#   for u in urls:
#       g.spawn(telecharger, [u], u)
#   res := await g.wait()                      # résultats dans l'ordre d'ajout
#   print(g.results_by_name()[urls[0]], g.errors)
#   rapide := tg.TaskGroup()
#   rapide.spawn(miroir_a)
#   rapide.spawn(miroir_b)
#   print(await rapide.wait_first_success())   # [nom, valeur] ; les autres sont annulées
#
# Erreurs : TaskGroupError (policy collect), CancelledError, InvalidStateError (groupe déjà attendu),
#           ArgumentError (politique inconnue), toute erreur d'une tâche (fail_fast).

from core use len, type
from collections use append, pop
use asyncio
use async.task as _task

const POLICIES := ["fail_fast", "collect", "ignore"]

class _Entry:
    func init(name, index):
        self.name = name
        self.index = index
        self.future = null

class TaskGroup:
    func init(name="groupe", max_concurrency=null, policy="fail_fast"):
        ok := false
        for p in POLICIES:
            if p == policy:
                ok = true
        if not ok:
            raise("ArgumentError", "TaskGroup : politique inconnue '" + str(policy) + "' (fail_fast, collect, ignore)")
        if max_concurrency != null and (type(max_concurrency) != "int" or max_concurrency < 1):
            raise("ArgumentError", "TaskGroup : max_concurrency >= 1 attendu")
        self.name = name
        self.max_concurrency = max_concurrency
        self.policy = policy
        self.entries = []
        self.errors = []
        self.running = 0
        self.peak = 0
        self._waiters = []
        self._closed = false

    # Ajoute fn(*args) au groupe ; renvoie le futur de son résultat.
    func spawn(fn, args=null, name=null):
        if self._closed:
            raise("InvalidStateError", "TaskGroup.spawn : groupe déjà attendu")
        n := name
        if n == null:
            n = self.name + "-" + str(len(self.entries) + 1)
        e := _Entry(n, len(self.entries))
        a := args
        if a == null:
            a = []
        e.future = _slot(self, fn, a, n)
        append(self.entries, e)
        return e.future

    func size():
        return len(self.entries)

    func pending():
        return len([e for e in self.entries if not asyncio.done(e.future)])

    func cancel_all():
        for e in self.entries:
            if not asyncio.done(e.future):
                asyncio.cancel(e.future)

    func _release():
        self.running -= 1
        if len(self._waiters) > 0:
            w := pop(self._waiters, 0)
            asyncio.resolve(w, true)

    # Résultats dans l'ordre d'ajout, selon la politique.
    func wait():
        self._closed = true
        return _wait(self)

    # {nom: résultat} (tâches réussies seulement).
    func results_by_name():
        out := {}
        for e in self.entries:
            if asyncio.done(e.future) and not asyncio.failed(e.future) and not asyncio.cancelled(e.future):
                out[e.name] = asyncio.result(e.future)
        return out

    func wait_any():
        return _first(self, false)

    func wait_first_success():
        return _first(self, true)

# Attend une place, exécute, rend la place.
async func _slot(g, fn, args, name):
    if g.max_concurrency != null:
        while g.running >= g.max_concurrency:
            w := asyncio.future()
            append(g._waiters, w)
            await w
    g.running += 1
    if g.running > g.peak:
        g.peak = g.running
    t := _task.spawn(fn, args, name)
    try:
        return await t.future
    catch CancelledError as e:
        asyncio.cancel(t.future)
        raise(e)
    finally:
        g._release()

async func _settle(f):
    try:
        await f
    catch e:
        return

async func _wait(g):
    remaining := [e for e in g.entries]
    while len(remaining) > 0:
        await _settle(asyncio.race([e.future for e in remaining]))
        still := []
        for e in remaining:
            if not asyncio.done(e.future):
                append(still, e)
                continue
            if asyncio.failed(e.future) or asyncio.cancelled(e.future):
                err := null
                try:
                    await e.future
                catch x:
                    err = x
                append(g.errors, {"name": e.name, "type": err.type, "message": err.message})
                if g.policy == "fail_fast":
                    for o in remaining:
                        if not asyncio.done(o.future):
                            asyncio.cancel(o.future)
                    for o in remaining:
                        await _settle(o.future)
                    raise(err)
        remaining = still
    out := []
    for e in g.entries:
        if asyncio.failed(e.future) or asyncio.cancelled(e.future):
            append(out, null)
        else:
            append(out, asyncio.result(e.future))
    if g.policy == "collect" and len(g.errors) > 0:
        first := g.errors[0]
        raise("TaskGroupError", g.name + " : " + str(len(g.errors)) + " tâche(s) en échec ; première : " + first["name"] + " : " + first["type"] + " : " + first["message"])
    return out

# Premier terminé ([nom, valeur]) ; success_only : premier succès. Les autres sont annulées.
async func _first(g, success_only):
    g._closed = true
    remaining := [e for e in g.entries]
    last_error := null
    while len(remaining) > 0:
        await _settle(asyncio.race([e.future for e in remaining]))
        still := []
        winner := null
        for e in remaining:
            if not asyncio.done(e.future):
                append(still, e)
            elif winner == null:
                if asyncio.failed(e.future) or asyncio.cancelled(e.future):
                    try:
                        await e.future
                    catch x:
                        last_error = x
                        append(g.errors, {"name": e.name, "type": x.type, "message": x.message})
                    if not success_only:
                        winner = e
                else:
                    winner = e
        if winner != null:
            for o in still:
                asyncio.cancel(o.future)
            for o in still:
                await _settle(o.future)
            return [winner.name, await winner.future]
        remaining = still
    if last_error != null:
        raise(last_error)
    raise("InvalidStateError", "TaskGroup : groupe vide")

# Exécute fns avec au plus max_concurrency à la fois ; résultats dans l'ordre.
func run_limited(fns, max_concurrency, policy="fail_fast"):
    g := TaskGroup("run_limited", max_concurrency, policy)
    for f in fns:
        g.spawn(f)
    return g.wait()

# fn(x) pour chaque élément, au plus max_concurrency à la fois.
func map_limited(fn, items, max_concurrency):
    g := TaskGroup("map_limited", max_concurrency)
    for x in items:
        g.spawn(fn, [x])
    return g.wait()

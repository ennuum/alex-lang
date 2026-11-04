# ALEX STANDARD LIBRARY — async.task_scope
#
# Portée de tâches (concurrence STRUCTURÉE, comme les nurseries de Trio ou StructuredTaskScope de Java) :
# aucune tâche lancée dans une portée ne lui survit. À la sortie, la portée attend toutes ses tâches ; si
# l'une échoue, les autres sont annulées et l'erreur est relancée ; si l'échéance est dépassée, tout est
# annulé et TimeoutError est levée. Une portée porte un jeton d'annulation transmis aux tâches.
#
#   use async.task_scope as ts
#   async func corps(s):
#       s.spawn(telecharger, ["a"])
#       s.spawn(telecharger, ["b"])
#       return "lancé"
#   r := await ts.scoped(corps, 5.0)        # attend a et b (5 s au plus), puis rend "lancé"
#   print(r)
#   s := ts.TaskScope("serveur")
#   t := s.spawn(servir)
#   s.cancel("arrêt")                        # annule tout ce qui tourne dans la portée
#   await s.close()
#
# Erreurs : TimeoutError (échéance), CancelledError, InvalidStateError (spawn après close), erreurs des tâches.

from core use len, type
from collections use append
use asyncio
use async.task as _task
use async.cancellation as _cancel

class TaskScope:
    func init(name="portée", timeout=null):
        self.name = name
        self.timeout = timeout
        self.deadline = null
        if timeout != null:
            self.deadline = asyncio.now() + timeout
        self.tasks = []
        self.source = _cancel.CancellationSource()
        self.token = self.source.token
        self.closed = false
        self.cancelled = false

    func spawn(fn, args=null, name=null):
        if self.closed:
            raise("InvalidStateError", "TaskScope.spawn : portée " + self.name + " fermée")
        t := _task.spawn(fn, args, name)
        append(self.tasks, t)
        return t

    func cancel(reason=null):
        self.cancelled = true
        self.source.cancel(reason)
        for t in self.tasks:
            t.cancel()

    func remaining_time():
        if self.deadline == null:
            return null
        r := self.deadline - asyncio.now()
        if r < 0:
            return 0
        return r

    func active():
        return [t for t in self.tasks if not t.done()]

    # Attend toutes les tâches selon les règles de la portée.
    func close():
        self.closed = true
        return _close(self)

async func _settle(f):
    try:
        await f
    catch e:
        return

async func _close(s):
    while true:
        live := s.active()
        failed := null
        for t in s.tasks:
            if t.done() and t.failed():
                failed = t
                break
        if failed != null:
            s.cancel("échec de " + failed.name)
            for t in s.tasks:
                await _settle(t.future)
            await failed.future
        if len(live) == 0:
            return [t.result() for t in s.tasks if t.state() == "done"]
        r := s.remaining_time()
        if r != null and r <= 0:
            s.cancel("échéance")
            for t in s.tasks:
                await _settle(t.future)
            raise("TimeoutError", "TaskScope " + s.name + " : échéance de " + str(s.timeout) + " s dépassée")
        waiters := [t.future for t in live]
        if r != null:
            append(waiters, asyncio.sleep(r))
        await _settle(asyncio.race(waiters))

# body(portée) ; à la sortie, attend les tâches de la portée (échéance timeout). Une erreur de body annule
# les tâches puis est relancée. Renvoie le résultat de body.
async func scoped(body, timeout=null, name="portée"):
    s := TaskScope(name, timeout)
    result := null
    try:
        result = body(s)
        if asyncio.is_future(result):
            result = await result
    catch e:
        s.cancel("erreur dans la portée")
        for t in s.tasks:
            await _settle(t.future)
        raise(e)
    await s.close()
    return result

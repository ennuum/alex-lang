# ALEX STANDARD LIBRARY — coroutine
#
# Coroutines : des fonctions qui se SUSPENDENT au milieu de leur exécution en rendant une valeur, et
# REPRENNENT là où elles s'étaient arrêtées — dialogue en deux sens entre un producteur et un consommateur,
# machines à états écrites comme du code séquentiel, protocoles pas à pas.
#
# ALEX n'a pas de `yield` : une coroutine est construite sur les tâches async (coroutines natives de la VM,
# docs/ASYNC.md). Son corps est une `async func` qui reçoit un Yielder (coroutine.yield).
#
#   use coroutine as co
#   async func echo(y, prefixe):
#       msg := await y.yield_("prêt")
#       while msg != null:
#           msg = await y.yield_(prefixe + msg)
#       return "terminé"
#   c := co.Coroutine(echo, [">> "])
#   print(await c.resume())            # « prêt »
#   print(await c.send("salut"))       # « >> salut »
#   print(await c.send(null))          # « terminé » (valeur de retour) ; c.state() == "done"
#   c2 := co.Coroutine(echo, [""])
#   await c2.resume()
#   await c2.throw("ValueError", "mauvaise entrée")   # levée DANS le corps, au point de suspension
#   await c2.close()                   # CoroutineExit dans le corps ; état « closed »
#
# resume / send / throw / close rendent des futurs : à utiliser avec await (au niveau supérieur ou dans une
# async func). Voir aussi coroutine.generator (générateurs), coroutine.coroutine_scheduler (planificateur).
# Erreurs : CoroutineError, CoroutineExit, CancelledError, toute erreur du corps (relancée par resume).

from core use type
from collections use append
use asyncio
use coroutine.coroutine_state as _st
use coroutine.coroutine_errors as _e
use coroutine.yield as _y

_ids := [0]

class Coroutine:
    func init(body, args=null, name=null):
        if type(body) != "function":
            raise("TypeError", "Coroutine : le corps doit être une async func (obtenu '" + type(body) + "')")
        _ids[0] += 1
        self.id = _ids[0]
        self.name = name
        if self.name == null:
            self.name = "coroutine-" + str(self.id)
        self._body = body
        self._args = args
        if self._args == null:
            self._args = []
        self._tracker = _st.StateTracker()
        self._in = null        # futur attendu par le corps suspendu
        self._out = null       # futur attendu par celui qui reprend
        self._task = null
        self.result = null
        self.error = null
        self.yields = 0
        self.last_value = null
        self.yielder = _y.Yielder(self)

    func state():
        return self._tracker.state

    func is_finished():
        return _st.is_finished(self._tracker.state)

    func is_suspended():
        return self._tracker.state == _st.SUSPENDED

    func _need_resumable(fn):
        s := self._tracker.state
        if s == _st.RUNNING:
            _e.coroutine_error("Coroutine." + fn, self.name + " est déjà en cours d'exécution")
        if _st.is_finished(s):
            _e.coroutine_error("Coroutine." + fn, self.name + " est terminée (" + s + ")")

    # Appelé par le corps (Yielder.yield_).
    func _suspend(value):
        if self._tracker.state != _st.RUNNING:
            _e.coroutine_error("yield_", "la coroutine " + self.name + " ne s'exécute pas")
        self.yields += 1
        self.last_value = value
        self._in = asyncio.future()
        waiter := self._in
        self._tracker.to(_st.SUSPENDED)
        asyncio.resolve(self._out, ["yield", value])
        return _await_message(waiter)

    func _deliver(message):
        self._out = asyncio.future()
        out := self._out
        if self._tracker.state == _st.CREATED:
            self._tracker.to(_st.RUNNING)
            self._task = _run(self)
        else:
            self._tracker.to(_st.RUNNING)
            asyncio.resolve(self._in, message)
        return _await_outcome(self, out)

    # Démarre ou reprend ; futur de la prochaine valeur rendue (ou de la valeur finale).
    func resume(value=null):
        self._need_resumable("resume")
        if self._tracker.state == _st.CREATED and value != null:
            _e.coroutine_error("Coroutine.resume", "la première reprise ne peut pas envoyer de valeur (rien ne l'attend)")
        return self._deliver(["value", value])

    func send(value):
        return self.resume(value)

    # Lève (error_type, message) dans le corps, au point de suspension.
    func throw(error_type, message=""):
        self._need_resumable("throw")
        if self._tracker.state == _st.CREATED:
            self._tracker.to(_st.CLOSED)
            raise(error_type, message)
        return self._deliver(["throw", error_type, message])

    # Ferme : CoroutineExit est levée dans le corps suspendu ; futur terminé quand le corps est sorti.
    func close():
        s := self._tracker.state
        if _st.is_finished(s):
            return asyncio.sleep(0)
        if s == _st.CREATED:
            self._tracker.to(_st.CLOSED)
            return asyncio.sleep(0)
        if s == _st.RUNNING:
            _e.coroutine_error("Coroutine.close", "impossible de fermer une coroutine pendant son exécution")
        return _close(self)

    func cancel():
        if self._task != null:
            asyncio.cancel(self._task)
        if not self.is_finished():
            self._tracker.to(_st.CANCELLED)

    func history():
        return self._tracker.history[:]

    func __str__():
        return "Coroutine(" + self.name + ", " + self.state() + ")"

async func _await_message(waiter):
    msg := await waiter
    if msg[0] == "throw":
        raise(msg[1], msg[2])
    if msg[0] == "close":
        raise(_e.EXIT, "coroutine fermée")
    return msg[1]

async func _run(co):
    try:
        r := await co._body(co.yielder, *co._args)
        co.result = r
        co._tracker.to(_st.DONE)
        asyncio.resolve(co._out, ["return", r])
    catch e:
        if e.type == _e.EXIT:
            if co._tracker.state != _st.CLOSED:
                co._tracker.to(_st.CLOSED)
            asyncio.resolve(co._out, ["closed", null])
            return
        co.error = e
        if co._tracker.state == _st.RUNNING:
            co._tracker.to(_st.FAILED)
        asyncio.resolve(co._out, ["error", e])

async func _await_outcome(co, out):
    r := await out
    if r[0] == "error":
        raise(r[1])
    return r[1]

async func _close(co):
    co._out = asyncio.future()
    out := co._out
    co._tracker.to(_st.RUNNING)
    asyncio.resolve(co._in, ["close"])
    r := await out
    if r[0] == "yield":
        _force_closed(co)
        _e.coroutine_error("Coroutine.close", "le corps a ignoré CoroutineExit et s'est de nouveau suspendu")
    if r[0] == "error":
        raise(r[1])
    return null

func _force_closed(co):
    co._tracker.state = _st.CLOSED

func coroutine(body, args=null, name=null):
    return Coroutine(body, args, name)

# Reprend la coroutine jusqu'à la fin ; liste de toutes les valeurs rendues (la valeur finale n'y est pas).
async func run_to_end(co, value=null):
    out := []
    v := await co.resume()
    while not co.is_finished():
        append(out, v)
        v = await co.resume(value)
    return out

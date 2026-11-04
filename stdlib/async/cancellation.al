# ALEX STANDARD LIBRARY — async.cancellation
#
# Annulation COOPÉRATIVE : une source d'annulation (CancellationSource) distribue un jeton (CancellationToken)
# aux tâches ; quand la source annule, chaque tâche le constate (cancelled, raise_if_cancelled) ou réagit
# (on_cancel), et les opérations enveloppées par guard() sont annulées.
#
#   use async.cancellation as cancel
#   src := cancel.CancellationSource()
#   async func travail(jeton):
#       for lot in lots:
#           jeton.raise_if_cancelled()          # CancelledError si annulé
#           await traiter(lot)
#   t := travail(src.token)
#   src.cancel_after(5.0)                       # ou src.cancel("arrêt demandé")
#   r := await cancel.guard(telecharger(url), src.token)   # annule le téléchargement si le jeton l'est
#   lie := cancel.linked([jeton_a, jeton_b])               # annulé dès que l'un l'est
#
# Erreurs : CancelledError (raise_if_cancelled, guard).

from core use len, type
from collections use append
use asyncio

class CancellationToken:
    func init():
        self._cancelled = false
        self.reason = null
        self._callbacks = []
        self._waiters = []

    func cancelled():
        return self._cancelled

    func raise_if_cancelled():
        if self._cancelled:
            msg := "opération annulée"
            if self.reason != null:
                msg = msg + " : " + str(self.reason)
            raise("CancelledError", msg)

    # fn(raison) à l'annulation (tout de suite si déjà annulé). Renvoie une fonction qui retire l'abonnement.
    func on_cancel(fn):
        if self._cancelled:
            fn(self.reason)
            return () => null
        entry := [fn]
        append(self._callbacks, entry)
        return () => self._unsubscribe(entry)

    func _unsubscribe(entry):
        self._callbacks = [c for c in self._callbacks if c != entry]

    # Futur terminé à l'annulation (valeur : la raison).
    func wait():
        f := asyncio.future()
        if self._cancelled:
            asyncio.resolve(f, self.reason)
        else:
            append(self._waiters, f)
        return f

    func _fire(reason):
        if self._cancelled:
            return false
        self._cancelled = true
        self.reason = reason
        for w in self._waiters:
            asyncio.resolve(w, reason)
        self._waiters = []
        cbs := self._callbacks
        self._callbacks = []
        for c in cbs:
            f := c[0]
            f(reason)
        return true

class CancellationSource:
    func init():
        self.token = CancellationToken()
        self._timer = null

    # Annule ; renvoie false si c'était déjà fait.
    func cancel(reason=null):
        if self._timer != null:
            asyncio.cancel(self._timer)
            self._timer = null
        return self.token._fire(reason)

    # Annule automatiquement après seconds secondes (remplace un délai précédent).
    func cancel_after(seconds, reason="délai dépassé"):
        if self._timer != null:
            asyncio.cancel(self._timer)
        self._timer = _cancel_later(self, seconds, reason)
        return self

    func cancelled():
        return self.token.cancelled()

async func _cancel_later(src, seconds, reason):
    await asyncio.sleep(seconds)
    src._timer = null
    src.cancel(reason)

# Jeton jamais annulé (paramètre par défaut).
func none():
    return CancellationToken()

func source():
    return CancellationSource()

# Source annulée automatiquement après seconds.
func timeout_source(seconds):
    return CancellationSource().cancel_after(seconds)

# Jeton annulé dès que l'un des jetons l'est.
func linked(tokens):
    src := CancellationSource()
    for t in tokens:
        t.on_cancel((reason) => src.cancel(reason))
    return src.token

# Attend f ; si le jeton est annulé avant, annule f et lève CancelledError.
async func guard(f, token):
    if token.cancelled():
        asyncio.cancel(f)
        token.raise_if_cancelled()
    w := token.wait()
    first := asyncio.race([f, w])
    try:
        await first
    catch e:
        first = null
    if asyncio.done(f):
        asyncio.cancel(w)
        return await f
    asyncio.cancel(f)
    token.raise_if_cancelled()
    return await f

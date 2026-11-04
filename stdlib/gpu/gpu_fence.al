# ALEX STANDARD LIBRARY — gpu.gpu_fence
#
# Synchronisation entre le programme et les files de commandes (gpu.gpu_queue) :
#   - Fence : barrière binaire, signalée quand une soumission est terminée ; wait(timeout) fait avancer la file
#     propriétaire jusqu'à ce point (exécution différée) ; reset pour réutiliser ; état d'erreur si une commande
#     a échoué (l'erreur est relancée par wait) ;
#   - Timeline : sémaphore à valeur croissante (comme les timeline semaphores de Vulkan) : signal(v),
#     wait(v), value() ; plusieurs files peuvent l'attendre ;
#   - wait_all / wait_any sur une liste de barrières.
#
#   use gpu.gpu_fence as gf
#   f := file.submit(cmds)             # Fence
#   f.wait(2.0)                        # FenceTimeout si la file n'arrive pas à ce point
#   tl := gf.Timeline()
#   tl.signal(3)
#   print(tl.reached(2))               # true
#
# Erreurs : FenceTimeout, ArgumentError (valeur de timeline décroissante), erreur de la commande qui a échoué.

from core use len
from collections use append
use asyncio as _as
use time as _time

class Fence:
    func init(name="fence", queue=null, seq=0):
        self.name = name
        self.queue = queue
        self.seq = seq
        self.signaled = false
        self.error = null
        self.signaled_at = null
        self.callbacks = []

    func signal():
        if self.signaled:
            return
        self.signaled = true
        self.signaled_at = _as.now()
        for cb in self.callbacks:
            cb(self)
        self.callbacks = []

    func fail(err_type, message):
        self.error = [err_type, message]
        self.signal()

    func failed():
        return self.error != null

    func is_signaled():
        return self.signaled

    # Rappel quand la barrière est signalée (immédiat si elle l'est déjà).
    func on_signal(fn):
        if self.signaled:
            fn(self)
        else:
            append(self.callbacks, fn)
        return self

    # Attend la barrière ; timeout en secondes (null : sans limite). La file propriétaire est avancée jusqu'à
    # la soumission correspondante. Relance l'erreur d'une commande échouée.
    func wait(timeout=null):
        start := _as.now()
        while not self.signaled:
            q := self.queue
            progressed := false
            if q != null:
                progressed = q.step()
            if self.signaled:
                break
            if timeout != null and _as.now() - start >= timeout:
                raise("FenceTimeout", "barrière « " + self.name + " » non signalée après " + str(timeout) + " s")
            if not progressed:
                if q == null or q.idle():
                    if timeout == null:
                        raise("FenceTimeout", "barrière « " + self.name + " » : rien ne la signalera (file vide)")
                _time.sleep(0.001)
        if self.error != null:
            raise(self.error[0], self.error[1])
        return true

    func reset():
        self.signaled = false
        self.error = null
        self.signaled_at = null

    func describe():
        st := "en attente"
        if self.signaled:
            st = "signalée"
            if self.error != null:
                st = "échouée (" + self.error[0] + ")"
        return "Fence " + self.name + " #" + str(self.seq) + " : " + st

func signaled_fence(name="fence"):
    f := Fence(name)
    f.signal()
    return f

func wait_all(fences, timeout=null):
    start := _as.now()
    for f in fences:
        rest := null
        if timeout != null:
            rest = timeout - (_as.now() - start)
            if rest < 0:
                rest = 0.0
        f.wait(rest)
    return true

# Indice de la première barrière signalée.
func wait_any(fences, timeout=null):
    start := _as.now()
    while true:
        i := 0
        while i < len(fences):
            if fences[i].is_signaled():
                return i
            i += 1
        progressed := false
        for f in fences:
            q := f.queue
            if q != null and q.step():
                progressed = true
                break
        if timeout != null and _as.now() - start >= timeout:
            raise("FenceTimeout", "wait_any : aucune barrière signalée après " + str(timeout) + " s")
        if not progressed:
            all_idle := true
            for f in fences:
                q := f.queue
                if q != null and not q.idle():
                    all_idle = false
            if all_idle and timeout == null:
                raise("FenceTimeout", "wait_any : rien ne signalera ces barrières")
            _time.sleep(0.001)

class Timeline:
    func init(initial=0, name="timeline"):
        self.name = name
        self.current = initial
        self.waiters = []

    func value():
        return self.current

    func reached(v):
        return self.current >= v

    func signal(v):
        if v < self.current:
            raise("ArgumentError", "timeline « " + self.name + " » : valeur décroissante " + str(v) + " < " + str(self.current))
        self.current = v
        keep := []
        for w in self.waiters:
            if self.current >= w[0]:
                cb := w[1]
                cb(v)
            else:
                append(keep, w)
        self.waiters = keep

    func on_value(v, fn):
        if self.current >= v:
            fn(self.current)
        else:
            append(self.waiters, [v, fn])

    # Attend que la valeur atteigne v ; queues : files à faire avancer pendant l'attente.
    func wait(v, timeout=null, queues=null):
        start := _as.now()
        while self.current < v:
            progressed := false
            if queues != null:
                for q in queues:
                    if q.step():
                        progressed = true
            if self.current >= v:
                break
            if timeout != null and _as.now() - start >= timeout:
                raise("FenceTimeout", "timeline « " + self.name + " » : " + str(v) + " non atteint (valeur " + str(self.current) + ")")
            if not progressed:
                if timeout == null:
                    raise("FenceTimeout", "timeline « " + self.name + " » : " + str(v) + " ne sera jamais atteint")
                _time.sleep(0.001)
        return self.current

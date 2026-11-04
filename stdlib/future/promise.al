# ALEX STANDARD LIBRARY — future.promise
#
# Promesses : un futur que l'on complète soi-même, plus tard, depuis un autre endroit du programme.
#   - Promise       : pour les tâches async d'un même fil (futur asyncio) ;
#   - ThreadPromise : complétée par un AUTRE FIL (thread) et attendue ici, de façon bloquante (wait) ou async.
#
#   use future.promise as pr
#   p := pr.Promise()
#   rappel_quand_pret((v) => p.resolve(v))
#   print(await p.future)
#
#   tp := pr.ThreadPromise()
#   thread.spawn(calcul, [tp.share()])        # dans le fil : pr.attach(ids).resolve(resultat)
#   print(tp.wait(5.0))                       # ou : await tp.as_future()
#
# Une promesse ne se complète qu'une fois : resolve / reject / cancel renvoient false si elle l'était déjà.
#
# Erreurs : wait / await relancent l'erreur de reject ; TimeoutError (wait) ; CancelledError.

from core use type
use asyncio
use _native_sync as _s

class Promise:
    func init():
        self.future = asyncio.future()

    func resolve(value=null):
        return asyncio.resolve(self.future, value)

    func reject(error_type, message=""):
        return asyncio.reject(self.future, error_type, message)

    func cancel():
        return asyncio.cancel(self.future)

    func settled():
        return asyncio.done(self.future)

    # Complète avec l'issue de fn() (valeur, ou exception de fn) ; renvoie true si la promesse était en attente.
    func settle_with(fn):
        try:
            return self.resolve(fn())
        catch e:
            return self.reject(e.type, e.message)

    # Suit un autre futur : même issue.
    func follow(f):
        _follow(self, f)
        return self

async func _follow(p, f):
    try:
        p.resolve(await f)
    catch e:
        p.reject(e.type, e.message)

func promise():
    return Promise()

# Futur déjà réussi / déjà échoué.
func resolved(value=null):
    f := asyncio.future()
    asyncio.resolve(f, value)
    return f

func rejected(error_type, message=""):
    f := asyncio.future()
    asyncio.reject(f, error_type, message)
    return f

# ---------------------------------------------------------------- entre fils
# Etat dans une AtomicReference native : null (en attente), [true, valeur], [false, type, message].
class ThreadPromise:
    func init(ids=null):
        if ids != null:
            self._ref = ids[0]
            self._event = ids[1]
        else:
            self._ref = _s.ref_new(null)
            self._event = _s.event_new(false)

    # Identifiants à passer au fil qui complétera la promesse.
    func share():
        return [self._ref, self._event]

    func _settle(state):
        r := _s.ref_cas(self._ref, null, state)
        if r[0]:
            _s.event_set(self._event)
        return r[0]

    func resolve(value=null):
        return self._settle([true, value])

    func reject(error_type, message=""):
        return self._settle([false, error_type, message])

    func settled():
        return _s.event_is_set(self._event)

    # Attend l'issue (bloque ce fil) ; relance l'erreur ; TimeoutError après timeout secondes.
    func wait(timeout=null):
        if _s.event_wait(self._event, timeout) != 1:
            raise("TimeoutError", "ThreadPromise.wait : pas d'issue dans le délai")
        st := _s.ref_load(self._ref)
        if st[0]:
            return st[1]
        raise(st[1], st[2])

    # Futur asyncio de l'issue (les autres tâches continuent pendant l'attente).
    func as_future():
        return _thread_promise_future(self)

async func _thread_promise_future(tp):
    pause := 0.0005
    while not tp.settled():
        await asyncio.sleep(pause)
        if pause < 0.02:
            pause = pause * 2
    return tp.wait(0)

func attach(ids):
    return ThreadPromise(ids)

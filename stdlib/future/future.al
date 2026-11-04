# ALEX STANDARD LIBRARY — future
#
# Futurs : composer des résultats asynchrones (futurs et tâches asyncio) sans écrire soi-même les tâches
# d'attente. Toutes les fonctions renvoient un NOUVEAU futur, à attendre avec await.
#
#   use future
#   f := future.then(telecharger(url), (texte) => len(texte))     # transforme le résultat
#   g := future.catch_error(f, (type, msg) => 0)                    # remplace une erreur par une valeur
#   h := future.finally_do(g, () => print("fini"))
#   n := await h
#   tout := await future.all([a, b, c])               # comme asyncio.gather
#   premier := await future.any([a, b, c])            # premier SUCCÈS (échoue si tous échouent)
#   issues := await future.all_settled([a, b])        # liste de future.result.Result
#   v := await future.delay(0.5, "prêt")
#   print(future.state(h))                            # pending | done | failed | cancelled
#
# Voir aussi : future.promise (Promise, ThreadPromise), future.shared_future (SharedFuture, lazy),
# future.result (Result : Ok / Err), thread.thread_pool (ThreadFuture).
#
# Erreurs : celles des futurs composés ; AggregateError (any : tous ont échoué) ; TimeoutError (with_timeout).

from core use len, type
from collections use append
use asyncio
use future.result as _res
use future.promise as _pr

func is_future(x):
    return asyncio.is_future(x)

func state(f):
    if not asyncio.done(f):
        return "pending"
    if asyncio.cancelled(f):
        return "cancelled"
    if asyncio.failed(f):
        return "failed"
    return "done"

func resolved(value=null):
    return _pr.resolved(value)

func rejected(error_type, message=""):
    return _pr.rejected(error_type, message)

# Futur de fn(valeur de f) ; si fn renvoie un futur, il est attendu à son tour.
async func then(f, fn):
    v := fn(await f)
    if asyncio.is_future(v):
        v = await v
    return v

# Si f échoue : fn(type, message) devient le résultat (ou son futur) ; sinon la valeur de f.
async func catch_error(f, fn):
    try:
        return await f
    catch e:
        v := fn(e.type, e.message)
        if asyncio.is_future(v):
            v = await v
        return v

# Exécute fn() quand f se termine, quelle que soit l'issue ; l'issue de f est conservée.
async func finally_do(f, fn):
    try:
        return await f
    finally:
        v := fn()
        if asyncio.is_future(v):
            await v

func map(f, fn):
    return then(f, fn)

async func all(futures):
    out := []
    for f in futures:
        append(out, await f)
    return out

# Résultats sous forme de Result (Ok / Err), dans l'ordre ; ne lève jamais.
async func all_settled(futures):
    out := []
    for f in futures:
        append(out, await _res.from_future(f))
    return out

# Premier futur à RÉUSSIR ; AggregateError si tous échouent. Les autres ne sont pas annulés.
async func any(futures):
    if len(futures) == 0:
        raise("AggregateError", "future.any : liste vide")
    pending := [f for f in futures]
    errors := []
    while len(pending) > 0:
        winner := asyncio.race(pending)
        try:
            await winner
        catch e:
            winner = null
        still := []
        for f in pending:
            if asyncio.done(f):
                if not asyncio.failed(f) and not asyncio.cancelled(f):
                    return asyncio.result(f)
                append(errors, f)
            else:
                append(still, f)
        pending = still
    msgs := []
    for f in errors:
        r := await _res.from_future(f)
        append(msgs, r.error_type + ": " + r.message)
    raise("AggregateError", "future.any : tous ont échoué (" + str(len(msgs)) + ") : " + str(msgs))

# Premier futur à se terminer (succès ou échec).
func race(futures):
    return asyncio.race(futures)

# Futur de valeur après seconds secondes.
async func delay(seconds, value=null):
    await asyncio.sleep(seconds)
    return value

# Suit f ou échoue en TimeoutError après seconds (f est alors annulé).
func with_timeout(f, seconds):
    return asyncio.timeout(f, seconds)

# Annule f (renvoie false s'il était déjà terminé).
func cancel(f):
    return asyncio.cancel(f)

# Futur de l'issue de fn() calculée au prochain tour de boucle (fn ordinaire ou async).
async func defer(fn):
    await asyncio.sleep(0)
    v := fn()
    if asyncio.is_future(v):
        v = await v
    return v

# Attend f et renvoie un Result (jamais d'exception).
func settle(f):
    return _res.from_future(f)

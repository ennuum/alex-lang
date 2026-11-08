# ALEX STANDARD LIBRARY — thread.offload
#
# Calcul lourd (ou E/S bloquante) hors de la boucle async : la fonction s'exécute sur un fil d'une réserve (thread.thread_pool,
# vrais cœurs), le gestionnaire l'attend avec await, et le serveur continue de servir les autres requêtes.
#
#   use thread.offload as offload
#   use calculs                                  # module qui définit miniature(chemin, largeur)
#
#   async func vignette(req):
#       octets := await offload.run(calculs.miniature, [req.query_param("f"), 200])
#       return response.bytes(octets, "image/png")
#
# Règles des fils ALEX (voir thread.thread_pool) : la fonction est de PREMIER NIVEAU, de préférence dans un module
# à part (le module de la fonction est réimporté dans chaque fil : un fichier qui lance le serveur au niveau
# supérieur doit protéger ce code par `if thread.is_main():`) ; arguments et résultat sont COPIÉS (null, bool,
# nombres, str, list, tuple, dict). Une exception dans le fil est relancée par await (même type).
#
# web.server relève les résultats à chaque tour de sa boucle async (poll) ; sans serveur, la tâche rendue par run
# se relève elle-même (intervalle de 0,5 à 20 ms).
#
# configure(workers) : taille de la réserve par défaut (fils par fonction ; défaut : nombre de cœurs) ;
# run_on(réserve, fn, args) : sur une réserve à soi (ThreadPool), par exemple un fil unique qui garde une
# connexion (database.async_database) ; shutdown() : arrêt de la réserve par défaut.

from core use len, type
from collections use append, keys
use asyncio as _aio
use thread.thread_pool as _tp

_state := {"pool": null, "workers": null, "pending": []}   # pending : [réserve, ThreadFuture, promesse]

# Taille de la réserve (fils par fonction) ; à appeler avant le premier run. null : nombre de cœurs.
func configure(workers=null):
    if _state["pool"] != null:
        raise("ThreadError", "offload.configure : réserve déjà démarrée")
    _state["workers"] = workers

func _pool():
    if _state["pool"] == null:
        _state["pool"] = _tp.ThreadPool(_state["workers"], "offload")
    return _state["pool"]

# Exécute fn(*args) sur un fil ; rend une tâche à attendre (résultat de fn, ou son exception).
func run(fn, args=null):
    return run_on(_pool(), fn, args)

# Comme run, sans tâche async : rend la promesse (asyncio.future) que poll() termine ; pour une boucle qui relève
# elle-même les résultats (web.server : poignées de main TLS). asyncio.done / result pour la lire.
func submit(fn, args=null):
    tf := _pool().submit(fn, args if args != null else [])
    promise := _aio.future()
    append(_state["pending"], [_pool(), tf, promise])
    return promise

# Comme run, sur une réserve donnée (thread.thread_pool.ThreadPool).
func run_on(pool, fn, args=null):
    tf := pool.submit(fn, args if args != null else [])
    promise := _aio.future()
    append(_state["pending"], [pool, tf, promise])
    return _wait(promise)

async func _wait(promise):
    pause := 0.0005
    while not _aio.done(promise):
        poll()
        if _aio.done(promise):
            break
        await _aio.race([promise, _aio.sleep(pause)])
        if pause < 0.02:
            pause = pause * 2
    return await promise

# Nombre de calculs en cours.
func pending():
    return len(_state["pending"])

# Relève les résultats arrivés et termine leurs promesses (appelé par la boucle du serveur à chaque tour).
func poll():
    if len(_state["pending"]) == 0:
        return 0
    seen := []
    for p in _state["pending"]:
        if not (p[0] in seen):
            append(seen, p[0])
            p[0]._collect(0)
    done := 0
    kept := []
    for p in _state["pending"]:
        pool := p[0]
        job := p[1].job
        r := pool._results[job] if job in pool._results else null
        if r == null:
            append(kept, p)
            continue
        pool._results = _without(pool._results, job)
        if r[0]:
            _aio.resolve(p[2], r[1])
        else:
            _aio.reject(p[2], r[1], r[2] + " [offload]")
        done += 1
    _state["pending"] = kept
    return done

# Arrête la réserve (les calculs en cours finissent).
func shutdown(wait=true):
    if _state["pool"] != null:
        _state["pool"].shutdown(wait)
        _state["pool"] = null

func _without(d, key):
    out := {}
    for k in keys(d):
        if k != key:
            out[k] = d[k]
    return out

# ALEX STANDARD LIBRARY — async.executor
#
# Exécuter un travail BLOQUANT ou de CALCUL hors de la boucle d'événements, sur des fils parallèles, et l'attendre
# comme un futur : les autres tâches async continuent pendant ce temps.
#
#   use async.executor as ex
#   func hacher(chemin):                       # fonction de PREMIER NIVEAU (exécutée dans un autre fil)
#       return crypto.sha256(file.read(chemin))
#   async func main():
#       h := await ex.run_in_thread(hacher, ["gros.iso"])
#       tous := await ex.map(hacher, fichiers)        # en parallèle
#   if thread.is_main():
#       await main()
#
# Un exécuteur partagé (default()) est créé à la première utilisation (un fil par cœur et par fonction) ;
# Executor(n) en crée un dédié. Arguments et résultats sont copiés (règles de thread).
#
# Erreurs : celles de la fonction (relancées par await), ThreadError, TimeoutError.

from core use len
from collections use append
use thread.thread_pool as _tp

class Executor:
    func init(workers=null, name="executor"):
        self.pool = _tp.ThreadPool(workers, name)

    # Futur du résultat de fn(*args) exécutée sur un fil de l'exécuteur.
    func run(fn, args=null):
        return self.pool.submit(fn, args).as_future()

    # Futur de la liste [fn(x) for x in items], calculée en parallèle.
    func map(fn, items):
        futures := [self.pool.submit(fn, [x]).as_future() for x in items]
        return _gather(futures)

    func shutdown(wait=true):
        self.pool.shutdown(wait)

async func _gather(futures):
    out := []
    for f in futures:
        append(out, await f)
    return out

_default := [null]

func default():
    if _default[0] == null:
        _default[0] = Executor(null, "async-executor")
    return _default[0]

func run_in_thread(fn, args=null):
    return default().run(fn, args)

func map(fn, items):
    return default().map(fn, items)

func shutdown_default():
    if _default[0] != null:
        _default[0].shutdown(true)
        _default[0] = null

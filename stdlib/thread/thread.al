# ALEX STANDARD LIBRARY — thread
#
# Fils d'exécution PARALLÈLES (un fil système par fil, plusieurs cœurs), isolés : chacun a sa propre VM, les
# valeurs qui passent d'un fil à l'autre sont copiées (docs/CONCURRENCY.md). Ce paquet réunit :
#   - concurrency.thread : Thread, spawn, join, boîtes aux lettres, Channel entre fils, parallel_map ;
#   - thread.thread_pool : ThreadPool (réserve de fils, ThreadFuture) ;
#   - thread.thread_local : ThreadLocal ;  thread.thread_info : informations sur les fils.
#
#   use thread
#   func carre(n):
#       return n * n
#   if thread.is_main():                  # chaque fil réimporte ce module : protéger le programme principal
#       t := thread.spawn(carre, [12])
#       print(t.join())                   # 144
#       pool := thread.pool(4)
#       print(pool.map(carre, [1, 2, 3]))
#       pool.shutdown()
#
# Partager de l'état modifiable entre fils : atomic (compteurs, drapeaux), mutex (verrous), synchronization
# (sémaphores, conditions, barrières...), ou des messages (Channel).

use concurrency.thread as _ct
use thread.thread_pool as _pool
use thread.thread_local as _local
use thread.thread_info as _info
use os as _os

func supported():
    return _ct.supported()

func is_main():
    return _ct.is_main()

func current_id():
    return _ct.current_id()

func current():
    return _info.current()

func cpu_count():
    return _ct.cpu_count()

func active_count():
    return _ct.active_count()

# Nouveau fil (pas encore démarré) : Thread(cible, args, nom).start().
func Thread(target, args=null, name=null):
    return _ct.Thread(target, args, name)

func spawn(target, args=null, name=null):
    return _ct.spawn(target, args, name)

# Attend tous les fils ; renvoie leurs résultats dans l'ordre (relance la première erreur).
func join_all(threads, timeout=null):
    return [t.join(timeout) for t in threads]

func parallel_map(f, items, workers=null):
    return _ct.parallel_map(f, items, workers)

# Boîte aux lettres du fil courant (côté fil) : message vers / depuis le parent.
func send(value, timeout=null):
    return _ct.send(value, timeout)

func receive(timeout=null):
    return _ct.receive(timeout)

# Canal entre fils (capacité 0 : sans limite) ; attach_channel(id) dans un autre fil.
func Channel(capacity=0):
    return _ct.Channel(capacity)

func attach_channel(id):
    return _ct.attach(id)

func pool(workers=null, name="pool"):
    return _pool.ThreadPool(workers, name)

func local(default=null, factory=null):
    return _local.ThreadLocal(default, factory)

# Suspend le fil courant (secondes).
func sleep(seconds):
    _os.sleep(seconds)

# Cède le processeur aux autres fils.
func yield_now():
    _os.sleep(0)

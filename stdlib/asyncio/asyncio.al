# ALEX STANDARD LIBRARY — asyncio
# Futurs, tâches et boucle d'événements coopérative (voir docs/ASYNC.md).
#
# Une `async func` appelée renvoie une TÂCHE (un futur) qui démarre au prochain tour de boucle ; `await` la
# suspend jusqu'à sa fin. Le programme principal est lui-même une coroutine : `await` est permis au niveau
# supérieur d'un module.
#
#   use asyncio
#   async func fetch(n):
#       await asyncio.sleep(0.1)
#       return n * 2
#   print(await fetch(21))        # 42
#
# Les primitives (futurs, minuteurs) sont fournies par le runtime (`_native_asyncio`) ; le reste est écrit en ALEX.

use _native_asyncio as _a

# --- futurs / promesses -------------------------------------------------------------------------------------

# Crée une promesse : un futur que l'on complète soi-même avec resolve() ou reject().
func future():
    return _a.future()

# Complète avec une valeur. Renvoie false si le futur était déjà terminé (le premier gagne).
func resolve(f, value):
    return _a.resolve(f, value)

# Complète avec une exception de type libre (ex. "ValueError"). Même retour que resolve().
func reject(f, type, message):
    return _a.reject(f, type, message)

# Demande l'annulation : la tâche reçoit un CancelledError à son point de suspension (rattrapable). Renvoie false
# si le futur est déjà terminé.
func cancel(f):
    return _a.cancel(f)

func done(f):
    return _a.done(f)

func cancelled(f):
    return _a.cancelled(f)

func failed(f):
    return _a.failed(f)

# Valeur d'un futur terminé avec succès, sans attendre. ArgumentError si ce n'est pas (encore) le cas.
func result(f):
    return _a.result(f)

# Vrai si `f` est en attente et que son résultat n'intéresse plus personne : la tâche qui l'attendait a été
# annulée (et aucune autre ne l'attend), ou tous les futurs construits dessus (timeout, race) le sont. Un futur
# jamais attendu n'est PAS abandonné. Sert aux canaux à ne pas livrer une valeur à un attendant fantôme.
func abandoned(f):
    return _a.abandoned(f)

func is_future(x):
    return _a.is_future(x)

func is_task(x):
    return _a.is_task(x)

# --- temps --------------------------------------------------------------------------------------------------

# Futur terminé après `seconds` secondes ; `await asyncio.sleep(0)` cède la main aux autres tâches.
func sleep(seconds):
    return _a.sleep(seconds)

# Horloge monotone, en secondes.
func now():
    return _a.now()

# Futur qui suit `f`, ou échoue en TimeoutError après `seconds` (et annule alors `f`).
#   r := await asyncio.timeout(fetch(1), 2.0)
func timeout(f, seconds):
    return _a.timeout(f, seconds)

# --- composition --------------------------------------------------------------------------------------------

# Futur qui suit le PREMIER des futurs de la liste à se terminer (succès, échec ou annulation).
func race(futures):
    return _a.race(futures)

# Attend tous les futurs de la liste et renvoie la liste des résultats, dans l'ordre de la liste. Si l'un
# échoue, son exception est relancée à sa position ; les autres tâches continuent (annulez-les au besoin).
async func gather(futures):
    out := []
    for f in futures:
        __list_append(out, await f)
    return out

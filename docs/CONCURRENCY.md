# Concurrence : `concurrency.thread`, `mutex`, `semaphore`, `atomic`, `async`

Deux niveaux, qui se combinent :

| | Tâches async (`async func`, `await`) | Fils (`concurrency.thread`) |
|---|---|---|
| Exécution | coopérative, un seul fil, bascule aux `await` | **parallèle**, un fil système par fil, plusieurs cœurs |
| Mémoire | partagée (mêmes objets) | **isolée** : une VM par fil, valeurs copiées |
| Pour | attendre beaucoup de choses (réseau, minuteurs) | calculer en parallèle, isoler un travail |
| Synchronisation | `mutex`, `semaphore`, `async.Event/Barrier/Queue`, `channel` | messages : boîte aux lettres, `thread.Channel` |

## `concurrency.thread` — fils parallèles isolés

```
use concurrency.thread as thread

func carre(n):                    # fonction de PREMIER NIVEAU d'un module
    return n * n

if thread.is_main():              # le fil importe ce script : son code de haut niveau ne doit pas se relancer
    t := thread.spawn(carre, [12])
    print(t.join())               # 144
    print(thread.parallel_map(carre, [1, 2, 3, 4]))   # [1, 4, 9, 16], sur plusieurs cœurs
```

| Appel | Sens |
|---|---|
| `spawn(f, args, nom)` / `Thread(f, args, nom).start()` | lance `f(*args)` dans un nouveau fil |
| `t.join(délai)` | résultat de `f`, ou relance son erreur (type et message, `[fil n : nom]` ajouté ; `t.trace()` : trace du fil) |
| `t.is_alive()`, `t.id`, `t.name` | état |
| `t.send(v)` / `t.receive(délai)` | boîte aux lettres, côté parent |
| `thread.send(v)` / `thread.receive(délai)` | la même, côté fil |
| `Channel(capacité)`, `ch.send`, `ch.receive`, `ch.try_receive`, `ch.close`, `ch.size` | canal entre fils (capacité 0 : sans limite) |
| `thread.attach(id)` | canal reçu par son identifiant (`ch.id`) |
| `parallel_map(f, éléments, fils)` | `f` sur chaque élément, au plus `fils` à la fois, résultats dans l'ordre |
| `is_main()`, `current_id()`, `cpu_count()`, `active_count()` | informations |

- **Isolation.** Chaque fil a sa propre VM : son tas, son ramasse-miettes, son ordonnanceur async. Rien n'est
  partagé ; ce qui passe d'un fil à l'autre est **copié** : `null`, `bool`, `int`, `float`, `char`, `byte`, `str`,
  et les `list`, `tuple`, `dict` qui n'en contiennent pas d'autres. Une fonction, un objet de classe, un futur
  ou un socket ne passe pas (`TypeError`) ; un canal passe par son identifiant.
- **Fonction du fil.** Elle doit être de premier niveau dans un module (ni fermeture, ni lambda, ni méthode :
  `ArgumentError`). Le fil importe ce module : son code de haut niveau s'exécute. Si c'est le script principal,
  le protéger par `if thread.is_main():` ; un `spawn` dans ce code pendant l'import d'un fil lève `ThreadError`
  (au lieu de relancer le programme dans chaque fil).
- **Fin du programme.** Comme en Python, le programme principal attend la fin de ses fils ; un fil qui a échoué
  sans être attendu est signalé sur stderr.
- **Ressources.** Sockets, processus fils et bibliothèques FFI appartiennent au fil qui les a créés.
  L'interface graphique (`ui`) reste au programme principal. `os.chdir` et `os.setenv` agissent sur tout le
  processus. Au plus 256 fils en cours.
- **Erreurs.** `TimeoutError` (délai), `ChannelClosedError`, `TypeError`, `ArgumentError`, `ThreadError`.

## Primitives des tâches async

Les tâches sont coopératives (docs/ASYNC.md) : entre deux `await`, une tâche n'est jamais interrompue. Un verrou
ne sert donc qu'aux sections critiques **qui contiennent un `await`**.

| Module | Contenu |
|---|---|
| `concurrency.mutex` | `Mutex` (`lock()` → futur, `unlock`, `try_lock`, `locked`, `waiting`), `with_lock(m, f)`, `Condition` (`wait`, `wait_for(prédicat)`, `notify(n)`, `notify_all`) |
| `concurrency.semaphore` | `Semaphore(n)` (`acquire()` → futur, `release`, `try_acquire`, `value`), `BoundedSemaphore`, `with_permit(s, f)` |
| `concurrency.atomic` | `Atomic(v)` (`load`, `store`, `exchange`, `compare_exchange`, `add`/`sub` → ancienne valeur, `increment`/`decrement` → nouvelle, `update(f)`, `fetch_max`, `fetch_min`), `AtomicFlag` (`test_and_set`, `clear`, `is_set`) |
| `concurrency.async` | `Event`, `Barrier(n)`, `Queue(taille)` (`put`/`get` → futurs, `try_put`/`try_get`), `all_settled`, `retry(f, essais, pause, facteur)`, `with_timeout(f, s)`, `map_limit(éléments, f, limite)`, et `sleep`, `gather`, `race`, `timeout`... d'`asyncio` |

Verrous et sémaphores sont **équitables** (ordre des demandes) ; une tâche annulée pendant son attente ne reçoit
jamais le verrou ni le jeton (il passe à la suivante, comme pour les canaux). Le `Mutex` n'a pas de
propriétaire, comme `asyncio.Lock` de Python. Erreurs : `LockError`, `QueueEmpty`, `QueueFull`.

« async » étant un mot-clé, `concurrency.async` s'importe avec un alias : `use concurrency.async as aio`
(un mot-clé est désormais permis comme segment de chemin de module ; l'alias est alors obligatoire).

## Implémentation des fils

`runtime/native/thread/` (`_native_thread`) : registre des fils et des canaux (verrou et variables de condition),
valeurs portables (copie profonde, indépendante des tas), fils système détachés (pile de 64 Mio). Le fil exécute
`runWorker` (`src/main_alex.cpp`) : VM neuve, programme d'amorçage généré qui importe le module de la fonction et
l'appelle avec les arguments copiés. Les compilations sont sérialisées (caches de bytecode). Les tables de
ressources natives (`net`, `process`, `ffi`, `memory`) sont propres à chaque fil.

## Tests

`make test-concurrency` : `tests/concurrency/test_concurrency.al` (61 vérifications : mises à jour perdues sans
verrou, équité, annulation, Condition, sémaphores, atomiques, Event, Barrier, Queue, retry, map_limit) et
`tests/concurrency/test_thread.al` (45 vérifications : copie, erreurs, délais, boîtes aux lettres, canal partagé
par trois producteurs, serveur TCP dans un fil, fils imbriqués, parallélisme réel). Vérifié aussi sous
ThreadSanitizer (aucune course de données) et avec `ALEX_GC_STRESS=1`.

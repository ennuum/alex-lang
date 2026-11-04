# async / await — tâches, futurs et boucle d'événements

Alex exécute l'asynchrone avec des **coroutines coopératives sur un seul thread**. Une tâche ne cède la main qu'à un
`await` sur un futur non terminé : aucune préemption, donc pas de verrou ni de course de données.

```
use asyncio

async func fetch(n):
    await asyncio.sleep(0.1)
    return n * 2

async func main():
    t := fetch(21)                       # crée une tâche ; elle démarre au prochain tour de boucle
    other := fetch(1)                    # les deux sont en vol en même temps
    print(await t, await other)          # 42 2

await main()                             # `await` est permis au niveau supérieur
```

## Langage

| Construction | Sens |
|---|---|
| `async func f(...)` | appeler `f` ne l'exécute pas : renvoie une **tâche** (un futur) planifiée immédiatement |
| `await e` | `e` doit être un futur/une tâche ; suspend la tâche courante jusqu'à sa fin, vaut son résultat, ou **relance son exception** à cet endroit |
| `await` hors `async func` | `AsyncError` à l'analyse (fonction ordinaire, lambda, initialiseur de champ) |
| `await` au niveau supérieur | permis : le programme principal est lui-même une coroutine |
| `await 42` | `TypeError` à l'exécution (opérande qui n'est pas un futur) |

Les méthodes (`async func` dans un `class`/`struct`), les fonctions imbriquées et les fermetures marchent comme
les fonctions ordinaires. Le `try/catch` fonctionne de part et d'autre d'un `await`.

> **Changement de comportement.** Avant, `async func` se comportait comme `func` et `await e` valait `e`
> (sémantique synchrone provisoire). Un appel `f(x)` d'une `async func` renvoie désormais une tâche : il faut
> l'attendre. Deux tests de `tests/test_compiler.cpp` qui affirmaient l'ancien comportement ont été mis à jour.

## Module `asyncio`

| Fonction | Rôle |
|---|---|
| `sleep(s)` | futur terminé après `s` secondes ; `sleep(0)` cède la main |
| `future()` | promesse : futur que l'on complète soi-même |
| `resolve(f, v)` / `reject(f, type, msg)` | complète une promesse ; `false` si déjà terminée (le premier gagne) |
| `cancel(f)` | demande l'annulation ; `false` si déjà terminé |
| `timeout(f, s)` | futur qui suit `f`, ou échoue en `TimeoutError` après `s` et **annule** `f` |
| `race(liste)` | suit le premier futur terminé (succès, échec ou annulation) |
| `gather(liste)` | `async func` : résultats dans l'ordre de la liste ; relance le premier échec rencontré |
| `abandoned(f)` | `true` si `f` est en attente et que plus personne n'attend son résultat (voir ci-dessous) |
| `done`, `cancelled`, `failed`, `result`, `is_future`, `is_task`, `now` | inspection |

Une **tâche** et une **promesse** sont le même type (`ObjFuture`) : toutes deux s'attendent, s'annulent et se
composent de la même façon ; `type(x)` donne `"task"` ou `"future"`.

## Sémantique précise

- **Ordre.** File FIFO des tâches prêtes ; un minuteur échu passe avant la file (une file chargée n'affame pas
  un `sleep`). Les tâches démarrent dans l'ordre de création. Deux tâches qui font `sleep(0)` en boucle
  alternent strictement.
- **Annulation.** `cancel(t)` fait lever `CancelledError` dans `t` à son point de suspension ; elle peut la
  rattraper (nettoyage, voire continuer). Si l'exception sort de la tâche, son état est *annulée* et ceux qui
  l'attendent reçoivent `CancelledError`. Une tâche qui n'a pas encore démarré est annulée sans exécuter son corps.
  L'annulation ne se propage **pas** aux futurs que la tâche attendait.
- **Abandon.** Un futur est *abandonné* si une tâche qui l'attendait a été annulée et qu'aucune autre ne l'attend ;
  un futur construit dessus par `timeout`/`race` l'est aussi quand tous les futurs chaînés le sont. Un futur jamais
  attendu ne l'est pas, ni un futur terminé ; réattendre un futur lui rend sa vie. Cela permet à une file d'attente
  (canaux) de ne pas livrer à un attendant fantôme sans que l'annulation se propage.
- **Échecs perdus.** Une tâche échouée que personne n'a attendue produit un avertissement sur stderr à la fin du
  programme. Les tâches encore en cours à la fin du programme principal sont abandonnées.
- **Interblocage.** Si plus aucune tâche ne peut avancer et que le programme principal attend, il reçoit
  `DeadlockError` (rattrapable) au lieu de se figer.
- **Exceptions.** Types visibles par `catch e:` / `e.type` : `CancelledError`, `TimeoutError`, `DeadlockError`,
  `InvalidStateError` (une tâche qui s'attend elle-même), plus toute exception levée par la tâche.

## Implémentation

| Étape | Fichier | Détail |
|---|---|---|
| Bytecode | `Opcode.hpp` | `ASYNC_ENTRY` (marqueur en tête d'une async func), `AWAIT` ; ajoutés en fin d'énumération, aucun opcode renuméroté |
| Compilateur | `Compiler.cpp` | émet `ASYNC_ENTRY` en première instruction ; `await e` -> `e`, `AWAIT` |
| Analyseur | `Analyzer.cpp` | pile « fonction englobante async ? » -> `AsyncError` |
| Runtime | `rt/Coroutine.hpp`, `rt/Obj.hpp` | `Frame`/`Handler` déplacés hors de `VM.cpp` ; `ObjFuture`, `CoroutineState` ; marquage GC |
| Ordonnanceur | `vm/Scheduler.hpp`, `Scheduler.cpp` | file prête, minuteurs, transitions, annulation, `timeout`, `race` |
| VM | `VM.cpp` | `CALL` d'une async func crée une tâche ; `AWAIT` suspend ; changement de contexte |
| Stdlib | `runtime/native/asyncio/`, `stdlib/asyncio/asyncio.al` | primitives natives + API publique en Alex |

La VM n'est pas récursive en C++ (un appel Alex empile un `Frame`) : une coroutine est donc sa pile de frames
plus sa pile d'opérandes. **Suspendre = déplacer ces deux vecteurs hors de la VM, reprendre = les y remettre**
(O(1), aucune pile native copiée). Le programme principal est une coroutine comme les autres ; une exception sans
handler fait échouer la tâche au lieu de sortir de `run()`.

## Tests

`make test-async` (69 vérifications, `tests/lang/test_async.al`) + cas ajoutés à `tests/test_analyzer.cpp`,
`tests/test_compiler.cpp` et `tests/test_bc.cpp`.

## Hors périmètre (étapes suivantes)

Les canaux sont livrés (docs/CHANNELS.md). E/S asynchrones, sockets et HTTP asynchrones se brancheront sur cet
ordonnanceur (un futur par opération, complété par la boucle) ; ils ne sont pas dans cette livraison.

# Concurrence : `atomic`, `mutex`, `synchronization`, `thread`, `future`, `async`

Fils du système (plusieurs cœurs), primitives de synchronisation partagées entre fils (et, pour certaines,
entre processus), futurs, et programmation asynchrone de haut niveau au-dessus d'`asyncio`.

```
use thread
use thread.thread_pool as tp
use atomic
use mutex
use future.promise as pr

func travail(n):                      # fonction de PREMIER NIVEAU (chaque fil a sa propre VM)
    return n * n

if thread.is_main():
    compteur := atomic.integer(0)     # partagé entre fils par son identifiant (atomic.attach(id))
    verrou := mutex.Mutex()
    pool := tp.ThreadPool(4)
    print(pool.map(travail, [1, 2, 3]))
    p := pr.Promise()
    p.resolve(42)
    print(await p.future)
    pool.shutdown()
```

Modèle : chaque fil exécute sa propre VM ; les valeurs passées sont COPIÉES (null, bool, nombres, str,
list, tuple, dict). Les objets de synchronisation (atomiques, verrous, sémaphores, barrières...) sont des
jetons natifs partagés : on les passe aux fils comme des entiers et on les rouvre de l'autre côté
(`atomic.attach(id)`, `mutex.attach(id)`...). Les fonctions lancées dans un fil sont de premier niveau ; un module
importé par un fil est réexécuté : protéger le programme par `if thread.is_main():`.

Tests : `make test-concurrency2` (`tests/concurrency2/test_concurrency_pkgs.al`, 109 vérifications, aussi
sous `ALEX_GC_STRESS=50`).

## Paquet `atomic`

### `atomic`

```text
Valeurs ATOMIQUES partagées entre fils d'exécution réels (thread, concurrency.thread) : AtomicInteger,
AtomicBoolean, AtomicReference. Chaque opération est indivisible, même exécutée sur plusieurs cœurs à la fois.
Les objets passent d'un fil à l'autre par leur identifiant entier (.id) : attach(id) les retrouve.

  use atomic
  n := atomic.integer(0)
  fini := atomic.boolean(false)
  etat := atomic.reference({"phase": 1})
  ids := [n.id, fini.id, etat.id]          # à passer aux fils
  x := atomic.attach(ids[0])               # AtomicInteger (le type est retrouvé)

Entre TÂCHES async d'un même fil (coopératives), concurrency.atomic suffit ; ces types-ci fonctionnent aussi
dans ce cas. Barrières mémoire : chaque opération est séquentiellement cohérente (seq_cst) ; fence() est
fournie pour la lisibilité et ne fait rien de plus.

Mémoire : un objet atomique vit jusqu'à destroy() (ou la fin du processus) ; live_objects() compte les objets
de synchronisation natifs (atomiques, verrous, sémaphores...).
```

API publique :

- `integer(value=0)`
- `boolean(value=false)`
- `reference(value=null)`
- `attach(id, as_bool=false)`
- `fence()`
- `live_objects()`

### `atomic.atomic_boolean`

```text
Booléen ATOMIQUE partagé entre fils : drapeau d'arrêt, « déjà fait », verrou rudimentaire.

  use atomic.atomic_boolean as ab
  arret := ab.AtomicBoolean(false)
  thread.spawn(boucle, [arret.id])              # dans le fil : a := ab.attach(id) ; while not a.get(): ...
  arret.set(true)
  if not deja.test_and_set():                   # le premier fil qui arrive passe
      initialiser()

Erreurs : TypeError, ArgumentError.
```

API publique :

- class `AtomicBoolean(value=false, id=null)` : `get()`, `set(value)`, `get_and_set(value)`, `compare_and_set(expected, new)`, `test_and_set()`, `clear()`, `toggle()`, `wait_until(value, timeout=null)`, `destroy()`, `to_string()`
- `attach(id)`

### `atomic.atomic_integer`

```text
Entier de 64 bits à opérations ATOMIQUES, partagé entre FILS (thread, concurrency.thread) : chaque opération
lire-modifier-écrire est indivisible, même quand plusieurs cœurs l'exécutent en même temps. Un AtomicInteger se
transmet à un fil par son identifiant (.id), que le fil rattache avec attach(id).

  use atomic.atomic_integer as ai
  compteur := ai.AtomicInteger(0)
  t := thread.spawn(travailleur, [compteur.id])        # dans le fil : c := ai.attach(id) ; c.increment()
  print(compteur.increment())                          # nouvelle valeur
  print(compteur.get_and_add(10))                      # ancienne valeur
  compteur.compare_and_set(11, 0)                      # true si la valeur était 11
  compteur.update((v) => v * 2)                        # boucle CAS : f peut être rappelée
  compteur.wait_while(0, 5.0)                          # attend qu'il ne vaille plus 0 (5 s au plus)

Arithmétique enroulée sur 64 bits, comme les int d'Alex (max + 1 == min).

Erreurs : TypeError (valeur non entière, identifiant d'un autre type), ArgumentError (objet détruit).
```

API publique :

- class `AtomicInteger(value=0, id=null)` : `get()`, `set(value)`, `get_and_set(value)`, `compare_and_set(expected, new)`, `compare_exchange(expected, new)`, `get_and_add(delta)`, `add_and_get(delta)`, `get_and_increment()`, `get_and_decrement()`, `increment()`, `decrement()`, `fetch_and(mask)`, `fetch_or(mask)`, `fetch_xor(mask)`, `fetch_max(v)`, `fetch_min(v)`, `update(f)`, `accumulate(x, f)`, `wait_while(value, timeout=null)`, `wait_until(value, timeout=null)`, `notify_all()`, `destroy()`, `to_string()`
- `attach(id)`

### `atomic.atomic_reference`

```text
Référence ATOMIQUE à une valeur copiable (null, bool, nombres, str, list, tuple, dict — comme les messages entre
fils) : lecture, remplacement, échange et compare-and-set de la valeur ENTIÈRE, entre fils.

  use atomic.atomic_reference as ar
  config := ar.AtomicReference({"niveau": "info"})
  config.set({"niveau": "debug"})                  # visible de tous les fils (attach(config.id))
  config.update((c) => fusion(c, {"x": 1}))        # boucle compare-and-set
  if config.compare_and_set(ancienne, nouvelle): ...

Comme entre fils les valeurs sont COPIÉES, get() renvoie une copie : la modifier ne change pas la référence
(il faut set()). compare_and_set compare par égalité de structure (==), pas par identité. version() augmente
à chaque écriture (détecter un changement sans comparer les valeurs).

Erreurs : TypeError (valeur non copiable : fonction, objet...), ArgumentError.
```

API publique :

- class `AtomicReference(value=null, id=null)` : `get()`, `set(value)`, `get_and_set(value)`, `compare_and_set(expected, new)`, `compare_exchange(expected, new)`, `update(f)`, `version()`, `destroy()`, `to_string()`
- `attach(id)`

## Paquet `mutex`

### `mutex`

```text
Verrous d'exclusion mutuelle entre FILS d'exécution réels (thread, concurrency.thread) : un seul fil à la fois
exécute la section protégée. Le verrou a un PROPRIÉTAIRE (le fil qui l'a pris) : seul lui peut le rendre.

  use mutex
  m := mutex.Mutex()
  thread.spawn(travail, [m.id])              # dans le fil : m := mutex.attach(id)
  m.lock()
  try:
      section_critique()
  finally:
      m.unlock()
  m.run(section_critique)                    # la même chose
  if m.lock(0.5): ...                        # au plus 0,5 s d'attente (false sinon)
  await m.lock_async()                       # depuis une tâche async : n'arrête pas les autres tâches

Variantes : mutex.recursive_mutex (reprenable par son propriétaire), mutex.read_write_lock (lecteurs multiples
ou un écrivain), mutex.spinlock (attente active, sections très courtes). Pour des tâches async d'un même fil,
mutex.async_mutex() renvoie le verrou coopératif de concurrency.mutex.

Erreurs : LockError (rendre un verrou non détenu ; reprendre un Mutex non récursif qu'on détient déjà :
interblocage certain), TimeoutError (run avec délai), TypeError, ArgumentError.
```

API publique :

- class `Mutex(id=null)` : `lock(timeout=null)`, `try_lock()`, `unlock()`, `locked()`, `owned()`, `waiting()`, `run(fn, timeout=null)`, `lock_async(timeout=null)`, `destroy()`
- `attach(id)`
- `async_mutex()`
- `with_all(locks, fn)`

### `mutex.read_write_lock`

```text
Verrou LECTEURS / ÉCRIVAIN entre fils : plusieurs fils lisent en même temps, un seul écrit (et personne ne lit
pendant ce temps). Équitable pour les écrivains : dès qu'un écrivain attend, les nouveaux lecteurs patientent
(pas de famine des écritures).

  use mutex.read_write_lock as rw
  verrou := rw.ReadWriteLock()
  v := verrou.read(() => cache_lire(cle))         # lecture partagée
  verrou.write(() => cache_ecrire(cle, val))      # écriture exclusive
  verrou.write_lock() ; ... ; verrou.downgrade() ; ... ; verrou.read_unlock()   # écrire puis relire

Réentrance : un lecteur peut reprendre la lecture, l'écrivain peut reprendre l'écriture ou lire. Un lecteur
ne peut PAS passer en écriture (LockError : deux lecteurs qui le tenteraient s'attendraient à jamais) : rendre
la lecture, puis prendre l'écriture.

Erreurs : LockError, TimeoutError (read / write avec délai), TypeError.
```

API publique :

- class `ReadWriteLock(id=null)` : `read_lock(timeout=null)`, `read_unlock()`, `write_lock(timeout=null)`, `write_unlock()`, `try_read_lock()`, `try_write_lock()`, `downgrade()`, `read(fn, timeout=null)`, `write(fn, timeout=null)`, `readers()`, `writing()`, `writers_waiting()`, `destroy()`
- `attach(id)`

### `mutex.recursive_mutex`

```text
Verrou RÉENTRANT entre fils : le fil qui le détient peut le reprendre (appels imbriqués, récursion) ; il est
libéré quand chaque lock() a été suivi de son unlock().

  use mutex.recursive_mutex as rm
  m := rm.RecursiveMutex()
  func ajouter(x):
      m.run(() => _ajouter_sans_verrou(x))
  func ajouter_tout(xs):
      m.lock()                         # reprise par le même fil : pas d'interblocage
      for x in xs:
          ajouter(x)
      m.unlock()

Erreurs : LockError (unlock par un autre fil ou verrou libre), TimeoutError (run), TypeError.
```

API publique :

- class `RecursiveMutex(id=null)` : `level()`
- `attach(id)`

### `mutex.spinlock`

```text
Verrou TOURNANT entre fils : en attente, le fil réessaie en boucle (instruction atomique) au lieu de dormir,
puis cède le processeur toutes les 64 tentatives. Pour des sections TRÈS courtes, sinon Mutex est préférable.
Sans OS (--freestanding), hw.spin_lock / hw.spin_unlock sont l'équivalent sur un mot de la mémoire.

  use mutex.spinlock as sl
  s := sl.SpinLock()
  s.run(() => compteur_global_incrementer())

Erreurs : LockError (unlock par un autre fil, reprise par le détenteur), TimeoutError (run), TypeError.
```

API publique :

- class `SpinLock(id=null)` : `lock(timeout=null)`, `try_lock()`, `unlock()`, `locked()`, `run(fn, timeout=null)`, `destroy()`
- `attach(id)`

## Paquet `synchronization`

### `synchronization`

```text
Primitives de synchronisation entre FILS d'exécution réels (thread, concurrency.thread), toutes avec délai :

| Primitive        | Module                         | Pour                                              |
|------------------|--------------------------------|---------------------------------------------------|
| Semaphore        | synchronization.semaphore      | limiter le nombre de fils sur une ressource       |
| Condition        | synchronization.condition      | attendre un changement d'état, verrou pris        |
| Barrier          | synchronization.barrier        | avancer par étapes, tous ensemble                 |
| CountDownLatch   | synchronization.latch          | attendre que N choses soient prêtes               |
| Once, Lazy       | synchronization.once           | initialisation unique                             |
| Event            | ici                            | signal « c'est arrivé », attendu par plusieurs fils |
| Mutex...         | mutex                          | exclusion mutuelle                                |
| AtomicInteger... | atomic                         | compteurs et drapeaux sans verrou                 |

  use synchronization as sync
  pret := sync.Event()
  thread.spawn(serveur, [pret.id])          # le fil : sync.attach_event(id).set()
  pret.wait(5.0)

Chaque objet a un identifiant (.id) à transmettre aux fils, qui le rattachent (attach). Entre processus : ipc.
Entre tâches async d'un même fil : concurrency.* (verrous coopératifs).
```

API publique :

- class `Event(is_set=false, id=null)` : `set()`, `clear()`, `is_set()`, `wait(timeout=null)`, `wait_async(timeout=null)`, `destroy()`
- `attach_event(id)`
- `semaphore(value=1)`
- `bounded_semaphore(value=1)`
- `condition(mutex=null)`
- `barrier(parties, action=null)`
- `latch(count)`
- `once()`
- `lazy(fn)`
- `live_objects()`

### `synchronization.barrier`

```text
Barrière entre FILS : chaque participant attend, à wait(), que tous les `parties` participants soient arrivés ;
puis tous repartent ensemble. Réutilisable (cycles successifs : calcul par étapes).

  use synchronization.barrier as bar
  b := bar.Barrier(4)
  # dans chacun des 4 fils (b2 := bar.attach(id)) :
  for etape in 0..10:
      calculer(etape)
      b2.wait()                      # renvoie le rang d'arrivée 0..3 ; le dernier arrivé a parties - 1

Délai : si un participant attend plus que son délai, la barrière est CASSÉE pour tous (BrokenBarrierError
chez chacun, comme threading.Barrier de Python) ; reset() la remet en service. abort() la casse volontairement
(par exemple quand un participant échoue, pour ne pas bloquer les autres).

action : fonction appelée par le DERNIER arrivé de chaque cycle, avant que les autres ne repartent... seulement
dans le fil dont l'objet Barrier a reçu l'action (une fonction ne passe pas d'un fil à l'autre).

Erreurs : BrokenBarrierError, ArgumentError, TypeError.
```

API publique :

- class `Barrier(parties=2, action=null, id=null)` : `wait(timeout=null)`, `parties()`, `waiting()`, `broken()`, `generation()`, `reset()`, `abort()`, `destroy()`
- `attach(id, action=null)`

### `synchronization.condition`

```text
Variables de condition entre FILS : attendre, verrou pris, qu'un autre fil signale un changement d'état.
Une Condition est liée à un mutex.Mutex (créé si absent) : wait() le rend pendant l'attente et le reprend avant
de revenir.

  use synchronization.condition as cond
  c := cond.Condition()
  # consommateur                           # producteur
  c.lock()                                 c.lock()
  c.wait_for(() => file_non_vide(), 5.0)   ajouter(x)
  x := retirer()                           c.notify()
  c.unlock()                               c.unlock()

Les réveils sans raison sont possibles en théorie : toujours revérifier la condition (wait_for le fait).
Passage à un fil : (c.id, c.mutex.id), puis cond.attach(cid, mid) dans le fil.

Erreurs : LockError (wait / notify sans détenir le verrou), TypeError, ArgumentError.
```

API publique :

- class `Condition(mutex=null, id=null)` : `lock(timeout=null)`, `unlock()`, `wait(timeout=null)`, `wait_for(predicate, timeout=null)`, `notify(n=1)`, `notify_all()`, `run(fn, timeout=null)`, `destroy()`
- `attach(id, mutex_id)`

### `synchronization.latch`

```text
Loquet à compte à rebours (CountDownLatch) entre FILS : wait() bloque jusqu'à ce que le compteur atteigne 0 ;
count_down() le diminue. À usage unique (contrairement à Barrier) : une fois ouvert, il le reste.

  use synchronization.latch as latch
  prets := latch.CountDownLatch(3)
  # chacun des 3 fils de service, une fois initialisé :  latch.attach(id).count_down()
  if not prets.wait(10.0):
      raise("TimeoutError", "les services n'ont pas démarré")

Erreurs : ArgumentError, TypeError.
```

API publique :

- class `CountDownLatch(count=1, id=null)` : `count_down(n=1)`, `count()`, `wait(timeout=null)`, `try_wait()`, `destroy()`
- `attach(id)`

### `synchronization.once`

```text
Exécution UNIQUE entre fils : Once.call(fn) exécute fn une seule fois pour l'ensemble des fils qui partagent
l'objet ; les autres attendent la fin de cette exécution et reçoivent le même résultat (copié). Si fn lève une
exception, l'exécution compte comme non faite : l'appelant reçoit l'erreur et un appel suivant réessaie.

  use synchronization.once as once
  init := once.Once()
  cfg := init.call(charger_configuration)       # dans chaque fil : once.attach(ids).call(charger_configuration)

  l := once.Lazy(calcul_couteux)                  # valeur paresseuse (un seul fil)
  print(l.get())

Le résultat doit être copiable entre fils (null, bool, nombres, str, list, tuple, dict).

Erreurs : celles de fn ; TimeoutError (call avec délai) ; TypeError (résultat non copiable).
```

API publique :

- class `Once(ids=null)` : `share()`, `call(fn, timeout=null)`, `done()`, `running()`, `destroy()`
- `attach(ids)`
- class `Lazy(fn)` : `get()`, `evaluated()`

### `synchronization.semaphore`

```text
Sémaphores entre FILS d'exécution : un compteur de jetons ; acquire en prend (attend s'il n'y en a pas assez),
release en rend. Limite le nombre de fils qui utilisent une ressource en même temps.

  use synchronization.semaphore as sem
  connexions := sem.Semaphore(4)                  # 4 fils au plus
  connexions.with_permit(() => interroger_base())
  b := sem.BoundedSemaphore(2)                    # rendre plus de jetons qu'au départ : ValueError
  if s.acquire(1, 0.5): ...                       # 1 jeton, 0,5 s d'attente au plus
  await s.acquire_async()                          # depuis une tâche async

Entre processus : ipc.semaphore. Entre tâches async d'un même fil : concurrency.semaphore.

Erreurs : ValueError (BoundedSemaphore dépassé), TimeoutError (with_permit), ArgumentError, TypeError.
```

API publique :

- class `Semaphore(value=1, id=null, bound=0)` : `acquire(n=1, timeout=null)`, `try_acquire(n=1)`, `release(n=1)`, `value()`, `waiting()`, `with_permit(fn, timeout=null)`, `acquire_async(n=1, timeout=null)`, `destroy()`
- class `BoundedSemaphore(value=1, id=null)`
- `attach(id)`

## Paquet `thread`

### `thread`

```text
Fils d'exécution PARALLÈLES (un fil système par fil, plusieurs cœurs), isolés : chacun a sa propre VM, les
valeurs qui passent d'un fil à l'autre sont copiées (docs/CONCURRENCY.md). Ce paquet réunit :
  - concurrency.thread : Thread, spawn, join, boîtes aux lettres, Channel entre fils, parallel_map ;
  - thread.thread_pool : ThreadPool (réserve de fils, ThreadFuture) ;
  - thread.thread_local : ThreadLocal ;  thread.thread_info : informations sur les fils.

  use thread
  func carre(n):
      return n * n
  if thread.is_main():                  # chaque fil réimporte ce module : protéger le programme principal
      t := thread.spawn(carre, [12])
      print(t.join())                   # 144
      pool := thread.pool(4)
      print(pool.map(carre, [1, 2, 3]))
      pool.shutdown()

Partager de l'état modifiable entre fils : atomic (compteurs, drapeaux), mutex (verrous), synchronization
(sémaphores, conditions, barrières...), ou des messages (Channel).
```

API publique :

- `supported()`
- `is_main()`
- `current_id()`
- `current()`
- `cpu_count()`
- `active_count()`
- `Thread(target, args=null, name=null)`
- `spawn(target, args=null, name=null)`
- `join_all(threads, timeout=null)`
- `parallel_map(f, items, workers=null)`
- `send(value, timeout=null)`
- `receive(timeout=null)`
- `Channel(capacity=0)`
- `attach_channel(id)`
- `pool(workers=null, name="pool")`
- `local(default=null, factory=null)`
- `sleep(seconds)`
- `yield_now()`

### `thread.thread_info`

```text
Informations sur les fils : le fil courant (identifiant Alex, identité système, nom), le nombre de cœurs et de
fils actifs, et la liste des fils SYSTÈME du processus (Linux : /proc/self/task — état, temps processeur, nom),
ce qui comprend les fils internes du runtime.

  use thread.thread_info as ti
  me := ti.current()
  print(me.id, me.name, me.is_main)        # 0 « principal » true dans le programme principal
  print(ti.cpu_count(), ti.active_count())
  for t in ti.os_threads():
      print(t["tid"], t["name"], t["state"], t["cpu_time"])
```

API publique :

- class `ThreadInfo(id, name, token, is_main)` : `to_string()`
- `current()`
- `current_id()`
- `is_main()`
- `cpu_count()`
- `active_count()`
- `os_threads()`
- `os_thread_count()`

### `thread.thread_local`

```text
Valeurs PROPRES À CHAQUE FIL. Chaque fil d'Alex a sa propre VM : les variables d'un module y sont déjà propres
au fil (un module est réimporté dans chaque fil). ThreadLocal rend cette intention explicite et donne en plus une
valeur initiale fabriquée à la demande, la remise à zéro et l'identité du fil système.

  use thread.thread_local as tl
  connexion := tl.ThreadLocal(null, ouvrir_connexion)     # factory : appelée au premier get() de chaque fil
  c := connexion.get()
  compteur := tl.ThreadLocal(0)
  compteur.set(compteur.get() + 1)

Attention : les tâches async d'un même fil partagent ses valeurs (elles s'exécutent sur le même fil).
```

API publique :

- class `ThreadLocal(default=null, factory=null)` : `get()`, `set(value)`, `has()`, `clear()`, `update(f)`
- `local(default=null, factory=null)`

### `thread.thread_pool`

```text
Réserve de fils (ThreadPool) : des fils lancés une fois, qui exécutent ensuite des tâches les unes après les
autres, en PARALLÈLE sur plusieurs cœurs. submit renvoie un ThreadFuture ; map applique une fonction à une
liste.

  use thread.thread_pool as tp
  func carre(x):                          # fonction de PREMIER NIVEAU d'un module
      return x * x
  if thread.is_main():                    # le module est réimporté par chaque fil : protéger le programme
      pool := tp.ThreadPool(4)
      f := pool.submit(carre, [12])
      print(f.result())                   # 144
      print(pool.map(carre, [1, 2, 3]))   # [1, 4, 9]
      r := await pool.submit(carre, [5]).as_future()     # depuis une tâche async
      pool.shutdown()

Fonctionnement : chaque fonction soumise a sa propre équipe de fils (au plus `workers`), créée à la demande,
qui importe le module de la fonction une seule fois puis boucle sur ses tâches. Arguments et résultats sont
COPIÉS (null, bool, nombres, str, list, tuple, dict), comme pour thread.spawn ; 12 arguments au plus.

Erreurs : l'erreur d'une tâche est relancée par result() (même type, message suffixé du fil) ; TimeoutError
(result, map avec délai) ; ThreadError (pool arrêté, trop de fils) ; ArgumentError (fonction non de premier
niveau).
```

API publique :

- class `ThreadFuture(pool, job)` : `done()`, `result(timeout=null)`, `exception(timeout=null)`, `as_future()`
- class `ThreadPool(workers=null, name="pool")` : `submit(fn, args=null)`, `map(fn, items, timeout=null)`, `starmap(fn, arg_lists, timeout=null)`, `pending()`, `threads()`, `shutdown(wait=true, timeout=null)`
- `with_pool(workers, fn)`

## Paquet `future`

### `future`

```text
Futurs : composer des résultats asynchrones (futurs et tâches asyncio) sans écrire soi-même les tâches
d'attente. Toutes les fonctions renvoient un NOUVEAU futur, à attendre avec await.

  use future
  f := future.then(telecharger(url), (texte) => len(texte))     # transforme le résultat
  g := future.catch_error(f, (type, msg) => 0)                    # remplace une erreur par une valeur
  h := future.finally_do(g, () => print("fini"))
  n := await h
  tout := await future.all([a, b, c])               # comme asyncio.gather
  premier := await future.any([a, b, c])            # premier SUCCÈS (échoue si tous échouent)
  issues := await future.all_settled([a, b])        # liste de future.result.Result
  v := await future.delay(0.5, "prêt")
  print(future.state(h))                            # pending | done | failed | cancelled

Voir aussi : future.promise (Promise, ThreadPromise), future.shared_future (SharedFuture, lazy),
future.result (Result : Ok / Err), thread.thread_pool (ThreadFuture).

Erreurs : celles des futurs composés ; AggregateError (any : tous ont échoué) ; TimeoutError (with_timeout).
```

API publique :

- `is_future(x)`
- `state(f)`
- `resolved(value=null)`
- `rejected(error_type, message="")`
- `then(f, fn)`
- `catch_error(f, fn)`
- `finally_do(f, fn)`
- `map(f, fn)`
- `all(futures)`
- `all_settled(futures)`
- `any(futures)`
- `race(futures)`
- `delay(seconds, value=null)`
- `with_timeout(f, seconds)`
- `cancel(f)`
- `defer(fn)`
- `settle(f)`

### `future.promise`

```text
Promesses : un futur que l'on complète soi-même, plus tard, depuis un autre endroit du programme.
  - Promise       : pour les tâches async d'un même fil (futur asyncio) ;
  - ThreadPromise : complétée par un AUTRE FIL (thread) et attendue ici, de façon bloquante (wait) ou async.

  use future.promise as pr
  p := pr.Promise()
  rappel_quand_pret((v) => p.resolve(v))
  print(await p.future)

  tp := pr.ThreadPromise()
  thread.spawn(calcul, [tp.share()])        # dans le fil : pr.attach(ids).resolve(resultat)
  print(tp.wait(5.0))                       # ou : await tp.as_future()

Une promesse ne se complète qu'une fois : resolve / reject / cancel renvoient false si elle l'était déjà.

Erreurs : wait / await relancent l'erreur de reject ; TimeoutError (wait) ; CancelledError.
```

API publique :

- class `Promise()` : `resolve(value=null)`, `reject(error_type, message="")`, `cancel()`, `settled()`, `settle_with(fn)`, `follow(f)`
- `promise()`
- `resolved(value=null)`
- `rejected(error_type, message="")`
- class `ThreadPromise(ids=null)` : `share()`, `resolve(value=null)`, `reject(error_type, message="")`, `settled()`, `wait(timeout=null)`, `as_future()`
- `attach(ids)`

### `future.result`

```text
Result : le résultat d'une opération qui peut échouer, comme une VALEUR (au lieu d'une exception) — Ok(valeur)
ou Err(type, message). Pratique pour collecter les issues de plusieurs opérations, ou les transmettre.

  use future.result as res
  r := res.capture(() => int_of(texte))           # Ok(42) ou Err("ValueError", "...")
  if r.is_ok():
      print(r.value)
  n := r.unwrap_or(0)
  r2 := r.map((v) => v * 2).and_then(verifier)    # enchaîne ; une erreur traverse sans rien exécuter
  valeurs := res.collect([r1, r2, r3])            # Ok([...]) ou la première Err
  r3 := await res.from_future(tache)              # issue d'un futur, sans exception

Erreurs : unwrap / expect sur une Err relancent l'erreur d'origine (type et message) ; TypeError.
```

API publique :

- class `Result(ok, value=null, error_type=null, message=null)` : `is_ok()`, `is_err()`, `unwrap()`, `expect(context)`, `unwrap_or(default)`, `unwrap_or_else(fn)`, `map(fn)`, `map_err(fn)`, `and_then(fn)`, `or_else(fn)`, `to_dict()`, `to_string()`
- `ok(value=null)`
- `err(error_type, message="")`
- `capture(fn)`
- `from_dict(d)`
- `collect(results)`
- `partition(results)`
- `from_future(f)`

### `future.shared_future`

```text
SharedFuture : un résultat asynchrone calculé UNE fois et partagé par plusieurs consommateurs, qui l'attendent
chacun quand ils veulent (avant ou après la fin du calcul). Paresseux s'il est créé à partir d'une fonction : le
calcul démarre au premier get().

  use future.shared_future as sf
  config := sf.lazy(charger_config_async)          # rien ne démarre encore
  a := await config.get()                           # démarre, attend
  b := await config.get()                           # même résultat, sans recalcul
  print(config.value_or(null))                      # sans attendre : la valeur si elle est prête

  s := sf.SharedFuture(tache)                       # à partir d'un futur existant

Si le calcul échoue, chaque get() relance la même erreur ; reset() permet de recommencer (lazy seulement).

Erreurs : celles du calcul ; InvalidStateError (value() avant la fin).
```

API publique :

- class `SharedFuture(source)` : `started()`, `get()`, `done()`, `value()`, `value_or(default)`, `reset()`
- `lazy(fn)`
- `share(f)`

## Paquet `async`

### `async`

```text
Programmation asynchrone (tâches coopératives sur un fil, docs/ASYNC.md) — boîte à outils complète :

| Besoin                                   | Ici                                      | Module                 |
|------------------------------------------|------------------------------------------|------------------------|
| attendre, composer                       | sleep, gather, race, timeout, now        | asyncio                |
| tâches nommées, groupes structurés       | spawn, TaskGroup                         | async.task             |
| annulation coopérative                   | cancellation_source, guard               | async.cancellation     |
| travail bloquant / calcul en parallèle   | run_in_thread, executor                  | async.executor         |
| travaux planifiés (délai, période, cron) | scheduler, call_later, every             | async.scheduler        |
| flux de valeurs                          | stream, from_list, from_channel, interval| async.async_stream     |
| premier prêt parmi canaux / futurs       | select                                   | async.select           |
| verrous, files, événements de tâches     | —                                        | concurrency.*, channel |
| futurs composés, promesses, Result       | —                                        | future                 |

« async » étant un mot-clé, le paquet s'importe avec un alias :

  use async as aio
  async func main():
      g := aio.TaskGroup()
      g.spawn(telecharger, ["a"])
      g.spawn(telecharger, ["b"])
      print(await g.wait())
      h := await aio.run_in_thread(hacher, ["gros.iso"])
      r := await aio.select([aio.recv(ch), aio.after(1.0)])
  await main()
```

API publique :

- `sleep(seconds)`
- `now()`
- `gather(futures)`
- `race(futures)`
- `timeout(f, seconds)`
- `cancel(f)`
- `future()`
- `run(fn, args=null)`
- `spawn(fn, args=null, name=null)`
- `TaskGroup(name="groupe")`
- `cancellation_source()`
- `guard(f, token)`
- `run_in_thread(fn, args=null)`
- `executor(workers=null)`
- `scheduler()`
- `call_later(delay, fn, args=null)`
- `every(interval, fn, args=null, count=null)`
- `cron(expression, fn, args=null)`
- `stop_scheduler()`
- `from_list(items)`
- `from_channel(ch)`
- `interval(seconds, count=null)`
- `from_producer(producer, buffer=16)`
- `merge(streams)`
- `select(cases, default=false)`
- `recv(ch)`
- `send(ch, value)`
- `after(seconds)`
- `on_future(f)`

### `async.async_stream`

```text
Flux ASYNCHRONES : une suite de valeurs qui arrivent au fil du temps (messages d'un canal, lignes, mesures
périodiques...), transformée par des opérateurs paresseux, puis consommée.

  use async.async_stream as st
  s := st.from_channel(ch).filter((m) => m["niveau"] == "erreur").map((m) => m["texte"]).take(10)
  for_each_res := await s.for_each((t) => print(t))
  mesures := await st.interval(0.1, 5).map((i) => lire_capteur()).collect()     # 5 mesures, une par 0,1 s
  total := await st.from_list([1, 2, 3]).reduce((acc, x) => acc + x, 0)
  fusion := st.merge([flux_a, flux_b])          # valeurs des deux, dans l'ordre d'arrivée
  lots := st.from_list(xs).batch(100)           # listes de 100

Un flux se consomme UNE fois. Chaque opérateur renvoie un nouveau flux (rien ne s'exécute avant la
consommation). next() renvoie un futur de [true, valeur] ou [false, null] à la fin.

Les fonctions passées (map, filter...) peuvent être ordinaires ou async (leur futur est attendu).

Erreurs : une erreur de la source ou d'une fonction traverse le flux jusqu'au consommateur.
```

API publique :

- class `AsyncStream(pull)` : `next()`, `map(fn)`, `filter(fn)`, `tap(fn)`, `take(n)`, `skip(n)`, `take_while(fn)`, `batch(size)`, `enumerate()`, `chain(other)`, `throttle(seconds)`, `collect()`, `for_each(fn)`, `reduce(fn, initial)`, `first()`, `count()`
- `from_list(items)`
- `range(start, stop, step=1)`
- `from_channel(ch)`
- `interval(seconds, count=null)`
- `from_producer(producer, buffer=16)`
- `merge(streams)`
- `zip(a, b)`
- `empty()`

### `async.cancellation`

```text
Annulation COOPÉRATIVE : une source d'annulation (CancellationSource) distribue un jeton (CancellationToken)
aux tâches ; quand la source annule, chaque tâche le constate (cancelled, raise_if_cancelled) ou réagit
(on_cancel), et les opérations enveloppées par guard() sont annulées.

  use async.cancellation as cancel
  src := cancel.CancellationSource()
  async func travail(jeton):
      for lot in lots:
          jeton.raise_if_cancelled()          # CancelledError si annulé
          await traiter(lot)
  t := travail(src.token)
  src.cancel_after(5.0)                       # ou src.cancel("arrêt demandé")
  r := await cancel.guard(telecharger(url), src.token)   # annule le téléchargement si le jeton l'est
  lie := cancel.linked([jeton_a, jeton_b])               # annulé dès que l'un l'est

Erreurs : CancelledError (raise_if_cancelled, guard).
```

API publique :

- class `CancellationToken()` : `cancelled()`, `raise_if_cancelled()`, `on_cancel(fn)`, `wait()`
- class `CancellationSource()` : `cancel(reason=null)`, `cancel_after(seconds, reason="délai dépassé")`, `cancelled()`
- `none()`
- `source()`
- `timeout_source(seconds)`
- `linked(tokens)`
- `guard(f, token)`

### `async.executor`

```text
Exécuter un travail BLOQUANT ou de CALCUL hors de la boucle d'événements, sur des fils parallèles, et l'attendre
comme un futur : les autres tâches async continuent pendant ce temps.

  use async.executor as ex
  func hacher(chemin):                       # fonction de PREMIER NIVEAU (exécutée dans un autre fil)
      return crypto.sha256(file.read(chemin))
  async func main():
      h := await ex.run_in_thread(hacher, ["gros.iso"])
      tous := await ex.map(hacher, fichiers)        # en parallèle
  if thread.is_main():
      await main()

Un exécuteur partagé (default()) est créé à la première utilisation (un fil par cœur et par fonction) ;
Executor(n) en crée un dédié. Arguments et résultats sont copiés (règles de thread).

Erreurs : celles de la fonction (relancées par await), ThreadError, TimeoutError.
```

API publique :

- class `Executor(workers=null, name="executor")` : `run(fn, args=null)`, `map(fn, items)`, `shutdown(wait=true)`
- `default()`
- `run_in_thread(fn, args=null)`
- `map(fn, items)`
- `shutdown_default()`

### `async.scheduler`

```text
Planificateur de travaux sur la boucle async : une fois après un délai, à une heure, périodiquement, ou selon
une expression CRON (minute heure jour mois jour-de-semaine). Les fonctions peuvent être ordinaires ou async.

  use async.scheduler as sched
  s := sched.Scheduler()
  s.call_later(2.0, rappel)                         # dans 2 s
  j := s.every(0.5, sonder, [capteur])              # toutes les 0,5 s
  s.every(60, rapport, null, 10)                    # 10 fois seulement
  s.cron("*/15 8-18 * * 1-5", sauvegarde)           # toutes les 15 min, 8 h-18 h, du lundi au vendredi
  s.start()                                         # tâche de fond ; ou : await s.run(30) pendant 30 s
  ...
  j.cancel()
  s.stop()

Un travail n'est jamais exécuté deux fois en même temps : si une exécution async dure plus que la période, la
suivante attend sa fin (pas de chevauchement). Une erreur dans un travail est gardée dans job.last_error et
comptée dans job.errors ; elle n'arrête pas le planificateur (on_error(fn) pour être prévenu).

Erreurs : ArgumentError (délai négatif, expression cron invalide), TypeError.
```

API publique :

- class `Job(scheduler, fn, args, when, interval, count, cron)` : `cancel()`, `active()`, `due_in()`
- class `Scheduler()` : `call_later(delay, fn, args=null)`, `call_at(t, fn, args=null)`, `every(interval, fn, args=null, count=null, first_delay=null)`, `cron(expression, fn, args=null, count=null)`, `on_error(fn)`, `cancel(job)`, `cancel_all()`, `jobs()`, `run(duration=null)`, `start()`, `stop()`
- `parse_cron(expression)`
- `seconds_until_next(spec, now)`
- `next_run(expression, now=null)`

### `async.select`

```text
Attendre le PREMIER prêt parmi plusieurs opérations de natures différentes : réception ou envoi sur un canal
(channel.Channel), fin d'un futur ou d'une tâche, délai ; avec une branche par défaut si rien n'est prêt.

  use async.select as sel
  r := await sel.select([sel.recv(commandes), sel.recv(arret), sel.future(tache), sel.after(5.0)])
  match r[0]:
      0: traiter(r[1])
      1: arreter()
      2: print("tâche finie :", r[1])
      3: print("rien depuis 5 s")
  r := await sel.select([sel.recv(ch)], true)  # default : (-1, null) tout de suite si rien n'est prêt

Résultat : (indice du cas, valeur) — valeur reçue, résultat du futur, null pour un envoi ou un délai. Un canal
FERMÉ donne (indice, null) pour une réception (vérifier ch.closed()). Un futur qui échoue relance son erreur.

Garanties : un seul cas s'exécute ; les opérations de canal qui n'ont pas gagné n'ont aucun effet (s'appuie sur
channel.select). Si un cas de canal et un futur se terminent au même tour, le canal l'emporte (sa valeur n'est
jamais perdue).

Erreurs : celles des futurs ; ArgumentError (cas invalide, liste vide).
```

API publique :

- `recv(ch)`
- `send(ch, value)`
- `future(f)`
- `after(seconds)`
- `select(cases, default=false)`

### `async.task`

```text
Tâches asynchrones nommées et groupes de tâches (concurrence STRUCTURÉE).

  use async.task as task
  t := task.spawn(telecharger, [url], "dl-1")   # Task : nom, état, annulation, rappels
  t.add_done_callback((tache) => print(tache.name, tache.state()))
  print(await t.wait())                          # résultat (ou relance l'erreur)

  g := task.TaskGroup()
  for u in urls:
      g.spawn(telecharger, [u])
  resultats := await g.wait()        # tous les résultats ; au premier échec, les autres sont ANNULÉS et
                                     # l'erreur est relancée

spawn accepte une async func (sa tâche est reprise) ou une fonction ordinaire (exécutée au prochain tour de
boucle). Une Task enveloppe un futur asyncio (t.future) : asyncio.timeout(t.future, 2) etc. s'appliquent.

Erreurs : celles des tâches ; InvalidStateError (result avant la fin) ; CancelledError.
```

API publique :

- class `Task(future, name=null)` : `done()`, `cancelled()`, `failed()`, `state()`, `cancel()`, `wait()`, `result()`, `add_done_callback(fn)`
- `spawn(fn, args=null, name=null)`
- `wrap(future, name=null)`
- class `TaskGroup(name="groupe")` : `spawn(fn, args=null, name=null)`, `add(future, name=null)`, `cancel_all()`, `wait()`, `pending()`
- `run_all(fns)`


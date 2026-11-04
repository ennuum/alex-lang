# Bibliothèque standard complétée

Ce document recense les **269 modules** ajoutés à `stdlib/` pour que la bibliothèque corresponde à
l'arborescence de référence (`ALEX_stdlib_arborescence_completee`), répartis dans **50 paquets**. Chaque
module suit la convention de la bibliothèque : en-tête `# ALEX STANDARD LIBRARY — paquet.module`, description,
exemple d'utilisation, erreurs levées. Les modules marqués *(natif)* appartiennent au sous-ensemble compilable
en natif (`# alex: native`) : ils fonctionnent dans la VM (machine simulée `hw.sim_*`) **et** dans le noyau Alex
compilé avec `alexc build --native --freestanding`.

## Principes

- **Pas de matériel simulé en douce.** Les modules matériels lisent la vraie machine (`/sys`, `/dev`, `/proc`,
  outils `ffmpeg`, `v4l2-ctl`, `arecord`…) au travers des couches existantes (`hardware._sys`,
  `hardware.permissions`, `hw`). Les tests remplacent la racine de lecture (`hardware._sys.set_root`) par une
  arborescence temporaire, ou utilisent la machine simulée de la VM (`hw.sim_pci`, `hw.sim_apic`) ; un dorsal
  qui n'existe pas ici (rendu DRM accéléré, par exemple) est détecté et déclaré indisponible, jamais imité.
- **Réutilisation.** Les nouveaux modules s'appuient sur ceux qui existaient (`driver.driver_manager`,
  `storage_driver.disk`, `network_driver.network_packet`, `usb_driver.usb_class`, `gpu.gpu_compute`,
  `graphics.pipeline`, `camera.video_frame`, `audio.audio_stream`…) plutôt que de les dupliquer.
- **Vérifié indépendamment quand c'est possible.** Exemples : tables GPT relues par `storage_driver.disk` et
  validées par Python (`zlib.crc32`, `uuid`) ; diviseurs FTDI identiques aux valeurs du fabricant (115200 →
  115384 bauds, 9600 → 0x4138) ; enveloppes de chiffrement (security) interopérables avec la bibliothèque
  Python `cryptography` ; serveur HTTPS local avec certificat OpenSSL.

## Modifications du cœur (C++)

| Fichier | Changement |
|---|---|
| `src/Compiler.cpp` | boucle `for` : seule une `IndexError` termine l'itération ; toute autre exception levée en lisant l'élément (par exemple dans le `__getitem__` d'un itérateur paresseux) est relancée au lieu d'arrêter la boucle en silence |
| `runtime/native/reflect/*`, `src/VM.cpp`, `include/alex/vm/VM.hpp`, `src/main_alex.cpp`, `src/ModuleResolver.cpp` | module natif privé `_native_reflect` (types, classes, champs, méthodes liées, arités) utilisé par `reflection`, `testing.mock` et le compilateur auto-hébergé (`compiler.ast`) |
| `Makefile` | cibles `test-stdlib2` et `test-stdlib2-native`, ajoutées à `make test` |

## Tests

| Commande | Contenu |
|---|---|
| `make test-stdlib2` | tous les programmes `tests/stdlib2/test_*.al` (format « N OK, M échecs ») ; la partie interface utilisateur tourne avec `ALEX_UI_BACKEND=headless` |
| `make test-stdlib2-native` | `tests/stdlib2/native_drivers.sh` : chaque `tests/stdlib2/native/k*.al` compilé avec `--native --freestanding`, puis compilé pour l'hôte et exécuté : sa sortie doit être identique à celle de la VM |

Les tests préexistants (`test-drivers`, `test-media`, `test-hardware-ext`, `test-sysapp`, `test-concurrency2`,
`test-lang`…) passent toujours.

## Modules ajoutés, par paquet

### process

| Module | Contenu |
|---|---|
| `process.process_builder` | ProcessBuilder : construire le lancement d'un processus pas à pas (comme java.lang.ProcessBuilder), puis le démarrer (ProcessHandle) ou l'exécuter jusqu'au bout (Result). Réunit en un seul objet ce que process.Command, … |
| `process.process_handle` | ProcessHandle : une poignée UNIFORME sur un processus, qu'il soit un fils de ce programme (process.Process) ou un processus quelconque désigné par son pid. Mêmes opérations dans les deux cas : état, attente, signaux, … |
| `process.process_state` | États d'un processus et transitions permises, pour suivre le cycle de vie d'un fils ou décrire un processus quelconque (codes de /proc/<pid>/stat). |
| `process.process_signal` | Envoyer des signaux à des PROCESSUS (par pid), avec les gestes usuels : terminer proprement, tuer, suspendre, reprendre, interrompre — et attendre la disparition du processus. |
| `process.process_limits` | Limites de ressources d'un processus (rlimit) : temps processeur, mémoire, fichiers ouverts, taille des fichiers, processus... Chaque limite a une valeur SOUPLE (appliquée) et une valeur DURE (plafond de la souple ; seul root … |
| `process.process_priority` | Priorité d'ordonnancement (« nice ») des processus : de -20 (la plus haute) à 19 (la plus basse), 0 par défaut. Baisser sa priorité est toujours permis ; l'augmenter (valeur plus petite) demande des droits (root / CAP_SYS_NICE) : … |
| `process.process_group` | Groupes de processus : - ProcessGroup : un ensemble de fils lancés et pilotés ENSEMBLE (démarrer, attendre tous / le premier, signaler, arrêter, bilan), chacun dans son propre groupe système pour que les signaux atteignent aussi … |
| `process.process_monitor` | Surveillance de processus dans le temps : échantillonnage du processeur (%), de la mémoire résidente et du nombre de fils d'exécution, historique borné, seuils déclenchant des alertes, détection de la fin. |
| `process.process_errors` | Erreurs liées aux processus, et aide au diagnostic : ProcessError processus absent, code de sortie non nul (check=true), opération impossible ProcessNotFoundError aucun processus de ce pid (sous-type logique de ProcessError) … |

### pipe

| Module | Contenu |
|---|---|
| `pipe.pipe_reader` | PipeReader : le bout LECTURE d'un tube, avec ce qu'un programme qui consomme un flux attend : délai par défaut, parcours ligne à ligne PARESSEUX (`for ligne in r`), lecture jusqu'à un délimiteur, compteurs, test de disponibilité … |
| `pipe.pipe_writer` | PipeWriter : le bout ÉCRITURE d'un tube, avec mise en tampon optionnelle (moins d'appels système pour de nombreuses petites écritures), compteurs, et traitement explicite du lecteur parti (EPIPE ; SIGPIPE est ignoré dès le … |
| `pipe.pipe_buffer` | PipeBuffer : un tube EN MÉMOIRE, borné, à la sémantique d'un vrai tube (FIFO d'octets, fin de flux quand l'écrivain ferme) — pour relier deux parties d'un même programme, tester du code de tube sans descripteur, ou absorber la … |
| `pipe.pipe_errors` | Erreurs des tubes : BrokenPipeError écriture alors que plus personne ne lit (EPIPE) PipeClosedError opération sur un bout déjà fermé ProtocolError message mal formé (pipe.pipe_stream) TimeoutError délai dépassé (lecture, … |

### signal

| Module | Contenu |
|---|---|
| `signal.signal_mask` | Masques de signaux : RETARDER la prise en compte de signaux pendant une section critique (écriture d'un fichier d'état, transaction), puis les traiter à la sortie — comme sigprocmask, au niveau du programme ALEX : un signal … |
| `signal.signal_errors` | Erreurs des signaux : SignalError échec système (sigaction, kill...) InterruptError levée par un gestionnaire interrupt_on (Ctrl+C), ou un arrêt forcé ArgumentError signal inconnu, ou non interceptable (KILL, STOP, fautes) … |

### ipc

| Module | Contenu |
|---|---|
| `ipc.ipc_message` | Message interprocessus STRUCTURÉ et auto-descriptif : enveloppe (identifiant, sujet, expéditeur, date, corrélation pour les réponses, en-têtes) + charge utile JSON, avec version de format, empreinte d'intégrité (Adler-32) et … |
| `ipc.ipc_permissions` | Droits d'accès des objets IPC nommés : où ils vivent dans le système de fichiers, qui les possède, quels droits ils portent, et les restreindre. Sous Linux : mémoire partagée /dev/shm/<nom> sémaphore nommé /dev/shm/sem.<nom> file … |
| `ipc.ipc_errors` | Erreurs de la communication interprocessus : IpcError échec système (shm_open, mq_open, socket...), plateforme non prise en charge IpcExistsError création exclusive d'un objet qui existe déjà (mode "create") IpcNotFoundError … |

### atomic

| Module | Contenu |
|---|---|
| `atomic.atomic_counter` | Compteurs atomiques prêts à l'emploi, partagés entre fils réels : AtomicCounter compte borné (min / max) : increment/decrement SATURANTS ou stricts (erreur au-delà), try_increment (false au plafond : jetons, places disponibles), … |
| `atomic.atomic_flag` | AtomicFlag : le drapeau atomique minimal (std::atomic_flag) — deux états, test_and_set / clear, et attente d'un changement (wait / notify), sans autre valeur. Base des verrous tournants et des signaux « une fois ». Partageable … |
| `atomic.memory_order` | Ordres mémoire des opérations atomiques, comme std::memory_order (C++) : RELAXED, CONSUME, ACQUIRE, RELEASE, ACQ_REL, SEQ_CST. Les opérations natives d'ALEX sont TOUJOURS séquentiellement cohérentes (SEQ_CST) — le plus fort : … |

### mutex

| Module | Contenu |
|---|---|
| `mutex.try_lock` | Prise de verrous SANS blocage indéfini, sur tous les verrous du paquet (Mutex, RecursiveMutex, SpinLock, ReadWriteLock en écriture) : try_lock(l) essai immédiat try_lock_for(l, s) essai pendant au plus s secondes … |
| `mutex.lock_guard` | Gardes de verrou (RAII, comme std::lock_guard / unique_lock / scoped_lock / shared_lock) : le verrou est pris à la construction et rendu par release() — ou automatiquement avec `with` — exactement une fois. |

### synchronization

| Module | Contenu |
|---|---|
| `synchronization.countdown_event` | CountdownEvent : un événement qui se LÈVE quand un compteur atteint zéro (comme CountdownEvent de .NET). À la différence de CountDownLatch, le compte peut AUGMENTER tant qu'il n'est pas à zéro (add_count : des travaux découverts … |
| `synchronization.synchronization_errors` | Erreurs des primitives de synchronisation entre fils : SyncError usage invalide (compter en dessous de zéro, ajouter à un CountdownEvent déjà levé) BrokenBarrierError barrière cassée (un participant est parti, délai, abort) … |

### thread

| Module | Contenu |
|---|---|
| `thread.thread_id` | ThreadId : identité d'un fil d'exécution — numéro ALEX (0 : programme principal), identifiant système (tid Linux, visible dans /proc/self/task, top -H, gdb) et jeton natif stable. Comparable et hachable : sert de clé de dict pour … |
| `thread.thread_priority` | Priorité d'ordonnancement d'un FIL (Linux : chaque fil a sa propre valeur nice, -20 la plus haute, 19 la plus basse). Un fil règle d'ordinaire SA propre priorité, au début de sa fonction : un fil de calcul de fond se met à LOW … |
| `thread.thread_state` | États d'un fil : NEW (créé, pas démarré), RUNNING, FINISHED (fonction rendue), FAILED (erreur), et, pour les fils système observés dans /proc, SLEEPING / BLOCKED / STOPPED / ZOMBIE. |
| `thread.thread_errors` | Erreurs des fils d'exécution : ThreadError démarrage impossible (trop de fils, spawn depuis le code de haut niveau d'un module importé dans un fil), fil démarré deux fois, opération avant start TimeoutError join / receive / … |

### future

| Module | Contenu |
|---|---|
| `future.exception_result` | ExceptionResult : l'issue d'une opération avec, en cas d'échec, l'EXCEPTION COMPLÈTE (type, message, trace de pile, cause) — là où future.result.Result ne garde que type et message. Pour journaliser une erreur survenue ailleurs … |
| `future.future_errors` | Erreurs des futurs et promesses : InvalidStateError résultat lu avant la fin, promesse complétée deux fois (strict), futur qui s'attend CancelledError futur annulé TimeoutError délai dépassé (with_timeout, ThreadPromise.wait) … |

### async

| Module | Contenu |
|---|---|
| `async.task_group` | Groupe de tâches asynchrones à POLITIQUE configurable (complète async.task.TaskGroup) : max_concurrency au plus N tâches en cours ; les suivantes attendent leur tour (file d'attente) policy "fail_fast" (défaut) : au premier … |
| `async.task_scope` | Portée de tâches (concurrence STRUCTURÉE, comme les nurseries de Trio ou StructuredTaskScope de Java) : aucune tâche lancée dans une portée ne lui survit. À la sortie, la portée attend toutes ses tâches ; si l'une échoue, les … |
| `async.async_errors` | Erreurs de la programmation asynchrone : CancelledError tâche annulée (cancel, jeton d'annulation, groupe dont une tâche a échoué) TimeoutError délai dépassé (timeout, TaskScope avec échéance) DeadlockError plus aucune tâche ne … |

### coroutine

| Module | Contenu |
|---|---|
| `coroutine.coroutine` | Coroutines : des fonctions qui se SUSPENDENT au milieu de leur exécution en rendant une valeur, et REPRENNENT là où elles s'étaient arrêtées — dialogue en deux sens entre un producteur et un consommateur, machines à états écrites … |
| `coroutine.coroutine_handle` | CoroutineHandle : une poignée légère sur une coroutine (comme std::coroutine_handle) — identifiant, reprise, état, destruction — et un registre des coroutines vivantes, pour les retrouver par identifiant (planificateurs, outils … |
| `coroutine.coroutine_state` | États d'une coroutine et transitions permises : |
| `coroutine.coroutine_scheduler` | Planificateur COOPÉRATIF de coroutines, à tours : chaque coroutine prête est reprise à son tour ; elle s'exécute jusqu'à sa prochaine suspension. Une coroutine qui rend yield.wait(s) n'est reprise qu'après s secondes ; toute … |
| `coroutine.generator` | Générateurs : produire une suite de valeurs à la demande. |
| `coroutine.yield` | Le côté CORPS d'une coroutine : suspendre l'exécution en rendant une valeur à celui qui l'a reprise, et recevoir ce qu'il renvoie à la reprise suivante. ALEX n'a pas d'instruction `yield` : le corps d'une coroutine est une `async … |
| `coroutine.coroutine_errors` | Erreurs des coroutines : CoroutineError reprise d'une coroutine terminée ou en cours d'exécution, corps qui n'est pas une async func, yield hors de sa coroutine CoroutineExit levée DANS le corps au point de suspension quand on … |

### memory

| Module | Contenu |
|---|---|
| `memory.allocator` | Interface commune des allocateurs (stratégies interchangeables, comme std::pmr ou les allocateurs de Zig) et allocateurs de base. Une allocation rend un objet Allocation dont .view est une MemoryView SÛRE (bornes vérifiées, … |
| `memory.arena` | Arène EXTENSIBLE à points de restauration (complète memory.buffer.Arena, qui a une capacité fixe). Allocation « bump » en O(1) dans des tronçons (chunks) ; quand un tronçon est plein, un nouveau est créé (taille doublée, … |
| `memory.pool_allocator` | Pools d'emplacements de taille fixe : PoolAllocator(block_size, capacity) emplacements d'octets dans UN Buffer ; alloc/free en O(1) (liste libre) ; un emplacement rendu invalide ses vues (StaleViewError) ; double libération et … |
| `memory.aligned_memory` | Alignement : arithmétique d'adresses et tampons alignés (SIMD, DMA, lignes de cache, pages). |
| `memory.memory_region` | Plages d'adresses : modèle et calculs (sans accès à la mémoire). Sert à décrire la carte mémoire d'un processus, d'un périphérique (fenêtres MMIO, BAR PCI) ou d'un noyau, et à raisonner dessus. |
| `memory.memory_stats` | Mesures de la mémoire, en un seul endroit : registre natif (blocs gérés, brut, mappé), ramasse-miettes (objets ALEX), processus (résident, virtuel, pic — /proc/self/status) et machine (/proc/meminfo). |
| `memory.memory_protection` | Protection de la mémoire : notation des droits (« rwx »), politique W^X, gel temporaire de tampons, régions à pages de garde, effacement sûr des secrets. |
| `memory.page_allocator` | Allocateur de PAGES sur une réservation d'espace d'adressage : on réserve d'un coup une grande plage inaccessible (PROT_NONE), puis on « engage » (commit) des suites de pages contiguës à la demande (lecture/écriture), et on les … |
| `memory.memory_errors` | Erreurs de la gestion mémoire (natives et ALEX), avec leur sens : MemoryError quota dépassé, mémoire insuffisante, utilisation après libération, double free UnsafeError opération brute hors d'un bloc unsafe LeakError fuite … |

### smart_pointer

| Module | Contenu |
|---|---|
| `smart_pointer.smart_pointer` | Pointeurs intelligents : propriété explicite et fin de vie déterministe des ressources. |
| `smart_pointer.unique_ptr` | UniquePtr : propriété EXCLUSIVE d'une valeur (std::unique_ptr / Box de Rust). Un seul propriétaire ; la propriété se transfère par move() (l'ancien pointeur devient inutilisable) ; le suppresseur (deleter) est appelé à la … |
| `smart_pointer.shared_ptr` | SharedPtr : propriété PARTAGÉE à comptage de références (std::shared_ptr / Rc de Rust). Chaque copie (clone) est un propriétaire ; le suppresseur est appelé quand le DERNIER propriétaire relâche (drop ou reset). WeakPtr … |
| `smart_pointer.weak_ptr` | WeakPtr : référence FAIBLE vers une valeur détenue par des SharedPtr (std::weak_ptr). Elle n'empêche pas la destruction : lock() rend un nouveau SharedPtr si la valeur vit encore, sinon null. Sert à casser les cycles (parent <-> … |
| `smart_pointer.reference_count` | Bloc de contrôle à comptage de références, partagé par SharedPtr et WeakPtr (comme le « control block » de std::shared_ptr) : compte FORT (propriétaires), compte FAIBLE (observateurs), suppresseur appelé exactement une fois quand … |
| `smart_pointer.ownership` | Discipline de propriété et libération déterministe des ressources (RAII), en ALEX : Owned(v) valeur à propriétaire unique : take() la déplace (l'original devient inutilisable), borrow(f) la prête le temps d'un appel ; une … |
| `smart_pointer.smart_pointer_errors` | Erreurs des pointeurs intelligents : NullPointerError accès à la valeur d'un pointeur vide (jamais initialisé, reset(), release()) OwnershipError usage d'un pointeur dont la propriété a été déplacée (move) ou relâchée (drop) … |

### gc

| Module | Contenu |
|---|---|
| `gc.gc_config` | Réglages du ramasse-miettes sous forme d'objet : lire la configuration courante, en appliquer une autre, l'appliquer le temps d'un appel puis restaurer la précédente, et préréglages nommés. |
| `gc.gc_heap` | Le tas géré par le ramasse-miettes, vu de l'intérieur : objets vivants, pic, objets créés et libérés, seuil et marge avant la prochaine collecte ; collecte avec compte rendu. |
| `gc.gc_roots` | Racines explicites : garder des objets VIVANTS indépendamment des variables du programme (comme les handles « épinglés » des runtimes managés). Un objet épinglé ne peut pas être collecté tant que son épingle existe — utile quand … |
| `gc.gc_stats` | Statistiques du ramasse-miettes dans le temps : mesure d'un bloc de code (objets créés, libérés, collectes déclenchées), échantillonnage périodique et rapport. |
| `gc.gc_errors` | Erreurs du pilotage du ramasse-miettes : GcConfigError réglage invalide (seuil < 1, intervalle de stress négatif, préréglage inconnu) GcRootError racine inconnue ou déjà retirée (gc.gc_roots) TypeError valeur du mauvais type |

### collections

| Module | Contenu |
|---|---|
| `collections.list` | Contrats communs des collections et liste immuable. |
| `collections.linked_list` | LinkedList : liste doublement chaînée. Ajout et retrait aux deux bouts en O(1), insertion/retrait au milieu en O(1) une fois le nœud atteint (curseur ListCursor). L'accès par position parcourt depuis le bout le plus proche ; un … |
| `collections.array_list` | ArrayList : liste dynamique indexée (accès O(1), ajout en fin O(1) amorti, insertion/suppression O(n)), avec compteur de modifications pour détecter les modifications pendant un parcours par itérateur. |
| `collections.vector` | Vector : tableau dynamique à CAPACITÉ explicite, dans l'esprit de std::vector (C++) : la mémoire réservée (capacity) est distincte de la taille (size) ; reserve() pré-alloue, shrink_to_fit() rend l'excédent. Les cases réservées … |
| `collections.deque` | Deque : file à double entrée sur tampon circulaire. Ajout et retrait aux deux bouts en O(1) amorti, accès par position en O(1). Bornée si max_len est donné : un ajout dans une deque pleine ÉJECTE l'élément du bout opposé (comme … |
| `collections.stack` | Stack : pile LIFO (dernier entré, premier sorti), éventuellement bornée. |
| `collections.queue` | Queue : file FIFO (premier entré, premier sorti), éventuellement bornée, sur tampon circulaire. Deux styles d'API, comme java.util.Queue : enqueue / dequeue / front lèvent une erreur (CapacityError, EmptyCollectionError) offer / … |
| `collections.priority_queue` | PriorityQueue : file de priorité sur tas binaire. push / pop en O(log n), peek en O(1). Par défaut le PLUS PETIT sort en premier (tas min) ; max=true inverse. La priorité vient de l'élément lui-même, de key(élément) ou d'un … |
| `collections.hash_map` | HashMap : table associative à adressage par compartiments, ORDONNÉE par insertion. Contrairement au dict natif, elle accepte TOUTE clé, y compris des instances : une instance définissant hash_code() et __eq__ est comparée par … |
| `collections.hash_set` | HashSet : ensemble sans doublon, ordonné par insertion, sur collections.hash_map. Accepte toute valeur hachable ET les instances (hash_code() / __eq__, sinon identité) — ce que le set natif refuse. |
| `collections.tree_map` | TreeMap : table associative TRIÉE par clé, sur arbre AVL équilibré. Insertion, recherche et suppression en O(log n) ; parcours dans l'ordre des clés ; requêtes d'ordre (plus petite clé >= x, intervalle...). L'ordre est celui de < … |
| `collections.tree_set` | TreeSet : ensemble TRIÉ sans doublon, sur collections.tree_map (AVL). Ajout, retrait, recherche en O(log n) ; parcours dans l'ordre ; requêtes d'ordre (floor, ceiling, intervalle). |
| `collections.bitset` | BitSet : ensemble d'entiers positifs compact, un bit par valeur (mots de 32 bits). Opérations ensemblistes mot à mot, comptage de population, recherche du bit suivant. Croît à la demande, sauf si une taille fixe est donnée … |
| `collections.collection_errors` | Erreurs communes aux collections de collections.* : noms de types, messages homogènes et vérifications d'arguments partagées. Toutes les collections lèvent par ces fonctions, ce qui garantit des messages identiques d'une … |

### iterator

| Module | Contenu |
|---|---|
| `iterator.iterator` | Itérateurs paresseux et composables. ALEX n'a pas de `yield` : un itérateur est un objet qui produit ses éléments à la demande (has_next / next), qu'on enchaîne en pipeline sans construire de listes intermédiaires, et qu'on peut … |
| `iterator.range` | Progressions arithmétiques PARESSEUSES (aucune liste construite) : entiers ou flottants, pas positif ou négatif ; count() donne une progression sans fin. La forme `a..b` d'ALEX n'existe que dans un `for` ; Range est une valeur … |
| `iterator.enumerate` | Enumerate : associe à chaque élément sa position, paresseusement : rend des paires [position, élément]. |
| `iterator.zip` | Combinaisons d'itérables, paresseuses : Zip(sources) [a0, b0], [a1, b1]... ; s'arrête au plus court ZipLongest(sources, fill) va jusqu'au plus long, complète avec fill ZipWith(sources, f) f(a, b, ...) au lieu d'une liste … |
| `iterator.filter` | Sélections paresseuses : FilterIterator(source, pred) garde les x tels que pred(x) (pred null : valeurs vraies) RejectIterator(source, pred) écarte les x tels que pred(x) FilterMapIterator(source, f) f(x) ; garde les résultats … |
| `iterator.map_iterator` | Transformations paresseuses : chaque élément n'est calculé qu'au moment où il est demandé. |
| `iterator.iterator_errors` | Erreurs des itérateurs : StopIteration next() sur un itérateur épuisé (has_next() aurait rendu false) IteratorError usage invalide : itérable non reconnu, pas négatif, taille de fenêtre nulle... IndexError levée par __getitem__ … |

### algorithm

| Module | Contenu |
|---|---|
| `algorithm.algorithm` | Algorithmes génériques sur les séquences, dans l'esprit de <algorithm> (C++) et d'itertools/heapq/bisect (Python). Tous acceptent une clé (key), un comparateur (cmp) et, pour les tris, reverse. |
| `algorithm.sort` | Tris EN PLACE sur une liste, tous paramétrables par key (clé), cmp (comparateur -> int) et reverse : sort tri fusion STABLE (O(n log n)) — le tri par défaut quick_sort tri rapide à pivot médian de trois, introspectif (repli tas … |
| `algorithm.search` | Recherche linéaire dans une séquence (liste, tuple, str, collection) : find / find_if / find_last / find_last_if position ou -1 count / count_if search(xs, motif) première occurrence d'une sous-séquence (Knuth-Morris-Pratt, O(n + … |
| `algorithm.binary_search` | Recherche dichotomique sur une liste TRIÉE (selon key / cmp), en O(log n) : lower_bound(xs, v) première position où v pourrait être inséré en restant trié (avant les égaux) upper_bound(xs, v) idem après les égaux equal_range(xs, … |
| `algorithm.min_max` | Extrema d'une séquence, avec key / cmp : min / max élément (EmptySequenceError si vide, sauf default fourni) minmax [min, max] en une passe (~1,5 n comparaisons) argmin / argmax position (première en cas d'égalité) min_k / max_k … |
| `algorithm.transform` | Transformations de séquences. Les fonctions « _in_place » modifient la liste reçue ; les autres rendent une NOUVELLE liste. transform / transform_in_place f(x) transform2(a, b, f) f(a[i], b[i]) fill / generate / iota remplissages … |
| `algorithm.reduce` | Réductions et sommes préfixes : reduce(xs, f, init) f(f(f(init, x0), x1), ...) ; sans init : à partir du premier élément fold_left / fold_right accumulate / prefix_sum sommes partielles inclusives (ou f) ; exclusive_scan : … |
| `algorithm.partition` | Partitions selon un prédicat : partition(xs, pred) EN PLACE : les vrais devant ; renvoie le point de partition (non stable) stable_partition(xs, pred) en place, ordre relatif conservé partition_copy(xs, pred) [vrais, faux] … |
| `algorithm.set_operations` | Opérations ensemblistes sur des listes TRIÉES (fusion linéaire, O(n + m), multiensembles respectés comme std::set_union : un élément présent 2 fois d'un côté et 3 de l'autre apparaît 3 fois dans l'union) : merge, set_union, … |
| `algorithm.heap` | Tas binaire DANS une liste ordinaire (comme heapq de Python / std::make_heap de C++) : xs[0] est le plus petit (max=true : le plus grand). La liste reste une liste, utilisable telle quelle ; pour un objet file de priorité … |
| `algorithm.algorithm_errors` | Erreurs des algorithmes : EmptySequenceError opération sans résultat sur une séquence vide (min, max, mean...) UnsortedError entrée qui devait être triée et ne l'est pas (vérification demandée par check=true) AlgorithmError … |

### functional

| Module | Contenu |
|---|---|
| `functional.function` | Fonctions comme valeurs : introspection (nom, arité) et objet Function enveloppant une fonction pour la composer, la décorer et la nommer, tout en restant appelable comme une fonction ordinaire (f(x)). |
| `functional.closure` | Outils bâtis sur les fermetures (fonctions qui capturent leurs variables par référence) : état privé, évaluation paresseuse, appels limités. |
| `functional.lambda` | Fabriques de petites fonctions (comme le module operator de Python). Les lambdas d'ALEX ne contiennent qu'une expression ; ces fabriques couvrent les cas courants sans en écrire. |
| `functional.bind` | Liaison d'arguments, à la std::bind (C++) : on fixe certains arguments et on laisse des ESPACES RÉSERVÉS (_1, _2, ...) que rempliront les arguments de l'appel. Les arguments supplémentaires de l'appel sont ajoutés à la fin. |
| `functional.compose` | Composition de fonctions : compose(f, g, h) x -> f(g(h(x))) (de droite à gauche, notation mathématique) pipe(f, g, h) x -> h(g(f(x))) (de gauche à droite, ordre de lecture) Pipeline construction pas à pas : … |
| `functional.optional` | Optional : une valeur PRÉSENTE ou ABSENTE, explicitement (au lieu d'un null qui circule sans le dire). Inspiré de java.util.Optional / std::optional ; chaînable sans tests de null à chaque étape. |
| `functional.either` | Either : une valeur de l'un de deux côtés — Left (par convention : l'échec, l'alternative) ou Right (le succès, « right » = correct). Les transformations ne s'appliquent qu'au côté Right, un Left traverse la chaîne intact : on … |
| `functional.functional_errors` | Erreurs de la programmation fonctionnelle : EmptyOptionalError get() sur un Optional vide EitherError lecture du mauvais côté d'un Either (left() sur un Right, right() sur un Left) BindError appel d'une fonction liée sans assez … |

### reflection

| Module | Contenu |
|---|---|
| `reflection.reflection` | Réflexion et métadonnées : examiner et manipuler les objets d'après les NOMS de leurs types, champs et méthodes, à l'exécution. S'appuie sur le module natif _native_reflect (registre des classes de la VM). |
| `reflection.type_info` | Description d'un TYPE à l'exécution : nom, genre, héritage, interfaces, méthodes. Les types utilisateur (struct, class) portent un nom COMPLET (qualifié par leur module, ex. « $mod…::ArrayList ») et un nom COURT (« ArrayList ») ; … |
| `reflection.type_traits` | Prédicats sur les valeurs et leurs types (dans l'esprit de <type_traits>) : ce qu'une valeur EST et ce qu'elle SAIT FAIRE (hachage, comparaison, itération, opérateurs). |
| `reflection.type_registry` | Registre de types : créer des objets à partir d'un NOM (désérialisation, greffons, configuration). En ALEX, une classe n'est pas une valeur : on enregistre une FABRIQUE (fonction qui construit l'objet) sous le nom du type, avec … |
| `reflection.field_info` | Champs d'une INSTANCE, par leur nom : lister, lire, écrire, copier, convertir en dict et inversement. (Les champs ALEX sont dynamiques : chaque instance porte les siens ; une même classe peut en avoir de différents selon les … |
| `reflection.method_info` | Méthodes d'un type ou d'un objet, par leur nom : lister (héritage compris), connaître l'arité, appeler, obtenir une méthode liée. |
| `reflection.attributes` | Métadonnées attachées aux types, à leurs champs et méthodes, et aux fonctions (équivalent des attributs C# / annotations Java, qu'ALEX n'a pas en syntaxe). On les déclare une fois, on les lit par réflexion. |
| `reflection.reflection_errors` | Erreurs de la réflexion : UnknownTypeError aucun type de ce nom dans le programme AmbiguousTypeError nom court partagé par plusieurs modules (préciser le nom complet) AttributeError champ ou méthode absent ReflectionError … |

### serialization

| Module | Contenu |
|---|---|
| `serialization.serialization` | Sérialisation : transformer des valeurs ALEX (instances comprises) en texte ou en octets, et inversement, dans plusieurs formats, avec reconstruction des objets et validation par schéma. |
| `serialization.serializer` | Serializer : convertit n'importe quelle valeur ALEX en DONNÉES SIMPLES (null, bool, int, float, str, listes, dicts à clés texte) — la forme commune que les formats (JSON, XML, CSV, binaire, MessagePack) savent écrire. Les … |
| `serialization.deserializer` | Deserializer : reconstruit des valeurs ALEX à partir de données simples produites par serializer (dicts marqués "__type__"). En ALEX une classe n'est pas une valeur : on enregistre, pour chaque type, une FABRIQUE sans argument … |
| `serialization.json` | Objets ALEX <-> JSON : le module json traite les données simples ; celui-ci y ajoute les instances (via serializer / deserializer), les fichiers, les lignes JSON (JSON Lines) et la validation par schéma. |
| `serialization.xml` | Objets ALEX <-> XML. Une valeur devient un élément : null -> <nom type="null"/> bool/int/float -> <nom type="int">42</nom> str -> <nom>texte</nom> liste -> <nom type="list"><item>…</item>…</nom> dict -> <nom … |
| `serialization.csv` | Tables d'objets <-> CSV : une ligne par objet (ou dict), une colonne par champ ; à la lecture, les colonnes sont CONVERTIES selon un schéma (le module csv ne rend que du texte) et peuvent reconstruire des objets. |
| `serialization.binary` | Format binaire compact d'ALEX (« ALXB ») : autodescriptif, typé, sans perte pour les données simples, les octets (Binary) et les instances (via serializer). Plus petit et plus rapide à relire que JSON ; idéal pour les caches, … |
| `serialization.message_pack` | MessagePack (msgpack.org) : format binaire standard, lu par la plupart des langages. Encodage/décodage conformes à la spécification : nil, booléens, entiers (fixint, 8 à 64 bits signés et non signés), flottants (64 bits à … |
| `serialization.schema` | Schémas de données : décrire la forme attendue (types, champs obligatoires, bornes, motifs, valeurs permises, listes, objets imbriqués), VALIDER des données (liste d'erreurs avec leur chemin), les CONVERTIR depuis du texte (CSV, … |
| `serialization.serialization_errors` | Erreurs de la sérialisation : SerializationError valeur impossible à convertir (fonction, futur, cycle, clé non texte en JSON...) DeserializationError données incohérentes avec le format ou le type annoncé, type inconnu (mode … |

### logging

| Module | Contenu |
|---|---|
| `logging.logger` | Loggers HIÉRARCHIQUES à la Python, avec gestionnaires par logger, propagation vers les parents, filtres, contexte structuré et journalisation des exceptions. (Le module logging, lui, reste l'interface simple d'un journal unique ; … |
| `logging.log_level` | Niveaux de journalisation : TRACE 5 < DEBUG 10 < INFO 20 < NOTICE 25 < WARNING 30 < ERROR 40 < CRITICAL 50, et OFF 100 (rien). On les désigne par nom (insensible à la casse, « warn » accepté) ou par nombre ; des niveaux … |
| `logging.log_record` | LogRecord : UN événement de journal — qui (logger), quoi (message et arguments), quand (instant), où (processus, fil), avec quel contexte (champs extra, structurés) et, s'il y a lieu, quelle exception (type, message, trace de … |
| `logging.log_formatter` | Mise en forme des enregistrements : Formatter(fmt, time_format) gabarit : {time} {level} {level:8} (justifié) {name} {message} {pid} {thread} {extra} (clé=valeur...) {exception} et tout champ extra par son nom {clé} JsonFormatter … |
| `logging.log_handler` | Gestionnaires (handlers) : OÙ vont les enregistrements. Un Handler a un niveau minimal, un formateur et des filtres ; les sous-classes redéfinissent emit(texte, enregistrement). Handler base (à étendre : emit) FunctionHandler … |
| `logging.file_handler` | FileHandler : écrit chaque enregistrement à la fin d'un fichier (mode « a ») ou dans un fichier remis à zéro à l'ouverture (mode « w »). Les dossiers manquants sont créés ; delay=true n'ouvre (ne crée) le fichier qu'au premier … |
| `logging.console_handler` | ConsoleHandler : écrit sur la sortie standard ou d'erreur, avec couleurs optionnelles. Par défaut, les niveaux WARNING et plus vont sur stderr, le reste sur stdout (split=true), comme le veulent les outils en ligne de commande … |
| `logging.rotating_handler` | Fichiers de journal à ROTATION : le fichier courant est renommé (app.log -> app.log.1 -> app.log.2 ...) et un nouveau commence, pour borner la place occupée. RotatingFileHandler(path, max_bytes, backup_count) rotation par taille … |
| `logging.logging_errors` | Erreurs de la journalisation : LoggingError configuration invalide (gestionnaire qui n'en est pas un, format inconnu, rotation impossible) ValueError niveau inconnu TypeError argument du mauvais type Une erreur levée PENDANT … |

### testing

| Module | Contenu |
|---|---|
| `testing.test_case` | TestCase : tests regroupés en CLASSE, à la xUnit. Chaque méthode dont le nom commence par « test_ » est un test ; set_up() / tear_down() encadrent chacun d'eux, set_up_class() / tear_down_class() la classe entière. Les méthodes … |
| `testing.test_suite` | TestSuite : un ensemble NOMMÉ de tests — fonctions (nom, fn), instances de TestCase, et sous-suites — avec étiquettes et filtres, à confier à un TestRunner. |
| `testing.test_runner` | TestRunner : exécute une TestSuite (ou une instance de TestCase) — fixtures, chronométrage, classement réussi / échec / erreur / ignoré, arrêt au premier échec si demandé, délai par test signalé — et rend un TestReport … |
| `testing.assertions` | Assertions riches : chaque échec lève AssertionError avec un message qui MONTRE la différence (premier élément différent d'une liste, clés manquantes d'un dict, position du premier caractère différent d'un texte). |
| `testing.mock` | Doublures de test : Mock(return_value, side_effect) objet APPELABLE qui enregistre ses appels ; renvoie return_value, ou une valeur de la liste side_effect à chaque appel, ou appelle side_effect(*args) si c'est une fonction ; … |
| `testing.benchmark` | Mesures de performance : exécutions répétées après échauffement, statistiques robustes (minimum, médiane, moyenne, écart-type, opérations par seconde), comparaison de variantes, tableau de résultats. |
| `testing.property_test` | Tests de PROPRIÉTÉS (à la QuickCheck / Hypothesis) : au lieu de quelques exemples choisis à la main, on énonce une propriété vraie pour TOUTES les entrées, et le module l'essaie sur des centaines d'entrées aléatoires … |
| `testing.test_report` | Résultats d'une exécution de tests et leurs rapports : texte lisible, JUnit XML (Jenkins, GitLab, GitHub Actions...), JSON, et la ligne de synthèse « nom : N OK, M échecs » lue par tests/run_checked.sh. |
| `testing.testing_errors` | Erreurs du cadre de test : AssertionError assertion fausse : le test ÉCHOUE SkipTest levée par skip() dans un test : le test est IGNORÉ (avec sa raison) MockError vérification d'un mock non satisfaite (assert_called_with...) … |

### event

| Module | Contenu |
|---|---|
| `event.event_filter` | Filtres d'événements composables : un filtre est un prédicat sur un événement (event.Event, ou toute valeur pour les filtres génériques), que l'on combine (both / either / negate) et que l'on applique à un écouteur (guard). … |
| `event.event_subscription` | Abonnements : un objet Subscription pour chaque écouteur inscrit sur un EventEmitter, un Dispatcher ou un EventTarget (ou toute source qui rend une fonction de désinscription) — pause / reprise, compteur d'appels, filtre, fin … |
| `event.event_errors` | Erreurs du système d'événements, et outils pour qu'un écouteur défaillant ne casse pas toute la chaîne : EventError usage incorrect (type d'événement vide, écouteur invalide, abonnement terminé) ListenerError un ou plusieurs … |

### window

| Module | Contenu |
|---|---|
| `window.window_geometry` | Géométrie des fenêtres : rectangles (Rect), points et tailles, avec les opérations de placement courantes — intersection, union, marges, centrage, alignement (9 positions), ajustement en gardant les proportions, maintien dans une … |
| `window.window_events` | Événements de fenêtre TYPÉS : les dicts bruts du backend (resize, move, state, focus_in / focus_out, close, close_request, drop, shortcut, key_*, pointer_*, wheel) deviennent des objets avec des champs clairs, et un WindowEvents … |
| `window.window_properties` | Propriétés d'une fenêtre lues et appliquées EN BLOC : titre, position, taille, état, visibilité, focus, style (redimensionnable, décorée, toujours devant, opacité, tailles min / max). read(fenêtre) donne un instantané ; apply() … |
| `window.window_errors` | Erreurs du système de fenêtres et diagnostics : distinguer « pas d'affichage » (serveur graphique absent, session sans écran) de « fenêtre fermée » ou d'un réglage invalide, et proposer la marche à suivre. WindowError erreur … |

### keyboard

| Module | Contenu |
|---|---|
| `keyboard.key_code` | Codes de touches dans TOUS les systèmes de numérotation, autour d'un nom uniforme (keyboard.key) : vk codes virtuels des fenêtres (window / ui, façon Win32 : A = 65) evdev codes du noyau Linux (hardware.keyboard : A = 30) hid … |
| `keyboard.key_mapping` | Correspondances clavier : liaisons raccourci -> ACTION (nommée), par CONTEXTE (global, éditeur, menu... avec héritage), SÉQUENCES de touches (« ctrl+k ctrl+c », comme Emacs / VS Code) avec délai, REMAPPAGE de touches physiques … |
| `keyboard.keyboard_errors` | Erreurs du clavier et diagnostic de l'accès au clavier PHYSIQUE (lecture brute evdev) : KeyboardError erreur générale KeyboardUnavailable aucun clavier lisible (pas de /dev/input, droits insuffisants, conteneur) ShortcutError … |

### mouse

| Module | Contenu |
|---|---|
| `mouse.pointer_position` | Position du pointeur et espaces de coordonnées : PositionTracker position courante et historique, à partir d'événements absolus (fenêtre) ou RELATIFS (souris brute evdev : intégrés, avec courbe d'accélération, et bornés à une … |
| `mouse.mouse_button` | Boutons de la souris dans tous les systèmes de numérotation, autour d'un nom uniforme (left, right, middle, back, forward) : window numéros des événements de fenêtre (1 gauche, 2 droit, 3 milieu) evdev codes du noyau Linux … |
| `mouse.mouse_errors` | Erreurs de la souris et diagnostic de l'accès à la souris PHYSIQUE (lecture brute evdev) : MouseError erreur générale MouseUnavailable aucune souris lisible (pas de /dev/input, droits insuffisants, conteneur) CursorError forme de … |

### input

| Module | Contenu |
|---|---|
| `input.input` | Point d'entrée du paquet input : la couche d'entrées unifiée au-dessus des fenêtres (window) et des périphériques du noyau (hardware, evdev). |
| `input.input_device` | Périphériques d'entrée du système (Linux : /proc/bus/input/devices et /dev/input/eventN) : inventaire avec leur GENRE déduit des capacités annoncées par le noyau (keyboard, mouse, touchpad, touchscreen, gamepad, tablet, other), … |
| `input.input_event` | Événement d'entrée UNIFIÉ, quelle que soit la source (fenêtre, périphérique evdev, programme) et le genre de périphérique (clavier, souris, pavé ou écran tactile, manette, tablette) : InputEvent(kind, code, value, ...) kind : key … |
| `input.input_manager` | Gestionnaire d'entrées d'une application (jeu, kiosque, interface tactile) : réunit plusieurs SOURCES (fenêtre, périphériques evdev ouverts, événements injectés), diffuse des InputEvent unifiés, tient l'état courant (touches et … |
| `input.touch` | Contact tactile simple (un doigt, un stylet, ou le pointeur d'une fenêtre traité comme un doigt) : TouchPoint (identifiant, position, pression, phase began / moved / stationary / ended / cancelled, origine, durée, déplacement) et … |
| `input.multitouch` | Multi-contact (écrans et pavés tactiles) : décodeur du protocole B du noyau Linux — emplacements (ABS_MT_SLOT), identifiants de suivi (ABS_MT_TRACKING_ID, -1 = doigt levé), positions et pression par emplacement, trames terminées … |
| `input.gamepad` | Manettes de jeu : état complet (boutons, sticks normalisés en [-1, 1] avec zone morte, gâchettes en [0, 1], croix directionnelle) construit à partir des événements evdev selon la disposition standard du noyau Linux (BTN_SOUTH = A … |
| `input.gesture` | Reconnaissance de gestes TACTILES à partir des trames de contacts (input.touch / input.multitouch) — ou du pointeur d'une fenêtre vu comme un doigt : tap, double tap, appui long, balayage (swipe : direction, vitesse), déplacement … |
| `input.input_errors` | Erreurs du paquet input et diagnostic des périphériques d'entrée : InputError erreur générale (événement invalide, état incohérent) DeviceNotFound aucun périphérique du genre demandé (clavier, souris, manette, écran tactile...) … |

### hardware

| Module | Contenu |
|---|---|
| `hardware.bus` | Bus de périphériques du système hôte (Linux, /sys/bus) : - Bus : périphériques et pilotes d'un bus (pci, usb, i2c, platform, virtio, hid, scsi...), pilote lié à chaque périphérique, sonde automatique (drivers_autoprobe) ; - … |
| `hardware.device_resource` | Ressources d'un périphérique telles que Linux les publie (lecture seule, sans privilège sauf mention) : - fenêtres PCI du fichier /sys/.../resource (BAR 0 à 5, ROM d'extension, fenêtres de pont) : début, fin, drapeaux (E/S, … |
| `hardware.hardware_errors` | Erreurs d'accès au matériel depuis une application, et diagnostic d'un nœud de périphérique : HardwareError erreur générale HardwareUnavailable périphérique absent (non branché, pilote non chargé, machine virtuelle) … |

### pci

| Module | Contenu |
|---|---|
| `pci.pci_capability` (natif) | Capacités PCI en détail (la liste brute est donnée par PciDevice.capabilities()) : gestion d'énergie état D0..D3hot, changement d'état, PME MSI nombre de messages demandés / alloués, 64 bits, masquage par vecteur, activation … |
| `pci.pci_bar` (natif) | Registres de base (BAR) d'une fonction PCI : décodage d'une valeur brute (genre ports / mémoire 32 / 64 bits, préchargeable, adresse), ACCÈS aux registres d'un périphérique à travers son BAR (BarWindow : lecture et écriture 8 / … |
| `pci.pci_errors` (natif) | Erreurs du paquet pci et vérifications courantes d'un pilote PCI, avec des messages précis : PciError erreur générale (accès à la configuration, valeur incohérente) PciDeviceNotFound aucune fonction PCI ne correspond … |

### interrupt

| Module | Contenu |
|---|---|
| `interrupt.interrupt_vector` (natif) | Vecteurs d'interruption : nom de chaque vecteur (exception, IRQ héritée, GSI, MSI, IPI, minuterie...), ALLOCATEUR de vecteurs par plage (blocs alignés pour le MSI multi-messages, réservations, propriétaires, libération, rapport … |
| `interrupt.interrupt_affinity` (natif) | Affinité des interruptions : sur quels processeurs une interruption peut être livrée. CpuSet (ensemble de processeurs, notation « 0-3,6 » comme /proc/irq/*/smp_affinity_list, masque), table d'affinité par source (IRQ / GSI / … |
| `interrupt.interrupt_errors` (natif) | Erreurs du paquet interrupt, et décodage lisible des EXCEPTIONS du processeur x86-64 (nom, mnémonique, signification du code d'erreur : faute de page — présent, écriture, utilisateur, réservé, instruction —, sélecteur fautif … |

### dma

| Module | Contenu |
|---|---|
| `dma.dma_descriptor` (natif) | Descripteurs DMA : la mise en mémoire des tables que lisent les contrôleurs, à partir d'une liste de segments (dma.dma_mapping.ScatterList) ou d'adresses, pour les formats courants : PRD ATA bus master adresse 32 bits, octets 16 … |
| `dma.dma_coherency` (natif) | Cohérence entre le processeur et les périphériques pour les transferts DMA : - PROPRIÉTÉ d'une zone DMA (processeur ou périphérique) suivie explicitement : give_to_device() synchronise (copie vers le tampon de rebond si besoin) … |
| `dma.dma_errors` (natif) | Erreurs du paquet dma et VÉRIFICATIONS des contraintes qu'un contrôleur impose à ses transferts : masque d'adressage (24 / 32 / 64 bits), alignement, frontière à ne pas traverser (64 Kio pour l'ISA et les PRD ATA, 4 Kio pour les … |

### usb

| Module | Contenu |
|---|---|
| `usb.usb_interface` | Interfaces USB vues comme des FONCTIONS du périphérique : regroupement des réglages alternatifs d'un même numéro d'interface, recherche de points d'accès (sens, type), BANDE PASSANTE des points d'accès périodiques (interruption, … |
| `usb.usb_configuration` | Configurations USB : analyse des octets bruts (y compris les ASSOCIATIONS d'interfaces, IAD, qui regroupent plusieurs interfaces en une seule fonction — webcam UVC, carte réseau CDC-NCM, série CDC-ACM), budget d'ALIMENTATION … |
| `usb.usb_errors` | Erreurs USB et diagnostic : les types d'erreur du paquet usb, la traduction des codes errno renvoyés par usbfs (EPIPE = point d'accès bloqué / STALL, ETIMEDOUT, ENODEV = débranché, EACCES = droits, EBUSY = interface tenue par un … |

### audio

| Module | Contenu |
|---|---|
| `audio.audio_buffer` | Tampons audio de travail (échantillons flottants entrelacés) pour le traitement en flux : RingBuffer tampon CIRCULAIRE de capacité fixe (en trames) entre un producteur (capture, décodeur) et un consommateur (lecture, analyse) : … |
| `audio.audio_output` | Sortie audio de haut niveau au-dessus d'un flux (audio_stream : PlayerStream vers le haut-parleur, WavWriter, MemorySink...) : FILE de tampons à jouer, volume (linéaire ou dB) et sourdine appliqués bloc par bloc, fondus d'entrée … |
| `audio.audio_errors` | Erreurs du son et DIAGNOSTIC de la chaîne audio de la machine : cartes ALSA présentes, outils de lecture et de capture installés (aplay, pw-play, paplay, ffplay / arecord, pw-record, parecord, ffmpeg), serveur de son (PipeWire, … |

### microphone

| Module | Contenu |
|---|---|
| `microphone.capture_session` | Session d'enregistrement pilotée : démarrer, mettre en PAUSE, reprendre, arrêter ; accumulation en mémoire et / ou écriture progressive en WAV ; MARQUEURS horodatés ; durée maximale ; arrêt automatique après un silence prolongé … |
| `microphone.input_levels` | Mesure des NIVEAUX d'entrée, comme un vumètre : crête et efficace (RMS) en dBFS par bloc, BALISTIQUE (montée rapide, retombée lente), maintien de crête, détection d'écrêtage, estimation du BRUIT DE FOND (percentile bas des … |
| `microphone.microphone_errors` | Erreurs du microphone et diagnostic de la capture : micro présent (entrées ALSA), outil de capture installé, serveur de son, droits sur /dev/snd, et vérification d'un enregistrement (silence complet : micro coupé ou mauvais … |

### camera

| Module | Contenu |
|---|---|
| `camera.camera_stream` | Flux d'images au-dessus de n'importe quelle source qui a une méthode read() renvoyant un VideoFrame ou null : camera.camera_capture.CameraCapture (caméra réelle, fichier, mire ffmpeg), FrameListSource (images en mémoire, tests), … |
| `camera.camera_controls` | Réglages de la caméra : - MATÉRIELS par Video4Linux (outil v4l2-ctl) : liste des contrôles proposés par le pilote (luminosité, contraste, saturation, exposition automatique / absolue, balance des blancs, mise au point, gain, … |
| `camera.camera_errors` | Erreurs de la caméra et diagnostic : nœuds /dev/video*, droits (groupe « video »), caméra déjà occupée, outils présents (ffmpeg pour la capture, v4l2-ctl pour les formats et réglages), et vérification d'une image capturée (noire … |

### gpu

| Module | Contenu |
|---|---|
| `gpu.gpu_queue` | Files de commandes pour un gpu.gpu_device.GpuDevice : on enregistre une liste de commandes (CommandList) puis on la soumet ; la file l'exécute dans l'ordre et signale une barrière (gpu.gpu_fence.Fence). - commandes : write … |
| `gpu.gpu_fence` | Synchronisation entre le programme et les files de commandes (gpu.gpu_queue) : - Fence : barrière binaire, signalée quand une soumission est terminée ; wait(timeout) fait avancer la file propriétaire jusqu'à ce point (exécution … |
| `gpu.gpu_errors` | Erreurs du calcul sur carte graphique et diagnostic de l'accès aux cartes : GpuError erreur générale GpuUnavailable aucune carte utilisable (nœuds /dev/dri absents ou illisibles) DeviceLost périphérique perdu (réinitialisation, … |

### graphics

| Module | Contenu |
|---|---|
| `graphics.framebuffer` | Cibles de rendu et affichage : - Framebuffer : plusieurs attachements couleur (graphics.surface.Surface), profondeur, gabarit (stencil) ; suréchantillonnage (samples 4 ou 16 : rendu en 2x / 4x puis réduction par moyenne, « … |
| `graphics.sampler` | Échantillonneur indépendant de la texture (comme VkSampler / GPUSampler) : la même texture peut être lue avec plusieurs réglages. - filtres de réduction (min) et d'agrandissement (mag) : « nearest » ou « linear » ; - mipmaps : « … |
| `graphics.vertex_layout` | Formats de sommets typés, comme les décrivent les API graphiques (Vulkan, WebGPU) : chaque attribut a un nom, un emplacement (location) et un format de composantes : float32 / float32x2 / float32x3 / float32x4, float16x2 / x4, … |
| `graphics.graphics_backend` | Choix du dorsal de rendu et de présentation. Le rendu lui-même est le pipeline logiciel de graphics ; ce qui change d'un dorsal à l'autre est où l'image est présentée et ce qui est disponible sur la machine : « software » … |
| `graphics.graphics_errors` | Erreurs du rendu et vérification des données d'un dessin avant de le lancer : GraphicsError erreur générale ShaderError shader incompatible avec les sommets (attributs manquants, varyings) PipelineError topologie inconnue, état … |

### driver

| Module | Contenu |
|---|---|
| `driver.driver_loader` (natif) | Chargement des pilotes à la demande, comme modprobe : un pilote est décrit par une fabrique (nom, fonction qui crée le pilote, dépendances, version d'API demandée) ; le chargeur - charge un pilote et ses dépendances dans l'ordre … |
| `driver.driver_lifecycle` (natif) | Cycle de vie des périphériques liés à un pilote, au-dessus de driver.driver_manager : |
| `driver.driver_version` (natif) | Versions des pilotes et compatibilité : - Version : « majeur.mineur.correctif[-pré] » (« 1.4 » vaut 1.4.0), comparaison (une pré-version est antérieure à la version finale : 2.0.0-rc1 < 2.0.0) ; - contraintes : « >=1.2 », « <2 », … |
| `driver.driver_permissions` (natif) | Ce qu'un pilote a le droit de toucher : plages de ports d'E/S, plages de mémoire (MMIO), lignes d'interruption, accès DMA (avec masque d'adresses), bus. Les droits sont accordés à partir des ressources du périphérique lié (BAR … |

### storage_driver

| Module | Contenu |
|---|---|
| `storage_driver.storage_request` (natif) | Requêtes d'E/S complètes pour les pilotes de blocs (complément de storage_queue) : - IoRequest : opération, premier bloc, segments (listes dispersées : plusieurs tampons), priorité, délai en « ticks », nombre de nouvelles … |
| `storage_driver.storage_partition` (natif) | Création et vérification de tables de partitions GPT (UEFI) sur un BlockDevice — la lecture est dans storage_driver.disk : - GptLayout : partitions prévues (nom, type, taille en blocs ; 0 = le reste), alignement (2048 blocs = 1 … |
| `storage_driver.storage_cache` (natif) | Cache de blocs avec lecture anticipée (complément de block_device.BlockCache) : - détection des lectures séquentielles : la fenêtre d'anticipation double (de min_ahead à max_ahead blocs) tant que les lectures se suivent, et … |
| `storage_driver.storage_errors` (natif) | Erreurs du stockage et décodage des codes d'erreur des contrôleurs : StorageError erreur générale MediaError secteur illisible / écriture impossible ReadOnlyError support en lecture seule OutOfRangeError bloc hors du disque … |

### network_driver

| Module | Contenu |
|---|---|
| `network_driver.network_interface` (natif) | Table des interfaces et routage IPv4 au-dessus des pilotes (NetworkDevice) : - Iface : nom (eth0, lo...), périphérique, état administratif (up / down) et lien, MTU (bornée par la carte), adresses IPv4 avec longueur de préfixe, … |
| `network_driver.network_ring` (natif) | Anneaux de descripteurs génériques pour cartes réseau (émission et réception) : - DescFormat : position des champs dans un descripteur (adresse du tampon, longueur, commande, état, bit « fait » DD, bit « fin de paquet » EOP) — … |
| `network_driver.network_offload` (natif) | Délestage (offload) : ce que la carte peut faire à la place du processeur, et l'équivalent logiciel quand elle ne le peut pas : - Features : capacités (sommes de contrôle en émission / réception, TSO, retrait / insertion VLAN, … |
| `network_driver.network_driver_errors` (natif) | Erreurs des pilotes réseau et vérification des trames : NetworkDriverError erreur générale LinkDown lien physique absent RingFull anneau d'émission plein NoBuffer plus de tampon de réception FrameError trame trop courte / longue, … |

### usb_driver

| Module | Contenu |
|---|---|
| `usb_driver.usb_mass_storage` (natif) | Stockage de masse USB : tout ce qu'il faut autour du transport « Bulk-Only » (usb_class.MassStorage) pour les clés et disques réels : - CBW / CSW : construction et analyse en mémoire (signatures, étiquette, résidu, état 0 / 1 / 2 … |
| `usb_driver.usb_hid` (natif) | HID générique (au-delà du protocole d'amorçage de usb_class) : analyse du DESCRIPTEUR DE RAPPORT et décodage des rapports de n'importe quel périphérique HID (claviers complets, souris à molettes et boutons multiples, manettes, … |
| `usb_driver.usb_serial` (natif) | Ports série USB : - CDC-ACM (classe 02 / sous-classe 02, interface de données classe 0A) : modems, cartes Arduino, la plupart des microcontrôleurs ; LineCoding (débit, bits de données, parité, bits d'arrêt) codé sur 7 octets, … |
| `usb_driver.usb_driver_errors` (natif) | Erreurs des pilotes USB du noyau et décodage des états de transfert : UsbDriverError erreur générale UsbStall le périphérique a refusé (STALL : requête non UsbTimeout pas de réponse (CRC/délai) prise en charge ou point d'accès … |

### gpu_driver

| Module | Contenu |
|---|---|
| `gpu_driver.gpu_device_binding` (natif) | Liaison des cartes graphiques à leurs pilotes, avec ce qui est propre à l'affichage : - classification PCI (classe 03) : VGA compatible (03:00, interface 00), contrôleur XGA, 3D (03:02), autre ; carte d'amorçage (« boot VGA ») = … |
| `gpu_driver.gpu_scheduler` (natif) | Ordonnanceur du moteur 2D : plusieurs clients (contextes : bureau, application, console) soumettent des tampons de commandes (gpu_command.CommandBuffer) ; l'ordonnanceur les exécute sur le moteur (GpuEngine) chacun sur sa surface … |
| `gpu_driver.gpu_firmware` (natif) | Micrologiciels et données fournies par le matériel graphique : - ROM d'extension PCI (VBIOS) : chaîne d'images (signature 55 AA, structure « PCIR » : fabricant, périphérique, classe, longueur, type de code x86 / Open Firmware / … |
| `gpu_driver.gpu_driver_errors` (natif) | Erreurs des pilotes graphiques du noyau : GpuDriverError erreur générale ModeError mode vidéo non pris en charge / refusé VramExhausted mémoire vidéo épuisée GpuHang moteur bloqué (budget de commandes dépassé) FirmwareError ROM / … |

### network

| Module | Contenu |
|---|---|
| `network.ip_address` | Adresses de POINTS DE TERMINAISON (adresse IP + port) et outils autour des adresses : analyse et écriture de « hôte:port » (IPv6 entre crochets, zone %eth0), résolution d'un nom en points de terminaison, adresses locales, octets … |
| `network.https` | HTTPS strict, au-dessus de network.http_client et network.tls : - refuse toute URL http:// et toute redirection vers http:// (pas de rétrogradation) ; - vérification des certificats TOUJOURS active (autorité système ou ca_file … |
| `network.network_errors` | Diagnostic des erreurs réseau, en complément de network.errors (types et hiérarchie, dont ce module reprend les noms) : fiche structurée d'une erreur (classify), explications en français des codes errno, statuts HTTP traduits en … |

### filesystem

| Module | Contenu |
|---|---|
| `filesystem.file` | Opérations sur des FICHIERS entiers (le contenu ligne à ligne est dans le module file) : copie avec politique d'écrasement et vérification, comparaison de contenu, empreintes, sauvegarde avec rotation, remplacement sûr, … |
| `filesystem.directory` | Directory : un dossier comme OBJET — contenu, recherche, taille, copie, synchronisation (miroir), et comparaison de deux arborescences. |
| `filesystem.path` | Path : un chemin comme OBJET (à la pathlib de Python). Calculs lexicaux par le module path, accès au disque par os / file / filesystem : on enchaîne au lieu d'imbriquer des appels. |
| `filesystem.metadata` | Métadonnées d'un chemin, en un objet : genre (fichier, dossier, lien, tube, socket, périphérique), taille, droits, propriétaire, dates (modification, accès, changement d'état), inode et périphérique (identité du fichier : deux … |
| `filesystem.permissions` | Droits des fichiers (POSIX) : lecture, notation symbolique et octale, modifications à la chmod (« u+x », « go-w », « a=r »), tests d'accès pour l'utilisateur courant, bits spéciaux. |
| `filesystem.watch_service` | WatchService : surveillance de dossiers à la manière de java.nio WatchService — on ENREGISTRE des dossiers (avec les genres d'événements voulus et des filtres de noms), puis on récupère des CLÉS portant les événements de chaque … |
| `filesystem.filesystem_mount` | Points de montage : quels systèmes de fichiers sont montés, où, avec quel type et quelles options ; sur quel montage se trouve un chemin ; espace disque de chacun. |
| `filesystem.filesystem_errors` | Erreurs du système de fichiers, PRÉCISES (les primitives lèvent IoError ; ce module en déduit le cas) : FileNotFoundError chemin absent FileExistsError création exclusive d'un chemin qui existe NotADirectoryError dossier attendu … |

### security

| Module | Contenu |
|---|---|
| `security.security` | Socle du paquet security : types d'erreur, comparaison en temps constant, effacement des listes d'octets, conversions octets <-> texte, et classement des niveaux de gravité. Les autres modules du paquet : random_secure (entropie … |
| `security.access_control` | Contrôle d'accès : rôles (RBAC) avec héritage, permissions hiérarchiques à jokers (« docs.* », « * »), et listes de contrôle d'accès (ACL) par ressource avec règles allow / deny — un refus explicite l'emporte toujours. explain() … |
| `security.capability` | Sécurité par capacités : 1. Jetons de capacité SIGNÉS (à la manière des « macaroons ») : un émetteur détenant une clé secrète délivre un jeton portant une ressource, des droits et une échéance ; tout détenteur peut l'ATTÉNUER … |
| `security.sandbox` | Exécution confinée de code non fiable, à deux niveaux : 1. Sandbox (processus) : le programme ALEX (ou une commande) tourne dans un PROCESSUS FILS avec limites du noyau posées avant son démarrage (temps processeur, mémoire, … |
| `security.secure_memory` | Secrets en mémoire protégée : un SecureBuffer place ses octets dans des pages dédiées (mmap), VERROUILLÉES en mémoire vive quand le système le permet (mlock : jamais écrites dans le swap), rendues INACCESSIBLES (PROT_NONE) en … |
| `security.credential_store` | Coffres de secrets (identifiants, jetons, clés d'API) : CredentialStore(chemin, mot_de_passe) fichier CHIFFRÉ (enveloppe authentifiée de crypto_provider, clé dérivée du mot de passe maître par PBKDF2) écrit atomiquement, mode … |
| `security.crypto_provider` | Fournisseurs cryptographiques interchangeables, avec une API unique : « openssl » libcrypto (OpenSSL 3) par FFI, si elle est installée : SHA-2 natifs, PBKDF2 natif (EVP_KDF), chiffrement authentifié ChaCha20-Poly1305 et … |
| `security.random_secure` | Nombres aléatoires CRYPTOGRAPHIQUES, tirés de l'entropie du système d'exploitation : getrandom(2) (Linux, par FFI) ou /dev/urandom. À utiliser pour les clés, sels, nonces, jetons de session, mots de passe — jamais le module … |
| `security.security_audit` | Audit de sécurité : AuditLog : journal d'événements de sécurité INFALSIFIABLE — chaque entrée contient l'empreinte (SHA-256, ou HMAC avec une clé) de la précédente ; modifier, supprimer ou réordonner une entrée casse la chaîne, … |

### database

| Module | Contenu |
|---|---|
| `database.database` | Point d'entrée du paquet database : ouvrir une base, connaître les moteurs disponibles, et raccourcis. |
| `database.connection` | Connexion à une base de données. Deux moteurs : « alexdb » moteur SQL embarqué écrit en ALEX (toujours disponible) : en mémoire, ou persistant dans un fichier JSON réécrit atomiquement à chaque validation « sqlite » SQLite 3 réel … |
| `database.query` | Construction de requêtes SQL par méthodes chaînées, avec paramètres liés (jamais de valeurs collées dans le texte) : SELECT (colonnes, jointures, conditions, groupement, tri, pagination), INSERT, UPDATE, DELETE. |
| `database.transaction` | Transactions : tout ou rien. Une Transaction ouverte alors qu'une autre est déjà en cours devient un POINT DE SAUVEGARDE (SAVEPOINT) : on peut annuler une partie sans tout perdre (transactions imbriquées). |
| `database.prepared_statement` | Requête préparée : le texte SQL est analysé (ou compilé par SQLite) UNE fois, puis exécuté autant de fois que voulu avec des paramètres différents — plus rapide pour les insertions en série, et sûr : les valeurs ne sont jamais … |
| `database.result_set` | Résultat d'une requête : noms de colonnes, lignes, nombre de lignes touchées et dernier identifiant inséré. Lecture par curseur (fetch_one / fetch_many / fetch_all), par index (rs[0]), par itération (for ligne in rs), en … |
| `database.database_pool` | Réserve (pool) de connexions réutilisables vers une même base : évite de rouvrir une connexion à chaque requête et borne leur nombre. Une connexion rendue est remise à zéro (transaction en cours annulée). Avec « memory:nom », … |
| `database.database_errors` | Types d'erreur du paquet database (inspirés de la DB-API Python) et classement des erreurs SQLite. DatabaseError erreur générale (base fermée, opération impossible) ConnectionError ouverture impossible, URL inconnue, connexion … |

### ui

| Module | Contenu |
|---|---|
| `ui.component` | Composants RÉUTILISABLES et à ÉTAT pour ui.view (affichés par gui.run ou tui.run) : une classe Component a des propriétés (props, données d'entrée), un état propre (state) et une méthode render() qui rend l'arbre ui.view. … |
| `ui.dialog` | Dialogues pour les interfaces ui.view (fenêtre ou terminal) : une PILE de dialogues modaux gérée par un DialogManager — message, confirmation, saisie de texte avec validation, choix dans une liste, progression — avec des rappels … |
| `ui.accessibility` | Accessibilité des interfaces ui.view : arbre d'accessibilité (rôle, nom accessible, état, focalisable) calculé à partir de l'arbre de la vue, ordre de tabulation, linéarisation telle qu'un lecteur d'écran l'énoncerait, et AUDIT … |
| `ui.ui_renderer` | Rendus d'une interface ui.view SANS écran, pour les tests, la documentation et l'export : render_text(vue, l, h) l'écran réel produit par le moteur terminal (tui) sur un terminal virtuel render_screen_html(...) le même écran en … |

### compiler

| Module | Contenu |
|---|---|
| `compiler.lexer` | Analyseur lexical d'ALEX écrit en ALEX : le texte source devient une liste de jetons, avec exactement les règles du compilateur natif (src/Lexer.cpp) — indentation structurante (INDENT / DEDENT, espaces seulement), NEWLINE en fin … |
| `compiler.parser` | Analyseur syntaxique d'ALEX écrit en ALEX (descente récursive) : jetons de compiler.lexer -> arbre de compiler.ast. Même grammaire et mêmes priorités que le compilateur natif (src/Parser.cpp) : déclarations (func / async func / … |
| `compiler.ast` | Arbre syntaxique abstrait d'ALEX. Chaque nœud est un Node : un genre (kind), une position (line, column) et des champs nommés accessibles directement (n.left, n.body...). L'arbre est FIDÈLE au texte : with, assert, del, pass, … |
| `compiler.type_checker` | Analyse sémantique et vérification de types statique (légère) d'un arbre compiler.ast. Elle reprend les règles du compilateur natif (src/Analyzer.cpp) — portée par blocs, hissage des func / class / struct / enum / interface, noms … |
| `compiler.ir` | Représentation intermédiaire (IR) à pile, abaissement (lowering) depuis compiler.ast, et interpréteur de référence. L'IR est simple et lisible — une liste d'instructions par fonction, des étiquettes symboliques pour les sauts — … |
| `compiler.optimizer` | Optimisations sur l'arbre (compiler.ast) et sur l'IR (compiler.ir), sans changer le sens du programme : AST : repliement des constantes (1 + 2 * 3 -> 7, "a" + "b", not true, comparaisons), propagation des `const` de module dont … |
| `compiler.codegen` | Génération de code et chaîne de compilation complète. emit_alex(arbre) source ALEX formatée (indentation 4 espaces, parenthèses minimales selon les priorités) : sert de formateur et garantit l'aller-retour parse(emit(arbre)) == … |
| `compiler.linker` | Édition des liens de modules IR (compiler.ir) : table des symboles exportés, résolution des imports (use m / from m use a, b), détection des modules absents, des symboles introuvables, des doublons et des cycles d'import ; ordre … |
| `compiler.diagnostics` | Diagnostics du compilateur : erreurs, avertissements et notes, avec position (fichier, ligne, colonne, étendue), code (« E0101 », « W0201 »...), notes complémentaires, et un rendu lisible qui cite la ligne fautive et la souligne … |
| `compiler.source_map` | Positions dans les sources et correspondances source ↔ code généré. SourceFile(nom, texte) décalage <-> (ligne, colonne), texte d'une ligne, extrait avec contexte SourceMap() correspondances (ligne_gen, col_gen) -> (fichier, … |

### modules

| Module | Contenu |
|---|---|
| `modules.module` | Description STATIQUE d'un module ALEX à partir de son source (sans l'exécuter) : imports (`use`, `from … use …`), noms exportés (func, class, struct, interface, enum, const et variables de premier niveau), en-tête de … |
| `modules.module_loader` | Résolution et chargement STATIQUE des modules, avec les mêmes racines que le compilateur (src/ModuleResolver.cpp) : stdlib, projet, dossier du fichier d'entrée et ses parents, alex_packages. Permet d'outiller un projet : graphe … |
| `modules.package` | Le manifeste d'un paquet ALEX (alex.toml) et son verrou (alex.lock), lus et écrits en ALEX — même format que `alexc pkg` (src/Manifest.cpp) : sous-ensemble de TOML (sections, chaînes, tables en ligne, commentaires). |
| `modules.package_manager` | Gestion des paquets d'un projet depuis un programme ALEX : - lecture locale (sans rien exécuter) : paquets installés dans alex_packages/, verrou alex.lock, contenu du registre local ($ALEX_REGISTRY, ~/.alex/registry), … |
| `modules.dependency` | Dépendances et graphes de dépendances : ordre de construction (tri topologique), détection de cycles, dépendances transitives, et RÉSOLUTION de versions (choisir, pour chaque nom, une version qui satisfait toutes les contraintes … |
| `modules.version` | Versions sémantiques (SemVer 2.0.0) et contraintes — mêmes règles que le gestionnaire de paquets (`alexc pkg`, src/Semver.cpp), plus les intervalles composés. |
| `modules.abi` | ABI binaire : tailles, alignements et DISPOSITION des structures C selon la plateforme, pour échanger des données avec du code natif (ffi, fichiers binaires, pilotes) sans deviner les décalages. |
| `modules.plugin` | Système de greffons (plugins) : des composants qui s'enregistrent auprès d'une application, déclarent leurs dépendances entre eux, sont activés dans le bon ordre, et étendent l'application par des POINTS D'EXTENSION (hooks). |

### diagnostics

| Module | Contenu |
|---|---|
| `diagnostics.profiler` | Profilage du temps d'exécution, de deux façons : 1. Profileur NATIF de la VM (`alexc run --profile=rapport.json`) : profile_script(fichier) exécute un programme dans un processus fils avec le profileur intégré et relit son rapport … |
| `diagnostics.cpu_stats` | Utilisation du processeur : temps CPU du processus et de ses fils système (utilisateur / noyau), taux d'occupation de la machine entre deux échantillons (global et par cœur, Linux : /proc/stat), charge moyenne, fréquence courante … |
| `diagnostics.memory_profiler` | Profil mémoire : ce qu'un bloc de code alloue et retient (mémoire native, objets ALEX du ramasse-miettes, mémoire résidente du processus), suivi d'étapes nommées, chronologie d'échantillons et pic observé. |
| `diagnostics.trace` | Traçage d'exécution : intervalles (spans) imbriqués avec attributs et événements, journal des appels de fonctions tracées, et export au format Chrome Trace Event (ouvrable dans chrome://tracing ou Perfetto) ou en JSON simple. |
| `diagnostics.crash_report` | Rapports de plantage : à partir d'une erreur rattrapée, un rapport complet et autonome — type et message, pile d'appels avec les lignes de source (et un extrait autour de la ligne fautive), contexte du processus (pid, arguments, … |
| `diagnostics.stack_trace` | Piles d'appels : celle du point courant (current), celle d'une erreur rattrapée (from_error), sous forme de cadres StackFrame (fonction, fichier, ligne) avec le texte source de chaque ligne, et un rendu lisible. |
| `diagnostics.performance_counter` | Compteurs de performance : chronomètres de haute résolution (horloge monotone), compteurs nommés d'événements et de mesures (nombre, total, min, max, moyenne, débit), minuteries utilisables avec `with`. |

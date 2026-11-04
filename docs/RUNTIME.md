# Runtime ALEX — spécification formelle

Cette spécification décrit le runtime tel qu'il est **implémenté** (`include/alex/rt/*`, `src/Value.cpp`,
`src/Heap.cpp`, `src/VM.cpp`, `include/alex/RuntimeError.hpp`). Les règles sont numérotées ; chacune est
vérifiée par un test (§11). Les mots DOIT / NE DOIT PAS / PEUT ont leur sens habituel (RFC 2119). Les écarts
connus entre l'intention et l'implémentation sont listés au §10 : **ils ne sont pas cachés dans les règles**.

```
source ─ Lexer ─ Parser ─ Analyzer ─ Compiler ─▶ BcModule ─ mergeModules ─▶ VM::run
                                                               │
                         Value · Obj · Heap  ◀── allocation ───┤──▶ natives (_native_*)
                                                               └──▶ Scheduler (tâches, futurs)
```

## 1. Vocabulaire et hypothèses

- **Monothread coopératif** : un seul fil d'exécution C++. La concurrence ALEX (`async`/`await`) est
  coopérative : les coroutines ne s'entrelacent qu'aux points `await`. Aucune règle de ce document n'exige de
  synchronisation.
- **Heap** : l'ensemble des `Obj` alloués par `Heap::allocate`. **Racine** : valeur déclarée atteignable par
  l'appelant d'une collecte (§4).
- Les messages d'erreur sont en français ; seuls les **types** d'exception (§7) font partie du contrat.

## 2. Valeur (`Value`)

**V1 — Représentation.** Une `Value` est une union étiquetée de **16 octets** : une étiquette
(`Null Bool Int Float Char Byte Obj`) et 8 octets de charge. Elle se copie par valeur (pas de comptage de
références). La valeur par défaut est `null`.

| Étiquette | Charge | Domaine |
|---|---|---|
| `Null` | — | une seule valeur |
| `Bool` | `bool` | `true` / `false` |
| `Int` | `int64_t` | complément à deux |
| `Float` | `double` | IEEE-754 binaire64 |
| `Char` | `uint32_t` | point de code Unicode scalaire |
| `Byte` | `uint8_t` | 0..255 |
| `Obj` | `Obj*` | pointeur non propriétaire vers un objet du heap ; peut être nul (traité comme `null`) |

**V-arith — Arithmétique.** `+ - *` sur `int` bouclent modulo 2^64 (jamais d'erreur de débordement) ;
`/` rend toujours un `float` ; `//` et `%` arrondissent vers −∞ (le signe de `%` est celui du diviseur) ;
`**` entier rend un `int`, un exposant négatif rend un `float`. Une division (`/ // %`) par zéro lève
`ZeroDivisionError`, **y compris `float / 0.0`** (pas d'`inf` produit par division). Un décalage hors
`0..63` (`0..7` sur `byte`) lève `TypeError`.

**V-truth — Vérité.** Exactement cinq valeurs sont *falsy* : `false`, `null`, `0`, `0.0` (et `-0.0`), `""`.
Tout le reste est *truthy* : `char`/`byte` (même `0`), `NaN`, toute collection (même vide), fonction, instance.

**V-eq — Égalité (`==`).** Scalaires de même étiquette : par valeur. `int` ↔ `float` : par valeur numérique
**exacte** (`1 == 1.0` ; `9007199254740993 != 9007199254740992.0`). `NaN != NaN`. Étiquettes différentes
(autres que int/float) : inégales (`true != 1`). Objets : identité d'abord ; sinon `str`, `list`, `tuple`, `dict`
par structure (même type d'objet requis : `[1] != (1, 2)`) ; `function`, `native`, `exception`, `instance`,
`cell`, `future` par identité seule. L'égalité structurelle d'objets plus profonds que **2000 niveaux** (donc
cycliques) lève `RecursionError` ; `a == a` reste vrai (identité).

**V-hash — Hachage (clés de dictionnaire).** Sont hashables : `null bool int char byte`, `float` non-NaN,
`str`, `tuple` dont tous les éléments sont hashables. Les autres lèvent `TypeError`. **Invariant :** si
`a == b` et que les deux sont hashables, alors `hash(a) == hash(b)` — un `float` entier hache comme l'`int`
égal, donc `d[1]` et `d[1.0]` désignent la même clé. **V-order — Ordre des dict.** Un `dict` itère
(`for`, `keys`, `values`, `items`, affichage) dans l'**ordre d'insertion** ; réaffecter une clé garde sa place,
une clé supprimée puis réinsérée passe à la fin. L'égalité `==` ignore l'ordre.

**V-type — Noms de types** (`typeName`) : `null bool int float char byte str list tuple dict function native
exception instance cell future task`. Une tâche (`future` avec coroutine) s'appelle `task`.

**V-display — Affichage** (`toDisplayString`, utilisé par `print` et `str`) : `null`, `true`/`false`, entiers
décimaux, flottants avec au moins `.0` (15 chiffres significatifs), `str` brute, `[a, b]`, `(a,)`, `{k: v}`,
`<function nom>`, `type: message` pour une exception. Une collection qui se contient s'affiche `[...]`,
`(...)`, `{...}` à l'endroit du cycle.

## 3. Objets (`Obj`)

**O1 — Types.** Tout objet dérive de `Obj` (`type`, `marked`, `next`, destructeur virtuel). Les types sont
exactement : `String List Tuple Dict Function Native Exception Instance Cell Future`.

| Type | Contenu | Mutabilité | Enfants pour le GC |
|---|---|---|---|
| `String` | octets UTF-8 (peut contenir NUL) | immuable | — |
| `List` | `vector<Value>` | mutable | éléments |
| `Tuple` | `vector<Value>` | immuable après construction | éléments |
| `Dict` | table `Value → Value` (clés hashables) | mutable | clés **et** valeurs |
| `Function` | `functionId`, arités, `closureEnv`, `boundReceiver` | immuable | `closureEnv`, `boundReceiver` |
| `Native` | `name`, `std::function` | immuable | — (voir N-GC) |
| `Exception` | `exceptionType`, `message` (deux `std::string`) | immuable | — |
| `Instance` | `typeName`, `fields: nom → Value` | mutable | tous les champs |
| `Cell` | une `Value` + drapeau d'initialisation | mutable | la valeur |
| `Future` | état, valeur, attendants, coroutine | mutable | valeur, attendants, chaînés, attendu, frames (locaux, `closureEnv`), pile, `pendingThrow` |

**O2 — Propriété.** Un `Obj` appartient au seul `Heap` qui l'a créé ; personne d'autre ne fait `new`/`delete`
dessus. **O3 — Identité.** Un objet ne bouge jamais : son adresse est stable pendant toute sa vie (le GC est non
déplaçant). **O4 — Cellules.** `Cell` n'est jamais visible du code utilisateur : le compilateur « boxe » une
variable locale capturée par une fermeture ; la déclarante et toutes les fermetures partagent la même cellule.

## 4. Heap et collecte

**H1 — Allocation.** `Heap::allocate<T>(args…)` construit un `T` (dérivé d'`Obj`), le chaîne dans la liste
intrusive du heap et incrémente `liveObjects` et `totalAllocated`. Elle ne déclenche **jamais** de collecte.
**H2 — Collecte.** `collectGarbage(racines)` est un *mark-and-sweep* non générationnel, non déplaçant :
marque tout ce qui est atteignable depuis les racines, puis détruit (`delete`) tout objet non marqué ;
`totalFreed` compte les destructions. Les racines non-objet (`int`, `null`…) sont ignorées. **H3 —
Exhaustivité.** L'accessibilité est transitive à travers *tous* les enfants du tableau du §3. **H4 — Cycles.** Un
cycle inaccessible est collecté ; un cycle enraciné survit. **H5 — Marquage itératif.** Le marquage utilise une
pile explicite : une chaîne de 200 000 objets ne déborde pas la pile C++. **H6 — Seuil.** `maybeCollect`
ne collecte que si `liveObjects ≥ seuil` (64 au départ) ; après une collecte le seuil devient
`max(64, 2 × liveObjects)`. **H7 — Destruction.** Libérer un objet exécute son destructeur C++ ; en
particulier, libérer un `ObjNative` détruit la `std::function` et donc tout ce qu'elle capture (mécanisme
utilisé par `memory.buffer` pour libérer un bloc natif : §8, N8).
**H8 — Fin de programme.** `~Heap` détruit tous les objets restants.
**H9 — Point sûr.** La VM ne collecte qu'**en tête de la boucle d'exécution, entre deux instructions** : à cet
instant aucune `Value` vivante n'est détenue par une variable locale C++ d'un opcode. Les natives, qui s'exécutent
à l'intérieur d'une instruction, ne sont donc jamais interrompues par une collecte (N4).
**H10 — Déclenchement.** À chaque point sûr, la VM teste `Heap::shouldCollect()` (`liveObjects ≥ seuil`, test
bon marché) ; si vrai, ou si une collecte a été demandée (`gc.collect()`), elle construit les racines et appelle
`Heap::collect`, qui recalcule le seuil (H6). Le déclenchement est fondé sur le **nombre d'objets, pas sur leur
taille en octets** (un petit nombre de très gros objets peut retarder une collecte ; `gc.collect()` la force).
**H11 — Racines (ensemble exact, exigé et fourni par `VM::run`).** (1) la pile d'opérandes ; (2) pour chaque frame
de la coroutine courante : tous les locaux et `closureEnv` ; (3) les constantes du module en cours ; (4) les
globales ; (5) les exports de tous les modules natifs enregistrés ; (6) l'exception en attente ; (7) le futur du
programme principal ; (8) via l'ordonnanceur : la tâche courante, la file des prêtes, les minuteurs (futur et
cible), et les tâches encore actives ou échouées non lues. Les coroutines suspendues sont atteintes depuis
leur `Future` (frames, pile, `pendingThrow`, attendants). Les tâches **terminées** sont élaguées de l'ordonnanceur à
chaque collecte (leurs pointeurs deviendraient pendants) ; une tâche bloquée à jamais mais encore « active »
reste enracinée (fuite bornée, jamais d'accès invalide).
**H12 — Diagnostic.** `ALEX_GC=0` désactive le déclenchement automatique ; `ALEX_GC_STRESS=N` collecte toutes les
`N` instructions ; `ALEX_GC_POISON=1` active le mode poison (`Heap::setPoison`) : un objet libéré est rempli de
`0xDD` et jamais rendu à l'allocateur, et le marquage abandonne le processus s'il rencontre un objet empoisonné.
Une racine oubliée devient ainsi une erreur déterministe. (Le mode poison **retient** la mémoire libérée : à
réserver à la validation.) Module `gc` : `stats()`, `collect()`, `enable()/disable()`, `set_threshold()`, `set_stress()`.

## 5. Modèle mémoire

**M-alias — Sémantique de référence.** Les scalaires et `str`/`tuple` se comportent comme des valeurs ; `list`,
`dict`, instances et fonctions sont des **références partagées** : `b := a` crée un alias, une mutation est
visible par tous les alias. Réaffecter un paramètre ne modifie jamais l'appelant.
**M-closure — Capture par référence.** Une fermeture lit et écrit la *même* variable que sa déclarante, y compris
après le retour de celle-ci ; chaque appel de la déclarante crée de nouvelles cellules ; chaque itération
d'une boucle `for` crée une variable fraîche.
**M-eval — Ordre d'évaluation.** Les arguments sont évalués de gauche à droite.
**M-cycle — Structures cycliques.** Les cycles sont licites (`append(a, a)`) ; affichage et collecte les gèrent
(V-display, H4) ; l'égalité structurelle de deux cycles distincts lève `RecursionError` (V-eq).
**M-ext — Mémoire hors heap.** La mémoire native (`memory`, `ffi`) vit hors du heap ALEX : le GC ne la voit
pas. Elle est désignée par des identifiants entiers jamais recyclés (voir `docs/MEMORY.md`).
**M-order — Pas de finaliseurs utilisateur, pas de références faibles** dans le noyau (`memory.reference.Weak`
est un comptage explicite, pas une référence faible du GC).

## 6. Modèle d'exécution (résumé normatif)

La VM exécute un `BcModule` fusionné. Le programme principal est une coroutine ; chaque appel ALEX empile un
`Frame` (`functionId`, `ip`, `locals`, `closureEnv`, `handlers`). Un appel de fonction native ne crée pas de
frame. Le point d'entrée du module fusionné est identifié par **identité** (`functionId`), jamais par position
(règle E-top, corrigée : une lambda sans paramètre de haut niveau ne remplace pas le programme).
**L-depth :** un appel qui ferait dépasser `maxCallDepth` (100 000 frames par coroutine, `VM::setMaxCallDepth`)
lève `RecursionError`. La pile d'opérandes n'a pas de limite propre.

## 7. Exceptions

**E1 — Valeur.** Une exception est un `ObjException { exceptionType, message, trace }`. Le *type* est une chaîne
libre. Membres lisibles depuis ALEX : `e.type`, `e.message`, `e.trace` (liste de `str` « fichier:ligne, dans
fonction », appel le plus récent en dernier).
**E2 — Origines.** (a) erreur du runtime : un `alex::RuntimeError(code, message)` C++ est converti en
exception dont le type est le nom du code ; (b) `raise(type, message)` : deux `str`, sinon `TypeError`
(`E-code`) ; (c) `THROW` d'une valeur : une `ObjException` est propagée telle quelle, toute autre valeur est
enveloppée (`type = "Exception"`, `message =` affichage) ; (d) `raise(e)` où `e` est une exception : **relance
le même objet** (identité, type, message et trace conservés).

**E-code — Codes du runtime** (`RuntimeErrorCode`) : `TypeError ZeroDivisionError IndexError KeyError NameError
ArgumentError ImportError AttributeError IoError ValueError MemoryError RecursionError`. Les bibliothèques ALEX
lèvent d'autres types libres (`ArgparseError`, `UnsafeError`, `StaleViewError`…).

**E3 — Handlers.** `try` installe un handler **sur le frame courant** (`TRY_BEGIN` : cible du `catch`, local de
liaison, profondeur de pile à l'installation). Les handlers d'un frame forment une pile ; le plus récent est le
plus interne.
**E-unwind — Désenroulage.** Quand une exception est levée : on cherche, du frame courant vers l'appelant, le
premier frame ayant un handler ; les frames sans handler sont détruits ; le handler trouvé est **consommé**.
**E-stack — Reprise.** La pile d'opérandes est ramenée à la profondeur enregistrée (toute évaluation partielle
est abandonnée), l'exception est liée au local du `catch` s'il y en a un, l'exécution reprend au `catch`.
**E-nest — Imbrication.** Le `catch` s'exécute *après* consommation de son handler : une exception levée dans un
`catch` est traitée par le handler englobant (y compris celui d'un `finally`, E8).
**E-match — Clauses typées.** Un `try` peut porter plusieurs clauses, essayées dans l'ordre :

```alex
try:
    ...
catch IndexError as e:          # typée, liée
    ...
catch KeyError, ValueError as e: # plusieurs types
    ...
catch (IoError):                 # typée, non liée (parenthèses obligatoires sans `as`)
    ...
catch e:                         # générique (forme historique) — forcément la dernière
    ...
```

Une clause typée correspond si l'un de ses types vaut `Exception` (attrape tout), est le type exact de
l'exception, ou en est un super-type déclaré (`class X extends Y`, même règle qu'`INSTANCE_OF` ; opcode
`EXC_MATCHES`). Une clause après une clause générique est une `SyntaxError`. Si **aucune** clause ne
correspond, la **même** exception est relancée (trace conservée).
**E-pass — Chemin normal.** `TRY_END` désinstalle le handler : un `catch` n'est jamais exécuté sans exception
et un handler retiré n'avale pas les exceptions suivantes.
**E7 — Sorties anormales d'un `try`.** `break` et `continue` qui sortent d'un ou plusieurs `try` DOIVENT
désinstaller leurs handlers (émission de `TRY_END` par le compilateur). `return` détruit le frame et donc ses
handlers. *(Violation corrigée lors de cette formalisation.)*
**E8 — `finally`.** `try: … [catch …] finally: …` exécute le bloc `finally` à **toute** sortie du `try` et de
ses `catch` : chemin normal, exception (le `finally` s'exécute puis l'exception est relancée, même objet),
`return` (la valeur est calculée **avant** le `finally`), `break`, `continue`. Les `finally` imbriqués
s'exécutent du plus interne au plus externe. Réalisation : un handler supplémentaire (`TRY_BEGIN`) attrape
l'exception ; pour `return`/`break`/`continue`, le compilateur **recopie** le bloc `finally` au point de sortie
après avoir désinstallé les handlers concernés (`TRY_END`). Une exception levée dans un `finally` remplace
celle en cours (comme en Python/Java).
**E9 — Trace de pile.** Au **premier** routage d'une exception, la VM enregistre la pile d'appels de la
coroutine courante (fonction, fichier, ligne ; les fonctions synthétiques du chargeur `$link…` sont omises).
Les lignes viennent de la `DEBUG_SECTION` (table offset→ligne par fonction) et le fichier de `source_const`
(bytecode `VERSION_MINOR` 2). Une relance du même objet ne la modifie pas.
**E-return, E-closure.** Une exception traverse les frames de fermetures comme celles de fonctions.
**E4 — Tâches.** Une exception non rattrapée dans une tâche la fait passer à l'état `Failed` (ou `Cancelled`
pour `CancelledError`), réveille ses attendants qui la relèvent ; si personne ne l'a attendue, un avertissement
est écrit sur stderr à la fin du programme. Si toutes les tâches sont bloquées, le programme principal reçoit
`DeadlockError`.
**E5 — Non rattrapée dans le programme principal.** `run()` lève `UncaughtAlexException(type, message)` (ou
l'`alex::RuntimeError` d'origine) et `VM::lastTrace()` donne sa trace ; `alexc run` écrit sur stderr la trace
(chemins relatifs au dossier courant) puis `type: message`, et sort avec le code 1 :

```
Trace (appel le plus récent en dernier) :
  app.al:12, dans <module>
  app.al:10, dans run
  app.al:6, dans Calc.div
ZeroDivisionError: division entière par zéro (int // 0)
```

`ALEX_NO_TRACE=1` supprime la trace (sorties comparées octet pour octet).
**E6 — Erreurs hôte.** `BytecodeException` (module invalide) et `VmUnsupportedOpcode` ne sont **pas**
rattrapables par ALEX. `std::bad_alloc` est converti en exception `MemoryError` rattrapable. Toute autre
exception C++ issue d'une native fuit hors de `run()` (diagnostic hôte, code 1) — §10 D5.

## 8. API native

Une **native** est un `ObjNative` : `Value fn(std::vector<Value>& args, Heap& heap)`.

**N1 — Appel.** `CALL` évalue les arguments (gauche→droite), les passe dans `args` (vecteur modifiable, propre à
l'appel) et empile la valeur retournée ; aucun frame n'est créé. **N2 — Validation.** La native DOIT vérifier
arité, types et bornes (helpers de `runtime/native/common/args.hpp`) : `ArgumentError` pour l'arité ou une
valeur invalide, `TypeError` pour un mauvais type. **N3 — Erreurs.** Une native signale un échec en lançant
`alex::RuntimeError(code, message)` (jamais une autre exception, N6/E6) ; elle NE DOIT PAS laisser l'état du
runtime à moitié modifié avant de lancer. **N4 — Allocation.** Les résultats-objets s'allouent par
`heap.allocate<T>` ; ils appartiennent au heap. Pendant un appel natif, aucune collecte n'a lieu : tout objet
créé est sûr jusqu'au retour. **N5 — Pas de rappel.** Une native ne peut pas appeler du code ALEX (pas de
callbacks) ni réentrer dans la VM. **N-GC — Capture.** La `std::function` d'un `ObjNative` est invisible du GC :
elle NE DOIT PAS capturer de `Value` objet (elle peut capturer des ressources C++ : N8). Une native qui garde
une `Value` entre deux appels DOIT la déclarer comme racine (§4).
**N6 — Enregistrement.** `VM::registerNativeModule(nom, exports)` ; les modules natifs se nomment `_native_*`
et sont **privés** : l'API publique est en ALEX (`stdlib/<module>/<module>.al`), qui importe `use _native_x`.
Les noms connus du résolveur sont dans `ModuleResolver.cpp`. **N7 — Valeurs aux frontières.** `int` =
`int64` (une adresse ou un `u64` > 2^63−1 n'est pas représentable : `ValueError`) ; une `str` est une suite
d'octets pouvant contenir NUL (`requireCString` refuse le NUL quand C s'en servirait) ; `null` encode
« pointeur nul / absence ». **N8 — Ressources hors heap.** Une native possédant une ressource (bloc mémoire,
bibliothèque, processus) la range dans une table à identifiants jamais recyclés, expose des `free/close`
idempotents côté ALEX, et PEUT attacher en filet de sécurité un `ObjNative` « garde » dont la destruction (H7)
libère la ressource. Un identifiant périmé DOIT donner une erreur (`MemoryError`/`ArgumentError`), jamais un
accès invalide.

## 9. Limites

| Limite | Valeur | Dépassement |
|---|---|---|
| Profondeur d'appel | 100 000 frames / coroutine (réglable) | `RecursionError` |
| Profondeur de comparaison structurelle | 2 000 niveaux | `RecursionError` |
| Mémoire | celle de l'hôte (+ quota `memory.set_limit` pour la mémoire native) | `MemoryError` |
| Entiers | 64 bits, bouclent | — |
| Pile d'opérandes | non bornée | `MemoryError` à l'épuisement |

## 10. Écarts connus et questions ouvertes

- **D1 — Déclenchement fondé sur le nombre d'objets, non sur les octets.** Les gros objets (chaînes, listes
  énormes) comptent pour un ; la mémoire native (`memory`) n'est pas mesurée non plus. *(Le câblage du GC lui-même
  est fait : H9–H12 ; avant lui, 3 000 000 listes occupaient 333 Mo, maintenant ≈ 11 Mo.)*
- **D1b — Pas de références faibles ni de finaliseurs utilisateur** : la libération automatique des ressources
  natives repose sur le destructeur d'un `ObjNative` « garde » (H7), exécuté à un moment non déterministe.
  Une adresse brute (`Buffer.address()`, `Pointer`) ne garde **pas** son propriétaire vivant ; une `MemoryView` si.
- **D2** — `float / 0.0` lève `ZeroDivisionError` au lieu de produire `inf`/`nan` (V-arith).
- ~~**D3** — L'ordre d'itération des `dict` est non spécifié.~~ **Résolu** : ordre d'insertion (V-order).
- ~~**D4** — Une seule clause `catch`, non typée.~~ **Résolu** : clauses typées et multiples, `finally` (E-match, E8).
- **D5** — Les `std::exception` hôte autres que `bad_alloc` ne sont pas rattrapables par ALEX.
- ~~**D6** — Relever une exception recrée un objet ; pas de trace de pile.~~ **Résolu** : `raise(e)` relance
  le même objet (E2 d), trace de pile capturée (E9) et affichée par le CLI (E5).
- **D7** — `test_os.al` exige que `./alex` existe (il s'invoque lui-même).

## 11. Conformité

| Règles | Test |
|---|---|
| V1 V-truth V-eq V-hash V-type V-display, O1, H1–H10 (Heap) | `tests/test_runtime_contract.cpp` — `make test-runtime-contract` (56 vérifications) |
| H9–H12 (VM + racines) | `tests/lang/test_gc.al` — `make test-gc-vm` (24 vérifications, aussi sous `ALEX_GC_STRESS`/`ALEX_GC_POISON`) |
| V-arith V-eq V-hash V-truth V-type, M-alias M-cycle M-closure M-eval, E-code E-unwind E-nest E-pass E-stack E7 E-return E-closure E-top, L-depth L-oom | `tests/lang/test_runtime.al` — `make test-runtime` (78 vérifications) |
| H (marquage, cycles, accessibilité) hors VM | `tests/test_gc.cpp` (74) ; `tests/test_value.cpp` (36) |
| E2/E3 au niveau bytecode | `tests/test_vm_exc.cpp` (24) |
| V-order | `tests/lang/test_dict_order.al` — `make test-dict-order` (13 vérifications, aussi sous `ALEX_GC_STRESS`) |
| E2 d, E-match, E8, E9 (`e.trace`) | `tests/lang/test_exceptions.al` — `make test-exceptions` (18 vérifications) |
| E5 (trace affichée par le CLI, `ALEX_NO_TRACE`) | `tests/lang/run_trace_test.sh` — `make test-trace` |

## 12. Corrections apportées lors de la formalisation

1. `mergeModules` désignait une lambda de haut niveau comme point d'entrée (E-top / §6).
2. `break`/`continue` laissaient un handler `try` installé (E7).
3. Égalité int/float inexacte au-delà de 2^53 et hachage incohérent avec l'égalité (V-eq, V-hash).
4. `print` et `==` sur une structure cyclique faisaient planter le processus (V-display, V-eq).
5. La récursion infinie épuisait la mémoire : limite de profondeur et `RecursionError` (L-depth).
6. `std::bad_alloc` était fatal : converti en `MemoryError` rattrapable (E6).
7. **Ramasse-miettes câblé à la VM** (H9–H12) : racines exactes, point sûr, élagage des tâches terminées, mode poison de validation, module `gc`.

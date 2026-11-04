# Compilateur et machine virtuelle ALEX écrits en ALEX — étapes A, B, C et D

- **Étape A** : la chaîne source `.al` → bytecode `.albc` est écrite en ALEX (ci-dessous).
- **Étape C** : la chaîne source → **exécutable natif** (ELF x86-64 Linux, PE32+ Windows x64 console et
  graphique, application UEFI x86-64) est écrite en ALEX, et le compilateur natif se compile lui-même (voir « Étape C : compilateur natif »).
- **Étape D** : la **machine virtuelle** `alexvm` est écrite en ALEX (`runtime/vm/vm.al`), et la chaîne d'outils
  `alexc` (`src/alexc.al`) réunit les compilateurs bytecode et natif et les outils du langage (`run`,
  `test`, `fmt`, `doc`, `new`, `pkg`, `repl`, `debug`, `lsp`) ; **étape B** : la chaîne entière s'amorce sans compilateur C++ depuis une graine
  versionnée (voir « Étapes D et B : machine virtuelle en ALEX, chaîne sans C++ »). Le C++ ne sert plus que d'oracle.


L'étape A de l'autonomie du compilateur est franchie : la chaîne **source `.al` → bytecode `.albc`** existe
entièrement en ALEX, sans le compilateur C++. Elle produit des fichiers **identiques, octet pour octet**, à
ceux de `alexc build`, et s'exécute sur la VM existante (`alexc run`).

```sh
alexc run src/alexc.al build prog.al -o prog.albc    # compilation par le compilateur ALEX
alexc run prog.albc                                             # exécution par la VM
```

Le compilateur ALEX se compile lui-même : `alexc` compilé par `alexc` reproduit exactement le même
`.albc` (point fixe), lui-même identique à `alexc build src/alexc.al`. Le banc de comparaison
utilise d'ailleurs cette version auto-compilée.

## Architecture

| Module ALEX | Rôle | Portage de |
|---|---|---|
| `src/lexer/lexer.al` | lexer sur octets (indentation, f-strings, littéraux, positions) | `src/Lexer.cpp` |
| `src/ast/ast.al` | nœuds de l'AST (forme du C++ après désucrage) | `include/alex/ast/Ast.hpp` |
| `src/parser/parser.al` | parser et tous ses désucrages (décorateurs, with, assert, del, déstructuration, tranches, ensembles, comparaisons chaînées, f-strings) | `src/Parser.cpp` |
| `src/semantic/analyzer.al` | analyse sémantique : noms, doublons, const, arité, OOP, await | `src/Analyzer.cpp` |
| `src/semantic/types.al` | vérification graduelle des types, raffinement `T?`, entiers dimensionnés | `src/TypeChecker.cpp` |
| `src/bytecode/compiler.al` | AST → instructions : portées, fermetures, boucles, try/finally, match, classes, enums, async | `src/Compiler.cpp`, `src/TypeIndex.cpp` |
| `src/bytecode/format.al` | format `.albc` 0.4 : constantes, fonctions, sections debug, lecture/écriture, fusion | `src/Writer.cpp`, `src/Reader.cpp`, `src/Module.cpp` |
| `src/resolver/resolver.al` | graphe de modules, résolution des `use`, qualificatifs FNV-1a, builtins implicites, signatures, préludes, liaison `$link` | `src/ModuleGraph.cpp`, `src/ModuleResolver.cpp`, `Builtins.hpp` |
| `src/alexc.al` | ligne de commande (`build`, `compile`, `dump`) | `alexc build` |

Environ 7 100 lignes d'ALEX pour environ 9 200 lignes de C++ portées.

Choix de conception : un portage **fidèle** (même ordre de parcours, mêmes compteurs de désucrage, même ordre
d'internement des constantes, mêmes tables de lignes), pour que l'égalité octet pour octet serve d'oracle de
test. Les préludes core et collections sont lus dans de vrais fichiers ALEX (`runtime/alex/prelude/*.al`) : la chaîne
d'outils n'ouvre aucun fichier C++. Le producteur inscrit dans le `.albc` est celui de la chaîne
ALEX qui exécute le compilateur (`os.alex_build()`), comme `version::producer()` côté C++.

## Banc de comparaison

`tools/selfhost/bench.sh` compile chaque programme avec les deux compilateurs, dans une copie de l'arbre
**sans aucun cache** (`.albc` / `.meta` effacés avant chaque construction, y compris ceux des modules de
projet), compare les `.albc` octet par octet puis, avec `--run`, exécute les deux sorties et compare leurs sorties.

```sh
make bench-selfhost          # tous les exemples et tests (bench_selfhost.tsv)
make test-selfhost           # sous-ensemble rapide, inclus dans `make test`
```

Résultats sur l'ensemble du dépôt (`examples/*.al` et `tests/**/*.al`) :

| Résultat | Programmes |
|---|---|
| `.albc` identiques octet pour octet | **261 / 261** compilés |
| `.albc` différents | 0 |
| refusés par les deux compilateurs, **avec le même message d'erreur** | 22 (dont 12 fixtures `tests/selfhost/bad/`, 10 programmes réservés au natif) |
| acceptés par un seul des deux | 0 |
| exécution des deux sorties : même sortie | 241 |
| exécution : sorties différentes | 20 — toutes dues à une durée mesurée (`… sur 8 (0.0024 s)`) ; le même `.albc` exécuté deux fois diffère de la même façon |

Détail programme par programme (taille, temps C++ et ALEX) : [selfhost_bench.tsv](selfhost_bench.tsv).
Temps cumulés de compilation des 261 programmes : C++ 10,1 s, ALEX 945 s.

Vérifications complémentaires :

- **fichier seul** (sans graphe ni prélude, outil témoin `alex-compile1`) : 912 fichiers sur 912 (toute la
  stdlib, les tests, les exemples) identiques, en mode entrée et en mode module qualifié ;
- **lexer** : flux de jetons identique à `alex-lex` sur les 1 024 fichiers `.al` du dépôt ;
- **diagnostics** : pour les programmes refusés (`tests/selfhost/bad/` : lexique, syntaxe, nom non défini,
  doublon, constante réaffectée, arité, héritage, interface, await, type de retour, entier dimensionné hors
  bornes), le message d'erreur est identique au mot près.

## Performance

Le compilateur ALEX tourne sur la VM à bytecode : il est environ 90 fois plus lent que le compilateur C++
natif (ordre de grandeur : 0,2 à 2 s par programme, 15 à 20 s pour les plus gros tests contre quelques
dizaines de millisecondes). Il n'utilise pas de cache de modules : tout le graphe est recompilé à chaque fois.
L'étape C (backend natif écrit en ALEX) supprimera l'essentiel de cet écart.

## Limites connues

- Pas de cache `.albc` / `.meta` : correct mais plus lent ; les fichiers produits restent identiques.
- `--emit-map` n'est pas porté (voir l'étape C).

## Étape C : compilateur natif

La chaîne de `alexc build --native` est portée en ALEX, pour Linux x86-64, Windows x64 et UEFI x86-64 : chargement des modules (stdlib
native typée), abaissement AST → IR typé, runtime natif, inlining, allocation de registres, génération x86-64,
écriture ELF ; et le **mode dynamique**, qui traduit le bytecode de la VM en code machine et compile donc tout
programme. Les exécutables produits sont **identiques octet pour octet** à ceux du compilateur C++.

```sh
alexc run src/alexc.al native prog.al -o prog             # statique si possible, sinon dynamique
alexc run src/alexc.al native --static prog.al -o prog    # sous-ensemble statique typé seulement
alexc run src/alexc.al native --dynamic prog.al -o prog   # mode dynamique (tout programme)
make alexc-native                                                   # build/alexc : le compilateur, natif
build/alexc native prog.al -o prog                                  # sans VM ni compilateur C++
build/alexc native --windows prog.al -o prog.exe                    # exécutable Windows x64 (PE32+ console)
build/alexc native --gui app.al -o app.exe                          # application graphique Windows (wingui)
build/alexc native --uefi chargeur.al -o BOOTX64.EFI                # application UEFI (sous-ensemble statique)
```

| Module ALEX | Rôle | Portage de |
|---|---|---|
| `src/native/ir.al` | IR à registres virtuels (97 opérations), dumps | `include/alex/native/Ir.hpp` |
| `src/native/lower.al` | abaissement AST → IR typé : types (listes, dicts, tuples, `T?`, classes, enums, fonctions), spécialisation des fonctions génériques, fermetures, async, exceptions, intrinsèques, élimination des fonctions inatteignables | `src/NativeLower.cpp` |
| `src/native/inline.al` | intégration des petites fonctions feuilles du runtime | `src/NativeInline.cpp` |
| `src/native/x64.al` | assembleur x86-64 (encodage, étiquettes, relocations absolues ou relatives à RIP) et écriture ELF64 / PE32+ (imports, manifeste, `.reloc`) | `src/NativeX64.cpp`, `src/NativeElf.cpp` |
| `src/native/codegen_x64.al` | génération de code : runtime assembleur, allocation de registres, relais par rax, fusion comparaison/saut, tables de trace ; Windows : imports kernel32/user32, pile VirtualAlloc, sortie console UTF-16, rappels Microsoft x64, MessageBoxW (`--gui`) ; UEFI : entrée Microsoft x64, tas par AllocatePages, pile de 4 Mio dans le bss, port série COM1, retour au micrologiciel avec statut EFI | `src/NativeCodegen.cpp` |
| `src/native/dyn.al` | mode dynamique : bytecode → IR, pile d'opérandes résolue à la compilation, chemins rapides en ligne | `src/NativeDyn.cpp` |
| `src/native/dyn_registry.al` | registre des modules natifs de la VM (données d'ABI générées par `make nt-dyn-registry`) | `registerStubModules` |
| `src/native/build.al` | chargeur de modules natif, sources du runtime, chaînes `build` / `build_dynamic` / `build_auto` | `ModuleLoader`, `buildNative` |

Environ 8 100 lignes d'ALEX (plus 770 lignes de registre généré). Le runtime natif et le runtime dynamique étaient déjà écrits en ALEX (sources
désormais des fichiers `.al` sous `runtime/alex/` ; les en-têtes `include/alex/native/Runtime*.hpp` ne subsistent que
pour le compilateur C++ de référence et la graine `bootstrap/`).

### Résultats

Oracles : le dump complet de l'IR (`ALEX_IR_FULL=fichier alexc build --native …`, avant et après inlining), puis
les octets de l'exécutable. Bancs : `tools/selfhost/bench_native.sh` (arbre sans cache, exécutables comparés,
puis exécutés). Détails : [selfhost_native_bench.tsv](selfhost_native_bench.tsv) (statique, tous les programmes),
[selfhost_native_dyn_bench.tsv](selfhost_native_dyn_bench.tsv) (dynamique, compilé avec `build/alexc`),
[selfhost_native_win_bench.tsv](selfhost_native_win_bench.tsv) et
[selfhost_native_win_dyn_bench.tsv](selfhost_native_win_dyn_bench.tsv) (Windows, `make bench-selfhost-native-windows`),
[selfhost_native_uefi_bench.tsv](selfhost_native_uefi_bench.tsv) (UEFI, `make bench-selfhost-native-uefi` ; les
« sorties différentes » sont les programmes du noyau qui touchent la mémoire physique — VGA, DMA, MMIO — et que
le chargeur de test ne peut pas émuler : son message de faute contient une adresse aléatoire).

| Vérification | Résultat |
|---|---|
| IR complet, sous-ensemble statique (tous les programmes du dépôt acceptés) | **61 / 61 identiques**, avant et après inlining |
| exécutables, sous-ensemble statique | **61 / 61 identiques octet pour octet** ; 59 mêmes sorties, 2 sorties non déterministes (pid, temps) |
| programmes refusés par le sous-ensemble statique | **222 / 222 avec le même diagnostic** |
| mode dynamique (24 programmes variés : exemples, tests du langage, json, csv, regex, datetime, crypto, stdlib2…) | **24 / 24 identiques** (0,7 à 6,5 Mo) ; 19 mêmes sorties, 5 sorties qui ne diffèrent que par une durée mesurée |
| compilateur ALEX compilé en natif par lui-même | **identique** au binaire produit par le C++ (8,27 Mo) |
| point fixe natif : `build/alexc` recompile `build/alexc` | **identique** (stage1 = stage2 = stage3) |
| **Windows**, sous-ensemble statique (`--windows`) | **60 / 60 identiques octet pour octet**, **224 / 224 refus identiques** ; 59 mêmes sorties sous le chargeur de test, 1 non déterministe (`win_input` boucle sur la fin de fichier, tronquée par la limite de temps) |
| **Windows**, mode dynamique | **24 / 24 identiques** (0,7 à 6,5 Mo) ; 19 mêmes sorties, 5 ne diffèrent que par une durée mesurée |
| **Windows graphique** (`--gui` : calculatrice d'exemple, erreur dans un rappel) | **2 / 2 identiques** |
| suite `make test-native-windows` avec les exécutables produits par `build/alexc` | **51 / 51** (sorties, codes, traces, GC stress, console UTF-16, clics simulés, structure PE, refus de `posix`) |
| **UEFI** (`--uefi`) : tous les programmes du dépôt acceptés sans OS | **75 / 75 identiques octet pour octet**, **210 / 210 refus identiques** |
| suite `make test-native-uefi` (chargeur `efirun`), avec les applications du C++ puis celles de `build/alexc` | **toutes les vérifications passent** (sortie série = sortie et trace de la VM, code de sortie = statut EFI, tas réduit, services du micrologiciel) |
| `alexc` compilé pour Windows par `build/alexc` | **identique** au C++ (8,55 Mo) ; exécuté sous le chargeur de test, il produit lui-même des exécutables identiques |

Temps de compilation : sous-ensemble statique ≈ 1,9 s par programme avec le compilateur ALEX sur la VM ;
mode dynamique ≈ 25 à 40 s sur la VM (le runtime dynamique fait ~20 000 lignes d'ALEX à abaisser), 10 à 20 s
avec `build/alexc` natif (le compilateur se recompile en 57 s contre 2 min 18 sur la VM).

Deux ajustements du compilateur de référence, sans effet sur le sens des programmes : l'ordre d'émission des
constantes préconstruites du mode dynamique ne dépend plus de l'ordre interne d'un `unordered_map` (il suit
l'ordre de première utilisation) ; et le C++ peut écrire l'IR complet (`ALEX_IR_FULL`) et le registre des modules
natifs (`ALEX_DYN_REGISTRY`). Le portage reproduit aussi l'ordre d'évaluation des arguments de GCC (de droite à
gauche) aux trois endroits où deux arguments d'un même appel émettent du code.

Le chemin du compilateur embarqué dans un exécutable dynamique (`ALEX_EXE`, pour les programmes qui relancent la
chaîne d'outils) est celui de `os.executable()` : `alex` sous la VM, et pour `build/alexc` la valeur héritée de
`ALEX_EXE`, sinon lui-même.

### Limites de l'étape C

- Cibles portées : Linux x86-64, Windows x64 (console et `--gui`), UEFI x86-64. La cible sans OS
  (`--freestanding`, image Multiboot : interruptions, anneau 3, multiprocesseur) et AArch64 (Linux, Windows ARM64,
  UEFI ARM64) restent servies par le C++ (le compilateur ALEX les refuse avec un message explicite).
- UEFI : vérifié sous le chargeur de test `efirun` (`tests/native/uefi/efirun.cpp` : table système minimale,
  COM1, registres de contrôle et MSR émulés), pas sous QEMU + OVMF, absents de cet environnement
  (`EFIRUN=...` pour un autre lanceur). Deux limites du runtime de référence, identiques avec le C++ : le tas
  est fixé à 64 Mio (`ok_async`, avec une pile de 256 Kio par tâche, l'épuise selon l'alignement de l'adresse
  rendue par le micrologiciel ; 256 Mio suffisent) et la pile de 4 Mio ne tient pas 100 000 cadres
  (`err_recursion`).
- Les exécutables Windows sont vérifiés sous le chargeur de test `winrun` (kernel32 / user32 émulés, convention
  Microsoft x64 contrôlée), pas sur un vrai Windows dans ce dépôt (`WINRUN=wine` pour Wine).
- `--emit-map`, `--standalone` : non portés.

## Étapes D et B : machine virtuelle en ALEX, chaîne sans C++

La machine virtuelle qui exécute les `.albc` (**`alexvm`**) est écrite en ALEX et compilée en code machine par le
compilateur natif écrit en ALEX. Avec la chaîne d'outils **`alexc`**, elle aussi écrite en ALEX — compilateur vers
bytecode, compilateur natif, exécution, tests, mise en forme, documentation, modèles de projets, paquets, boucle
interactive, débogueur —, rien ne passe plus par le C++. Le compilateur C++ et sa VM restent dans le dépôt comme
**oracle** : mêmes octets pour les compilateurs, mêmes sorties pour la VM et pour chaque commande.

```sh
make pure                           # amorçage SANS g++ : graine bootstrap/ -> build/alexc, build/alexvm
powershell -ExecutionPolicy Bypass -File tools/selfhost/bootstrap.ps1   # Windows : bootstrap/alexvm.exe -> build/alexc.exe, build/alexvm.exe
build/alexc bundle -o alexc-portable  # alexc autonome : stdlib, runtime, templates et VM embarqués (un seul fichier)
build/alexc run prog.al [args...]   # compile (compilateur ALEX natif) puis exécute sur alexvm
build/alexc run --profile=r.json prog.al
build/alexc build prog.al           # .albc identique à celui du C++
build/alexc build --native prog.al  # exécutable natif identique à celui du C++ (aussi : alexc native prog.al)
build/alexc build --standalone prog.al   # exécutable autonome (compilateur natif, mode dynamique)
build/alexc check prog.al
build/alexc test [chemins] [--json] [--list] [-k filtre] [-j N]
build/alexc fmt [--check] [chemins]
build/alexc doc json | --json os | --html site | --list
build/alexc new gui mon_app         # modèles console, gui, cli, lib, server, kernel, driver
build/alexc pkg init|add|remove|install [--locked]|update|list|publish|verify
build/alexc repl
build/alexc debug --protocol 2 [--break-on-exception] prog.al   # protocole d'ALEX Studio et de l'adaptateur DAP
build/alexc lsp [--jsonl] [dossier] # serveur de langage (LSP ; JSON Lines pour ALEX Studio)
build/alexvm prog.albc [args...]    # la VM seule, comme `alexc run prog.albc`
make alexvm                         # même chaîne, premier alexc produit par le C++ (plus rapide en développement)
make bench-vm                       # banc : tous les programmes, VM C++ contre VM ALEX
make test-alexc                     # commandes d'alexc contre celles de l'alex C++
```

### Architecture

| Fichier | Rôle |
|---|---|
| `runtime/vm/vm.al` | la VM : lecture du `.albc`, décodage paresseux (instructions de 32 octets, opérandes résolus : constantes, cases de globales, cibles de saut), analyse de la pile (même analyse de flot que le mode dynamique), boucle d'exécution, cadres d'appel, gestionnaires `try` du bytecode, traces, profileur, modules natifs `_native_reflect`, `_native_ffi` et `_native_tls` |
| `src/native/vm.al` | construction de la VM : table des modules natifs générée depuis le registre (`nt_dyn_registry`), point d'entrée ; `alexc vm -o alexvm` |
| `src/alexc.al` | `alexc` : répartition des commandes ; `run [--profile[=f]]` (sans argument : `entry` de `alex.toml`), `build [--native ...]`, `native`, `compile`, `check`, `vm`, `dump`, `version` |
| `src/commands/*.al` | les outils : `test` (exécuteur, processus `alexc __test-file`, lignes `@@ALEXTEST`), `fmt`, `doc` (index de symboles du service de langage, Markdown, JSON, site HTML), `new` (modèles `templates/`), `pkg` (manifeste, SemVer, résolution, registre local, `alex.lock` SHA-256), `repl`, `debug` (protocoles 1 et 2, évaluateur sans effet de bord), `lsp` et `lang_service` (serveur de langage et service IntelliSense) ; `common` (chemins, JSON dans l'ordre d'insertion) |
| `tools/selfhost/test_alexc.sh` | chaque commande d'`alexc` comparée à celle de l'alex C++ (`make test-alexc`) |
| `tools/selfhost/bootstrap.sh` | amorçage sans C++ et contrôle du point fixe (`make pure`, `make seed`) |
| `tools/selfhost/bootstrap.ps1` | même amorçage sous Windows x64 depuis `bootstrap/alexvm.exe` (`make pure-windows`), puis SDK embarqué dans `build/alexc.exe` ; `-Seed` régénère toute la graine (`make seed-windows`) |
| `src/commands/bundle.al` | `alexc bundle` : SDK (stdlib, runtime, templates, VM) ajouté à la fin de l'exécutable ; un `alexc` copié seul l'extrait une fois dans `%LOCALAPPDATA%\alex\sdk\<version>-<empreinte>` (`~/.cache/alex/sdk` ailleurs) quand aucune stdlib n'est trouvée sur le disque |
| `bootstrap/alexvm`, `bootstrap/alexvm.exe`, `bootstrap/alexc.albc` | la graine : la VM Linux (2,5 Mo), la VM Windows (2,8 Mo) et `alexc` en bytecode, commun aux deux (1,7 Mo) |
| `tools/selfhost/bench_vm.sh` | banc VM C++ / VM ALEX |

La VM réutilise le **runtime du mode dynamique** (`runtime/alex/native/dyn*.al`, déjà écrit en ALEX, ~20 000
lignes) : représentation des valeurs, opérations de la VM (mêmes messages d'erreur), ramasse-miettes, tâches async,
fils, et les fonctions natives de la VM C++ (618 sur 634 ; la VM ajoute les 16 de `_native_reflect` et remplace
les versions inactives de `_native_ffi` et `_native_tls`). Elle n'ajoute que ce qui est propre à un interpréteur :

- **valeurs fonction** : celles du mode dynamique (`[10][code][nom]...`) dont le code est `__vm_fn_entry` ; le nom est
  une chaîne « marquée » (le mot qui la précède désigne le descripteur de la fonction) : natives, méthodes liées,
  surcharges d'opérateurs, rappels (`sort`, `map`...) et tâches appellent le bytecode sans savoir qu'il est interprété ;
- **appels sans récursion native** : un appel bytecode → bytecode empile un cadre et continue dans la même boucle,
  comme la VM C++ (100 000 cadres de récursion, `RecursionError` identique) ; les cadres rendus sont recyclés ;
- **exceptions** : un `try` natif par activation de la boucle ; une exception est routée vers le gestionnaire du
  cadre le plus récent qui en a un, la trace est relevée une fois, pile intacte (mêmes traces, `e.trace` compris) ;
- **globales** : cases stables (blocs de 4 096 mots) ; le registre des méthodes du runtime dynamique les repère par
  leur rang depuis `__globals_start()` ;
- **ffi et TLS** : la VM est un **ELF dynamique** (interpréteur `ld-linux`, `libdl`, `libc`) : `dlopen` / `dlsym` sont
  liés au chargement (`__elf_import`), les fonctions C sont appelées selon la convention System V
  (`__sysv_call`, trampoline de l'IR `SYSV_CALL`) ; OpenSSL (`network`, `http`, `smtp`, `security`...) et SQLite
  (`database`) sont chargés comme par la VM C++, le rappel de sélection ALPN est une fonction du runtime appelée par C.
  Ces deux intrinsèques n'existent que pour la VM : les exécutables natifs ordinaires restent statiques et
  identiques à ceux du compilateur C++ ;
- **GC conservatif et `gc.collect()`** : un appel explicite est exécuté hors du cadre natif de la boucle et la pile
  morte est effacée avant la collecte, pour que la libération des objets abandonnés reste déterministe
  (`memory`, `diagnostics.memory_profiler`).

Deux ajustements du runtime dynamique partagé (aussi lus par le C++, donc sans effet sur la parité des deux
compilateurs) : `e.trace` lit aussi une trace relevée par la VM, et `os.args()` saute les arguments propres à la VM
(`__dyn_argv_shift`).

### Résultats

Banc `tools/selfhost/bench_vm.sh --all` : chaque programme du dépôt (`examples/*.al`, `tests/**/*.al`) est compilé une
fois, puis exécuté par `alexc run` (VM C++) et par `build/alexvm` (VM ALEX) ; sorties standard, sorties d'erreur et
codes de sortie sont comparés séparément (durées mesurées neutralisées). Côté ALEX, les programmes qui relancent la
chaîne d'outils (éditeur de code, profileur, sous-processus `alexc run`) utilisent `alexc`. Détail :
[selfhost_vm_bench.tsv](selfhost_vm_bench.tsv).

| Vérification | Résultat |
|---|---|
| programmes exécutés par les deux VM | **259 / 263 identiques** (stdout, stderr, code de sortie) |
| écarts restants | 4, tous non déterministes : deux serveurs de test qui tournent jusqu'à la limite de temps en affichant un port aléatoire, `win_input` (boucle sur la fin de fichier, tronquée), un nom de rapport horodaté |
| refusés à la compilation | 22 (les mêmes pour les deux chaînes) |
| ffi, TLS (client, serveur, ALPN, certificats), SQLite, profileur, récursion profonde, GC stress | identiques |
| amorçage sans C++ (`make pure`) | graine → `alexc` → `alexc` : **point fixe** (stage2 == stage3, et stage1 == stage2 graine à jour) ; VM reconstruite identique à la graine ; 7 min |
| compilateur exécuté par la VM ALEX | `.albc` et exécutables natifs **identiques** à ceux produits sous la VM C++ |

Performances (2 cœurs, même machine) :

| Charge | VM C++ | VM ALEX |
|---|---|---|
| `fib(25)` + boucle de 300 000 tours | 0,11 s | **0,08 s** |
| listes, dicts, méthodes, chaînes (allocations) | **0,49 s** | 0,66 s |
| compilateur ALEX en bytecode qui compile `alexc.al` | 22 s | **13 s** |
| banc complet (temps cumulés des 259 programmes) | 158 s | 171 s |

L'interprétation est plus rapide que la VM C++ ; l'écart inverse vient des allocations (entiers hors de -256..1023
encadrés, ramasse-miettes conservatif) et des natives écrites en ALEX (cryptographie, regex), plus lentes que leur
version C++.

### Outils d'alexc

Chaque commande reproduit celle de l'alex C++ (`src/tooling/*.cpp`, `src/main_alex.cpp`), messages compris, au
nom de l'outil près (`alexc` dans les usages et les conseils) ; `tools/selfhost/test_alexc.sh` le vérifie.

| Commande | Mise en œuvre | Contrôle |
|---|---|---|
| `test` | découverte (`test_*`, `testing.test`/`skip`), épilogue ajouté à la source du fichier (`build_program(..., entry_append)`), un processus `alexc __test-file` par fichier (`-j N` en parallèle, lecture non bloquante des sorties), rapports texte et `--json` | sorties identiques ; `tests/tooling` |
| `fmt` | `LanguageService::format` | identique |
| `doc` | index des déclarations (port du `Builder` du service de langage : signatures, commentaires, membres, champs `self.x`) ; Markdown, `--json`, `--html`, `--list` | identique, octet pour octet |
| `new` | modèles de `templates/`, substitutions, CI GitHub/GitLab | arborescences identiques |
| `pkg` | manifeste (édition chirurgicale du texte), SemVer, résolution transitive au point fixe, registre local, empreintes SHA-256 (et FNV-1a héritées) | sorties, verrous et empreintes identiques |
| `repl` | `alexvm --repl` lit les lignes (même tampon qu'`input()`) et exécute chaque module en gardant les globales ; `alexc` compile chaque ligne (tubes nommés) | identique |
| `lsp` | port de `LanguageService` et `LspServer` : index avec réparation des lignes fautives, portées, résolution (imports, classes, héritage, types inférés), diagnostics du compilateur (modules de la bibliothèque compilés une fois par session) et avertissements, complétion, survol, signature, définition, références, renommage, symboles, mise en forme, actions rapides ; Content-Length ou `--jsonl`, colonnes UTF-8 / UTF-16 / UTF-32 | session de `tests/tooling/lsp_test.py` identique octet pour octet (37 messages) ; 35 / 35 |
| `debug` | `alexvm --debug` : arrêts (entrée, pause, pas à pas par niveau d'appel, points d'arrêt, exception non rattrapée avant déroulement), inspection (variables nommées depuis les noms de locales du `.albc`, références, globales, aperçus) ; `alexc` : protocole, options des points d'arrêt, évaluateur | transcriptions identiques en protocoles 1 et 2 ; `tests/tooling/debug_test.py` : 29 / 29 |

Pour la boucle interactive, chaque fonction du bytecode garde les données de son module (constantes, section de
code, noms) : plusieurs modules se chargent l'un après l'autre dans la même VM. Le débogueur se branche sur le
crochet du profileur (aucun coût hors débogage).

### Limites de l'étape D

- La VM cible Linux x86-64 (ELF dynamique : ld-linux, glibc) et Windows x64 (`alexvm.exe`, voir « Windows x64 »
  ci-dessous). AArch64 : pas encore.
- `edit` (éditeur en terminal) reste servi par l'alex C++ (c'est un programme ALEX : il tourne aussi sur
  `alexvm`). ALEX Studio, l'IDE, est un projet séparé : il fonctionne entièrement sur `alexc` (scénario de bout en
  bout et vérification de plateforme), et son exécutable Linux est compilé en code machine par `alexc`.
- `alexc run` lance le programme dans un processus `alexvm` fils : la VM meurt avec `alexc` (`--parent`), si bien
  qu'un IDE qui arrête `alexc` arrête aussi le programme.
- `alexc fmt` et `alexc test` parcourent les dossiers dans l'ordre alphabétique (le C++, dans l'ordre du système
  de fichiers) ; `alexc doc --html` sur toute la bibliothèque prend environ une minute (analyse de 740 fichiers
  par l'analyseur écrit en ALEX, compilé en mode dynamique), contre moins d'une seconde en C++.
- `build --native` : cibles du compilateur natif écrit en ALEX (Linux x86-64, Windows x64, UEFI).
- Ramasse-miettes conservatif (celui du runtime natif) : hors `gc.collect()` explicite, un objet abandonné peut
  survivre un peu plus longtemps que sous la VM C++, dont le GC est précis.
- La graine est binaire (`bootstrap/alexvm`) : `make seed` la régénère quand le compilateur évolue.

### Windows x64

`make alexc-windows` produit, sous Linux, `build/alexc.exe` (la chaîne d'outils, compilée en mode dynamique) et
`build/alexvm.exe` (la machine virtuelle) ; copiés côte à côte près d'un dossier `stdlib` (ou `../stdlib`,
`../lib/alex/stdlib` : l'installeur Windows les met dans `bin\`), ils remplacent `alex.exe` sans compilateur C++.

| Domaine | Mise en œuvre (runtime écrit en ALEX, `runtime/alex/native/windows.al` et `dyn_nat.al`) |
|---|---|
| fichiers, dossiers | appels système Linux traduits en kernel32 (`__rt_win_syscall`) : open, read, write, stat, fstat, lseek, ftruncate, mkdir, rmdir, unlink, chdir ; `os.list_dir` par FindFirstFileW ; `rename` (MoveFileExW), `copy_file` (CopyFileW), `realpath` / `absolute` (GetFullPathNameW), droits (attribut lecture seule), dates à la centaine de ns (SetFileTime, stat) |
| mode texte de la CRT | comme la VM C++ (stdout, stderr, stdin en mode texte) : LF -> CR LF en sortie, CR LF -> LF et Ctrl+Z en entrée (état du runtime [1600], fixé par la VM ; aussi dans l'écriture console/tube du générateur de code) |
| processus | `os.spawn`, `run`, `execute` (cmd.exe /c), `wait`, `kill`, `process_exists` ; module `process` complet : CreateProcessW (ligne de commande quotée comme CommandLineToArgvW), tubes anonymes, objets Job (groupe), messages d'erreur de FormatMessageW |
| fils (`concurrency.thread`) | un fil est un processus `alexvm.exe` : la région partagée des fils est une section du fichier d'échange (CreateFileMappingW, SEC_RESERVE) projetée à la même adresse ; le fil importe le programme puis appelle la fonction (comme la VM C++) ; canaux, boîtes aux lettres, ThreadPool, objets de `sync` ; les fils meurent avec le programme (Job KILL_ON_JOB_CLOSE) |
| réseau | Winsock 2 derrière les appels système (socket, connect, accept, send / recv, poll par WSAPoll, options traduites, AF_INET6 = 23) ; résolution par getaddrinfo, interfaces par GetAdaptersAddresses, `random_bytes` par RtlGenRandom. **Au-delà de la VM C++**, qui n'a pas de réseau sous Windows |
| mémoire | `memory.vm_map` / `vm_protect` / `vm_lock` / `vm_sync` / `probe` (VirtualAlloc, VirtualProtect, VirtualLock, FlushViewOfFile, VirtualQuery) ; `vm_advise`, `vm_resident`, `vm_map_file` refusés comme par la VM C++ |
| `_native_fd` (sous-ensemble) | `read` / `write` / `close` sur 0, 1, 2 et sur les tubes de `open_fifo` (délai par sondage PeekNamedPipe) ; `mkfifo` / `open_fifo` : tubes nommés Windows `\\.\pipe\...` côté serveur, non bloquants (PIPE_NOWAIT) ; `isatty`, `set_mode` / `restore` (console en mode brut, séquences VT en entrée et en sortie), `strerror`, `errno_name`. Le reste (`pipe`, `poll`, périphériques, USB) refusé |
| console | sortie UTF-8 rendue en UTF-16 (WriteConsoleW) quelle que soit la page de code (850, 1252...) |
| signaux, `io.pipe`, IPC nommés, ffi, TLS | refusés exactement comme par la VM C++ sous Windows (noms INT et TERM seulement, `signal.supported()` faux, messages identiques) |
| `alexc` | toutes les commandes : `run` (VM fille `alexvm.exe`), `build`, `check`, `test`, `fmt`, `doc`, `new`, `pkg`, `lsp`, `repl` et `debug` (canaux avec la VM : tubes nommés `\\.\pipe\alexc-<pid>-<nom>`), `edit` (console en mode brut) ; résolution des modules et URI du serveur de langage adaptées aux chemins Windows (lecteurs, UNC, séparateurs, casse). Bancs `tests/tooling` : `lsp_test` 35/35, `debug_test` 29/29, `tools_test` 33/33 |

Vérification sur un vrai Windows 11 (25H2, MSYS2 UCRT64 pour construire l'`alex.exe` C++ de référence) : chaque
programme du banc (`examples/*.al`, `tests/**/*.al`) est compilé par `alex.exe`, puis exécuté par `alex.exe run` et
par `alexvm.exe` ; sorties standard, d'erreur et codes de sortie comparés octet pour octet.

| Banc Windows | Résultat |
|---|---|
| programmes exécutés par les deux VM (263 compilés par `alex.exe`) | **217 identiques** octet pour octet (sorties, erreurs, codes) |
| écarts (46) | 27 `ui` (backend Win32 de la VM C++ contre `headless`) ; 11 réseau (refusé par la VM C++ sous Windows, réussi par `alexvm.exe` : `test_network` 89 / 89, `test_network2` 37 / 37, `test_http_server` 46 / 46) ; 8 non déterministes ou liés à l'environnement (noms de dossiers temporaires, durées, `test_thread` : 45 / 45 par `alexvm.exe`, en échec dans la VM C++ qui n'a pas de réseau) |
| `alexc.exe` : `run` (fils compris), `check`, `test tests/lang` (14 / 14), `fmt` | identiques à la chaîne C++ |
| `make test-native-windows` (chargeur `winrun`, complété des fonctions Windows désormais importées) | toutes les vérifications passent |

Limites sous Windows :
- Interface graphique : `alexvm.exe` (donc `alexc run`) et les exécutables `--windows` ont le backend Win32
  (`dyn_w32` : vraies fenêtres) ; `ALEX_UI_BACKEND=headless` pour un rendu hors écran (tests).
- Connexion TCP refusée : sur la boucle locale, le refus est immédiat (SYN sans réémission,
  `SIO_TCP_INITIAL_RTO`) ; vers une autre machine, Windows réessaie le SYN après un RST (environ 2 s) avant
  ECONNREFUSED.
- Tests propres à Linux (`/proc`, `/sys`, interface `lo`) : `network_interface.counters()` n'a pas de compteurs
  sous Windows.
- Les messages propres à `alexc.exe` (erreurs de compilation…) sortent en LF, sans le mode texte de la CRT.
- Messages d'erreur de std::filesystem : reproduits pour `remove` / `rmdir` (FormatMessageA, page de code ANSI, comme
  libstdc++) ; ailleurs, textes errno (anglais) de la VM ALEX.

## Étapes suivantes

- **B — auto-hébergement** : fait (`make pure`, graine `bootstrap/`, point fixe vérifié).
- **C — backend natif en ALEX** : fait pour Linux x86-64, Windows x64 et UEFI x86-64 (ci-dessus) ; restent la
  cible sans OS et AArch64 (`NativeCodegen` freestanding, `NativeElf` multiboot, `NativeCodegenA64`).
- **D — runtime en ALEX** : fait pour Linux x86-64 (VM, tas, GC, modules natifs, ffi, TLS). Outils portés dans
  `alexc` (`test`, `fmt`, `doc`, `new`, `pkg`, `repl`, `debug`, `lsp`). Windows x64 : fait (ci-dessus). Reste : AArch64.

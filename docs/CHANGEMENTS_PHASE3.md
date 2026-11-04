# Phase 3, étape E1 — compilation native x86-64

Détails : `docs/NATIVE.md`.

- `alexc build --native main.al [-o sortie] [--emit-ir]` : exécutable ELF64 Linux statique produit
  directement (assembleur x86-64 et écrivain ELF intégrés, runtime par appels système, sans C ni libc).
- Nouveaux fichiers : `include/alex/native/{X64,Elf,Ir,Native}.hpp`, `src/Native{X64,Elf,Lower,Codegen}.cpp`.
- Sous-ensemble E1 : `int`, `bool`, littéraux `str`, fonctions typées, `if/while/for a..b`, `print` ;
  le reste est refusé à la compilation avec la liste complète des constructions concernées.
- Sémantique identique à la VM (sorties, codes de sortie, messages d'erreur) : `make test-native`
  (9 programmes + diagnostics) et un test différentiel aléatoire hors dépôt (100 × 305 expressions).
- Performances : `fib(35)` 73 ms (VM 7 200 ms, Python 1 170 ms, gcc -O0 72 ms).

Corrections trouvées en chemin :

- VM : `INT64_MIN // -1` et `INT64_MIN % -1` faisaient planter le processus (SIGFPE) ; ils enroulent
  désormais (`floorDivInt`/`floorModInt`).
- Makefile : les cibles `test-types`, `test-exceptions`, `test-trace`, `test-standalone`,
  `test-dict-order` (phases 1-2) n'étaient pas dans `make test` (ajoutées à `.PHONY` par erreur) ; elles y sont,
  avec `test-native`.
- Makefile : `test-sci` lançait `tests/test_complex.al` et `tests/test_random.al`, absents de l'archive
  d'origine ; lignes retirées (les modules `complex` et `random` existent et se chargent).
- `make test` passe désormais en entier (code de retour 0).

Remarque : `tests/test_os.al` (envoi de SIGINT) échoue si `make test` est lancé en arrière-plan par un
shell non interactif, qui fait ignorer SIGINT aux processus fils ; au premier plan il passe.

# Phase 3, étape E2 — flottants, chaînes, listes, objets, traces, registres

- Types natifs : `float` (SSE2), `str` dynamiques (UTF-8), `list[T]`, `struct`/`class` sans héritage ;
  f-strings, `str()`, `len`, `append`, `to_int`, `to_float`.
- Runtime natif écrit **en Alex** (`include/alex/native/RuntimeSource.hpp`), avec intrinsèques mémoire
  réservées ; conversion exacte des flottants (`%.15g` de glibc reproduit), `floor`, `fmod` (algorithme musl).
- Allocation mémoire par blocs `mmap` (pas encore de ramasse-miettes).
- Traces de pile natives identiques à la VM (tables fonctions/lignes + remontée des cadres `rbp`).
- Allocation de registres (rbx, r12–r14) avec modèle de coût, immédiats, relais par `rax`.
- `make test-native` : 16 programmes comparés à la VM (sortie, code, message et trace complète).

Particularité de la VM mise au jour (reproduite, non modifiée) : avec NaN, `<=` et `>=` valent `true`.

# Phase 3, étape E3 — langage complet pour les applications

- Ramasse-miettes marquer-balayer conservatif (classes de taille, pages, grands objets rendus par `munmap`) ;
  `ALEX_GC_STRESS=1` force une collecte toutes les 4 Kio (rejoué sur chaque test natif).
- `dict[K, V]` (ordre d'insertion, `KeyError`), `null` et types `T?` avec raffinement (`if x != null`,
  `while x != null`, `if x == null: return`) — raffinement ajouté aussi au `TypeChecker` de la VM.
- Exceptions : `try` / `catch` typé / `finally`, `raise`, erreurs d'exécution rattrapables.
- Héritage simple, `super`, interfaces, répartition dynamique, `isinstance`.
- Fermetures : lambdas, fonctions locales, fonctions comme valeurs, capture par référence (cellules).
- Fonctions non annotées compilées par spécialisation (une version par types d'arguments).
- Compréhensions de liste et de dict.
- Modules : `use`, `use … as`, `from … use` résolus comme la VM (mêmes racines, cycles détectés),
  initialisation unique dans l'ordre des dépendances, traces avec le fichier de chaque cadre.
- Stdlib native : `math` (`src/NativeStdlib.cpp`, mêmes algorithmes que `stdlib/math/math.al`).
- Arguments passés dans les registres (`rdi` … `r9`) : `fib(35)` 98 → 79 ms.
- `make test-native` : 30 programmes (dont `natmod/`, modules de test).
- `ModuleGraph::collectExportableNames` / `computeSignatures` rendus publics (typage des imports natifs).

# Phase 3, étape E4 — tuples, enums, stdlib système, noyau sans OS

- Natif : tuples (`tuple[A, B]`), `enum` simples et à charge utile, `match` complet (littéraux, plages,
  captures, variantes, tuples, listes, gardes), type `char` (`s[i]`, `for c in s`, littéraux `'é'`),
  `to_int` / `to_float` sur des chaînes (règles de `std::stoll` / `std::stod`, arrondi correct vérifié
  contre Python sur 1 800 cas aléatoires), `input()`.
- Langage : type facultatif des champs d'enum (`Rgb(r: int, g: int, b: int)`), ignoré par la VM.
- VM, `TypeChecker` : `s[i]` et `for c in s` sont typés `char` (ce qu'ils sont à l'exécution).
- Stdlib native : `string` (toute l'API), `io` (fichiers), `os` (arguments, environnement, processus,
  chemins) par appels système directs (`__syscall`).
- `alexc build --native --freestanding` : image Multiboot démarrable (amorçage 32 bits → mode long généré),
  `print`/`input` sur le port série, tas en mémoire physique ; module `hw` (ports, accès mémoire volatils,
  `hlt`/`cli`/`sti`, assembleur en ligne `asm` / `asm_value`) ; exemple `examples/noyau/noyau.al`.
- `make test-kernel` (QEMU) : les programmes de `tests/native` démarrés sans OS donnent la même sortie que
  la VM ; tests matériels dans `tests/native/kernel`.
- `make test-native` : 37 programmes.

# Phase 3, étape E5 — interruptions, tâches, pilotes

- Sans OS : IDT de 256 vecteurs, entrées assembleur générées, répartition vers des gestionnaires Alex
  (`hw.on_interrupt`), exceptions du processeur en erreurs `CPUError` avec trace jusqu'à l'instruction fautive ;
  PIC 8259, minuterie PIT, `wait`/`enable`/`disable` ; pages physiques (`alloc_pages`, `free_pages`), `cr2`,
  `cr3`, `invlpg`.
- Runtime : allocation, ramasse-miettes et sortie en sections critiques (interruptions masquées) sans OS ;
  `if __freestanding():` résolu à la compilation dans le runtime.
- Module `tasks` (natif, avec ou sans OS) : tâches à piles séparées, commutation assembleur, GC sur toutes
  les piles, `try` et profondeur propres à chaque tâche ; préemptif sans OS par la minuterie.
- Pilotes en Alex (`examples/noyau/`) : écran VGA, clavier PS/2, bus PCI ; interpréteur de commandes
  `shell.al`.
- Tests : `tests/native/only` (natif seulement, dans `make test-native`), `tests/native/kernel` : interruptions,
  préemption, pages, défaut de page, interpréteur piloté au clavier (`sendkeys.py`, moniteur QEMU).

# Phase 3, étape E6 — async natif, espace utilisateur, disque

- `async` / `await` natifs : fonctions, méthodes et fonctions locales `async`, type `future[T]`, module
  `asyncio` complet ; ordonnanceur du runtime calqué sur celui de la VM (mêmes sorties, mêmes avertissements,
  interblocage). Les tâches `async` tournent sur les fibres de l'étape E5. Test `ok_async` (68 vérifications).
- Sans OS : GDT avec segments utilisateur et TSS, `syscall`/`sysret`, `hw.on_syscall`, `hw.enter_user`,
  `hw.leave_user`, copies mémoire et chaînes ↔ mémoire brute.
- Exécutables Linux chargés à 1 Gio : le même ELF tourne sous Linux et comme processus du noyau Alex
  (`examples/noyau/processus.al` : chargeur ELF, appels système Linux, pagination à la demande).
- Pilotes `disque.al` (ATA PIO) et `fat.al` (FAT16) ; commandes `ls`, `taille`, `cat`, `ecrire`, `rm`,
  `lancer` dans `shell.al`.
- Natif : `clear` (collections), égalité structurelle des listes.
- VM et natif : un `raise` final raffine les types nullables ; `TypeChecker` accepte `future[T]`.
- Correction : les traces d'une erreur levée par le runtime (`__rt_with_site`) lisaient un mauvais mot de cadre
  depuis le passage des arguments par registres (E3).
- `make test-native` : 40 programmes ; `make test-kernel` : disque de test, programmes utilisateur.
- Reporté à E7 : multiprocesseur.

# Phase 3, étape E7 — multiprocesseur, processus isolés, virtio

Détails : `docs/NATIVE.md`, « Multiprocesseur » et « Espace utilisateur ».

- **Multiprocesseur** (sans OS) : bloc par cœur adressé par `gs` (`swapgs` aux entrées depuis l'anneau 3),
  une TSS par cœur (16 cœurs au plus), page de démarrage générée (mode réel → protégé → long) copiée en 0x8000,
  point d'entrée 64 bits des autres cœurs ; tables de démarrage étendues d'une fenêtre sans cache sur les
  4 premiers Gio physiques (PML4[1], `hw.mmio`) pour l'APIC.
- **Verrou global du noyau** : le code Alex du noyau s'exécute sur un cœur à la fois (le runtime et le
  ramasse-miettes ne sont pas réentrants) ; rendu en anneau 3, pendant `hw.wait()`, repris aux appels système
  et interruptions ; compteur des cœurs en attente. Le GC parcourt la pile d'une tâche active sur un autre cœur
  depuis le pointeur rangé quand ce cœur a rendu le verrou.
- Runtime : entrées de tâche de 128 octets (pile noyau en anneau 3, espace d'adressage, cœur) ; tâche courante
  par cœur ; tâches inactives (une par cœur, créée au besoin) ; espace d'adressage et pile noyau rétablis à
  chaque reprise d'une tâche (cr3 rechargé : TLB local vidé quand un processus change de cœur).
- `hw` : `mmio`, `rdmsr`, `wrmsr`, `cas`, `atomic_add`, `spin_lock`, `spin_unlock`, `cpu_id`, `cpus`,
  `cpu_block`, `smp_prepare`, `cpu_online`, `kernel_space`, `set_space`, `from_user` ; `enter_user` /
  `leave_user` propres à chaque tâche ; `wait` rend le verrou global.
- `examples/noyau/smp.al` : cœurs de la table ACPI MADT, APIC local, INIT / SIPI, minuterie APIC étalonnée sur
  le PIT, préemption sur chaque cœur.
- **Processus** (`processus.al`) : plusieurs à la fois, chacun avec sa table PML4 (premier Gio du noyau partagé
  en superviseur) et sa tâche du noyau ; `spawn`, `spawn_image`, `wait`, `run`, `running` ; exceptions venues de
  l'anneau 3 (division, instruction invalide, protection générale, défaut de page) : seul le programme fautif
  s'arrête (codes 136, 132, 139). Nouveau programme `programmes/calcul.al`.
- **virtio-blk** (`virtio_blk.al`, interface PCI « legacy ») et `bloc.al` (virtio s'il est présent, sinon ATA) ;
  `fat.al` passe par `bloc` ; `pci.al` : `find`, `bar`, `enable`, `write32`.
- Tests (`make test-kernel`, 52 vérifications) : `demo_smp` (`-smp 4`), `demo_multi` (six processus sur quatre
  cœurs, accès interdits), `demo_virtio` (FAT et processus sur un disque virtio), scénario au clavier de
  `shell.al` rejoué sur virtio ; options de QEMU par test (`<nom>_qemu.txt`, `<nom>_virtio`).

Corrections trouvées en chemin :

- Runtime sans OS : la table des régions de mémoire physique rendues (mots 112..127 de l'état) chevauchait la
  table des tâches (mot 120) et l'ordonnanceur async (mot 126) : à la cinquième région rendue (grands objets
  libérés par le GC), le pointeur de la table des tâches était écrasé. L'état passe à 2 Kio, régions en 128..143.
- Interruption venue de l'anneau 3 : `r15` (profondeur d'appel) est remis à zéro, au lieu de garder la valeur du
  programme utilisateur (risque de `RecursionError` parasite dans le gestionnaire).
- Une instruction privilégiée ou invalide dans un programme utilisateur arrêtait tout le noyau ; elle n'arrête
  plus que le programme.


## E7 (suite) — sous-répertoires et noms longs FAT

- `fat.al` réécrit : répertoires en chaînes de grappes (racine FAT16 : zone fixe), chemins `a/b/c` avec `.` et
  `..`, `mkdir` (entrées `.` et `..`), `rmdir` (vide seulement), répertoire agrandi d'une grappe quand il est
  plein ; noms longs VFAT en lecture (morceaux, ordre, somme de contrôle, UTF-16 avec paires de substitution ;
  drapeaux de minuscules de l'octet 12 pour les noms courts) et en écriture (comme Linux : nom long dès que le
  nom n'est pas un 8.3 en majuscules ; nom court = le nom en majuscules s'il tient en 8.3 et est libre, sinon
  `BASE~N.EXT`) ; recherche insensible à la casse ASCII ; mêmes fonctions qu'avant (`find`, `list`, `read`,
  `write`, `remove`) plus `mkdir`, `rmdir`, `is_dir`.
- Changement visible : la casse des noms écrits est conservée (`note.txt` reste `note.txt`, avec un nom long,
  au lieu de devenir `NOTE.TXT`).
- `processus.al` : répertoire courant par processus (hérité du shell), `getcwd`, `chdir`, `mkdir`, `rmdir`,
  `unlink` et `stat` des répertoires, `open` refuse un répertoire ou un parent absent ; un disque plein donne
  `ENOSPC` au programme au lieu d'une erreur du noyau. Nouveau programme `programmes/fichiers.al`.
- `os` natif : `mkdir`, `rmdir` (non récursif), `remove`, mêmes messages d'erreur que la VM (vérifié par
  `tests/native/ok_io_os.al`).
- Shell : `cd`, `pwd`, `mkdir`, `rmdir`, `ls [chemin]` (répertoires suivis de `/`), chemins relatifs,
  arguments entre guillemets ; le scénario au clavier les exerce (sur ATA et sur virtio).
- Tests : `demo_fat` (`make test-kernel`, 53 vérifications) avec un disque préparé par mtools
  (`demo_fat_disk.sh`) et une vérification par l'hôte après le passage du noyau (`demo_fat_after.sh` :
  `fsck.fat`, `mdir`, `mtype`, et un lecteur LFN en Python indépendant du noyau).
- Les sorties attendues n'affichent plus la taille des exécutables (elle change avec le compilateur).

# Phase 3, étape S1 — modules de la bibliothèque standard (réseau, concurrence, E/S, système, matériel)

Arborescence cible : `core`, `system/*`, `concurrency/*`, `io/*`, `network/*`, `hardware/*`, `memory/*`.
Ces modules sont traités par ordre de priorité et ciblent la VM (`alex run`).

- **Réseau** (docs/NETWORK.md) : `network.socket`, `dns`, `tcp`, `udp`, `http` (client HTTP/1.1, serveur,
  outils d'URL) sur le module natif `_native_net` (sockets non bloquants, délais par `poll`). Ajout de
  `io.flush()`. 170 vérifications : interopérabilité avec un serveur Python, avec curl, et d'Alex à Alex.
- **Concurrence** (docs/CONCURRENCY.md) :
  - `concurrency.mutex`, `semaphore`, `atomic` et `async` : primitives des tâches async, `Queue`, `Barrier`,
    `Event`, `retry`, `with_timeout`, `map_limit` ;
  - `concurrency.thread` : de vrais fils parallèles et isolés, une VM par fil. Les valeurs sont copiées. Le
    module fournit `Thread`, `spawn`, `parallel_map`, des boîtes aux lettres et des `Channel` entre fils ;
  - le programme principal attend ses fils avant de se terminer ;
  - les tables des modules natifs sont propres à chaque fil (`thread_local`) ;
  - un mot-clé est désormais accepté comme segment de chemin de module (`use concurrency.async as aio`) ;
  - 106 vérifications, 0 alerte sous ThreadSanitizer.
- **Entrées-sorties** (docs/IO.md) :
  - `io.stream` : flux interchangeables (chaîne, fichier, descripteur, sorties standard, processus) ;
  - `io.pipe` : tubes anonymes et nommés, `pipeline` sans shell ;
  - `io.console` : couleurs, curseur, `read_key` et `read_password` en mode brut, `confirm`, `choose` ;
  - `io.file` ;
  - nouveau module natif `_native_fd` ;
  - `process` accepte un descripteur comme flux d'un fils ;
  - 60 vérifications, dont 8 dans un pseudo-terminal.
- **Système** (docs/SYSTEM.md) :
  - `system.signal` : gestionnaires Alex exécutés par la VM entre deux instructions (frame inséré au point
    sûr), `interrupt_on` (`InterruptError`), `watch` / `wait`, `send`. `time.sleep` s'interrompt à
    l'arrivée d'un signal intercepté ;
  - `system.environment` : lecture typée, `expand`, `with_vars` ;
  - `system.system_info` : mémoire, disques, charge, durée de fonctionnement, distribution, processeur ;
  - façades `system.process`, `system.filesystem` et `system.time` ;
  - `memory.virtual`, nom court de `memory.virtual_memory` ;
  - nouveau module natif `_native_signal` ; `_native_os` gagne `disk_usage` et `load_average` ;
  - 66 vérifications, y compris sous `ALEX_GC_STRESS`.
- **Matériel** (docs/HARDWARE.md) :
  - `hardware.keyboard` et `mouse` : inventaire et événements evdev bruts ;
  - `hardware.screen` : DRM, EDID, xrandr, framebuffers ;
  - `hardware.gpu`, `usb` et `camera` (Video4Linux, capture par ffmpeg) ;
  - `hardware.audio` : ALSA, WAV de 8 à 32 bits, sons, lecture ;
  - `hardware.microphone` : enregistrement ;
  - 59 vérifications sur une copie construite de `/sys`, `/proc` et `/dev`.
- **Corrections** :
  - `io.read_bytes` (donc `file.open(..., "rb")`) lit désormais jusqu'à la fin, sans se fier à la taille
    annoncée : celle-ci vaut 0 pour `/proc` ;
  - `io.stream.read(1)` ne coupe plus un caractère UTF-8 ;
  - le mode brut du terminal coupe `ISIG`, si bien que `read_key` rend `"ctrl+c"` comme une touche.
- **Makefile** : nouvelles cibles `test-network`, `test-concurrency`, `test-io`, `test-system` et
  `test-hardware`, toutes incluses dans `make test`.

# Phase 3, étape S2 — interfaces : ui.view (description), gui (fenêtre), tui (terminal)

Une interface est décrite une seule fois avec `ui.view`. `gui.run(vue)` l'affiche dans une fenêtre,
`tui.run(vue)` dans le terminal. Le comportement des composants (clavier, souris, focus, défilement,
édition) est écrit une fois, en Alex. Chaque rendu ne fournit qu'une surface : métriques, une vingtaine de
primitives de dessin et des événements au format commun. Voir docs/UI_VIEW.md.

- **`ui.view`** :
  - les composants : `text`, `button`, `field`, `textarea`, `checkbox`, `radio`, `select`, `slider`,
    `spinbox`, `progress`, `list_view`, `table` (tri), `tree`, `column`, `row`, `panel`, `scroll`, `tabs`,
    `split`, `dialog` / `alert` / `confirm` (modaux), `menu_bar` (sous-menus, raccourcis, coches),
    `separator`, `spacer` ;
  - l'état propre à chaque composant est gardé sous son chemin ou son `id`, avec des valeurs contrôlées ;
  - mise en page flex (tailles en caractères et en lignes), focus (Tab, restauration après un menu ou un
    dialogue), superpositions, routage des événements ;
  - `quit`, `focus`, `app` ; thèmes `dark`, `light` et `terminal`.
- **`tui`** :
  - surface en cellules sur un tampon à rendu différentiel ;
  - `run` gère l'écran alternatif, la souris SGR, le collage, le redimensionnement, la remise en état à la
    sortie et les couleurs 24 bits / 256 / 16 / sans ;
  - `TestApp` sur terminal virtuel, avec capture HTML.
- **Couche terminal bas niveau** : `tui.terminal`, `tui.screen`, `tui.input`, `tui.style`, `tui.width`,
  `tui.markup`, `tui.inline` (menus, saisies, tableaux, arbres, panneaux, barres de progression, spinners
  dans un script ordinaire), `tui.emulator`.
- **`gui`** :
  - surface en pixels sur le canvas du module `ui` (X11, Win32/Direct2D, headless) : formes anticrénelées,
    ombres, anneau de focus, survol ;
  - conversion des événements, y compris le `text_input` de Windows ;
  - `TestApp` (événements de fenêtre injectés, captures PNG).
- **Langage** :
  - échappements `\xHH`, `\uXXXX`, `\u{...}`, `\e` ;
  - virgule finale dans les listes, dictionnaires, tuples, appels et paramètres ;
  - `core.arity(f)`.
- **Corrections** :
  - `ui.rgb` (division entière) ;
  - le backend headless synthétise un `close` quand sa file est vide, ce que les applications de test
    ignorent désormais.
- **Exemples** : `examples/ui_view/demo.al` (tous les composants ; argument `gui` pour la fenêtre) et
  `compteur.al`.
- **Tests** : `make test-ui-view` lance :
  - la couche terminal bas niveau (47 vérifications) ;
  - les composants dans un terminal virtuel (124, dont des tests de non-régression tirés d'une relecture
    indépendante) ;
  - un vrai pseudo-terminal (14) ;
  - une fenêtre headless avec captures (38) ;
  - une vraie fenêtre X11 sous Xvfb, pilotée par de vrais événements X.

  `tests/lang/test_syntax_ui.al` couvre les ajouts au langage.

## Éditeur de code — `alex edit` et `ui.view.code_editor`

- **`alex edit [--gui] [--dir d] [--theme t] [fichiers]`** : éditeur écrit en Alex
  (`stdlib/outils/editeur_app.al`), dans le terminal ou une fenêtre :
  - arbre des fichiers, onglets, enregistrement, dialogues de confirmation (fermer, quitter) ;
  - F5 lance `alex run` (F7 `alex check`) : sortie affichée en direct, code de sortie et durée, erreurs
    changées en marqueurs sur les lignes concernées ; F5 pendant l'exécution l'arrête.
- **`v.code_editor`** (`ui.view.wcode`) : numéros de ligne, coloration (`ui.view.syntax` : Alex,
  Python, JSON), ligne courante, parenthèse correspondante, sélection clavier et souris (double et triple
  clic), presse-papiers, annulation groupée, auto-indentation, indentation et commentaire de blocs,
  dupliquer / supprimer / déplacer des lignes, recherche avec compte des résultats, aller à la ligne,
  marqueurs, lecture seule, défilement horizontal.
- **Fenêtre** : police à chasse fixe DejaVu Sans Mono embarquée (`font_mono_data.cpp`,
  `tools/gen_font.py --mono`) ; `ui.text_measure` et le canvas acceptent une famille (`"mono"` ; Consolas
  sous Windows) ; rôles de thème du code (`code_bg`, `gutter`, `syn_keyword`...).
- **`ui.view`** :
  - `v.press(touche)` envoie une touche au composant qui a le focus ;
  - un `on_tick` qui renvoie `false` évite de redessiner ;
  - **correction** : le focus suit un composant à `id` quand la vue l'entoure d'un nouveau conteneur (le
    panneau de sortie apparaissait en volant le focus de l'éditeur).
- **Runtime** : l'exécutable connaît son chemin (`os.executable()`), pour relancer `alex`.
- **Tests** (`make test-ui-view`) : `tests/ui_view/test_code_editor.al` (71 vérifications), 13 de plus
  dans `test_view_gui.al` (fenêtre headless, captures), `tests/ui_view/edit_pty.py` (`alex edit` dans un
  vrai pseudo-terminal). Documentation : `docs/EDITEUR.md`.

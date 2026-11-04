# Compilation native

```sh
alexc build --native main.al            # -> ./main, exécutable ELF x86-64 Linux
alexc build --native main.al -o outil
alexc build --native main.al --emit-ir  # affiche aussi la représentation intermédiaire
alexc build --native --freestanding noyau.al -o noyau.bin   # image démarrable sans OS (voir « Sans OS »)
alexc build --native --windows main.al  # -> main.exe, exécutable Windows x64 (voir « Windows »)
alexc build --native --windows --gui app.al   # application graphique Windows (module wingui)
alexc build --native --target linux-aarch64 main.al   # exécutable ELF ARM64 Linux (voir « ARM64 »)
alexc build --native --windows --arm64 main.al        # exécutable Windows ARM64 (voir « Windows ARM64 »)
```

Le compilateur produit **directement** le code machine et le fichier exécutable : pas de C, pas
d'assembleur ni d'éditeur de liens externes, pas de libc. L'exécutable est statique (26 Ko pour un
`print`, runtime et ramasse-miettes compris) ; il ne dépend que du noyau Linux (appels système). Avec
`--freestanding`, il ne dépend de rien : c'est un noyau démarrable.

## Tout programme : sous-ensemble statique ou mode dynamique

`alexc build --native` compile **tout** programme que `alexc run` exécute :

1. d'abord dans le **sous-ensemble statique** (ci-dessous) : code typé, le plus rapide et le plus compact ;
2. sinon — construction hors du sous-ensemble, typage plus strict que la VM, module de la bibliothèque
   standard non écrit pour le natif statique — en **mode dynamique** : le message de construction le signale
   (`Exécutable natif écrit : app (mode dynamique)`).

```sh
alexc build --native app.al            # statique si possible, sinon dynamique
alexc build --native --dynamic app.al  # mode dynamique imposé
alexc build --native --static app.al   # sous-ensemble statique seulement : diagnostics au lieu du repli
```

Le mode dynamique traduit en code machine le **bytecode exact de la VM** (programme fusionné avec les préludes
et toute la bibliothèque standard utilisée) : chaque opcode devient du code natif qui appelle un runtime écrit
en Alex reproduisant `VM.cpp` / `Value.cpp` — mêmes résultats, mêmes messages d'erreur, même affichage, mêmes
traces de pile. L'exécutable reste autonome (aucune VM embarquée, pas de libc) et vise les mêmes systèmes
(Linux x86-64 et ARM64, Windows x64 et ARM64 ; pas `--freestanding` ni `--uefi`).

| Fichier | Rôle |
|---|---|
| `src/NativeDyn.cpp` | bytecode → IR : analyse de la pile, gestionnaires `try`, globales, modules natifs |
| `include/alex/native/RuntimeDyn.hpp` | valeurs dynamiques, égalité, hachage, affichage |
| `include/alex/native/RuntimeDynOps.hpp` | opcodes : appels, classes, opérateurs, index, exceptions, async |
| `include/alex/native/RuntimeDynNat.hpp` | fonctions natives des modules `_native_*` (même contrat que `runtime/native/`) |
| `include/alex/native/RuntimeDynOffice.hpp` | `_native_office` : deflate/inflate octet pour octet, XML, base64, nombres, PDF, PNG |
| `include/alex/native/RuntimeDynUi.hpp` | `_native_ui` : backend portable headless (fenêtres, widgets émulés, événements, menus, module window, canvas) |
| `include/alex/native/RuntimeDynUiRaster.hpp` | rastériseur 2D de la VM (`runtime/native/ui/portable/raster.cpp`) réécrit en Alex : pixels identiques, PNG / BMP / PPM |
| `include/alex/native/RuntimeDynUiFont.hpp` | atlas DejaVu Sans / Sans Mono (généré depuis `font_data.cpp`, `font_mono_data.cpp`) |
| `tools/native_coverage.sh` | compile chaque programme d'`examples/` et `tests/`, compare sortie et code de sortie à la VM |

Valeurs : un mot de 64 bits, `0` = `null`, sinon un objet du tas dont le premier mot est le genre (int, float,
bool, char, byte, str, list, tuple, dict, fonction, native, instance, exception, cellule, futur). `async` /
`await` utilisent l'ordonnanceur du runtime natif (fibres, minuteurs, `asyncio`) ; la profondeur d'appel est
limitée comme dans la VM (`RecursionError` au-delà de 100000 frames). Le ramasse-miettes compte les objets comme
la VM (`gc.stats()`, `enable`, `set_threshold`, `set_stress`) ; seuil : max(16384, 2 × vivants).

Modules natifs disponibles : `core`, `math`, `string`, `collections`, `io`, `os`, `process`, `cli`, `asyncio`,
`fd` (tubes, terminal, `poll`, inotify, USB par usbfs), `hwsim`, `gc`, `net` (sockets TCP/UDP/Unix, DNS),
`thread` et `sync` (fils = processus partageant une région mémoire), `signal` (interception par signalfd),
`memory` (blocs gérés/bruts/mappés/externes, gardes, mémoire virtuelle), `office` (bureautique et PDF), `ui`
(backend headless : voir ci-dessous).

Interface graphique : avec `ALEX_UI_BACKEND=headless`, l'exécutable natif se comporte comme la VM — fenêtres,
widgets émulés (bouton, label, saisie, case, radio, liste déroulante, progression, défilement) et leur moteur
d'interaction (survol, focus, Tab, clavier, presse-papiers), événements injectés (`inject_*`), menus, raccourcis,
module `window` (position, états, réglages, focus), canvas 2D (formes, chemins, dégradés, ombres, texte, images,
transformations, découpe, opacité, `put_pixels`), images PNG / BMP / PPM, captures `window_screenshot` et
`canvas_save_png`. Le rastériseur reprend opération flottante pour opération flottante celui de la VM (`hypot`
de la glibc, flottants 32 bits du flou et de la couverture, ordre d'évaluation des arguments) : les PNG produits
sont identiques octet pour octet. Presse-papiers, notifications et sélecteurs de fichiers passent par les mêmes
outils externes que la VM (`xclip`, `xsel`, `wl-copy`, `notify-send`, `zenity`, `kdialog`), avec les mêmes replis.

Performances du mode dynamique (Linux x86-64, comparées à `alexc run`) : boucles entières, appels, récursion,
méthodes, objets, dictionnaires, listes et flottants sont 1,2 à 3 fois plus rapides que la VM (récursion `fib` :
~3 fois) ; la concaténation répétée de longues chaînes reste ~2 fois plus lente (copies et ramasse-miettes).
Leviers : chemins rapides en ligne pour `+ - *` et les comparaisons d'entiers et pour les sauts conditionnels,
petits entiers partagés (-256..1023), allocation rapide des boîtes, cache des méthodes, appel direct des méthodes
liées, intégration des petites fonctions du runtime (`src/NativeInline.cpp`), longueur et curseur mémorisés des
chaînes (indexation O(1) en ASCII, parcours linéaire sinon), réserve des gros blocs par paliers, seuil du GC
amorti sur la taille du tas et la profondeur de pile.

Limites assumées du mode dynamique :

* **TLS** : non fourni (`tls.supported()` est faux, les connexions sécurisées lèvent `IoError`).
* **FFI** : non fourni (`ffi.supported()` est faux : pas de chargeur de bibliothèques dans un exécutable sans libc).
* **Interface graphique à l'écran** : le backend X11 n'est pas fourni. Sans `ALEX_UI_BACKEND=headless`,
  `ui.available()` est faux et `backend()` vaut `"unavailable"` (message d'erreur de la VM sans affichage) ; le
  backend headless est complet (voir plus haut).
* **PDF chiffrés** : `rc4`, `aes_cbc_*`, `sha2` lèvent `NotImplementedError` (`md5`, utilisé à l'écriture, est fourni).
* `argv[0]` est, comme sous `alexc run`, le chemin du script compilé ; `ALEX_EXE` désigne par défaut le
  compilateur `alex` qui a produit l'exécutable.

Couverture (`sh tools/native_coverage.sh`, Linux x86-64) : **162 programmes sur 174** du corpus se comportent exactement comme
sous la VM (sortie standard et code de sortie). Les 12 écarts restants relèvent des limites ci-dessus (TLS : 7, FFI : 3) ou
de deux serveurs qui tournent sans fin sous la VM aussi (`http_alex_server`, `ws_alex_server`).
Avec `ALEX_UI_BACKEND=headless`, les 38 programmes graphiques (exemples `ui_*`, `tests/ui`, `tests/ui_view`,
`tests/window`, et le scénario de bout en bout d'ALEX Studio) sont identiques à la VM, captures PNG comprises (hors durées affichées).

## Chaîne de compilation

| Étape | Fichier | Rôle |
|---|---|---|
| Modules | `src/NativeCodegen.cpp` (`ModuleLoader`) | résout les `use` comme la VM, ordre d'initialisation |
| Analyse | `Lexer`, `Parser`, `Analyzer`, `TypeChecker` | communes avec la VM : mêmes erreurs |
| Abaissement | `src/NativeLower.cpp` | AST typé → IR ; refuse tout ce qui sort du sous-ensemble natif |
| IR | `include/alex/native/Ir.hpp` | code à trois adresses sur registres virtuels 64 bits |
| Code machine | `src/NativeCodegen.cpp` | IR → x86-64, runtime minimal en assembleur |
| Assembleur | `src/NativeX64.cpp` | encodage des instructions (REX, ModRM, SIB, sauts relatifs) |
| Exécutable | `src/NativeElf.cpp` | ELF64 (code+données en lecture seule, bss) ; image Multiboot sans OS ; PE32+ (UEFI, Windows) |
| Runtime | `include/alex/native/RuntimeSource.hpp` | runtime écrit en Alex (GC, chaînes, dicts, exceptions…) |
| Runtime Windows | `include/alex/native/RuntimeWindows.hpp` | argv / envp et émulation des appels système par kernel32 (`--windows`) |
| Stdlib | `src/NativeStdlib.cpp` | modules natifs typés : `math`, `string`, `io`, `os`, `posix`, `tasks`, `asyncio`, `hw` |

## Sous-ensemble natif (étapes E1 à E6)

| Accepté | Détail |
|---|---|
| Types | `int` (64 bits), `float` (IEEE 754, SSE2), `bool`, `char` (point de code), `str` (UTF-8, immuable), `list[T]`, `dict[K, V]`, `tuple[A, B, …]`, `T?` et `null`, types fonction `func(A, B) -> R`, `struct` / `class` / `interface`, `enum` |
| Fonctions | paramètres annotés, ou **non annotés** : la fonction est alors compilée une fois par combinaison de types d'arguments (type de retour déduit) ; `-> T`, récursion, défauts littéraux, arguments nommés |
| Fermetures | lambdas (`x => x * 2`, `(a, b) => …`, `func(x: int) => …`), fonctions locales (récursives), fonctions comme valeurs ; capture **par référence** comme la VM, une variable de boucle neuve à chaque tour |
| Objets | champs typés, `init`, méthodes, `self`, héritage simple (`extends`), `super.m()`, interfaces (`implements`), redéfinition avec répartition dynamique, `isinstance` |
| Exceptions | `try` / `catch` typé / `finally`, `raise(msg)`, `raise(type, msg)`, `e.type`, `e.message` ; les erreurs d'exécution (division par zéro, index…) sont rattrapables |
| `null` | `T?`, `x == null`, raffinement par `if x != null:` / `while x != null:` / `if x == null: return` |
| Tuples | `(1, "a", 2.5)`, `t[0]` (index constant : type de l'élément ; variable : tuple homogène), égalité structurelle, `len`, `for` (homogène), immuables |
| Enums | simples et à charge utile (`Rgb(r, g, b)`), types de champs facultatifs (`Rgb(r: int, g: int, b: int)`, sinon fixés par la première construction) ; égalité par identité, comme la VM |
| `match` | littéraux (`int`, `float`, `str`, `char`, `bool`, `null`), `_`, captures, plages `a..b`, variantes `E.V(motifs…)`, tuples, listes, gardes `if` ; aucun cas : rien |
| Collections | listes homogènes, dicts (ordre d'insertion, clés `int`/`bool`/`float`/`str`), compréhensions de liste et de dict (`for` imbriqués, filtres `if`), `for k in d` |
| Chaînes | `+`, comparaisons, `len`, `s[i]` et `for c in s` (des `char`, comme la VM), `str(x)`, f-strings, `to_int` / `to_float` (mêmes règles que `std::stoll` / `std::stod` de la VM, arrondi correct) |
| `async` / `await` | fonctions et méthodes `async` (aussi locales), `await`, type `future[T]` ; `asyncio` : `sleep`, `now`, `gather`, `race`, `timeout`, `future`, `resolve`, `reject`, `cancel`, `cancelled`, `done`, `failed`, `result`, `is_task`, `abandoned` ; ordonnanceur identique à celui de la VM (file FIFO, minuteurs triés, interblocage signalé, avertissements d'échecs perdus) ; sans OS, horloge virtuelle |
| Contrôle | `if/elif/else`, `while`, `for v in a..b`, `for x in xs`, `break`, `continue`, `x if c else y`, `and`/`or` |
| Modules | `use m`, `use a.b as c`, `from m use x, y` : fonctions, constantes, variables, classes ; initialisation unique, dépendances d'abord (comme la VM) |
| Stdlib | `math`, `string` (toute l'API), `io` (`read_file`, `write_file`, `append_file`, `file_exists`, `delete_file`), `os` (`argv`, `args`, `argc`, `exit`, `getenv`, `hasenv`, `pid`, `parent_pid`, `cwd`, `chdir`, `mkdir`, `rmdir` (non récursif), `remove`, `exists`, `isfile`, `isdir`, `name`, `platform`, `arch`, `hostname`, `version`), `tasks` (natif seulement, voir « Tâches »), `asyncio`, `hw` (sans OS) ; `from core use len, to_int, to_float`, `from collections use append, keys, values, get, contains_key, remove, set, clear` |
| Entrées-sorties | `print(...)` (un argument par ligne, comme la VM), tamponnée ; `input([invite])` |

Plus strict que la VM, par choix (sinon l'affichage différerait) :
- un `int` n'est pas converti implicitement en `float` dans une variable ou un paramètre utilisateur
  (`x: float := 3` est refusé) ; il l'est en argument d'une fonction de la stdlib (`math.sqrt(16)`) ;
- une variable garde un seul type : `t := 0` puis `t += 0.5` est refusé ;
- une liste est homogène (`[1, 2.5]` refusé) ; une liste vide doit avoir un type connu (`xs: list[int] := []`) ;
- une fonction non annotée doit renvoyer le même type par tous ses `return`, et annoter son type de
  retour si elle est récursive ; les paramètres d'une lambda doivent être annotés, ou déduits du type
  fonction attendu (`apply(x => x * 2, 3)` avec `func apply(f: func(int) -> int, …)`).

Tout le reste est refusé **à la compilation**, toutes les constructions d'un coup, avec leur position
(et leur fichier pour un module) :

```
NativeError: main.al:11:6: '**' sur des flottants : non supporté en natif (utiliser math.pow)
  main.al:14:8: index non constant sur un tuple hétérogène (tuple[int, str])
  util.al:3:8: paramètre 'k' de la fonction locale inner : type requis en natif
```

Encore hors du natif : `**` sur des flottants (utiliser `math.pow`), `type(x)`, les
nombres hexadécimaux à virgule dans `to_float`, les tuples comme clés de dict, et les modules de la stdlib
autres que `math`, `string`, `io`, `os`, `asyncio`, `core` et `collections` (et `hw`, sans OS).

## Sémantique : identique à la VM

Garanti par `make test-native` — 40 programmes, plus `tests/native/only` (natif seulement) ; sortie standard, code de sortie, message d'erreur **et
trace de pile** comparés à la VM octet par octet, chaque programme étant aussi rejoué avec un ramasse-miettes
déclenché toutes les 4 Kio (`ALEX_GC_STRESS=1`) — et par deux tests différentiels aléatoires hors dépôt
(expressions entières, valeurs flottantes) : aucun écart.

- Entiers 64 bits en complément à deux, **enroulement** sur dépassement (`max + 1 == min`).
- `//` et `%` arrondis vers −∞, sur les entiers comme sur les flottants (`%` flottant : `fmod` exact).
- Flottants affichés comme `printf("%.15g")` de glibc, plus `.0` pour une valeur entière.
- `-x` sur un flottant vaut `0 - x` (donc `-0.0` affiche `0.0`), comme la VM.
- Avec NaN, `<` et `>` sont faux mais `<=` et `>=` sont **vrais** (particularité de la VM, reproduite).
- `and`/`or` rendent l'un des opérandes ; vérité : nombre non nul, `str` non vide ; listes, dicts, objets et
  fonctions toujours vrais (même vides, comme la VM).
- Dicts : ordre d'insertion, affichage `{a: 1}`, `KeyError` sur clé absente.
- Exceptions : la trace est celle du premier `raise` (conservée si l'exception est relancée) ; les `finally`
  s'exécutent sur `return`, `break`, `continue` et exceptions.
- Erreurs d'exécution avec **trace de pile identique à la VM**, fichier de chaque cadre compris
  (`ALEX_NO_TRACE=1` la masque) : `ZeroDivisionError`, `IndexError`, `KeyError`, `TypeError`,
  `RecursionError` au-delà de 100 000 appels, `MemoryError`, exceptions non rattrapées.

Écarts assumés : `a ** b` avec `b < 0` donne un `float` dans la VM, une `ValueError` en natif ; le module
`math` natif (mêmes algorithmes que `stdlib/math/math.al`, résultats identiques bit à bit) renvoie toujours un
`float` là où la VM renvoie parfois l'entier `0` ou `1` (`math.exp(0.0)` : `1.0` contre `1`), `nan` hors du
domaine là où la VM renvoie `null` (`math.sqrt(-1.0)`), un `int` pour `floor`/`ceil`/`round`/`trunc` (avec
`ValueError` pour un flottant non fini), et `pow` est flottant (`math.pow(2, 10)` : `1024.0`).
Une erreur levée dans une fonction de la stdlib a le même message, mais sa trace s'arrête à l'appel (la VM
ajoute un cadre `stdlib/…/….al`). `os.argv()[0]` est le chemin de l'exécutable (dans la VM : celui du
script). `string.ord` n'accepte qu'un `char` (la VM accepte aussi une `str` d'un caractère).

## Processus : module `posix` (natif seulement)

Appels système x86-64 standard au niveau des processus, des fichiers et du réseau ; le même exécutable fonctionne
sous un système x86-64 courant et sous Alex OS, voir `tests/native/only/ok_posix.al`.

```
use posix
t := posix.pipe()                      # [lecture, écriture]
pid := posix.fork()                    # 0 dans l'enfant (la sortie de print est vidée avant)
if pid == 0:
    posix.dup2(t[1], 1)
    posix.execv("/bin/ls", ["ls", "-l"])   # ne revient qu'en cas d'erreur (OSError)
posix.close(t[1])
texte := posix.read_all(t[0])
posix.waitpid(pid)                     # ou waitpid(pid, true) : WNOHANG
code := posix.status()                 # code façon shell : 0..255 ou 128 + signal
```

Aussi : `execve(path, argv, env)`, `spawn(path, argv)`, `run(path, argv)`, `wait()`, `dup`, `close`,
`open(path, "r"|"w"|"a")`, `read(fd, n)`, `write(fd, s)`, `listdir(path)` (getdents64), `kill(pid, sig)`,
`ignore_signal(sig)` / `default_signal(sig)` (rt_sigaction SIG_IGN / SIG_DFL), `getpid`, `getppid`,
`chdir`, `exit` ; constantes `WNOHANG`, `SIGINT`, `SIGKILL`, `SIGTERM`. Les erreurs lèvent `OSError`.

Fichiers et utilisateurs : `lseek(fd, décalage, origine)`, `chmod(path, mode)`, `getuid()`, `setpgid`,
`getpgid`, `getpgrp`, `sync()`, `link(ancien, nouveau)`, `symlink(cible, lien)`, `readlink(lien)`.

Réseau IPv4 (adresses en texte « a.b.c.d ») : `socket("tcp" | "udp")`, `connect(fd, ip, port)`,
`bind(fd, port)`, `listen(fd, file=8)`, `accept(fd)` → descripteur, `peer(fd)` → `[ip, port]`, `send(fd, s)`,
`sendto(fd, s, ip, port)`, `recv(fd, n=4096)` (`""` en fin de flux), `recvfrom(fd, n)` → `[données, ip, port]`.

Aléa : `random_bytes(n)` (appel `getrandom` : générateur cryptographique du système).

## Dessin 2D : module `pixmap` (natif seulement)

`stdlib/pixmap/pixmap.al` : moteur de dessin logiciel pour les programmes natifs (interface graphique d'Alex OS).
Surfaces ARGB 32 bits (0xAARRGGBB) ou masques 8 bits en mémoire brute (mmap, jamais le ramasse-miettes) :
remplissages, découpe, mélange alpha, dégradés, rectangles arrondis anti-crénelés, ombres, polygones, copies
(avec opacité, mise à l'échelle), texte (polices lissées `.alfont`), images `.alpx`, enregistrement PNG,
enveloppe d'un tampon de trame (`wrap`, `map_file`). Il s'appuie sur la pragma `# alex: intrinsics` : un module
de la bibliothèque qui la porte peut utiliser les primitives mémoire du mode sans OS (`hw.*`) dans un
programme hébergé. Format des fichiers : en-tête du module. Test : `tests/native/only/ok_pixmap.al`.

Ajouts à `posix` pour les programmes interactifs : `set_nonblock(fd)` (O_NONBLOCK), `read_nb(fd, n)` (lecture sans
attente : chaîne vide s'il n'y a rien), `eof(fd)`.

Polices TrueType : `pixmap.load_ttf("Sans.ttf", 14)` lit une police `.ttf` (tables `glyf`/`loca`, glyphes
composés, `cmap` formats 4 et 12, métriques `hhea`/`hmtx`) et rend la même structure qu'une police `.alfont` ;
chaque glyphe est rastérisé (anticrénelage, enroulement non nul, sans hinting) à son premier affichage.

Identités et limites (Alex OS 0.7, aussi sous Linux) : `posix.geteuid()`, `getgid()`, `getegid()`,
`getgroups()`, `setuid()`, `setgid()`, `setresuid()`, `setresgid()`, `setgroups()`, `umask()`, `chown()`,
`access()`, `set_echo(fd, actif)` (saisie sans écho), `getrlimit(r)` → `[souple, dure]` et
`setrlimit(r, souple, dure)` (-1 : illimité). `posix.stat` rend aussi l'uid et le gid.

Sans OS (`--freestanding`) : `hw.set_smap` / `hw.smap()` (fenêtres `stac`/`clac` des accès `hw.*` à la zone
utilisateur), `hw.guard_page(adresse, présente)` (page de garde dans l'identité du noyau ; chaque pile de tâche en
a une), `hw.image_start()` / `image_rodata()` / `image_end()` (code et constantes de l'image, alignés sur 4 Kio),
`hw.gc_stress(actif)`, `hw.memory_left()`. La double faute (vecteur 8) est traitée sur une pile IST propre à
chaque cœur ; `syscall` démarre avec le drapeau AC effacé.

## Tâches : module `tasks` (natif seulement)

```
use tasks
tasks.spawn(() => travail("a"))   # nouvelle tâche, sur sa propre pile ; renvoie son identifiant
tasks.yield_now()                  # passe la main à la tâche prête suivante (tourniquet)
tasks.run()                        # attend la fin de toutes les autres tâches
tasks.current(), tasks.alive()
```

Chaque tâche a sa pile (1 Mio réservé sous Linux, avec une page de garde ; 256 Kio sans OS), sa chaîne de
`try` et sa profondeur d'appel ; la commutation sauve les registres préservés et les drapeaux. Le
ramasse-miettes parcourt les piles de toutes les tâches vivantes. Une exception non rattrapée dans une tâche
arrête le programme avec sa trace. Sans OS, un gestionnaire de minuterie qui appelle `tasks.yield_now()` rend
le multitâche **préemptif** (voir `tests/native/kernel/k_irq.al`) ; les tâches démarrent interruptions
autorisées. Les variables partagées se protègent par `hw.disable()` / `hw.enable()`.

## Runtime natif

- **En assembleur** (quelques centaines d'octets) : point d'entrée, tampon de sortie, écriture, conversion
  entier → texte, remontée des cadres pour les traces, conversion d'une erreur en exception.
- **En Alex** (`include/alex/native/RuntimeSource.hpp`), compilé avec chaque programme — seules les
  fonctions utilisées sont émises : ramasse-miettes, chaînes, listes, dicts, flottants, exceptions, rapport
  d'erreur. Il utilise des intrinsèques réservées (`__load64`, `__store8`, `__mmap`, `__unwind`…) : la base
  des accès mémoire bruts de l'étape E4 (pilotes).
- **Ramasse-miettes** marquer-balayer, conservatif (pile, registres préservés, globales et objets sont
  parcourus mot à mot ; un mot qui ressemble à l'adresse d'un bloc le garde vivant) : classes de taille de
  16 o à 32 Kio sur des pages de 64 Kio regroupées en blocs `mmap` de 32 Mio alignés, grands objets en
  `mmap` direct (rendus au système par `munmap`), collecte quand l'allocation depuis la dernière collecte
  dépasse un seuil proportionnel au tas vivant. 2 millions de chaînes temporaires : 16 Mo de mémoire au plus.
- **Exceptions** : chaque `try` empile un enregistrement (pile, cadre, registres préservés, profondeur,
  adresse de reprise) ; `raise` restaure le plus récent et y saute — coût nul hors des `raise`.
- **Fermetures** : objet `[code][nom affiché][cellules capturées…]` ; une variable capturée vit dans une
  cellule du tas, partagée par référence ; appel indirect avec l'objet en paramètre caché.

## Performances

| Programme | VM | Natif | gcc -O0 | gcc -O2 |
|---|---|---|---|---|
| `fib(35)` récursif | 9 070 ms | **79 ms** | 93 ms | 27 ms |
| premiers < 300 000 (boucles) | 2 125 ms | **49 ms** | | |
| 40 corps × 300 pas (flottants, objets) | 369 ms | **10 ms** | | |
| 200 000 chaînes dans une liste | 216 ms | **34 ms** | | |

Optimisations : arguments dans les registres (`rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9`) ; allocation des
variables les plus utilisées (pondérées par la profondeur de boucle, modèle de coût) aux registres
préservés `rbx`, `r12`–`r14` (pas dans une fonction contenant un `try`) ; constantes en immédiats ; fusion
comparaison + saut ; relais des temporaires par `rax`. Le natif dépasse `gcc -O0` ; s'approcher de
`gcc -O2` demandera une allocation par durée de vie et l'intégration des petites fonctions.

## Détails de l'exécutable

- Point d'entrée : réserve une pile de 256 Mio par `mmap` (pages allouées à la demande), initialise chaque
  module dans l'ordre des dépendances puis le programme, vide le tampon de sortie, `exit(0)`.
- Convention d'appel interne : 6 premiers arguments dans `rdi`, `rsi`, `rdx`, `rcx`, `r8`, `r9` (rangés
  dès l'entrée de l'appelé, donc visibles du GC), les suivants sur la pile ; résultat dans `rax` ;
  `rbx`/`r12`–`r14` préservés par l'appelé ; `r15` = profondeur d'appel ; `rbp` chaîne les cadres.
- Traces : table (début, fin, nom, fichier) des fonctions et table (adresse, ligne) en données en lecture
  seule ; en cas d'erreur, le runtime remonte la chaîne `rbp` et retrouve fonction, fichier et ligne.
- Sortie standard tamponnée (64 Kio), vidée à la fin et avant tout message d'erreur.
- Image chargée à 1 Gio (`0x40000000`) : sous le noyau Alex, les adresses basses restent au noyau
  (identité) et le même exécutable tourne comme processus utilisateur (voir « Espace utilisateur »).

## Sans OS : `--freestanding`

```sh
alexc build --native --freestanding examples/noyau/noyau.al -o noyau.bin
qemu-system-x86_64 -kernel noyau.bin -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04
```

Le même compilateur produit une **image Multiboot** (chargée à 1 Mio par GRUB ou `qemu -kernel`) : le
programme Alex devient un noyau 64 bits, avec **tout le langage** — ramasse-miettes, exceptions,
fermetures, classes, dicts, `match`, modules. `make test-kernel` le vérifie : les 39 programmes de
`tests/native` (sauf ceux qui utilisent `io`/`os`) démarrés sous QEMU donnent sur le port série exactement
la sortie et les traces de la VM, plus les tests propres au matériel (`tests/native/kernel`) et
l'exemple `examples/noyau/noyau.al` (écran VGA, horloge CMOS, compteur de cycles).

| Élément | Sans OS |
|---|---|
| Démarrage | en-tête Multiboot, amorçage 32 bits généré (tables de pages : 1 Gio en identité par pages de 2 Mio, plus une fenêtre sans cache sur les 4 premiers Gio physiques pour les périphériques, SSE, mode long, GDT 64 bits), pile de 16 Mio **hors de l'image** : les 16 Mio qui précèdent le tas (en général [16, 32 Mio)), pour que l'image reste petite (~1 à 3 Mio) et évite les zones réservées par le micrologiciel ; adresse de la structure Multiboot : `hw.multiboot_info()` |
| `print`, traces | port série COM1 (0x3F8, 38 400 bauds) |
| `input()` | une ligne lue sur COM1 (fin : `\n` ou `\r`) |
| Mémoire | tas du ramasse-miettes dans la mémoire physique, de 32 Mio à la fin de la RAM annoncée par Multiboot (1 Gio au plus) |
| Fin du programme, `hw.exit(code)` | port 0xF4 : QEMU (`isa-debug-exit`) se termine avec le code `2 × code + 1` ; sinon le processeur s'arrête (`cli; hlt`) |
| Interruptions | IDT de 256 portes ; chaque vecteur appelle le gestionnaire Alex enregistré (`hw.on_interrupt`), interruptions masquées pendant le gestionnaire ; registres non préservés, `xmm0`/`xmm1` et chaîne des `try` sauvés ; `hw.from_user()` dit si l'anneau 3 a été interrompu ; exception du processeur sans gestionnaire : erreur `CPUError` avec trace jusqu'à l'instruction fautive |
| Sections critiques | allocation, ramasse-miettes et tampon de sortie s'exécutent interruptions masquées : un gestionnaire peut allouer et afficher |
| Segments | GDT créée au démarrage 64 bits : code/données noyau, données/code utilisateur (anneau 3), une TSS par cœur (pile noyau des interruptions venues de l'anneau 3) |
| Appels système | `syscall` / `sysret` (MSR `STAR`, `LSTAR`, `SFMASK`) : l'instruction `syscall` d'un programme en anneau 3 appelle le gestionnaire Alex (`hw.on_syscall`), sur la pile noyau de sa tâche (`swapgs`, bloc du cœur) |
| Cœurs | bloc par cœur adressé par `gs` ; verrou global du noyau (voir « Multiprocesseur ») ; jusqu'à 16 cœurs |
| Modules | `hw` réservé à ce mode ; `io` et `os` refusés |

Module `hw` (accès matériel) :

| Fonction | Rôle |
|---|---|
| `outb` / `outw` / `outl(port, v)`, `inb` / `inw` / `inl(port)` | ports d'entrée-sortie |
| `peek8/16/32/64(adresse)`, `poke8/16/32/64(adresse, v)` | mémoire physique ; chaque appel fait exactement un accès de la taille indiquée, jamais mis en cache ni supprimé : accès **volatils** (registres de périphériques) |
| `hlt()`, `cli()`, `sti()`, `pause()` | instructions privilégiées |
| `asm("fa f4")`, `asm_value("0f 31 …")` | **assembleur en ligne** : octets machine insérés à l'endroit de l'appel ; `asm_value` renvoie `rax`. Registres libres : `rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`–`r11` ; les autres et la pile doivent être préservés |
| `on_interrupt(vecteur, f)` | gestionnaire `func(int)` (reçoit le code d'erreur du processeur, 0 sinon) ; vecteurs 0–31 : exceptions, 32–47 : lignes du PIC |
| `pic_init()`, `irq_enable(n)`, `irq_disable(n)`, `eoi(n)` | contrôleur d'interruptions 8259 (lignes renumérotées à partir de 32) |
| `timer_start(hz)` | minuterie PIT (ligne 0, vecteur 32) |
| `wait()`, `enable()`, `disable()` | `sti ; hlt` (verrou global du noyau rendu pendant l'attente), `sti`, `cli` |
| `alloc_pages(n)`, `free_pages(adresse, n)` | pages physiques de 4 Kio, mises à zéro |
| `cr2()`, `cr3()`, `invlpg(adresse)` | registres de contrôle, invalidation du TLB |
| `flush_tlb()` | recharge `cr3` |
| `on_syscall(f)` | gestionnaire `func(nr, a1, a2, a3, a4, a5) -> int` des appels système venus de l'anneau 3 ; sa valeur revient dans `rax` |
| `enter_user(rip, rsp)`, `leave_user(code)` | passe en anneau 3 à `rip` avec la pile `rsp`, dans l'espace d'adressage de la tâche courante ; `leave_user` (depuis un gestionnaire) revient de `enter_user` avec `code`. Une tâche à la fois par programme, plusieurs tâches en même temps |
| `user_frame(buf)`, `enter_user_frame(buf)` | pendant un appel système : copie dans `buf` (18 mots : rip, rsp, rflags, rax, rbx, rcx, rdx, rsi, rdi, rbp, r8..r15) les registres du programme au moment de l'instruction `syscall`, avec rax = 0 ; `enter_user_frame` reprend l'anneau 3 avec tous ces registres (fork : l'enfant repart après son appel système). L'entrée `syscall` sauve les 15 registres du programme sous la pile noyau de la tâche |
| `kernel_space()`, `set_space(pml4)` | table PML4 du noyau ; espace d'adressage de la tâche courante (rechargé à chaque reprise, sur n'importe quel cœur ; 0 : celui du noyau) |
| `mmio(phys)` | adresse virtuelle d'un registre de périphérique en `phys` (< 4 Gio), sans cache |
| `rdmsr(n)`, `wrmsr(n, v)` | registres spécifiques du modèle |
| `cas(adresse, attendu, nouveau)`, `atomic_add(adresse, v)` | opérations atomiques (`lock cmpxchg`, `lock xadd`) ; renvoient l'ancienne valeur |
| `spin_lock(adresse)`, `spin_unlock(adresse)` | verrou tournant sur un mot de la mémoire partagée |
| `cpu_id()`, `cpus()`, `cpu_block()` | numéro du cœur courant, nombre de cœurs en service, bloc du cœur |
| `smp_prepare(numéro, inactive)`, `cpu_online(bloc)` | prépare le démarrage d'un cœur (bloc, pile, tâche inactive, page de démarrage en 0x8000) ; il reste à lui envoyer INIT et SIPI (voir `smp.al`) |
| `from_user()` | vrai si l'interruption en cours a interrompu l'anneau 3 |
| `copy`, `zero`, `string_at(adresse, n)`, `store_string(s, adresse)`, `byte_addr(s)`, `byte_size(s)` | copies mémoire, chaînes ↔ mémoire brute |
| `console_write(s)` | écrit sur la console série sans tampon |
| `memory_end()`, `exit(code)` | fin de la RAM utilisable ; arrêt |

Pilotes écrits en Alex (`examples/noyau/`, modules importés par `shell.al`) :

- `ecran.al` : écran texte VGA (couleurs, défilement, accents en page de code 437, curseur matériel) ;
- `clavier.al` : clavier PS/2 par interruption (ligne 1), majuscules, retour arrière ;
- `bus_pci.al` (importé `use bus_pci as pci` ; la bibliothèque a désormais son propre paquet `pci`, docs/DRIVERS.md) : énumération du bus PCI (ports 0xCF8 / 0xCFC), classes de périphériques, registres de base,
  accès DMA ;
- `disque.al` : disque ATA en PIO (contrôleur primaire, secteurs de 512 o, LBA 28 bits) ;
- `virtio_blk.al` : disque virtio-blk (interface PCI « legacy », une file virtqueue, requêtes de trois
  descripteurs, attente par scrutation de l'anneau « used ») ;
- `bloc.al` : périphérique de bloc du système de fichiers (virtio s'il y en a un, sinon ATA) ;
- `fat.al` : système de fichiers FAT16 sur `bloc` : sous-répertoires (chemins `a/b/c`, `.` et `..`, `mkdir`,
  `rmdir`, répertoire agrandi d'une grappe quand il est plein), noms longs VFAT (UTF-16 avec paires de
  substitution, sommes de contrôle ; à l'écriture, comme Linux, un nom long dès que le nom n'est pas un 8.3 en
  majuscules, avec le nom court `BASE~N.EXT`), recherche insensible à la casse (ASCII) ; dates lues dans
  l'horloge CMOS. Compatible avec mkfs.fat, mtools et fsck.fat ;
- `smp.al` : multiprocesseur (cœurs de la table ACPI MADT, APIC local, INIT / SIPI, minuterie APIC par cœur) ;
- `processus.al` : processus utilisateur (voir ci-dessous) ;
- `shell.al` : interpréteur de commandes (`aide`, `pci`, `mem`, `taches`, `temps`, `ls`, `cd`, `pwd`, `mkdir`,
  `rmdir`, `taille`, `cat`, `ecrire`, `rm`, `lancer`, `quitter` ; chemins relatifs au répertoire courant,
  `"..."` pour les noms à espaces) avec minuterie à 100 Hz et tâches préemptées. `make test-kernel` le
  pilote au clavier (moniteur QEMU, `sendkey`) sur une image disque FAT16 de test.

### Espace utilisateur

`processus.run(nom, args, …)` charge depuis le disque un exécutable produit par `alexc build --native`
(le **même fichier ELF** que sous Linux) et l'exécute en anneau 3. Le noyau Alex implémente les appels
système Linux dont le runtime a besoin : `read`, `write`, `open`, `close`, `stat`, `mmap`, `mprotect`,
`munmap`, `exit` / `exit_group`, `getpid`, `getppid`, `uname`, `getcwd`, `chdir`, `mkdir`, `rmdir`, `unlink`,
`sched_yield` ; fichiers et répertoires sur la FAT (chemins relatifs au répertoire courant du processus, codes
d'erreur de Linux), entrée au clavier, sortie à l'écran. Les pages du processus (au-dessus de 1 Gio) sont allouées **à la demande** par le
gestionnaire de défaut de page ; à la fin, elles sont rendues. Une erreur du programme affiche sa trace
comme sous Linux. `examples/noyau/programmes/` contient des exemples, et `demo_processus.al` les lance.

Plusieurs processus à la fois (`processus.spawn`, `processus.wait`, `processus.run`), isolés : chacun a son
espace d'adressage (sa table PML4 ; le premier Gio du noyau y est partagé en mode superviseur) et sa tâche du
noyau, préemptée par la minuterie comme les autres. Un accès interdit ne termine que le programme fautif, avec
les codes de Linux : 139 (défaut de page hors de ses zones, protection générale), 132 (instruction
invalide), 136 (division). `demo_multi.al` lance six exemplaires d'un même calcul (mêmes adresses virtuelles,
résultats distincts et exacts) sur quatre cœurs, puis des exécutables construits en mémoire qui lisent la
mémoire du noyau ou exécutent `cli`, `ud2`, une division par zéro.

### Multiprocesseur

`smp.start(hz)` (`examples/noyau/smp.al`) lit les cœurs dans la table ACPI MADT, active l'APIC local (registres
par `hw.mmio`), étalonne sa minuterie sur le canal 2 du PIT, démarre chaque autre cœur (INIT, puis SIPI vers la
page de démarrage en 0x8000 : mode réel, protégé, puis long) et donne à chacun une minuterie APIC à `hz` tics
par seconde, qui préempte les tâches (`tasks.yield_now()`).

Le runtime Alex (ramasse-miettes, chaîne des `try`, tables des tâches) n'est pas réentrant : un **verrou
global du noyau** sérialise le code Alex du noyau (un seul cœur à la fois), comme les premiers noyaux Linux
multiprocesseurs. Un cœur le rend quand il passe en anneau 3 (`enter_user`), quand il attend (`hw.wait()`) et
l'attend en revenant (appel système, interruption). Le parallélisme réel est donc celui des **processus** :
chaque cœur libre prend un processus prêt et l'exécute en anneau 3, en même temps que les autres ; la
minuterie les fait migrer d'un cœur à l'autre (l'espace d'adressage est rechargé à chaque reprise, ce qui vide
le TLB local). Le ramasse-miettes ne s'exécute que sous le verrou : les autres cœurs sont alors en anneau 3,
en attente du verrou ou en sommeil, et leurs piles sont parcourues depuis le pointeur rangé au moment où ils
l'ont rendu. Chaque cœur a sa tâche courante, et une tâche inactive (créée au besoin) quand il n'a rien à
exécuter.

`demo_smp.al` vérifie le démarrage (1 à 8 cœurs), la minuterie de chaque cœur et les opérations atomiques ;
`demo_virtio.al` monte la FAT sur un disque virtio-blk et y lance des processus sur quatre cœurs ; le scénario
au clavier de `shell.al` est rejoué sur un disque virtio. `demo_fat.al` lit une arborescence préparée par mtools
(noms longs accentués, répertoire de 40 fichiers), écrit la sienne, puis l'hôte la vérifie (`fsck.fat`,
mtools, et un lecteur LFN indépendant en Python : mtools n'affiche pas les caractères hors du plan de base).

Les données de démarrage (premiers octets reçus sur le port série) peuvent être consommées par le
micrologiciel : un test qui envoie une entrée attend la fin du démarrage.

### Noyau parallèle (`hw.smp_parallel(true)`)

Par défaut le verrou global du noyau sérialise le code ALEX (ci-dessus). `hw.smp_parallel(true)` l'abandonne :
le code ALEX s'exécute alors sur plusieurs cœurs **en même temps**, et le runtime se protège lui-même :

| Partagé | Protection en mode parallèle |
|---|---|
| chaîne des `try` | **par cœur** (bloc du cœur, `gs:[192]`), toujours (aussi hors mode parallèle) |
| allocateur et ramasse-miettes | verrou de l'allocateur (interruptions masquées) |
| pages physiques (`alloc_pages`, piles des tâches) | verrou des pages |
| table des tâches, commutations | verrou des tâches, tenu pendant la commutation et rendu par la tâche reprise |
| tampon de `print` | verrou de la sortie |
| GC | **arrêt des autres cœurs** : IPI vecteur 253 (APIC local, xAPIC ou x2APIC) ; chaque cœur range tous ses registres sur sa pile, publie son pointeur de pile (bloc du cœur + 200) et attend. Toute attente active du runtime (verrous, `yield`) est un point d'arrêt ; une attente active du programme faite interruptions masquées doit appeler `hw.safepoint()` |

Les données du programme partagées entre cœurs restent à protéger par le programme (`hw.spin_lock`).
`hw.parallel()`, `hw.gc_count()` (nombre de GC), `hw.safepoint()`. Test : `tests/native/kernel/k_parallel.al`
(8 tâches sur 4 cœurs sans verrou global : allocations, exceptions, GC, résultats identiques au calcul séquentiel).
Conception et étapes suivantes : `docs/NOYAU_PARALLELE.md` d'Alex OS.

#### Mode intermédiaire : `hw.runtime_locks(true)` (libération chemin par chemin)

Le runtime se protège comme ci-dessus, mais le verrou global **existe toujours** ; c'est le programme qui le
prend là où il en a besoin. Utilisé par Alex OS pour retirer le verrou global chemin par chemin (P2) :

| Point d'entrée | Comportement |
|---|---|
| appel système (`syscall`) | n'entre plus avec le verrou : le répartiteur du noyau le prend (`hw.bkl_take()`) sauf pour les appels qu'il a rendus sûrs entre cœurs |
| interruption ou exception | entre avec le verrou, sauf les vecteurs **libérés** par `hw.interrupt_free(v, true)` (0..63) : le gestionnaire le prend lui-même sur ses chemins lents |
| sortie (`sysret`, `iretq`) | rend le verrou **s'il appartient à ce cœur** et s'il n'était pas détenu à l'entrée |

`hw.bkl_take()` / `hw.bkl_drop()` / `hw.bkl_held()`. Règle : une commutation de tâche se fait verrou global
détenu. L'attente du verrou relit le numéro du cœur à chaque essai : une attente interruptions permises peut
être commutée puis reprise sur un autre cœur (le verrou serait sinon pris au nom du premier). Le noyau prend donc
le verrou **interruptions masquées** quand il le peut.

## UEFI : `--uefi`

```sh
alexc build --native --uefi chargeur.al -o BOOTX64.EFI
```

Produit une **application UEFI** (PE32+, sous-système 10) au lieu d'une image Multiboot. Le code est assemblé en
mode « indépendant de la position » (adresses de données et de fonctions relatives à RIP) : aucune relocation, le
micrologiciel charge l'image où il veut. Au démarrage, le runtime garde le mode long, l'IDT et la GDT du
micrologiciel, demande son tas au micrologiciel (`AllocatePages`, 64 Mio, sinon 16 ou 4), passe sur une pile de
4 Mio dans le bss, puis exécute le programme ; la fin du programme (ou `hw.exit(code)`) **revient au
micrologiciel** (code non nul : statut d'erreur EFI). `print` écrit sur le port série COM1 (muet sur une machine
sans port série) ; la console de l'écran passe par les services UEFI (voir la bibliothèque `boot/uefi/efi.al`
d'Alex OS).

| Fonction (`hw`) | Rôle |
|---|---|
| `efi_call(fn, a1, ..., a12)` | appelle le pointeur de fonction `fn` (un service lu dans une table UEFI) avec la convention Microsoft x64 (rcx, rdx, r8, r9, pile au-delà de 32 octets réservés, rsp aligné) ; renvoie rax (`EFI_STATUS`) |
| `efi_image()`, `efi_system_table()` | `EFI_HANDLE` de l'image et `EFI_SYSTEM_TABLE*` reçus à l'entrée |
| `uefi()` | vrai dans une application UEFI |
| `peek*`, `poke*`, `copy`, `zero`, `alloc_pages`, `outb`..., `asm` | comme sans OS (la mémoire est en identité) |

Pas disponibles en UEFI : interruptions (`on_interrupt`), anneau 3, multiprocesseur (le micrologiciel les garde).

Tests : `make test-native-uefi` exécute les applications sous Linux avec le chargeur de test
`tests/native/uefi/efirun.cpp` (table système minimale : `AllocatePages`, `FreePages`, `ConOut->OutputString` ;
port série COM1, registres de contrôle et MSR émulés), sans QEMU ; `EFIRUN=...` pour un autre lanceur.
Le tas est fixé à 64 Mio (16 et 4 Mio en repli) et la pile à 4 Mio : un programme à nombreuses tâches (pile de
256 Kio chacune) ou à récursion très profonde peut les épuiser.

Exemple complet : **AlexBoot**, le chargeur d'Alex OS (`boot/uefi/alexboot.al` du dépôt Alex OS) : lecture de
fichiers sur la partition EFI, carte mémoire, écran GOP, vérification Ed25519, `ExitBootServices`, passage au
noyau.

## Windows : `--windows`

```sh
alexc build --native --windows app.al                 # -> app.exe
alexc build --native --target windows-x86_64 app.al -o outil.exe   # équivalent
make test-native-windows                             # mêmes tests que test-native, version Windows
```

Le compilateur produit un **exécutable Windows x64** (y compris depuis Linux : la génération ne dépend pas de
l'hôte) : PE32+ console
(sous-système 3, Windows 8 / Server 2012 ou ultérieur), sans éditeur de liens, sans CRT ni DLL autre que
`kernel32.dll` et `ntdll.dll`, toujours présentes. Le programme garde **tout le sous-ensemble natif** (ramasse-miettes,
exceptions et traces de pile identiques à la VM, fermetures, classes, `match`, `async`, modules) et les modules
`io`, `os`, `math`, `string`, `tasks`, `asyncio`. `posix` est refusé à la compilation (`hw` l'est déjà hors
`--freestanding`).

| Élément | Windows |
|---|---|
| Image | `.text` (RX), `.rdata` (R), `.idata` (RW : IAT, descripteurs, noms), `.reloc`, `.bss` ; chargée de préférence à `0x140000000`, mais le code est **indépendant de la position** (mode `pic` de la cible UEFI : données, fonctions et IAT adressées relativement à RIP) : ASLR avec entropie haute (`DYNAMIC_BASE`, `HIGH_ENTROPY_VA`), `NX_COMPAT`, une section `.reloc` sans correction |
| Appels Windows | convention Microsoft x64 (`MsCall`) : `rcx`, `rdx`, `r8`, `r9`, pile au-delà de 32 octets réservés, `rsp` aligné sur 16 ; les résultats de 32 bits (BOOL, DWORD) sont masqués, la moitié haute de `rax` étant indéfinie |
| Point d'entrée | pile du programme de 256 Mio engagée par `VirtualAlloc` (pages physiques à la demande ; 64 puis 16 Mio si l'engagement est refusé) ; bornes de pile du TEB élargies (`gs:[8]`, `gs:[16]`) pour que les sondes de pile et la répartition des exceptions internes aux DLL acceptent cette pile et celles des tâches ; puis `argc` / `argv` / `envp` reconstruits comme sous Linux |
| Arguments | `GetCommandLineW`, découpée selon les règles de la CRT de Microsoft (guillemets, `\"`, `""`), en UTF-8 |
| `print`, traces | tampon de 64 Kio comme sous Linux ; vers une **console** : UTF-8 converti en UTF-16 et `WriteConsoleW` (accents et emoji corrects quelle que soit la page de code de la console) ; vers un tube ou un fichier : octets UTF-8 tels quels (`WriteFile`), fins de ligne `\n` |
| `input()` | console : `ReadConsoleW` puis UTF-8 ; tube ou fichier : `ReadFile` ; le `\r` d'une fin de ligne CRLF est retiré ; Ctrl+Z en début de ligne : fin de fichier |
| Mémoire | tas, grands objets et piles de tâches par `VirtualAlloc` / `VirtualFree` (le runtime ne rend que des allocations entières) ; page de garde des tâches : `VirtualProtect(PAGE_NOACCESS)` |
| Fin | `ExitProcess(code)` après vidage de la sortie |

Le runtime et la stdlib natifs parlent aux appels système Linux (`__syscall(numéro, …)`). Pour la cible Windows,
l'abaissement remplace chaque `__syscall` par un appel à `__rt_win_syscall` (runtime en Alex,
`RuntimeWindows.hpp`), qui les traduit en appels kernel32 avec les mêmes conventions de retour (≥ 0 ou
`-errno`) : `read`, `write`, `open` (drapeaux `O_CREAT`, `O_EXCL`, `O_TRUNC`, `O_APPEND` → `CreateFileW`),
`close`, `stat` (mode, taille, dates), `mprotect`, `nanosleep`, `clock_gettime` (compteur de performance, heure
système précise), `getpid`, `getppid` (`NtQueryInformationProcess`), `uname` (« Windows », nom DNS de la
machine, version de `RtlGetVersion`), `getcwd`, `chdir`, `mkdir`, `rmdir`, `unlink`. Les codes d'erreur Win32
deviennent les errno de Linux (table de `_dosmaperr`), si bien que les messages d'erreur de `io` et `os` sont
ceux de Linux et de la VM. Chemins : UTF-8 → UTF-16 ; `/` est accepté comme séparateur.

Différences avec l'exécutable Linux (et avec la VM sous Windows) : `os.name()` vaut `"Windows"` et
`os.platform()` `"windows"` ; `os.getenv` ignore la casse des noms, comme Windows ; `os.cwd()` rend le chemin
Windows (`C:\…`) ; `os.remove` supprime aussi un fichier en lecture seule (comme `unlink` sous Linux) ; un
débordement de la pile d'une tâche termine le processus (code `0xC0000005`) au lieu d'un signal.
Les intrinsèques réservées au runtime : `__windows()` (choix à la compilation, comme `__freestanding()`) et
`__wincall("dll!Nom", arguments…)` (fonction importée ; `"Nom"` seul : `kernel32.dll`), qui ajoute l'import à
l'exécutable (seuls les imports du code gardé sont émis).

**Tests** (`make test-native-windows`, `tests/native/run_windows_tests.sh`) : les 41 programmes de
`tests/native` et les tâches de `tests/native/only` donnent la même sortie, le même code de sortie, la même
erreur et la même trace de pile que la VM, aussi avec `ALEX_GC_STRESS=1` et vers une console (UTF-16) ; plus
la ligne de commande (guillemets, barres obliques inverses, argument vide, tabulation, caractères hors du plan
de base), `input()` en CRLF, `os` et `io` sur des chemins accentués, la structure du PE (`objdump`) et le refus
de `posix`. Les exécutables y sont lancés sous Linux par `tests/native/windows/winrun.cpp`, un **chargeur de
test** (pas un émulateur complet) : il place l'image à une adresse quelconque au-delà de 4 Gio, applique les
relocations, résout les imports par nom et fournit les fonctions de kernel32 / ntdll avec leur sémantique
(codes d'erreur Win32, UTF-16, poignées, `ERROR_BROKEN_PIPE` en fin de tube…). Il vérifie surtout la convention
d'appel : `rsp` aligné sur 16 à chaque appel, et au retour `rcx`, `rdx`, `r8`-`r11`, `xmm0`-`xmm5` et la zone
réservée détruits, la moitié haute de `rax` aléatoire pour un résultat de 32 bits ; un `VirtualFree` qui ne
vise pas une allocation entière l'arrête. `WINRUN=wine make test-native-windows` lance les mêmes
comparaisons avec la VM sous Wine (sans les vérifications de convention d'appel propres à `winrun`).

### Applications graphiques : `--gui` et le module `wingui`

```sh
alexc build --native --windows --gui examples/windows/calculatrice.al -o calculatrice.exe
```

`--gui` (implique `--windows`) produit une application **sans console** (sous-système 2) avec, en ressource
(`.rsrc`), un manifeste : contrôles communs v6 (styles visuels de Windows 10/11), DPI système, compatibilité
Windows 10/11. Le module natif `wingui` (seulement avec `--windows`) construit l'interface avec les contrôles
Win32 de user32 et gdi32 :

| Fonction | Rôle |
|---|---|
| `window(titre, largeur, hauteur)` | fenêtre principale (taille intérieure, non redimensionnable), affichée par `run()` |
| `label(parent, texte, x, y, l, h, right=false)` | texte statique |
| `edit(parent, texte, x, y, l, h, readonly=false, right=false)` | champ d'une ligne |
| `button(parent, texte, x, y, l, h, on_click)` | bouton ; `on_click` : fermeture ALEX `func()` |
| `get_text(c)`, `set_text(c, s)`, `enable(c, actif)` | texte et état d'un contrôle (UTF-8 ↔ UTF-16) |
| `font(points, bold=false)`, `set_font(c, f)` | police Segoe UI (tous les contrôles ont Segoe UI 10 points) |
| `message(parent, titre, texte)` | boîte de message |
| `click(bouton)` | clic comme à la souris (`BM_CLICK`) : tests automatiques |
| `capture(fenêtre, "image.bmp")` | image de la fenêtre dessinée par Windows (`PrintWindow`), BMP 32 bits |
| `show(f)`, `close(f)`, `run()` | affichage, fermeture (`WM_CLOSE`), boucle de messages jusqu'à la fermeture de la fenêtre principale |

Coordonnées en pixels à 96 ppp, mises à l'échelle du DPI du système. Les clics arrivent dans la procédure de
fenêtre, une fonction ALEX que Windows appelle à travers un **thunk** convention Microsoft x64
(`__wincallback("f")`, `Op::WinThunk`) : il préserve rbx, rbp, rdi, rsi, r12–r15, remet r15 (profondeur
d'appel) à 0 — Windows ne le garde pas forcément pendant l'appel —, met rbp à 0 (la trace d'une erreur s'arrête
au rappel) et isole la chaîne des `try`. Une exception non rattrapée dans un rappel termine le programme ; sans
console, la trace est montrée par `MessageBoxW` (titre « Erreur ALEX ») avant `ExitProcess`.

`make test-native-windows` pilote la calculatrice d'exemple sous `winrun`, qui simule user32 et gdi32 en
mémoire (`WINRUN_CLICKS="7 × 8 ="` : chaque clic devient un `WM_COMMAND`, puis les textes des contrôles sont
affichés), appelle chaque rappel en vérifiant les registres non volatils (avec un r15 quelconque), exige que la
fenêtre principale soit affichée avant la boucle de messages, et vérifie la boîte d'erreur. La calculatrice a
aussi un auto-test pour Windows lui-même : `ALEX_CALC_AUTOTEST="7 * 8 ="` (clics par `BM_CLICK`, état affiché
après chacun) et `ALEX_CALC_CAPTURE=fin.bmp` (image de la fenêtre).

## ARM64 : `--target linux-aarch64`

`alexc build --native --target linux-aarch64 main.al` (alias `--arm64`, `--target arm64` / `aarch64`) produit
un exécutable ELF AArch64 statique pour Linux (Raspberry Pi 4/5 en 64 bits, serveurs Graviton / Ampere, Mac
Apple Silicon sous Linux, Android en ligne de commande avec un noyau Linux), sans libc ni chargeur dynamique.
C'est le même compilateur, le même IR (`NativeLower`) et le même runtime ALEX (ramasse-miettes, exceptions,
tâches, traces de pile) ; seuls changent le générateur et l'assembleur :

| Fichier | Rôle |
|---|---|
| `include/alex/native/A64.hpp`, `src/NativeA64.cpp` | assembleur A64 (encodages vérifiés contre llvm-mc), relocations ADRP / ADD / LDR |
| `src/NativeCodegenA64.cpp` | IR → AArch64, runtime assembleur (sortie tamponnée, erreurs, traces, commutation de tâches) |
| `include/alex/native/RuntimeA64.hpp` | traduction en Alex des appels système x86-64 vers la table générique d'AArch64 |
| `src/NativeElf.cpp` (`writeElfA64`) | ELF `EM_AARCH64`, segments alignés sur 64 Kio (noyaux à pages de 4, 16 et 64 Kio) |

Conventions : arguments dans x0..x7 (au-delà, sur la pile), résultat dans x0 ; x19..x22 reçoivent les
registres virtuels les plus utilisés (comme rbx, r12..r14 sous x86-64), x28 compte la profondeur d'appel
(r15), x29 / x30 forment la chaîne des cadres lue par les traces et le ramasse-miettes ; sp reste aligné sur
16. Les dispositions partagées avec le runtime (enregistrement d'un `try`, registres rangés pour le GC, pile
initiale d'une tâche) sont celles de x86-64, ce qui permet au runtime en Alex d'être commun aux deux.

Sémantique identique à la VM, y compris dans les cas où les deux processeurs diffèrent : division entière
arrondie vers −∞ (`sdiv` puis correction), `INT64_MIN // -1`, conversion d'un flottant NaN ou hors limites en
entier (`INT64_MIN`, comme `cvttsd2si`), comparaisons avec NaN, décalages hors 0..63 (erreur).

Le runtime commun et la stdlib appellent `__syscall` avec les numéros de Linux x86-64 : pour cette cible,
l'abaissement les redirige vers `__rt_a64_syscall`, qui utilise les appels `*at` (`openat`, `mkdirat`,
`unlinkat`...), `pipe2`, `dup3`, `clone(SIGCHLD)` pour `fork`, traduit les drapeaux d'`open` et convertit la
`struct stat`. `__svc(n, ...)` fait un appel système AArch64 brut ; `__a64()` vaut vrai pour cette cible
(`os.arch()` rend `"aarch64"`). Modules disponibles : tout le natif Linux (`posix`, `tasks`, `pixmap`...) ;
`--freestanding`, `--uefi` et l'assembleur en ligne restent propres à x86-64 (Windows ARM64 : section suivante).

`make test-native-aarch64` compare l'assembleur à llvm-mc (152 instructions), valide l'émulateur de test
`tests/native/aarch64/a64run.cpp` (interpréteur A64 + appels système Linux relayés à l'hôte) contre des
programmes C compilés par clang à -O0 et -O2, puis exécute toute la suite native sous cet émulateur :
sortie, code de sortie, message et trace de pile identiques à la VM, aussi avec `ALEX_GC_STRESS=1`.
`A64RUN=qemu-aarch64 make test-native-aarch64` utilise QEMU ; sur une machine ARM64, `A64RUN=` exécute
directement. `--emit-map` fonctionne comme pour x86-64 (adresses à partir de 0x40000000).

### Windows ARM64 : `--windows --arm64`

`alexc build --native --windows --arm64 app.al` (ou `--target windows-aarch64` / `windows-arm64`) produit un
exécutable PE32+ ARM64 (machine 0xAA64, sous-système 10.0 : Windows 10 / 11 sur ARM, Surface Pro X / 11,
PC Snapdragon X, machines virtuelles Windows ARM sur Mac Apple Silicon) ; avec `--gui`, une application graphique
(module `wingui`, manifeste, calculatrice d'exemple comprise). Mêmes sections, mêmes imports et même runtime
Windows (`RuntimeWindows.hpp`) qu'en x64 : seuls le code et la convention d'appel changent.

- Convention de Windows ARM64 (AAPCS64) pour les fonctions importées : arguments x0..x7 puis la pile, x0..x17
  détruits par l'appel ; la moitié haute de x0 est masquée pour un résultat de 32 bits (BOOL, DWORD) ;
  **x18 désigne le TEB et n'est jamais modifié** par le code généré (l'assembleur n'utilise que x16 / x17).
- Image indépendante de la position (adresses ADRP relatives), `DYNAMIC_BASE` (obligatoire sous ARM64) avec
  un bloc de relocations vide ; pile du programme de 256 Mio engagée par `VirtualAlloc`, limites de pile du TEB
  (`[x18 + 8]`, `[x18 + 16]`) élargies comme en x64.
- Rappels (`__wincallback`, procédures de fenêtre) : point d'entrée AAPCS64 qui préserve x19..x29, remet la
  profondeur d'appel (x28) à 0, isole la chaîne des try et arrête la trace d'une erreur au rappel.

`make test-native-windows-arm64` (`WIN_ARCH=arm64 tests/native/run_windows_tests.sh`) exécute toute la suite
Windows (programmes de `tests/native`, tâches, ligne de commande, `input()` CRLF, `os` / `io`, calculatrice
pilotée par clics, boîte d'erreur, structure du PE vérifiée par `llvm-readobj`) avec
`tests/native/aarch64/a64winrun.cpp` : l'émulateur ARM64 de `a64run` et les fonctions kernel32 / user32 /
gdi32 simulées de `winrun`. À chaque appel d'une fonction importée, il vérifie l'alignement de sp et x18, puis
détruit x1..x17 et d0..d7 / d16..d31 et rend une moitié haute quelconque pour les résultats de 32 bits ; chaque
rappel reçoit x19..x29 et d8..d15 quelconques, vérifiés au retour. Sur un PC Windows ARM64, l'exécutable se
lance directement.

## Carte des symboles : `--emit-map`

`alexc build --native [--freestanding | --uefi | --windows] [--arm64] --emit-map prog.al -o prog.bin` écrit aussi
`prog.bin.map` : une ligne « début fin nom » par fonction (adresses du code une fois l'image chargée ; pour UEFI
et Windows, relatives à l'adresse préférée 0x10000000 et 0x140000000). Sert à lire un blocage ou une panique (adresse de RIP relevée par le moniteur de
QEMU, adresses de retour sur la pile).

## Modules de la bibliothèque compilables en natif : `# alex: native`

Un module de `stdlib/` dont l'en-tête contient la ligne `# alex: native` est compilé par `alexc build
--native` (et `--freestanding`) depuis son fichier, comme un module du programme : il doit donc respecter le
sous-ensemble natif (annotations de types, champs de classe déclarés, valeurs par défaut littérales,
`implements` d'interfaces...). Sans cette ligne, un module de la bibliothèque n'est disponible qu'avec la VM
(ou par sa version intégrée au compilateur, comme `math`, `string`, `hw`).

Modules natifs livrés : `pci.pci_ids`, `pci.pci_config`, `pci.pci_device`, `pci.pci_bus`, `interrupt.*`,
`dma.*`, `driver.*`, `storage_driver.*`, `network_driver.*`, `usb.usb_descriptor`, `usb_driver.*`,
`gpu_driver.*` (docs/DRIVERS.md). Les mêmes fichiers s'exécutent dans la VM grâce à la machine simulée de
`stdlib/hw/hw.al` (`hw.sim_pci`, `hw.sim_apic`).

Ajouts au langage utiles au bas niveau (VM et natif) :

- littéraux entiers hexadécimaux, binaires et octaux avec séparateurs : `0xFEE0_0000`, `0b1010_0001`,
  `0o755`, `1_000_000` ; jusqu'à 64 bits (`0xFFFF_FFFF_FFFF_FFFF` vaut -1, complément à deux) ;
- champs de classe DÉCLARÉS sans valeur : `config: ConfigAccess` dans le corps d'une classe (le
  constructeur les affecte ; requis par le compilateur natif pour les champs de type objet) ;
- un mot-clé peut commencer un chemin de module : `use async as aio`, `use async.task as task`.

Pour un noyau qui pilote du DMA ISA (tampons sous 16 Mio), déclarer une zone basse libre :
`dma.low_zone(0x20000, 0x60000)` (le tas des pages commence à 32 Mio).

## Étapes suivantes

- **E7** (fait, voir `docs/CHANGEMENTS_PHASE3.md`) : multiprocesseur, processus isolés et ordonnancés en
  parallèle, pilote virtio-blk, sous-répertoires et noms longs FAT.
- **E8** (fait, voir `docs/CHANGEMENTS_PHASE4.md` et `docs/DRIVERS.md`) : PCI, contrôleurs d'interruptions
  (PIC, APIC local, IO-APIC, MSI), DMA, cadre de pilotes, pilotes IDE / AHCI / NVMe, e1000, UHCI (clavier
  HID, stockage de masse), carte Bochs ; tous testés sous QEMU et dans la machine simulée de la VM.
- Ensuite : code du noyau exécuté en parallèle (ramasse-miettes avec arrêt des autres cœurs, allocation par
  cœur) ; interruptions des périphériques par l'IOAPIC et virtio par interruption plutôt que par scrutation ;
  invalidation du TLB entre cœurs (nécessaire dès que deux cœurs partageront un même espace d'adressage :
  processus à plusieurs fils).

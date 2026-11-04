# ALEX 1.3.0 — nouvelles cibles natives : Windows x64, ARM64 Linux et Windows

Ajouts rétrocompatibles : le langage, le bytecode (ALBC 0.4) et les cibles existantes du backend natif sont
inchangés.

## Ajouts

* **Windows x64** (`alexc build --native --windows`) : exécutable PE32+ console, sans CRT ni DLL autre que
  kernel32 / ntdll ; appels système Linux du runtime et de la stdlib traduits en appels kernel32
  (`include/alex/native/RuntimeWindows.hpp`), sortie console UTF-16 (`WriteConsoleW`), image indépendante de la
  position (ASLR). docs/NATIVE.md, « Windows ».
* **Applications graphiques Windows** (`--windows --gui`, module `wingui`) : fenêtres, contrôles, procédures
  de fenêtre écrites en ALEX (`__wincallback`), manifeste (contrôles v6, DPI), erreurs montrées par
  `MessageBoxW`. Exemple : `examples/windows/calculatrice.al`.
* **Linux ARM64** (`--target linux-aarch64`, alias `--arm64`) : ELF AArch64 statique (Raspberry Pi 4/5,
  Graviton, Ampere...) ; nouvel assembleur A64 (`src/NativeA64.cpp`) et générateur (`src/NativeCodegenA64.cpp`),
  même IR et même runtime ALEX ; appels système traduits vers la table générique d'AArch64
  (`include/alex/native/RuntimeA64.hpp`). `os.arch()` rend `"aarch64"`. docs/NATIVE.md, « ARM64 ».
* **Windows ARM64** (`--windows --arm64`, `--target windows-aarch64`) : PE32+ machine 0xAA64, console et
  graphique ; convention AAPCS64 de Windows (x18 réservé au TEB). docs/NATIVE.md, « Windows ARM64 ».
* **`--target SYSTÈME-ARCH`** : `linux`, `windows` ; `x86_64`, `aarch64` / `arm64` (ex. `windows-arm64`).

Limites : `--uefi`, `--freestanding` et l'assembleur en ligne restent propres à x86-64.

## Mode dynamique du compilateur natif

* `alexc build --native` compile désormais **tout programme** : hors du sous-ensemble statique, il bascule en
  **mode dynamique** — le bytecode de la VM traduit en code machine, avec un runtime écrit en Alex qui
  reproduit la VM (valeurs, opérateurs, classes, exceptions et traces, fermetures, async/await).
  `--dynamic` l'impose, `--static` l'interdit (diagnostics du sous-ensemble). docs/NATIVE.md, « Tout
  programme ».
* Instruction `FSqrt` (racine carrée IEEE : `sqrtsd` / `fsqrt`) ; puissance flottante correctement arrondie
  (double-double), identique à la glibc.
* Fonctions natives réécrites en Alex : `core`, `math`, `string`, `collections`, `io`, `os`, `process`, `cli`,
  `asyncio`, `fd` (dont USB), `hwsim`, `signal`, `gc` (comptes d'objets comme la VM), `net` (sockets, DNS),
  `thread`, `sync`, `memory`, `office` (deflate identique octet pour octet, XML, PDF, PNG), `ui` (backend headless complet).
* Interface graphique en natif (`ALEX_UI_BACKEND=headless`) : cœur portable de la VM (fenêtres, widgets émulés,
  interaction, événements, menus, module window) et rastériseur réécrits en Alex ; captures PNG identiques octet
  pour octet à celles de la VM. Le backend X11 reste propre à la VM.
* GC conservatif plus précis : cadres des fonctions du programme et petits cadres du runtime mis à zéro à l'entrée.
* Performances du mode dynamique : 1,2 à 3 fois plus rapide que la VM sur la plupart des programmes (chemins
  rapides en ligne, petits entiers partagés, cache des méthodes, intégration des petites fonctions du runtime,
  indexation des chaînes en O(1), réserve des gros blocs) ; docs/NATIVE.md.
* `tools/native_coverage.sh` : comparaison systématique natif / VM sur `examples/` et `tests/` — 162 programmes sur 174
  identiques à la VM (sortie et code de sortie) ; restent TLS et FFI (docs/NATIVE.md).

## Vérification

* `make test-native-windows` (51 vérifications) : chargeur de test `tests/native/windows/winrun.cpp`
  (kernel32 / user32 / gdi32 simulés, convention Microsoft x64 vérifiée) ; validé aussi sur Windows 11.
* `make test-native-aarch64` (47) : assembleur comparé à llvm-mc (152 instructions), émulateur
  `tests/native/aarch64/a64run.cpp` validé contre clang, suite native complète identique à la VM.
* `make test-native-windows-arm64` (51) : `tests/native/aarch64/a64winrun.cpp` (émulateur ARM64 + fonctions
  de winrun, AAPCS64 et x18 vérifiés).
* Non-régression : `make test-native` (46).

## Correctifs (2026-11-01, pour ALEX Studio 1.3.1)

* `ui.clipboard` / presse-papiers de `ui.view` **sous Windows** : le runtime appelait `xclip` / `wl-copy` (outils
  Linux, introuvables) et ne gardait qu'un presse-papiers interne au programme ; il utilise maintenant le
  presse-papiers Win32 (`OpenClipboard`, `CF_UNICODETEXT`, fins de ligne CR LF ↔ LF) — `dyn_w32.al`, `dyn_ui.al`.
  Fenêtre hors écran (`ALEX_UI_BACKEND=headless`) : presse-papiers interne seulement, comme avant.
* `gui.set_ui_font_size(px)` / `gui.ui_font_size()` : taille de la police de l'interface (10 à 32 px, 14 par
  défaut) ; hauteurs de ligne, de menu, d'onglet et de titre de dialogue ajustées, effet immédiat
  (`Surface.refresh_metrics`, appelée à chaque construction de la vue).
* `gui.surface` : touches `*`, `+`, `-`, `/` du pavé numérique nommées (« ctrl++ », « ctrl+- »...).
* Compilateur : une fonction intégrée appelée seulement dans une f-string (`f"{max(notes)}"`, `f"{len(l)}"`) n'était
  pas importée automatiquement (NameError « 'max' n'est pas défini ») ; les expressions des f-strings sont maintenant
  prises en compte (`src/resolver/resolver.al`, `inject_builtins`). Effet après reconstruction de la chaîne d'outils.

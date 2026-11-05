<p align="center"><img src="docs/images/alex_logo_256.png" width="128" alt="ALEX"></p>

# ALEX

Langage de programmation pour les applications, les systèmes et le bas niveau : syntaxe à indentation, types
graduels, classes, interfaces, enums, `match`, fermetures, asynchrone, exceptions ; machine virtuelle à bytecode,
compilation native x86-64 et ARM64 (Linux, Windows) et noyaux sans système d'exploitation ; bibliothèque standard de 390 modules
(fichiers, réseau, processus, fils, interfaces graphiques, matériel, pilotes) ; serveur de langage, débogueur et
outils pour les éditeurs et les IDE.

```
make alex                          # construit l'exécutable ./alex
./alex new gui mon_app             # projet depuis un modèle (console, gui, cli, lib, server, kernel, driver)
cd mon_app && ../alex run          # exécute
../alex test                       # tests
../alexc build --native --windows main.al   # exécutable Windows x64 (main.exe), aussi depuis Linux
../alexc build --native --windows --gui ../examples/windows/calculatrice.al   # application graphique Windows
../alexc build --native --target linux-aarch64 main.al   # exécutable ARM64 Linux (Raspberry Pi, Graviton...)
../alexc build --native --windows --arm64 main.al     # exécutable Windows ARM64 (PC Snapdragon, Surface...)
make pure                          # chaîne 100 % ALEX, sans g++ : build/alexc (outils), build/alexvm (VM)
powershell -ExecutionPolicy Bypass -File tools/selfhost/bootstrap.ps1   # idem sous Windows : build/alexc.exe, build/alexvm.exe
build/alexc.exe bundle -o alexc.exe   # un seul fichier : SDK et VM embarqués, copiable n'importe où (fait par bootstrap.ps1)
build/alexc run main.al            # compilateurs et machine virtuelle écrits en ALEX (docs/SELFHOST.md)
build/alexc test · fmt · doc · new · pkg · repl · debug   # les outils, eux aussi écrits en ALEX
make package                       # dist/ : archive .tar.gz et paquet .deb installables
make installer-windows              # Windows : installeur (alex.exe inscrit dans le PATH) et archive zip
```

## Apprendre ALEX

| Guide | Contenu |
|---|---|
| [Langage ALEX : parcours pratique pour débutants](docs/guides/Langage_ALEX_parcours_pratique_debutants.pdf) (PDF, 18 pages) | apprendre ALEX de zéro, pas à pas |
| [Diaporama : apprendre ALEX](docs/guides/Diaporama_Apprendre_ALEX.pdf) (PDF, 27 diapositives) | présentation du langage et de ses notions |

Le compilateur prêt à l'emploi (Windows, Linux) est dans les [versions publiées](https://github.com/ennuum/alex-lang/releases).

## ALEX Studio

L'IDE du langage, **ALEX Studio**, est un projet séparé, non publié dans ce dépôt (exécutables autonomes
`alex-studio` et `alex-studio.exe`, paquets propres). Il s'appuie sur ce SDK : `alexc lsp` (IntelliSense), `alexc debug --protocol
2`, `alexc test --json`, `alexc doc --json`, `alexc new`, `alexc pkg` — protocoles décrits dans [docs/SDK.md](docs/SDK.md).

## Outils

`alexc run · check · build · test · fmt · doc · new · lsp · debug · pkg · edit · repl` —
référence et protocoles : [docs/SDK.md](docs/SDK.md). Distribution, VS Code, intégration continue :
[docs/ECOSYSTEME.md](docs/ECOSYSTEME.md).

## Documentation

| Thème | Guides |
|---|---|
| Langage | [TYPES](docs/TYPES.md), [OOP](docs/OOP.md), [CLOSURES](docs/CLOSURES.md), [COMPREHENSIONS](docs/COMPREHENSIONS.md), [PYTHONIC](docs/PYTHONIC.md), [ASYNC](docs/ASYNC.md), [CHANNELS](docs/CHANNELS.md) |
| Jeux | [GAMEDEV](docs/GAMEDEV.md) (math3d, mesh, scene, physics, physics2d, spatial, ecs, gameloop, ai) |
| Applications | [UI_VIEW](docs/UI_VIEW.md), [IO](docs/IO.md), [NETWORK](docs/NETWORK.md), [JSON](docs/JSON.md), [SYSAPP](docs/SYSAPP.md), [CONCURRENCY2](docs/CONCURRENCY2.md), [MEDIA](docs/MEDIA.md), [MULTIMEDIA](docs/MULTIMEDIA.md), [OFFICE](docs/OFFICE.md) |
| Système et bas niveau | [NATIVE](docs/NATIVE.md), [HARDWARE](docs/HARDWARE.md), [DRIVERS](docs/DRIVERS.md), [MEMORY](docs/MEMORY.md), [STANDALONE](docs/STANDALONE.md) |
| Outils | [SELFHOST](docs/SELFHOST.md) (compilateur et VM ALEX en ALEX), [SDK](docs/SDK.md), [ECOSYSTEME](docs/ECOSYSTEME.md), [VERSIONS](docs/VERSIONS.md) |
| Bibliothèque | `alexc doc --html docs/api` (référence de tous les modules) |

## Tests

`make -k test` : suite complète (compilateur, VM, bibliothèque, natif et noyaux sous QEMU, interfaces,
outillage). Cibles détaillées dans le `Makefile`.

## Licence

Copyright 2026 Alexandre Koffi. Distribué sous la [licence Apache 2.0](LICENSE) ; voir aussi [NOTICE](NOTICE)
(les noms « ALEX » et le logo restent des signes distinctifs de l'auteur).

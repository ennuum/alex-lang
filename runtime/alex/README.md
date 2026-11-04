# runtime/alex — runtime d'ALEX, 100 % ALEX

Fichiers lus à l'exécution par `alexc` (dossier `runtime/` à côté de `stdlib/`) :

| Dossier | Contenu |
|---|---|
| `prelude/core.al`, `prelude/collections.al` | préludes fusionnés avec tout programme (`run`, `build`, `repl`) |
| `native/source.al`, `windows.al`, `a64.al` | runtime du backend natif (`build --native`) |
| `native/dyn*.al` | runtime du mode dynamique et de la VM (`--dynamic`, `alexc vm`) |
| `stdlib/*.al` | modules de la stdlib en version native typée (math, string, io, os, hw, tasks, asyncio, posix, wingui) |
| `../vm/vm.al` | machine virtuelle |

Aucun fichier C++ n'est lu par `alexc`. Ces fichiers sont la source canonique ; les anciennes copies embarquées
dans `include/alex/native/Runtime*.hpp`, `src/NativeStdlib.cpp` et `runtime/native/*/*_prelude_native.hpp` ne servent
plus qu'au compilateur C++ de référence et à la graine `bootstrap/` : à supprimer après `make seed`.

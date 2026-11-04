# Écosystème ALEX — distribution, éditeurs, intégration continue, modèles, documentation

## Installer ALEX

```
make package                 # dist/alex-<version>-linux-x86_64.tar.gz et .deb ; version = celle du compilateur (docs/VERSIONS.md)
make installer-windows         # dist/alex-<version>-windows-x86_64.zip + -setup.exe : installe alex.exe et l'ajoute au PATH (docs/VERSIONS.md)
make release                 # compilateur STABLE (1.0.0), tests complets, puis paquets
```

* **Archive** : `tar -xzf alex-1.0.0-linux-x86_64.tar.gz && sh alex-1.0.0-linux-x86_64/install.sh` (dans
  `/usr/local`) ou `sh install.sh ~/.local` (sans droits d'administration). Sans installer :
  `./bin/alex run fichier.al` (la bibliothèque est trouvée dans `lib/alex/stdlib`).
* **Paquet Debian** : `sudo apt install ./alex-lang_1.0.0_amd64.deb`.

Contenu installé :

| Chemin | Contenu |
|---|---|
| `bin/alex` | compilateur, machine virtuelle, compilation native, outils (`lsp`, `debug`, `test`, `doc`, `fmt`, `new`, `pkg`) |
| `bin/alexc`, `bin/alexvm` | chaîne d'outils écrite en ALEX (si construite : `make alexvm` ou `make pure`) |
| `lib/alex/stdlib/` | bibliothèque standard (390 modules) |
| `lib/alex/templates/` | modèles de projets |
| `share/doc/alex/` | guides (Markdown) et `reference/index.html` (référence de la bibliothèque) |
| `share/alex/editors/vscode/` | extension VS Code |

`make dist PLATFORM=...` construit seulement l'exécutable pour d'autres plateformes (compilateur croisé).
Sous Windows, les outils utilisés par les IDE (`process`, `alexc lsp`, `alexc debug`) ont une implémentation native.
ALEX Studio, l'IDE, est un projet séparé avec ses propres paquets (`alex-studio`, qui dépend de `alex-lang`).

## Modèles de projets

| Modèle | Contenu |
|---|---|
| `console` | programme en ligne de commande : point d'entrée, module testable, tests |
| `gui` | application graphique `ui.view` (fenêtre X11 / Windows ou terminal) : état, vue, logique métier testée |
| `cli` | outil `argparse` : sous-commandes, aide, version, exécutable autonome |
| `lib` | bibliothèque réutilisable : module documenté, exemple, tests, publication `alexc pkg` |
| `server` | serveur HTTP/1.1 `network.http` : routes JSON, logique testée sans réseau |
| `kernel` | noyau démarrable sans OS (Multiboot x86-64, écran VGA, port série) : `alexc build --native --freestanding`, QEMU |
| `driver` | pilote de périphérique à ports d'E/S, testé sur la machine simulée de `hw`, compilable dans un noyau |

```
alexc new kernel mon_os && cd mon_os
alexc build --native --freestanding noyau.al -o mon_os.bin
qemu-system-x86_64 -kernel mon_os.bin -serial stdio -device isa-debug-exit,iobase=0xf4,iosize=0x04
```

Chaque modèle est vérifié par `make test-tooling` (création, puis ses tests passent).

## Intégration continue

`alexc new` ajoute au projet (option `--ci`, GitHub par défaut) :

* `.github/workflows/alex.yml` : installe ALEX depuis l'archive de `make package` (variable de dépôt
  `ALEX_DIST_URL`), vérifie la mise en forme (`alexc fmt --check`), lance les tests (`alexc test --json`, résultats
  conservés comme artefact) ;
* ou `.gitlab-ci.yml` : mêmes étapes (`verifier`, `tester`).

Le dépôt d'ALEX lui-même : `.github/workflows/ci.yml` construit le compilateur et lance `make test`.

## VS Code (et autres éditeurs)

`editors/vscode/` est une extension complète :

| Élément | Fichier |
|---|---|
| langage `.al` : commentaires, crochets, indentation après `:`, repli par indentation | `language-configuration.json` |
| coloration (mots-clés, déclarations, imports, chaînes et f-strings, nombres, types, appels, opérateurs) | `syntaxes/alex.tmLanguage.json` |
| extraits (`func`, `class`, `if`, `for`, `try`, `match`, `main`, `test`, `gui`) | `snippets/alex.json` |
| IntelliSense : client LSP de `alexc lsp` (`vscode-languageclient`) | `src/extension.js` |
| débogueur : adaptateur DAP sans dépendance au-dessus de `alexc debug --protocol 2` (points d'arrêt conditionnels, compteurs, journaux, variables dépliables, évaluation, pas à pas, saisie dans la console) | `src/dap.js` |
| tâches (`alexc test`, `alexc build`, `alexc fmt`, `alexc doc`), commandes « exécuter », « tests », « ouvrir dans ALEX Studio » | `src/extension.js` |

Construction du paquet `.vsix` : `cd editors/vscode && npm install && npx vsce package`, puis
*Extensions › Installer depuis un VSIX*. Réglage `alex.path` : chemin de l'exécutable.

Tout éditeur parlant LSP peut utiliser `alexc lsp` directement (voir [SDK.md](SDK.md#serveur-de-langage-alex-lsp)) ;
tout client DAP peut utiliser `node editors/vscode/src/dap.js`.

## Documentation

* Guides : `docs/*.md` — en particulier [SDK.md](SDK.md) (outils et protocoles),
  [UI_VIEW.md](UI_VIEW.md) (interfaces), [NATIVE.md](NATIVE.md) (compilation native et noyaux),
  [DRIVERS.md](DRIVERS.md) (pilotes).
* Référence de la bibliothèque : `alexc doc --html docs/api` (site statique avec filtre, une page par module), ou
  `alexc doc module` dans un terminal, ou la vue Documentation d'ALEX Studio.
* Référence d'un projet : `alexc doc --html docs/api .` (ses propres modules, à partir des commentaires).

## Vérification de l'outillage

| Cible | Vérifie |
|---|---|
| `make test-lsp` | serveur de langage : session LSP réelle (35 vérifications) |
| `make test-tooling` | + débogueur protocole 2 (29), outils `new` / `test` / `fmt` / `doc` / profileur (33), adaptateur DAP (15) |
| `make test-studio` | ALEX Studio de bout en bout dans une fenêtre hors écran, captures d'écran |
| `make test-ui-view` | composants (dont ceux de l'IDE : gouttière, survol, Ctrl+clic, complétion externe) |

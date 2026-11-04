# Phase 5 — ALEX Studio et outillage

## ALEX Studio (`alex studio`, `IDE/studio/`)

* **Core** : fenêtre principale (menus, barre d'outils, barre d'activités, barre latérale, onglets, fil d'Ariane,
  panneau du bas, barre d'état), thèmes Studio sombre / clair tirés du logo, page d'accueil, projets à modèles,
  explorateur avec structure du fichier, recherche / remplacement dans le projet, palette de commandes (fichiers,
  commandes, symboles, lignes), exécution avec console interactive, réglages persistants.
* **IntelliSense** : client du serveur de langage — complétion contextuelle et extraits, survol, diagnostics
  soulignés, définition (F12, Ctrl+clic), références, occurrences, renommage dans le projet, actions rapides,
  mise en forme.
* **Débogueur** : points d'arrêt (conditions, compteurs, journaux), variables nommées et dépliables, globales, pile,
  espions, console d'évaluation, survol des valeurs, pas à pas, arrêt sur exception avant déroulement.
* **Designer** : fichiers `.alui`, surface WYSIWYG faite de vrais composants, palette, arborescence, inspecteur
  (propriétés, liaisons à l'état, événements), annuler / rétablir, génération de `nom_ui.al` et `nom.al`, aperçu.
* **Professional** : explorateur de tests, gestionnaire de paquets, profileur, construction (autonome, natif,
  bytecode, noyau), empaquetage (archive, `.deb`).

## Outils (C++)

* `alex lsp` : service de langage sur le vrai compilateur (`src/tooling/LanguageService.cpp`) et serveur LSP
  (`--jsonl` pour le Studio).
* `alex debug --protocol 2` : inspecteur et évaluateur sans effet de bord, points d'arrêt enrichis, arrêt sur
  exception, sortie / entrée du programme dans le protocole ; noms des variables locales dans le bytecode
  (version mineure 3).
* `alex run --profile` (profileur exact), `alex test` (découverte, parallélisme, JSON), `alex fmt`, `alex doc`
  (Markdown, JSON, site HTML), `alex new` (7 modèles), `alex studio`.
* JSON natif (`json.parse` ~1700 fois plus rapide), `ALEX_FLUSH`.

## Bibliothèque

* `ui.view` : `code_editor` pour IDE, `image`, `canvas`, `design_surface`, interception de la souris par un
  conteneur, rappels à 4–5 arguments, thèmes `studio`, couleurs `#rrggbb` directes.
* Rendu : chemins rapides du rastériseur (rectangles, rectangles arrondis, mélange entier) et cache des glyphes —
  une image complète du Studio passe de 73 ms à 17 ms. Polices : Œ œ et symboles de l'IDE.
* `testing` : rapport structuré pour `alex test`.

## Écosystème

* Documentation : [STUDIO.md](STUDIO.md), [SDK.md](SDK.md), [ECOSYSTEME.md](ECOSYSTEME.md), README.
* Extension VS Code (`editors/vscode`) : grammaire, extraits, client LSP, adaptateur DAP testé.
* `make package` : archive et paquet Debian d'ALEX (Studio, modèles, documentation HTML, lanceur de bureau).
* Intégration continue : modèles GitHub / GitLab pour les projets, `.github/workflows/ci.yml` pour le dépôt.

## Tests ajoutés

`make test-lsp` (35), `test-tooling` (+ débogueur 29, outils 33, DAP 15), `test-studio` (scénario complet du
Studio, 10 étapes avec captures), `tests/ui_view/test_ide_widgets.al` (5).

# SDK ALEX — outils, protocoles et formats

Ce document décrit la chaîne d'outils `alex` telle qu'un IDE, un éditeur, un script d'intégration continue ou
un autre outil peut l'utiliser : commandes, serveur de langage, protocole du débogueur, formats JSON des tests
et du profileur, format des interfaces `.alui`, modèles de projets.

## Commandes

| Commande | Rôle |
|---|---|
| `alexc run [--profile[=rapport.json]] fichier.al [--] [args...]` | exécute (avec `alex.toml` : `alexc run [-- args...]` lance le point d'entrée) ; `--` sépare les arguments du programme (`alexc run -- --help`) et ne lui est pas transmis ; `--profile` : rapport de profilage |
| `alexc check fichier.al` | analyse, résolution des modules, vérification des types, sans exécuter |
| `alexc build fichier.al -o sortie [--standalone \| --native [--freestanding] \| --emit-ir]` | bytecode `.albc`, exécutable autonome, binaire natif, noyau sans OS |
| `alexc build app.al --native --windows [--gui] --icon app.ico` | exécutable Windows avec icône (ressources RT_ICON / RT_GROUP_ICON ; aussi celle des fenêtres). `alex vm --windows` met le logo d'ALEX (`runtime/alex/windows/alex.ico`) sur la VM, donc sur `alexc run` et `--standalone` |
| `alexc test [chemins] [--filter texte] [--json] [--list] [-j N]` | exécuteur de tests |
| `alexc fmt [--check] [chemins]` | mise en forme (indentation en espaces, espaces de fin, lignes vides, fin de fichier) |
| `alexc doc module \| fichier.al` · `--json module` · `--html dossier [modules]` · `--list` | référence de l'API |
| `alexc new [modèle] nom [--dir dossier] [--ci github\|gitlab\|aucune]` · `--list [--json]` | projet depuis un modèle |
| `alexc lsp [--jsonl] [dossier]` | serveur de langage |
| `alexc debug [--protocol 2] [--break-on-exception] fichier.al [args...]` | débogueur (JSON Lines) |
| `alexc pkg init\|add\|remove\|install\|update\|list\|publish\|verify` | gestionnaire de paquets |
| `alex edit [--gui] [fichier]` · `alexc repl` | éditeur léger, boucle interactive |

Variables d'environnement : `ALEX_STDLIB` (dossier de la bibliothèque), `ALEX_UI_BACKEND=headless` (fenêtres hors
écran), `ALEX_FLUSH=1` (chaque `print` est vidé aussitôt : sortie lue en direct par un IDE), `ALEX_TEST_REPORT=1`
(posée par `alexc test` : `testing` écrit des lignes `@@ALEXTEST {json}`), `ALEX_EXE` (posée par `alex` : chemin de
l'exécutable, pour les programmes qui relancent `alex`).

## Serveur de langage (`alexc lsp`)

Protocole LSP 3.17 standard sur stdin / stdout (en-têtes `Content-Length`) : utilisable par VS Code, Neovim,
Emacs, Sublime Text, Helix, Zed, Kate... Avec `--jsonl`, un message JSON par ligne (sans en-têtes) : c'est le mode
d'ALEX Studio (IDE distribué à part). Le dossier donné (ou `rootUri` / `workspaceFolders`) est la racine du projet.

Capacités : `textDocument/` `didOpen`, `didChange` (texte complet ou modifications incrémentales), `didClose`,
`didSave`, `publishDiagnostics`, `completion` (déclencheur `.`), `hover`, `signatureHelp` (`(` `,`), `definition`,
`declaration`, `references`, `documentHighlight`, `documentSymbol` (hiérarchique), `prepareRename`, `rename`,
`formatting`, `codeAction` (`quickfix`, `source.organizeImports`) ; `workspace/symbol`, `didChangeWatchedFiles`.
Encodage des positions : `utf-16` (défaut LSP), `utf-32` ou `utf-8` selon `general.positionEncodings` du client.

Le service analyse avec le vrai lexer, parser et compilateur d'ALEX ; un fichier dont la syntaxe est cassée reste
indexé (la ligne fautive est neutralisée), les diagnostics viennent de la compilation complète du module et de
ses imports (erreur dans un module importé : signalée sur la ligne de l'import). Les types sont inférés pour la
complétion et la navigation : annotations, `Classe(...)`, `module.Classe(...)`, valeur de retour des fonctions
(`p := forme.point(3, 4)` → `Point`), `self`, héritage.

Configuration pour Neovim (exemple) :

```lua
vim.lsp.start({ name = "alex", cmd = { "alex", "lsp" }, root_dir = vim.fs.dirname(vim.fs.find({ "alex.toml" }, { upward = true })[1]) })
```

## Protocole du débogueur (`alexc debug --protocol 2`)

JSON Lines : une commande par ligne sur stdin, un événement par ligne sur stdout. Le programme démarre arrêté à
sa première ligne (`paused`, raison `entry`) : l'IDE pose ses points d'arrêt puis envoie `continue`. Les
commandes qui exigent un programme arrêté et arrivent pendant l'exécution sont différées jusqu'à la pause suivante.
Un champ `id` facultatif dans une commande est recopié dans la réponse.

### Commandes

| `command` | Champs | Effet |
|---|---|---|
| `continue` | | reprend |
| `step` | `mode` : `over`, `into`, `out` | pas à pas (dans le code du programme : la bibliothèque standard est traversée) |
| `pause` | | arrêt à la prochaine ligne |
| `stop` | | termine la session |
| `breakpoints.set` | `file`, `breakpoints` : `[{line, condition?, hitCount?, logMessage?}]` | remplace les points d'arrêt du fichier ; réponse `ack` avec `lines` |
| `breakpoint.add` / `breakpoint.remove` | `file`, `line` | point d'arrêt simple |
| `exceptions` | `break` : bool | arrêt sur exception non rattrapée |
| `variables` | `ref` | enfants d'une valeur dépliable → événement `variables` |
| `evaluate` | `expression`, `frame` (indice, −1 : courant) | → événement `evaluate` (`result`, `type`, `ref` ou `error`) |
| `input` | `text` | ligne fournie à `input()` du programme |

### Événements

| `event` | Champs |
|---|---|
| `started` | session lancée |
| `paused` | `reason` (`entry`, `breakpoint`, `step`, `pause`, `exception`), `file`, `line`, `frames` (du programme au frame courant : `function`, `file`, `line`, `locals` [`{name, type, value, ref?}`]), `globals`, `exception` (`type`, `message`) |
| `output` | `category` (`stdout`, `log`), `text`, (`file`, `line` pour un point de journalisation) |
| `input` | le programme attend une ligne |
| `variables` | `ref`, `variables` |
| `evaluate` | `expression`, `result` / `type` / `ref`, ou `error` |
| `ack` / `error` | `command`, `message` |
| `terminated` / `stopped` / `exception` / `compile_error` | fin de session, `exitCode`, `message` |

Points d'arrêt : `condition` est une expression évaluée sans effet de bord (une condition invalide arrête),
`hitCount` = arrêt au N-ième passage seulement, `logMessage` interpole `{expression}` et n'arrête pas. Le
bytecode (version mineure 3) conserve le nom de chaque variable locale : les variables sont nommées comme dans le
source. Sans `--protocol 2`, `alexc debug` garde l'ancien protocole (variables `local[n]`, sortie sur stderr).

Un adaptateur **DAP** (Debug Adapter Protocol) sans dépendance traduit ce protocole pour VS Code et les autres
clients DAP : `node editors/vscode/src/dap.js` (testé par `tests/tooling/dap_test.py`).

## Tests : `alexc test --json`

Une ligne JSON par résultat :

```json
{"event":"test","file":"/projet/tests/test_calc.al","name":"test_add","line":4,"status":"passed","message":"","duration":0.0001}
{"event":"file","file":"/projet/tests/test_calc.al","status":"failed","duration":0.02,"exitCode":0}
{"event":"summary","passed":3,"failed":1,"errors":1,"skipped":0,"files":2,"duration":0.03}
```

`status` : `passed`, `failed` (AssertionError), `error` (autre exception), `skipped`. Un fichier sans test reconnu
est exécuté comme un script : réussi si son code de sortie est 0 et qu'aucun résumé « N échecs » non nul n'est
affiché. Code de sortie de `alexc test` : 1 s'il y a un échec ou une erreur.

## Profil : `alexc run --profile=rapport.json`

```json
{"version":1,"elapsed":0.012,"instructions":92628,
 "functions":[{"name":"fib","file":"prof.al","line":2,"calls":8361,"instructions":91966,"self":0.0120,"total":0.0120}],
 "lines":[{"file":"prof.al","line":4,"function":"fib","instructions":50160,"self":0.0068}]}
```

Mesure exacte par instruction : `self` = temps passé dans la fonction elle-même, `total` = temps inclusif
(appels récursifs comptés une fois). Le temps d'un appel natif bloquant (lecture, `sleep`) est attribué à la
ligne qui l'appelle. Le surcoût du profilage est d'environ ×2.

## Documentation : `alexc doc --json module`

```json
{"module":"network.http","file":"…/stdlib/network/http.al","summary":"HTTP/1.1 : client…","header":"…",
 "entries":[{"kind":"classe","name":"Server","signature":"class Server","doc":"…","line":602,
             "members":[{"kind":"méthode","name":"serve","signature":"func serve(handler, max_requests=null)","doc":"…","line":671}]}]}
```

Les commentaires `#` placés juste au-dessus d'une déclaration en sont la documentation ; le premier bloc de
commentaires du fichier est l'en-tête du module (sa première phrase sert de résumé).

## Format des interfaces `.alui`

JSON produit et lu par le Designer d'ALEX Studio :

```json
{
  "format": "alex-ui/1",
  "name": "formulaire",
  "title": "Inscription",
  "width": 640,
  "height": 420,
  "state": {"nom": "", "accepte": false},
  "root": {
    "uid": 1, "type": "column", "props": {"padding": 2, "gap": 1}, "events": {}, "bind": {},
    "children": [
      {"uid": 2, "type": "field", "props": {"placeholder": "Votre nom"}, "bind": {"value": "nom"}, "events": {"on_submit": "valider"}, "children": []},
      {"uid": 3, "type": "button", "props": {"label": "Valider", "primary": true}, "events": {"on_click": "valider"}, "bind": {}, "children": []}
    ]
  }
}
```

| Champ d'un nœud | Sens |
|---|---|
| `type` | `column`, `row`, `panel`, `scroll` (conteneurs) ; `text`, `button`, `field`, `textarea`, `checkbox`, `radio`, `select`, `slider`, `spinbox`, `progress`, `list_view`, `image`, `separator`, `spacer` |
| `props` | paramètres du composant `ui.view` du même nom (`label`, `content`, `style`, `placeholder`, `gap`, `padding`, `flex`...) ; les listes (`options`, `items`) s'écrivent `"Un, Deux"` |
| `bind` | propriété → variable de `state` : la valeur affichée vient de `etat[...]` et chaque modification l'y écrit |
| `events` | événement (`on_click`, `on_change`, `on_submit`, `on_select`, `on_activate`) → nom du gestionnaire |
| `uid` | identifiant stable (sélection, annuler / rétablir) |

Code généré (`formulaire_ui.al`) : `etat`, `actions` (dict nom → fonction), `vue()`, `TITRE`, `LARGEUR`,
`HAUTEUR`. Un événement appelle `actions[nom]` (avec la nouvelle valeur pour `on_change`, `on_submit`,
`on_select`, `on_activate`) ; une liaison met d'abord `etat` à jour.

## Dossiers de sources (`alex.toml`)

```toml
[package]
name = "mon_app"
version = "0.1.0"
description = "Gestionnaire de tâches"
entry = "src/main.al"
sources = ["src"]
```

`sources` déclare les dossiers de sources du projet : ce sont des racines de modules pour **tout** fichier du
projet — application, tests, outils — avec `run`, `check`, `test`, `build` (bytecode et natif) et le serveur de
langage. `use vues.principale` trouve `src/vues/principale.al`, aussi depuis `tests/`. Le manifeste retenu est le
`alex.toml` le plus proche en remontant depuis le fichier compilé. Ordre de recherche : bibliothèque standard,
dossier courant, dossiers `sources`, dossier du fichier et ses parents, `alex_packages`.

## Modèles de projets

`alexc new` copie un dossier de `templates/` (à côté de `stdlib/`) en remplaçant `{{nom}}`, `{{Nom}}`,
`{{description}}`, `{{modele}}` et `{{entree}}` dans les noms de fichiers et le contenu, puis ajoute `alex.toml`,
`README.md` (commun), `.gitignore` et l'intégration continue choisie. Pour créer un modèle : un dossier avec un
`template.toml` (`title`, `description`, `category`, et facultativement `essai` : la commande proposée après la
création, `alexc run` sinon ; `entry` : point d'entrée, ex. `src/main.al` ; `sources` : dossiers de sources
recopiés dans `alex.toml`) et les fichiers du projet (binaires compris : icônes, images) ; il apparaît dans `alexc new --list` et dans l'assistant
d'ALEX Studio. `alexc new gui` (un nom de modèle seul) crée le projet `mon_gui` depuis ce modèle ; avec le modèle
`lib`, un nom déjà pris par un module de la bibliothèque standard (`cli`, `gui`...) est refusé, puisque `use nom`
chargerait ce module.

## Composants ui.view pour les outils

Ajoutés pour l'IDE et utilisables par toute application : `code_editor` (points d'arrêt, ligne d'exécution,
soulignements, occurrences, complétion externe avec extraits, survol, Ctrl+clic, `goto`, `border`), `image`
(PNG / BMP / PPM), `canvas` (dessin libre avec souris, molette et clavier en coordonnées locales),
`design_surface` (surface de conception) ; thèmes `studio` et `studio_light`. Voir les commentaires de
`stdlib/ui/view/view.al`.

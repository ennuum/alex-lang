# Éditeur de code : `alex edit` et `ui.view.code_editor`

## `alex edit`

```
alex edit                       # terminal, dossier courant, fichier vide
alex edit main.al outils.al     # ouvre ces fichiers (un onglet chacun)
alex edit --gui main.al         # dans une fenêtre
alex edit --dir projet --theme light
```

Le même programme (`stdlib/outils/editeur.al`, écrit en Alex avec `ui.view`) s'affiche dans le terminal
ou, avec `--gui`, dans une fenêtre :

- **à gauche**, l'arbre des fichiers du dossier (dossiers cachés, `build`, `node_modules`... omis ;
  Entrée ou double clic ouvre) ;
- **au centre**, un onglet par fichier, marqué `•` s'il a des modifications ;
- **en bas**, le panneau de sortie et la barre d'état (position du curseur, langage, messages).

| Touche | Action |
|---|---|
| Ctrl+N, Ctrl+O, Ctrl+S, Ctrl+Maj+S | nouveau, ouvrir, enregistrer, enregistrer sous |
| Ctrl+W | fermer l'onglet (confirmation s'il est modifié) |
| Ctrl+Q | quitter (confirmation s'il reste des fichiers non enregistrés) |
| F5 | enregistrer puis lancer `alexc run` sur le fichier ; F5 pendant l'exécution l'arrête (Ctrl+F5 aussi) |
| F8 | fin de l'entrée du programme en cours (`input()` reçoit une fin de fichier) |
| F7 | `alexc check` (vérification sans exécution) |
| F12 | montrer / cacher le panneau de sortie (Échap le cache aussi) |
| Ctrl+Pg↑ / Ctrl+Pg↓ | onglet précédent / suivant |
| F6 | passer de l'arbre à l'éditeur ; F10 : menus |

**Entrée du programme** : pendant l'exécution, une ligne « Entrée ▸ » apparaît sous la sortie et reçoit le
focus. Ce qu'on y tape (Entrée pour envoyer) arrive sur l'entrée standard du programme : `input()` le lit, et
la ligne est répétée dans la sortie. F8 ou le bouton « Fin » ferme l'entrée ; Échap rend le focus à l'éditeur.
L'invite d'`input("...")` s'affiche avant l'attente (la VM vide stdout avant de lire stdin).

La sortie du programme (sortie standard et erreurs) s'affiche **pendant** l'exécution, puis son code de
sortie et sa durée. Les erreurs qui citent le fichier (`fichier.al:12:5: ...` ou une trace `fichier.al:12,
dans ...`) deviennent des **marqueurs** : la ligne est surlignée, le message écrit à sa droite, et la barre
d'état indique la première.

## Le composant `v.code_editor`

```
v.code_editor(valeur, on_change, language="alex", on_cursor=null, markers=null, readonly=false,
              line_numbers=true, tab_size=4, id=null, width=null, height=null, flex=null)
```

Utilisable dans toute application `ui.view`, dans les deux rendus :

- `on_change(texte)` reçoit le texte entier après chaque modification ; `on_cursor(ligne, colonne)` la
  position (à partir de 1) ;
- `language` : `"alex"`, `"python"`, `"json"` ou `"text"`. `ui.view.syntax.language_of(chemin)` le
  déduit de l'extension ;
- `markers` : liste de `{"line": n, "message": "...", "kind": "error" | "warning"}`.

**Affichage** : numéros de ligne, ligne courante surlignée, coloration syntaxique, parenthèse
correspondante, occurrences recherchées, barre de défilement. Police à chasse fixe dans la fenêtre
(DejaVu Sans Mono embarquée sous Linux, Consolas sous Windows).

**Clavier** :

| Touche | Action |
|---|---|
| flèches, Début (intelligent : après l'indentation), Fin, Pg↑/Pg↓, Ctrl+←→, Ctrl+Début/Fin | déplacement ; avec Maj : sélection |
| Ctrl+A, Ctrl+C, Ctrl+X, Ctrl+V | tout sélectionner, copier, couper, coller (sans sélection : la ligne entière) |
| Ctrl+Z, Ctrl+Y (ou Ctrl+Maj+Z) | annuler, rétablir (la frappe continue d'une ligne est groupée) |
| Entrée | nouvelle ligne avec la même indentation, un niveau de plus après `:` `{` `[` `(` |
| Retour arrière | dans l'indentation : recule jusqu'au taquet précédent |
| Tab, Maj+Tab | indente, désindente (la ligne ou les lignes sélectionnées) |
| Ctrl+/ | commente / décommente (`#`) |
| Ctrl+D, Ctrl+Maj+K, Alt+↑ / Alt+↓ | dupliquer, supprimer, déplacer la ligne |
| Ctrl+F, F3 / Maj+F3 | rechercher (nombre de résultats), suivant / précédent |
| Ctrl+G (ou Ctrl+L) | aller à la ligne |
| Ctrl+Espace | complétion (liste des propositions) |
| F4, Maj+F4, Ctrl+F4 | plier / déplier le bloc du curseur, tout plier, tout déplier (fenêtre : aussi Ctrl+Maj+[ et Ctrl+Maj+]) |
| Échap puis Tab | sortir de l'éditeur (Tab seul indente) |

**Complétion** : la liste s'ouvre en tapant (2 caractères d'un identifiant, hors commentaire et chaîne) ou par
Ctrl+Espace. Propositions : mots-clés, constantes et fonctions prédéfinies du langage, plus les identifiants du
texte (après un point : ceux du texte seulement). ↑ ↓ Pg↑ Pg↓ choisissent, Entrée ou Tab (ou un clic) valident
en un seul pas d'annulation, Échap ferme. `completion=false` la désactive.

**Pliage** : une ligne suivie de lignes plus indentées ouvre un bloc, signalé par ▾ dans la marge ; F4 ou un clic
sur le triangle le replie en ▸ avec « … N lignes » à droite (une erreur dans le bloc masqué colore l'en-tête).
Le curseur saute les lignes masquées ; Entrée sur un en-tête replié, les opérations sur les lignes et la
recherche déplient ce qu'il faut ; les blocs repliés suivent les insertions et suppressions de lignes au-dessus.

**Coloration** : les chaînes à triples guillemets de Python (`"""` et `'''`, avec préfixes f, r, b) et les
commentaires `/* ... */` d'Alex sont colorés sur toutes leurs lignes (`syntax.tokens_from(ligne, langage, état)`
retourne `[segments, état de fin]` ; `syntax.states(lignes, langage)`). Les chaînes d'Alex n'ont pas de retour
à la ligne littéral (erreur du lexer), il n'y a donc rien d'autre à propager.

**Souris** : clic, glisser pour sélectionner, double clic (mot), triple clic (ligne), clic dans la
gouttière (ligne entière), barre de défilement, molette.

Les menus d'une application peuvent envoyer ces touches à l'éditeur qui a le focus avec `v.press("ctrl+z")`.

## Tests

`make test-ui-view` lance, en plus des tests de `ui.view` :

- `tests/ui_view/test_code_editor.al` (144 vérifications) : coloration (y compris multiligne), pliage, complétion, entrée standard de F5, édition, annulation, sélection et
  presse-papiers, opérations sur les lignes, recherche, marqueurs, lecture seule, et l'application
  complète (arbre, onglets, enregistrement, exécution, marqueurs d'erreur, dialogues de confirmation) ;
- `tests/ui_view/test_view_gui.al` : le composant et l'application dans une fenêtre headless, avec
  captures ;
- `tests/ui_view/edit_pty.py` : `alex edit` dans un vrai pseudo-terminal (saisie, Ctrl+S, F5, Ctrl+Q).

## Limites

- Pas de retour à la ligne automatique des lignes longues (défilement horizontal) ; pas de multi-curseur.
- Le pliage est fondé sur l'indentation (pas sur la grammaire) : un commentaire en colonne 0 dans un bloc le
  termine ; les blocs repliés ne sont pas conservés à la fermeture du fichier.
- La complétion ne connaît pas les types : elle propose des mots, pas les membres d'un objet.
- `alexc run` ne vide stdout que lorsqu'il attend une saisie : une sortie abondante sans `input()` peut
  n'apparaître qu'à la fin (tampon de tube). Le programme lancé n'a pas de terminal : pas de saisie touche
  par touche (`io.console`).

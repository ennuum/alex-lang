# Interfaces : `ui.view` (description), `gui` (fenêtre), `tui` (terminal)

Thèmes : `dark`, `light`, `terminal`, `studio` et `studio_light` (ceux d'ALEX Studio), ou un dict de rôles.

Une même description d'interface s'affiche dans une fenêtre ou dans un terminal :

```
use ui.view as v
use gui                                     # ou : use tui

etat := {"n": 0, "nom": ""}

func plus():
    etat["n"] += 1

func set_nom(t):
    etat["nom"] = t

func vue():
    return v.column([
        v.text("Compteur", style="title"),
        v.text("Valeur : " + str(etat["n"])),
        v.row([v.button("+1", plus, primary=true), v.button("Quitter", v.quit)]),
        v.field(etat["nom"], set_nom, placeholder="Votre nom"),
    ], padding=1)

gui.run(vue, "Compteur", 480, 320)          # ou : tui.run(vue)
```

| Couche | Rôle |
|---|---|
| `ui.view` | les composants (ce qu'on voit) et leur comportement au clavier et à la souris, commun aux deux affichages |
| `gui` | `run(vue, titre, largeur, hauteur, theme, on_key, on_tick, tick)` : fenêtre (Windows : Win32/Direct2D ; Linux : X11 ; partout : `ALEX_UI_BACKEND=headless`, hors écran) ; `TestApp` |
| `tui` | `run(vue, titre, theme, on_key, on_tick, tick, mouse)` : plein écran dans le terminal (écran alternatif, souris, couleurs 24 bits / 256 / 16 / sans) ; `TestApp` |
| `ui` (existant) | fenêtres et contrôles natifs, canvas, animations : le socle sur lequel `gui` dessine |
| `tui.*` | le terminal en bas niveau : `terminal`, `screen`, `input`, `style`, `width`, `markup`, et `inline` (menus, saisies, tableaux, barres de progression dans un script ordinaire) |

## Modèle

- **La vue est une fonction** sans argument qui renvoie l'arbre des composants à partir de l'état du programme
  (variables, dicts, objets). Elle est rappelée après chaque événement : les gestionnaires (`on_click`,
  `on_change`...) modifient l'état, l'affichage suit. Un gestionnaire peut accepter moins d'arguments que
  ceux fournis (`on_change` sans argument), jamais plus : `on_click()` ne reçoit rien,
  `on_change(valeur)`, `on_select(indice)` et `on_activate(indice)` un argument. Pour `tree`, ces deux
  derniers reçoivent le dict du nœud. Les enfants d'un conteneur peuvent être des composants, des textes
  ou des nombres (devenus `text`), des list (aplaties), ou `null` / `false` (ignorés : `cond and
  v.text(...)`).
- **État propre aux composants** : curseur d'un champ, défilement d'une liste, onglet ou menu ouvert, tri
  d'un tableau... sont gardés d'une image à l'autre sous le chemin du composant dans l'arbre, ou sous son
  `id=` (à donner aux composants qui apparaissent et disparaissent). Les valeurs (`value`, `selected`,
  `checked`) sont **contrôlées** : celle du programme fait foi quand elle change ; si le programme n'écoute
  pas `on_change`, la valeur modifiée par l'utilisateur est gardée par le composant.
- **Tailles portables** : `width` en caractères (la place du contenu : texte d'un bouton, saisie d'un champ),
  `height` en lignes, `padding` et `gap` en unités (une cellule dans le terminal, 8 pixels dans une
  fenêtre) : la même vue tient dans les deux. Une taille donnée l'emporte sur l'étirement ; sans taille,
  listes, tableaux et arbres prennent autant de lignes que de contenu (3 à 8 ou 10) et s'agrandissent
  s'il reste de la place. Quand la place manque, chacun cède en proportion.
- **Mise en page** : `column` et `row` placent leurs enfants. `flex=n` partage l'espace libre. Les champs,
  listes, tableaux et panneaux s'étirent en travers par défaut ; dans une ligne, les autres composants sont
  centrés verticalement. `align` (sur un enfant) ou `align=` (sur le conteneur) donne "start", "center",
  "end" ou "stretch". `v.spacer()` pousse ce qui suit.
- **Contrôle** : `v.quit()` termine l'application, `v.focus(id)` donne le focus à un composant,
  `v.press(touche)` envoie une touche au composant qui a le focus (menus Édition),
  `v.app().stop(valeur)` termine avec une valeur (rendue par `run`). Un composant qui a un `id` garde le
  focus quand la vue l'entoure d'un nouveau conteneur.

## Composants

| Fonction | Rôle |
|---|---|
| `text(contenu, style, wrap, text_align)` | texte ; style `title`, `subtitle`, `bold`, `muted`, `error`, `success`, `warning`, `accent` |
| `button(libellé, on_click, primary, enabled)` | bouton (Entrée / Espace / clic) |
| `field(valeur, on_change, on_submit, placeholder, password, width)` | champ d'une ligne (édition : ←→, Début/Fin, Ctrl+←→ par mot, Ctrl+W, Ctrl+U, Ctrl+K, collage) |
| `textarea(valeur, on_change, height, readonly)` | texte multiligne avec défilement |
| `checkbox(libellé, coché, on_change)` | case à cocher |
| `radio(options, choix, on_change, horizontal)` | choix exclusif (flèches) |
| `select(options, choix, on_change)` | liste déroulante (Entrée l'ouvre, ↑↓ changent directement) |
| `slider(valeur, min, max, step, on_change)` | curseur glissant (flèches, Pg↑/Pg↓, Début/Fin, souris, molette) |
| `spinbox(valeur, min, max, step, on_change)` | nombre (↑↓, saisie de chiffres validée par Entrée, ▲▼) |
| `progress(valeur 0..1, libellé)` | barre de progression |
| `list_view(éléments, choix, on_select, on_activate, height)` | liste (saisie rapide de la première lettre, double clic / Entrée activent) |
| `table(colonnes, lignes, choix, on_select, on_activate, sortable)` | tableau : colonnes `str` ou `{"title", "width", "align"}` ; tri par clic sur l'entête ou `s` / `S` ; les indices rendus sont ceux de `lignes` |
| `tree(nœuds, on_select, on_activate)` | arbre (`{"label", "children", "id", "expanded"}`) ; → / ← ouvrent, ferment, descendent, remontent |
| `column(enfants, gap, padding, align)`, `row(...)` | conteneurs |
| `panel(contenu, title, border, padding)` | cadre avec titre |
| `scroll(contenu, height)` | zone qui défile (molette, Pg↑/Pg↓, suit le focus) |
| `tabs([[titre, contenu], ...], choix, on_change)` | onglets (←→ sur la barre, Ctrl+Pg↑/Pg↓ de partout) |
| `split(a, b, vertical, ratio)` | deux zones, séparation déplaçable (souris, Ctrl+Maj+flèches ; F6 passe de l'une à l'autre) |
| `dialog(titre, contenu, [[libellé, fonction], ...], on_close, width)` | dialogue modal, où qu'il soit dans la vue ; `alert(titre, message, on_close)`, `confirm(titre, message, on_yes, on_no)` |
| `menu_bar([menu(titre, éléments), ...])` | barre de menus ; `item(libellé, fonction, shortcut, enabled, checked)`, `submenu(libellé, éléments)`, `menu_separator()` |
| `separator()`, `spacer(flex, size)` | séparation, espace |
| `code_editor(valeur, on_change, language, on_cursor, markers, readonly)` | éditeur de code : coloration, numéros de ligne, annulation, recherche, marqueurs d'erreur (voir [EDITEUR.md](EDITEUR.md), qui décrit aussi `alex edit`) |
| `code_editor(..., breakpoints, on_gutter, exec_line, highlights, completion_provider, on_hover, on_definition, goto, border)` | propriétés pour un IDE : colonne de points d'arrêt (simples, conditionnels, journaux, désactivés), ligne d'exécution, soulignement ondulé des marqueurs à colonnes (`{line, col, end_col, kind}`), occurrences, complétion fournie par le programme (avec détails et extraits `${1:x}`), bulle de survol (après 0,45 s ; demande un `tick`), Ctrl+clic, déplacement du curseur imposé par jeton |
| `image(chemin, px_width, px_height, alt)` | image PNG / BMP / PPM (proportions conservées) ; `alt` dans le terminal |
| `canvas(paint, px_width, px_height, on_mouse, on_wheel, on_key, focusable, track_move, expand)` | dessin libre : `paint(p)` avec `p.fill`, `stroke`, `line`, `circle`, `text`, `image`, `gradient`, `clip` en coordonnées locales, couleurs `#rrggbb` ou rôles du thème ; souris et clavier locaux |
| `design_surface(contenu, form_width, form_height, form_title, selected, on_pick, on_resize, on_delete, on_key)` | surface de conception (Designer d'ALEX Studio) : affiche de vrais composants dans un cadre de fenêtre et intercepte la souris pour les désigner |

## Clavier et souris

- **Partout** : Tab / Maj+Tab passent d'un composant à l'autre (dans un dialogue ouvert, seulement entre
  les siens). Échap ferme le menu, la liste ou le dialogue du dessus. F10 ouvre la barre de menus. Les
  raccourcis des éléments de menu (`shortcut="ctrl+o"`) marchent menu fermé. Ctrl+Q quitte (et Ctrl+C dans
  le terminal). `on_key(touche)` reçoit les touches que personne n'a utilisées (renvoyer `true` : traitée).
- **Noms des touches** : comme `tui.input` : le caractère lui-même, ou `enter`, `tab`, `escape`, `space`,
  `backspace`, `delete`, `up`, `down`, `left`, `right`, `home`, `end`, `page_up`, `page_down`, `f1`..`f12`,
  avec `ctrl+`, `alt+`, `shift+`.
- **Souris** : clic, double clic, glisser (curseur, séparation, barres de défilement), molette sur ce qui
  est sous le pointeur, survol (fenêtre). Un clic à côté d'un menu ou d'une liste ouverte la ferme ; sur le
  titre d'un autre menu, il l'ouvre.

## Affichage

- **Terminal** : les composants dessinent en cellules (cadres en caractères de boîte, `[x]`, `(•)`, `▸`,
  `█`...) sur un tampon ; seules les cellules modifiées sont réécrites. Le curseur du terminal est placé
  dans le champ actif. Couleurs selon le terminal (`COLORTERM`, `TERM`) ; sans couleurs (`NO_COLOR`), la
  vidéo inverse et le gras marquent sélection et focus. Le terminal est rétabli à la sortie, même après une
  erreur ou un signal TERM / HUP ; le redimensionnement est suivi.
- **Fenêtre** : formes arrondies anticrénelées, ombres des menus et dialogues, anneau de focus, survol,
  polices DejaVu Sans et DejaVu Sans Mono (code) embarquées (Linux) ; le texte est mesuré par le moteur de la fenêtre.
- **Thèmes** : `"dark"` (défaut), `"light"`, `"terminal"` (couleurs du terminal) ou un dict de rôles
  (`{"base": "dark", "accent": "#ff8800"}`). Rôles : `bg`, `surface`, `field`, `text`, `muted`, `accent`,
  `accent_text`, `border`, `selection`, `selection_text`, `danger`, `success`, `warning`, `disabled`, et
  des rôles dérivés (`button`, `header`, `menubar`, `hover`, `track`...) qui reprennent une couleur de base
  s'ils ne sont pas donnés.
- **Rythme** : `tick=0.5, on_tick=f` appelle `f(temps)` régulièrement (horloge, données qui changent) et
  redessine, sauf si `f` renvoie `false` (rien n'a changé).

## Tests et captures

`tui.TestApp(vue, largeur, hauteur, theme, on_key)` et `gui.TestApp(vue, largeur, hauteur, theme,
on_key)` (avec `ALEX_UI_BACKEND=headless`) pilotent une application sans écran :

- **Événements** : `press("tab")`, `press("down", 3)`, `type("texte")`, `paste(...)`, `click("OK")` (sur
  le texte affiché) ou `click(x, y)`, `double_click`, `drag(x0, y0, x1, y1)`, `move`, `resize(largeur,
  hauteur)`, `wheel("texte", crans)` ou `wheel(x, crans, y)` (crans > 0 : vers le haut) ;
- **Lecture** : `contains`, `find`, `focused()`, `running()`.

`tui.TestApp` donne aussi l'écran (`lines`, `screen`, `html()` en HTML coloré), `gui.TestApp` des captures
PNG (`screenshot`). `make test-ui-view` lance :

- la couche terminal bas niveau (47 vérifications) ;
- les composants dans un terminal virtuel (124) ;
- l'éditeur de code et `alex edit` (71, plus 5 dans un vrai pseudo-terminal) ;
- un vrai pseudo-terminal (14) : saisie brute, souris SGR, redimensionnement, sortie propre ;
- une fenêtre hors écran (51), avec les captures examinées ;
- une vraie fenêtre X11 sous Xvfb : vrais événements X, positions prises sur la même mise en page.

## Limites

- **Fenêtre sous Windows** : `gui` utilise les mêmes fonctions natives (canvas Direct2D, événements,
  `text_input` pour la saisie). Ce rendu n'a pas pu être compilé ni essayé ici, seulement relu.
- **Caractères dans la fenêtre** : la police embarquée (DejaVu Sans, Linux) n'a ni idéogrammes CJK ni émojis
  (affichés « ? ») ; le terminal les affiche s'il en a la police.
- **Texte** : pas de sélection d'un passage à la souris dans les champs (copier / coller portent sur le
  champ entier : Ctrl+C / Ctrl+V dans la fenêtre, collage du terminal). Pas de méthode de saisie riche
  (IME), ni de texte de droite à gauche. Dans le terminal, la largeur des émojis composés dépend du
  terminal.
- **Composants** : listes à sélection simple ; pas de glisser-déposer entre composants ; dans la fenêtre, une
  police proportionnelle (normale, titre) et une à chasse fixe (code).

## Ajouts au langage (utiles aux interfaces)

- **Échappements** `\xHH`, `\uXXXX`, `\u{1F600}`, `\e` (Échap) dans les chaînes, les f-strings et les
  caractères.
- **Virgule finale** permise dans les listes, dictionnaires, tuples, appels et paramètres. Les vues se
  décrivent donc sur plusieurs lignes, une ligne par composant.
- **`core.arity(f)`** donne `[minimum, maximum]` d'arguments d'une fonction Alex.

# ALEX STANDARD LIBRARY — ui.view
#
# Description d'une interface, indépendante de l'endroit où elle s'affiche : une fonction (la vue) renvoie
# l'arbre des composants à partir de l'état du programme ; gui.run(vue) l'affiche dans une fenêtre,
# tui.run(vue) dans le terminal. Après chaque événement (touche, clic, molette...), les gestionnaires
# (on_click, on_change...) modifient l'état et la vue est recalculée.
#
# Les tailles données par le programme sont en CARACTÈRES (largeur) et en LIGNES (hauteur), donc les mêmes
# dans le terminal et dans une fenêtre. Clavier partout : Tab / Maj+Tab passent d'un composant à l'autre,
# Échap ferme un menu ou un dialogue, F10 ouvre la barre de menus, Ctrl+Q quitte.
#
# Exemple
#   use ui.view as v
#   use gui                                   # ou : use tui
#
#   etat := {"n": 0, "nom": ""}
#   func plus():
#       etat["n"] += 1
#   func nom(t):
#       etat["nom"] = t
#   func vue():
#       return v.column([
#           v.text("Compteur", style="title"),
#           v.text("Valeur : " + str(etat["n"])),
#           v.row([v.button("+1", plus, primary=true), v.button("Quitter", v.quit)]),
#           v.field(etat["nom"], nom, placeholder="Votre nom"),
#       ], padding=1)
#   gui.run(vue, "Compteur")                  # ou : tui.run(vue)
#
# Composants
#   texte et actions   text, button, separator, spacer
#   saisie             field, textarea, code_editor, checkbox, radio, select, slider, spinbox
#   graphique          image, canvas
#   données            progress, list_view, table, tree
#   structure          column, row, panel, scroll, tabs, split, dialog, alert, confirm, menu_bar, menu, item,
#                      submenu, menu_separator
#   contrôle           quit(), focus(id), app()

from core use len, type
from collections use append
use ui.view.node as _n
use ui.view.runtime as _rt

func _p(d, id, flex, width, height, align):
    d["id"] = id
    d["flex"] = flex
    d["width"] = width
    d["height"] = height
    d["align"] = align
    return d

func _list(children):
    if type(children) != "list":
        return [children]
    return children

# ---------------------------------------------------------------- texte et actions
# style : null, "title", "subtitle", "muted", "bold", "error", "success", "warning", "accent", "code".
# wrap : retour à la ligne à la largeur disponible ; text_align : "left", "center", "right".
func text(content, style=null, wrap=false, text_align="left", id=null, flex=0, width=null, height=null, align=null):
    return _n.Node("text", _p({"content": str(content), "style": style, "wrap": wrap, "text_align": text_align}, id, flex, width, height, align))

# on_click() est appelé au clic, ou par Entrée / Espace quand le bouton a le focus.
func button(label, on_click=null, primary=false, enabled=true, id=null, flex=0, width=null, align=null):
    return _n.Node("button", _p({"label": str(label), "on_click": on_click, "primary": primary, "enabled": enabled}, id, flex, width, null, align))

func separator(id=null):
    return _n.Node("separator", _p({}, id, 0, null, null, null))

# Espace extensible (flex) ou fixe (size, en caractères dans une ligne, en lignes dans une colonne).
func spacer(flex=1, size=0):
    return _n.Node("spacer", {"flex": flex, "size": size})

# ---------------------------------------------------------------- saisie
# Champ d'une ligne. on_change(texte) à chaque modification, on_submit(texte) sur Entrée. width : caractères
# (null : 20, et le champ s'étire en largeur dans une colonne). on_key(touche) : appelé avant l'édition, true si
# la touche est traitée (ex. : historique aux flèches haut / bas d'une ligne de commande).
func field(value="", on_change=null, on_submit=null, placeholder="", password=false, enabled=true, id=null, width=null, flex=0, align=null, on_key=null):
    return _n.Node("input", _p({"value": str(value), "on_change": on_change, "on_submit": on_submit, "placeholder": placeholder, "password": password, "enabled": enabled, "on_key": on_key}, id, flex, width, null, align))

# Texte sur plusieurs lignes (Entrée insère une ligne). height : lignes visibles (null : 5, et la zone
# s'agrandit s'il reste de la place).
func textarea(value="", on_change=null, height=null, placeholder="", readonly=false, enabled=true, id=null, width=null, flex=0, align=null):
    return _n.Node("textarea", _p({"value": str(value), "on_change": on_change, "placeholder": placeholder, "readonly": readonly, "enabled": enabled}, id, flex, width, height, align))

# on_change(bool)
func checkbox(label, checked=false, on_change=null, enabled=true, id=null, align=null):
    return _n.Node("checkbox", _p({"label": str(label), "checked": checked, "on_change": on_change, "enabled": enabled}, id, 0, null, null, align))

# Choix exclusif parmi options (list de str). on_change(indice).
func radio(options, selected=0, on_change=null, horizontal=false, enabled=true, id=null, align=null):
    return _n.Node("radio", _p({"options": [str(o) for o in options], "selected": selected, "on_change": on_change, "horizontal": horizontal, "enabled": enabled}, id, 0, null, null, align))

# Liste déroulante. on_change(indice).
func select(options, selected=0, on_change=null, enabled=true, id=null, width=null, flex=0, align=null):
    return _n.Node("select", _p({"options": [str(o) for o in options], "selected": selected, "on_change": on_change, "enabled": enabled}, id, flex, width, null, align))

# Curseur glissant entre min et max (pas step). on_change(valeur).
func slider(value, min=0, max=100, step=1, on_change=null, show_value=true, enabled=true, id=null, width=null, flex=0, align=null):
    return _n.Node("slider", _p({"value": value, "min": min, "max": max, "step": step, "on_change": on_change, "show_value": show_value, "enabled": enabled}, id, flex, width, null, align))

# Nombre modifiable au clavier (chiffres, ↑ ↓, Pg↑ Pg↓) ou à la souris (▲ ▼). on_change(valeur).
func spinbox(value, min=0, max=100, step=1, on_change=null, enabled=true, id=null, width=null, align=null):
    return _n.Node("spinbox", _p({"value": value, "min": min, "max": max, "step": step, "on_change": on_change, "enabled": enabled}, id, 0, width, null, align))

# Éditeur de code : police à chasse fixe, numéros de ligne, coloration (language : "alex", "python", "json",
# "text"), sélection, presse-papiers, annuler (Ctrl+Z) / rétablir (Ctrl+Y), indentation automatique, Tab /
# Maj+Tab, Ctrl+/ (commentaire), Ctrl+D (dupliquer), Alt+↑↓ (déplacer), Ctrl+F / F3 (rechercher), Ctrl+G
# (aller à la ligne). on_change(texte) après chaque modification ; on_cursor(ligne, colonne) (à partir
# de 1). markers : list de {"line", "message", "kind" : "error" / "warning"} (marge et fin de ligne).
# Tab indente : Échap puis Tab passe au composant suivant.
# Éditeur de code. Pour un IDE (ALEX Studio) :
#   breakpoints  liste de lignes (int) ou de dict {line, condition, hit, log, enabled} : colonne de points d'arrêt ;
#                on_gutter(ligne) au clic dans cette colonne
#   exec_line    ligne d'exécution du débogueur (fond et flèche), rendue visible
#   markers      dict {line, col?, end_col?, kind: error|warning|info|hint, message} : fond de ligne, message en fin
#                de ligne, soulignement ondulé si col est donnée
#   highlights   liste de [ligne, col, col_fin] (occurrences du symbole sous le curseur)
#   completion_provider(ligne, col, préfixe, membre) -> liste de str ou dict {label, detail, insert} (« ${1:x} »)
#   on_hover(ligne, col) -> texte (markdown simple) d'une bulle après 0,45 s de survol (il faut un tick)
#   on_definition(ligne, col) au Ctrl+clic ; goto [ligne, col, jeton] place le curseur quand le jeton change
# Lignes et colonnes 1-based.
func code_editor(value="", on_change=null, language="alex", on_cursor=null, markers=null, readonly=false, line_numbers=true, tab_size=4, id=null, width=null, height=null, flex=0, align=null, completion=true, breakpoints=null, on_gutter=null, exec_line=null, highlights=null, completion_provider=null, on_hover=null, on_definition=null, goto=null, border=true):
    if markers == null:
        markers = []
    if highlights == null:
        highlights = []
    return _n.Node("code_editor", _p({"value": str(value), "on_change": on_change, "language": language, "on_cursor": on_cursor, "markers": markers, "readonly": readonly, "line_numbers": line_numbers, "tab_size": tab_size, "completion": completion, "breakpoints": breakpoints, "on_gutter": on_gutter, "exec_line": exec_line, "highlights": highlights, "completion_provider": completion_provider, "on_hover": on_hover, "on_definition": on_definition, "goto": goto, "border": border}, id, flex, width, height, align))

# Image d'un fichier PNG / BMP / PPM, à sa taille en pixels (px_width x px_height) ou réduite pour tenir ;
# alt : texte affiché dans le terminal (ou si le fichier manque).
func image(path, px_width=64, px_height=64, alt="", opacity=1.0, role="accent", id=null, width=null, height=null, flex=0, align=null):
    return _n.Node("image", _p({"path": path, "px_width": px_width, "px_height": px_height, "alt": alt, "opacity": opacity, "role": role}, id, flex, width, height, align))

# Surface de dessin : paint(p) dessine avec p.fill / stroke / line / circle / text / image / gradient (coordonnées
# locales, p.width, p.height ; couleurs « #rrggbb » ou rôles du thème). on_mouse(ev) : ev x, y locaux, action
# (down, up, drag, move si track_move), clicks, shift, ctrl ; renvoie false pour ne pas redessiner.
# on_key(touche, ev) -> true si traitée (focusable=true pour recevoir le clavier).
# expand : étirement en travers du conteneur ("both", "w", "h", "none") ; flex : part de l'espace libre.
func canvas(paint, px_width=200, px_height=120, on_mouse=null, on_wheel=null, on_key=null, focusable=false, track_move=false, focus_ring=false, expand="both", id=null, width=null, height=null, flex=0, align=null):
    return _n.Node("canvas", _p({"paint": paint, "px_width": px_width, "px_height": px_height, "on_mouse": on_mouse, "on_wheel": on_wheel, "on_key": on_key, "focusable": focusable, "track_move": track_move, "focus_ring": focus_ring, "expand": expand}, id, flex, width, height, align))

# Surface de conception (ALEX Studio Designer) : content dans un cadre de fenêtre ; les composants d'id
# « dz:<uid> » se désignent à la souris (on_pick(uid ou null)) ; selected : uid encadré ; on_resize(l, h) ;
# on_delete() sur Suppr.
func design_surface(content, form_width=640, form_height=420, form_title="", selected=null, selected_label="", on_pick=null, on_resize=null, on_delete=null, on_key=null, id=null, flex=1):
    return _n.Node("design_surface", _p({"form_width": form_width, "form_height": form_height, "form_title": form_title, "selected": selected, "selected_label": selected_label, "on_pick": on_pick, "on_resize": on_resize, "on_delete": on_delete, "on_key": on_key}, id, flex, null, null, null), [content])

# ---------------------------------------------------------------- données
# value : 0..1. label : texte affiché à côté (null : le pourcentage).
func progress(value, label=null, id=null, width=null, flex=0, align=null):
    return _n.Node("progress", _p({"value": value, "label": label}, id, flex, width, null, align))

# Liste sélectionnable. on_select(indice) quand la sélection change, on_activate(indice) sur Entrée ou
# double clic. height : lignes visibles (null : 8, et la liste s'agrandit s'il reste de la place).
func list_view(items, selected=0, on_select=null, on_activate=null, height=null, id=null, width=null, flex=0, align=null):
    return _n.Node("list_view", _p({"items": [str(i) for i in items], "selected": selected, "on_select": on_select, "on_activate": on_activate}, id, flex, width, height, align))

# Tableau. columns : list de titres (str) ou de dict {"title", "width" (caractères), "align" : "left" /
# "right" / "center"}. rows : list de list. Tri par clic sur un titre, ou touche s (colonne suivante) / S
# (ordre inverse). on_select(indice) et on_activate(indice) donnent l'indice dans rows (pas dans l'ordre trié).
func table(columns, rows, selected=0, on_select=null, on_activate=null, sortable=true, height=null, id=null, width=null, flex=0, align=null):
    return _n.Node("table", _p({"columns": columns, "rows": rows, "selected": selected, "on_select": on_select, "on_activate": on_activate, "sortable": sortable}, id, flex, width, height, align))

# Arbre. nodes : list de dict {"label", "children" (list, facultatif), "id" (facultatif), "expanded"}.
# → / ← ouvrent et ferment, Entrée active. on_select(nœud) et on_activate(nœud) reçoivent le dict.
func tree(nodes, on_select=null, on_activate=null, height=null, id=null, width=null, flex=0, align=null):
    return _n.Node("tree", _p({"nodes": nodes, "on_select": on_select, "on_activate": on_activate}, id, flex, width, height, align))

# ---------------------------------------------------------------- structure
# gap : espace entre les enfants ; padding : marge intérieure (caractères / lignes).
# align : alignement des enfants en travers ("start", "center", "end", "stretch").
func column(children, gap=null, padding=0, align=null, id=null, flex=0, width=null, height=null):
    return _n.Node("column", _p({"gap": gap, "padding": padding, "cross": align}, id, flex, width, height, null), _list(children))

func row(children, gap=null, padding=0, align=null, id=null, flex=0, width=null, height=null):
    return _n.Node("row", _p({"gap": gap, "padding": padding, "cross": align}, id, flex, width, height, null), _list(children))

# Cadre avec titre facultatif ; content : un composant ou une list (empilée en colonne).
func panel(content, title=null, border=true, padding=null, id=null, flex=0, width=null, height=null, align=null):
    return _n.Node("panel", _p({"title": title, "border": border, "padding": padding}, id, flex, width, height, align), _list(content))

# Zone qui défile verticalement (molette, Pg↑ / Pg↓ ; suit le focus). height : lignes visibles.
func scroll(content, height=null, id=null, flex=0, width=null, align=null):
    return _n.Node("scroll", _p({}, id, flex, width, height, align), _list(content))

# Onglets. pages : list de [titre, composant]. on_change(indice). ← → sur la barre, Ctrl+Pg↑ / Ctrl+Pg↓.
func tabs(pages, selected=null, on_change=null, id=null, flex=0, width=null, height=null, align=null):
    titles := [str(p[0]) for p in pages]
    contents := [p[1] for p in pages]
    return _n.Node("tabs", _p({"titles": titles, "selected": selected, "on_change": on_change}, id, flex, width, height, align), contents)

# Deux zones séparées par une barre déplaçable (souris, ou ← → / ↑ ↓ quand elle a le focus).
# vertical=false : côte à côte ; true : l'une au-dessus de l'autre. ratio : part de la première.
func split(first, second, vertical=false, ratio=0.5, id=null, flex=1, width=null, height=null, align=null):
    return _n.Node("split", _p({"vertical": vertical, "ratio": ratio}, id, flex, width, height, align), [first, second])

# Dialogue modal (affiché au-dessus du reste, qui ne reçoit plus d'événements), où qu'il soit placé dans la
# vue. buttons : list de [libellé, fonction]. on_close() sur Échap. width : caractères.
func dialog(title, content, buttons=null, on_close=null, width=48, id=null):
    if buttons == null:
        buttons = []
    return _n.Node("dialog", _p({"title": title, "buttons": buttons, "on_close": on_close}, id, 0, width, null, null), _list(content))

func alert(title, message, on_close=null, ok="OK"):
    return dialog(title, text(message, wrap=true), [[ok, on_close]], on_close)

func confirm(title, message, on_yes=null, on_no=null, yes="Oui", no="Non"):
    return dialog(title, text(message, wrap=true), [[yes, on_yes], [no, on_no]], on_no)

# Barre de menus : menus = list de menu(titre, éléments). F10 ou un clic l'ouvrent.
func menu_bar(menus, id=null):
    return _n.Node("menu_bar", _p({"menus": menus}, id, 0, null, null, null))

func menu(title, items):
    return {"title": str(title), "items": items}

# Élément de menu. shortcut : "ctrl+o", "f5"... (actif même menu fermé). checked : null ou bool (coche).
func item(label, on_select=null, shortcut=null, enabled=true, checked=null):
    return {"label": str(label), "on_select": on_select, "shortcut": shortcut, "enabled": enabled, "checked": checked, "items": null}

func submenu(label, items, enabled=true):
    return {"label": str(label), "on_select": null, "shortcut": null, "enabled": enabled, "checked": null, "items": items}

func menu_separator():
    return {"label": null, "separator": true, "items": null, "enabled": false}

# ---------------------------------------------------------------- contrôle
# Termine l'application en cours (gui.run / tui.run reviennent).
func quit():
    a := _rt.current()
    if a != null:
        a.stop()

# Donne le focus au composant d'identifiant id (à la prochaine image).
func focus(id):
    a := _rt.current()
    if a != null:
        a.focus_request = id

# Envoie une touche (« ctrl+z », « ctrl+c »...) au composant qui a le focus, après l'événement en cours :
# éléments de menu Édition qui agissent sur l'éditeur ou le champ actif.
func press(key):
    a := _rt.current()
    if a != null:
        a.post_key(key)

# Application en cours (runtime), ou null.
func app():
    return _rt.current()

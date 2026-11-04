# Test de ui.view (composants, mise en page, focus, superpositions, clavier, souris) sur le rendu terminal
# (tui.TestApp : terminal virtuel). Le comportement des composants est commun aux deux rendus.

from core use len, type
from collections use append, contains_key
use string as s
use ui.view as v
use tui
use tui.screen as screen
use tui.terminal as terminal
use tui.surface as surface
use ui.view.runtime as runtime

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

func error_of(f):
    try:
        f()
    catch e:
        return e.type
    return "aucune erreur"

func focus_kind(t):
    f := t.focused()
    if f == null:
        return null
    return f.kind

# ---------------------------------------------------------------- formulaire
form := {"nom": "", "envoye": null, "ok": false, "taille": 1, "pays": 0, "vol": 50, "qte": 3, "clics": 0}

func set_nom(x):
    form["nom"] = x

func envoyer(x):
    form["envoye"] = x

func set_ok(x):
    form["ok"] = x

func set_taille(i):
    form["taille"] = i

func set_pays(i):
    form["pays"] = i

func set_vol(x):
    form["vol"] = x

func set_qte(x):
    form["qte"] = x

func clic():
    form["clics"] += 1

func vue_form():
    return v.column([
        v.text("Formulaire", style="title"),
        v.field(form["nom"], set_nom, envoyer, placeholder="Nom", id="nom"),
        v.checkbox("Accepter", form["ok"], set_ok),
        v.radio(["S", "M", "L"], form["taille"], set_taille, horizontal=true),
        v.select(["France", "Belgique", "Suisse", "Canada"], form["pays"], set_pays, id="pays"),
        v.slider(form["vol"], 0, 100, 10, set_vol),
        v.spinbox(form["qte"], 0, 10, 1, set_qte),
        v.row([v.button("Valider", clic, primary=true), v.button("Inactif", clic, enabled=false)]),
    ], padding=1)

func test_form():
    t := tui.TestApp(vue_form, 50, 16)
    check(t.contains("Formulaire") and t.contains("[ Valider ]"), "rendu initial")
    check_eq(focus_kind(t), "input", "focus initial : premier composant focalisable")
    t.type("Ada L")
    check_eq(form["nom"], "Ada L", "saisie dans le champ")
    t.press("backspace")
    t.press("left")
    t.press("left")
    t.type("x")
    check_eq(form["nom"], "Adxa ", "édition : retour arrière, flèches, insertion")
    t.press("ctrl+u")
    check_eq(form["nom"], "a ", "Ctrl+U efface jusqu'au début")
    t.press("end")
    t.paste("collé\nici")
    check_eq(form["nom"], "a collé ici", "collage (fin de ligne remplacée)")
    t.press("enter")
    check_eq(form["envoye"], "a collé ici", "Entrée : on_submit")
    check(t.cursor() != null, "curseur du terminal placé dans le champ")
    t.press("tab")
    check_eq(focus_kind(t), "checkbox", "Tab : composant suivant")
    t.press("space")
    check_eq(form["ok"], true, "Espace coche")
    t.press("tab")
    t.press("right")
    check_eq(form["taille"], 2, "radio : → choisit l'option suivante")
    t.press("tab")
    t.press("down")
    check_eq(form["pays"], 1, "select fermé : ↓ change le choix")
    t.press("enter")
    check(t.contains("Suisse") and t.contains("Canada"), "select : Entrée ouvre la liste")
    check_eq(focus_kind(t), "popup_list", "liste ouverte : elle a le focus")
    t.press("down")
    t.press("down")
    t.press("enter")
    check_eq(form["pays"], 3, "liste : ↓ ↓ Entrée choisit Canada")
    check_eq(focus_kind(t), "select", "liste fermée : focus rendu au select")
    t.press("enter")
    t.press("escape")
    check_eq(form["pays"], 3, "Échap ferme la liste sans changer")
    t.press("tab")
    t.press("right")
    check_eq(form["vol"], 60, "slider : → ajoute un pas")
    t.press("end")
    check_eq(form["vol"], 100, "slider : Fin = maximum")
    t.press("tab")
    t.press("up")
    check_eq(form["qte"], 4, "spinbox : ↑")
    t.type("12")
    t.press("enter")
    check_eq(form["qte"], 10, "spinbox : saisie bornée au maximum")
    t.press("tab")
    t.press("enter")
    check_eq(form["clics"], 1, "bouton : Entrée")
    t.press("tab")
    check_eq(focus_kind(t), "input", "le bouton inactif est sauté, retour au début")
    t.press("shift+tab")
    check_eq(t.focused().get("label"), "Valider", "Maj+Tab : composant précédent")
    p := t.find("[ Valider ]")
    t.click(p[0] + 3, p[1])
    check_eq(form["clics"], 2, "bouton : clic")
    p2 := t.find("[ Inactif ]")
    t.click(p2[0] + 3, p2[1])
    check_eq(form["clics"], 2, "bouton inactif : clic sans effet")
    t.click("Accepter")
    check_eq(form["ok"], false, "case : clic décoche")
    t.click(t.find("( ) S")[0] + 1, t.find("( ) S")[1])
    check_eq(form["taille"], 0, "radio : clic sur une option")
    v.focus("pays")
    t.step()
    check_eq(focus_kind(t), "select", "v.focus(id)")
    t.click(t.find("Canada")[0], t.find("Canada")[1])
    check_eq(focus_kind(t), "popup_list", "select : clic ouvre la liste")
    t.click(t.find("Belgique")[0], t.find("Belgique")[1])
    check_eq(form["pays"], 1, "liste : clic sur un élément")
    t.click(t.find("Belgique")[0], t.find("Belgique")[1])
    t.click(0, 0)
    check(not t.contains("Suisse"), "clic à côté : la liste se ferme")
    check(t.running(), "toujours en marche")
    t.press("ctrl+q")
    check(not t.running(), "Ctrl+Q quitte")

# ---------------------------------------------------------------- listes, tableau, arbre
data := {"item": 0, "act": null, "row": 0, "rowact": null, "noeud": null, "nact": null}

func set_item(i):
    data["item"] = i

func act_item(i):
    data["act"] = i

func set_row(i):
    data["row"] = i

func act_row(i):
    data["rowact"] = i

func sel_noeud(n):
    data["noeud"] = n["label"]

func act_noeud(n):
    data["nact"] = n["label"]

items := ["pomme", "poire", "prune", "abricot", "banane", "cerise", "datte", "figue", "kiwi", "mangue", "melon", "orange"]
rows := [["Ada", 1815, "Londres"], ["Alan", 1912, "Londres"], ["Grace", 1906, "New York"], ["Edsger", 1930, "Rotterdam"]]
nodes := [{"label": "src", "children": [{"label": "main.al"}, {"label": "ui", "children": [{"label": "view.al"}]}]}, {"label": "docs", "children": [{"label": "UI.md"}]}, {"label": "Makefile"}]

func vue_data():
    return v.row([
        v.list_view(items, data["item"], set_item, act_item, height=5, width=12),
        v.table(["Nom", {"title": "Année", "align": "right"}, "Ville"], rows, data["row"], set_row, act_row, height=5),
        v.tree(nodes, sel_noeud, act_noeud, height=6, width=16),
    ], align="start")

func test_data():
    t := tui.TestApp(vue_data, 76, 8)
    check(t.contains("pomme") and t.contains("prune"), "liste affichée")
    check(not t.contains("cerise"), "liste : seules les lignes visibles sont dessinées")
    t.press("down")
    check_eq(data["item"], 1, "liste : ↓")
    t.press("end")
    check_eq(data["item"], 11, "liste : Fin")
    check(t.contains("orange") and not t.contains("pomme"), "liste : défilement pour montrer la sélection")
    t.press("home")
    t.type("b")
    check_eq(data["item"], 4, "liste : saisie rapide (b → banane)")
    t.press("enter")
    check_eq(data["act"], 4, "liste : Entrée active")
    t.wheel("poire", -1)
    t.wheel("abricot", -1)
    check(t.contains("figue"), "liste : molette")
    t.click("figue")
    check_eq(data["item"], 7, "liste : clic")
    t.double_click("kiwi")
    check_eq([data["item"], data["act"]], [8, 8], "liste : double clic active")
    t.press("tab")
    check_eq(focus_kind(t), "table", "Tab vers le tableau")
    t.press("down")
    check_eq(data["row"], 1, "tableau : ↓")
    t.press("s")
    check(s.contains(t.line(0), "Nom") and s.contains(t.line(0), "↑"), "tableau : s trie (indicateur ↑)")
    lines := t.lines()
    ada := -1
    alan := -1
    i := 0
    for l in lines:
        if s.contains(l, "Ada "):
            ada = i
        if s.contains(l, "Alan"):
            alan = i
        i += 1
    check(ada >= 0 and ada < alan, "tableau : tri par nom")
    t.press("s")
    t.press("S")
    first := ""
    for l in t.lines():
        if s.contains(l, "1815") or s.contains(l, "1906") or s.contains(l, "1912") or s.contains(l, "1930"):
            if first == "":
                first = l
    check(s.contains(first, "1930"), "tableau : s puis S → année décroissante")
    t.press("home")
    check_eq(data["row"], 3, "tableau : sélection = indice dans rows (après tri)")
    t.press("enter")
    check_eq(data["rowact"], 3, "tableau : Entrée active la ligne")
    t.click("Ville")
    check(s.contains(t.line(0), "Ville↑") or s.contains(t.line(0), "Ville ↑") or s.contains(t.line(0), "Ville↑"), "tableau : clic sur l'entête trie")
    t.press("tab")
    check_eq(focus_kind(t), "tree", "Tab vers l'arbre")
    check(t.contains("src") and not t.contains("main.al"), "arbre fermé")
    t.press("down")
    check_eq(data["noeud"], "src", "arbre : ↓ sélectionne")
    t.press("right")
    check(t.contains("main.al"), "arbre : → déplie")
    t.press("right")
    check_eq(data["noeud"], "main.al", "arbre : → va au premier enfant")
    t.press("left")
    check_eq(data["noeud"], "src", "arbre : ← va au parent")
    t.press("left")
    check(not t.contains("main.al"), "arbre : ← replie")
    t.click("docs")
    check_eq(data["noeud"], "docs", "arbre : clic")
    t.double_click("Makefile")
    check_eq(data["nact"], "Makefile", "arbre : double clic sur une feuille active")
    p := t.find("▸ docs")
    t.click(p[0], p[1])
    check(t.contains("UI.md"), "arbre : clic sur ▸ déplie")

# ---------------------------------------------------------------- zone de texte, défilement
doc := {"texte": "un\ndeux\ntrois\nquatre\ncinq\nsix\nsept"}

func set_texte(x):
    doc["texte"] = x

func vue_texte():
    champs := [v.field("", null, id="c" + str(i), width=10) for i in 0..12]
    return v.row([v.textarea(doc["texte"], set_texte, height=4, width=20), v.scroll(champs, height=6, width=16)], align="start")

func test_texte():
    t := tui.TestApp(vue_texte, 50, 8)
    check(t.contains("un") and t.contains("quatre") and not t.contains("cinq"), "textarea : 4 lignes visibles")
    t.press("ctrl+end")
    check(t.contains("sept") and not t.contains("deux"), "textarea : Ctrl+Fin défile")
    t.press("enter")
    t.type("huit")
    check_eq(doc["texte"], "un\ndeux\ntrois\nquatre\ncinq\nsix\nsept\nhuit", "textarea : Entrée insère une ligne")
    t.press("up")
    t.press("home")
    t.press("backspace")
    check_eq(doc["texte"], "un\ndeux\ntrois\nquatre\ncinq\nsixsept\nhuit", "textarea : retour arrière joint les lignes")
    t.press("ctrl+home")
    check(t.contains("un"), "textarea : Ctrl+Début")
    t.press("tab")
    check_eq(t.focused().id, "c0", "scroll : premier champ")
    k := 0
    while k < 9:
        t.press("tab")
        k += 1
    check_eq(t.focused().id, "c9", "scroll : Tab vers un champ caché")
    cur := t.cursor()
    check(cur != null and cur[1] < 8, "scroll : le champ focalisé est rendu visible")

# ---------------------------------------------------------------- onglets, split, menus, dialogue
app_state := {"onglet": 0, "dlg": false, "msg": "", "touches": [], "ticks": 0, "coche": false}

func set_onglet(i):
    app_state["onglet"] = i

func msg(m):
    app_state["msg"] = m

func ouvrir():
    app_state["dlg"] = true

func fermer():
    app_state["dlg"] = false

func oui():
    app_state["dlg"] = false
    msg("oui")

func basculer():
    app_state["coche"] = not app_state["coche"]

func vue_struct():
    menus := v.menu_bar([
        v.menu("Fichier", [v.item("Nouveau", () => msg("nouveau"), "ctrl+n"), v.submenu("Récents", [v.item("a.txt", () => msg("a.txt")), v.item("b.txt", () => msg("b.txt"))]), v.menu_separator(), v.item("Désactivé", () => msg("non"), enabled=false), v.item("Dialogue", ouvrir)]),
        v.menu("Vue", [v.item("Coche", basculer, checked=app_state["coche"])]),
    ])
    pages := [["Un", v.field("", null, id="champ1")], ["Deux", v.split(v.text("gauche"), v.text("droite"), ratio=0.5)]]
    out := [menus, v.tabs(pages, app_state["onglet"], set_onglet), v.text("msg=" + app_state["msg"])]
    if app_state["dlg"]:
        append(out, v.confirm("Question", "Continuer ?", oui, fermer))
    return v.column(out)

func on_key(k):
    append(app_state["touches"], k)
    return k == "f5"

func test_struct():
    t := tui.TestApp(vue_struct, 60, 14, "dark", on_key)
    check(t.contains("Fichier") and t.contains("Un") and t.contains("Deux"), "barre de menus et onglets")
    t.press("ctrl+n")
    check_eq(app_state["msg"], "nouveau", "raccourci de menu (menu fermé)")
    t.press("f10")
    check(t.contains("Nouveau") and t.contains("Ctrl+N"), "F10 ouvre le premier menu")
    check_eq(focus_kind(t), "menu_popup", "menu ouvert : il a le focus")
    t.press("down")
    t.press("right")
    check(t.contains("a.txt") and t.contains("b.txt"), "→ ouvre le sous-menu")
    t.press("down")
    t.press("enter")
    check_eq(app_state["msg"], "b.txt", "sous-menu : élément choisi")
    check(not t.contains("Nouveau"), "menus fermés après le choix")
    check_eq(focus_kind(t), "tabs", "focus rendu après fermeture des menus")
    t.press("f10")
    t.press("right")
    check(t.contains("Coche"), "→ passe au menu suivant")
    t.press("enter")
    check_eq(app_state["coche"], true, "élément de menu coché")
    t.press("f10")
    t.press("right")
    check(t.contains("✓"), "coche affichée")
    t.press("escape")
    check(not t.contains("Coche"), "Échap ferme le menu")
    t.click("Fichier")
    check(t.contains("Dialogue"), "clic ouvre le menu")
    t.click("Vue")
    check(t.contains("Coche") and not t.contains("Dialogue"), "clic sur un autre titre change de menu")
    t.click("Vue")
    check(not t.contains("Coche"), "clic sur le même titre ferme")
    t.click("Fichier")
    t.click("Désactivé")
    check_eq(app_state["msg"], "b.txt", "élément désactivé sans effet")
    t.click("Dialogue")
    check(t.contains("Continuer ?") and t.contains("[ Oui ]"), "dialogue affiché")
    check_eq(t.focused().get("label"), "Oui", "dialogue : focus sur le premier bouton")
    t.click("Deux")
    check_eq(app_state["onglet"], 0, "dialogue modal : le reste ne réagit pas")
    t.press("tab")
    check_eq(t.focused().get("label"), "Non", "Tab reste dans le dialogue")
    t.press("tab")
    check_eq(t.focused().get("label"), "Oui", "Tab boucle dans le dialogue")
    t.press("escape")
    check(not app_state["dlg"], "Échap : on_close du dialogue")
    check_eq(focus_kind(t), "tabs", "focus rendu après le dialogue")
    app_state["dlg"] = true
    t.step()
    t.press("enter")
    check_eq([app_state["dlg"], app_state["msg"]], [false, "oui"], "dialogue : Entrée sur Oui")
    t.press("right")
    check_eq(app_state["onglet"], 1, "onglets : →")
    check(t.contains("gauche") and t.contains("droite"), "page 2 : split")
    t.press("ctrl+page_up")
    check_eq(app_state["onglet"], 0, "Ctrl+Pg↑")
    t.press("tab")
    t.type("abc")
    t.press("ctrl+page_down")
    t.press("ctrl+page_up")
    check(t.contains("abc"), "l'état d'un champ non contrôlé survit au changement d'onglet")
    t.press("f5")
    check(app_state["touches"][len(app_state["touches"]) - 1] == "f5", "on_key reçoit les touches non utilisées")
    t.click("Deux")
    check_eq(app_state["onglet"], 1, "onglet : clic")
    p := t.find("gauche")
    bar := -1
    row := t.line(p[1])
    i := 0
    for c in row:
        if c == '│':
            bar = i
        i += 1
    t.drag(bar, p[1], bar + 10, p[1])
    row2 := t.line(p[1])
    k := 0
    bar2 := -1
    for c in row2:
        if c == '│':
            bar2 = k
        k += 1
    check(bar2 > bar + 5, "split : glisser la barre")
    t.resize(40, 10)
    check(t.contains("Fichier") and len(t.lines()) == 10, "redimensionnement")

# ---------------------------------------------------------------- texte, mise en page, erreurs
func test_layout():
    t := tui.TestApp(() => v.column([v.text("Un long texte qui doit revenir à la ligne tout seul", wrap=true), v.row([v.text("g"), v.spacer(), v.text("d")]), v.text("centré", text_align="center"), v.panel([v.text("dedans")], title="Cadre")]), 24, 12)
    ls := t.lines()
    check(len(ls[0]) <= 24 and s.contains(ls[1], "revenir") or s.contains(ls[2], "revenir"), "wrap à la largeur")
    found := false
    for l in ls:
        if s.starts_with(l, "g") and s.ends_with(l, "d") and len(l) == 24:
            found = true
    check(found, "spacer : pousse à droite")
    check(t.contains("╭ Cadre ") or t.contains("─ Cadre "), "panneau : titre dans le cadre")
    check(t.contains("dedans"), "panneau : contenu")
    check_eq(error_of(() => tui.TestApp(() => v.column([v.text("a"), 3.5, null]), 10, 3)), "aucune erreur", "nombres et null comme enfants")
    bad := () => tui.TestApp(() => v.column([{"x": 1}]), 10, 3)
    check(error_of(bad) != "aucune erreur", "enfant invalide : erreur")
    # thème sans couleurs : vidéo inverse pour la sélection
    t2 := tui.TestApp(() => v.list_view(["a", "b"], 0), 10, 4, "dark")
    check(t2.contains("a"), "list_view seule")
    html := t2.html()
    check(s.starts_with(html, "<pre") and s.contains(html, "background:"), "capture HTML")

# ---------------------------------------------------------------- rythme (tick) et valeur de fin
horloge := {"ticks": 0}

func tic(temps):
    horloge["ticks"] += 1
    if horloge["ticks"] == 3:
        v.app().stop("fini")

func test_tick():
    vt := terminal.VirtualTerminal(30, 3)
    app := runtime.App(() => v.text("tic " + str(horloge["ticks"])), surface.Surface(vt, "dark", true), null, tic, 0.02)
    r := app.run()
    check_eq([r, horloge["ticks"]], ["fini", 3], "on_tick toutes les tick secondes, stop(valeur)")
    check(vt.contains("tic 2"), "affichage redessiné après chaque tick")

# ---------------------------------------------------------------- régressions (relecture indépendante)
appels := {"ouvrir": 0, "touches": 0}

func ouvrir_f():
    appels["ouvrir"] += 1

func compter(k):
    appels["touches"] += 1
    return false

func test_regressions():
    # tri d'une colonne avec plusieurs cellules nulles ou absentes, accents
    t := tui.TestApp(() => v.table(["A", "B"], [["a", 1], ["b"], ["c", null], ["Élodie", 0], ["zoé", 2], ["eric", 3]], 0, null), 40, 10)
    t.press("s")
    t.press("s")
    check(t.contains("Élodie"), "tri : cellules nulles sans erreur")
    t.press("s")
    t.press("s")
    order := []
    for l in t.lines():
        w := s.split(s.trim(l), " ")[0]
        if w == "a" or w == "b" or w == "c" or w == "Élodie" or w == "zoé" or w == "eric":
            append(order, w)
    check_eq(order, ["a", "b", "c", "Élodie", "eric", "zoé"], "tri sans casse ni accents (É avec les e)")
    # enfants : booléens ignorés, list aplaties, dict refusé avec un message clair
    t2 := tui.TestApp(() => v.column([false, [v.text("un"), [v.text("deux")]], true and v.text("trois"), null]), 20, 5)
    check(t2.contains("un") and t2.contains("deux") and t2.contains("trois"), "enfants : booléens ignorés, list aplaties")
    msg := ""
    try:
        tui.TestApp(() => v.column([{"x": 1}]), 10, 3)
    catch e:
        msg = e.message
    check(s.contains(msg, "enfant invalide de type 'dict'"), "enfant dict : message clair")
    # manque de place partagé ; hauteur naturelle d'après le contenu
    t3 := tui.TestApp(() => v.column([v.table(["A", "B"], [["x", 1], ["y", 2], ["z", 3]], -1, null), v.list_view(["a", "b", "c", "d", "e"], 0, null, height=5), v.select(["s1", "s2"], 0, null), v.radio(["r1", "r2"], 0, null), v.tree([{"label": "t1"}, {"label": "t2"}, {"label": "t3"}], null), v.text("fin")]), 30, 20)
    check(t3.contains("x") and t3.contains("z") and t3.contains("t3") and t3.contains("fin"), "colonne pleine : tout reste visible")
    # tailles explicites prioritaires sur l'étirement
    t4 := tui.TestApp(() => v.column([v.field("abc", null, width=10, id="f"), v.row([v.list_view(["1", "2", "3", "4", "5"], 0, null, height=2), v.text("haut\nb\nc\nd")])]), 30, 8)
    f := null
    for n in t4.app.placed:
        if n.id == "f":
            f = n
    check_eq(f.w, 12, "field width=10 non étiré (10 + marges)")
    check(t4.contains("2") and not t4.contains("3"), "list_view height=2 dans une ligne")
    # dialogue modal : ni raccourcis, ni F10, ni on_key
    t5 := tui.TestApp(() => v.column([v.menu_bar([v.menu("Fichier", [v.item("Ouvrir", ouvrir_f, shortcut="ctrl+o")])]), v.alert("Modal", "msg", null)]), 40, 10, "dark", compter)
    t5.press("ctrl+o")
    t5.press("f10")
    t5.press("x")
    check_eq([appels["ouvrir"], appels["touches"]], [0, 0], "modal : raccourcis, F10 et on_key bloqués")
    check(not t5.contains("Ouvrir"), "modal : le menu ne s'ouvre pas")
    # petits terminaux : raccourci non superposé au libellé, dialogue découpé dans son cadre
    t6 := tui.TestApp(() => v.column([v.menu_bar([v.menu("F", [v.item("Ouvrir le fichier", null, shortcut="ctrl+shift+o")])])]), 12, 4)
    t6.press("f10")
    check(not t6.contains("rl+"), "menu étroit : raccourci omis plutôt que superposé")
    t7 := tui.TestApp(() => v.confirm("Question", "Continuer ?", null, null), 20, 5)
    check(s.starts_with(t7.line(4), "╰") or s.contains(t7.line(4), "─"), "dialogue trop haut : bordure du bas intacte")
    # slider hors bornes : affiché borné
    t8 := tui.TestApp(() => v.slider(50, 0, 10, 1, null), 30, 2)
    check(t8.contains("10") and not t8.contains("50"), "slider : valeur bornée à l'affichage")

func main():
    test_regressions()
    test_tick()
    test_form()
    test_data()
    test_texte()
    test_struct()
    test_layout()
    print(f"ui.view (terminal) : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_view_tui : échecs")

main()

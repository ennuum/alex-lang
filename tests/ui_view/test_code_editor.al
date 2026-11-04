# Test de l'éditeur de code : ui.view.code_editor (terminal virtuel), ui.view.syntax, et l'application
# outils.editeur_app (Studio : fichiers, onglets, exécution, marqueurs d'erreur).

from core use len, type
from collections use append, pop
use string as s
use file
use os
use ui.view as v
use ui.view.syntax as syntax
use tui
use outils.editeur_app as ed

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

# ---------------------------------------------------------------- coloration
func roles(line, lang):
    return [[s.slice(line, t[0], t[1]), t[2]] for t in syntax.tokens(line, lang) if t[2] != "code_text"]

func couvre(line, lang):
    toks := syntax.tokens(line, lang)
    pos := 0
    for t in toks:
        if t[0] != pos:
            return false
        pos = t[1]
    return pos == len(line)

func test_syntax():
    r := roles("func carre(x):  # carré", "alex")
    check_eq(r[0], ["func", "syn_keyword"], "syntaxe : mot-clé")
    check_eq(r[1], ["carre", "syn_function"], "syntaxe : nom de fonction")
    check_eq(r[len(r) - 1], ["# carré", "syn_comment"], "syntaxe : commentaire")
    r2 := roles("x := print(\"a\\\"b\", 3.5e-2, true, Point)", "alex")
    check_eq(r2[2], ["print", "syn_builtin"], "syntaxe : fonction prédéfinie")
    check_eq(r2[3], ["\"a\\\"b\"", "syn_string"], "syntaxe : chaîne avec échappement")
    check_eq(r2[5], ["3.5e-2", "syn_number"], "syntaxe : nombre à exposant")
    check_eq(r2[7], ["true", "syn_constant"], "syntaxe : constante")
    check_eq(r2[9], ["Point", "syn_type"], "syntaxe : type (majuscule)")
    check_eq(roles("def f(): return None", "python")[0], ["def", "syn_keyword"], "syntaxe : python")
    check_eq(roles("{\"a\": -1}", "json")[0], ["\"a\"", "syn_string"], "syntaxe : json")
    check_eq(syntax.tokens("abc", "text"), [[0, 3, "code_text"]], "syntaxe : texte brut")
    check(couvre("class A extends B:  'x' # é", "alex") and couvre("s := \"non fermée", "alex"), "syntaxe : segments couvrants")
    check_eq([syntax.language_of("a.AL"), syntax.language_of("b.py"), syntax.language_of("c.json"), syntax.language_of("d.txt")], ["alex", "python", "json", "text"], "language_of")

# ---------------------------------------------------------------- composant
src := {"t": "", "pos": null, "changes": 0}

func ch(t):
    src["t"] = t
    src["changes"] += 1

func cur(l, c):
    src["pos"] = [l, c]

marks := []

func editeur(text, w=60, h=10, ro=false):
    src["t"] = text
    src["changes"] = 0
    return tui.TestApp(() => v.code_editor(src["t"], ch, "alex", cur, marks, readonly=ro), w, h)

func test_edition():
    t := editeur("func carre(x):\n    return x * x\n\nprint(carre(4))")
    check(t.contains("1") and t.contains("func carre(x):"), "éditeur : numéros et texte")
    check_eq(t.focused().kind, "code_editor", "éditeur : focus")
    # auto-indentation après « : »
    t.press("end")
    t.press("enter")
    t.type("y := 1")
    check_eq(s.split(src["t"], "\n")[1], "    y := 1", "entrée : indentation ajoutée après ':'")
    check_eq(src["pos"], [2, 11], "on_cursor (ligne, colonne)")
    # frappe rapide : aucun caractère perdu entre deux images
    t.type("23456789")
    check_eq(s.split(src["t"], "\n")[1], "    y := 123456789", "frappe : aucun caractère perdu")
    # annuler / rétablir
    t.press("ctrl+z")
    check(not s.contains(src["t"], "y := 1"), "Ctrl+Z annule la saisie groupée")
    t.press("ctrl+y")
    check(s.contains(src["t"], "y := 123456789"), "Ctrl+Y rétablit")
    t.press("ctrl+z")
    t.press("ctrl+z")
    check_eq(src["t"], "func carre(x):\n    return x * x\n\nprint(carre(4))", "annulations jusqu'au texte initial")
    # retour arrière jusqu'au taquet d'indentation
    t2 := editeur("if a:\n        b")
    t2.press("down")
    t2.press("home")
    t2.press("backspace")
    check_eq(src["t"], "if a:\n    b", "retour arrière : un taquet")
    # le programme change la valeur : elle fait foi
    src["t"] = "nouveau"
    t2.step()
    check(t2.contains("nouveau") and not t2.contains("if a:"), "valeur contrôlée par le programme")

func test_selection():
    t := editeur("alpha beta\ngamma\ndelta")
    t.press("shift+end")
    t.press("ctrl+c")
    t.press("ctrl+end")
    t.press("ctrl+v")
    check_eq(src["t"], "alpha beta\ngamma\ndeltaalpha beta", "sélection Maj+Fin, copier, coller")
    t.press("ctrl+a")
    t.press("ctrl+x")
    check_eq(src["t"], "", "Ctrl+A puis Ctrl+X vident")
    t.press("ctrl+v")
    check_eq(src["t"], "alpha beta\ngamma\ndeltaalpha beta", "collage du texte coupé")
    t3 := editeur("un\ndeux")
    t3.press("ctrl+c")
    t3.press("down")
    t3.press("end")
    t3.paste("\nX")
    check_eq(src["t"], "un\ndeux\nX", "collage du terminal")
    t3.press("ctrl+home")
    t3.press("ctrl+x")
    check_eq(src["t"], "deux\nX", "Ctrl+X sans sélection coupe la ligne")
    # double clic : sélection d'un mot
    t4 := editeur("valeur := autre_nom + 1")
    t4.double_click("autre_nom")
    t4.type("z")
    check_eq(src["t"], "valeur := z + 1", "double clic : mot remplacé")

func test_lignes():
    t := editeur("a\nb\nc")
    t.press("shift+down")
    t.press("shift+down")
    t.press("shift+end")
    t.press("tab")
    check_eq(src["t"], "    a\n    b\n    c", "Tab indente le bloc")
    t.press("shift+tab")
    check_eq(src["t"], "a\nb\nc", "Maj+Tab désindente")
    t.press("ctrl+/")
    check_eq(src["t"], "# a\n# b\n# c", "Ctrl+/ commente")
    t.press("ctrl+_")
    check_eq(src["t"], "a\nb\nc", "Ctrl+/ décommente")
    t2 := editeur("a\nb\nc")
    t2.press("ctrl+d")
    check_eq(src["t"], "a\na\nb\nc", "Ctrl+D duplique")
    t2.press("alt+down")
    t2.press("alt+down")
    check_eq(src["t"], "a\nb\nc\na", "Alt+↓ déplace la ligne")
    t2.press("ctrl+shift+k")
    check_eq(src["t"], "a\nb\nc", "Ctrl+Maj+K supprime la ligne")

func test_recherche():
    lignes := []
    for i in 0..60:
        append(lignes, "ligne " + str(i + 1) + (" cible" if i % 20 == 5 else ""))
    t := editeur(s.join("\n", lignes), 60, 10)
    t.press("ctrl+f")
    t.type("cible")
    check(t.contains("3 résultat"), "recherche : nombre de résultats")
    t.press("escape")
    t.press("end")
    check_eq(src["pos"][0], 6, "recherche : curseur sur le 1er résultat")
    t.press("f3")
    check_eq(src["pos"][0], 26, "F3 : résultat suivant")
    t.press("shift+f3")
    check_eq(src["pos"][0], 6, "Maj+F3 : précédent")
    t.press("ctrl+g")
    t.type("45")
    t.press("enter")
    check_eq(src["pos"], [45, 1], "Ctrl+G : aller à la ligne")
    check(t.contains("ligne 45"), "aller à la ligne : défilement")
    t.press("ctrl+home")
    check(t.contains("ligne 1 ") or t.contains("ligne 1\n") or s.contains(t.screen(), "ligne 1"), "Ctrl+Début")

func test_marqueurs():
    append(marks, {"line": 2, "message": "NameError : y", "kind": "error"})
    t := editeur("x := 1\nprint(y)\n", 60, 6)
    check(t.contains("NameError : y"), "marqueur : message en fin de ligne")
    y := t.find("print(y)")[1]
    bg := t.style_at(50, y)
    bg0 := t.style_at(50, 0)
    check(bg != bg0, "marqueur : fond de la ligne")
    marks[0] = {"line": 1, "message": "attention", "kind": "warning"}
    t.step()
    check(t.contains("attention") and not t.contains("NameError"), "marqueurs mis à jour")
    pop(marks)

func test_lecture_seule():
    t := editeur("fixe", 40, 4, true)
    t.type("abc")
    t.press("backspace")
    check_eq(src["changes"], 0, "lecture seule : aucune modification")
    # Échap puis Tab sort de l'éditeur
    t2 := tui.TestApp(() => v.column([v.code_editor("a", null), v.button("OK", null)]), 40, 8)
    t2.press("tab")
    check_eq(t2.focused().kind, "code_editor", "Tab dans l'éditeur : indentation, pas de sortie")
    t2.press("escape")
    t2.press("tab")
    check_eq(t2.focused().kind, "button", "Échap puis Tab : sortie de l'éditeur")


# ---------------------------------------------------------------- chaînes et commentaires sur plusieurs lignes
func editeur_lang(text, lang, w=60, h=10):
    src["t"] = text
    src["changes"] = 0
    return tui.TestApp(() => v.code_editor(src["t"], ch, lang, cur, marks), w, h)

func style_de(t, texte):
    p := t.find(texte)
    st := t.style_at(p[0], p[1])
    k := s.find(st, ";48;")
    return st if k < 0 else s.slice(st, 0, k)

func test_multiligne():
    py := ["x = \"\"\"abc", "def f(): # pas du code", "fin\"\"\" + \"z\"", "y = 1"]
    r1 := syntax.tokens_from(py[0], "python", "")
    check_eq(r1[1], "tq_d", "multiligne : triple guillemet ouvert en fin de ligne")
    check_eq(r1[0][len(r1[0]) - 1], [4, 10, "syn_string"], "multiligne : la chaîne commence au triple guillemet")
    r2 := syntax.tokens_from(py[1], "python", r1[1])
    check_eq(r2, [[[0, len(py[1]), "syn_string"]], "tq_d"], "multiligne : ligne du milieu entièrement chaîne")
    r3 := syntax.tokens_from(py[2], "python", r2[1])
    check_eq(r3[1], "", "multiligne : état refermé")
    check_eq(r3[0][0], [0, 6, "syn_string"], "multiligne : fin de la chaîne")
    check(couvre(py[2], "python"), "multiligne : couverture complète")
    check_eq(syntax.states(py, "python"), ["", "tq_d", "tq_d", "", ""], "multiligne : états de chaque ligne")
    # simples apostrophes, préfixe f, chaîne sur une seule ligne
    check_eq(syntax.tokens_from("a = '''x", "python", "")[1], "tq_s", "multiligne : apostrophes triples")
    check_eq(syntax.tokens_from("a = f\"\"\"x", "python", "")[1], "tq_d", "multiligne : préfixe f")
    check_eq(syntax.tokens_from("a = \"\"\"x\"\"\"", "python", "")[1], "", "multiligne : refermé sur la ligne")
    check_eq(syntax.tokens_from("a = \"\"\"x\\\"\"\"", "python", "")[1], "tq_d", "multiligne : guillemet échappé avant la fin")
    check_eq(syntax.tokens_from("a = \"\"", "python", "")[1], "", "multiligne : chaîne vide")
    # commentaires /* */ d'Alex
    c1 := syntax.tokens_from("a := 1 /* début", "alex", "")
    check_eq(c1[1], "block", "commentaire /* ouvert")
    c2 := syntax.tokens_from(" fin */ b := 2", "alex", c1[1])
    check_eq(c2[0][0], [0, 7, "syn_comment"], "commentaire /* refermé")
    check_eq(c2[1], "", "commentaire : état refermé")
    check_eq(syntax.tokens_from("# /* pas un bloc", "alex", "")[1], "", "/* dans un commentaire #")
    check_eq(syntax.tokens_from("x := \"/*\"", "alex", "")[1], "", "/* dans une chaîne")
    check_eq(syntax.tokens_from("a /* b */ c", "alex", "")[1], "", "commentaire sur une ligne")
    check_eq(syntax.tokens_from("\"\"\"", "json", "")[1], "", "JSON : pas de multiligne")
    # dans l'éditeur : la ligne du milieu a la couleur d'une chaîne, pas celle d'un mot-clé
    t := editeur_lang(s.join("\n", py), "python")
    chaine := style_de(t, "abc")
    check_eq(style_de(t, "def f()"), chaine, "éditeur : ligne du milieu colorée comme une chaîne")
    check(style_de(t, "y = 1") != chaine, "éditeur : le code après la chaîne n'est plus coloré en chaîne")
    # taper l'ouverture colore les lignes suivantes ; annuler les rétablit
    t2 := editeur_lang("x = 1\ndef f(): pass\ny = 2", "python")
    avant := style_de(t2, "def f()")
    t2.press("end")
    t2.type(" + \"\"\"")
    ouvre := t2.find("\"\"\"")
    check_eq(style_de(t2, "def f()"), t2.style_at(ouvre[0], ouvre[1]) if false else style_de(t2, "\"\"\""), "éditeur : triple guillemet tapé colore les lignes suivantes")
    t2.press("ctrl+z")
    check_eq(style_de(t2, "def f()"), avant, "éditeur : annuler rétablit la coloration")
    # nouvelle valeur du programme
    src["t"] = "def f(): pass"
    t.step()
    check(style_de(t, "def f()") != chaine, "éditeur : nouveau texte, nouvelle coloration")
    # commentaire /* */ dans un éditeur Alex
    t3 := editeur("a := 1 /* début\nfunc g(): # milieu\nfin */ b := 2")
    cm := style_de(t3, "début")
    check_eq(style_de(t3, "func g()"), cm, "éditeur : commentaire /* */ sur plusieurs lignes")

# ---------------------------------------------------------------- pliage
const BLOCS := "func a():\n    x := 1\n    y := 2\n\nfunc b():\n    return 3\nprint(a())"

func test_pliage():
    t := editeur(BLOCS, 60, 12)
    check(t.contains("▾"), "pliage : triangle sur les lignes qui ouvrent un bloc")
    t.press("ctrl+home")
    t.press("f4")
    check(not t.contains("x := 1") and not t.contains("y := 2") and t.contains("func b():"), "F4 : bloc replié")
    check(t.contains("▸") and t.contains("2 lignes"), "pliage : triangle et nombre de lignes masquées")
    t.press("down")
    check_eq(src["pos"][0], 4, "pliage : ↓ saute le bloc replié")
    t.press("up")
    check_eq(src["pos"][0], 1, "pliage : ↑ revient sur l'en-tête")
    t.press("end")
    t.press("right")
    check_eq(src["pos"][0], 4, "pliage : → en fin d'en-tête passe après le bloc")
    t.press("ctrl+home")
    t.press("f4")
    check(t.contains("x := 1") and t.contains("y := 2"), "F4 : bloc déplié")
    # Entrée sur un en-tête replié le déplie
    t.press("f4")
    t.press("end")
    t.press("enter")
    check(t.contains("x := 1"), "Entrée sur un en-tête replié le déplie")
    t.press("ctrl+z")
    check_eq(src["t"], BLOCS, "pliage : texte intact après annulation")
    t.press("ctrl+home")
    t.press("shift+f4")
    check(not t.contains("return 3") and not t.contains("x := 1") and t.contains("print(a())"), "Maj+F4 : tout plier")
    t.press("ctrl+f4")
    check(t.contains("return 3") and t.contains("x := 1"), "Ctrl+F4 : tout déplier")
    # un bloc replié suit les lignes insérées au-dessus
    t.press("ctrl+home")
    t.press("down", 4)
    t.press("f4")
    check(not t.contains("return 3"), "pliage du second bloc")
    t.press("ctrl+home")
    t.press("enter")
    check(not t.contains("return 3") and t.contains("func b():"), "pliage : le bloc suit une insertion au-dessus")
    check_eq(s.split(src["t"], "\n")[5], "func b():", "pliage : texte décalé d'une ligne")
    # clic sur le triangle
    t2 := editeur(BLOCS, 60, 12)
    y := t2.find("func a():")[1]
    t2.click(0, y)
    check(not t2.contains("x := 1") and t2.contains("▸"), "clic sur le triangle : replie")
    y2 := t2.find("func a():")[1]
    t2.click(0, y2)
    check(t2.contains("x := 1"), "clic sur le triangle : déplie")
    # un long fichier tout replié : la fin reste atteignable
    lignes := []
    for i in 0..30:
        append(lignes, "func f" + str(i) + "():")
        append(lignes, "    a")
        append(lignes, "    b")
    t3 := editeur(s.join("\n", lignes), 60, 10)
    t3.press("shift+f4")
    t3.press("ctrl+end")
    check_eq(src["pos"][0], 88, "pliage : Ctrl+Fin retombe sur le dernier en-tête")
    check(t3.contains("func f29():") and t3.contains("func f28():"), "pliage : la fin du fichier est visible")
    t3.press("up")
    check_eq(src["pos"][0], 85, "pliage : ↑ d'un bloc à l'autre")
    t3.press("ctrl+home")
    check_eq(src["pos"][0], 1, "pliage : Ctrl+Début")
    check(t3.contains("func f0():") and t3.contains("func f1():"), "pliage : le début du fichier est visible")
    # recherche dans un bloc replié : il se déplie
    t4 := editeur(BLOCS, 60, 12)
    t4.press("ctrl+home")
    t4.press("f4")
    t4.press("ctrl+f")
    t4.type("y := 2")
    check(t4.contains("y := 2"), "recherche : déplie le bloc qui contient le résultat")
    # lecture seule : on peut plier
    t5 := editeur(BLOCS, 60, 12, true)
    t5.press("f4")
    check(not t5.contains("x := 1"), "pliage en lecture seule")

# ---------------------------------------------------------------- complétion
func test_completion():
    t := editeur("valeur := 1\nvaleur_max := 2\n", 60, 12)
    t.press("ctrl+end")
    t.type("val")
    check(t.contains("values"), "complétion : liste ouverte en tapant")
    t.press("enter")
    check_eq(src["t"], "valeur := 1\nvaleur_max := 2\nvaleur", "complétion : Entrée valide la première proposition")
    t.press("ctrl+z")
    check_eq(src["t"], "valeur := 1\nvaleur_max := 2\nval", "complétion : annulable en un coup")
    # mot-clé
    t2 := editeur("", 60, 8)
    t2.type("ret")
    t2.press("tab")
    check_eq(src["t"], "return", "complétion : mot-clé du langage")
    # Échap ferme la liste : Entrée fait alors une nouvelle ligne
    t3 := editeur("", 60, 8)
    t3.type("retu")
    t3.press("escape")
    t3.press("enter")
    check_eq(src["t"], "retu\n", "complétion : Échap ferme, Entrée va à la ligne")
    # un seul caractère : pas de liste
    t4 := editeur("", 60, 8)
    t4.type("v")
    t4.press("enter")
    check_eq(src["t"], "v\n", "complétion : pas de liste pour un seul caractère")
    # pas dans un commentaire
    t5 := editeur("valeur := 1\n", 60, 8)
    t5.press("ctrl+end")
    t5.type("# val")
    t5.press("enter")
    check_eq(src["t"], "valeur := 1\n# val\n", "complétion : rien dans un commentaire")
    # F8space : liste sans préfixe
    t6 := editeur("ab_cd := 1\n", 60, 12)
    t6.press("ctrl+end")
    t6.press("ctrl+space")
    t6.press("enter")
    check_eq(src["t"], "ab_cd := 1\nab_cd", "F8space : propositions sans préfixe")
    # après un point : seulement les identifiants du texte
    t7 := editeur("self.largeur := 1\nx := self.", 60, 12)
    t7.press("ctrl+end")
    t7.press("ctrl+space")
    t7.press("enter")
    check_eq(src["t"], "self.largeur := 1\nx := self.largeur", "complétion après un point")
    # désactivée
    src["t"] = ""
    src["changes"] = 0
    t8 := tui.TestApp(() => v.code_editor(src["t"], ch, "alex", cur, marks, completion=false), 60, 8)
    t8.type("retu")
    t8.press("enter")
    check_eq(src["t"], "retu\n", "completion=false : pas de liste")
    # lecture seule : jamais de liste
    t9 := editeur("valeur", 60, 8, true)
    t9.press("ctrl+end")
    t9.press("ctrl+space")
    check(not t9.contains("values"), "lecture seule : pas de complétion")
    # la liste se réduit quand on tape, revient en effaçant
    t11 := editeur("alpha := 1\nalpine := 2\n", 60, 12)
    t11.press("ctrl+end")
    t11.type("alp")
    t11.type("i")
    t11.press("enter")
    check_eq(src["t"], "alpha := 1\nalpine := 2\nalpine", "complétion : la liste se réduit quand on tape")

# ---------------------------------------------------------------- application
func attendre(st, t):
    k := 0
    while st.proc != null and k < 500:
        st.tick()
        os.sleep(0.02)
        k += 1
    t.step()

# Clique le bouton de dialogue libellé label (sur la ligne du bouton Annuler).
func bouton(t, label):
    y := t.find("Annuler")[1]
    t.click(s.find(t.line(y), label) + 1, y)

func test_studio():
    dir := os.tmp_dir() + "/alex_editeur_test_" + str(os.pid())
    os.mkdir_all(dir)
    p := dir + "/main.al"
    file.write(p, "func carre(x):\n    return x * x\n\nprint(carre(7))\n")
    file.write(dir + "/notes.txt", "notes")
    st := ed.Studio(dir, [p])
    t := tui.TestApp(st.vue, 100, 30, "dark", st._on_key)
    check(t.contains("main.al") and t.contains("notes.txt"), "studio : arbre des fichiers")
    check_eq(t.focused().kind, "code_editor", "studio : focus dans l'éditeur")
    t.press("ctrl+end")
    t.type("print(\"fin\")")
    check(t.contains("main.al ●") or t.contains("● main.al") or t.contains("*"), "studio : marque de modification")
    t.press("ctrl+s")
    check(s.contains(file.read(p), "print(\"fin\")"), "Ctrl+S enregistre")
    t.press("f5")
    attendre(st, t)
    check(s.contains(st.output, "49") and s.contains(st.output, "fin"), "F5 : sortie du programme")
    check(s.contains(st.output, "code de sortie 0"), "F5 : code de sortie")
    check(t.contains("49"), "panneau de sortie affiché")
    # erreur : marqueur sur la bonne ligne
    t.press("ctrl+home")
    t.press("end")
    t.press("enter")
    t.type("y := inconnu + 1")
    t.press("f5")
    attendre(st, t)
    b := st.buffer()
    check(len(b.markers) > 0, "erreur : marqueur posé")
    if len(b.markers) > 0:
        check_eq(b.markers[0]["line"], 2, "erreur : ligne du marqueur")
    check(s.contains(st.status, "erreur"), "erreur : barre d'état")
    # parse_errors
    m := ed.parse_errors("Erreur dans " + p + ":12:3: SyntaxError: x\n", p)
    check(len(m) == 1 and m[0]["line"] == 12, "parse_errors : fichier:ligne:col")
    # nouvel onglet, fermeture avec confirmation
    t.press("ctrl+n")
    check_eq(len(st.buffers), 2, "Ctrl+N : nouvel onglet")
    t.type("brouillon")
    t.press("ctrl+w")
    check(st.dialog != null, "fermeture d'un onglet modifié : confirmation")
    bouton(t, "Fermer")
    check(st.dialog == null and len(st.buffers) == 1, "dialogue : Fermer quand même")
    check_eq(t.focused().kind, "code_editor", "focus rendu à l'éditeur")
    # ouvrir depuis l'arbre
    check(st.open(dir + "/notes.txt"), "ouvrir un fichier")
    check_eq(st.buffer().language, "text", "langage d'après l'extension")
    check_eq(len(st.buffers), 2, "ouvert dans un nouvel onglet")
    st.open(p)
    check_eq(st.current, 0, "fichier déjà ouvert : onglet existant")
    # quitter avec des modifications : confirmation
    t.type("x")
    t.press("ctrl+q")
    check(st.dialog == "quit" and t.running(), "quitter : confirmation si non enregistré")
    t.click("Annuler")
    check(st.dialog == null and t.running(), "quitter : annuler")
    t.press("ctrl+q")
    bouton(t, "Quitter")
    check(not t.running(), "quitter quand même")
    os.remove(dir + "/notes.txt")
    os.remove(p)
    os.rmdir(dir, true)


# ---------------------------------------------------------------- entrée standard du programme lancé par F5
func attendre_sortie(st, t, texte):
    k := 0
    while not s.contains(st.output, texte) and st.proc != null and k < 500:
        st.tick()
        os.sleep(0.02)
        k += 1
    t.step()

func test_entree_standard():
    dir := os.tmp_dir() + "/alex_editeur_stdin_" + str(os.pid())
    os.mkdir_all(dir)
    p := dir + "/echo.al"
    file.write(p, "nom := input(\"Votre nom ?\")\nprint(\"Bonjour \" + nom)\nn := input()\nprint(\"deux [\" + n + \"]\")\n")
    st := ed.Studio(dir, [p])
    t := tui.TestApp(st.vue, 100, 30, "dark", st._on_key)
    t.press("f5")
    attendre_sortie(st, t, "Votre nom ?")
    check(st.proc != null, "stdin : le programme attend la saisie")
    check(s.contains(st.output, "Votre nom ?"), "stdin : l'invite est affichée avant la saisie (flush)")
    check(t.contains("Entrée"), "stdin : ligne d'entrée affichée pendant l'exécution")
    check_eq(t.focused().kind, "input", "stdin : le focus est dans la ligne d'entrée")
    t.type("Alex")
    t.press("enter")
    attendre_sortie(st, t, "Bonjour Alex")
    check(s.contains(st.output, "Bonjour Alex"), "stdin : input() reçoit la ligne saisie")
    check(st.proc != null, "stdin : le programme attend la seconde saisie")
    t.press("f8")
    attendre(st, t)
    check(s.contains(st.output, "deux []"), "stdin : F8 donne une fin de fichier")
    check(s.contains(st.output, "code de sortie 0"), "stdin : le programme se termine")
    check(not t.contains("Entrée ▸"), "stdin : la ligne d'entrée disparaît à la fin")
    check_eq(t.focused().kind, "code_editor", "stdin : le focus revient à l'éditeur")
    # arrêt d'un programme qui attend une saisie
    st.buffer().text = "x := input(\"?\")\nprint(x)\n"
    t.step()
    t.press("f5")
    attendre_sortie(st, t, "?")
    check(st.proc != null, "stdin : programme en attente")
    st.stop_run()
    check(st.proc == null and s.contains(st.output, "[arrêté]"), "stdin : arrêt pendant l'attente")
    # vérification (F7) : pas de ligne d'entrée
    t.press("f7")
    attendre(st, t)
    check(not t.contains("Entrée ▸"), "F7 : pas de ligne d'entrée")
    os.remove(p)
    os.rmdir(dir, true)

func main():
    test_syntax()
    test_edition()
    test_selection()
    test_lignes()
    test_recherche()
    test_marqueurs()
    test_lecture_seule()
    test_multiligne()
    test_pliage()
    test_completion()
    test_studio()
    test_entree_standard()
    print(f"éditeur de code : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_code_editor : échecs")

main()

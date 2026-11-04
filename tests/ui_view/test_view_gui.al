# Test de ui.view dans une fenêtre (gui.TestApp, backend headless) : conversion des vrais événements de
# fenêtre (codes de touche, texte, modificateurs, souris, molette), dessin sur le canvas et captures.
#   ALEX_UI_BACKEND=headless ./alex run tests/ui_view/test_view_gui.al [dossier des captures]

from core use len, type
from collections use append
use string as s
use os
use ui.view as v
use gui
use examples.ui_view.demo_view as demo
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

func focus_kind(t):
    f := t.focused()
    if f == null:
        return null
    return f.kind

shots := os.tmp_dir() + "/alex_ui_view_gui"
args := os.args()
if len(args) > 0:
    shots = args[0]
if not os.exists(shots):
    os.mkdir_all(shots)

func shot(t, name):
    check(t.screenshot(shots + "/" + name + ".png"), "capture " + name)

st := {"nom": "", "ok": false, "clics": 0, "vol": 50, "item": 0, "msg": "", "ratio": null}

func set_nom(x):
    st["nom"] = x

func set_ok(x):
    st["ok"] = x

func clic():
    st["clics"] += 1

func set_vol(x):
    st["vol"] = x

func set_item(i):
    st["item"] = i

func msg(m):
    st["msg"] = m

func vue():
    return v.column([
        v.menu_bar([v.menu("Fichier", [v.item("Nouveau", () => msg("nouveau"), "ctrl+n"), v.item("Quitter", v.quit, "ctrl+q")])]),
        v.column([
            v.field(st["nom"], set_nom, placeholder="Nom"),
            v.checkbox("Accepter", st["ok"], set_ok),
            v.slider(st["vol"], 0, 100, 1, set_vol),
            v.list_view(["l" + str(i) for i in 0..40], st["item"], set_item, height=5),
            v.row([v.button("OK", clic, primary=true), v.text("msg=" + st["msg"])]),
        ], padding=2),
    ])

func test_events():
    t := gui.TestApp(vue, 480, 420)
    check(gui.backend() == "headless", "backend headless")
    check(t.contains("Fichier") and t.contains("Nom") and t.contains("OK"), "textes dessinés")
    check_eq(focus_kind(t), "input", "focus initial")
    t.type("Élodie")
    check_eq(st["nom"], "Élodie", "texte accentué (événements texte)")
    t.press("backspace")
    t.press("home")
    t.type("<")
    check_eq(st["nom"], "<Élodi", "touches Retour arrière et Début (codes de touche)")
    t.press("tab")
    t.press("space")
    check_eq(st["ok"], true, "Tab puis Espace")
    t.press("shift+tab")
    check_eq(focus_kind(t), "input", "Maj+Tab")
    t.press("ctrl+n")
    check_eq(st["msg"], "nouveau", "Ctrl+N (modificateur Ctrl)")
    t.click("Accepter")
    check_eq(st["ok"], false, "clic sur la case")
    n := t.find("msg=")
    sl := null
    for p in t.app.placed:
        if p.kind == "slider":
            sl = p
    check(sl != null, "slider placé")
    t.click(sl.x + sl.w // 8, sl.y + sl.h // 2)
    check(st["vol"] < 30, "slider : clic au début de la piste")
    t.drag(sl.x + 10, sl.y + sl.h // 2, sl.x + sl.w - 30, sl.y + sl.h // 2)
    check(st["vol"] > 80, "slider : glisser")
    t.click("l2")
    check_eq(st["item"], 2, "liste : clic")
    t.wheel("l3", -3)
    check(t.contains("l9") and not t.contains("l0"), "liste : molette")
    t.press("down")
    check_eq(st["item"], 3, "liste : ↓ (code de touche)")
    t.click("OK")
    check_eq(st["clics"], 1, "bouton : clic")
    t.move("OK")
    check(t.app.hover != null and s.contains(t.app.hover, "button"), "survol suivi")
    shot(t, "evenements")
    # événements au format Windows (texte séparé de la touche) : conversion
    sf := t.surface
    check_eq(sf._convert({"type": "key_down", "key": 65, "mods": 0, "data": "", "window": 1, "widget": 65}), null, "Windows : lettre sans Ctrl → attendre le texte")
    check_eq(sf._convert({"type": "text_input", "data": "é", "window": 1, "widget": 0})["key"], "é", "Windows : text_input")
    check_eq(sf._convert({"type": "key_down", "key": 83, "mods": 6, "data": "", "window": 1, "widget": 83})["key"], "ctrl+shift+s", "Windows : Ctrl+Maj+S")
    check_eq(sf._convert({"type": "key_down", "key": 40, "mods": 4, "data": "", "window": 1, "widget": 40})["key"], "shift+down", "Windows : Maj+↓")
    t.click("Fichier")
    check(t.contains("Quitter") and t.contains("Ctrl+Q"), "menu ouvert au clic")
    shot(t, "menu")
    t.click("Quitter")
    check(not t.running(), "menu Quitter : v.quit()")
    t.close()

func test_demo():
    t := gui.TestApp(demo.vue, 900, 640)
    shot(t, "demo_saisie")
    t.click("Données")
    check(t.contains("Ada Lovelace") and t.contains("lisez-moi.txt"), "onglet Données")
    t.click("Année")
    t.click("Année")
    shot(t, "demo_donnees")
    t.click("Arbre")
    t.click("src")
    t.press("right")
    t.press("right")
    check(t.contains("runtime.al") or t.contains("ui"), "arbre déplié")
    shot(t, "demo_arbre")
    t.click("Fichier")
    t.press("down")
    t.press("down")
    t.press("right")
    shot(t, "demo_menus")
    t.press("escape")
    t.press("escape")
    t.click("Enregistrer")
    check(t.contains("Annuler"), "dialogue")
    shot(t, "demo_dialogue")
    t.press("escape")
    check(not t.contains("Annuler"), "dialogue fermé par Échap")
    t.close()

func test_light():
    t := gui.TestApp(demo.vue, 900, 640, "light")
    shot(t, "demo_clair")
    t.resize(640, 480)
    check_eq(t.surface.size(), [640, 480], "resize : nouvelle taille")
    check(t.contains("Enregistrer"), "resize : la vue suit")
    shot(t, "demo_clair_petit")
    t.close()

code := {"t": "func carre(x):\n    return x * x\n\nprint(carre(4))\nprint(y)", "pos": null}

func set_code(x):
    code["t"] = x

func set_pos(l, c):
    code["pos"] = [l, c]

func test_code():
    sf := gui.TestApp(() => v.text("x"), 200, 100).surface
    check_eq(sf.text_width("iiii", "mono"), sf.text_width("WWWW", "mono"), "police mono : chasse fixe")
    check(sf.text_width("iiii") < sf.text_width("WWWW"), "police normale : proportionnelle")
    marks := [{"line": 5, "message": "NameError : y", "kind": "error"}]
    t := gui.TestApp(() => v.code_editor(code["t"], set_code, "alex", set_pos, marks), 640, 300)
    check_eq(focus_kind(t), "code_editor", "éditeur (fenêtre) : focus")
    check(t.contains("NameError : y"), "éditeur (fenêtre) : marqueur affiché")
    t.press("end")
    t.press("enter")
    t.type("y := 2")
    check_eq(s.split(code["t"], "\n")[1], "    y := 2", "éditeur (fenêtre) : saisie et indentation")
    t.press("shift+home")
    t.press("ctrl+x")
    check_eq(s.split(code["t"], "\n")[1], "    ", "éditeur (fenêtre) : Maj+Début (début intelligent) et couper")
    t.press("ctrl+z", 3)
    check(not s.contains(code["t"], "y := 2") and s.split(code["t"], "\n")[1] == "    return x * x", "éditeur (fenêtre) : annuler")
    t.click("return")
    check_eq(code["pos"][0], 2, "éditeur (fenêtre) : clic place le curseur")
    t.wheel("return", -3)
    shot(t, "editeur_composant")
    t.close()
    st := ed.Studio("examples/ui_view", ["examples/ui_view/compteur.al"])
    g := gui.TestApp(st.vue, 1100, 720)
    check_eq(focus_kind(g), "code_editor", "studio (fenêtre) : focus")
    st.buffer().markers = [{"line": 3, "message": "exemple de marqueur", "kind": "error"}]
    st.output = "$ alex run compteur.al\nexemple de sortie\n[code de sortie 0, 5 ms]\n"
    st.show_output = true
    g.step()
    check(g.contains("exemple de marqueur") and g.contains("exemple de sortie"), "studio (fenêtre) : marqueur et sortie")
    g.press("ctrl+f")
    g.type("etat")
    check(g.contains("résultat"), "studio (fenêtre) : recherche")
    shot(g, "editeur_studio")
    g.close()

test_events()
test_demo()
test_light()
test_code()
print(f"ui.view (fenêtre) : {stats[0]} vérifications OK, {stats[1]} échec(s) — captures dans {shots}")
for n in notes:
    print("  ÉCHEC " + n)
if stats[1] > 0:
    raise("TestError", "test_view_gui : échecs")

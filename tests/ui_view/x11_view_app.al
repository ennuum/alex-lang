# Application ui.view pilotée sous Xvfb par tests/ui_view/run_x11_view.sh (vrais événements X11).
#   « probe » : positions des éléments (backend headless, même mise en page) ; sinon : gui.run.
from core use len
use os
use ui.view as v
use gui

etat := {"nom": "", "ok": false, "n": 0, "item": 0}
items := ["un", "deux", "trois", "quatre", "cinq", "six", "sept", "huit", "neuf", "dix"]

func set_nom(t):
    etat["nom"] = t

func set_ok(b):
    etat["ok"] = b

func ajouter():
    etat["n"] += 1

func set_item(i):
    etat["item"] = i

func vue():
    return v.column([
        v.menu_bar([v.menu("Fichier", [v.item("Ajouter", ajouter, "ctrl+a"), v.menu_separator(), v.item("Quitter", v.quit)])]),
        v.column([
            v.field(etat["nom"], set_nom, placeholder="nom", width=20),
            v.checkbox("Cocher", etat["ok"], set_ok),
            v.row([v.button("Ajouter", ajouter, primary=true), v.text("total " + str(etat["n"]))]),
            v.list_view(items, etat["item"], set_item, height=4, width=16),
        ], padding=2),
    ])

args := os.args()
if len(args) > 0 and args[0] == "probe":
    t := gui.TestApp(vue, 640, 420)
    for label in ["nom", "Cocher", "Ajouter", "trois", "Fichier"]:
        p := t.where(label)
        print("POS " + label + " " + str(p[0]) + " " + str(p[1]))
else:
    gui.run(vue, "ALEX VIEW X11", 640, 420)
    print("FINAL nom=" + etat["nom"] + " ok=" + str(etat["ok"]) + " n=" + str(etat["n"]) + " item=" + items[etat["item"]])

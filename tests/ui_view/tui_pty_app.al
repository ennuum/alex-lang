# Application pilotée dans un vrai pseudo-terminal par tests/ui_view/tui_pty.py.
from collections use append
use ui.view as v
use tui

etat := {"n": 0, "nom": "", "fruit": 0, "menu": ""}
fruits := ["pomme", "poire", "prune", "kiwi"]

func plus():
    etat["n"] += 1

func set_nom(t):
    etat["nom"] = t

func set_fruit(i):
    etat["fruit"] = i

func vue():
    return v.column([
        v.menu_bar([v.menu("Menu", [v.item("Marquer", () => v.app().stop("marque"))])]),
        v.text("Compteur " + str(etat["n"]), style="title"),
        v.row([v.button("Plus", plus, primary=true), v.field(etat["nom"], set_nom, placeholder="nom", width=12)]),
        v.list_view(fruits, etat["fruit"], set_fruit, height=4, width=14),
    ], padding=1)

r := tui.run(vue, "Test pty")
print("ETAT n=" + str(etat["n"]) + " nom=" + etat["nom"] + " fruit=" + fruits[etat["fruit"]] + " fin=" + str(r))

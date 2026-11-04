# Le plus petit exemple ui.view : la même vue dans une fenêtre ou dans le terminal.
#   ./alex run examples/ui_view/compteur.al        (terminal)
#   ./alex run examples/ui_view/compteur.al gui    (fenêtre)

from core use len
use os
use ui.view as v
use gui
use tui

etat := {"n": 0, "nom": ""}

func plus():
    etat["n"] += 1

func moins():
    etat["n"] -= 1

func set_nom(t):
    etat["nom"] = t

func vue():
    salut := "Bonjour " + etat["nom"] + " !" if etat["nom"] != "" else "Bonjour !"
    return v.column([
        v.text("Compteur", style="title"),
        v.text(salut, style="muted"),
        v.row([v.button("−", moins), v.text(str(etat["n"]), width=6, text_align="center"), v.button("+", plus, primary=true)]),
        v.field(etat["nom"], set_nom, placeholder="Votre nom"),
        v.spacer(),
        v.row([v.spacer(), v.button("Quitter", v.quit)]),
    ], padding=2)

args := os.args()
if len(args) > 0 and args[0] == "gui":
    gui.run(vue, "Compteur", 420, 300)
else:
    tui.run(vue, "Compteur")

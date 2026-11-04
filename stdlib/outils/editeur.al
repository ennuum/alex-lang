# ALEX STANDARD LIBRARY — outils.editeur : l'éditeur de code d'Alex (commande `alex edit`).
#
#   alex edit [fichier.al ...]            dans le terminal
#   alex edit --gui [fichier.al ...]      dans une fenêtre
#   options : --theme dark|light|terminal, --dir dossier (dossier de l'arbre des fichiers, défaut « . »)

from core use len
from collections use append
use os
use tui
use gui
use outils.editeur_app as app

args := os.args()
fenetre := false
theme := null
root := "."
fichiers := []
i := 0
while i < len(args):
    a := args[i]
    if a == "--gui":
        fenetre = true
    elif a == "--theme" and i + 1 < len(args):
        theme = args[i + 1]
        i += 1
    elif a == "--dir" and i + 1 < len(args):
        root = args[i + 1]
        i += 1
    elif a == "-h" or a == "--help":
        print("usage : alex edit [--gui] [--theme dark|light|terminal] [--dir dossier] [fichier ...]")
        os.exit(0)
    else:
        append(fichiers, a)
    i += 1

studio := app.Studio(root, fichiers)
if fenetre:
    gui.run(studio.vue, "Éditeur Alex", 1100, 720, theme if theme != null else "dark", studio._on_key, studio.tick, 0.1)
else:
    tui.run(studio.vue, "Éditeur Alex", theme if theme != null else "dark", studio._on_key, studio.tick, 0.1)

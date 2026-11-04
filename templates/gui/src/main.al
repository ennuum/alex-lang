# {{Nom}} — point d'entrée.
#   alexc run                     fenêtre (Windows, X11)
#   alexc run -- --terminal       même interface dans le terminal
#   alexc test                    tests (dossier tests/)
# Les modules se trouvent depuis src/ (alex.toml : sources = ["src"]) : `use vues.principale` -> src/vues/principale.al.
from core use len
use os
use gui
use tui
use app.config as config
use app.application as application
use vues.principale as principale

func principal():
    args := os.args()
    application.demarrer(config.fichier_donnees())
    if len(args) > 0 and (args[0] == "--terminal" or args[0] == "tui"):
        tui.run(principale.racine, config.NOM)
    else:
        gui.run(principale.racine, config.NOM, config.LARGEUR, config.HAUTEUR)
    application.arreter()

principal()

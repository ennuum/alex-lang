# Persistance de {{Nom}} : la liste de tâches en JSON. Écriture atomique (fichier temporaire puis
# remplacement) ; un fichier illisible est mis de côté (.bak) au lieu d'être écrasé. Testé dans tests/test_stockage.al.
use os
use io
use json
use modeles.taches as taches

func charger(chemin):
    if chemin == null or not os.isfile(chemin):
        return taches.Liste()
    try:
        return taches.depuis_donnees(json.parse(io.read_file(chemin)))
    catch e:
        try:
            os.copy(chemin, chemin + ".bak")
        catch e2:
            return taches.Liste()
        return taches.Liste()

func enregistrer(liste, chemin):
    os.mkdir_all(os.dirname(chemin))
    tmp := chemin + ".tmp"
    io.write_file(tmp, json.pretty(liste.vers_donnees()) + "\n")
    if os.exists(chemin):
        os.remove(chemin)
    os.move(tmp, chemin)

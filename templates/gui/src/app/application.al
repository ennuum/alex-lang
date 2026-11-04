# État et actions de {{Nom}} (contrôleur) : les vues lisent `etat` et appellent ces fonctions ; chaque
# modification des tâches est enregistrée. Testé sans fenêtre dans tests/test_application.al.
use modeles.taches as taches
use services.stockage as stockage

etat := {"liste": taches.Liste(), "saisie": "", "filtre": "toutes", "fichier": null, "message": ""}

# Charge les tâches enregistrées (fichier : chemin du JSON, ou null pour ne rien enregistrer).
func demarrer(fichier):
    etat["fichier"] = fichier
    etat["liste"] = stockage.charger(fichier)
    etat["saisie"] = ""
    etat["filtre"] = "toutes"
    etat["message"] = ""

func arreter():
    _enregistrer()

func _enregistrer():
    if etat["fichier"] == null:
        return null
    try:
        stockage.enregistrer(etat["liste"], etat["fichier"])
    catch e:
        etat["message"] = "Enregistrement impossible : " + e.message

func saisir(texte):
    etat["saisie"] = texte

func ajouter():
    if etat["liste"].ajouter(etat["saisie"]):
        etat["saisie"] = ""
        etat["message"] = ""
        _enregistrer()
    else:
        etat["message"] = "Le titre de la tâche est vide."

func basculer(i):
    etat["liste"].basculer(i)
    _enregistrer()

func supprimer(i):
    etat["liste"].supprimer(i)
    _enregistrer()

func vider_faites():
    n := etat["liste"].vider_faites()
    etat["message"] = str(n) + " tâche(s) terminée(s) retirée(s)."
    _enregistrer()

func filtrer(nom):
    etat["filtre"] = nom

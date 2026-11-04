# Vue principale de {{Nom}} : assemble les composants à partir de l'état ; ui.view la redessine après chaque action.
from core use len
use ui.view as v
use app.config as config
use app.application as application
use vues.composants as composants

func racine():
    etat := application.etat
    liste := etat["liste"]
    lignes := []
    for i in liste.visibles(etat["filtre"]):
        lignes = lignes + [composants.ligne_tache(i, liste.elements[i])]
    if len(lignes) == 0:
        lignes = [v.text("Aucune tâche ici — ajoutez-en une ci-dessus.", style="muted")]
    return v.column([
        composants.en_tete(config.NOM, liste.restantes(), len(liste.elements)),
        composants.barre_saisie(etat["saisie"]),
        composants.barre_filtres(etat["filtre"]),
        v.scroll(v.column(lignes), flex=1),
        v.row([
            v.text(etat["message"], style="muted"),
            v.spacer(),
            v.button("Retirer les tâches faites", application.vider_faites, id="vider"),
            v.button("Quitter", v.quit, id="quitter"),
        ]),
    ], padding=2)

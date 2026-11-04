# Composants de l'interface de {{Nom}} : fonctions pures de l'état, qui renvoient des éléments ui.view.
from core use len
use ui.view as v
use app.application as application

func en_tete(titre, restantes, total):
    return v.column([
        v.text(titre, style="title"),
        v.text(str(restantes) + " tâche(s) à faire sur " + str(total), style="muted"),
    ], gap=0)

func barre_saisie(saisie):
    return v.row([
        v.field(saisie, application.saisir, on_submit=(x) => application.ajouter(), placeholder="Nouvelle tâche…", flex=1, id="saisie"),
        v.button("Ajouter", application.ajouter, primary=true, id="ajouter"),
    ])

func barre_filtres(actif):
    libelles := [["toutes", "Toutes"], ["a_faire", "À faire"], ["faites", "Faites"]]
    boutons := []
    for f in libelles:
        boutons = boutons + [v.button(f[1], _filtre(f[0]), primary=f[0] == actif, id="filtre_" + f[0])]
    return v.row(boutons)

func _filtre(nom):
    return () => application.filtrer(nom)

func ligne_tache(i, t):
    return v.row([
        v.checkbox(t["titre"], t["faite"], (x) => application.basculer(i), id="tache_" + str(i)),
        v.spacer(),
        v.button("Supprimer", () => application.supprimer(i), id="supprimer_" + str(i)),
    ])

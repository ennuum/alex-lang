# Démonstration de ui.view : la vue (état + fonction vue), affichée par demo.al dans le terminal ou une
# fenêtre, et utilisée par les tests (tests/ui_view).

from core use len
from collections use append
use os
use ui.view as v

etat := {"nom": "", "notes": "Première ligne\nDeuxième ligne", "abonne": true, "taille": 1, "pays": 0, "volume": 40, "quantite": 3, "fichier": 0, "ligne": 0, "onglet": 0, "dialogue": false, "message": "Prêt.", "sombre": true}

fichiers := ["lisez-moi.txt", "main.al", "notes.md", "photo.png", "rapport.pdf", "données.csv", "script.sh", "image.svg", "config.toml", "journal.log"]
lignes := [["Ada Lovelace", 1815, "Londres"], ["Alan Turing", 1912, "Londres"], ["Grace Hopper", 1906, "New York"], ["Edsger Dijkstra", 1930, "Rotterdam"], ["Barbara Liskov", 1939, "Los Angeles"], ["Donald Knuth", 1938, "Milwaukee"], ["Margaret Hamilton", 1936, "Paoli"], ["Ken Thompson", 1943, "La Nouvelle-Orléans"]]
arbre := [{"label": "src", "expanded": true, "children": [{"label": "main.al"}, {"label": "ui", "children": [{"label": "view.al"}, {"label": "runtime.al"}]}]}, {"label": "docs", "children": [{"label": "UI_VIEW.md"}]}, {"label": "Makefile"}]

func dire(m):
    etat["message"] = m

func setter(cle):
    func set(valeur):
        etat[cle] = valeur
    return set

func ouvrir():
    etat["dialogue"] = true

func fermer():
    etat["dialogue"] = false

func valider():
    etat["dialogue"] = false
    dire("Enregistré : " + etat["nom"])

func page_saisie():
    return v.column([
        v.row([v.text("Nom", width=10), v.field(etat["nom"], setter("nom"), placeholder="Votre nom", flex=1)]),
        v.row([v.text("Pays", width=10), v.select(["France", "Belgique", "Suisse", "Canada", "Sénégal", "Côte d'Ivoire"], etat["pays"], setter("pays"))]),
        v.row([v.text("Taille", width=10), v.radio(["S", "M", "L", "XL"], etat["taille"], setter("taille"), horizontal=true)]),
        v.row([v.text("Quantité", width=10), v.spinbox(etat["quantite"], 0, 99, 1, setter("quantite"))]),
        v.row([v.text("Volume", width=10), v.slider(etat["volume"], 0, 100, 5, setter("volume"), flex=1)]),
        v.checkbox("S'abonner à la lettre", etat["abonne"], setter("abonne")),
        v.text("Notes"),
        v.textarea(etat["notes"], setter("notes"), height=4),
        v.progress(etat["volume"] / 100),
    ])

func page_donnees():
    return v.split(
        v.panel(v.list_view(fichiers, etat["fichier"], setter("fichier"), dire, flex=1), title="Fichiers"),
        v.panel([v.table(["Nom", {"title": "Année", "align": "right"}, "Ville"], lignes, etat["ligne"], setter("ligne"), flex=1)], title="Personnes"),
        ratio=0.35)

func page_arbre():
    return v.panel(v.tree(arbre, (n) => dire("Choisi : " + n["label"])), title="Projet")

func vue():
    menus := v.menu_bar([
        v.menu("Fichier", [v.item("Nouveau", () => dire("Nouveau"), "ctrl+n"), v.item("Ouvrir…", ouvrir, "ctrl+o"), v.submenu("Récents", [v.item("rapport.pdf", () => dire("rapport.pdf")), v.item("notes.md", () => dire("notes.md"))]), v.menu_separator(), v.item("Quitter", v.quit, "ctrl+q")]),
        v.menu("Affichage", [v.item("Thème sombre", () => dire("thème"), checked=etat["sombre"]), v.item("Plein écran", null, enabled=false)]),
        v.menu("Aide", [v.item("À propos", ouvrir, "f1")]),
    ])
    corps := v.tabs([["Saisie", page_saisie()], ["Données", page_donnees()], ["Arbre", page_arbre()]], etat["onglet"], setter("onglet"))
    pied := v.row([v.text(etat["message"], style="muted", flex=1), v.button("Enregistrer", ouvrir, primary=true)], align="center")
    enfants := [menus, v.column([corps, pied], padding=1, flex=1)]
    if etat["dialogue"]:
        append(enfants, v.dialog("Enregistrer", [v.text("Enregistrer la fiche de " + (etat["nom"] if etat["nom"] != "" else "(sans nom)") + " ?", wrap=true)], [["Enregistrer", valider], ["Annuler", fermer]], fermer, width=44))
    return v.column(enfants, gap=0)


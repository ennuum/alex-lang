# Routes de {{nom}} : fonctions pures (méthode, chemin, paramètres) -> [statut, corps, "json" | "text"], et leur
# traduction en réponse HTTP (traiter). Les deux se testent sans réseau.
from collections use contains_key
use network.http as http

compteur := {"visites": 0}

func repondre(methode, chemin, params):
    compteur["visites"] += 1
    if methode == "GET" and chemin == "/":
        return [200, "{{Nom}} fonctionne.\n", "text"]
    if methode == "GET" and chemin == "/api/bonjour":
        nom := "monde"
        if contains_key(params, "nom"):
            nom = params["nom"]
        return [200, {"message": "Bonjour, " + nom + " !"}, "json"]
    if methode == "GET" and chemin == "/api/stats":
        return [200, {"visites": compteur["visites"]}, "json"]
    return [404, "introuvable : " + chemin + "\n", "text"]

# Réponse HTTP (network.http.Response) d'une requête : JSON ou texte, avec le statut de repondre.
func traiter(methode, chemin, params):
    r := repondre(methode, chemin, params)
    if r[2] == "json":
        return http.json_response(r[1], r[0])
    return http.text(r[1], r[0])

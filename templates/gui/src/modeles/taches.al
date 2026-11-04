# Modèle de {{Nom}} : la liste de tâches, sans interface ni fichier (testé dans tests/test_taches.al).
from core use len, type
from collections use append, contains_key
use string

const FILTRES := ["toutes", "a_faire", "faites"]

class Liste:
    func init():
        self.elements = []

    # Ajoute une tâche ; refuse un titre vide. Renvoie true si ajoutée.
    func ajouter(titre):
        t := string.trim(titre)
        if t == "":
            return false
        append(self.elements, {"titre": t, "faite": false})
        return true

    func basculer(i):
        if i >= 0 and i < len(self.elements):
            self.elements[i]["faite"] = not self.elements[i]["faite"]

    func supprimer(i):
        garde := []
        k := 0
        for t in self.elements:
            if k != i:
                append(garde, t)
            k += 1
        self.elements = garde

    # Retire les tâches terminées ; renvoie leur nombre.
    func vider_faites():
        garde := []
        for t in self.elements:
            if not t["faite"]:
                append(garde, t)
        n := len(self.elements) - len(garde)
        self.elements = garde
        return n

    # Nombre de tâches non faites.
    func restantes():
        n := 0
        for t in self.elements:
            if not t["faite"]:
                n += 1
        return n

    # Indices des tâches visibles pour un filtre : "toutes", "a_faire" ou "faites".
    func visibles(filtre):
        out := []
        i := 0
        for t in self.elements:
            if filtre == "toutes" or (filtre == "faites") == t["faite"]:
                append(out, i)
            i += 1
        return out

    # Données sérialisables (liste de dicts), pour le stockage.
    func vers_donnees():
        out := []
        for t in self.elements:
            append(out, {"titre": t["titre"], "faite": t["faite"]})
        return out

# Liste reconstruite depuis des données lues (entrées invalides ignorées).
func depuis_donnees(donnees):
    l := Liste()
    if type(donnees) != "list":
        return l
    for e in donnees:
        if type(e) == "dict" and contains_key(e, "titre") and type(e["titre"]) == "str" and string.trim(e["titre"]) != "":
            append(l.elements, {"titre": string.trim(e["titre"]), "faite": contains_key(e, "faite") and e["faite"] == true})
    return l

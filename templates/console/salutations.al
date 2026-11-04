# Fonctions de {{nom}} : séparées du point d'entrée pour être testables.
from core use len

# Message d'accueil pour `nom`.
func bonjour(nom):
    return "Bonjour, " + nom + " !"

# Somme, minimum et maximum d'une liste de nombres non vide.
func resume(valeurs):
    total := 0
    mini := valeurs[0]
    maxi := valeurs[0]
    for v in valeurs:
        total = total + v
        if v < mini:
            mini = v
        if v > maxi:
            maxi = v
    return {"total": total, "min": mini, "max": maxi, "n": len(valeurs)}

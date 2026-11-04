# {{nom}} — bibliothèque ALEX.
#
#   use {{nom}}
#   print({{nom}}.slug("Bonjour le Monde !"))     # bonjour-le-monde
#   print({{nom}}.mots("un deux  trois"))          # 3
#
# La documentation de référence se génère avec `alexc doc {{nom}}.al` (ou --html dossier).
from core use len
from collections use append
use string

# Version de la bibliothèque.
const VERSION := "0.1.0"

# Identifiant d'URL : minuscules, lettres et chiffres, mots séparés par « - ».
func slug(texte):
    out := []
    tiret := false
    for c in string.lower(texte):
        ok := (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9')
        if ok:
            if tiret and len(out) > 0:
                append(out, "-")
            append(out, str(c))
            tiret = false
        else:
            tiret = true
    return string.join("", out)

# Nombre de mots (séparés par des espaces).
func mots(texte):
    n := 0
    dans_mot := false
    for c in texte:
        if c == ' ' or c == '\t' or c == '\n':
            dans_mot = false
        elif not dans_mot:
            dans_mot = true
            n += 1
    return n

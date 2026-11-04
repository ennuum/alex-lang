# Commandes de {{nom}} (testées dans tests/).
from core use len
use io

# Lignes, mots et caractères d'un texte.
func statistiques(texte):
    lignes := 0
    mots := 0
    car := 0
    dans_mot := false
    for c in texte:
        car += 1
        if c == '\n':
            lignes += 1
        if c == ' ' or c == '\n' or c == '\t':
            dans_mot = false
        elif not dans_mot:
            dans_mot = true
            mots += 1
    return [lignes, mots, car]

# Statistiques d'un fichier texte (fins de ligne \r\n et \r ramenées à \n : mêmes comptes sous Windows et Linux).
func compter(fichier):
    return statistiques(io.read_text(fichier)[0])

func executer(args):
    if args["commande"] == "saluer":
        print("Bonjour, " + args["nom"] + " !")
    elif args["commande"] == "compter":
        for f in args["fichiers"]:
            st := compter(f)
            ligne := str(st[0]) + "\t" + str(st[1]) + "\t" + str(st[2]) + "\t" + f
            print(ligne)

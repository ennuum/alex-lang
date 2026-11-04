# Démonstration (et test) : FAT16 avec sous-répertoires et noms longs VFAT.
# - lit une arborescence préparée sous Linux par mtools (noms longs avec espaces, apostrophe, accents ;
#   répertoire de 40 fichiers sur deux grappes) ;
# - écrit sa propre arborescence (noms longs, caractère hors du plan de base en UTF-16, noms courts ~N,
#   répertoire agrandi au-delà d'une grappe), vérifiée ensuite par l'hôte (demo_fat_after.sh : fsck.fat, mtools) ;
# - un processus utilisateur crée, parcourt et supprime des répertoires par les appels système Linux.
use hw
use bloc
use fat
use processus
from core use len
from string use strip

func show(path: str, sizes: bool = true):
    for e in fat.list(path):
        if e.is_dir:
            print(f"  {e.name}/")
        elif sizes:
            print(f"  {e.name} ({e.size} o)")
        else:
            print(f"  {e.name}")

disk := bloc.init() > 0
print("pilote :", bloc.name(), disk)
fat.mount()
print("--- racine")
show("", false) # tailles des exécutables : propres à chaque version du compilateur
print("--- Documents")
show("Documents")
print("--- lectures (casse ignorée, chemins relatifs avec . et ..)")
print(strip(fat.read("documents/lisez-moi d'abord.txt")))
print(strip(fat.read("Documents/./Archive/../Rapports annuels/Résumé 2026.txt")))
archive := fat.list("Documents/Archive")
print("Archive :", len(archive), "fichiers, dernier :", archive[len(archive) - 1].name)
print(strip(fat.read("Documents/Archive/fichier numéro 40.txt")))
d := fat.find("Documents")
if d != null:
    print("nom court de Documents :", strip(d.short))

print("--- écritures du noyau")
fat.mkdir("Projets")
fat.mkdir("Projets/Alex OS")
fat.write("Projets/Alex OS/Journal de bord.txt", "E7 : sous-répertoires et noms longs.\n")
fat.write("Projets/README.TXT", "nom 8.3 en majuscules : pas de nom long\n")
fat.write("Projets/Clé 🔑 musicale 𝄞.txt", "caractères hors du plan de base : paires UTF-16\n")
fat.write("Projets/Rapport final version 1.txt", "v1\n")
fat.write("Projets/Rapport final version 2.txt", "v2\n")
fat.mkdir("Projets/Beaucoup")
i := 0
while i < 30:
    fat.write(f"Projets/Beaucoup/note numéro {i} du journal.txt", f"{i}\n")
    i += 1
print("Beaucoup :", len(fat.list("Projets/Beaucoup")), "fichiers")
fat.write("Projets/Alex OS/Journal de bord.txt", "E7 : sous-répertoires et noms longs (réécrit).\n")
fat.mount() # relu depuis le disque
show("Projets")
print(strip(fat.read("PROJETS/alex os/journal de bord.txt")))
print(strip(fat.read("Projets/Clé 🔑 musicale 𝄞.txt")))

print("--- erreurs")
func read_projets():
    fat.read("Projets")
for bad in [() => fat.mkdir("Projets"), () => fat.rmdir("Projets"), () => fat.remove("Projets/Alex OS"),
            () => fat.write("Absent/x.txt", ""), () => fat.write("Projets/a:b.txt", ""), read_projets]:
    try:
        bad()
    catch e:
        print(e)
fat.mkdir("Projets/Vide")
fat.rmdir("Projets/Vide")
fat.remove("Projets/Rapport final version 1.txt")
i = 0
while i < 30:
    fat.remove(f"Projets/Beaucoup/note numéro {i} du journal.txt")
    i += 1
fat.rmdir("Projets/Beaucoup")
print("après suppressions :", len(fat.list("Projets")), "entrées dans Projets")

print("--- processus")
func out(s: str):
    hw.console_write(s)
func no_input() -> str:
    return ""
print("code :", processus.run("FICHIERS.ELF", [], out, no_input))
show("Mes documents")
hw.exit(0)

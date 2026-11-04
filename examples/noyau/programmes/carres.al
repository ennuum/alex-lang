# Programme utilisateur interactif : lit des nombres au clavier (input) jusqu'à une ligne vide.
from core use to_int
total := 0
while true:
    ligne := input("nombre ?")
    if ligne == "":
        break
    n := to_int(ligne)
    total += n * n
    print(f"{n}² = {n * n}")
print(f"somme des carrés : {total}")

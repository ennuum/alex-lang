# Erreur levée dans une fonction d'un module : la trace donne le fichier de chaque appel.
use natmod.shapes

func run(n: int) -> int:
    return shapes.divide(n, n - 3)

print(run(5))
print(run(3))

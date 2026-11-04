# Sans OS : input() lit une ligne sur le port série (COM1).
from core use to_int
print("nom ?")
n := input()
a := to_int(input("âge ?"))
print(f"bonjour {n}, {a + 1} ans l'an prochain")

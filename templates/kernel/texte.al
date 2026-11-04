# alex: native
# Fonctions pures utilisées par le noyau (compilées en natif) et testées dans la VM.
from string use ord

# Code d'un caractère pour l'écran texte et le port série (ASCII ; « ? » au-delà).
func code(c: char) -> int:
    n := ord(c)
    if n > 126:
        return 63
    return n

# Bandeau centré sur 80 colonnes : « ===  titre  === ».
func titre(s: str) -> str:
    bord := "=== "
    return bord + s + " ==="

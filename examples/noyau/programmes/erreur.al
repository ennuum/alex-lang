# Programme utilisateur en erreur : la trace et le code de sortie 1 reviennent au noyau.
func division(a: int, b: int) -> int:
    return a // b
print("avant l'erreur")
print(division(10, 0))

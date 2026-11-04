# Erreur d'exécution rattrapée puis relancée : la trace d'origine (site de l'erreur) est conservée.
func f(n: int) -> int:
    return 10 // n
try:
    print(f(0))
catch e:
    print("pris", e.type)
    raise(e)

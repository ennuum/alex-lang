# Module de test (ok_modules.al) : initialisé une seule fois, avant ses utilisateurs.
ticks := 0
print("init counter")

func tick():
    ticks += 1

func total() -> int:
    return ticks

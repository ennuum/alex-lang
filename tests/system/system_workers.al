# Fonctions exécutées dans des fils par tests/system/test_system.al.
use system.signal as signal

# Un fil ne peut pas intercepter de signal : renvoie le type de l'erreur.
func try_on():
    try:
        signal.on("USR1", (n) => null)
    catch e:
        return e.type
    return "aucune erreur"

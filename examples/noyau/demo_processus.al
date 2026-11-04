# Démonstration (et test) : exécutables Linux produits par `alexc build --native` lancés en anneau 3 depuis le
# disque FAT (appels système du noyau Alex, pages à la demande, fichiers, erreurs avec trace).
use hw
use disque
use fat
use processus
print("disque :", disque.init() > 0)
fat.mount()
func out(s: str):
    hw.console_write(s)
func line() -> str:
    return "7"
print("code :", processus.run("BONJOUR.ELF", ["a", "b"], out, line))
print("code :", processus.run("ERREUR.ELF", [], out, line))
inputs: list[str] := ["5", "6", ""]
pos := 0
func scripted() -> str:
    s := inputs[pos]
    pos += 1
    return s
print("code :", processus.run("CARRES.ELF", [], out, scripted))
# Exécutions répétées : les pages rendues sont réutilisées (pas de fuite de mémoire physique).
i := 0
while i < 5:
    processus.run("BONJOUR.ELF", [], out, line)
    i += 1
print("pages libres réutilisées :", processus.free_frames != 0)
try:
    processus.run("HELLO.TXT", [], out, line)
catch e:
    print(e)
hw.exit(0)

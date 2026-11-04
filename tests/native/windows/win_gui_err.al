# Application --gui : une exception non rattrapée dans un rappel (clic) termine le programme ; sans console,
# la trace est montrée dans une boîte de message.
use wingui
func profond(n: int) -> int:
    if n == 0:
        raise("Panne", "dans le gestionnaire du clic")
    return profond(n - 1) + 1
f := wingui.window("Erreur", 200, 100)
wingui.button(f, "Boum", 10, 10, 100, 30, () => print(profond(3)))
wingui.run()

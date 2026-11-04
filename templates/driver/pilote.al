# alex: native
# {{nom}} — pilote d'un capteur de température à ports d'entrée-sortie :
#   base + 0 : commande (écriture) : 1 = mesurer, 2 = remettre à zéro
#   base + 1 : état (lecture)      : bit 0 = mesure prête
#   base + 2 : donnée (lecture 16 bits) : température en dixièmes de degré, décalée de +500 (0 = −50,0 °C)
# Compilé dans un noyau (alexc build --native --freestanding) ou exécuté dans la VM sur la machine simulée de hw.
use hw

const CMD_MESURER := 1
const CMD_RAZ := 2

class Capteur:
    base: int := 0
    mesures: int := 0

    func init(base: int):
        self.base = base
        self.mesures = 0

    func remise_a_zero():
        hw.outb(self.base, CMD_RAZ)

    # Lance une mesure et attend le résultat (en dixièmes de degré Celsius).
    func lire_dixiemes() -> int:
        hw.outb(self.base, CMD_MESURER)
        essais := 0
        while (hw.inb(self.base + 1) & 1) == 0:
            essais += 1
            if essais > 100000:
                raise("DriverError", "capteur muet")
        self.mesures += 1
        return hw.inw(self.base + 2) - 500

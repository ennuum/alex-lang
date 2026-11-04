# Modèle SIMULÉ du capteur pour la machine simulée de hw (tests dans la VM, sans matériel) :
# io_read / io_write reçoivent le port, la taille (1, 2, 4) et la valeur.
class CapteurSimule:
    func init(base, dixiemes):
        self.base = base
        self.valeur = dixiemes
        self.pret = false
        self.commandes = 0

    func io_write(port, taille, valeur):
        if port == self.base:
            self.commandes += 1
            if valeur == 1:
                self.pret = true
            elif valeur == 2:
                self.pret = false

    func io_read(port, taille):
        if port == self.base + 1:
            if self.pret:
                return 1
            return 0
        if port == self.base + 2:
            self.pret = false
            return self.valeur + 500
        return 255

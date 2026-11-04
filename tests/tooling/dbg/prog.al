from collections use append
class Compte:
    func init(nom, solde):
        self.nom = nom
        self.solde = solde
        self.historique = []

    func deposer(montant):
        append(self.historique, montant)
        self.solde = self.solde + montant
        return self.solde

LIMITE := 100

func total(valeurs):
    somme := 0
    for v in valeurs:
        somme = somme + v
    return somme

func main():
    c := Compte("Alice", 10)
    notes := {"maths": 15, "info": 18}
    for i in [0, 1, 2, 3, 4]:
        c.deposer(i * 10)
    t := total([1, 2, 3])
    nom := input()
    print("bonjour " + nom)
    print(t)
    x := 10 / (t - 6)

main()

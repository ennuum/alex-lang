# Programme de calcul, lancé en plusieurs exemplaires simultanés : ses variables globales sont aux mêmes
# adresses virtuelles dans chaque processus ; seuls des espaces d'adressage séparés donnent à chacun son résultat.
use os
from core use to_int
args := os.args()
n := to_int(args[0])
graine := to_int(args[1])
etat := graine
total := 0
i := 0
while i < n:
    etat = (etat * 1103515245 + 12345) % 2147483648
    total = (total + etat % 1000) % 1000000007
    i += 1
print(f"graine {graine} : {total}")

# Application de test des exécutables autonomes (tests/app/run_standalone_test.sh).
#   app                -> salue, affiche ses arguments et un calcul JSON (stdlib embarquée)
#   app --exit N       -> os.exit(N)
#   app --boom         -> exception non rattrapée (trace + code 1)
use os
use json
from collections use contains
from greet use greeting
from core use to_int

func main():
    a := os.args()
    print(greeting("monde"))
    print("args=" + json.stringify(a))
    print("somme=" + str(json.parse("[1, 2, 3, 4]")[3] + 38))
    if contains(a, "--exit"):
        os.exit(to_int(a[1]))
    if contains(a, "--boom"):
        boom()

func boom():
    x := {"k": 1}
    return x["absente"]

main()

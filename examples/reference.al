use math

const VERSION := "0.1.0"

func add(a, b):
    return a + b

func main():
    name := "Alexandre"
    age := 25
    numbers := [10, 20, 30]
    print("ALEX", VERSION)
    print("Bonjour " + name)
    if age >= 18:
        print("Utilisateur majeur")
    else:
        print("Utilisateur mineur")
    total := add(10, 20)
    print("Résultat :", total)
    for number in numbers:
        print(number)

main()

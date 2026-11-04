use math
from math use sqrt

const VERSION := "0.1.0"

struct Point:
    func init(x, y):
        self.x = x
        self.y = y

    func distance_to_origin():
        return sqrt(self.x ** 2 + self.y ** 2)

func divide(a, b):
    if b == 0:
        return null
    return a / b

func describe(age):
    return "majeur" if age >= 18 else "mineur"

func main():
    name := "Alexandre"
    age := 25
    greeting := f"Bonjour {name}, tu es {describe(age)}"
    print(greeting)
    print("Version :", VERSION)

    p := Point(3, 4)
    print(p.distance_to_origin())

    numbers := [10, 20, 30]
    total := 0
    for n in numbers:
        total += n
    print("Somme :", total)

    try:
        result := divide(10, 0)
        print(result)
    catch error:
        print("Erreur :", error)

    outcome := divide(10, 2)
    print(outcome)

main()

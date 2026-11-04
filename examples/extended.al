use math
from math use sqrt

struct User:
    func init(name, age):
        self.name = name
        self.age = age

class Admin extends User:
    func init(name, age, role):
        super.init(name, age)
        self.role = role

interface Printable:
    func print_info()

enum Status:
    PENDING
    ACTIVE
    CLOSED

func square(x) => x * x

async func download(url):
    data := await http.get(url)
    return data

func main():
    name := "Alexandre"
    age := 25
    point := (10, 20)
    user := {"name": "Alexandre", "age": 25}
    greeting := f"Bonjour {name}, âge = {age}"

    status := Status.ACTIVE
    result := -2 ** 2
    label := "majeur" if age >= 18 else "mineur"

    for i in 0..10:
        print(i)

    x := 0
    while x < 10:
        x += 1
        if x == 5:
            continue
        if x == 9:
            break

    try:
        value := divide(10, 0)
    catch error:
        print(error)

    outcome := divide(10, 2)?

    match age:
        0:
            print("Zéro")
        18:
            print("Majeur pile")
        n:
            print("Autre :", n)

    greet(name=name, age=age)

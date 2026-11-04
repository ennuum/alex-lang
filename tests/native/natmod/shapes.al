# Module de test (ok_modules.al) : constantes, état, classes, fonctions.
use natmod.counter
const UNIT := 10
created := 0
print("init shapes")

class Shape:
    name: str := "forme"
    func area() -> int:
        return 0
    func describe() -> str:
        return self.name + " d'aire " + str(self.area())

class Rect extends Shape:
    w: int := 0
    h: int := 0
    func init(w: int, h: int):
        self.w = w
        self.h = h
        self.name = "rectangle"
        created += 1
        counter.tick()
    func area() -> int:
        return self.w * self.h

func square(side: int) -> Rect:
    return Rect(side, side)

func scaled(r: Rect) -> int:
    return r.area() * UNIT

func divide(a: int, b: int) -> int:
    return a // b

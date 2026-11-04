enum Shape:
    Circle(radius)
    Rectangle(width, height)
    Point

struct Counter:
    func init(start):
        self.value = start

    func bump(n):
        self.value += n
        return self.value

func area(shape):
    match shape:
        Shape.Circle(r) if r > 0:
            return 3.14159 * r * r
        Shape.Circle(r):
            return 0
        Shape.Rectangle(w, h):
            return w * h
        Shape.Point:
            return 0

func classify(n):
    match n:
        0..10:
            return "petit"
        10..100:
            return "moyen"
        n:
            return "grand"

func main():
    c := Shape.Circle(4)
    r := Shape.Rectangle(3, 5)
    p := Shape.Point
    print("aire cercle :", area(c))
    print("aire rectangle :", area(r))
    print("aire point :", area(p))

    print(classify(5))
    print(classify(42))
    print(classify(1000))

    counter := Counter(10)
    print(counter.bump(5))
    print(counter.bump(2))

main()

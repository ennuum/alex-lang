# Enums (simples et à charge utile) et match : littéraux, plages, captures, gardes, variantes, tuples, listes.
enum Color:
    Red
    Green
    Rgb(r: int, g: int, b: int)

enum Shape:
    Circle(radius)
    Rect(w, h)
    Empty

c := Color.Red
d := Color.Rgb(1, 2, 3)
print(c, d, Color.Green)
print(c == c, c == Color.Red, d != Color.Rgb(1, 2, 3))

func name(c: Color) -> str:
    match c:
        Color.Red:
            return "rouge"
        Color.Rgb(r, g, b) if r > 0:
            return f"rgb({r},{g},{b})"
        Color.Rgb(0, g, _):
            return f"vert {g}"
        _:
            return "autre"
    return "?"

print(name(c), name(d), name(Color.Green), name(Color.Rgb(0, 9, 1)))

func area(s: Shape) -> float:
    match s:
        Shape.Circle(r):
            return 3.0 * r * r
        Shape.Rect(w, h):
            return w * h
    return 0.0

shapes: list[Shape] := [Shape.Circle(2.0), Shape.Rect(3.0, 4.0), Shape.Empty]
for s in shapes:
    print(s, area(s))

func classify(x: int) -> str:
    match x:
        0:
            return "zéro"
        1..5:
            return "petit"
        n if n % 2 == 1:
            return f"impair {n}"
        _:
            return "grand pair"
    return "?"

for v in [0, 3, 7, 8, -2]:
    print(classify(v))
match (1, "a"):
    (2, s):
        print("deux", s)
    (1, s):
        print("un", s)
match [1, 2]:
    [a]:
        print("un élément")
    [a, b]:
        print(a + b)
match "hey":
    "ho":
        print("non")
    "hey":
        print("salut")
match 3.5:
    3.5:
        print("float")
match 42:
    0:
        print("non")
counter := 0
for k in 0..10:
    match k % 3:
        0:
            counter += 1
        _:
            counter += 10
print(counter)

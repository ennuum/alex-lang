use string
# Erreurs de type détectées à la compilation (make test-types compare avec types_errors_expected.txt).
struct Point:
    x: int := 0
    func init(x: int):
        self.x = x

func add(a: int, b: int) -> int:
    return a + b

func name() -> str:
    return 42

func nothing() -> int:
    return

x: int := "texte"
o: u8 := 300
add(1, "deux")
add(b="deux", a=1)
p: Point := Point(1.5)
p.x = "a"
y := 1 + "a"
z: Pointt := null
n: int := null
q: int? := null
w := q + 1
l: list[int] := ["a"]
d: dict[str] := {}
c: i8 := -129
e: i32 := 1
f: u8 := 2
g := e + f
h := string.upper(42)
func after_test(n: int?) -> int:
    if n != null:
        print("ok")
    return n + 1

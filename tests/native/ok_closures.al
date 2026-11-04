from collections use append

func make_counter() -> func() -> int:
    n := 0
    func next() -> int:
        n += 1
        return n
    return next

func apply(f: func(int) -> int, x: int) -> int:
    return f(x)

func twice(f: func(int) -> int) -> func(int) -> int:
    return x => f(f(x))

func double(n: int) -> int:
    return n * 2

func compose(f: func(int) -> int, g: func(int) -> int) -> func(int) -> int:
    return (x) => g(f(x))

func fact_local(n: int) -> int:
    func go(k: int) -> int:
        if k <= 1:
            return 1
        return k * go(k - 1)
    return go(n)

func adder(base: int) -> func(int) -> int:
    return x => x + base

c := make_counter()
print(c(), c(), c())
d := make_counter()
print(d(), c())
print(c)
print(apply(x => x * 10, 4))
print(apply(double, 21))
print(twice(double)(3))
print(compose(double, adder(1))(5))
print(fact_local(10))
inc := adder(100)
print(inc(1), adder(-1)(1))
print(double)

fs: list[func() -> int] := []
for i in 0..3:
    append(fs, () => i * 10)
for f in fs:
    print(f())
gs: list[func() -> str] := []
for s in ["a", "b"]:
    append(gs, () => s + "!")
for g in gs:
    print(g())

total := 0
for k in 0..5:
    func bump(v: int):
        total += v
    bump(k)
print(total)

func logger(prefix: str) -> func(str):
    return m => print(prefix + m)
log := logger("> ")
log("bonjour")

ops: dict[str, func(int, int) -> int] := {"add": (a, b) => a + b, "mul": (a, b) => a * b}
print(ops["add"](3, 4), ops["mul"](3, 4))
h := func(x: float) => x / 2.0
print(h(5.0))
if c:
    print("fonction vraie")

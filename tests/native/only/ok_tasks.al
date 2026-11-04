# Module tasks (natif seulement) : tâches coopératives, exceptions isolées par tâche, GC sur toutes les piles.
use tasks
from collections use append
results: dict[str, int] := {}
func builder(name: str, n: int):
    parts: list[str] := []
    for i in 0..n:
        append(parts, name + str(i * i))
        if i % 10 == 0:
            tasks.yield_now()
    total := 0
    for p in parts:
        total += len(p)
    results[name] = total
func risky(k: int):
    try:
        tasks.yield_now()
        if k % 2 == 0:
            raise("Oups", f"tâche {k}")
        tasks.yield_now()
    catch e:
        print("rattrapé dans la tâche :", e.message)
from core use len
for t in ["x", "y", "z"]:
    tasks.spawn(() => builder(t, 3000))
try:
    for k in 0..4:
        tasks.spawn(() => risky(k))
    tasks.run()
catch e:
    print("ne doit pas arriver", e)
print(results)
func deep(n: int) -> int:
    if n == 0:
        return 0
    return 1 + deep(n - 1)
tasks.spawn(() => print(deep(5000)))
tasks.run()
log: list[str] := []
func worker2(name: str, n: int):
    for i in 0..n:
        append(log, f"{name}{i}")
        tasks.yield_now()
tasks.spawn(() => worker2("a", 3))
tasks.spawn(() => worker2("b", 2))
id := tasks.spawn(() => worker2("c", 4))
print(id > 0, tasks.alive())
tasks.run()
print(log)
print(tasks.alive(), tasks.current())
for k in 0..300:
    tasks.spawn(() => print_nothing())
    if k % 100 == 99:
        tasks.run()
func print_nothing():
    s := "x" + str(1)
print("fini")

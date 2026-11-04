# Sans OS : interruptions (minuterie PIT, int3), gestionnaires Alex qui allouent, préemption des tâches
# par la minuterie, pages physiques.
use hw
use tasks
from collections use append
from core use len
ticks := 0
func on_tick(code: int):
    ticks += 1
    hw.eoi(0)
hw.pic_init()
hw.on_interrupt(32, on_tick)
hw.timer_start(1000)
hw.irq_enable(0)
while ticks < 20:
    hw.wait()
hw.disable()
print("minuterie :", ticks >= 20)
hits: list[int] := []
hw.on_interrupt(3, c => append(hits, c + 1))
hw.asm("cc") # int3
hw.asm("cc")
print("int3 :", hits)
# Le gestionnaire alloue (chaînes) pendant que le programme alloue aussi.
names: list[str] := []
func alloc_tick(code: int):
    if len(names) < 100:
        append(names, "tick " + str(len(names)))
    hw.eoi(0)
hw.on_interrupt(32, alloc_tick)
hw.enable()
total := 0
for i in 0..30000:
    total += len(str(i) + "!")
while len(names) < 100:
    hw.wait()
hw.disable()
print("allocations :", total, names[99])
# Préemption : trois tâches sans yield partagent le processeur.
counts: list[int] := [0, 0, 0]
done := 0
order: list[int] := []
func busy(k: int):
    i := 0
    while i < 400000:
        counts[k] += 1
        i += 1
    hw.disable()
    done += 1
    hw.enable()
func switch_tick(code: int):
    if len(order) < 8:
        append(order, tasks.current())
    hw.eoi(0)
    tasks.yield_now()
hw.on_interrupt(32, switch_tick)
for k in 0..3:
    tasks.spawn(() => busy(k))
hw.enable()
while done < 3:
    hw.wait()
hw.disable()
print("préemption :", counts, order)
# Pages physiques : alignées, mises à zéro, réutilisées après libération.
p := hw.alloc_pages(4)
print("pages :", p % 4096, hw.peek64(p), hw.peek64(p + 4096 * 4 - 8))
hw.poke64(p, 1234)
hw.free_pages(p, 4)
q := hw.alloc_pages(4)
print(q % 4096, hw.peek64(q), hw.cr3() % 4096)

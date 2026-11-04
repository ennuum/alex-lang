# Sans OS (QEMU) : paquet interrupt avec le vrai matériel — PIC 8259 + PIT, puis APIC local + IO-APIC
# (PIT sur la GSI 2), minuterie de l'APIC local, interruption vers soi (vecteur MSI), exception int3.
use hw
use interrupt
use interrupt.interrupt_types as it
use interrupt.interrupt_controller as ic
from collections use append
from core use len

ticks: list[int] := [0]
func tick(irq: int):
    ticks[0] += 1

func bump(cell: list[int]):
    cell[0] += 1

m := interrupt.with_pic()
m.on_simple(it.IRQ_TIMER, tick)
hw.timer_start(1000)
hw.enable()
while ticks[0] < 10:
    hw.wait()
hw.disable()
print("PIC : minuterie", ticks[0] >= 10, m.count(0) >= 10)
bps: list[int] := []
m.on_exception(it.BREAKPOINT, (code) => append(bps, code))
hw.asm("cc")
print("int3 :", len(bps), m.vector_count(3))

print("APIC présent :", ic.has_apic())
m2 := interrupt.with_ioapic(0xFEC00000)
l := m2.lapic
if l != null:
    print("APIC local actif :", l.enabled(), "id", l.id(), "LVT", l.max_lvt() >= 4)
    io := m2.controller
    print("IO-APIC : entrées", io.lines())
    t2: list[int] := [0]
    m2.on_simple(interrupt.legacy_gsi(it.IRQ_TIMER), (g) => bump(t2))
    hw.enable()
    while t2[0] < 10:
        hw.wait()
    hw.disable()
    m2.mask(2)
    print("IO-APIC : minuterie sur la GSI 2", t2[0] >= 10)
    hits: list[int] := []
    v := m2.allocate_msi((vec) => append(hits, vec), "test")
    l.send_self(v)
    hw.enable()
    while len(hits) < 1:
        hw.wait()
    hw.disable()
    print("IPI vers soi : vecteur", hits[0], v == 80)
    lt: list[int] := [0]
    m2.on_vector(it.APIC_TIMER, (vec) => bump(lt))
    l.timer_start(it.APIC_TIMER, 100000, 16, true)
    hw.enable()
    while lt[0] < 5:
        hw.wait()
    hw.disable()
    l.timer_stop()
    print("minuterie de l'APIC local :", lt[0] >= 5)
    print("EOI APIC :", l.eoi_count >= 16)

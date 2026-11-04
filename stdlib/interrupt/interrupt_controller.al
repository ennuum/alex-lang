# alex: native
# ALEX STANDARD LIBRARY — interrupt.interrupt_controller
#
# Contrôleurs d'interruptions x86 :
#   - Pic8259 : les deux PIC 8259A en cascade (ports 0x20/0x21, 0xA0/0xA1), remappés aux vecteurs choisis,
#     masques, fin d'interruption, registres IRR / ISR, détection des interruptions parasites (IRQ 7 / 15) ;
#   - LocalApic : APIC local du processeur (MMIO 0xFEE00000, MSR 0x1B) : activation, identifiant, priorité,
#     fin d'interruption, minuterie (périodique / unique), interruptions inter-processeurs ;
#   - IoApic : IO-APIC (MMIO 0xFEC00000) : table de redirection (vecteur, destination, front / niveau,
#     polarité, masque) pour chaque entrée globale (GSI).
# Pic8259 et IoApic implémentent InterruptController (enable / disable / eoi / vector_of), ce qui permet à
# interrupt.InterruptManager de fonctionner avec l'un ou l'autre.
#
#   use interrupt.interrupt_controller as ic
#   pic := ic.Pic8259(32, 40)
#   pic.setup()                      # tout masqué
#   pic.enable(1)                    # clavier -> vecteur 33
#   ...
#   pic.eoi(1)
#
#   lapic := ic.LocalApic(0)         # 0 : adresse lue dans le MSR IA32_APIC_BASE
#   lapic.setup()
#   ioapic := ic.IoApic(0xFEC00000, 0, lapic)
#   ic.Pic8259(32, 40).disable_all() # le PIC hérité se tait
#   ioapic.route(2, 32, lapic.id(), false, false)   # PIT (GSI 2 sous QEMU / ACPI) -> vecteur 32
#
# Compilable en natif (# alex: native) ; dans la VM, la machine simulée de hw fournit le PIC (et hw.sim_apic
# l'APIC local et l'IO-APIC).

use hw
use interrupt.interrupt_types as it

interface InterruptController:
    func name() -> str
    func setup()
    func enable(irq: int)
    func disable(irq: int)
    func eoi(irq: int)
    func vector_of(irq: int) -> int
    func lines() -> int
    # Vrai si l'interruption irq qui arrive est parasite (à ignorer, sans fin d'interruption complète).
    func spurious(irq: int) -> bool

# ---------------------------------------------------------------- PIC 8259A
const PIC1_CMD := 0x20
const PIC1_DATA := 0x21
const PIC2_CMD := 0xA0
const PIC2_DATA := 0xA1

class Pic8259 implements InterruptController:
    master_base: int := 32
    slave_base: int := 40
    eoi_count: int := 0
    spurious_count: int := 0

    func init(master_base: int, slave_base: int):
        self.master_base = master_base & 0xF8
        self.slave_base = slave_base & 0xF8
        self.eoi_count = 0
        self.spurious_count = 0

    func name() -> str:
        return "PIC 8259A"

    # Initialisation (ICW1..ICW4) : bases des vecteurs, cascade sur la ligne 2, mode 8086 ; tout masqué.
    func setup():
        hw.outb(PIC1_CMD, 0x11)
        hw.outb(PIC2_CMD, 0x11)
        hw.outb(PIC1_DATA, self.master_base)
        hw.outb(PIC2_DATA, self.slave_base)
        hw.outb(PIC1_DATA, 4)
        hw.outb(PIC2_DATA, 2)
        hw.outb(PIC1_DATA, 1)
        hw.outb(PIC2_DATA, 1)
        hw.outb(PIC1_DATA, 0xFF)
        hw.outb(PIC2_DATA, 0xFF)

    func lines() -> int:
        return 16

    func vector_of(irq: int) -> int:
        if irq < 8:
            return self.master_base + irq
        return self.slave_base + irq - 8

    func enable(irq: int):
        if irq < 8:
            hw.outb(PIC1_DATA, hw.inb(PIC1_DATA) & ~(1 << irq))
        else:
            hw.outb(PIC2_DATA, hw.inb(PIC2_DATA) & ~(1 << (irq - 8)))
            hw.outb(PIC1_DATA, hw.inb(PIC1_DATA) & ~4)

    func disable(irq: int):
        if irq < 8:
            hw.outb(PIC1_DATA, hw.inb(PIC1_DATA) | (1 << irq))
        else:
            hw.outb(PIC2_DATA, hw.inb(PIC2_DATA) | (1 << (irq - 8)))

    # Masque toutes les lignes (pour passer à l'IO-APIC).
    func disable_all():
        hw.outb(PIC1_DATA, 0xFF)
        hw.outb(PIC2_DATA, 0xFF)

    # Masque des 16 lignes (bit à 1 : masquée).
    func mask() -> int:
        return hw.inb(PIC1_DATA) | (hw.inb(PIC2_DATA) << 8)

    func set_mask(m: int):
        hw.outb(PIC1_DATA, m & 255)
        hw.outb(PIC2_DATA, (m >> 8) & 255)

    func eoi(irq: int):
        self.eoi_count += 1
        if irq >= 8:
            hw.outb(PIC2_CMD, 0x20)
        hw.outb(PIC1_CMD, 0x20)

    # Demandes en attente (IRR) des 16 lignes.
    func irr() -> int:
        hw.outb(PIC1_CMD, 0x0A)
        hw.outb(PIC2_CMD, 0x0A)
        return hw.inb(PIC1_CMD) | (hw.inb(PIC2_CMD) << 8)

    # Interruptions en service (ISR) des 16 lignes.
    func isr() -> int:
        hw.outb(PIC1_CMD, 0x0B)
        hw.outb(PIC2_CMD, 0x0B)
        v := hw.inb(PIC1_CMD) | (hw.inb(PIC2_CMD) << 8)
        hw.outb(PIC1_CMD, 0x0A)
        hw.outb(PIC2_CMD, 0x0A)
        return v

    # IRQ 7 / 15 sans bit ISR : parasite. Pour 15, le maître a tout de même reçu la cascade : EOI au maître.
    func spurious(irq: int) -> bool:
        if irq != 7 and irq != 15:
            return false
        if self.isr() & (1 << irq) != 0:
            return false
        self.spurious_count += 1
        if irq == 15:
            hw.outb(PIC1_CMD, 0x20)
        return true

# ---------------------------------------------------------------- APIC local
const APIC_BASE_MSR := 0x1B
const LAPIC_ID := 0x20
const LAPIC_VERSION := 0x30
const LAPIC_TPR := 0x80
const LAPIC_EOI := 0xB0
const LAPIC_SVR := 0xF0
const LAPIC_ISR := 0x100
const LAPIC_ESR := 0x280
const LAPIC_ICR_LOW := 0x300
const LAPIC_ICR_HIGH := 0x310
const LAPIC_LVT_TIMER := 0x320
const LAPIC_LVT_LINT0 := 0x350
const LAPIC_LVT_LINT1 := 0x360
const LAPIC_LVT_ERROR := 0x370
const LAPIC_TIMER_INITIAL := 0x380
const LAPIC_TIMER_CURRENT := 0x390
const LAPIC_TIMER_DIVIDE := 0x3E0
const LVT_MASKED := 0x10000
const TIMER_PERIODIC := 0x20000

class LocalApic:
    phys: int := 0
    base: int := 0
    eoi_count: int := 0

    # phys : adresse physique (0 : celle du MSR IA32_APIC_BASE).
    func init(phys: int):
        p := phys
        if p == 0:
            p = hw.rdmsr(APIC_BASE_MSR) & 0xFFFFF000
        self.phys = p
        self.base = hw.mmio(p)
        self.eoi_count = 0

    func read(reg: int) -> int:
        return hw.peek32(self.base + reg)

    func write(reg: int, value: int):
        hw.poke32(self.base + reg, value & 0xFFFFFFFF)

    # Active l'APIC (MSR et registre SVR avec le vecteur parasite), priorité 0, erreurs effacées.
    func setup():
        hw.wrmsr(APIC_BASE_MSR, hw.rdmsr(APIC_BASE_MSR) | 0x800)
        self.write(LAPIC_SVR, 0x100 | it.SPURIOUS)
        self.write(LAPIC_TPR, 0)
        self.write(LAPIC_ESR, 0)
        self.write(LAPIC_ESR, 0)
        self.write(LAPIC_LVT_ERROR, it.APIC_ERROR)

    func enabled() -> bool:
        return self.read(LAPIC_SVR) & 0x100 != 0

    func id() -> int:
        return (self.read(LAPIC_ID) >> 24) & 255

    func version() -> int:
        return self.read(LAPIC_VERSION) & 255

    func max_lvt() -> int:
        return ((self.read(LAPIC_VERSION) >> 16) & 255) + 1

    func set_priority(p: int):
        self.write(LAPIC_TPR, p & 255)

    func eoi():
        self.eoi_count += 1
        self.write(LAPIC_EOI, 0)

    # Minuterie : vecteur, compte initial, diviseur (1, 2, 4, ..., 128), périodique ou unique.
    func timer_start(vector: int, initial: int, divide: int, periodic: bool):
        d := 0xB      # 1
        if divide == 2:
            d = 0
        elif divide == 4:
            d = 1
        elif divide == 8:
            d = 2
        elif divide == 16:
            d = 3
        elif divide == 32:
            d = 8
        elif divide == 64:
            d = 9
        elif divide == 128:
            d = 10
        self.write(LAPIC_TIMER_DIVIDE, d)
        lvt := vector & 255
        if periodic:
            lvt = lvt | TIMER_PERIODIC
        self.write(LAPIC_LVT_TIMER, lvt)
        self.write(LAPIC_TIMER_INITIAL, initial)

    func timer_stop():
        self.write(LAPIC_LVT_TIMER, LVT_MASKED)
        self.write(LAPIC_TIMER_INITIAL, 0)

    func timer_current() -> int:
        return self.read(LAPIC_TIMER_CURRENT)

    # Interruption inter-processeurs : vecteur vers l'APIC dest (mode fixe).
    func send_ipi(dest: int, vector: int):
        self.write(LAPIC_ICR_HIGH, (dest & 255) << 24)
        self.write(LAPIC_ICR_LOW, vector & 255)

    # À soi-même (raccourci de destination « self »).
    func send_self(vector: int):
        self.write(LAPIC_ICR_HIGH, 0)
        self.write(LAPIC_ICR_LOW, 0x40000 | (vector & 255))

    func ipi_pending() -> bool:
        return self.read(LAPIC_ICR_LOW) & 0x1000 != 0

    func error_status() -> int:
        self.write(LAPIC_ESR, 0)
        return self.read(LAPIC_ESR)

    # Le vecteur est-il en service (ISR) ?
    func in_service(vector: int) -> bool:
        return (self.read(LAPIC_ISR + 0x10 * (vector // 32)) >> (vector % 32)) & 1 == 1

# ---------------------------------------------------------------- IO-APIC
const IOAPIC_REGSEL := 0x00
const IOAPIC_WINDOW := 0x10
const IOAPIC_ID := 0x00
const IOAPIC_VERSION := 0x01
const IOAPIC_REDIRECTION := 0x10
const REDIR_MASKED := 0x10000
const REDIR_LEVEL := 0x8000
const REDIR_ACTIVE_LOW := 0x2000

class IoApic implements InterruptController:
    phys: int := 0
    base: int := 0
    gsi_base: int := 0
    vector_base: int := 32
    lapic: LocalApic
    count: int := 24
    dest: int := 0

    # phys : adresse physique (0xFEC00000 d'habitude) ; gsi_base : première entrée globale de cet IO-APIC ;
    # lapic : APIC local qui reçoit la fin d'interruption.
    func init(phys: int, gsi_base: int, lapic: LocalApic):
        self.phys = phys
        self.base = hw.mmio(phys)
        self.gsi_base = gsi_base
        self.vector_base = it.IRQ_BASE
        self.lapic = lapic
        self.count = 24
        self.dest = 0

    func name() -> str:
        return "IO-APIC"

    func read(reg: int) -> int:
        hw.poke32(self.base + IOAPIC_REGSEL, reg & 255)
        return hw.peek32(self.base + IOAPIC_WINDOW)

    func write(reg: int, value: int):
        hw.poke32(self.base + IOAPIC_REGSEL, reg & 255)
        hw.poke32(self.base + IOAPIC_WINDOW, value & 0xFFFFFFFF)

    func id() -> int:
        return (self.read(IOAPIC_ID) >> 24) & 15

    func version() -> int:
        return self.read(IOAPIC_VERSION) & 255

    # Masque toutes les entrées ; leur vecteur par défaut est vector_base + n, destination l'APIC local.
    func setup():
        self.count = ((self.read(IOAPIC_VERSION) >> 16) & 255) + 1
        self.dest = self.lapic.id()
        n := 0
        while n < self.count:
            self.set_entry(n, REDIR_MASKED | (self.vector_base + self.gsi_base + n), self.dest)
            n += 1

    func lines() -> int:
        return self.count

    func entry(n: int) -> int:
        return self.read(IOAPIC_REDIRECTION + 2 * n) | (self.read(IOAPIC_REDIRECTION + 2 * n + 1) << 32)

    func set_entry(n: int, low: int, dest: int):
        self.write(IOAPIC_REDIRECTION + 2 * n + 1, (dest & 255) << 24)
        self.write(IOAPIC_REDIRECTION + 2 * n, low)

    # Dirige l'entrée gsi vers vector sur l'APIC dest (déclenchement par niveau / actif bas si demandé), démasquée.
    func route(gsi: int, vector: int, dest: int, level: bool, active_low: bool):
        low := vector & 255
        if level:
            low = low | REDIR_LEVEL
        if active_low:
            low = low | REDIR_ACTIVE_LOW
        self.set_entry(gsi - self.gsi_base, low, dest)

    func vector_of(irq: int) -> int:
        return self.entry(irq - self.gsi_base) & 255

    func enable(irq: int):
        n := irq - self.gsi_base
        self.write(IOAPIC_REDIRECTION + 2 * n, self.read(IOAPIC_REDIRECTION + 2 * n) & ~REDIR_MASKED)

    func disable(irq: int):
        n := irq - self.gsi_base
        self.write(IOAPIC_REDIRECTION + 2 * n, self.read(IOAPIC_REDIRECTION + 2 * n) | REDIR_MASKED)

    func masked(irq: int) -> bool:
        return self.read(IOAPIC_REDIRECTION + 2 * (irq - self.gsi_base)) & REDIR_MASKED != 0

    func eoi(irq: int):
        self.lapic.eoi()

    func spurious(irq: int) -> bool:
        return false

# Le processeur a-t-il un APIC local (CPUID n'est pas lisible ici : MSR IA32_APIC_BASE non nul) ?
func has_apic() -> bool:
    return hw.rdmsr(APIC_BASE_MSR) & 0xFFFFF000 != 0

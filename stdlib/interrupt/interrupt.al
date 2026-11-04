# alex: native
# ALEX STANDARD LIBRARY — interrupt
#
# Gestion des interruptions d'un NOYAU (compilé avec --freestanding) ou de la machine simulée de la VM :
# un InterruptManager relie un contrôleur (PIC 8259 ou IO-APIC) aux gestionnaires Alex, gère les lignes
# partagées, les interruptions parasites, la fin d'interruption, les vecteurs MSI, les exceptions du
# processeur, et tient des statistiques.
#
#   use hw
#   use interrupt
#   use interrupt.interrupt_types as it
#   m := interrupt.with_pic()                       # PIC remappé à 32..47, tout masqué
#   m.on_simple(it.IRQ_TIMER, (irq) => tick())      # gestionnaire, ligne démasquée, EOI automatique
#   m.on(it.IRQ_ATA_PRIMARY, (irq) => disque.interruption(), "ata")   # ligne partagée : -> bool
#   v := m.allocate_msi((v) => carte.interruption(), "e1000")         # vecteur MSI (80..223)
#   m.on_exception(it.PAGE_FAULT, (code) => defaut_de_page(code))
#   hw.enable()
#   ...
#   print(m.report())
#
# Le gestionnaire s'exécute interruptions masquées ; l'EOI est envoyée après lui. Pour une section critique :
# interrupt.critical(fn) (masque, exécute, rétablit l'état précédent).
#
# Modules : interrupt.interrupt_types (vecteurs, noms), interrupt.interrupt_controller (Pic8259, LocalApic,
# IoApic), interrupt.interrupt_handler (InterruptHandler, HandlerChain, Deferred).

from collections use append, contains_key
use hw
use interrupt.interrupt_types as it
use interrupt.interrupt_controller as ic
from interrupt.interrupt_controller use InterruptController, Pic8259, LocalApic, IoApic
use interrupt.interrupt_handler as ih
from interrupt.interrupt_handler use InterruptHandler, HandlerChain, FunctionHandler, SimpleHandler

class InterruptManager:
    controller: InterruptController
    chains: dict[int, HandlerChain] := {}
    exceptions: dict[int, int] := {}         # vecteur -> nombre
    vectors: dict[int, int] := {}            # vecteurs MSI / logiciels attribués -> nombre reçus
    next_msi: int := 80
    lapic_eoi: bool := false
    lapic: LocalApic?
    total: int := 0

    func init(controller: InterruptController):
        self.controller = controller
        self.chains = {}
        self.exceptions = {}
        self.vectors = {}
        self.next_msi = it.MSI_BASE
        self.lapic_eoi = false
        self.lapic = null
        self.total = 0

    func setup():
        self.controller.setup()

    # APIC local qui reçoit la fin d'interruption des vecteurs MSI et IPI.
    func use_lapic(l: LocalApic):
        self.lapic = l
        self.lapic_eoi = true

    func chain(irq: int) -> HandlerChain:
        if not contains_key(self.chains, irq):
            c := HandlerChain(irq, self.controller.vector_of(irq))
            self.chains[irq] = c
            hw.on_interrupt(c.vector, (code) => self._dispatch(irq))
        return self.chains[irq]

    # Ajoute un gestionnaire à la ligne irq et la démasque.
    func register(irq: int, h: InterruptHandler):
        self.chain(irq).add(h)
        self.controller.enable(irq)

    # fn(irq) -> bool : vrai si le périphérique a levé l'interruption (ligne partagée).
    func on(irq: int, fn: func(int) -> bool, label: str):
        self.register(irq, FunctionHandler(label, fn))

    # fn(irq) : la ligne n'est pas partagée, l'interruption est toujours revendiquée.
    func on_simple(irq: int, fn: func(int)):
        self.register(irq, SimpleHandler("irq" + str(irq), fn))

    # Retire le gestionnaire label ; la ligne est masquée s'il n'en reste aucun.
    func unregister(irq: int, label: str) -> bool:
        if not contains_key(self.chains, irq):
            return false
        c := self.chains[irq]
        r := c.remove(label)
        if c.size() == 0:
            self.controller.disable(irq)
        return r

    func mask(irq: int):
        self.controller.disable(irq)

    func unmask(irq: int):
        self.controller.enable(irq)

    func _dispatch(irq: int):
        self.total += 1
        c := self.chains[irq]
        if self.controller.spurious(irq):
            c.spurious += 1
            return
        c.dispatch(irq)
        self.controller.eoi(irq)

    # Gestionnaire d'une exception du processeur (code : code d'erreur empilé, 0 sinon).
    func on_exception(vector: int, fn: func(int)):
        self.exceptions[vector] = 0
        hw.on_interrupt(vector, (code) => self._exception(vector, code, fn))

    func _exception(vector: int, code: int, fn: func(int)):
        self.exceptions[vector] = self.exceptions[vector] + 1
        fn(code)

    # Attribue un vecteur MSI / MSI-X et y branche fn(vecteur) ; EOI à l'APIC local (use_lapic) ensuite.
    # Renvoie le vecteur, ou -1 si tous sont pris.
    func allocate_msi(fn: func(int), label: str) -> int:
        if self.next_msi > it.MSI_LAST:
            return -1
        v := self.next_msi
        self.next_msi += 1
        self.on_vector(v, fn)
        return v

    # Branche fn(vecteur) sur un vecteur quelconque (IPI, minuterie de l'APIC, vecteur logiciel).
    func on_vector(vector: int, fn: func(int)):
        self.vectors[vector] = 0
        hw.on_interrupt(vector, (code) => self._vector(vector, fn))

    func _vector(vector: int, fn: func(int)):
        self.total += 1
        self.vectors[vector] = self.vectors[vector] + 1
        fn(vector)
        if self.lapic_eoi:
            l := self.lapic
            if l != null:
                l.eoi()

    func count(irq: int) -> int:
        if contains_key(self.chains, irq):
            return self.chains[irq].count
        return 0

    func vector_count(vector: int) -> int:
        if contains_key(self.vectors, vector):
            return self.vectors[vector]
        if contains_key(self.exceptions, vector):
            return self.exceptions[vector]
        return 0

    func report() -> str:
        out := self.controller.name() + " : " + str(self.total) + " interruptions\n"
        irq := 0
        while irq <= 255:
            if contains_key(self.chains, irq):
                c := self.chains[irq]
                out = out + "  " + c.describe() + " [" + it.irq_name(irq) + "]\n"
            irq += 1
        v := 0
        while v <= 255:
            if contains_key(self.vectors, v):
                out = out + "  vecteur " + str(v) + " (" + it.kind_of(v) + ") : " + str(self.vectors[v]) + " reçues\n"
            if contains_key(self.exceptions, v):
                out = out + "  " + it.exception_name(v) + " : " + str(self.exceptions[v]) + "\n"
            v += 1
        return out

# Gestionnaire avec les PIC 8259 remappés à 32..47 (initialisés, tout masqué).
func with_pic() -> InterruptManager:
    m := InterruptManager(Pic8259(it.IRQ_BASE, it.IRQ_BASE + 8))
    m.setup()
    return m

# Gestionnaire avec l'APIC local et l'IO-APIC (0xFEC00000, GSI 0..) ; le PIC hérité est réduit au silence.
# Sous QEMU / ACPI, la minuterie PIT arrive sur la GSI 2 (route_legacy le prend en compte).
func with_ioapic(ioapic_phys: int) -> InterruptManager:
    Pic8259(it.IRQ_BASE, it.IRQ_BASE + 8).disable_all()
    l := LocalApic(0)
    l.setup()
    io := IoApic(ioapic_phys, 0, l)
    m := InterruptManager(io)
    m.setup()
    m.use_lapic(l)
    return m

# GSI de l'IO-APIC qui porte la ligne ISA irq (redirection habituelle : la minuterie 0 arrive sur 2).
func legacy_gsi(irq: int) -> int:
    if irq == 0:
        return 2
    return irq

# Exécute fn interruptions masquées, puis rétablit l'état précédent.
func critical(fn: func()):
    s := hw.disable_saved()
    fn()
    hw.restore(s)

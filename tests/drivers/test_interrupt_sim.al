# Paquet interrupt dans la machine simulée : PIC 8259 (remappage, masques, EOI, lignes partagées, parasites),
# APIC local et IO-APIC (hw.sim_apic), vecteurs MSI, exceptions, travail différé, sections critiques.
from core use len
from collections use append
use hw
use hw.sim_apic as sa
use interrupt
use interrupt.interrupt_types as it
use interrupt.interrupt_controller as ic
use interrupt.interrupt_handler as ih

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

func _inc(cell):
    cell[0] += 1

func counter(cell):
    return (x) => _inc(cell)

func _set(cell, v):
    cell[0] = v

# ---- types ----
check(it.exception_name(14) == "défaut de page (#PF)", "nom #PF")
check(it.has_error_code(13) and not it.has_error_code(3), "codes d'erreur")
check(it.irq_vector(it.IRQ_KEYBOARD) == 33 and it.vector_irq(46) == 14, "vecteurs IRQ")
check(it.kind_of(100) == "msi" and it.kind_of(255) == "parasite" and it.kind_of(3) == "exception", "kind_of")
check(it.describe(33) == "IRQ 1 (clavier PS/2)", "describe")
check(it.msi_message(81, 2, false)[0] == 0xFEE02000, "message MSI")

# ---- PIC ----
hw.sim_reset(16 * 1024 * 1024, 4 * 1024 * 1024)
m := interrupt.with_pic()
pic := hw.sim_pic()
check(pic["master_base"] == 32 and pic["slave_base"] == 40, "PIC remappé")
check(pic["master_mask"] == 255 and pic["slave_mask"] == 255, "tout masqué")
ticks := [0]
m.on_simple(it.IRQ_TIMER, counter(ticks))
check(hw.sim_pic()["master_mask"] == 254, "ligne 0 démasquée")
hw.sim_raise_irq(0)
check(ticks[0] == 0, "IF = 0 : rien")
hw.enable()
check(ticks[0] == 1, "délivrée à sti")
hw.sim_raise_irq(0)
hw.sim_raise_irq(0)
check(ticks[0] == 3 and m.count(0) == 3, "trois tics")
check(hw.sim_pic()["eoi"] == 3 and hw.sim_pic()["master_isr"] == 0, "EOI envoyées")
# ligne partagée : deux périphériques sur l'IRQ 11
a_pending := [false]
b_pending := [false]
seen := []
func dev_a(irq):
    if a_pending[0]:
        a_pending[0] = false
        append(seen, "a")
        return true
    return false
func dev_b(irq):
    if b_pending[0]:
        b_pending[0] = false
        append(seen, "b")
        return true
    return false
m.on(11, dev_a, "a")
m.on(11, dev_b, "b")
check(hw.sim_pic()["slave_mask"] == 255 - 8 and hw.sim_pic()["master_mask"] & 4 == 0, "IRQ 11 : esclave et cascade")
b_pending[0] = true
hw.sim_raise_irq(11)
a_pending[0] = true
b_pending[0] = true
hw.sim_raise_irq(11)
hw.sim_raise_irq(11)
check(len(seen) == 3 and seen[0] == "b", "gestionnaires partagés : " + str(seen))
check(m.chains[11].unhandled == 1, "non revendiquée comptée")
check(hw.sim_pic()["slave_isr"] == 0, "EOI esclave")
check(m.unregister(11, "a") and m.chains[11].size() == 1, "retrait")
m.unregister(11, "b")
check(hw.sim_pic()["slave_mask"] & 8 == 8, "ligne remasquée sans gestionnaire")
# parasite : IRQ 7 levée puis l'ISR ne la montre pas (le gestionnaire voit isr() = 0 car ISR est mis à la
# délivrance — la machine simulée ne fait pas de parasites, on l'appelle directement)
p := ic.Pic8259(32, 40)
check(not p.spurious(1), "pas parasite hors 7/15")
check(p.spurious(7), "IRQ 7 sans ISR : parasite")
check(p.irr() == 0, "IRR vide")
# exceptions
faults := []
m.on_exception(it.PAGE_FAULT, (code) => append(faults, code))
hw.sim_raise_interrupt(14, 2)
check(len(faults) == 1 and faults[0] == 2 and m.vector_count(14) == 1, "défaut de page")
# section critique
inside := [false]
interrupt.critical(() => _set(inside, not hw.sim_interrupts_enabled()))
check(inside[0] and hw.sim_interrupts_enabled(), "critical")
# travail différé
d := ih.Deferred(4)
for k in 0..6:
    d.post(k)
check(d.pending() == 4 and d.dropped == 2, "anneau plein")
got := []
check(d.drain((v) => append(got, v)) == 4 and got[3] == 3, "drain")
check(d.take() == -1, "vide")

# ---- APIC ----
hw.sim_reset(16 * 1024 * 1024, 4 * 1024 * 1024)
apic := sa.install()
m2 := interrupt.with_ioapic(0xFEC00000)
check(hw.sim_pic()["master_mask"] == 255, "PIC hérité masqué")
l := m2.lapic
check(l.enabled() and l.id() == 0 and l.max_lvt() == 6, "APIC local activé")
io := m2.controller
check(io.lines() == 24, "24 entrées")
check(io.vector_of(5) == 37, "vecteur par défaut")
timer := [0]
m2.on_simple(interrupt.legacy_gsi(it.IRQ_TIMER), counter(timer))
hw.enable()
apic[1].raise_gsi(2)
apic[1].raise_gsi(2)
check(timer[0] == 2, "GSI 2 -> gestionnaire")
check(apic[0].eoi_count == 2, "EOI à l'APIC local")
apic[1].raise_gsi(9)
check(m2.count(9) == 0, "GSI masquée")
kb := [0]
m2.on_simple(9, counter(kb))
check(kb[0] == 1, "demande gardée puis délivrée au démasquage")
# MSI et IPI
msi_hits := []
v := m2.allocate_msi((vec) => append(msi_hits, vec), "carte")
check(v == 80, "premier vecteur MSI")
l.send_self(v)
check(len(msi_hits) == 1 and msi_hits[0] == 80, "IPI vers soi -> MSI")
check(apic[0].eoi_count == 4, "EOI MSI")
# minuterie de l'APIC local
lt := [0]
m2.on_vector(it.APIC_TIMER, counter(lt))
l.timer_start(it.APIC_TIMER, 10, 16, true)
apic[0].tick(35)
check(lt[0] == 3, "minuterie périodique : " + str(lt[0]))
l.timer_stop()
apic[0].tick(50)
check(lt[0] == 3, "minuterie arrêtée")
rep := m2.report()
check(len(rep) > 0, "rapport")
print(rep)
print("interruptions simulées : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")

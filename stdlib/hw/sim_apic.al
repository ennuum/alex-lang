# ALEX STANDARD LIBRARY — hw.sim_apic (MACHINE SIMULÉE, VM seulement)
#
# APIC local (0xFEE00000) et IO-APIC (0xFEC00000) simulés pour la machine de `hw`, afin d'exécuter dans la VM
# les pilotes de interrupt.interrupt_controller (LocalApic, IoApic) :
#   - APIC local : registres lisibles / inscriptibles, identifiant, version (6 entrées LVT), SVR, TPR, EOI
#     (compté ; efface le bit en service le plus prioritaire), ICR (interruption vers soi-même ou vers l'APIC
#     0 : délivrée par hw.sim_raise_interrupt), minuterie (compte décrémenté par sim_tick_timer, périodique ou
#     unique, vecteur de la LVT) ;
#   - IO-APIC : REGSEL / WINDOW, identifiant, version (24 entrées), table de redirection ; raise_gsi(n) délivre
#     le vecteur programmé si l'entrée n'est pas masquée (sinon la demande est gardée pour le démasquage en
#     déclenchement par niveau).
#
#   use hw.sim_apic as sa
#   lapic, ioapic := ...
#   apic := sa.install()          # [lapic, ioapic]
#   apic[1].raise_gsi(2)
#   apic[0].tick(1000)            # minuterie

from core use len
from collections use append, contains_key
use hw

class SimLocalApic:
    func init(apic_id=0):
        self.regs = {0x20: apic_id << 24, 0x30: 0x50014, 0xF0: 0xFF, 0x320: 0x10000, 0x350: 0x10000, 0x360: 0x10000, 0x370: 0x10000}
        self.eoi_count = 0
        self.in_service = []
        self.ipis = []
        self.current = 0

    func mem_read(offset, size):
        if offset == 0x390:
            return self.current
        if contains_key(self.regs, offset):
            return self.regs[offset]
        return 0

    func mem_write(offset, size, value):
        if offset == 0xB0:
            self.eoi_count += 1
            if len(self.in_service) > 0:
                self.in_service = [self.in_service[i] for i in 1..len(self.in_service)]
            return
        if offset == 0x300:
            self.regs[0x300] = value & ~0x1000
            vector := value & 255
            shorthand := (value >> 18) & 3
            dest := (self.mem_read(0x310, 4) >> 24) & 255
            append(self.ipis, [dest, vector])
            if shorthand == 1 or dest == ((self.regs[0x20] >> 24) & 255):
                self.deliver(vector)
            return
        if offset == 0x380:
            self.current = value
        self.regs[offset] = value

    func deliver(vector):
        if self.mem_read(0xF0, 4) & 0x100 == 0:
            return
        append(self.in_service, vector)
        hw.sim_raise_interrupt(vector)

    # Fait avancer la minuterie de n unités (après division).
    func tick(n=1):
        lvt := self.mem_read(0x320, 4)
        k := 0
        while k < n and self.current > 0:
            self.current -= 1
            k += 1
            if self.current == 0:
                if lvt & 0x10000 == 0:
                    self.deliver(lvt & 255)
                if lvt & 0x20000 != 0:
                    self.current = self.mem_read(0x380, 4)

class SimIoApic:
    func init(apic_id=0, entries=24):
        self.id = apic_id
        self.entries = entries
        self.regsel = 0
        self.table = [65536 for i in 0..2 * entries]      # masquées
        self.pending = {}
        self.delivered = []

    func mem_read(offset, size):
        if offset == 0:
            return self.regsel
        if offset == 0x10:
            r := self.regsel
            if r == 0:
                return self.id << 24
            if r == 1:
                return ((self.entries - 1) << 16) | 0x20
            if r >= 0x10 and r < 0x10 + 2 * self.entries:
                return self.table[r - 0x10]
            return 0
        return 0

    func mem_write(offset, size, value):
        if offset == 0:
            self.regsel = value & 255
            return
        if offset == 0x10:
            r := self.regsel
            if r == 0:
                self.id = (value >> 24) & 15
            elif r >= 0x10 and r < 0x10 + 2 * self.entries:
                self.table[r - 0x10] = value & 0xFFFFFFFF
                n := (r - 0x10) // 2
                if contains_key(self.pending, n) and self.pending[n] and self.table[2 * n] & 65536 == 0:
                    self.pending[n] = false
                    self.raise_gsi(n)

    func raise_gsi(n):
        low := self.table[2 * n]
        if low & 65536 != 0:
            self.pending[n] = true
            return false
        append(self.delivered, [n, low & 255])
        hw.sim_raise_interrupt(low & 255)
        return true

# Branche un APIC local et un IO-APIC sur la machine simulée ; renvoie [lapic, ioapic].
func install(lapic_phys=0xFEE00000, ioapic_phys=0xFEC00000):
    l := SimLocalApic(0)
    io := SimIoApic(0)
    hw.sim_map_mmio(lapic_phys, 4096, l)
    hw.sim_map_mmio(ioapic_phys, 4096, io)
    return [l, io]

# Bus PCI simulé (hw.sim_pci) + pilote générique pci.* : énumération, BAR, capacités, MSI, ponts, ECAM, modèle.
from core use len
use hw
use hw.sim_pci as sp
use pci.pci_config as cfg
use pci.pci_bus as pbus
use pci.pci_device as pd

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

class Regs:
    func init():
        self.regs = {}
        self.log = []
    func io_read(bar, off, size):
        return 0x40 + off
    func io_write(bar, off, size, v):
        self.log = self.log
    func mem_read(bar, off, size):
        return 0x1234 + off
    func mem_write(bar, off, size, v):
        self.regs[off] = v

hw.sim_reset(32 * 1024 * 1024, 8 * 1024 * 1024)
host := sp.install(0xE0000000, 4)
nic := sp.SimPciFunction(0x8086, 0x100E, 0x02, 0x00, 0, 3)
nic.set_bar(0, 0x20000, "mem32")
nic.set_bar(1, 64, "io")
nic.set_interrupt(1, 11)
nic.add_power_management()
msi_off := nic.add_msi(true)
model := Regs()
nic.attach_model(model)
host.attach(0, 3, 0, nic)
gpu := sp.SimPciFunction(0x1234, 0x1111, 0x03, 0x00)
gpu.set_bar(0, 0x1000000, "mem64", true)
gpu.set_bar(2, 0x1000, "mem32")
host.attach(0, 2, 0, gpu)
# fonction multiple : 00:1f.0 et 00:1f.2
host.attach(0, 31, 0, sp.SimPciFunction(0x8086, 0x2918, 0x06, 0x01))
sata := sp.SimPciFunction(0x8086, 0x2922, 0x01, 0x06, 1)
sata.set_bar(5, 0x2000, "mem32")
host.attach(0, 31, 2, sata)
# pont vers le bus 1 avec un contrôleur USB
br := sp.bridge()
br.cfg[0x18] = 0
br.cfg[0x19] = 1
br.cfg[0x1A] = 1
host.attach(0, 30, 0, br)
host.attach(1, 0, 0, sp.SimPciFunction(0x8086, 0x7020, 0x0C, 0x03, 0x00))

conf := cfg.PortConfig()
check(cfg.present(conf, 0, 3, 0), "présent 00:03.0")
check(not cfg.present(conf, 0, 4, 0), "absent 00:04.0")
bus := pbus.PciBus(conf)
devs := bus.scan()
check(len(devs) == 7, "7 fonctions (obtenu " + str(len(devs)) + ")")
d := bus.find(0x8086, 0x100E)
check(d != null, "e1000 trouvé")
check(d.cls == 2 and d.revision == 3, "classe et révision")
check(d.class_name() == "Ethernet", "nom de classe : " + d.class_name())
check(d.vendor_name() == "Intel", "fabricant")
bars := d.bars()
check(len(bars) == 2, "2 BAR")
check(bars[0].size == 0x20000 and not bars[0].is_io, "BAR0 128 Kio mémoire")
check(bars[1].size == 64 and bars[1].is_io, "BAR1 64 ports")
check(d.read8(cfg.INTERRUPT_PIN) == 1 and d.read8(cfg.INTERRUPT_LINE) == 11, "ligne d'interruption")
caps := d.capabilities()
check(len(caps) == 2 and caps[0].id == 1 and caps[1].id == 5, "capacités PM, MSI")
check(d.find_capability(5) == msi_off, "find_capability MSI")
check(d.configure_msi(0xFEE00000, 0x41), "MSI programmé")
st := nic.msi_state()
check(st[0] and st[1] == 0xFEE00000 and st[2] == 0x41, "état MSI côté périphérique")
g := bus.find(0x1234, 0x1111)
gb := g.bars()
check(len(gb) == 2 and gb[0].is64 and gb[0].prefetchable and gb[0].size == 0x1000000, "BAR 64 bits préchargeable")
check(gb[1].index == 2 and gb[1].size == 0x1000, "BAR2 après BAR 64 bits")
check(len(bus.find_class(1, 6)) == 1, "AHCI par classe")
check(bus.at(0, 31, 0).is_multifunction(), "multifonction")
check(bus.at(1, 0, 0) != null, "bus 1 derrière le pont")
check(bus.at(0, 30, 0).bridge_buses()[1] == 1, "pont : bus secondaire")
# programmation des BAR et décodage : le modèle reçoit les accès
d.write32(cfg.BAR0, 0xFEB00000)
d.write32(cfg.BAR0 + 4, 0xC000)
d.enable()
check(d.command() & 7 == 7, "commande IO|MEM|MASTER")
check(nic.bar_address(0) == 0xFEB00000, "adresse BAR0")
check(hw.peek32(hw.mmio(0xFEB00000) + 8) == 0x1234 + 8, "lecture MMIO vers le modèle")
hw.poke32(hw.mmio(0xFEB00000) + 0x10, 99)
check(model.regs[0x10] == 99, "écriture MMIO vers le modèle")
check(hw.inb(0xC004) == 0x44, "ports du BAR1 vers le modèle")
d.set_command_bits(cfg.CMD_MEMORY, false)
erreur := ""
try:
    hw.peek32(hw.mmio(0xFEB00000))
catch e:
    erreur = e.type
check(erreur == "MemoryError", "décodage mémoire coupé")
# ECAM : mêmes fonctions, 4096 octets
ecam := cfg.EcamConfig(0xE0000000, 0, 3)
bus2 := pbus.PciBus(ecam)
check(len(bus2.scan()) == 7, "ECAM : 7 fonctions")
check(bus2.find(0x8086, 0x100E).bars()[1].size == 64, "ECAM : BAR")
print(bus.tree())
print("pci simulé : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")

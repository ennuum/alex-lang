# Cadre des pilotes (driver.*) dans la machine simulée : correspondances, choix du plus précis, probe refusé,
# attach en échec, plate-forme, rapport, détachement.
from core use len
from collections use append
use hw
use hw.sim_pci as sp
use pci.pci_config as cfg
use pci.pci_bus as pbus
from driver use Driver
use driver.driver_info as di
from driver.driver_info use DriverInfo, HwDevice
use driver.driver_manager as dmg
use driver.device_binding as dbind
use driver.driver_errors as de

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

class Generic implements Driver:
    func init():
        self.i = DriverInfo("ethernet-générique", "0.1", "toute carte Ethernet", "pci")
        self.i.add_id(di.pci_class(2, 0))
        self.attached = []
    func info():
        return self.i
    func probe(dev):
        return true
    func attach(dev):
        append(self.attached, dev.location)
    func detach(dev):
        self.attached = []
    func status(dev):
        return "générique"

class E1000 implements Driver:
    func init(fail):
        self.i = DriverInfo("e1000", "1.0", "Intel PRO/1000", "pci")
        self.i.add_id(di.pci_id(0x8086, 0x100E))
        self.fail = fail
        self.up = false
    func info():
        return self.i
    func probe(dev):
        return dev.mem_base(0) != -1
    func attach(dev):
        if self.fail:
            de.timeout("e1000", "réinitialisation")
        self.up = true
    func detach(dev):
        self.up = false
    func status(dev):
        return "lien actif" if self.up else "arrêté"

class Serial implements Driver:
    func init():
        self.i = DriverInfo("uart16550", "1.0", "port série", "platform")
        self.i.add_id(di.named("com1"))
    func info():
        return self.i
    func probe(dev):
        return dev.io_base(0) == 0x3F8
    func attach(dev):
        return null
    func detach(dev):
        return null
    func status(dev):
        return "38400 bauds"

hw.sim_reset(16 * 1024 * 1024, 4 * 1024 * 1024)
host := sp.install()
nic := sp.SimPciFunction(0x8086, 0x100E, 0x02, 0x00)
nic.set_bar(0, 0x20000, "mem32", false, 0xFEB00000)
nic.set_interrupt(1, 11)
host.attach(0, 3, 0, nic)
other := sp.SimPciFunction(0x10EC, 0x8139, 0x02, 0x00)
other.set_bar(0, 256, "io", false, 0xC100)
host.attach(0, 4, 0, other)
host.attach(0, 5, 0, sp.SimPciFunction(0x1234, 0x1111, 0x03, 0x00))

# correspondances
h := di.HwDevice("pci", "x", "x")
h.vendor = 0x8086
h.device = 0x100E
h.cls = 2
h.subclass = 0
check(di.pci_id(0x8086, 0x100E).score(h) > di.pci_class(2, 0).score(h), "exact > classe")
check(di.pci_id(0x8086, 0x1000).score(h) == 0, "modèle différent")
check(di.named("com1").score(h) == 0, "nom différent")

m := dmg.DriverManager()
gen := Generic()
e := E1000(true)
m.register(gen)
m.register(e)
m.register(Serial())
erreur := ""
try:
    m.register(Generic())
catch ex:
    erreur = ex.type
check(erreur == "DeviceBusy", "nom en double refusé")
n := m.add_pci_bus(pbus.PciBus(cfg.PortConfig()))
check(n == 3, "3 périphériques PCI (pont hôte exclu)")
m.add_device(di.platform("com1", 0x3F8, 8, 4))
m.add_device(di.platform("lpt1", 0x378, 3, 7))
dev := m.device("00:03.0")
check(dev.irq == 11 and dev.mem_base(0) == 0xFEB00000, "ressources du périphérique PCI")
check(len(m.registry.candidates(dev)) == 2 and m.registry.best_for(dev).info().name == "e1000", "candidats triés")
liaisons := []
m.notify((b) => append(liaisons, b.driver_name()))
check(m.bind_all() == 3, "3 liaisons")
# e1000 échoue (délai) -> le générique prend la carte
check(m.driver_of("00:03.0") == "ethernet-générique", "repli sur le générique")
check(m.driver_of("00:04.0") == "ethernet-générique", "RTL8139 -> générique")
check(m.driver_of("com1") == "uart16550", "plate-forme")
check(m.driver_of("00:05.0") == "" and m.device("00:05.0").state == "sans pilote", "VGA sans pilote")
check(len(m.unclaimed()) == 2, "2 sans pilote")
failed := [b for b in m.bindings if b.state == dbind.FAILED]
check(len(failed) == 1 and failed[0].error_type == "DeviceTimeout", "échec journalisé")
check(len(liaisons) == 3, "rappels")
# le pilote précis réparé : détacher puis relier
m.unbind(dev)
check(gen.attached == [], "détaché")
e.fail = false
b := m.bind(dev)
check(b.bound() and b.driver_name() == "e1000" and b.status() == "lien actif", "e1000 lié après correction")
rep := m.report()
check(len(rep) > 0, "rapport")
print(rep)
check(de.wait_until(() => true, 3) and not de.wait_until(() => false, 3), "wait_until")
m.unbind_all()
check(m.bound_count() == 0, "tout détaché")
print("pilotes simulés : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")

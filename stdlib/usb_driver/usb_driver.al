# alex: native
# ALEX STANDARD LIBRARY — usb_driver
#
# Pile USB d'un noyau Alex (--freestanding) :
#
# | Module                            | Contenu                                                          |
# |-----------------------------------|------------------------------------------------------------------|
# | usb_driver.usb_host_controller    | HostController, UhciController, UsbDev, enumerate                |
# | usb_driver.usb_class              | HidKeyboard, HidMouse, MassStorage (BOT + SCSI, BlockDevice)     |
# | usb_driver.usb_driver_registry    | UsbDriverRegistry : liaison des interfaces aux pilotes de classe |
# | usb.usb_descriptor                | descripteurs et requêtes (commun avec les applications)          |
#
# Ici : UhciDriver (pilote PCI des contrôleurs UHCI, classe 0C:03:00, pour le cadre driver) et UsbStack
# (découverte des contrôleurs, énumération des ports, liaison des pilotes de classe, scrutation).
#
#   use usb_driver
#   pile := usb_driver.start()                   # contrôleurs, périphériques, pilotes
#   print(pile.describe())
#   while true:
#       pile.poll()
#       for k in pile.registry.keyboards:
#           print(k.take_text())
#
# Pas encore : OHCI / EHCI / xHCI, concentrateurs externes (seuls les ports racines sont énumérés),
# transferts isochrones.
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use pci.pci_config as cfg
use pci.pci_bus as pbus
from pci.pci_bus use PciBus
use driver.driver_info as di
from driver.driver_info use DriverInfo, HwDevice
from driver.driver use Driver
use driver.driver_manager as dmg
from driver.driver_manager use DriverManager
use usb_driver.usb_host_controller as uhc
from usb_driver.usb_host_controller use HostController, UhciController, UsbDev
use usb_driver.usb_driver_registry as reg
from usb_driver.usb_driver_registry use UsbDriverRegistry

class UhciDriver implements Driver:
    i: DriverInfo
    controllers: list[UhciController] := []

    func init():
        self.i = DriverInfo("uhci", "1.0", "contrôleur hôte USB 1.1 UHCI", "pci")
        self.i.add_id(di.pci_class_if(0x0C, 0x03, 0x00))
        self.controllers = []

    func info() -> DriverInfo:
        return self.i

    func probe(dev: HwDevice) -> bool:
        return dev.io_base(0) > 0

    func attach(dev: HwDevice):
        p := dev.pci
        if p != null:
            p.enable_io()
            p.enable_bus_master()
            # désactive l'émulation PS/2 du BIOS (LEGSUP, registre 0xC0)
            p.write16(0xC0, 0x8F00)
        c := UhciController(dev.io_base(0))
        c.setup()
        append(self.controllers, c)

    func detach(dev: HwDevice):
        for c in self.controllers:
            hw.outw(c.io, 0)
        self.controllers = []

    func status(dev: HwDevice) -> str:
        if len(self.controllers) == 0:
            return "arrêté"
        return self.controllers[0].describe()

class UsbStack:
    manager: DriverManager
    uhci: UhciDriver
    registry: UsbDriverRegistry
    devices: list[UsbDev] := []
    hosts: list[HostController] := []
    next_address: int := 1

    func init():
        self.manager = DriverManager()
        self.uhci = UhciDriver()
        self.manager.register(self.uhci)
        self.registry = UsbDriverRegistry()
        self.registry.add_defaults()
        self.devices = []
        self.hosts = []
        self.next_address = 1

    # Contrôleurs du bus PCI, puis énumération de leurs ports et liaison des pilotes de classe.
    func discover(bus: PciBus):
        self.manager.add_pci_bus(bus)
        self.manager.bind_all()
        for c in self.uhci.controllers:
            append(self.hosts, c)
            self.scan(c)

    func scan(hc: HostController) -> int:
        n := 0
        p := 0
        while p < hc.port_count():
            if hc.port_connected(p):
                try:
                    d := uhc.enumerate(hc, p, self.next_address)
                    if d != null:
                        self.next_address += 1
                        append(self.devices, d)
                        self.registry.bind(hc, d)
                        n += 1
                catch e:
                    append(self.registry.log, "port " + str(p) + " : énumération en échec (" + e.message + ")")
            p += 1
        return n

    func poll() -> int:
        return self.registry.poll()

    func describe() -> str:
        t := ""
        for h in self.hosts:
            t = t + h.name() + "\n"
        for d in self.devices:
            t = t + "  " + d.describe() + "\n"
        return t + self.registry.describe()

func start() -> UsbStack:
    s := UsbStack()
    s.discover(PciBus(cfg.PortConfig()))
    return s

# alex: native
# ALEX STANDARD LIBRARY — driver
#
# Modèle de pilote de périphérique, commun au noyau Alex (--freestanding) et à la machine simulée de la VM :
#
#   interface Driver
#       info() -> DriverInfo          nom, version, bus, table des périphériques reconnus
#       probe(dev) -> bool            « est-ce bien le mien ? » (lecture de registres, sans rien changer)
#       attach(dev)                   prise en main : réinitialisation, interruptions, files (erreur : échec)
#       detach(dev)                   arrêt propre
#       status(dev) -> str            état lisible
#
# Les autres modules : driver.driver_info (DriverInfo, DeviceId, HwDevice, Resource), driver.device_binding
# (Binding), driver.driver_registry (DriverRegistry), driver.driver_manager (DriverManager : énumère, choisit le
# meilleur pilote, lie, journalise), driver.driver_errors (erreurs, attentes bornées).
#
#   from driver use Driver
#   use driver.driver_info as di
#   use driver.driver_manager as dmg
#   class MonPilote implements Driver:
#       ...
#   m := dmg.DriverManager()
#   m.register(MonPilote())
#   m.add_pci_bus(pci.pci_bus.PciBus(pci.pci_config.PortConfig()))
#   m.bind_all()
#   print(m.report())
#
# Pilotes fournis : storage_driver (ATA, AHCI, NVMe), network_driver (e1000), usb_driver (UHCI, HID),
# gpu_driver (Bochs / QEMU BGA).
#
# Compilable en natif (# alex: native).

use driver.driver_info as di
from driver.driver_info use DriverInfo, HwDevice

interface Driver:
    func info() -> DriverInfo
    func probe(dev: HwDevice) -> bool
    func attach(dev: HwDevice)
    func detach(dev: HwDevice)
    func status(dev: HwDevice) -> str

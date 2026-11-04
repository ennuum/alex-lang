# alex: native
# ALEX STANDARD LIBRARY — storage_driver
#
# Pilotes de stockage d'un noyau Alex (--freestanding) :
#
# | Module                          | Contenu                                                           |
# |---------------------------------|-------------------------------------------------------------------|
# | storage_driver.block_device     | interface BlockDevice, RamDisk, Partition, BlockCache, accès octet |
# | storage_driver.disk             | Disk : tables MBR / GPT, write_mbr                                 |
# | storage_driver.ata              | IDE / ATA en PIO (LBA28 / LBA48), AtaDriver                        |
# | storage_driver.ahci             | SATA AHCI (DMA, FIS, PRDT), AhciDriver                             |
# | storage_driver.nvme             | NVMe (files admin / E/S, PRP), NvmeDriver                          |
# | storage_driver.storage_queue    | file de requêtes : ascenseur, fusion, barrières                    |
#
#   use storage_driver
#   disques := storage_driver.discover()          # tous les disques des contrôleurs PCI reconnus
#   for d in disques:
#       print(block_device.describe(d))
#
# Compilable en natif (# alex: native). Dans la VM, RamDisk, Partition, BlockCache, Disk et la file
# fonctionnent sur la RAM simulée de hw.

from collections use append
use pci.pci_config as cfg
use pci.pci_bus as pbus
from pci.pci_bus use PciBus
use driver.driver_manager as dmg
from driver.driver_manager use DriverManager
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice
use storage_driver.ata as ata
from storage_driver.ata use AtaDriver
use storage_driver.ahci as ahci
from storage_driver.ahci use AhciDriver
use storage_driver.nvme as nvme
from storage_driver.nvme use NvmeDriver

class StorageStack:
    manager: DriverManager
    ata_driver: AtaDriver
    ahci_driver: AhciDriver
    nvme_driver: NvmeDriver

    func init():
        self.manager = DriverManager()
        self.ata_driver = AtaDriver()
        self.ahci_driver = AhciDriver()
        self.nvme_driver = NvmeDriver()
        self.manager.register(self.nvme_driver)
        self.manager.register(self.ahci_driver)
        self.manager.register(self.ata_driver)

    # Énumère le bus PCI, lie les contrôleurs de stockage ; renvoie les disques trouvés.
    func discover(bus: PciBus) -> list[BlockDevice]:
        self.manager.add_pci_bus(bus)
        self.manager.bind_all()
        return self.disks()

    func disks() -> list[BlockDevice]:
        out: list[BlockDevice] := []
        for d in self.nvme_driver.namespaces():
            append(out, d)
        for d in self.ahci_driver.disks():
            append(out, d)
        for d in self.ata_driver.disks():
            append(out, d)
        return out

    func report() -> str:
        return self.manager.report()

# Pile de stockage sur le bus PCI (mécanisme des ports 0xCF8) ; renvoie la pile, ses disques dans disks().
func stack() -> StorageStack:
    s := StorageStack()
    s.discover(PciBus(cfg.PortConfig()))
    return s

func discover() -> list[BlockDevice]:
    return stack().disks()

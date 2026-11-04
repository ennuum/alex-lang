# alex: native
#
# ALEX STANDARD LIBRARY — pci.pci_config
#
# Espace de configuration PCI : l'accès aux registres de configuration de chaque fonction (bus, emplacement,
# fonction, décalage), derrière une interface commune ConfigAccess, et les constantes des registres.
#
#   PortConfig    mécanisme n° 1 des PC (ports 0xCF8 / 0xCFC) : 256 octets par fonction, tous les PC et QEMU ;
#   EcamConfig    PCI Express « ECAM » (MMIO, 4096 octets par fonction) : adresse de base donnée par la table
#                 ACPI MCFG (QEMU q35 : 0xB0000000) ;
#   (pci.pci : SysfsConfig, l'espace de configuration lu dans /sys sous Linux, sans privilège pour 64 octets.)
#
#   use pci.pci_config as cfg
#   c := cfg.PortConfig()
#   v := c.read32(0, 3, 0, cfg.VENDOR_ID)          # (device << 16) | vendor
#   print(cfg.read16(c, 0, 3, 0, cfg.COMMAND))
#
# Module du sous-ensemble natif, à utiliser avec --freestanding (noyau) ou dans la VM (machine simulée de hw).

use hw

# ---- registres (en-tête commun) ----
const VENDOR_ID := 0x00
const DEVICE_ID := 0x02
const COMMAND := 0x04
const STATUS := 0x06
const REVISION := 0x08
const PROG_IF := 0x09
const SUBCLASS := 0x0A
const CLASS := 0x0B
const CACHE_LINE := 0x0C
const LATENCY := 0x0D
const HEADER_TYPE := 0x0E
const BIST := 0x0F
const BAR0 := 0x10
# en-tête de type 0 (périphérique)
const CARDBUS_CIS := 0x28
const SUBSYSTEM_VENDOR := 0x2C
const SUBSYSTEM_ID := 0x2E
const EXPANSION_ROM := 0x30
const CAPABILITIES := 0x34
const INTERRUPT_LINE := 0x3C
const INTERRUPT_PIN := 0x3D
const MIN_GRANT := 0x3E
const MAX_LATENCY := 0x3F
# en-tête de type 1 (pont PCI-PCI)
const PRIMARY_BUS := 0x18
const SECONDARY_BUS := 0x19
const SUBORDINATE_BUS := 0x1A
const IO_BASE := 0x1C
const MEMORY_BASE := 0x20
const BRIDGE_CONTROL := 0x3E

# ---- bits du registre COMMAND ----
const CMD_IO := 0x0001
const CMD_MEMORY := 0x0002
const CMD_BUS_MASTER := 0x0004
const CMD_SPECIAL := 0x0008
const CMD_MWI := 0x0010
const CMD_PARITY := 0x0040
const CMD_SERR := 0x0100
const CMD_INTX_DISABLE := 0x0400

# ---- bits du registre STATUS ----
const STATUS_INTERRUPT := 0x0008
const STATUS_CAPABILITIES := 0x0010
const STATUS_66MHZ := 0x0020

# ---- identifiants de capacités ----
const CAP_PM := 0x01
const CAP_AGP := 0x02
const CAP_VPD := 0x03
const CAP_MSI := 0x05
const CAP_PCIX := 0x07
const CAP_VENDOR := 0x09
const CAP_DEBUG := 0x0A
const CAP_HOTPLUG := 0x0C
const CAP_SUBSYSTEM := 0x0D
const CAP_PCIE := 0x10
const CAP_MSIX := 0x11
const CAP_SATA := 0x12

const PORT_ADDRESS := 0xCF8
const PORT_DATA := 0xCFC

interface ConfigAccess:
    func read32(bus: int, dev: int, fn: int, offset: int) -> int
    func write32(bus: int, dev: int, fn: int, offset: int, value: int)

# Mécanisme de configuration n° 1 (ports 0xCF8 / 0xCFC) : décalages 0..255, alignés sur 4 octets.
class PortConfig implements ConfigAccess:
    calls: int := 0

    func init():
        self.calls = 0

    func _select(bus: int, dev: int, fn: int, offset: int):
        hw.outl(PORT_ADDRESS, 0x80000000 | ((bus & 255) << 16) | ((dev & 31) << 11) | ((fn & 7) << 8) | (offset & 0xFC))

    func read32(bus: int, dev: int, fn: int, offset: int) -> int:
        self.calls += 1
        if offset < 0 or offset > 255:
            return 0xFFFFFFFF
        self._select(bus, dev, fn, offset)
        return hw.inl(PORT_DATA)

    func write32(bus: int, dev: int, fn: int, offset: int, value: int):
        self.calls += 1
        if offset < 0 or offset > 255:
            return
        self._select(bus, dev, fn, offset)
        hw.outl(PORT_DATA, value & 0xFFFFFFFF)

# PCI Express ECAM : 4096 octets par fonction, à base + (bus << 20 | dev << 15 | fn << 12), à partir du bus
# start_bus. base : adresse PHYSIQUE (table ACPI MCFG).
class EcamConfig implements ConfigAccess:
    base: int := 0
    start_bus: int := 0
    end_bus: int := 255

    func init(base: int, start_bus: int, end_bus: int):
        self.base = base
        self.start_bus = start_bus
        self.end_bus = end_bus

    func _addr(bus: int, dev: int, fn: int, offset: int) -> int:
        return hw.mmio(self.base + (((bus - self.start_bus) & 255) << 20) + ((dev & 31) << 15) + ((fn & 7) << 12) + (offset & 0xFFC))

    func read32(bus: int, dev: int, fn: int, offset: int) -> int:
        if bus < self.start_bus or bus > self.end_bus or offset < 0 or offset > 4095:
            return 0xFFFFFFFF
        return hw.peek32(self._addr(bus, dev, fn, offset))

    func write32(bus: int, dev: int, fn: int, offset: int, value: int):
        if bus < self.start_bus or bus > self.end_bus or offset < 0 or offset > 4095:
            return
        hw.poke32(self._addr(bus, dev, fn, offset), value & 0xFFFFFFFF)

# ---- accès de 8 et 16 bits (lecture du mot de 32 bits, écriture lecture-modification-écriture) ----
func read16(c: ConfigAccess, bus: int, dev: int, fn: int, offset: int) -> int:
    return (c.read32(bus, dev, fn, offset & 0xFFC) >> (8 * (offset & 2))) & 0xFFFF

func read8(c: ConfigAccess, bus: int, dev: int, fn: int, offset: int) -> int:
    return (c.read32(bus, dev, fn, offset & 0xFFC) >> (8 * (offset & 3))) & 0xFF

func write16(c: ConfigAccess, bus: int, dev: int, fn: int, offset: int, value: int):
    shift := 8 * (offset & 2)
    old := c.read32(bus, dev, fn, offset & 0xFFC)
    c.write32(bus, dev, fn, offset & 0xFFC, (old & ~(0xFFFF << shift)) | ((value & 0xFFFF) << shift))

func write8(c: ConfigAccess, bus: int, dev: int, fn: int, offset: int, value: int):
    shift := 8 * (offset & 3)
    old := c.read32(bus, dev, fn, offset & 0xFFC)
    c.write32(bus, dev, fn, offset & 0xFFC, (old & ~(0xFF << shift)) | ((value & 0xFF) << shift))

# Vrai si une fonction répond à cette adresse (identifiant de fabricant différent de 0xFFFF).
func present(c: ConfigAccess, bus: int, dev: int, fn: int) -> bool:
    v := c.read32(bus, dev, fn, 0) & 0xFFFF
    return v != 0xFFFF and v != 0

# Vrai si le mécanisme n° 1 fonctionne sur cette machine (registre d'adresse relu à l'identique).
func port_mechanism_present() -> bool:
    old := hw.inl(PORT_ADDRESS)
    hw.outl(PORT_ADDRESS, 0x80000000)
    ok := hw.inl(PORT_ADDRESS) == 0x80000000
    hw.outl(PORT_ADDRESS, old)
    return ok

# alex: native
#
# ALEX STANDARD LIBRARY — pci.pci_capability
#
# Capacités PCI en détail (la liste brute est donnée par PciDevice.capabilities()) :
#   gestion d'énergie   état D0..D3hot, changement d'état, PME
#   MSI                 nombre de messages demandés / alloués, 64 bits, masquage par vecteur, activation
#   MSI-X               taille de la table, BAR et décalage de la table et du PBA, programmation d'une entrée
#                       (adresse, donnée, masque) dans la table en MMIO, activation, masquage global
#   PCI Express         genre de port, version, vitesse et largeur du lien négociées et maximales
#   étendues (ECAM)     liste des capacités étendues (décalage 0x100 et suivants : AER, SR-IOV...)
#
#   use pci.pci_capability as pc
#   pm := pc.power(dev)                         # PowerManagement, ou null
#   pm.set_state(0)                             # D0
#   m := pc.msi(dev)
#   print(m.requested_vectors(), m.is64())
#   x := pc.msix(dev)
#   x.program(0, 0xFEE0_0000, 0x41, false)      # entrée 0 -> vecteur 0x41, démasquée
#   x.enable(true)
#   e := pc.pcie(dev)
#   print(e.port_type_name(), e.link_speed_name(), e.link_width())
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from core use len
from collections use append
use hw
use pci.pci_config as cfg
use pci.pci_device as pd
from pci.pci_device use PciDevice

# ---- gestion d'énergie ----
class PowerManagement:
    dev: PciDevice
    offset: int := 0

    func init(dev: PciDevice, offset: int):
        self.dev = dev
        self.offset = offset

    func version() -> int:
        return self.dev.read16(self.offset + 2) & 7

    func state() -> int:
        return self.dev.read16(self.offset + 4) & 3

    func state_name() -> str:
        return "D" + str(self.state())

    # Passe en D0 / D1 / D2 / D3hot (le délai de 10 ms après D3hot est à la charge de l'appelant).
    func set_state(d: int):
        if d < 0 or d > 3:
            raise("PciCapabilityError", "gestion d'énergie : état D0 à D3 attendu")
        v := self.dev.read16(self.offset + 4)
        self.dev.write16(self.offset + 4, (v & ~3) | d)

    func pme_supported() -> int:
        return (self.dev.read16(self.offset + 2) >> 11) & 0x1F

    func pme_status() -> bool:
        return (self.dev.read16(self.offset + 4) & 0x8000) != 0

    func clear_pme():
        v := self.dev.read16(self.offset + 4)
        self.dev.write16(self.offset + 4, v | 0x8000)

func power(dev: PciDevice) -> PowerManagement?:
    off := dev.find_capability(cfg.CAP_PM)
    if off == 0:
        return null
    return PowerManagement(dev, off)

# ---- MSI ----
class Msi:
    dev: PciDevice
    offset: int := 0

    func init(dev: PciDevice, offset: int):
        self.dev = dev
        self.offset = offset

    func control() -> int:
        return self.dev.read16(self.offset + 2)

    func is64() -> bool:
        return (self.control() & 0x80) != 0

    func per_vector_mask() -> bool:
        return (self.control() & 0x100) != 0

    func requested_vectors() -> int:
        return 1 << ((self.control() >> 1) & 7)

    func allocated_vectors() -> int:
        return 1 << ((self.control() >> 4) & 7)

    func enabled() -> bool:
        return (self.control() & 1) != 0

    # Programme adresse et donnée, alloue 2^log2 vecteurs (au plus ceux demandés).
    func configure(address: int, data: int, log2_vectors: int = 0):
        c := self.control()
        req := (c >> 1) & 7
        n := log2_vectors
        if n > req:
            n = req
        self.dev.write32(self.offset + 4, address & 0xFFFFFFFF)
        if self.is64():
            self.dev.write32(self.offset + 8, (address >> 32) & 0xFFFFFFFF)
            self.dev.write16(self.offset + 12, data)
        else:
            self.dev.write16(self.offset + 8, data)
        self.dev.write16(self.offset + 2, (c & ~0x70) | (n << 4))

    func enable(on: bool):
        c := self.control()
        if on:
            self.dev.write16(self.offset + 2, c | 1)
            self.dev.disable_intx()
        else:
            self.dev.write16(self.offset + 2, c & ~1)

    func address() -> int:
        a := self.dev.read32(self.offset + 4)
        if self.is64():
            a = a | (self.dev.read32(self.offset + 8) << 32)
        return a

    func data() -> int:
        if self.is64():
            return self.dev.read16(self.offset + 12)
        return self.dev.read16(self.offset + 8)

    func _mask_offset() -> int:
        if self.is64():
            return self.offset + 16
        return self.offset + 12

    # Masque (ou démasque) le vecteur v si le masquage par vecteur existe ; false sinon.
    func mask_vector(v: int, masked: bool) -> bool:
        if not self.per_vector_mask():
            return false
        m := self.dev.read32(self._mask_offset())
        if masked:
            m = m | (1 << v)
        else:
            m = m & ~(1 << v)
        self.dev.write32(self._mask_offset(), m)
        return true

func msi(dev: PciDevice) -> Msi?:
    off := dev.find_capability(cfg.CAP_MSI)
    if off == 0:
        return null
    return Msi(dev, off)

# ---- MSI-X ----
class MsiX:
    dev: PciDevice
    offset: int := 0

    func init(dev: PciDevice, offset: int):
        self.dev = dev
        self.offset = offset

    func control() -> int:
        return self.dev.read16(self.offset + 2)

    func table_size() -> int:
        return (self.control() & 0x7FF) + 1

    func table_bar() -> int:
        return self.dev.read32(self.offset + 4) & 7

    func table_offset() -> int:
        return self.dev.read32(self.offset + 4) & ~7

    func pba_bar() -> int:
        return self.dev.read32(self.offset + 8) & 7

    func pba_offset() -> int:
        return self.dev.read32(self.offset + 8) & ~7

    func enabled() -> bool:
        return (self.control() & 0x8000) != 0

    func enable(on: bool):
        c := self.control()
        if on:
            self.dev.write16(self.offset + 2, c | 0x8000)
            self.dev.disable_intx()
        else:
            self.dev.write16(self.offset + 2, c & ~0x8000)

    func mask_all(masked: bool):
        c := self.control()
        if masked:
            self.dev.write16(self.offset + 2, c | 0x4000)
        else:
            self.dev.write16(self.offset + 2, c & ~0x4000)

    # Adresse physique de l'entrée i de la table (16 octets par entrée).
    func entry_address(i: int) -> int:
        if i < 0 or i >= self.table_size():
            raise("PciCapabilityError", "MSI-X : entrée " + str(i) + " hors de la table (" + str(self.table_size()) + ")")
        self.dev.enable_memory()
        return self.dev.bar_address(self.table_bar()) + self.table_offset() + 16 * i

    func program(i: int, address: int, data: int, masked: bool):
        a := self.entry_address(i)
        hw.poke32(a, address & 0xFFFFFFFF)
        hw.poke32(a + 4, (address >> 32) & 0xFFFFFFFF)
        hw.poke32(a + 8, data & 0xFFFFFFFF)
        ctl := 0
        if masked:
            ctl = 1
        hw.poke32(a + 12, ctl)

    func entry(i: int) -> list[int]:
        a := self.entry_address(i)
        return [hw.peek32(a) | (hw.peek32(a + 4) << 32), hw.peek32(a + 8), hw.peek32(a + 12) & 1]

    func pending(i: int) -> bool:
        self.dev.enable_memory()
        base := self.dev.bar_address(self.pba_bar()) + self.pba_offset()
        word := hw.peek64(base + 8 * (i // 64))
        return ((word >> (i % 64)) & 1) != 0

func msix(dev: PciDevice) -> MsiX?:
    off := dev.find_capability(cfg.CAP_MSIX)
    if off == 0:
        return null
    return MsiX(dev, off)

# ---- PCI Express ----
class PciExpress:
    dev: PciDevice
    offset: int := 0

    func init(dev: PciDevice, offset: int):
        self.dev = dev
        self.offset = offset

    func version() -> int:
        return self.dev.read16(self.offset + 2) & 0xF

    func port_type() -> int:
        return (self.dev.read16(self.offset + 2) >> 4) & 0xF

    func port_type_name() -> str:
        match self.port_type():
            0:
                return "point de terminaison"
            1:
                return "point de terminaison hérité"
            4:
                return "port racine"
            5:
                return "port amont de commutateur"
            6:
                return "port aval de commutateur"
            7:
                return "pont PCIe vers PCI"
            8:
                return "pont PCI vers PCIe"
            9:
                return "point de terminaison intégré"
            10:
                return "collecteur d'événements"
            _:
                return "genre " + str(self.port_type())

    func link_capabilities() -> int:
        return self.dev.read32(self.offset + 0x0C)

    func link_status() -> int:
        return self.dev.read16(self.offset + 0x12)

    func max_link_speed() -> int:
        return self.link_capabilities() & 0xF

    func max_link_width() -> int:
        return (self.link_capabilities() >> 4) & 0x3F

    func link_speed() -> int:
        return self.link_status() & 0xF

    func link_width() -> int:
        return (self.link_status() >> 4) & 0x3F

    func link_speed_name() -> str:
        return speed_name(self.link_speed())

    func max_payload() -> int:
        return 128 << (self.dev.read32(self.offset + 4) & 7)

func speed_name(code: int) -> str:
    match code:
        1:
            return "2,5 GT/s"
        2:
            return "5 GT/s"
        3:
            return "8 GT/s"
        4:
            return "16 GT/s"
        5:
            return "32 GT/s"
        6:
            return "64 GT/s"
        _:
            return "inconnue"

func pcie(dev: PciDevice) -> PciExpress?:
    off := dev.find_capability(cfg.CAP_PCIE)
    if off == 0:
        return null
    return PciExpress(dev, off)

# ---- capacités étendues (espace de configuration de 4 Kio, ECAM) ----
class ExtendedCapability:
    id: int := 0
    version: int := 0
    offset: int := 0

    func init(id: int, version: int, offset: int):
        self.id = id
        self.version = version
        self.offset = offset

    func name() -> str:
        return extended_name(self.id)

func extended_name(id: int) -> str:
    match id:
        1:
            return "AER (rapport d'erreurs avancé)"
        2:
            return "canal virtuel"
        3:
            return "numéro de série"
        4:
            return "budget d'énergie"
        11:
            return "spécifique au fabricant"
        13:
            return "ACS (contrôle d'accès)"
        14:
            return "ARI"
        16:
            return "SR-IOV"
        21:
            return "BAR redimensionnable"
        23:
            return "TPH"
        24:
            return "LTR"
        _:
            return "capacité étendue " + str(id)

# Capacités étendues (vide sans espace étendu : accès par ports, ou fonction PCI classique).
func extended(dev: PciDevice) -> list[ExtendedCapability]:
    out: list[ExtendedCapability] := []
    off := 0x100
    guard := 0
    while off >= 0x100 and off < 0x1000 and guard < 64:
        h := dev.read32(off)
        if h == 0 or h == 0xFFFFFFFF:
            return out
        append(out, ExtendedCapability(h & 0xFFFF, (h >> 16) & 0xF, off))
        off = (h >> 20) & 0xFFC
        guard += 1
    return out

func summary(dev: PciDevice) -> list[str]:
    out: list[str] := []
    for c in dev.capabilities():
        append(out, pd.capability_name(c.id) + " @0x" + str(c.offset))
    return out

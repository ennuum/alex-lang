# alex: native
#
# ALEX STANDARD LIBRARY — pci.pci_device
#
# PciDevice : une fonction PCI identifiée (bus, emplacement, fonction) — identifiants, classe, en-tête, ligne
# d'interruption — avec ses registres de base (BAR : ports ou mémoire, adresse, TAILLE mesurée, 64 bits,
# préchargeable), sa liste de capacités (MSI, MSI-X, PCI Express, gestion d'énergie...) et les réglages du
# registre de commande (décodage des ports / de la mémoire, maîtrise du bus pour le DMA, INTx).
#
#   use pci.pci_device as pd
#   d := pd.read_device(cfg, 0, 3, 0)            # null si l'emplacement est vide
#   print(d.location(), d.name(), d.class_name())  # 00:03.0 82540EM Gigabit Ethernet ... Ethernet
#   for b in d.bars():
#       print(b.describe())                        # BAR0 mémoire 0xfebc0000 (128 Kio)
#   d.enable_memory()
#   d.enable_bus_master()
#   if d.find_capability(pci_config.CAP_MSI) != 0: ...
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from collections use append
use pci.pci_config as cfg
from pci.pci_config use ConfigAccess
use pci.pci_ids as ids

class Bar:
    index: int := 0
    is_io: bool := false
    address: int := 0
    size: int := 0
    prefetchable: bool := false
    is64: bool := false

    func init(index: int, is_io: bool, address: int, size: int, prefetchable: bool, is64: bool):
        self.index = index
        self.is_io = is_io
        self.address = address
        self.size = size
        self.prefetchable = prefetchable
        self.is64 = is64

    func describe() -> str:
        kind := "mémoire"
        if self.is_io:
            kind = "ports"
        t := "BAR" + str(self.index) + " " + kind + " 0x" + ids.hex32(self.address & 0xFFFFFFFF)
        if self.address > 0xFFFFFFFF:
            t = "BAR" + str(self.index) + " " + kind + " 0x" + ids.hex32(self.address >> 32) + ids.hex32(self.address & 0xFFFFFFFF)
        t = t + " (" + size_text(self.size) + ")"
        if self.is64:
            t = t + " 64 bits"
        if self.prefetchable:
            t = t + " préchargeable"
        return t

func size_text(n: int) -> str:
    if n >= 1073741824 and n % 1073741824 == 0:
        return str(n // 1073741824) + " Gio"
    if n >= 1048576 and n % 1048576 == 0:
        return str(n // 1048576) + " Mio"
    if n >= 1024 and n % 1024 == 0:
        return str(n // 1024) + " Kio"
    return str(n) + " o"

class Capability:
    id: int := 0
    offset: int := 0

    func init(id: int, offset: int):
        self.id = id
        self.offset = offset

    func name() -> str:
        return capability_name(self.id)

func capability_name(id: int) -> str:
    match id:
        1:
            return "gestion d'énergie"
        2:
            return "AGP"
        3:
            return "VPD"
        5:
            return "MSI"
        7:
            return "PCI-X"
        9:
            return "spécifique au fabricant"
        10:
            return "port de débogage"
        12:
            return "branchement à chaud"
        13:
            return "identifiant de sous-système"
        16:
            return "PCI Express"
        17:
            return "MSI-X"
        18:
            return "SATA"
        _:
            return "capacité " + ids.hex8(id)
    return "?"

class PciDevice:
    config: ConfigAccess
    bus: int := 0
    slot: int := 0
    fn: int := 0
    vendor: int := 0
    device: int := 0
    cls: int := 0
    subclass: int := 0
    prog_if: int := 0
    revision: int := 0
    header_type: int := 0
    subsystem_vendor: int := 0
    subsystem_id: int := 0
    irq_line: int := 0
    irq_pin: int := 0

    func init(config: ConfigAccess, bus: int, slot: int, fn: int):
        self.config = config
        self.bus = bus
        self.slot = slot
        self.fn = fn
        self.refresh()

    # Relit l'en-tête.
    func refresh():
        id := self.read32(0)
        self.vendor = id & 0xFFFF
        self.device = (id >> 16) & 0xFFFF
        c := self.read32(8)
        self.revision = c & 0xFF
        self.prog_if = (c >> 8) & 0xFF
        self.subclass = (c >> 16) & 0xFF
        self.cls = (c >> 24) & 0xFF
        self.header_type = self.read8(cfg.HEADER_TYPE)
        if self.header_kind() == 0:
            s := self.read32(cfg.SUBSYSTEM_VENDOR)
            self.subsystem_vendor = s & 0xFFFF
            self.subsystem_id = (s >> 16) & 0xFFFF
        il := self.read32(cfg.INTERRUPT_LINE)
        self.irq_line = il & 0xFF
        self.irq_pin = (il >> 8) & 0xFF

    func read32(offset: int) -> int:
        return self.config.read32(self.bus, self.slot, self.fn, offset)

    func read16(offset: int) -> int:
        return cfg.read16(self.config, self.bus, self.slot, self.fn, offset)

    func read8(offset: int) -> int:
        return cfg.read8(self.config, self.bus, self.slot, self.fn, offset)

    func write32(offset: int, value: int):
        self.config.write32(self.bus, self.slot, self.fn, offset, value)

    func write16(offset: int, value: int):
        cfg.write16(self.config, self.bus, self.slot, self.fn, offset, value)

    func write8(offset: int, value: int):
        cfg.write8(self.config, self.bus, self.slot, self.fn, offset, value)

    # 0 : périphérique, 1 : pont PCI-PCI, 2 : pont CardBus.
    func header_kind() -> int:
        return self.header_type & 0x7F

    func is_multifunction() -> bool:
        return (self.header_type & 0x80) != 0

    func is_bridge() -> bool:
        return self.header_kind() == 1

    # « bb:ss.f » (hexadécimal, comme lspci).
    func location() -> str:
        return ids.hex8(self.bus) + ":" + ids.hex8(self.slot) + "." + str(self.fn)

    func id_text() -> str:
        return ids.hex16(self.vendor) + ":" + ids.hex16(self.device)

    func vendor_name() -> str:
        return ids.vendor_name(self.vendor)

    func name() -> str:
        return ids.device_name(self.vendor, self.device)

    func class_name() -> str:
        return ids.class_name(self.cls, self.subclass, self.prog_if)

    func class_code() -> int:
        return (self.cls << 16) | (self.subclass << 8) | self.prog_if

    func is_class(cls: int, subclass: int) -> bool:
        return self.cls == cls and self.subclass == subclass

    # Ligne façon lspci : « 00:03.0 Ethernet [0200]: Intel 82540EM ... [8086:100e] (rev 03) »
    func describe() -> str:
        return self.location() + " " + self.class_name() + " [" + ids.hex8(self.cls) + ids.hex8(self.subclass) + "]: " + self.vendor_name() + " " + self.name() + " [" + self.id_text() + "] (rev " + ids.hex8(self.revision) + ")"

    # ---- registre de commande ----
    func command() -> int:
        return self.read16(cfg.COMMAND)

    func set_command_bits(bits: int, on: bool):
        c := self.command()
        if on:
            c = c | bits
        else:
            c = c & ~bits
        self.write16(cfg.COMMAND, c)

    func enable_io():
        self.set_command_bits(cfg.CMD_IO, true)

    func enable_memory():
        self.set_command_bits(cfg.CMD_MEMORY, true)

    # Autorise le périphérique à lire et écrire la mémoire (DMA).
    func enable_bus_master():
        self.set_command_bits(cfg.CMD_BUS_MASTER, true)

    func disable_intx():
        self.set_command_bits(cfg.CMD_INTX_DISABLE, true)

    func enable_intx():
        self.set_command_bits(cfg.CMD_INTX_DISABLE, false)

    # Ports, mémoire et DMA : ce que la plupart des pilotes demandent.
    func enable():
        self.set_command_bits(cfg.CMD_IO | cfg.CMD_MEMORY | cfg.CMD_BUS_MASTER, true)

    func status() -> int:
        return self.read16(cfg.STATUS)

    # ---- registres de base ----
    func bar_count() -> int:
        k := self.header_kind()
        if k == 0:
            return 6
        if k == 1:
            return 2
        return 0

    # Valeur brute (adresse sans les bits d'attributs) du registre n, sans mesurer sa taille.
    func bar_address(n: int) -> int:
        v := self.read32(cfg.BAR0 + 4 * n)
        if (v & 1) != 0:
            return v & 0xFFFFFFFC
        addr := v & 0xFFFFFFF0
        if ((v >> 1) & 3) == 2 and n + 1 < self.bar_count():
            addr = addr | (self.read32(cfg.BAR0 + 4 * (n + 1)) << 32)
        return addr

    # Registres de base, avec leur taille mesurée (écriture de 1 partout puis restauration ; le décodage est
    # coupé pendant la mesure). Les registres vides sont omis.
    func bars() -> list[Bar]:
        out: list[Bar] := []
        cmd := self.command()
        self.write16(cfg.COMMAND, cmd & ~(cfg.CMD_IO | cfg.CMD_MEMORY))
        n := 0
        count := self.bar_count()
        while n < count:
            off := cfg.BAR0 + 4 * n
            orig := self.read32(off)
            self.write32(off, 0xFFFFFFFF)
            probe := self.read32(off)
            self.write32(off, orig)
            if (orig & 1) != 0:
                mask := probe & 0xFFFFFFFC
                if mask != 0:
                    size := ((~mask) & 0xFFFF) + 1
                    append(out, Bar(n, true, orig & 0xFFFFFFFC, size, false, false))
                n += 1
                continue
            kind := (orig >> 1) & 3
            pref := (orig & 8) != 0
            if kind == 2 and n + 1 < count:
                off2 := off + 4
                orig2 := self.read32(off2)
                self.write32(off2, 0xFFFFFFFF)
                probe2 := self.read32(off2)
                self.write32(off2, orig2)
                mask64 := ((probe2 & 0xFFFFFFFF) << 32) | (probe & 0xFFFFFFF0)
                if mask64 != 0:
                    size64 := (~mask64) + 1
                    append(out, Bar(n, false, ((orig2 & 0xFFFFFFFF) << 32) | (orig & 0xFFFFFFF0), size64, pref, true))
                n += 2
                continue
            mask32 := probe & 0xFFFFFFF0
            if mask32 != 0:
                size32 := ((~mask32) & 0xFFFFFFFF) + 1
                append(out, Bar(n, false, orig & 0xFFFFFFF0, size32, pref, false))
            n += 1
        self.write16(cfg.COMMAND, cmd)
        return out

    # ---- capacités ----
    func capabilities() -> list[Capability]:
        out: list[Capability] := []
        if (self.status() & cfg.STATUS_CAPABILITIES) == 0:
            return out
        ptr := self.read8(cfg.CAPABILITIES) & 0xFC
        guard := 0
        while ptr >= 0x40 and guard < 48:
            id := self.read8(ptr)
            append(out, Capability(id, ptr))
            ptr = self.read8(ptr + 1) & 0xFC
            guard += 1
        return out

    # Décalage de la capacité id, ou 0 si absente.
    func find_capability(id: int) -> int:
        for c in self.capabilities():
            if c.id == id:
                return c.offset
        return 0

    # Configure MSI (si présent) : message (adresse, donnée) ; renvoie false sans capacité MSI.
    func configure_msi(address: int, data: int) -> bool:
        off := self.find_capability(cfg.CAP_MSI)
        if off == 0:
            return false
        ctrl := self.read16(off + 2)
        self.write32(off + 4, address & 0xFFFFFFFF)
        if (ctrl & 0x80) != 0:
            self.write32(off + 8, (address >> 32) & 0xFFFFFFFF)
            self.write16(off + 12, data)
        else:
            self.write16(off + 8, data)
        self.write16(off + 2, (ctrl & ~0x70) | 1)
        self.disable_intx()
        return true

    # Pont : [bus primaire, secondaire, subordonné].
    func bridge_buses() -> list[int]:
        v := self.read32(cfg.PRIMARY_BUS)
        return [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF]

# Fonction à cette adresse, ou null si l'emplacement est vide.
func read_device(c: ConfigAccess, bus: int, slot: int, fn: int) -> PciDevice?:
    if not cfg.present(c, bus, slot, fn):
        return null
    return PciDevice(c, bus, slot, fn)

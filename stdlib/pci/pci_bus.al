# alex: native
#
# ALEX STANDARD LIBRARY — pci.pci_bus
#
# Énumération du bus PCI : toutes les fonctions présentes, en descendant derrière les ponts PCI-PCI (bus
# secondaires), plusieurs bus hôtes compris ; recherche par identifiants ou par classe ; arborescence.
#
#   use pci.pci_config as cfg
#   use pci.pci_bus as bus
#   b := bus.PciBus(cfg.PortConfig())
#   devs := b.scan()
#   for d in devs:
#       print(d.describe())
#   nic := b.find(0x8086, 0x100E)                 # PciDevice? (null : absent)
#   disques := b.find_class(0x01, 0x06)           # contrôleurs SATA
#   print(b.tree())
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from collections use append, contains_key
use pci.pci_config as cfg
from pci.pci_config use ConfigAccess
use pci.pci_device as pd
from pci.pci_device use PciDevice
use pci.pci_ids as ids

class PciBus:
    config: ConfigAccess
    devices: list[PciDevice] := []
    scanned: bool := false

    func init(config: ConfigAccess):
        self.config = config
        self.devices = []
        self.scanned = false

    # Énumère (une seule fois ; rescan() pour recommencer) et renvoie toutes les fonctions.
    func scan() -> list[PciDevice]:
        if self.scanned:
            return self.devices
        self.devices = []
        seen: dict[int, bool] := {}
        host := pd.read_device(self.config, 0, 0, 0)
        multi := false
        if host != null:
            multi = host.is_multifunction()
        if multi:
            # Plusieurs contrôleurs hôtes : la fonction f de 00:00 décrit le bus hôte f.
            f := 0
            while f < 8:
                if cfg.present(self.config, 0, 0, f):
                    self._scan_bus(f, seen)
                f += 1
        else:
            self._scan_bus(0, seen)
        self.scanned = true
        return self.devices

    func rescan() -> list[PciDevice]:
        self.scanned = false
        return self.scan()

    func _scan_bus(bus: int, seen: dict[int, bool]):
        if contains_key(seen, bus) or bus > 255:
            return
        seen[bus] = true
        slot := 0
        while slot < 32:
            self._scan_slot(bus, slot, seen)
            slot += 1

    func _scan_slot(bus: int, slot: int, seen: dict[int, bool]):
        first := pd.read_device(self.config, bus, slot, 0)
        if first == null:
            return
        self._add(first, seen)
        if not first.is_multifunction():
            return
        fn := 1
        while fn < 8:
            d := pd.read_device(self.config, bus, slot, fn)
            if d != null:
                self._add(d, seen)
            fn += 1

    func _add(d: PciDevice, seen: dict[int, bool]):
        append(self.devices, d)
        if d.is_bridge() and d.subclass == 4:
            buses := d.bridge_buses()
            if buses[1] != 0:
                self._scan_bus(buses[1], seen)

    # Première fonction (fabricant, périphérique), ou null.
    func find(vendor: int, device: int) -> PciDevice?:
        for d in self.scan():
            if d.vendor == vendor and d.device == device:
                return d
        return null

    # Toutes les fonctions d'une classe / sous-classe (prog_if hors de 0..255 : n'importe laquelle).
    func find_class(cls: int, subclass: int, prog_if: int = 256) -> list[PciDevice]:
        out: list[PciDevice] := []
        for d in self.scan():
            if d.cls == cls and d.subclass == subclass and (prog_if < 0 or prog_if > 255 or d.prog_if == prog_if):
                append(out, d)
        return out

    func find_vendor(vendor: int) -> list[PciDevice]:
        out: list[PciDevice] := []
        for d in self.scan():
            if d.vendor == vendor:
                append(out, d)
        return out

    func at(bus: int, slot: int, fn: int) -> PciDevice?:
        for d in self.scan():
            if d.bus == bus and d.slot == slot and d.fn == fn:
                return d
        return null

    func count() -> int:
        return len_of(self.scan())

    # Arborescence (ponts et leurs bus secondaires), une ligne par fonction.
    func tree() -> str:
        out := ""
        for d in self.scan():
            indent := ""
            k := 0
            while k < d.bus:
                indent = indent + "  "
                k += 1
            out = out + indent + d.location() + " " + d.class_name() + " : " + d.vendor_name() + " " + d.name() + "\n"
        return out

func len_of(xs: list[PciDevice]) -> int:
    n := 0
    for x in xs:
        n += 1
    return n

func scan(config: ConfigAccess) -> list[PciDevice]:
    return PciBus(config).scan()

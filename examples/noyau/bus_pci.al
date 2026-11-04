# Énumération du bus PCI par les ports de configuration 0xCF8 / 0xCFC.
use hw
from collections use append

class Device:
    bus: int := 0
    slot: int := 0
    fn: int := 0
    vendor: int := 0
    device: int := 0
    cls: int := 0
    subclass: int := 0

    func init(bus: int, slot: int, fn: int, vendor: int, device: int, cls: int, subclass: int):
        self.bus = bus
        self.slot = slot
        self.fn = fn
        self.vendor = vendor
        self.device = device
        self.cls = cls
        self.subclass = subclass

    func kind() -> str:
        match (self.cls, self.subclass):
            (1, 1):
                return "contrôleur IDE"
            (1, 0):
                return "contrôleur SCSI / virtio"
            (2, _):
                return "carte réseau"
            (3, _):
                return "carte graphique"
            (6, 0):
                return "pont hôte"
            (6, 1):
                return "pont ISA"
            (6, _):
                return "pont"
            _:
                return "classe " + str(self.cls)
        return "?"

func read32(bus: int, slot: int, fn: int, offset: int) -> int:
    hw.outl(3320, (1 << 31) | (bus << 16) | (slot << 11) | (fn << 8) | (offset & 252))
    return hw.inl(3324)

func hex4(v: int) -> str:
    digits := "0123456789abcdef"
    return str(digits[(v >> 12) & 15]) + str(digits[(v >> 8) & 15]) + str(digits[(v >> 4) & 15]) + str(digits[v & 15])

func scan() -> list[Device]:
    found: list[Device] := []
    for slot in 0..32:
        for fn in 0..8:
            id := read32(0, slot, fn, 0)
            if (id & 65535) == 65535:
                if fn == 0:
                    break
                continue
            cls := read32(0, slot, fn, 8)
            append(found, Device(0, slot, fn, id & 65535, (id >> 16) & 65535, (cls >> 24) & 255, (cls >> 16) & 255))
            if fn == 0 and ((read32(0, slot, 0, 12) >> 16) & 128) == 0:
                break
    return found

func write32(bus: int, slot: int, fn: int, offset: int, value: int):
    hw.outl(3320, (1 << 31) | (bus << 16) | (slot << 11) | (fn << 8) | (offset & 252))
    hw.outl(3324, value)

# Premier périphérique (vendor, device), ou null.
func find(vendor: int, device: int) -> Device?:
    for d in scan():
        if d.vendor == vendor and d.device == device:
            return d
    return null

# Registre de base n (BAR) : adresse de ports (bit 0 à 1) ou de mémoire, sans les bits d'attributs.
func bar(d: Device, n: int) -> int:
    v := read32(d.bus, d.slot, d.fn, 16 + 4 * n)
    if (v & 1) != 0:
        return v & 65532
    return v & 4294967280

# Autorise le périphérique à répondre sur ses ports et sa mémoire et à accéder à la mémoire (DMA).
func enable(d: Device):
    c := read32(d.bus, d.slot, d.fn, 4)
    write32(d.bus, d.slot, d.fn, 4, (c & 65535) | 7)

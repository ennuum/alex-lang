# alex: native
#
# ALEX STANDARD LIBRARY — pci.pci_bar
#
# Registres de base (BAR) d'une fonction PCI : décodage d'une valeur brute (genre ports / mémoire 32 / 64 bits,
# préchargeable, adresse), ACCÈS aux registres d'un périphérique à travers son BAR (BarWindow : lecture et
# écriture 8 / 16 / 32 bits en ports d'E/S ou en MMIO, bornées à la taille du BAR), PROGRAMMATION d'une adresse
# (alignement vérifié, 64 bits), et détection des recouvrements entre BAR.
#
#   use pci.pci_bar as pb
#   info := pb.decode(0xFEBC0004)                 # BarInfo : mémoire 64 bits, adresse 0xfebc0000
#   w := pb.window(dev, 0)                        # BarWindow sur le BAR0 mesuré
#   w.write32(0x0, 0x0400_0000)                   # registre CTRL d'une carte e1000
#   print(pb.hex(w.read32(0x8)))                  # STATUS
#   pb.assign(dev, 0, 0xE000_0000)                # place le BAR0 (aligné sur sa taille)
#   print(pb.overlaps(dev.bars()))                # [] : pas de recouvrement
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from core use len
from collections use append
use hw
use pci.pci_config as cfg
use pci.pci_device as pd
from pci.pci_device use PciDevice, Bar
use pci.pci_ids as ids

const KIND_IO := 0
const KIND_MEM32 := 1
const KIND_MEM64 := 2
const KIND_MEM1M := 3

class BarInfo:
    kind: int := 0
    address: int := 0
    prefetchable: bool := false

    func init(kind: int, address: int, prefetchable: bool):
        self.kind = kind
        self.address = address
        self.prefetchable = prefetchable

    func is_io() -> bool:
        return self.kind == KIND_IO

    func is64() -> bool:
        return self.kind == KIND_MEM64

    func kind_name() -> str:
        if self.kind == KIND_IO:
            return "ports"
        if self.kind == KIND_MEM64:
            return "mémoire 64 bits"
        if self.kind == KIND_MEM1M:
            return "mémoire < 1 Mio"
        return "mémoire 32 bits"

# Décode la valeur brute d'un registre BAR (32 bits de poids faible).
func decode(raw: int) -> BarInfo:
    if (raw & 1) != 0:
        return BarInfo(KIND_IO, raw & 0xFFFFFFFC, false)
    t := (raw >> 1) & 3
    kind := KIND_MEM32
    if t == 2:
        kind = KIND_MEM64
    elif t == 1:
        kind = KIND_MEM1M
    return BarInfo(kind, raw & 0xFFFFFFF0, (raw & 8) != 0)

func hex(v: int) -> str:
    if v > 0xFFFFFFFF:
        return "0x" + ids.hex32(v >> 32) + ids.hex32(v & 0xFFFFFFFF)
    return "0x" + ids.hex32(v & 0xFFFFFFFF)

func find_bar(d: PciDevice, n: int) -> Bar?:
    for b in d.bars():
        if b.index == n:
            return b
    return null

class BarWindow:
    base: int := 0
    size: int := 0
    is_io: bool := false
    index: int := 0

    func init(base: int, size: int, is_io: bool, index: int):
        self.base = base
        self.size = size
        self.is_io = is_io
        self.index = index

    func _check(offset: int, width: int):
        if offset < 0 or offset + width > self.size:
            raise("PciBarError", "BAR" + str(self.index) + " : accès à +" + str(offset) + " (" + str(width) + " octets) hors de la fenêtre de " + str(self.size) + " octets")

    func read8(offset: int) -> int:
        self._check(offset, 1)
        if self.is_io:
            return hw.inb(self.base + offset)
        return hw.peek8(self.base + offset)

    func read16(offset: int) -> int:
        self._check(offset, 2)
        if self.is_io:
            return hw.inw(self.base + offset)
        return hw.peek16(self.base + offset)

    func read32(offset: int) -> int:
        self._check(offset, 4)
        if self.is_io:
            return hw.inl(self.base + offset)
        return hw.peek32(self.base + offset)

    func write8(offset: int, value: int):
        self._check(offset, 1)
        if self.is_io:
            hw.outb(self.base + offset, value)
        else:
            hw.poke8(self.base + offset, value)

    func write16(offset: int, value: int):
        self._check(offset, 2)
        if self.is_io:
            hw.outw(self.base + offset, value)
        else:
            hw.poke16(self.base + offset, value)

    func write32(offset: int, value: int):
        self._check(offset, 4)
        if self.is_io:
            hw.outl(self.base + offset, value)
        else:
            hw.poke32(self.base + offset, value)

    # Met à 1 (on) ou à 0 les bits de mask d'un registre 32 bits ; nouvelle valeur.
    func set_bits32(offset: int, mask: int, on: bool) -> int:
        v := self.read32(offset)
        if on:
            v = v | mask
        else:
            v = v & ~mask
        self.write32(offset, v)
        return v

    func describe() -> str:
        k := "MMIO"
        if self.is_io:
            k = "ports"
        return "BAR" + str(self.index) + " " + k + " " + hex(self.base) + " (" + pd.size_text(self.size) + ")"

# Fenêtre d'accès au BAR n (active le décodage correspondant). PciBarError si le BAR est vide.
func window(d: PciDevice, n: int) -> BarWindow:
    b := find_bar(d, n)
    if b == null:
        raise("PciBarError", d.location() + " : BAR" + str(n) + " absent ou vide")
        return BarWindow(0, 0, false, n)
    if b.is_io:
        d.enable_io()
    else:
        d.enable_memory()
    return BarWindow(b.address, b.size, b.is_io, n)

# Programme l'adresse du BAR n (alignée sur sa taille) ; renvoie l'adresse relue.
func assign(d: PciDevice, n: int, address: int) -> int:
    b := find_bar(d, n)
    if b == null:
        raise("PciBarError", d.location() + " : BAR" + str(n) + " absent ou vide")
        return 0
    if b.size > 0 and (address & (b.size - 1)) != 0:
        raise("PciBarError", "BAR" + str(n) + " : adresse " + hex(address) + " non alignée sur " + pd.size_text(b.size))
    if b.is_io and address > 0xFFFF:
        raise("PciBarError", "BAR" + str(n) + " : adresse de ports au-delà de 0xFFFF")
    if not b.is64 and address > 0xFFFFFFFF:
        raise("PciBarError", "BAR" + str(n) + " : registre 32 bits, adresse au-delà de 4 Gio")
    cmd := d.command()
    d.write16(cfg.COMMAND, cmd & ~(cfg.CMD_IO | cfg.CMD_MEMORY))
    off := cfg.BAR0 + 4 * n
    low := d.read32(off) & 0xF
    if b.is_io:
        low = d.read32(off) & 0x3
    d.write32(off, (address & 0xFFFFFFFF & ~0xF) | low)
    if b.is64:
        d.write32(off + 4, (address >> 32) & 0xFFFFFFFF)
    d.write16(cfg.COMMAND, cmd)
    return d.bar_address(n)

# Paires [i, j] de BAR (indices) dont les plages se recouvrent (même espace : ports ou mémoire).
func overlaps(bars: list[Bar]) -> list[list[int]]:
    out: list[list[int]] := []
    i := 0
    while i < len(bars):
        j := i + 1
        while j < len(bars):
            a := bars[i]
            b := bars[j]
            if a.is_io == b.is_io and a.size > 0 and b.size > 0:
                if a.address < b.address + b.size and b.address < a.address + a.size:
                    append(out, [a.index, b.index])
            j += 1
        i += 1
    return out

# Taille totale de mémoire (non ports) demandée par les BAR.
func memory_footprint(bars: list[Bar]) -> int:
    t := 0
    for b in bars:
        if not b.is_io:
            t += b.size
    return t

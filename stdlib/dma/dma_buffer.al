# alex: native
# ALEX STANDARD LIBRARY — dma.dma_buffer
#
# Tampon DMA : mémoire PHYSIQUEMENT CONTIGUË, alignée sur la page, mise à zéro, qu'un périphérique peut lire ou
# écrire par accès direct (bus master). Dans le noyau Alex, le premier Gio est en identité : l'adresse vue par
# le processeur (addr) est aussi l'adresse physique (phys) donnée au périphérique. Dans la VM, les pages
# viennent de la RAM simulée de hw.
#
#   use dma.dma_buffer as db
#   b := db.DmaBuffer(8192, 4096)
#   b.write32(0, 0xCAFE)
#   carte.programmer(b.phys, b.size)
#   ...
#   s := b.read_str(0, 512)          # octets reçus (str)
#   b.free()
#
# Erreurs : MemoryError (accès hors du tampon, tampon libéré), ArgumentError.
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw

const PAGE := 4096

# ---- zone basse : pages sous 16 Mio pour les périphériques à adressage limité (ISA, anciens contrôleurs) ----
# Le tas des pages du noyau Alex commence à 32 Mio : un noyau qui pilote du DMA ISA déclare une zone libre de
# la mémoire basse (par exemple dma.low_zone(0x20000, 0x60000)) où les tampons « sous masque » sont pris.
class _LowZone:
    start: int := 0
    end: int := 0
    free_runs: list[int] := []     # [adresse, pages, adresse, pages, ...] libres

    func init():
        self.start = 0
        self.end = 0
        self.free_runs = []

_zone: _LowZone := _LowZone()

func low_zone(start: int, size: int):
    s := (start + PAGE - 1) // PAGE * PAGE
    e := (start + size) // PAGE * PAGE
    _zone.start = s
    _zone.end = e
    _zone.free_runs = [s, (e - s) // PAGE]

func low_zone_free() -> int:
    n := 0
    i := 0
    while i < len(_zone.free_runs):
        n += _zone.free_runs[i + 1]
        i += 2
    return n * PAGE

func _low_alloc(pages: int, align: int) -> int:
    runs := _zone.free_runs
    i := 0
    while i < len(runs):
        a := runs[i]
        n := runs[i + 1]
        b := a
        if align > PAGE and b % align != 0:
            b = b + align - b % align
        skip := (b - a) // PAGE
        if skip + pages <= n:
            out: list[int] := []
            j := 0
            while j < len(runs):
                if j == i:
                    if skip > 0:
                        append(out, a)
                        append(out, skip)
                    if n - skip - pages > 0:
                        append(out, b + pages * PAGE)
                        append(out, n - skip - pages)
                else:
                    append(out, runs[j])
                    append(out, runs[j + 1])
                j += 2
            _zone.free_runs = out
            hw.zero(b, pages * PAGE)
            return b
        i += 2
    return -1

func _low_free(addr: int, pages: int):
    append(_zone.free_runs, addr)
    append(_zone.free_runs, pages)

func pages_for(size: int) -> int:
    return (size + PAGE - 1) // PAGE

class DmaBuffer:
    addr: int := 0           # adresse pour le processeur
    phys: int := 0           # adresse pour le périphérique
    size: int := 0           # octets demandés
    pages: int := 0
    freed: bool := false
    base: int := 0           # première page prise (alignement)
    low: bool := false       # pris dans la zone basse

    # size octets ; align : alignement demandé (une puissance de 2 ; au-delà d'une page, des pages sont prises
    # en plus pour l'obtenir).
    func init(size: int, align: int):
        if size <= 0:
            raise("ArgumentError", "DmaBuffer : taille > 0 attendue")
        n := pages_for(size)
        extra := 0
        if align > PAGE:
            extra = align // PAGE - 1
        base := hw.alloc_pages(n + extra)
        a := base
        if align > PAGE and a % align != 0:
            a = a + align - a % align
        self.addr = a
        self.phys = a
        self.size = size
        self.pages = n + extra
        self.base = base
        self.freed = false

    func _check(offset: int, n: int):
        if self.freed:
            raise("MemoryError", "DmaBuffer : tampon libéré")
        if offset < 0 or offset + n > self.size:
            raise("MemoryError", "DmaBuffer : accès " + str(offset) + "+" + str(n) + " hors du tampon de " + str(self.size) + " octets")

    func read8(offset: int) -> int:
        self._check(offset, 1)
        return hw.peek8(self.addr + offset)

    func read16(offset: int) -> int:
        self._check(offset, 2)
        return hw.peek16(self.addr + offset)

    func read32(offset: int) -> int:
        self._check(offset, 4)
        return hw.peek32(self.addr + offset)

    func read64(offset: int) -> int:
        self._check(offset, 8)
        return hw.peek64(self.addr + offset)

    func write8(offset: int, v: int):
        self._check(offset, 1)
        hw.poke8(self.addr + offset, v)

    func write16(offset: int, v: int):
        self._check(offset, 2)
        hw.poke16(self.addr + offset, v)

    func write32(offset: int, v: int):
        self._check(offset, 4)
        hw.poke32(self.addr + offset, v)

    func write64(offset: int, v: int):
        self._check(offset, 8)
        hw.poke64(self.addr + offset, v)

    # Octets [offset, offset + n) sous forme de str (binaire).
    func read_str(offset: int, n: int) -> str:
        self._check(offset, n)
        return hw.string_at(self.addr + offset, n)

    # Copie les octets de s à offset ; renvoie leur nombre.
    func write_str(offset: int, s: str) -> int:
        n := hw.byte_size(s)
        self._check(offset, n)
        hw.store_string(s, self.addr + offset)
        return n

    func fill(offset: int, n: int, value: int):
        self._check(offset, n)
        i := 0
        while i < n:
            hw.poke8(self.addr + offset + i, value)
            i += 1

    func zero():
        self._check(0, self.size)
        hw.zero(self.addr, self.size)

    # Copie n octets depuis l'adresse src (mémoire du noyau ou autre tampon).
    func copy_from(offset: int, src: int, n: int):
        self._check(offset, n)
        hw.copy(self.addr + offset, src, n)

    func copy_to(dst: int, offset: int, n: int):
        self._check(offset, n)
        hw.copy(dst, self.addr + offset, n)

    # La plage [phys, phys + size) tient-elle sous la limite d'adressage du périphérique (masque DMA) ?
    func fits(mask: int) -> bool:
        return self.phys + self.size - 1 <= mask

    # Ne traverse-t-elle pas une frontière de boundary octets (64 Kio pour le DMA ISA) ?
    func crosses(boundary: int) -> bool:
        return self.phys // boundary != (self.phys + self.size - 1) // boundary

    func free():
        if not self.freed:
            if self.low:
                _low_free(self.base, self.pages)
            else:
                hw.free_pages(self.base, self.pages)
            self.freed = true

    func describe() -> str:
        return "tampon DMA de " + str(self.size) + " octets à " + str(self.phys)

# Tampon dont toute la plage est sous mask : pages du tas si elles conviennent, sinon zone basse (low_zone).
# MemoryError si impossible.
func alloc_below(size: int, align: int, mask: int) -> DmaBuffer:
    b := DmaBuffer(size, align)
    if mask == -1 or b.fits(mask):
        return b
    b.free()
    pages := pages_for(size)
    a := _low_alloc(pages, align)
    if a < 0 or a + size - 1 > mask:
        raise("MemoryError", "DmaBuffer : aucune mémoire sous le masque DMA " + str(mask) + " (déclarer une zone basse : dma.low_zone)")
    b.base = a
    b.addr = a
    b.phys = a
    b.pages = pages
    b.low = true
    b.freed = false
    return b

func alloc(size: int) -> DmaBuffer:
    return DmaBuffer(size, PAGE)

func alloc_aligned(size: int, align: int) -> DmaBuffer:
    return DmaBuffer(size, align)

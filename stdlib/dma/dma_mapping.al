# alex: native
# ALEX STANDARD LIBRARY — dma.dma_mapping
#
# Rendre une zone de mémoire accessible à un périphérique, avec ses contraintes :
#   - DmaMapping : une zone (adresse, longueur, sens) vue par le périphérique ; si elle dépasse son masque
#     d'adressage (ex. 32 bits, 24 bits pour l'ISA) ou traverse une frontière interdite, elle passe par un
#     tampon de rebond (bounce buffer) : sync_for_device copie vers lui avant le transfert, sync_for_cpu
#     recopie après (selon le sens) ;
#   - ScatterList : liste de segments [adresse physique, longueur] découpés selon la taille maximale d'un
#     segment et les frontières (tables PRD d'ATA, PRDT d'AHCI, listes PRP de NVMe) ;
#   - DmaPool : petits blocs de taille fixe alignés (descripteurs), pris dans des pages DMA ;
#   - DmaRing : anneau de descripteurs (cartes réseau, files NVMe, xHCI) : indices de tête / queue, adresse de
#     chaque descripteur.
#
#   use dma.dma_mapping as dm
#   mp := dm.map_region(tampon, 4096, dm.TO_DEVICE, dm.MASK_32)
#   mp.sync_for_device()
#   carte.envoyer(mp.device_addr, mp.length)
#   mp.unmap()
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use dma.dma_buffer as db
from dma.dma_buffer use DmaBuffer

const TO_DEVICE := 1
const FROM_DEVICE := 2
const BIDIRECTIONAL := 3

const MASK_24 := 0xFFFFFF
const MASK_32 := 0xFFFFFFFF
const MASK_64 := -1

func direction_name(d: int) -> str:
    if d == TO_DEVICE:
        return "vers le périphérique"
    if d == FROM_DEVICE:
        return "depuis le périphérique"
    return "dans les deux sens"

# ---------------------------------------------------------------- correspondance
class DmaMapping:
    cpu_addr: int := 0
    device_addr: int := 0
    length: int := 0
    direction: int := 3
    bounce: DmaBuffer?
    mapped: bool := false

    func init(cpu_addr: int, length: int, direction: int, mask: int, boundary: int):
        self.cpu_addr = cpu_addr
        self.length = length
        self.direction = direction
        self.bounce = null
        self.mapped = true
        last := cpu_addr + length - 1
        ok := mask == MASK_64 or last <= mask
        if ok and boundary > 0 and cpu_addr // boundary != last // boundary:
            ok = false
        if ok:
            self.device_addr = cpu_addr
        else:
            align := 4096
            if boundary > 0 and boundary > align:
                align = boundary
            b := db.alloc_below(length, align, mask)
            self.bounce = b
            self.device_addr = b.phys

    func bounced() -> bool:
        return self.bounce != null

    # Avant que le périphérique lise : les données du processeur vont au tampon de rebond.
    func sync_for_device():
        b := self.bounce
        if b != null:
            if self.direction != FROM_DEVICE:
                hw.copy(b.addr, self.cpu_addr, self.length)

    # Après que le périphérique a écrit : ses données reviennent à la zone du processeur.
    func sync_for_cpu():
        b := self.bounce
        if b != null:
            if self.direction != TO_DEVICE:
                hw.copy(self.cpu_addr, b.addr, self.length)

    func unmap():
        if not self.mapped:
            return
        self.sync_for_cpu()
        b := self.bounce
        if b != null:
            b.free()
        self.mapped = false

    func describe() -> str:
        t := str(self.length) + " octets " + direction_name(self.direction) + " à " + str(self.device_addr)
        if self.bounced():
            t = t + " (rebond)"
        return t

# boundary : frontière à ne pas traverser (0 : aucune).
func map_region(cpu_addr: int, length: int, direction: int, mask: int) -> DmaMapping:
    return DmaMapping(cpu_addr, length, direction, mask, 0)

func map_region_bounded(cpu_addr: int, length: int, direction: int, mask: int, boundary: int) -> DmaMapping:
    return DmaMapping(cpu_addr, length, direction, mask, boundary)

func map_buffer(b: DmaBuffer, direction: int, mask: int) -> DmaMapping:
    return DmaMapping(b.addr, b.size, direction, mask, 0)

# ---------------------------------------------------------------- liste de segments
class Segment:
    addr: int := 0
    length: int := 0

    func init(addr: int, length: int):
        self.addr = addr
        self.length = length

class ScatterList:
    segments: list[Segment] := []
    max_segment: int := 65536
    boundary: int := 0

    # max_segment : longueur maximale d'un segment ; boundary : frontière qu'un segment ne traverse pas (0 : aucune).
    func init(max_segment: int, boundary: int):
        self.segments = []
        self.max_segment = max_segment
        self.boundary = boundary

    # Ajoute la zone [addr, addr + length), découpée selon les contraintes ; fusionne avec le segment
    # précédent s'il est contigu et que la contrainte le permet.
    func add(addr: int, length: int):
        a := addr
        rest := length
        while rest > 0:
            n := rest
            if n > self.max_segment:
                n = self.max_segment
            if self.boundary > 0:
                room := self.boundary - a % self.boundary
                if n > room:
                    n = room
            k := len(self.segments)
            merged := false
            if k > 0:
                last := self.segments[k - 1]
                if last.addr + last.length == a and last.length + n <= self.max_segment:
                    if self.boundary == 0 or last.addr // self.boundary == (a + n - 1) // self.boundary:
                        last.length = last.length + n
                        merged = true
            if not merged:
                append(self.segments, Segment(a, n))
            a += n
            rest -= n

    func add_buffer(b: DmaBuffer):
        self.add(b.phys, b.size)

    func count() -> int:
        return len(self.segments)

    func total() -> int:
        t := 0
        for s in self.segments:
            t += s.length
        return t

    # Écrit une table PRD (ATA bus master / AHCI PRDT simplifiée) en addr : par entrée [adresse 32 bits,
    # longueur 16 bits (0 = 64 Kio), fin de table (bit 15 du dernier mot)] ; renvoie le nombre d'entrées.
    func write_prd(addr: int) -> int:
        i := 0
        n := len(self.segments)
        while i < n:
            s := self.segments[i]
            hw.poke32(addr + 8 * i, s.addr & 0xFFFFFFFF)
            flags := 0
            if i == n - 1:
                flags = 0x8000
            hw.poke16(addr + 8 * i + 4, s.length & 0xFFFF)
            hw.poke16(addr + 8 * i + 6, flags)
            i += 1
        return n

# ---------------------------------------------------------------- réserve de petits blocs
class DmaPool:
    block: int := 64
    per_page: int := 64
    pages: list[int] := []
    free_blocks: list[int] := []
    used: int := 0

    # block : taille d'un bloc (arrondie à 16, alignée sur elle-même jusqu'à 4096).
    func init(block: int):
        b := (block + 15) & ~15
        p := 16
        while p < b:
            p = p * 2
        if p > 4096:
            raise("ArgumentError", "DmaPool : blocs de 4096 octets au plus")
        self.block = p
        self.per_page = 4096 // p
        self.pages = []
        self.free_blocks = []
        self.used = 0

    # Adresse (physique = processeur) d'un bloc mis à zéro.
    func alloc() -> int:
        if len(self.free_blocks) == 0:
            page := hw.alloc_pages(1)
            append(self.pages, page)
            k := self.per_page - 1
            while k >= 0:
                append(self.free_blocks, page + k * self.block)
                k -= 1
        n := len(self.free_blocks)
        a := self.free_blocks[n - 1]
        keep: list[int] := []
        i := 0
        while i < n - 1:
            append(keep, self.free_blocks[i])
            i += 1
        self.free_blocks = keep
        hw.zero(a, self.block)
        self.used += 1
        return a

    func release(addr: int):
        append(self.free_blocks, addr)
        self.used -= 1

    func destroy():
        for p in self.pages:
            hw.free_pages(p, 1)
        self.pages = []
        self.free_blocks = []
        self.used = 0

# ---------------------------------------------------------------- anneau de descripteurs
class DmaRing:
    buffer: DmaBuffer
    count: int := 0
    desc_size: int := 16
    head: int := 0           # prochain descripteur que le périphérique traitera (ou à récupérer)
    tail: int := 0           # prochain descripteur libre pour le pilote
    used: int := 0

    func init(count: int, desc_size: int, align: int):
        self.buffer = DmaBuffer(count * desc_size, align)
        self.count = count
        self.desc_size = desc_size
        self.head = 0
        self.tail = 0
        self.used = 0

    func phys() -> int:
        return self.buffer.phys

    func bytes() -> int:
        return self.count * self.desc_size

    func desc(i: int) -> int:
        return self.buffer.addr + (i % self.count) * self.desc_size

    func full() -> bool:
        return self.used == self.count

    func empty() -> bool:
        return self.used == 0

    func space() -> int:
        return self.count - self.used

    # Réserve le descripteur de queue ; renvoie son indice (-1 si plein).
    func produce() -> int:
        if self.used == self.count:
            return -1
        i := self.tail
        self.tail = (self.tail + 1) % self.count
        self.used += 1
        return i

    # Libère le descripteur de tête ; renvoie son indice (-1 si vide).
    func consume() -> int:
        if self.used == 0:
            return -1
        i := self.head
        self.head = (self.head + 1) % self.count
        self.used -= 1
        return i

    func free():
        self.buffer.free()

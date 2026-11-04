# alex: native
#
# ALEX STANDARD LIBRARY — dma.dma_descriptor
#
# Descripteurs DMA : la mise en mémoire des tables que lisent les contrôleurs, à partir d'une liste de
# segments (dma.dma_mapping.ScatterList) ou d'adresses, pour les formats courants :
#   PRD ATA bus master    adresse 32 bits, octets 16 bits (0 = 64 Kio), bit « fin de table »
#   PRDT AHCI             adresse 64 bits, octets - 1 sur 22 bits, bit « interruption à la fin »
#   PRP NVMe              PRP1 / PRP2 ou liste de PRP (pages de 4 Kio), selon la longueur du transfert
#   e1000 (hérité)        descripteurs de réception et d'émission de 16 octets (adresse, longueur, commande,
#                         état « fait »)
#   virtio (anneau scindé) adresse 64, longueur 32, drapeaux NEXT / WRITE, suivant
# Plus un format générique DescriptorLayout (champs nommés : décalage, largeur) pour un contrôleur maison.
#
#   use dma.dma_descriptor as dd
#   n := dd.write_ahci_prdt(table_phys + 0x80, sg, true)       # n entrées, interruption sur la dernière
#   prp := dd.nvme_prp(buffer.phys, 12288, liste)              # [prp1, prp2] (prp2 = liste si > 2 pages)
#   dd.write_e1000_tx(ring.desc(i), tampon.phys, 60, dd.E1000_TX_EOP | dd.E1000_TX_RS)
#   print(dd.e1000_done(ring.desc(i)))                         # état DD lu par le pilote
#   l := dd.DescriptorLayout(16)
#   l.field("adresse", 0, 8) ; l.field("longueur", 8, 4)
#   l.write(adr, "longueur", 512) ; print(l.read(adr, "longueur"))
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from core use len
from collections use append, contains_key
use hw
use dma.dma_errors as derr
use dma.dma_mapping as dm
from dma.dma_mapping use ScatterList, Segment
from dma.dma_buffer use DmaBuffer

const PAGE := 4096

# ---- format générique ----
class DescriptorLayout:
    size: int := 16
    offsets: dict[str, int] := {}
    widths: dict[str, int] := {}

    func init(size: int):
        self.size = size
        self.offsets = {}
        self.widths = {}

    # Champ name : width octets (1, 2, 4 ou 8) à offset.
    func field(name: str, offset: int, width: int):
        if width != 1 and width != 2 and width != 4 and width != 8:
            raise(derr.DMA, "DescriptorLayout.field : largeur 1, 2, 4 ou 8 attendue")
        if offset < 0 or offset + width > self.size:
            raise(derr.DMA, "DescriptorLayout.field : « " + name + " » déborde du descripteur de " + str(self.size) + " octets")
        self.offsets[name] = offset
        self.widths[name] = width

    func _get(name: str) -> int:
        if not contains_key(self.offsets, name):
            raise(derr.DMA, "DescriptorLayout : champ inconnu « " + name + " »")
        return self.offsets[name]

    func write(addr: int, name: str, value: int):
        off := self._get(name)
        w := self.widths[name]
        if w == 1:
            hw.poke8(addr + off, value)
        elif w == 2:
            hw.poke16(addr + off, value)
        elif w == 4:
            hw.poke32(addr + off, value)
        else:
            hw.poke64(addr + off, value)

    func read(addr: int, name: str) -> int:
        off := self._get(name)
        w := self.widths[name]
        if w == 1:
            return hw.peek8(addr + off)
        if w == 2:
            return hw.peek16(addr + off)
        if w == 4:
            return hw.peek32(addr + off)
        return hw.peek64(addr + off)

    func clear(addr: int):
        hw.zero(addr, self.size)

# ---- PRD ATA ----
func write_ata_prd(addr: int, sg: ScatterList) -> int:
    i := 0
    n := len(sg.segments)
    while i < n:
        s := sg.segments[i]
        derr.check_mask(s.addr, s.length, 0xFFFFFFFF)
        derr.check_boundary(s.addr, s.length, 65536)
        hw.poke32(addr + 8 * i, s.addr & 0xFFFFFFFF)
        hw.poke16(addr + 8 * i + 4, s.length & 0xFFFF)
        fl := 0
        if i == n - 1:
            fl = 0x8000
        hw.poke16(addr + 8 * i + 6, fl)
        i += 1
    return n

# ---- PRDT AHCI ----
func write_ahci_prdt(addr: int, sg: ScatterList, interrupt_last: bool) -> int:
    i := 0
    n := len(sg.segments)
    while i < n:
        s := sg.segments[i]
        if s.length > 4194304:
            raise(derr.DMA, "AHCI : segment de plus de 4 Mio")
        if s.length % 2 != 0:
            raise(derr.ALIGNMENT, "AHCI : longueur de segment paire attendue")
        e := addr + 16 * i
        hw.poke32(e, s.addr & 0xFFFFFFFF)
        hw.poke32(e + 4, (s.addr >> 32) & 0xFFFFFFFF)
        hw.poke32(e + 8, 0)
        dbc := (s.length - 1) & 0x3FFFFF
        if interrupt_last and i == n - 1:
            dbc = dbc | 0x80000000
        hw.poke32(e + 12, dbc)
        i += 1
    return n

func ahci_prdt_length(addr: int, count: int) -> int:
    t := 0
    i := 0
    while i < count:
        t += (hw.peek32(addr + 16 * i + 12) & 0x3FFFFF) + 1
        i += 1
    return t

# ---- PRP NVMe ----
# Pointeurs PRP d'un transfert contigu en addr de length octets : [prp1, prp2]. Au-delà de deux pages, la liste
# de PRP est écrite dans list_buffer (une page alignée) et prp2 pointe dessus.
func nvme_prp(addr: int, length: int, list_buffer: DmaBuffer?) -> list[int]:
    derr.check_alignment(addr, 4)
    first_len := PAGE - addr % PAGE
    if length <= first_len:
        return [addr, 0]
    rest := length - first_len
    second := addr + first_len
    if rest <= PAGE:
        return [addr, second]
    if list_buffer == null:
        raise(derr.DMA, "NVMe : liste de PRP nécessaire (" + str(length) + " octets) : tampon de liste attendu")
        return [0, 0]
    pages := (rest + PAGE - 1) // PAGE
    if pages > PAGE // 8:
        raise(derr.DMA, "NVMe : transfert trop long pour une seule page de liste PRP")
    i := 0
    while i < pages:
        list_buffer.write64(8 * i, second + i * PAGE)
        i += 1
    return [addr, list_buffer.phys]

# ---- e1000 (descripteurs hérités) ----
const E1000_TX_EOP := 0x01
const E1000_TX_IFCS := 0x02
const E1000_TX_RS := 0x08
const E1000_STATUS_DD := 0x01
const E1000_RX_EOP := 0x02

func write_e1000_rx(desc: int, buffer_phys: int):
    hw.poke64(desc, buffer_phys)
    hw.poke16(desc + 8, 0)
    hw.poke16(desc + 10, 0)
    hw.poke8(desc + 12, 0)
    hw.poke8(desc + 13, 0)
    hw.poke16(desc + 14, 0)

func write_e1000_tx(desc: int, buffer_phys: int, length: int, cmd: int):
    if length <= 0 or length > 16288:
        raise(derr.DMA, "e1000 : longueur de trame " + str(length) + " invalide")
    hw.poke64(desc, buffer_phys)
    hw.poke16(desc + 8, length)
    hw.poke8(desc + 10, 0)
    hw.poke8(desc + 11, cmd)
    hw.poke8(desc + 12, 0)
    hw.poke8(desc + 13, 0)
    hw.poke16(desc + 14, 0)

# Descripteur traité par la carte (bit DD de l'état : octet 12 en réception et en émission).
func e1000_done(desc: int) -> bool:
    return (hw.peek8(desc + 12) & E1000_STATUS_DD) != 0

func e1000_rx_length(desc: int) -> int:
    return hw.peek16(desc + 8)

# ---- virtio, anneau scindé ----
const VIRTQ_DESC_NEXT := 1
const VIRTQ_DESC_WRITE := 2
const VIRTQ_DESC_INDIRECT := 4

func write_virtq_desc(table: int, i: int, addr: int, length: int, flags: int, next: int):
    d := table + 16 * i
    hw.poke64(d, addr)
    hw.poke32(d + 8, length)
    hw.poke16(d + 12, flags)
    hw.poke16(d + 14, next)

# Chaîne de descripteurs virtio pour les segments, à partir de l'indice first ; device_writes : le
# périphérique écrit (lecture d'un disque, réception). Renvoie le nombre de descripteurs.
func write_virtq_chain(table: int, first: int, sg: ScatterList, device_writes: bool) -> int:
    n := len(sg.segments)
    i := 0
    while i < n:
        s := sg.segments[i]
        fl := 0
        if device_writes:
            fl = VIRTQ_DESC_WRITE
        nxt := 0
        if i < n - 1:
            fl = fl | VIRTQ_DESC_NEXT
            nxt = first + i + 1
        write_virtq_desc(table, first + i, s.addr, s.length, fl, nxt)
        i += 1
    return n

func virtq_desc(table: int, i: int) -> list[int]:
    d := table + 16 * i
    return [hw.peek64(d), hw.peek32(d + 8), hw.peek16(d + 12), hw.peek16(d + 14)]

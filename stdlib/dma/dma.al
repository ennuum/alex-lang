# alex: native
# ALEX STANDARD LIBRARY — dma
#
# Accès direct à la mémoire pour les pilotes (noyau --freestanding, ou machine simulée de la VM) :
#
# | Module               | Contenu                                                                       |
# |----------------------|-------------------------------------------------------------------------------|
# | dma.dma_buffer       | DmaBuffer : mémoire physiquement contiguë, alignée, lue / écrite par octets…  |
# | dma.dma_mapping      | DmaMapping (masque d'adressage, tampon de rebond, synchronisation),           |
# |                      | ScatterList (segments, tables PRD), DmaPool (descripteurs), DmaRing (anneaux) |
# | dma.dma_transfer     | Transfer, DmaEngine, MemcpyEngine (logiciel), Isa8237 (contrôleur ISA)        |
#
#   use dma
#   b := dma.alloc(4096)                         # tampon contigu
#   r := dma.ring(256, 16, 128)                  # 256 descripteurs de 16 octets, alignés sur 128
#   sg := dma.scatter(65536, 65536)              # segments de 64 Kio max., sans traverser 64 Kio
#   sg.add_buffer(b)
#   mp := dma.map(adresse, 512, dma.FROM_DEVICE, dma.MASK_32)
#
# Compilable en natif (# alex: native).

use dma.dma_buffer as db
from dma.dma_buffer use DmaBuffer
use dma.dma_mapping as dm
from dma.dma_mapping use DmaMapping, ScatterList, DmaPool, DmaRing
use dma.dma_transfer as dt
from dma.dma_transfer use MemcpyEngine, Transfer

const TO_DEVICE := 1
const FROM_DEVICE := 2
const BIDIRECTIONAL := 3
const MASK_24 := 0xFFFFFF
const MASK_32 := 0xFFFFFFFF
const MASK_64 := -1

func alloc(size: int) -> DmaBuffer:
    return DmaBuffer(size, 4096)

func alloc_aligned(size: int, align: int) -> DmaBuffer:
    return DmaBuffer(size, align)

# Zone de mémoire basse libre (sous 16 Mio) réservée aux tampons des périphériques à adressage limité.
func low_zone(start: int, size: int):
    db.low_zone(start, size)

func alloc_below(size: int, mask: int) -> DmaBuffer:
    return db.alloc_below(size, 4096, mask)

func map(addr: int, length: int, direction: int, mask: int) -> DmaMapping:
    return DmaMapping(addr, length, direction, mask, 0)

func scatter(max_segment: int, boundary: int) -> ScatterList:
    return ScatterList(max_segment, boundary)

func pool(block: int) -> DmaPool:
    return DmaPool(block)

func ring(count: int, desc_size: int, align: int) -> DmaRing:
    return DmaRing(count, desc_size, align)

func engine() -> MemcpyEngine:
    return MemcpyEngine(4096)

# Copie mémoire par le moteur logiciel (synchrone) ; renvoie le nombre d'octets copiés.
func copy(dst: int, src: int, n: int) -> int:
    e := MemcpyEngine(0)
    t := Transfer(src, dst, n, dt.MEM_TO_MEM)
    e.submit(t)
    e.run_all()
    return t.done_bytes

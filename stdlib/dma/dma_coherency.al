# alex: native
#
# ALEX STANDARD LIBRARY — dma.dma_coherency
#
# Cohérence entre le processeur et les périphériques pour les transferts DMA :
#   - PROPRIÉTÉ d'une zone DMA (processeur ou périphérique) suivie explicitement : give_to_device() synchronise
#     (copie vers le tampon de rebond si besoin) PUIS cède la zone ; take_back() la reprend et synchronise dans
#     l'autre sens. Un accès du processeur pendant que le périphérique la possède est une erreur détectée
#     (DmaStateError) — l'erreur classique des pilotes.
#   - BARRIÈRE mémoire avant de signaler un descripteur au périphérique (instruction verrouillée, barrière
#     complète sur x86-64).
#   - Politique de la plate-forme : sur x86-64, le DMA PCI est COHÉRENT avec les caches (espionnage du bus) ;
#     aucune opération de cache n'est donc nécessaire. Sur une architecture non cohérente, les opérations de
#     maintenance de cache ne sont pas exposées par hw : requires_cache_maintenance() le signale et
#     check_platform() refuse plutôt que de simuler.
#
#   use dma.dma_coherency as dc
#   z := dc.Ownership(dma.map(adresse, 4096, dma.TO_DEVICE, dma.MASK_32))
#   z.cpu_write32(0, 0xCAFE)                   # le processeur prépare les données
#   z.give_to_device()                         # synchronise + barrière ; le périphérique peut lire
#   z.cpu_read32(0)                            # DmaStateError : la zone appartient au périphérique
#   z.take_back()
#   dc.barrier()
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

use hw
use dma.dma_errors as derr
use dma.dma_mapping as dm
from dma.dma_mapping use DmaMapping

const CPU := 0
const DEVICE := 1

_fence_page := [0]

# Barrière mémoire complète (instruction verrouillée sur un mot réservé).
func barrier():
    if _fence_page[0] == 0:
        _fence_page[0] = hw.alloc_pages(1)
    a := _fence_page[0]
    v := hw.peek64(a)
    hw.cas(a, v, v + 1)

func coherent_platform() -> bool:
    return true

func requires_cache_maintenance() -> bool:
    return not coherent_platform()

func check_platform():
    if requires_cache_maintenance():
        raise(derr.DMA, "plate-forme non cohérente : maintenance de cache requise mais non exposée par hw")

class Ownership:
    mapping: DmaMapping
    owner: int := 0
    transfers: int := 0

    func init(mapping: DmaMapping):
        self.mapping = mapping
        self.owner = CPU
        self.transfers = 0

    func owned_by_cpu() -> bool:
        return self.owner == CPU

    func device_address() -> int:
        return self.mapping.device_addr

    func give_to_device():
        if self.owner == DEVICE:
            raise(derr.STATE, "zone DMA déjà cédée au périphérique")
        if not self.mapping.mapped:
            raise(derr.STATE, "zone DMA défaite (unmap)")
        self.mapping.sync_for_device()
        barrier()
        self.owner = DEVICE
        self.transfers += 1

    func take_back():
        if self.owner == CPU:
            raise(derr.STATE, "zone DMA déjà possédée par le processeur")
        barrier()
        self.mapping.sync_for_cpu()
        self.owner = CPU

    func _cpu(offset: int, n: int):
        if self.owner != CPU:
            raise(derr.STATE, "accès du processeur à une zone DMA possédée par le périphérique")
        if offset < 0 or offset + n > self.mapping.length:
            raise(derr.STATE, "accès hors de la zone DMA (" + str(self.mapping.length) + " octets)")

    func cpu_read32(offset: int) -> int:
        self._cpu(offset, 4)
        return hw.peek32(self.mapping.cpu_addr + offset)

    func cpu_write32(offset: int, value: int):
        self._cpu(offset, 4)
        hw.poke32(self.mapping.cpu_addr + offset, value)

    func cpu_read8(offset: int) -> int:
        self._cpu(offset, 1)
        return hw.peek8(self.mapping.cpu_addr + offset)

    func cpu_write8(offset: int, value: int):
        self._cpu(offset, 1)
        hw.poke8(self.mapping.cpu_addr + offset, value)

    func release():
        if self.owner == DEVICE:
            self.take_back()
        self.mapping.unmap()

func own(mapping: DmaMapping) -> Ownership:
    return Ownership(mapping)

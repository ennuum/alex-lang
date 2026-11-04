# alex: native
#
# ALEX STANDARD LIBRARY — dma.dma_errors
#
# Erreurs du paquet dma et VÉRIFICATIONS des contraintes qu'un contrôleur impose à ses transferts : masque
# d'adressage (24 / 32 / 64 bits), alignement, frontière à ne pas traverser (64 Kio pour l'ISA et les PRD ATA,
# 4 Kio pour les PRP NVMe), longueur maximale d'un segment, et tampon déjà libéré.
#   DmaError            erreur générale
#   DmaAddressError     adresse hors du masque du périphérique
#   DmaAlignmentError   adresse ou longueur mal alignée
#   DmaBoundaryError    zone qui traverse une frontière interdite
#   DmaStateError       tampon libéré, mapping défait, propriété (processeur / périphérique) non respectée
#
#   use dma.dma_errors as derr
#   derr.check_mask(adresse, 4096, dma.MASK_32)          # DmaAddressError au-delà de 4 Gio
#   derr.check_alignment(adresse, 128)                    # DmaAlignmentError
#   derr.check_boundary(adresse, 8192, 65536)             # DmaBoundaryError si la zone traverse 64 Kio
#   print(derr.violations(adresse, 8192, dma.MASK_24, 4096, 65536))   # liste des problèmes (sans lever)
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from collections use append

const DMA := "DmaError"
const ADDRESS := "DmaAddressError"
const ALIGNMENT := "DmaAlignmentError"
const BOUNDARY := "DmaBoundaryError"
const STATE := "DmaStateError"

func fail(message: str):
    raise(DMA, message)

func mask_name(mask: int) -> str:
    if mask == -1:
        return "64 bits"
    if mask == 0xFFFFFFFF:
        return "32 bits"
    if mask == 0xFFFFFF:
        return "24 bits (ISA)"
    return "masque " + str(mask)

func fits(addr: int, length: int, mask: int) -> bool:
    if mask == -1:
        return true
    return addr >= 0 and addr + length - 1 <= mask

func check_mask(addr: int, length: int, mask: int):
    if not fits(addr, length, mask):
        raise(ADDRESS, "zone DMA " + str(addr) + " (+" + str(length) + ") hors du masque d'adressage " + mask_name(mask))

func aligned(addr: int, align: int) -> bool:
    if align <= 1:
        return true
    return addr % align == 0

func check_alignment(addr: int, align: int):
    if not aligned(addr, align):
        raise(ALIGNMENT, "adresse DMA " + str(addr) + " non alignée sur " + str(align) + " octets")

func check_length_alignment(length: int, align: int):
    if align > 1 and length % align != 0:
        raise(ALIGNMENT, "longueur DMA " + str(length) + " non multiple de " + str(align))

func crosses(addr: int, length: int, boundary: int) -> bool:
    if boundary <= 0 or length <= 0:
        return false
    return addr // boundary != (addr + length - 1) // boundary

func check_boundary(addr: int, length: int, boundary: int):
    if crosses(addr, length, boundary):
        raise(BOUNDARY, "zone DMA " + str(addr) + " (+" + str(length) + ") traverse une frontière de " + str(boundary) + " octets")

func check_segment(length: int, max_segment: int):
    if max_segment > 0 and length > max_segment:
        raise(DMA, "segment DMA de " + str(length) + " octets (au plus " + str(max_segment) + ")")

# Problèmes d'une zone pour un contrôleur (sans lever) : textes, liste vide si tout va bien.
func violations(addr: int, length: int, mask: int, align: int, boundary: int) -> list[str]:
    out: list[str] := []
    if not fits(addr, length, mask):
        append(out, "hors du masque " + mask_name(mask))
    if not aligned(addr, align):
        append(out, "non alignée sur " + str(align))
    if crosses(addr, length, boundary):
        append(out, "traverse une frontière de " + str(boundary))
    return out

func state_error(message: str):
    raise(STATE, message)

func is_dma_error(t: str) -> bool:
    return t == DMA or t == ADDRESS or t == ALIGNMENT or t == BOUNDARY or t == STATE

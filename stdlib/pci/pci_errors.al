# alex: native
#
# ALEX STANDARD LIBRARY — pci.pci_errors
#
# Erreurs du paquet pci et vérifications courantes d'un pilote PCI, avec des messages précis :
#   PciError            erreur générale (accès à la configuration, valeur incohérente)
#   PciDeviceNotFound   aucune fonction PCI ne correspond (identifiants, classe, emplacement)
#   PciBarError         registre de base absent, du mauvais genre (ports / mémoire) ou trop petit
#   PciCapabilityError  capacité attendue absente (MSI, MSI-X, PCI Express...) ou mal formée
#
#   use pci.pci_errors as perr
#   d := perr.require_device(bus.find(0x8086, 0x100E), "e1000")     # PciDeviceNotFound si null
#   perr.require_bar_kind(b, false, 0x20000)                         # BAR mémoire d'au moins 128 Kio
#   print(perr.describe_status(d.status()))                          # « capacités, interruption en attente »
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from core use len
from collections use append
use pci.pci_device as pd
from pci.pci_device use PciDevice, Bar
use pci.pci_ids as ids

const PCI := "PciError"
const NOT_FOUND := "PciDeviceNotFound"
const BAR := "PciBarError"
const CAPABILITY := "PciCapabilityError"

func fail(message: str):
    raise(PCI, message)

func id_text(vendor: int, device: int) -> str:
    return ids.hex16(vendor) + ":" + ids.hex16(device)

func not_found(what: str):
    raise(NOT_FOUND, "aucune fonction PCI : " + what)

# La fonction trouvée, ou PciDeviceNotFound (what : ce que l'on cherchait).
func require_device(d: PciDevice?, what: str) -> PciDevice:
    if d == null:
        raise(NOT_FOUND, "aucune fonction PCI : " + what)
    return d

# Le BAR n (mesuré) de d ; PciBarError s'il est vide.
func require_bar(d: PciDevice, n: int) -> Bar:
    for b in d.bars():
        if b.index == n:
            return b
    raise(BAR, d.location() + " : BAR" + str(n) + " absent ou vide")
    return Bar(n, false, 0, 0, false, false)

# Vérifie le genre (ports si is_io) et la taille minimale d'un BAR.
func require_bar_kind(b: Bar, is_io: bool, min_size: int):
    if b.is_io != is_io:
        want := "mémoire"
        if is_io:
            want = "ports"
        raise(BAR, "BAR" + str(b.index) + " : registre de " + want + " attendu")
    if b.size < min_size:
        raise(BAR, "BAR" + str(b.index) + " : " + pd.size_text(b.size) + " au lieu d'au moins " + pd.size_text(min_size))

# Décalage de la capacité id ; PciCapabilityError si absente.
func require_capability(d: PciDevice, cap_id: int) -> int:
    off := d.find_capability(cap_id)
    if off == 0:
        raise(CAPABILITY, d.location() + " : capacité " + pd.capability_name(cap_id) + " absente")
    return off

# Bits du registre d'état (STATUS) en clair.
func describe_status(status: int) -> str:
    parts: list[str] := []
    if (status & 0x0008) != 0:
        append(parts, "interruption en attente")
    if (status & 0x0010) != 0:
        append(parts, "capacités")
    if (status & 0x0020) != 0:
        append(parts, "66 MHz")
    if (status & 0x0100) != 0:
        append(parts, "erreur de parité maître")
    if (status & 0x0800) != 0:
        append(parts, "abandon de cible signalé")
    if (status & 0x1000) != 0:
        append(parts, "abandon de cible reçu")
    if (status & 0x2000) != 0:
        append(parts, "abandon maître reçu")
    if (status & 0x4000) != 0:
        append(parts, "erreur système signalée")
    if (status & 0x8000) != 0:
        append(parts, "erreur de parité détectée")
    if len(parts) == 0:
        return "aucun bit"
    out := parts[0]
    i := 1
    while i < len(parts):
        out = out + ", " + parts[i]
        i += 1
    return out

# Vrai si le registre d'état signale une erreur (bits 8, 11 à 15).
func has_errors(status: int) -> bool:
    return (status & 0xF900) != 0

func is_pci_error(t: str) -> bool:
    return t == PCI or t == NOT_FOUND or t == BAR or t == CAPABILITY

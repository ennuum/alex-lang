# alex: native
#
# ALEX STANDARD LIBRARY — interrupt.interrupt_vector
#
# Vecteurs d'interruption : nom de chaque vecteur (exception, IRQ héritée, GSI, MSI, IPI, minuterie...),
# ALLOCATEUR de vecteurs par plage (blocs alignés pour le MSI multi-messages, réservations, propriétaires,
# libération, rapport d'occupation) et ENCODAGE des messages MSI / MSI-X (adresse 0xFEExxxxx et donnée, format
# Intel : APIC de destination, mode logique, déclenchement, mode de livraison).
#
#   use interrupt.interrupt_vector as iv
#   a := iv.VectorAllocator()
#   v := a.allocate("e1000")                         # premier vecteur MSI libre (80..223)
#   b := a.allocate_block(4, "nvme")                 # 4 vecteurs consécutifs alignés sur 4
#   a.free(v)
#   print(a.owner(b), a.used(), a.report())
#   print(iv.describe(14), iv.describe(46))          # exception #PF, IRQ 14 (disque ATA primaire)
#   adr := iv.msi_address(0)                         # 0xFEE00000 : APIC 0, mode physique
#   don := iv.msi_data(0x51, false, false)           # vecteur 0x51, front montant, livraison fixe
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from core use len
from collections use append, contains_key, remove, keys
use interrupt.interrupt_types as it
use interrupt.interrupt_errors as ierr

func irq_name(irq: int) -> str:
    match irq:
        0:
            return "minuterie (PIT)"
        1:
            return "clavier"
        2:
            return "cascade du PIC esclave"
        3:
            return "COM2"
        4:
            return "COM1"
        5:
            return "LPT2"
        6:
            return "lecteur de disquettes"
        7:
            return "LPT1"
        8:
            return "horloge temps réel"
        9:
            return "ACPI"
        12:
            return "souris PS/2"
        13:
            return "coprocesseur"
        14:
            return "disque ATA primaire"
        15:
            return "disque ATA secondaire"
        _:
            return "libre"

func category(v: int) -> str:
    if v < 0 or v > 255:
        return "invalide"
    if v < 32:
        return "exception"
    if v == it.SYSCALL:
        return "appel système"
    if v <= it.IRQ_LAST:
        return "irq"
    if v <= it.GSI_LAST:
        return "gsi"
    if v <= it.MSI_LAST:
        return "msi"
    if v <= it.IPI_LAST:
        return "ipi"
    if v == it.APIC_TIMER:
        return "minuterie apic"
    if v == it.APIC_ERROR:
        return "erreur apic"
    if v == it.SPURIOUS:
        return "parasite"
    return "réservé"

func describe(v: int) -> str:
    c := category(v)
    if c == "exception":
        return "exception " + ierr.mnemonic(v) + " (" + ierr.exception_name(v) + ")"
    if c == "irq":
        n := v - it.IRQ_BASE
        return "IRQ " + str(n) + " (" + irq_name(n) + ")"
    if c == "gsi":
        return "GSI " + str(v - it.IRQ_BASE)
    if c == "msi":
        return "MSI / MSI-X " + str(v)
    if c == "ipi":
        return "IPI " + str(v - it.IPI_BASE)
    return c + " (" + str(v) + ")"

class VectorAllocator:
    first: int := 80
    last: int := 223
    owners: dict[int, str] := {}
    reserved: dict[int, bool] := {}

    func init(first: int = 80, last: int = 223):
        ierr.check_vector(first)
        ierr.check_vector(last)
        self.first = first
        self.last = last
        self.owners = {}
        self.reserved = {}

    func is_free(v: int) -> bool:
        return v >= self.first and v <= self.last and not contains_key(self.owners, v) and not contains_key(self.reserved, v)

    func reserve(v: int):
        ierr.check_vector(v)
        self.reserved[v] = true

    func allocate(owner: str) -> int:
        v := self.first
        while v <= self.last:
            if self.is_free(v):
                self.owners[v] = owner
                return v
            v += 1
        raise(ierr.EXHAUSTED, "plus de vecteur libre entre " + str(self.first) + " et " + str(self.last) + " (" + owner + ")")
        return -1

    # count vecteurs consécutifs (puissance de deux), le premier aligné sur count (MSI multi-messages).
    func allocate_block(count: int, owner: str) -> int:
        if count < 1 or count > 32 or (count & (count - 1)) != 0:
            raise(ierr.INVALID, "allocate_block : puissance de deux de 1 à 32 attendue (obtenu " + str(count) + ")")
        start := (self.first + count - 1) & ~(count - 1)
        while start + count - 1 <= self.last:
            ok := true
            k := 0
            while k < count:
                if not self.is_free(start + k):
                    ok = false
                k += 1
            if ok:
                k = 0
                while k < count:
                    self.owners[start + k] = owner
                    k += 1
                return start
            start += count
        raise(ierr.EXHAUSTED, "pas de bloc libre de " + str(count) + " vecteurs (" + owner + ")")
        return -1

    func free(v: int):
        if contains_key(self.owners, v):
            remove(self.owners, v)

    func free_owner(owner: str) -> int:
        n := 0
        for v in keys(self.owners):
            if self.owners[v] == owner:
                remove(self.owners, v)
                n += 1
        return n

    func owner(v: int) -> str:
        if contains_key(self.owners, v):
            return self.owners[v]
        return ""

    func used() -> int:
        return len(self.owners)

    func available() -> int:
        n := 0
        v := self.first
        while v <= self.last:
            if self.is_free(v):
                n += 1
            v += 1
        return n

    func report() -> str:
        out := "vecteurs " + str(self.first) + ".." + str(self.last) + " : " + str(self.used()) + " attribués, " + str(self.available()) + " libres"
        v := self.first
        while v <= self.last:
            if contains_key(self.owners, v):
                out = out + "\n  " + str(v) + " -> " + self.owners[v]
            v += 1
        return out

const MSI_ADDRESS_BASE := 0xFEE00000
const DELIVERY_FIXED := 0
const DELIVERY_LOWEST := 1
const DELIVERY_SMI := 2
const DELIVERY_NMI := 4
const DELIVERY_INIT := 5
const DELIVERY_EXTINT := 7

# Adresse d'un message MSI : APIC de destination (physique, ou logique), indication de redirection.
func msi_address(dest_apic: int, logical: bool = false, redirect_hint: bool = false) -> int:
    a := MSI_ADDRESS_BASE | ((dest_apic & 255) << 12)
    if redirect_hint:
        a = a | 8
    if logical:
        a = a | 4
    return a

# Donnée d'un message MSI : vecteur, déclenchement par niveau (asserté), mode de livraison.
func msi_data(vector: int, level: bool, asserted: bool, delivery: int = 0) -> int:
    ierr.check_vector(vector)
    d := (vector & 255) | ((delivery & 7) << 8)
    if level:
        d = d | 0x8000
        if asserted:
            d = d | 0x4000
    return d

# [APIC de destination, logique, vecteur, mode de livraison] d'un couple (adresse, donnée).
func decode_msi(address: int, data: int) -> list[int]:
    logical := 0
    if (address & 4) != 0:
        logical = 1
    return [(address >> 12) & 255, logical, data & 255, (data >> 8) & 7]

# alex: native
# ALEX STANDARD LIBRARY — dma.dma_transfer
#
# Transferts DMA :
#   - Transfer : une opération (source, destination, longueur, sens), son état (pending, running, done, error),
#     sa progression et sa fonction de fin ;
#   - DmaEngine (interface) : submit(t), poll() -> transferts terminés, idle() ; un pilote de périphérique
#     bus master (AHCI, NVMe, carte réseau) peut l'implémenter pour son propre moteur ;
#   - MemcpyEngine : moteur logiciel (copie mémoire par morceaux), utile pour tester les pilotes et comme
#     solution de repli ;
#   - Isa8237 : contrôleur DMA du PC (8237A, canaux 0..3 en 8 bits, 5..7 en 16 bits) : programmation de
#     l'adresse, du compte, de la page, du mode (lecture / écriture, unique / bloc, auto-initialisation),
#     masques et état (fin de compte). Sert à la disquette, au Sound Blaster, au port parallèle ECP.
#
#   use dma.dma_transfer as dt
#   e := dt.MemcpyEngine(4096)
#   t := dt.Transfer(src, dst, 65536, dt.MEM_TO_MEM)
#   e.submit(t)
#   while not t.finished():
#       e.poll()
#
#   isa := dt.Isa8237()
#   isa.setup(2, tampon.phys, 512, dt.ISA_WRITE, false)   # disquette : canal 2, le périphérique écrit en mémoire
#   isa.enable(2)
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw

const MEM_TO_MEM := 0
const TO_DEVICE := 1
const FROM_DEVICE := 2

const PENDING := 0
const RUNNING := 1
const DONE := 2
const FAILED := 3

func state_name(s: int) -> str:
    if s == PENDING:
        return "en attente"
    if s == RUNNING:
        return "en cours"
    if s == DONE:
        return "terminé"
    return "échec"

class Transfer:
    id: int := 0
    source: int := 0
    dest: int := 0
    length: int := 0
    direction: int := 0
    state: int := 0
    done_bytes: int := 0
    error: str := ""
    on_done: func(Transfer)?

    func init(source: int, dest: int, length: int, direction: int):
        self.id = 0
        self.source = source
        self.dest = dest
        self.length = length
        self.direction = direction
        self.state = PENDING
        self.done_bytes = 0
        self.error = ""
        self.on_done = null

    func then(fn: func(Transfer)):
        self.on_done = fn

    func finished() -> bool:
        return self.state == DONE or self.state == FAILED

    func progress() -> float:
        if self.length == 0:
            return 1.0
        return 1.0 * self.done_bytes / self.length

    func complete(ok: bool, error: str):
        if ok:
            self.state = DONE
        else:
            self.state = FAILED
            self.error = error
        f := self.on_done
        if f != null:
            f(self)

    func describe() -> str:
        return "transfert " + str(self.id) + " : " + str(self.done_bytes) + "/" + str(self.length) + " octets, " + state_name(self.state)

interface DmaEngine:
    func name() -> str
    func submit(t: Transfer) -> bool
    func poll() -> int
    func idle() -> bool

# ---------------------------------------------------------------- moteur logiciel
class MemcpyEngine implements DmaEngine:
    chunk: int := 4096
    queue: list[Transfer] := []
    next_id: int := 1
    completed: int := 0
    bytes: int := 0
    max_queue: int := 64

    # chunk : octets copiés par transfert à chaque poll (0 : tout d'un coup).
    func init(chunk: int):
        self.chunk = chunk
        self.queue = []
        self.next_id = 1
        self.completed = 0
        self.bytes = 0
        self.max_queue = 64

    func name() -> str:
        return "copie logicielle"

    func submit(t: Transfer) -> bool:
        if len(self.queue) >= self.max_queue:
            return false
        t.id = self.next_id
        self.next_id += 1
        t.state = PENDING
        append(self.queue, t)
        return true

    # Fait avancer le transfert en tête ; renvoie le nombre de transferts terminés par cet appel.
    func poll() -> int:
        if len(self.queue) == 0:
            return 0
        t := self.queue[0]
        t.state = RUNNING
        n := t.length - t.done_bytes
        if self.chunk > 0 and n > self.chunk:
            n = self.chunk
        if n > 0:
            hw.copy(t.dest + t.done_bytes, t.source + t.done_bytes, n)
            t.done_bytes += n
            self.bytes += n
        if t.done_bytes < t.length:
            return 0
        keep: list[Transfer] := []
        i := 1
        while i < len(self.queue):
            append(keep, self.queue[i])
            i += 1
        self.queue = keep
        self.completed += 1
        t.complete(true, "")
        return 1

    func idle() -> bool:
        return len(self.queue) == 0

    # Exécute tout ce qui est en file ; renvoie le nombre de transferts terminés.
    func run_all() -> int:
        n := 0
        while len(self.queue) > 0:
            n += self.poll()
        return n

# ---------------------------------------------------------------- 8237A (ISA)
const ISA_VERIFY := 0x00
const ISA_WRITE := 0x04          # le périphérique écrit en mémoire (lecture du périphérique)
const ISA_READ := 0x08           # le périphérique lit la mémoire
const ISA_AUTO := 0x10
const ISA_DEMAND := 0x00
const ISA_SINGLE := 0x40
const ISA_BLOCK := 0x80

class Isa8237:
    programmed: list[int] := []      # dernier [adresse, compte, mode] par canal (8 x 3)

    func init():
        self.programmed = [0 for i in 0..24]

    func _addr_port(ch: int) -> int:
        if ch < 4:
            return ch * 2
        return 0xC0 + (ch - 4) * 4

    func _count_port(ch: int) -> int:
        if ch < 4:
            return ch * 2 + 1
        return 0xC2 + (ch - 4) * 4

    func _page_port(ch: int) -> int:
        if ch == 0:
            return 0x87
        if ch == 1:
            return 0x83
        if ch == 2:
            return 0x81
        if ch == 3:
            return 0x82
        if ch == 5:
            return 0x8B
        if ch == 6:
            return 0x89
        return 0x8A

    func _mask_port(ch: int) -> int:
        return 0x0A if ch < 4 else 0xD4

    func _mode_port(ch: int) -> int:
        return 0x0B if ch < 4 else 0xD6

    func _flip_port(ch: int) -> int:
        return 0x0C if ch < 4 else 0xD8

    func disable(ch: int):
        hw.outb(self._mask_port(ch), 4 | (ch & 3))

    func enable(ch: int):
        hw.outb(self._mask_port(ch), ch & 3)

    # Programme le canal ch : adresse physique (< 16 Mio, sans traverser 64 Kio — 128 Kio en 16 bits), longueur
    # en octets, sens (ISA_WRITE : périphérique -> mémoire, ISA_READ : mémoire -> périphérique), auto-init.
    # Le canal reste masqué : enable(ch) le lance.
    func setup(ch: int, phys: int, length: int, direction: int, auto_init: bool):
        if ch < 0 or ch > 7 or ch == 4:
            raise("ArgumentError", "Isa8237 : canal 0..3 ou 5..7 attendu")
        if phys + length > 0x1000000:
            raise("ArgumentError", "Isa8237 : tampon au-delà de 16 Mio")
        wide := ch >= 4
        span := 65536
        if wide:
            span = 131072
        if phys // span != (phys + length - 1) // span:
            raise("ArgumentError", "Isa8237 : le tampon traverse une frontière de " + str(span // 1024) + " Kio")
        a := phys & 0xFFFF
        count := length - 1
        if wide:
            a = (phys >> 1) & 0xFFFF
            count = length // 2 - 1
        mode := direction | ISA_SINGLE | (ch & 3)
        if auto_init:
            mode = mode | ISA_AUTO
        self.disable(ch)
        hw.outb(self._flip_port(ch), 0xFF)
        hw.outb(self._addr_port(ch), a & 255)
        hw.outb(self._addr_port(ch), (a >> 8) & 255)
        hw.outb(self._page_port(ch), (phys >> 16) & 255)
        hw.outb(self._flip_port(ch), 0xFF)
        hw.outb(self._count_port(ch), count & 255)
        hw.outb(self._count_port(ch), (count >> 8) & 255)
        hw.outb(self._mode_port(ch), mode)
        self.programmed[ch * 3] = phys
        self.programmed[ch * 3 + 1] = length
        self.programmed[ch * 3 + 2] = mode

    # Compte restant (octets ; mots pour 5..7) lu dans le contrôleur.
    func remaining(ch: int) -> int:
        hw.outb(self._flip_port(ch), 0xFF)
        lo := hw.inb(self._count_port(ch))
        hi := hw.inb(self._count_port(ch))
        return ((hi << 8) | lo) + 1

    # Bits « fin de compte » (TC) des canaux 0..3 (ou 4..7 si high).
    func terminal_counts(high: bool) -> int:
        if high:
            return hw.inb(0xD0) & 15
        return hw.inb(0x08) & 15

    func mode_of(ch: int) -> int:
        return self.programmed[ch * 3 + 2]

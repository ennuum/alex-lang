# alex: native
# ALEX STANDARD LIBRARY — network_driver.network_ring
#
# Anneaux de descripteurs génériques pour cartes réseau (émission et réception) :
#   - DescFormat : position des champs dans un descripteur (adresse du tampon, longueur, commande, état, bit
#     « fait » DD, bit « fin de paquet » EOP) — format « legacy » Intel e1000 fourni, autres décrits pareil ;
#   - TxRing : enfile un PacketBuffer (descripteur rempli, queue avancée), récupère ceux que la carte a émis
#     (bit DD), les tampons revenant à leur réserve ; état plein ; registre de queue (TDT) écrit par un rappel ;
#   - RxRing : garni de tampons de la réserve ; harvest relève les paquets reçus (DD), renvoie leurs tampons
#     (longueur prise dans le descripteur), regarnit et avance la queue (RDT) ; trames en plusieurs
#     descripteurs signalées.
# Les descripteurs sont en mémoire DMA (dma.dma_mapping.DmaRing) ; l'adresse physique des tampons est celle
# du noyau (identité), comme dans les pilotes existants.
#
#   use network_driver.network_ring as nr
#   tx := nr.TxRing(32, nr.legacy_tx(), pool)
#   tx.send(buffer)                  # false si plein
#   tx.reclaim()                     # tampons émis rendus à la réserve
#   rx := nr.RxRing(32, nr.legacy_rx(), pool)
#   rx.fill()
#   for b in rx.harvest(16): ...     # paquets reçus
#
# Erreurs : NoBuffer (réserve vide au garnissage initial), ArgumentError. Compilable en natif.

from core use len
from collections use append
use hw
use dma.dma_mapping as dm
from dma.dma_mapping use DmaRing
use network_driver.network_buffer as nb
from network_driver.network_buffer use PacketBuffer, BufferPool

class DescFormat:
    size: int := 16
    addr_off: int := 0
    len_off: int := 8
    len_bytes: int := 2
    cmd_off: int := 11
    status_off: int := 12
    dd_bit: int := 1
    eop_bit: int := 2
    cmd_value: int := 0
    errors_off: int := -1

    func init(size: int, addr_off: int, len_off: int, len_bytes: int, cmd_off: int, status_off: int, dd_bit: int, eop_bit: int):
        self.size = size
        self.addr_off = addr_off
        self.len_off = len_off
        self.len_bytes = len_bytes
        self.cmd_off = cmd_off
        self.status_off = status_off
        self.dd_bit = dd_bit
        self.eop_bit = eop_bit
        self.cmd_value = 0
        self.errors_off = -1

# e1000 émission : addr 0, length 8 (16 bits), cso 10, cmd 11 (EOP 0x01, IFCS 0x02, RS 0x08), status 12 (DD 1).
func legacy_tx() -> DescFormat:
    f := DescFormat(16, 0, 8, 2, 11, 12, 1, 0)
    f.cmd_value = 0x0B
    return f

# e1000 réception : addr 0, length 8, csum 10, status 12 (DD 1, EOP 2), errors 13.
func legacy_rx() -> DescFormat:
    f := DescFormat(16, 0, 8, 2, -1, 12, 1, 2)
    f.errors_off = 13
    return f

class TxRing:
    ring: DmaRing
    fmt: DescFormat
    pool: BufferPool
    slots: list[PacketBuffer?] := []
    on_tail: func(int)?
    sent: int := 0
    reclaimed: int := 0
    full_events: int := 0

    func init(count: int, fmt: DescFormat, pool: BufferPool):
        self.ring = DmaRing(count, fmt.size, 128)
        hw.zero(self.ring.buffer.addr, count * fmt.size)
        self.fmt = fmt
        self.pool = pool
        self.slots = [null for i in 0..count]
        self.on_tail = null
        self.sent = 0
        self.reclaimed = 0
        self.full_events = 0

    func count() -> int:
        return self.ring.count

    func phys() -> int:
        return self.ring.phys()

    func full() -> bool:
        return self.ring.space() <= 1

    func in_flight() -> int:
        return self.ring.used

    # Enfile b ; false si l'anneau est plein (un descripteur reste libre pour distinguer plein et vide).
    func send(b: PacketBuffer) -> bool:
        if self.full():
            self.reclaim()
            if self.full():
                self.full_events += 1
                return false
        i := self.ring.produce()
        d := self.ring.desc(i)
        hw.zero(d, self.fmt.size)
        hw.poke64(d + self.fmt.addr_off, b.data())
        if self.fmt.len_bytes == 2:
            hw.poke16(d + self.fmt.len_off, b.length)
        else:
            hw.poke32(d + self.fmt.len_off, b.length)
        if self.fmt.cmd_off >= 0:
            hw.poke8(d + self.fmt.cmd_off, self.fmt.cmd_value)
        self.slots[i] = b
        self.sent += 1
        f := self.on_tail
        if f != null:
            f(self.ring.tail)
        return true

    # Rend à la réserve les tampons des descripteurs terminés (DD) ; renvoie leur nombre.
    func reclaim() -> int:
        n := 0
        while not self.ring.empty():
            d := self.ring.desc(self.ring.head)
            if hw.peek8(d + self.fmt.status_off) & self.fmt.dd_bit == 0:
                break
            i := self.ring.consume()
            b := self.slots[i]
            if b != null:
                self.pool.put(b)
            self.slots[i] = null
            n += 1
        self.reclaimed += n
        return n

    # Côté carte simulée : marque comme émis le descripteur i.
    func device_complete(i: int):
        d := self.ring.desc(i)
        hw.poke8(d + self.fmt.status_off, hw.peek8(d + self.fmt.status_off) | self.fmt.dd_bit)

    func describe() -> str:
        return "anneau TX " + str(self.ring.count) + " : en vol " + str(self.ring.used) + ", émis " + str(self.sent) + ", récupérés " + str(self.reclaimed) + ", plein " + str(self.full_events) + " fois"

class RxRing:
    ring: DmaRing
    fmt: DescFormat
    pool: BufferPool
    slots: list[PacketBuffer?] := []
    next: int := 0
    tail: int := 0
    on_tail: func(int)?
    received: int := 0
    errors: int := 0
    fragments: int := 0
    starved: int := 0

    func init(count: int, fmt: DescFormat, pool: BufferPool):
        self.ring = DmaRing(count, fmt.size, 128)
        hw.zero(self.ring.buffer.addr, count * fmt.size)
        self.fmt = fmt
        self.pool = pool
        self.slots = [null for i in 0..count]
        self.next = 0
        self.tail = 0
        self.on_tail = null
        self.received = 0
        self.errors = 0
        self.fragments = 0
        self.starved = 0

    func count() -> int:
        return self.ring.count

    func phys() -> int:
        return self.ring.phys()

    func _arm(i: int) -> bool:
        b := self.pool.get()
        if b == null:
            self.starved += 1
            return false
        b.reset_raw(0)
        d := self.ring.desc(i)
        hw.zero(d, self.fmt.size)
        hw.poke64(d + self.fmt.addr_off, b.base)
        self.slots[i] = b
        return true

    # Garnit tous les descripteurs vides ; renvoie le nombre garni. NoBuffer si aucun ne peut l'être au départ.
    func fill() -> int:
        n := 0
        i := 0
        while i < self.ring.count:
            if self.slots[i] == null:
                if self._arm(i):
                    n += 1
            i += 1
        if n == 0 and self.slots[0] == null:
            raise("NoBuffer", "RxRing : réserve vide")
        self.tail = (self.next + self.ring.count - 1) % self.ring.count
        f := self.on_tail
        if f != null:
            f(self.tail)
        return n

    # Paquets reçus (au plus max) ; les descripteurs sont regarnis et la queue avancée.
    func harvest(max: int) -> list[PacketBuffer]:
        out: list[PacketBuffer] := []
        while len(out) < max:
            i := self.next
            d := self.ring.desc(i)
            st := hw.peek8(d + self.fmt.status_off)
            if st & self.fmt.dd_bit == 0:
                break
            b := self.slots[i]
            length := hw.peek16(d + self.fmt.len_off)
            bad := false
            if self.fmt.errors_off >= 0 and hw.peek8(d + self.fmt.errors_off) != 0:
                bad = true
            if self.fmt.eop_bit != 0 and st & self.fmt.eop_bit == 0:
                self.fragments += 1
                bad = true
            if b != null:
                if bad:
                    self.errors += 1
                    self.pool.put(b)
                else:
                    b.reset_raw(length)
                    append(out, b)
                    self.received += 1
            self.slots[i] = null
            self._arm(i)
            self.tail = i
            self.next = (i + 1) % self.ring.count
        if len(out) > 0:
            f := self.on_tail
            if f != null:
                f(self.tail)
        return out

    # Côté carte simulée : dépose n octets de src dans le descripteur suivant à remplir, avec le bit DD.
    func device_receive(src: int, n: int, eop: bool, error: int) -> bool:
        i := self.next
        k := 0
        while k < self.ring.count:
            d := self.ring.desc(i)
            if hw.peek8(d + self.fmt.status_off) & self.fmt.dd_bit == 0:
                b := self.slots[i]
                if b == null:
                    return false
                hw.copy(b.base, src, n)
                hw.poke16(d + self.fmt.len_off, n)
                if self.fmt.errors_off >= 0:
                    hw.poke8(d + self.fmt.errors_off, error)
                st := self.fmt.dd_bit
                if eop:
                    st = st | self.fmt.eop_bit
                hw.poke8(d + self.fmt.status_off, st)
                return true
            i = (i + 1) % self.ring.count
            k += 1
        return false

    func describe() -> str:
        return "anneau RX " + str(self.ring.count) + " : reçus " + str(self.received) + ", erreurs " + str(self.errors) + ", fragments " + str(self.fragments) + ", sans tampon " + str(self.starved)

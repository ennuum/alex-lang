# alex: native
# ALEX STANDARD LIBRARY — network_driver.network_buffer
#
# Tampons de paquets pour les pilotes réseau :
#   - PacketBuffer : zone contiguë (adressable par la carte, DMA) avec une marge de tête (headroom) : on écrit
#     la charge utile, puis on « pousse » les en-têtes devant (push) ; à la réception on les « retire » (pull).
#     Lecture / écriture d'entiers gros-boutistes, d'octets, de chaînes, à une position relative aux données ;
#   - BufferPool : réserve de tampons de taille fixe (2048 octets) pris dans des pages, réutilisés.
#
#   use network_driver.network_buffer as nb
#   pool := nb.BufferPool(64)
#   b := pool.get()
#   b.put_string("bonjour")                # charge utile
#   h := b.push(8)                         # adresse de 8 octets d'en-tête devant
#   ...
#   pool.put(b)
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use network_driver.ethernet as eth

const BUFFER_SIZE := 2048
const HEADROOM := 128

class PacketBuffer:
    base: int := 0          # début de la zone
    capacity: int := 2048
    start: int := 0         # décalage du premier octet de données
    length: int := 0        # octets de données
    pooled: bool := false

    func init(base: int, capacity: int):
        self.base = base
        self.capacity = capacity
        self.start = HEADROOM
        self.length = 0
        self.pooled = false

    # Remet à vide (marge de tête par défaut).
    func reset():
        self.start = HEADROOM
        self.length = 0

    # Données à partir du début de la zone (réception par la carte, sans marge).
    func reset_raw(length: int):
        self.start = 0
        self.length = length

    func data() -> int:
        return self.base + self.start

    func headroom() -> int:
        return self.start

    func tailroom() -> int:
        return self.capacity - self.start - self.length

    # Ajoute n octets en fin de données ; renvoie leur adresse.
    func put(n: int) -> int:
        if n > self.tailroom():
            raise("MemoryError", "PacketBuffer.put : plus de place (" + str(n) + " octets)")
        a := self.base + self.start + self.length
        self.length += n
        return a

    # Ajoute n octets devant les données (en-tête) ; renvoie leur adresse.
    func push(n: int) -> int:
        if n > self.start:
            raise("MemoryError", "PacketBuffer.push : marge de tête insuffisante")
        self.start -= n
        self.length += n
        return self.base + self.start

    # Retire n octets du début (en-tête lu) ; renvoie l'adresse de ce qui suit.
    func pull(n: int) -> int:
        if n > self.length:
            raise("MemoryError", "PacketBuffer.pull : paquet trop court")
        self.start += n
        self.length -= n
        return self.base + self.start

    func trim(n: int):
        if n < self.length:
            self.length = n

    func _at(offset: int, n: int) -> int:
        if offset < 0 or offset + n > self.length:
            raise("MemoryError", "PacketBuffer : accès " + str(offset) + "+" + str(n) + " hors des " + str(self.length) + " octets")
        return self.base + self.start + offset

    func u8(offset: int) -> int:
        return hw.peek8(self._at(offset, 1))

    func u16(offset: int) -> int:
        return eth.read16be(self._at(offset, 2))

    func u32(offset: int) -> int:
        return eth.read32be(self._at(offset, 4))

    func set_u8(offset: int, v: int):
        hw.poke8(self._at(offset, 1), v)

    func set_u16(offset: int, v: int):
        eth.write16be(self._at(offset, 2), v)

    func set_u32(offset: int, v: int):
        eth.write32be(self._at(offset, 4), v)

    func string(offset: int, n: int) -> str:
        return hw.string_at(self._at(offset, n), n)

    func put_string(s: str) -> int:
        n := hw.byte_size(s)
        a := self.put(n)
        hw.store_string(s, a)
        return a

    # Complète par des zéros jusqu'à n octets (trame minimale de 60 octets).
    func pad_to(n: int):
        if self.length < n:
            a := self.put(n - self.length)
            hw.zero(a, self.base + self.start + self.length - a)

    func copy_from(src: int, n: int):
        a := self.put(n)
        hw.copy(a, src, n)

class BufferPool:
    free_list: list[PacketBuffer] := []
    pages: list[int] := []
    created: int := 0
    in_use: int := 0
    limit: int := 0

    # limit : nombre maximal de tampons (0 : sans limite).
    func init(limit: int):
        self.free_list = []
        self.pages = []
        self.created = 0
        self.in_use = 0
        self.limit = limit

    # Un tampon vide (null si la limite est atteinte).
    func get() -> PacketBuffer?:
        if len(self.free_list) == 0:
            if self.limit > 0 and self.created >= self.limit:
                return null
            p := hw.alloc_pages(1)
            append(self.pages, p)
            append(self.free_list, PacketBuffer(p, BUFFER_SIZE))
            append(self.free_list, PacketBuffer(p + BUFFER_SIZE, BUFFER_SIZE))
            self.created += 2
        n := len(self.free_list)
        b := self.free_list[n - 1]
        keep: list[PacketBuffer] := []
        i := 0
        while i < n - 1:
            append(keep, self.free_list[i])
            i += 1
        self.free_list = keep
        b.reset()
        b.pooled = true
        self.in_use += 1
        return b

    func put(b: PacketBuffer):
        if b.pooled:
            b.pooled = false
            append(self.free_list, b)
            self.in_use -= 1

    func available() -> int:
        return len(self.free_list)

# alex: native
# ALEX STANDARD LIBRARY — storage_driver.block_device
#
# Périphérique de blocs : l'interface commune des disques (ATA, AHCI, NVMe, virtio, disque en mémoire,
# partition), utilisée par les systèmes de fichiers et storage_driver.storage_queue.
#
#   interface BlockDevice
#       name() -> str
#       block_size() -> int                    512 en général (4096 pour certains NVMe)
#       block_count() -> int
#       read_blocks(lba, count, buf) -> bool   buf : adresse (mémoire du noyau / tampon DMA)
#       write_blocks(lba, count, buf) -> bool
#       flush() -> bool
#       read_only() -> bool
#
# Fournis ici : RamDisk (en mémoire), Partition (vue décalée d'un autre périphérique), BlockCache (cache de
# blocs avec écriture différée), et les fonctions read_bytes / write_bytes (accès à l'octet au-dessus des blocs).
#
#   d := RamDisk("ram0", 512, 2048)              # 1 Mio
#   buf := hw.alloc_pages(1)
#   d.write_blocks(10, 1, buf)
#   p := Partition(d, 2048, 4096, "ram0p1")
#
# Erreurs : DeviceIoError (hors du disque, lecture seule). Compilable en natif (# alex: native).

from collections use append
from core use len
use hw

interface BlockDevice:
    func name() -> str
    func block_size() -> int
    func block_count() -> int
    func read_blocks(lba: int, count: int, buf: int) -> bool
    func write_blocks(lba: int, count: int, buf: int) -> bool
    func flush() -> bool
    func read_only() -> bool

func check_range(d: BlockDevice, lba: int, count: int):
    if lba < 0 or count < 0 or lba + count > d.block_count():
        raise("DeviceIoError", d.name() + " : blocs " + str(lba) + "+" + str(count) + " hors du disque (" + str(d.block_count()) + " blocs)")

func capacity(d: BlockDevice) -> int:
    return d.block_size() * d.block_count()

func size_text(n: int) -> str:
    if n >= 1073741824:
        return str(n // 1073741824) + "," + str((n % 1073741824) * 10 // 1073741824) + " Gio"
    if n >= 1048576:
        return str(n // 1048576) + " Mio"
    return str(n // 1024) + " Kio"

func describe(d: BlockDevice) -> str:
    t := d.name() + " : " + str(d.block_count()) + " blocs de " + str(d.block_size()) + " octets (" + size_text(capacity(d)) + ")"
    if d.read_only():
        t = t + ", lecture seule"
    return t

# ---------------------------------------------------------------- disque en mémoire
class RamDisk implements BlockDevice:
    label: str := ""
    bsize: int := 512
    count: int := 0
    base: int := 0
    pages: int := 0
    ro: bool := false
    reads: int := 0
    writes: int := 0

    func init(label: str, bsize: int, count: int):
        self.label = label
        self.bsize = bsize
        self.count = count
        self.pages = (bsize * count + 4095) // 4096
        self.base = hw.alloc_pages(self.pages)
        self.ro = false
        self.reads = 0
        self.writes = 0

    func name() -> str:
        return self.label

    func block_size() -> int:
        return self.bsize

    func block_count() -> int:
        return self.count

    func read_blocks(lba: int, count: int, buf: int) -> bool:
        check_range(self, lba, count)
        hw.copy(buf, self.base + lba * self.bsize, count * self.bsize)
        self.reads += count
        return true

    func write_blocks(lba: int, count: int, buf: int) -> bool:
        check_range(self, lba, count)
        if self.ro:
            raise("DeviceIoError", self.label + " : lecture seule")
        hw.copy(self.base + lba * self.bsize, buf, count * self.bsize)
        self.writes += count
        return true

    func flush() -> bool:
        return true

    func read_only() -> bool:
        return self.ro

    func set_read_only(ro: bool):
        self.ro = ro

    func free():
        hw.free_pages(self.base, self.pages)

# ---------------------------------------------------------------- partition
class Partition implements BlockDevice:
    parent: BlockDevice
    start: int := 0
    count: int := 0
    label: str := ""

    func init(parent: BlockDevice, start: int, count: int, label: str):
        self.parent = parent
        self.start = start
        self.count = count
        self.label = label
        if start < 0 or start + count > parent.block_count():
            raise("DeviceIoError", label + " : partition hors du disque " + parent.name())

    func name() -> str:
        return self.label

    func block_size() -> int:
        return self.parent.block_size()

    func block_count() -> int:
        return self.count

    func read_blocks(lba: int, count: int, buf: int) -> bool:
        check_range(self, lba, count)
        return self.parent.read_blocks(self.start + lba, count, buf)

    func write_blocks(lba: int, count: int, buf: int) -> bool:
        check_range(self, lba, count)
        return self.parent.write_blocks(self.start + lba, count, buf)

    func flush() -> bool:
        return self.parent.flush()

    func read_only() -> bool:
        return self.parent.read_only()

# ---------------------------------------------------------------- cache de blocs
class BlockCache implements BlockDevice:
    dev: BlockDevice
    slots: int := 0
    data: int := 0              # slots blocs contigus
    tags: list[int] := []       # lba en cache (-1 : vide)
    dirty: list[bool] := []
    stamp: list[int] := []      # dernier usage (LRU)
    clock: int := 0
    hits: int := 0
    misses: int := 0
    write_back: bool := true

    func init(dev: BlockDevice, slots: int, write_back: bool):
        self.dev = dev
        self.slots = slots
        self.data = hw.alloc_pages((slots * dev.block_size() + 4095) // 4096)
        self.tags = [-1 for i in 0..slots]
        self.dirty = [false for i in 0..slots]
        self.stamp = [0 for i in 0..slots]
        self.clock = 0
        self.hits = 0
        self.misses = 0
        self.write_back = write_back

    func name() -> str:
        return self.dev.name() + " (cache)"

    func block_size() -> int:
        return self.dev.block_size()

    func block_count() -> int:
        return self.dev.block_count()

    func read_only() -> bool:
        return self.dev.read_only()

    func _slot_addr(i: int) -> int:
        return self.data + i * self.dev.block_size()

    func _find(lba: int) -> int:
        i := 0
        while i < self.slots:
            if self.tags[i] == lba:
                return i
            i += 1
        return -1

    func _evict() -> int:
        best := 0
        i := 1
        while i < self.slots:
            if self.tags[i] == -1:
                return i
            if self.stamp[i] < self.stamp[best]:
                best = i
            i += 1
        if self.tags[best] != -1 and self.dirty[best]:
            self.dev.write_blocks(self.tags[best], 1, self._slot_addr(best))
            self.dirty[best] = false
        return best

    func _load(lba: int) -> int:
        i := self._find(lba)
        self.clock += 1
        if i >= 0:
            self.hits += 1
            self.stamp[i] = self.clock
            return i
        self.misses += 1
        i = self._evict()
        self.dev.read_blocks(lba, 1, self._slot_addr(i))
        self.tags[i] = lba
        self.dirty[i] = false
        self.stamp[i] = self.clock
        return i

    func read_blocks(lba: int, count: int, buf: int) -> bool:
        check_range(self, lba, count)
        bs := self.dev.block_size()
        k := 0
        while k < count:
            i := self._load(lba + k)
            hw.copy(buf + k * bs, self._slot_addr(i), bs)
            k += 1
        return true

    func write_blocks(lba: int, count: int, buf: int) -> bool:
        check_range(self, lba, count)
        bs := self.dev.block_size()
        k := 0
        while k < count:
            i := self._find(lba + k)
            self.clock += 1
            if i < 0:
                i = self._evict()
                self.tags[i] = lba + k
            hw.copy(self._slot_addr(i), buf + k * bs, bs)
            self.stamp[i] = self.clock
            if self.write_back:
                self.dirty[i] = true
            else:
                self.dev.write_blocks(lba + k, 1, self._slot_addr(i))
            k += 1
        return true

    # Écrit les blocs modifiés, puis vide le cache du disque.
    func flush() -> bool:
        i := 0
        while i < self.slots:
            if self.tags[i] != -1 and self.dirty[i]:
                self.dev.write_blocks(self.tags[i], 1, self._slot_addr(i))
                self.dirty[i] = false
            i += 1
        return self.dev.flush()

    func dirty_count() -> int:
        n := 0
        for d in self.dirty:
            if d:
                n += 1
        return n

# ---------------------------------------------------------------- accès à l'octet
# Lit n octets à partir de l'octet offset du périphérique vers dst (blocs partiels gérés par un tampon).
func read_bytes(d: BlockDevice, offset: int, n: int, dst: int):
    bs := d.block_size()
    tmp := hw.alloc_pages((bs + 4095) // 4096)
    pos := offset
    done := 0
    while done < n:
        lba := pos // bs
        within := pos % bs
        take := bs - within
        if take > n - done:
            take = n - done
        d.read_blocks(lba, 1, tmp)
        hw.copy(dst + done, tmp + within, take)
        done += take
        pos += take
    hw.free_pages(tmp, (bs + 4095) // 4096)

# Écrit n octets de src à partir de l'octet offset (lecture-modification-écriture des blocs partiels).
func write_bytes(d: BlockDevice, offset: int, n: int, src: int):
    bs := d.block_size()
    tmp := hw.alloc_pages((bs + 4095) // 4096)
    pos := offset
    done := 0
    while done < n:
        lba := pos // bs
        within := pos % bs
        take := bs - within
        if take > n - done:
            take = n - done
        if take < bs:
            d.read_blocks(lba, 1, tmp)
        hw.copy(tmp + within, src + done, take)
        d.write_blocks(lba, 1, tmp)
        done += take
        pos += take
    hw.free_pages(tmp, (bs + 4095) // 4096)

# Lit n octets à offset et les renvoie en str (binaire).
func read_string(d: BlockDevice, offset: int, n: int) -> str:
    tmp := hw.alloc_pages((n + 4095) // 4096)
    read_bytes(d, offset, n, tmp)
    s := hw.string_at(tmp, n)
    hw.free_pages(tmp, (n + 4095) // 4096)
    return s

func write_string(d: BlockDevice, offset: int, s: str):
    n := hw.byte_size(s)
    tmp := hw.alloc_pages((n + 4095) // 4096)
    hw.store_string(s, tmp)
    write_bytes(d, offset, n, tmp)
    hw.free_pages(tmp, (n + 4095) // 4096)

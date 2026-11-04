# alex: native
# ALEX STANDARD LIBRARY — storage_driver.storage_cache
#
# Cache de blocs avec lecture anticipée (complément de block_device.BlockCache) :
#   - détection des lectures séquentielles : la fenêtre d'anticipation double (de min_ahead à max_ahead
#     blocs) tant que les lectures se suivent, et revient au minimum sur un accès aléatoire ;
#   - remplacement LRU, écriture différée avec limite de blocs modifiés (au-delà, les plus anciens sont
#     écrits) ; write_through possible ; écriture forcée (fua) qui contourne le délai ;
#   - invalidate (après une écriture qui a contourné le cache, ex. DMA direct), sync ;
#   - statistiques : succès, échecs, blocs anticipés et ceux réellement utilisés (efficacité).
#
#   use storage_driver.storage_cache as sc
#   c := sc.ReadaheadCache(disque, 256, 4, 64)      # 256 blocs en cache, anticipation 4..64
#   c.read_blocks(0, 8, tampon)                      # BlockDevice comme les autres
#   print(c.stats().describe())
#
# Erreurs : CacheError (paramètres invalides), erreurs du périphérique. Compilable en natif.

from core use len
from collections use append
use hw
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice

class CacheStats:
    hits: int := 0
    misses: int := 0
    prefetched: int := 0
    prefetch_used: int := 0
    writebacks: int := 0
    evictions: int := 0

    func init():
        self.hits = 0
        self.misses = 0
        self.prefetched = 0
        self.prefetch_used = 0
        self.writebacks = 0
        self.evictions = 0

    # Part de succès en pour mille.
    func hit_rate() -> int:
        t := self.hits + self.misses
        if t == 0:
            return 0
        return self.hits * 1000 // t

    func describe() -> str:
        return "succès " + str(self.hits) + ", échecs " + str(self.misses) + " (" + str(self.hit_rate() // 10) + " %), anticipés " + str(self.prefetched) + " dont utilisés " + str(self.prefetch_used) + ", écritures différées " + str(self.writebacks) + ", évictions " + str(self.evictions)

class ReadaheadCache implements BlockDevice:
    dev: BlockDevice
    slots: int := 0
    data: int := 0
    pages: int := 0
    tags: list[int] := []
    dirty: list[bool] := []
    ahead: list[bool] := []      # chargé par anticipation, pas encore lu
    stamp: list[int] := []
    clock: int := 0
    min_ahead: int := 4
    max_ahead: int := 64
    window: int := 4
    next_seq: int := -1
    dirty_limit: int := 0
    write_through: bool := false
    st: CacheStats

    func init(dev: BlockDevice, slots: int, min_ahead: int, max_ahead: int):
        if slots < 2 or min_ahead < 0 or max_ahead < min_ahead or max_ahead >= slots:
            raise("CacheError", "ReadaheadCache : paramètres invalides (slots >= 2, 0 <= min <= max < slots)")
        self.dev = dev
        self.slots = slots
        self.pages = (slots * dev.block_size() + 4095) // 4096
        self.data = hw.alloc_pages(self.pages)
        self.tags = [-1 for i in 0..slots]
        self.dirty = [false for i in 0..slots]
        self.ahead = [false for i in 0..slots]
        self.stamp = [0 for i in 0..slots]
        self.clock = 0
        self.min_ahead = min_ahead
        self.max_ahead = max_ahead
        self.window = min_ahead
        self.next_seq = -1
        self.dirty_limit = slots // 2
        self.write_through = false
        self.st = CacheStats()

    func name() -> str:
        return self.dev.name() + " (anticipation)"

    func block_size() -> int:
        return self.dev.block_size()

    func block_count() -> int:
        return self.dev.block_count()

    func read_only() -> bool:
        return self.dev.read_only()

    func stats() -> CacheStats:
        return self.st

    func _addr(i: int) -> int:
        return self.data + i * self.dev.block_size()

    func _find(lba: int) -> int:
        i := 0
        while i < self.slots:
            if self.tags[i] == lba:
                return i
            i += 1
        return -1

    func _writeback(i: int):
        if self.tags[i] != -1 and self.dirty[i]:
            self.dev.write_blocks(self.tags[i], 1, self._addr(i))
            self.dirty[i] = false
            self.st.writebacks += 1

    func _victim() -> int:
        best := -1
        i := 0
        while i < self.slots:
            if self.tags[i] == -1:
                return i
            if best < 0 or self.stamp[i] < self.stamp[best]:
                best = i
            i += 1
        self._writeback(best)
        self.st.evictions += 1
        self.tags[best] = -1
        return best

    func _fill(lba: int, prefetch: bool) -> int:
        i := self._victim()
        self.dev.read_blocks(lba, 1, self._addr(i))
        self.tags[i] = lba
        self.dirty[i] = false
        self.ahead[i] = prefetch
        self.clock += 1
        self.stamp[i] = self.clock
        if prefetch:
            self.st.prefetched += 1
        return i

    func _get(lba: int) -> int:
        i := self._find(lba)
        self.clock += 1
        if i >= 0:
            self.st.hits += 1
            if self.ahead[i]:
                self.ahead[i] = false
                self.st.prefetch_used += 1
            self.stamp[i] = self.clock
            return i
        self.st.misses += 1
        return self._fill(lba, false)

    func read_blocks(lba: int, count: int, buf: int) -> bool:
        bd.check_range(self, lba, count)
        if lba == self.next_seq:
            self.window = self.window * 2 if self.window > 0 else 1
            if self.window > self.max_ahead:
                self.window = self.max_ahead
        else:
            self.window = self.min_ahead
        bs := self.dev.block_size()
        k := 0
        while k < count:
            i := self._get(lba + k)
            hw.copy(buf + k * bs, self._addr(i), bs)
            k += 1
        self.next_seq = lba + count
        # anticipation
        a := 0
        while a < self.window and lba + count + a < self.dev.block_count():
            if self._find(lba + count + a) < 0:
                self._fill(lba + count + a, true)
            a += 1
        return true

    func _dirty_count() -> int:
        n := 0
        for d in self.dirty:
            if d:
                n += 1
        return n

    func write_blocks(lba: int, count: int, buf: int) -> bool:
        bd.check_range(self, lba, count)
        if self.dev.read_only():
            raise("DeviceIoError", self.dev.name() + " : lecture seule")
        bs := self.dev.block_size()
        k := 0
        while k < count:
            i := self._find(lba + k)
            if i < 0:
                i = self._victim()
                self.tags[i] = lba + k
            hw.copy(self._addr(i), buf + k * bs, bs)
            self.clock += 1
            self.stamp[i] = self.clock
            self.ahead[i] = false
            if self.write_through:
                self.dev.write_blocks(lba + k, 1, self._addr(i))
            else:
                self.dirty[i] = true
            k += 1
        while self._dirty_count() > self.dirty_limit:
            oldest := -1
            j := 0
            while j < self.slots:
                if self.dirty[j] and (oldest < 0 or self.stamp[j] < self.stamp[oldest]):
                    oldest = j
                j += 1
            self._writeback(oldest)
        return true

    # Écriture qui atteint le support avant de rendre la main (Force Unit Access).
    func write_fua(lba: int, count: int, buf: int) -> bool:
        self.write_blocks(lba, count, buf)
        k := 0
        while k < count:
            i := self._find(lba + k)
            if i >= 0:
                self._writeback(i)
            k += 1
        return self.dev.flush()

    # Oublie les blocs [lba, lba + count) (les modifications non écrites sont perdues).
    func invalidate(lba: int, count: int) -> int:
        n := 0
        i := 0
        while i < self.slots:
            t := self.tags[i]
            if t >= lba and t < lba + count:
                self.tags[i] = -1
                self.dirty[i] = false
                self.ahead[i] = false
                n += 1
            i += 1
        return n

    func flush() -> bool:
        i := 0
        while i < self.slots:
            self._writeback(i)
            i += 1
        return self.dev.flush()

    func dirty_blocks() -> int:
        return self._dirty_count()

    func cached() -> int:
        n := 0
        for t in self.tags:
            if t != -1:
                n += 1
        return n

    func free():
        self.flush()
        hw.free_pages(self.data, self.pages)

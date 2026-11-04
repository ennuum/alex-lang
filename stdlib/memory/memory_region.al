# ALEX STANDARD LIBRARY — memory.memory_region
#
# Plages d'adresses : modèle et calculs (sans accès à la mémoire). Sert à décrire la carte mémoire d'un
# processus, d'un périphérique (fenêtres MMIO, BAR PCI) ou d'un noyau, et à raisonner dessus.
#
#   MemoryRegion(start, size, name, prot, kind)   contains overlaps intersect subtract split end
#   RegionMap                                      ensemble ordonné de régions DISJOINTES : insert, find(addr),
#                                                  remove, gaps (trous), merge_adjacent, total_size
#   process_map()                                  carte du processus courant (/proc/self/maps, Linux)
#   parse_maps(text)                               analyse d'un texte au format /proc/<pid>/maps
#
#   use memory.memory_region as mr
#   r := mr.MemoryRegion(0x1000, 0x2000, "code", "r-x")
#   print(r.contains(0x1800), mr.hex(r.end()))     # true 0x3000
#   m := mr.RegionMap()
#   m.insert(r)
#   m.insert(mr.MemoryRegion(0x4000, 0x1000, "pile", "rw-"))
#   print(m.find(0x4010).name)                      # pile
#   print(m.gaps(0, 0x6000))                        # trous : [0x0..0x1000), [0x3000..0x4000), [0x5000..0x6000)
#   for reg in mr.process_map().regions():
#       print(reg)
#
# Erreurs : ArgumentError (taille négative, chevauchement à l'insertion), TypeError.

from core use len, type
from collections use append, insert, pop
use string as _s
use io as _io

_HEX := "0123456789abcdef"

func hex(n, width=0):
    out := ""
    v := n
    while v > 0:
        out = str(_HEX[v % 16]) + out
        v = v // 16
    if out == "":
        out = "0"
    while len(out) < width:
        out = "0" + out
    return "0x" + out

func _need(fn, v, label):
    if type(v) != "int":
        raise("TypeError", fn + " : " + label + " int attendu (obtenu '" + type(v) + "')")

class MemoryRegion:
    func init(start, size, name="", prot="rw-", kind="anonymous"):
        _need("MemoryRegion", start, "début")
        _need("MemoryRegion", size, "taille")
        if size < 0 or start < 0:
            raise("ArgumentError", "MemoryRegion : début et taille >= 0 attendus")
        self.start = start
        self.size = size
        self.name = name
        self.prot = prot
        self.kind = kind

    # Première adresse APRÈS la région.
    func end():
        return self.start + self.size

    func is_empty():
        return self.size == 0

    func contains(addr):
        return addr >= self.start and addr < self.start + self.size

    func contains_range(start, size):
        return start >= self.start and start + size <= self.end()

    func overlaps(other):
        return self.start < other.end() and other.start < self.end()

    func adjacent(other):
        return self.end() == other.start or other.end() == self.start

    # Intersection (ou null).
    func intersect(other):
        a := self.start
        if other.start > a:
            a = other.start
        b := self.end()
        if other.end() < b:
            b = other.end()
        if b <= a:
            return null
        return MemoryRegion(a, b - a, self.name, self.prot, self.kind)

    # Parties de self hors de other (0, 1 ou 2 régions).
    func subtract(other):
        if not self.overlaps(other):
            return [self]
        out := []
        if other.start > self.start:
            append(out, MemoryRegion(self.start, other.start - self.start, self.name, self.prot, self.kind))
        if other.end() < self.end():
            append(out, MemoryRegion(other.end(), self.end() - other.end(), self.name, self.prot, self.kind))
        return out

    # [avant offset, à partir d'offset].
    func split(offset):
        if offset <= 0 or offset >= self.size:
            raise("ArgumentError", "MemoryRegion.split : décalage hors de 1.." + str(self.size - 1))
        return [MemoryRegion(self.start, offset, self.name, self.prot, self.kind),
                MemoryRegion(self.start + offset, self.size - offset, self.name, self.prot, self.kind)]

    func readable():
        return _s.contains(self.prot, "r")

    func writable():
        return _s.contains(self.prot, "w")

    func executable():
        return _s.contains(self.prot, "x")

    # Décalage de addr dans la région.
    func offset_of(addr):
        if not self.contains(addr):
            raise("ArgumentError", "MemoryRegion.offset_of : " + hex(addr) + " hors de la région")
        return addr - self.start

    func __eq__(other):
        return isinstance(other, MemoryRegion) and other.start == self.start and other.size == self.size and other.name == self.name

    func __str__():
        return hex(self.start, 12) + "-" + hex(self.end(), 12) + " " + self.prot + " " + _size_text(self.size) + " " + self.name

func _size_text(n):
    if n >= 1073741824 and n % 1073741824 == 0:
        return str(n // 1073741824) + "G"
    if n >= 1048576 and n % 1048576 == 0:
        return str(n // 1048576) + "M"
    if n >= 1024 and n % 1024 == 0:
        return str(n // 1024) + "K"
    return str(n)

class RegionMap:
    func init(regions=null):
        self._r = []
        if regions != null:
            for r in regions:
                self.insert(r)

    func _index_for(start):
        lo := 0
        hi := len(self._r)
        while lo < hi:
            mid := (lo + hi) // 2
            if self._r[mid].start < start:
                lo = mid + 1
            else:
                hi = mid
        return lo

    # Insère une région disjointe des autres (ArgumentError sinon, sauf allow_overlap).
    func insert(region, allow_overlap=false):
        if not isinstance(region, MemoryRegion):
            raise("TypeError", "RegionMap.insert : MemoryRegion attendue")
        i := self._index_for(region.start)
        if not allow_overlap:
            if i > 0 and self._r[i - 1].overlaps(region):
                raise("ArgumentError", "RegionMap.insert : " + str(region) + " chevauche " + str(self._r[i - 1]))
            if i < len(self._r) and self._r[i].overlaps(region):
                raise("ArgumentError", "RegionMap.insert : " + str(region) + " chevauche " + str(self._r[i]))
        insert(self._r, i, region)
        return region

    # Région contenant addr (ou null), en O(log n).
    func find(addr):
        i := self._index_for(addr + 1) - 1
        if i >= 0 and self._r[i].contains(addr):
            return self._r[i]
        return null

    func find_by_name(name):
        return [r for r in self._r if r.name == name]

    func remove(region):
        i := 0
        while i < len(self._r):
            if self._r[i] == region:
                pop(self._r, i)
                return true
            i += 1
        return false

    # Régions qui recouvrent [start, start + size).
    func overlapping(start, size):
        probe := MemoryRegion(start, size)
        return [r for r in self._r if r.overlaps(probe)]

    # Trous non couverts dans [lo, hi).
    func gaps(lo, hi):
        out := []
        cur := lo
        for r in self._r:
            if r.end() <= lo or r.start >= hi:
                continue
            if r.start > cur:
                append(out, MemoryRegion(cur, r.start - cur, "<libre>", "---", "gap"))
            if r.end() > cur:
                cur = r.end()
        if cur < hi:
            append(out, MemoryRegion(cur, hi - cur, "<libre>", "---", "gap"))
        return out

    # Premier trou d'au moins size octets (aligné) dans [lo, hi) : adresse ou null.
    func find_free(size, lo, hi, align=1):
        for g in self.gaps(lo, hi):
            a := ((g.start + align - 1) // align) * align
            if a + size <= g.end():
                return a
        return null

    # Fusionne les régions contiguës de mêmes nom et protections.
    func merge_adjacent():
        if len(self._r) < 2:
            return 0
        out := [self._r[0]]
        merged := 0
        i := 1
        while i < len(self._r):
            last := out[len(out) - 1]
            r := self._r[i]
            if last.end() == r.start and last.name == r.name and last.prot == r.prot:
                out[len(out) - 1] = MemoryRegion(last.start, last.size + r.size, last.name, last.prot, last.kind)
                merged += 1
            else:
                append(out, r)
            i += 1
        self._r = out
        return merged

    func regions():
        return self._r[:]

    func size():
        return len(self._r)

    func total_size():
        n := 0
        for r in self._r:
            n += r.size
        return n

    func __len__():
        return len(self._r)

    func __getitem__(i):
        return self._r[i]

    func __str__():
        return _s.join("\n", [str(r) for r in self._r])

func _parse_hex(t):
    v := 0
    for c in _s.lower(t):
        d := _s.find(_HEX, str(c))
        if d < 0:
            raise("ValueError", "memory_region : nombre hexadécimal invalide '" + t + "'")
        v = v * 16 + d
    return v

# Analyse le format de /proc/<pid>/maps : « début-fin perms décalage périph inode [chemin] ».
# Les plages au-delà de 2^63 (vsyscall, moitié noyau) sont ignorées : un int ALEX est signé 64 bits.
func parse_maps(text):
    m := RegionMap()
    for line in _s.split(text, "\n"):
        line = _s.trim(line)
        if line == "":
            continue
        f := [x for x in _s.split(line, " ") if x != ""]
        if len(f) < 5:
            continue
        span := _s.split(f[0], "-")
        if len(span) != 2:
            continue
        a := _parse_hex(span[0])
        b := _parse_hex(span[1])
        # Adresses >= 2^63 (vsyscall, noyau) : non représentables en int signé, ignorées.
        if a < 0 or b < 0 or b < a:
            continue
        prot := f[1][:3]
        name := ""
        if len(f) >= 6:
            name = _s.join(" ", f[5:])
        kind := "anonymous"
        if _s.starts_with(name, "/"):
            kind = "file"
        elif name == "[stack]":
            kind = "stack"
        elif name == "[heap]":
            kind = "heap"
        elif _s.starts_with(name, "["):
            kind = "special"
        m.insert(MemoryRegion(a, b - a, name, prot, kind), true)
    return m

# Carte mémoire du processus courant (Linux) ; RegionMap vide si /proc n'est pas disponible.
func process_map():
    try:
        return parse_maps(_io.read_file("/proc/self/maps"))
    catch e:
        return RegionMap()

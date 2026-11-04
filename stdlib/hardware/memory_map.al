# ALEX STANDARD LIBRARY — hardware.memory_map
#
# Cartes de la mémoire :
#   - PHYSIQUE : zones de RAM utilisable, réservées, ACPI, ROM, fenêtres des périphériques (Linux :
#     /sys/firmware/memmap = table e820 du micrologiciel, /proc/iomem = arbre des ressources ; les adresses de
#     /proc/iomem ne sont lisibles que par root, sinon elles valent 0 et seule la table e820 sert) ;
#   - D'UN PROCESSUS : ses projections (code, tas, pile, bibliothèques, fichiers ; /proc/<pid>/maps).
#
# MemoryMap sert aussi à bâtir sa propre carte (noyau, simulateur, chargeur) : ajouter des zones, réserver une
# plage, allouer des cadres alignés dans la RAM libre, fusionner, interroger.
#
#   use hardware.memory_map as mm
#   m := mm.physical()
#   print(m.describe())
#   print(m.total("ram") // 1048576, "Mio de RAM")
#   r := m.find(0xB8000)                         # zone qui contient l'adresse
#   for p in mm.process_maps():                  # projections du processus courant
#       print(p.describe())
#
#   carte := mm.MemoryMap()
#   carte.add(0, 0x9FC00, "ram")
#   carte.add(0x100000, 0x7F00000, "ram")
#   carte.reserve(0x100000, 0x400000, "noyau")
#   a := carte.allocate(0x10000, 4096)           # 64 Kio alignés sur 4 Kio, pris dans la RAM libre
#
# Types de zone : "ram", "reserved", "acpi", "acpi_nvs", "unusable", "persistent", "rom", "mmio", "kernel",
# "allocated", ou tout autre nom choisi.
#
# Erreurs : ArgumentError (zone invalide), MemoryError (allocation impossible).

from core use len, type
from collections use append, contains_key, keys, sort
use string as _s
use hardware._sys as _sys

const PAGE := 4096

func _hex(v, width=0):
    digits := "0123456789abcdef"
    out := "0" if v == 0 else ""
    n := v
    # entier non signé 64 bits (les adresses hautes peuvent être négatives une fois lues)
    if n < 0:
        lo := n & 4294967295
        hi := (n >> 32) & 4294967295
        return _hex(hi, 0) + _pad(_hex(lo, 0), 8)
    while n > 0:
        out = str(digits[n % 16]) + out
        n = n // 16
    return _pad(out, width)

func _pad(t, width):
    while len(t) < width:
        t = "0" + t
    return t

func _human(n):
    if n >= 1073741824 and n % 1073741824 == 0:
        return str(n // 1073741824) + " Gio"
    if n >= 1048576:
        return str(n // 1048576) + " Mio"
    if n >= 1024:
        return str(n // 1024) + " Kio"
    return str(n) + " o"

# ---------------------------------------------------------------- zones
class Region:
    # start inclus, end exclu.
    func init(start, end, kind, name=null):
        if end < start:
            raise("ArgumentError", "Region : fin avant le début")
        self.start = start
        self.end = end
        self.kind = kind
        self.name = name
        if name == null:
            self.name = kind
        self.children = []

    func size():
        return self.end - self.start

    func contains(addr):
        return addr >= self.start and addr < self.end

    func overlaps(start, end):
        return start < self.end and end > self.start

    func usable():
        return self.kind == "ram"

    func describe():
        t := _hex(self.start, 9) + "-" + _hex(self.end - 1, 9) + "  " + _pad_right(self.kind, 10) + " " + _pad_left(_human(self.size()), 9)
        if self.name != self.kind:
            t = t + "  " + self.name
        return t

    func to_dict():
        return {"start": self.start, "end": self.end, "kind": self.kind, "name": self.name, "size": self.size()}

func _pad_right(t, w):
    while len(t) < w:
        t = t + " "
    return t

func _pad_left(t, w):
    while len(t) < w:
        t = " " + t
    return t

func _align_up(v, a):
    if a <= 1:
        return v
    r := v % a
    if r == 0:
        return v
    return v + a - r

# ---------------------------------------------------------------- carte
class MemoryMap:
    func init():
        self.regions = []         # triées par adresse, sans chevauchement

    func _sort():
        n := len(self.regions)
        i := 1
        while i < n:
            r := self.regions[i]
            j := i - 1
            while j >= 0 and self.regions[j].start > r.start:
                self.regions[j + 1] = self.regions[j]
                j -= 1
            self.regions[j + 1] = r
            i += 1

    # Ajoute une zone [start, start + size) ; ce qui chevauchait est remplacé par elle.
    func add(start, size, kind, name=null):
        if size <= 0:
            raise("ArgumentError", "MemoryMap.add : taille > 0 attendue")
        self._carve(start, start + size)
        append(self.regions, Region(start, start + size, kind, name))
        self._sort()
        return self

    # Retire [start, end) des zones existantes (en les coupant).
    func _carve(start, end):
        out := []
        for r in self.regions:
            if not r.overlaps(start, end):
                append(out, r)
                continue
            if r.start < start:
                append(out, Region(r.start, start, r.kind, r.name))
            if r.end > end:
                append(out, Region(end, r.end, r.kind, r.name))
        self.regions = out

    func remove(start, size):
        self._carve(start, start + size)
        self._sort()
        return self

    # Marque [start, start + size) comme réservée (kind) : par exemple le noyau, une table, un tampon DMA.
    func reserve(start, size, name="reserved", kind="reserved"):
        return self.add(start, size, kind, name)

    # Fusionne les zones contiguës de même type et même nom.
    func merge():
        out := []
        for r in self.regions:
            if len(out) > 0:
                last := out[len(out) - 1]
                if last.end == r.start and last.kind == r.kind and last.name == r.name:
                    out[len(out) - 1] = Region(last.start, r.end, r.kind, r.name)
                    continue
            append(out, r)
        self.regions = out
        return self

    func find(addr):
        for r in self.regions:
            if r.contains(addr):
                return r
        return null

    func kind_at(addr):
        r := self.find(addr)
        return null if r == null else r.kind

    func by_kind(kind):
        return [r for r in self.regions if r.kind == kind]

    func total(kind="ram"):
        n := 0
        for r in self.regions:
            if r.kind == kind:
                n += r.size()
        return n

    # Plus haute adresse (exclue) de RAM.
    func ram_end():
        e := 0
        for r in self.regions:
            if r.kind == "ram" and r.end > e:
                e = r.end
        return e

    # Trous entre les zones, jusqu'à limit : list de Region("hole").
    func holes(limit=null):
        out := []
        pos := 0
        for r in self.regions:
            if r.start > pos:
                append(out, Region(pos, r.start, "hole"))
            if r.end > pos:
                pos = r.end
        if limit != null and limit > pos:
            append(out, Region(pos, limit, "hole"))
        return out

    # Prend size octets alignés dans la RAM libre (premier ajustement, à partir de minimum : la page 0 est évitée) et les marque
    # "allocated" ; renvoie l'adresse. MemoryError si aucune zone ne convient.
    func allocate(size, align=PAGE, name="allocated", minimum=PAGE):
        if size <= 0:
            raise("ArgumentError", "MemoryMap.allocate : taille > 0 attendue")
        for r in self.regions:
            if r.kind != "ram":
                continue
            a := _align_up(r.start if r.start > minimum else minimum, align)
            if a + size <= r.end:
                self.add(a, size, "allocated", name)
                return a
        raise("MemoryError", "MemoryMap.allocate : pas de zone libre de " + _human(size))

    # Rend une plage allouée à la RAM libre.
    func release(addr, size=null):
        r := self.find(addr)
        if r == null or r.kind != "allocated":
            raise("ArgumentError", "MemoryMap.release : " + _hex(addr) + " n'est pas une allocation")
        n := size if size != null else r.end - addr
        self.add(addr, n, "ram")
        self.merge()

    func copy():
        m := MemoryMap()
        for r in self.regions:
            append(m.regions, Region(r.start, r.end, r.kind, r.name))
        return m

    func describe():
        lines := [r.describe() for r in self.regions]
        append(lines, "RAM : " + _human(self.total("ram")) + ", réservée : " + _human(self.total("reserved")))
        return _s.join("\n", lines)

    func to_list():
        return [r.to_dict() for r in self.regions]

# ---------------------------------------------------------------- lecture du système
func _kind_of(text):
    t := _s.lower(_s.trim(text))
    if t == "system ram" or t == "usable":
        return "ram"
    if _s.contains(t, "acpi non-volatile") or _s.contains(t, "acpi nvs"):
        return "acpi_nvs"
    if _s.contains(t, "acpi"):
        return "acpi"
    if _s.contains(t, "unusable"):
        return "unusable"
    if _s.contains(t, "persistent"):
        return "persistent"
    if _s.contains(t, "rom"):
        return "rom"
    if _s.contains(t, "pci") or _s.contains(t, "ioapic") or _s.contains(t, "hpet") or _s.contains(t, "local apic"):
        return "mmio"
    if _s.contains(t, "kernel"):
        return "kernel"
    if _s.contains(t, "reserved"):
        return "reserved"
    return t

# Table e820 du micrologiciel (/sys/firmware/memmap) : MemoryMap, ou null si absente.
func firmware_map():
    base := "/sys/firmware/memmap"
    names := _sys.list(base)
    if len(names) == 0:
        return null
    m := MemoryMap()
    for n in names:
        s := _sys.hex(_sys.read(base + "/" + n + "/start"))
        e := _sys.hex(_sys.read(base + "/" + n + "/end"))
        t := _sys.read(base + "/" + n + "/type")
        if s == null or e == null or t == null:
            continue
        m.add(s, e - s + 1, _kind_of(t), t)
    return m

# Analyse un texte au format /proc/iomem : list de Region (niveau supérieur), avec leurs children.
func parse_iomem(text):
    roots := []
    stack := []       # [indentation, Region]
    if text == null:
        return roots
    for line in _s.split(text, "\n"):
        if _s.trim(line) == "":
            continue
        indent := 0
        while indent < len(line) and line[indent] == ' ':
            indent += 1
        body := _s.trim(line)
        k := _s.find(body, " : ")
        if k < 0:
            continue
        rng := _s.slice(body, 0, k)
        name := _s.slice(body, k + 3)
        d := _s.find(rng, "-")
        s := _sys.hex(_s.slice(rng, 0, d))
        e := _sys.hex(_s.slice(rng, d + 1))
        r := Region(s, e + 1, _kind_of(name), name)
        while len(stack) > 0 and stack[len(stack) - 1][0] >= indent:
            stack = [stack[i] for i in 0..len(stack) - 1]
        if len(stack) == 0:
            append(roots, r)
        else:
            append(stack[len(stack) - 1][1].children, r)
        append(stack, [indent, r])
    return roots

# Arbre /proc/iomem (list de Region) ; adresses à 0 sans les droits de root (readable() le dit).
func iomem():
    return parse_iomem(_sys.read("/proc/iomem"))

# Les adresses de /proc/iomem sont-elles lisibles (root) ?
func iomem_readable():
    for r in iomem():
        if r.start != 0 or r.end != 1:
            return true
    return false

# Carte physique de la machine : table e820, complétée par les fenêtres des périphériques et le noyau de
# /proc/iomem si ses adresses sont lisibles.
func physical():
    m := firmware_map()
    roots := iomem()
    readable := iomem_readable()
    if m == null:
        m = MemoryMap()
        if readable:
            for r in roots:
                m.add(r.start, r.size(), r.kind, r.name)
        return m
    if readable:
        for r in roots:
            if r.kind == "mmio" and m.find(r.start) == null:
                m.add(r.start, r.size(), "mmio", r.name)
            for c in r.children:
                if c.kind == "kernel":
                    m.add(c.start, c.size(), "kernel", c.name)
    return m

# Fenêtres MMIO des périphériques (list de Region) d'après /proc/iomem (root), ou [].
func device_windows():
    out := []
    _collect(iomem(), out)
    return out

func _collect(rs, out):
    for r in rs:
        if r.start != 0 and _s.contains(r.name, ":") and len(r.children) > 0:
            for c in r.children:
                append(out, Region(c.start, c.end, "mmio", r.name + " " + c.name))
        _collect(r.children, out)

# ---------------------------------------------------------------- projections d'un processus
class Mapping:
    func init(start, end, perms, offset, device, inode, path):
        self.start = start
        self.end = end
        self.perms = perms          # « r-xp »
        self.offset = offset
        self.device = device
        self.inode = inode
        self.path = path            # fichier, « [heap] », « [stack] », « [vdso] », ou "" (anonyme)

    func size():
        return self.end - self.start

    func readable():
        return self.perms[0] == 'r'

    func writable():
        return self.perms[1] == 'w'

    func executable():
        return self.perms[2] == 'x'

    func shared():
        return self.perms[3] == 's'

    func kind():
        if self.path == "[heap]":
            return "heap"
        if _s.starts_with(self.path, "[stack"):
            return "stack"
        if self.path == "[vdso]" or self.path == "[vvar]" or self.path == "[vsyscall]":
            return "kernel"
        if self.path == "":
            return "anonymous"
        if self.executable():
            return "code"
        return "file"

    func describe():
        return _hex(self.start, 12) + "-" + _hex(self.end, 12) + " " + self.perms + " " + _pad_left(_human(self.size()), 9) + "  " + self.path

func parse_maps(text):
    out := []
    if text == null:
        return out
    for line in _s.split(text, "\n"):
        w := _sys.split_words(line)
        if len(w) < 5:
            continue
        d := _s.find(w[0], "-")
        path := ""
        if len(w) >= 6:
            path = _s.join(" ", [w[i] for i in 5..len(w)])
        append(out, Mapping(_sys.hex(_s.slice(w[0], 0, d)), _sys.hex(_s.slice(w[0], d + 1)), w[1], _sys.hex(w[2]), w[3], _sys.dec(w[4]), path))
    return out

# Projections du processus pid (null : le processus courant).
func process_maps(pid=null):
    who := "self" if pid == null else str(pid)
    return parse_maps(_sys.read("/proc/" + who + "/maps"))

# Totaux par sorte de projection (octets) : dict code, file, heap, stack, anonymous, kernel.
func process_usage(pid=null):
    out := {"code": 0, "file": 0, "heap": 0, "stack": 0, "anonymous": 0, "kernel": 0}
    for m in process_maps(pid):
        out[m.kind()] = out[m.kind()] + m.size()
    return out

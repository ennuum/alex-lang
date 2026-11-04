# alex: native
# ALEX STANDARD LIBRARY — storage_driver.storage_partition
#
# Création et vérification de tables de partitions GPT (UEFI) sur un BlockDevice — la lecture est dans
# storage_driver.disk :
#   - GptLayout : partitions prévues (nom, type, taille en blocs ; 0 = le reste), alignement (2048 blocs =
#     1 Mio par défaut), placement sans chevauchement dans la zone utilisable, espaces libres ;
#   - write : MBR protecteur, en-tête principal (LBA 1) et table (LBA 2), copie de secours de la table et de
#     l'en-tête en fin de disque, CRC32 de l'en-tête et de la table, GUID uniques dérivés d'une graine ;
#   - load : reprend une table GPT existante pour la modifier (remove / add, puis write) ;
#   - verify : signatures, CRC, cohérence des deux en-têtes, entrées dans la zone utilisable, chevauchements.
#
#   use storage_driver.storage_partition as sp
#   g := sp.GptLayout(disque, 2048)
#   g.add("EFI", sp.type_guid("efi"), 204800)
#   g.add("racine", sp.type_guid("linux"), 0)
#   g.write(0x5EED)
#   print(sp.verify(disque))                  # [] si tout est cohérent
#   for p in storage_driver.disk.Disk(disque).partitions(): print(p.describe())
#
# Erreurs : PartitionError (plus de place, disque trop petit, GUID mal formé, type inconnu, table invalide).
# Compilable en natif (# alex: native).

from core use len
from collections use append
use string as _s
use hw
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice
use storage_driver.disk as dk

const ENTRIES := 128
const ENTRY_SIZE := 128

func type_guid(name: str) -> str:
    if name == "efi":
        return "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
    if name == "linux":
        return "0FC63DAF-8483-4772-8E79-3D69D8477DE4"
    if name == "swap":
        return "0657FD6D-A4AB-43C4-84E5-0933C84B4F4F"
    if name == "home":
        return "933AC7E1-2EB4-4F13-B844-0E14E2AEF915"
    if name == "msdata":
        return "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7"
    if name == "bios":
        return "21686148-6449-6E6F-744E-656564454649"
    if name == "lvm":
        return "E6D6D379-F507-44C2-A23C-238F2A3DF928"
    raise("PartitionError", "type de partition inconnu « " + name + " » (efi, linux, swap, home, msdata, bios, lvm)")

# ---------------------------------------------------------------- CRC32 (IEEE, celui de GPT et de zlib)
func _crc_table() -> list[int]:
    t: list[int] := []
    n := 0
    while n < 256:
        c := n
        k := 0
        while k < 8:
            if c & 1 != 0:
                c = 0xEDB88320 ^ (c >> 1)
            else:
                c = c >> 1
            k += 1
        append(t, c)
        n += 1
    return t

func crc32(addr: int, n: int) -> int:
    t := _crc_table()
    c := 0xFFFFFFFF
    i := 0
    while i < n:
        c = t[(c ^ hw.peek8(addr + i)) & 0xFF] ^ (c >> 8)
        i += 1
    return c ^ 0xFFFFFFFF

# ---------------------------------------------------------------- GUID
func _hexval(ch: char) -> int:
    if ch >= '0' and ch <= '9':
        return _s.ord(ch) - 48
    if ch >= 'a' and ch <= 'f':
        return _s.ord(ch) - 87
    if ch >= 'A' and ch <= 'F':
        return _s.ord(ch) - 55
    return -1

# Octets (16) d'un GUID texte, ordre mixte de GPT : trois premiers groupes petit-boutistes.
func guid_bytes(text: str) -> list[int]:
    digits: list[int] := []
    for ch in text:
        if ch != '-':
            v := _hexval(ch)
            if v < 0:
                raise("PartitionError", "GUID mal formé : « " + text + " »")
            append(digits, v)
    if len(digits) != 32:
        raise("PartitionError", "GUID mal formé : « " + text + " »")
    raw: list[int] := []
    i := 0
    while i < 16:
        append(raw, digits[2 * i] * 16 + digits[2 * i + 1])
        i += 1
    order := [3, 2, 1, 0, 5, 4, 7, 6, 8, 9, 10, 11, 12, 13, 14, 15]
    out: list[int] := []
    for k in order:
        append(out, raw[k])
    return out

func put_guid(addr: int, text: str):
    b := guid_bytes(text)
    i := 0
    while i < 16:
        hw.poke8(addr + i, b[i])
        i += 1

class GuidMaker:
    state: int := 1

    func init(seed: int):
        self.state = (seed & 0x7FFFFFFF) | 1

    func _next() -> int:
        self.state = (self.state * 1103515245 + 12345) & 0x7FFFFFFF
        return (self.state >> 7) & 0xFF

    # GUID de version 4 (aléatoire) au format texte.
    func make() -> str:
        b: list[int] := []
        i := 0
        while i < 16:
            append(b, self._next())
            i += 1
        b[6] = (b[6] & 0x0F) | 0x40
        b[8] = (b[8] & 0x3F) | 0x80
        hexd := "0123456789ABCDEF"
        t := ""
        i = 0
        while i < 16:
            if i == 4 or i == 6 or i == 8 or i == 10:
                t = t + "-"
            t = t + str(hexd[b[i] >> 4]) + str(hexd[b[i] & 15])
            i += 1
        return t

# ---------------------------------------------------------------- plan
class PlannedPartition:
    name: str := ""
    type_guid: str := ""
    unique_guid: str := ""
    blocks: int := 0          # demandé (0 : le reste)
    start: int := 0
    end: int := 0             # inclus
    attributes: int := 0

    func init(name: str, type_guid: str, blocks: int):
        self.name = name
        self.type_guid = type_guid
        self.unique_guid = ""
        self.blocks = blocks
        self.start = 0
        self.end = 0
        self.attributes = 0

    func count() -> int:
        return self.end - self.start + 1

class GptLayout:
    dev: BlockDevice
    align: int := 2048
    parts: list[PlannedPartition] := []
    disk_guid: str := ""

    func init(dev: BlockDevice, align: int):
        self.dev = dev
        self.align = align if align > 0 else 1
        self.parts = []
        self.disk_guid = ""
        if dev.block_count() < 2 * self.table_blocks() + 4:
            raise("PartitionError", dev.name() + " : disque trop petit pour une table GPT")

    func table_blocks() -> int:
        bs := self.dev.block_size()
        return (ENTRIES * ENTRY_SIZE + bs - 1) // bs

    func first_usable() -> int:
        return 2 + self.table_blocks()

    func last_usable() -> int:
        return self.dev.block_count() - 2 - self.table_blocks()

    func _up(v: int) -> int:
        return ((v + self.align - 1) // self.align) * self.align

    # Ajoute une partition placée après la dernière (alignée) ; blocks 0 : jusqu'à la fin.
    func add(name: str, type_guid: str, blocks: int) -> PlannedPartition:
        guid_bytes(type_guid)
        if len(self.parts) >= ENTRIES:
            raise("PartitionError", "table GPT pleine (" + str(ENTRIES) + " entrées)")
        start := self.first_usable()
        for p in self.parts:
            if p.end + 1 > start:
                start = p.end + 1
        start = self._up(start)
        last := self.last_usable()
        if start > last:
            raise("PartitionError", "plus de place pour « " + name + " »")
        p := PlannedPartition(name, type_guid, blocks)
        p.start = start
        if blocks == 0:
            p.end = last
        else:
            p.end = start + blocks - 1
            if p.end > last:
                raise("PartitionError", "« " + name + " » : " + str(blocks) + " blocs demandés, " + str(last - start + 1) + " disponibles")
        append(self.parts, p)
        return p

    # Ajoute à une position donnée (vérifie le chevauchement).
    func add_at(name: str, type_guid: str, start: int, blocks: int) -> PlannedPartition:
        guid_bytes(type_guid)
        if start < self.first_usable() or start + blocks - 1 > self.last_usable() or blocks <= 0:
            raise("PartitionError", "« " + name + " » hors de la zone utilisable")
        for q in self.parts:
            if start <= q.end and start + blocks - 1 >= q.start:
                raise("PartitionError", "« " + name + " » chevauche « " + q.name + " »")
        p := PlannedPartition(name, type_guid, blocks)
        p.start = start
        p.end = start + blocks - 1
        append(self.parts, p)
        return p

    func remove(index: int):
        if index < 1 or index > len(self.parts):
            raise("PartitionError", "pas de partition " + str(index))
        keep: list[PlannedPartition] := []
        i := 0
        while i < len(self.parts):
            if i != index - 1:
                append(keep, self.parts[i])
            i += 1
        self.parts = keep

    # Espaces libres [début, fin] (inclus) de la zone utilisable.
    func free_ranges() -> list[list[int]]:
        sorted: list[PlannedPartition] := []
        for p in self.parts:
            k := 0
            while k < len(sorted) and sorted[k].start < p.start:
                k += 1
            nxt: list[PlannedPartition] := []
            j := 0
            while j < len(sorted):
                if j == k:
                    append(nxt, p)
                append(nxt, sorted[j])
                j += 1
            if k == len(sorted):
                append(nxt, p)
            sorted = nxt
        out: list[list[int]] := []
        cur := self.first_usable()
        for p in sorted:
            if p.start > cur:
                append(out, [cur, p.start - 1])
            if p.end + 1 > cur:
                cur = p.end + 1
        if cur <= self.last_usable():
            append(out, [cur, self.last_usable()])
        return out

    func write(seed: int):
        g := GuidMaker(seed)
        if self.disk_guid == "":
            self.disk_guid = g.make()
        for p in self.parts:
            if p.unique_guid == "":
                p.unique_guid = g.make()
        bs := self.dev.block_size()
        n := self.dev.block_count()
        tb := self.table_blocks()
        pages := (tb * bs + 4095) // 4096
        tbl := hw.alloc_pages(pages)
        hw.zero(tbl, tb * bs)
        i := 0
        while i < len(self.parts):
            p := self.parts[i]
            e := tbl + i * ENTRY_SIZE
            put_guid(e, p.type_guid)
            put_guid(e + 16, p.unique_guid)
            hw.poke64(e + 32, p.start)
            hw.poke64(e + 40, p.end)
            hw.poke64(e + 48, p.attributes)
            k := 0
            for ch in p.name:
                if k < 36:
                    hw.poke16(e + 56 + 2 * k, _s.ord(ch))
                k += 1
            i += 1
        tcrc := crc32(tbl, ENTRIES * ENTRY_SIZE)
        hp := (bs + 4095) // 4096
        hdr := hw.alloc_pages(hp)
        # MBR protecteur
        hw.zero(hdr, bs)
        hw.poke8(hdr + 446 + 1, 0x00)
        hw.poke8(hdr + 446 + 2, 0x02)
        hw.poke8(hdr + 446 + 4, 0xEE)
        hw.poke8(hdr + 446 + 5, 0xFF)
        hw.poke8(hdr + 446 + 6, 0xFF)
        hw.poke8(hdr + 446 + 7, 0xFF)
        hw.poke32(hdr + 446 + 8, 1)
        cnt := n - 1
        if cnt > 0xFFFFFFFF:
            cnt = 0xFFFFFFFF
        hw.poke32(hdr + 446 + 12, cnt)
        hw.poke16(hdr + 510, 0xAA55)
        self.dev.write_blocks(0, 1, hdr)
        # en-tête principal puis de secours
        self._header(hdr, 1, n - 1, 2, tcrc)
        self.dev.write_blocks(1, 1, hdr)
        self.dev.write_blocks(2, tb, tbl)
        self._header(hdr, n - 1, 1, n - 1 - tb, tcrc)
        self.dev.write_blocks(n - 1 - tb, tb, tbl)
        self.dev.write_blocks(n - 1, 1, hdr)
        self.dev.flush()
        hw.free_pages(hdr, hp)
        hw.free_pages(tbl, pages)

    func _header(h: int, current: int, backup: int, entries_lba: int, tcrc: int):
        bs := self.dev.block_size()
        hw.zero(h, bs)
        sig := "EFI PART"
        k := 0
        for ch in sig:
            hw.poke8(h + k, _s.ord(ch))
            k += 1
        hw.poke32(h + 8, 0x00010000)
        hw.poke32(h + 12, 92)
        hw.poke64(h + 24, current)
        hw.poke64(h + 32, backup)
        hw.poke64(h + 40, self.first_usable())
        hw.poke64(h + 48, self.last_usable())
        put_guid(h + 56, self.disk_guid)
        hw.poke64(h + 72, entries_lba)
        hw.poke32(h + 80, ENTRIES)
        hw.poke32(h + 84, ENTRY_SIZE)
        hw.poke32(h + 88, tcrc)
        hw.poke32(h + 16, crc32(h, 92))

    func describe() -> str:
        t := "GPT " + self.dev.name() + " : zone " + str(self.first_usable()) + ".." + str(self.last_usable())
        i := 1
        for p in self.parts:
            t = t + "\n  " + str(i) + " « " + p.name + " » " + str(p.start) + ".." + str(p.end) + " (" + str(p.count()) + " blocs)"
            i += 1
        return t

# Plan reprenant la table GPT existante (même GUID de disque et de partitions).
func load(dev: BlockDevice, align: int) -> GptLayout:
    d := dk.Disk(dev)
    parts := d.partitions()
    if d.scheme != "gpt":
        raise("PartitionError", dev.name() + " : pas de table GPT (" + d.scheme + ")")
    g := GptLayout(dev, align)
    bs := dev.block_size()
    buf := hw.alloc_pages((bs + 4095) // 4096)
    dev.read_blocks(1, 1, buf)
    g.disk_guid = dk.guid_at(buf + 56)
    entries_lba := hw.peek64(buf + 72)
    esize := hw.peek32(buf + 84)
    for e in parts:
        p := PlannedPartition(e.label, e.type_guid, e.count)
        p.start = e.start
        p.end = e.start + e.count - 1
        off := (e.index - 1) * esize
        dev.read_blocks(entries_lba + off // bs, 1, buf)
        p.unique_guid = dk.guid_at(buf + off % bs + 16)
        p.attributes = hw.peek64(buf + off % bs + 48)
        append(g.parts, p)
    hw.free_pages(buf, (bs + 4095) // 4096)
    return g

func _check_header(dev: BlockDevice, lba: int, which: str, out: list[str]) -> list[int]:
    bs := dev.block_size()
    buf := hw.alloc_pages((bs + 4095) // 4096)
    dev.read_blocks(lba, 1, buf)
    res: list[int] := []
    if hw.string_at(buf, 8) != "EFI PART":
        append(out, "en-tête " + which + " : signature absente")
        hw.free_pages(buf, (bs + 4095) // 4096)
        return res
    stored := hw.peek32(buf + 16)
    hw.poke32(buf + 16, 0)
    size := hw.peek32(buf + 12)
    if size < 92 or size > bs:
        append(out, "en-tête " + which + " : taille " + str(size) + " invalide")
        hw.free_pages(buf, (bs + 4095) // 4096)
        return res
    if crc32(buf, size) != stored:
        append(out, "en-tête " + which + " : CRC incorrect")
    if hw.peek64(buf + 24) != lba:
        append(out, "en-tête " + which + " : LBA courant " + str(hw.peek64(buf + 24)) + " au lieu de " + str(lba))
    append(res, hw.peek64(buf + 32))
    append(res, hw.peek64(buf + 40))
    append(res, hw.peek64(buf + 48))
    append(res, hw.peek64(buf + 72))
    append(res, hw.peek32(buf + 80))
    append(res, hw.peek32(buf + 84))
    append(res, hw.peek32(buf + 88))
    hw.free_pages(buf, (bs + 4095) // 4096)
    return res

# Problèmes de la table GPT (liste vide : cohérente).
func verify(dev: BlockDevice) -> list[str]:
    out: list[str] := []
    bs := dev.block_size()
    n := dev.block_count()
    buf := hw.alloc_pages((bs + 4095) // 4096)
    dev.read_blocks(0, 1, buf)
    if hw.peek16(buf + 510) != 0xAA55 or hw.peek8(buf + 446 + 4) != 0xEE:
        append(out, "MBR protecteur absent")
    hw.free_pages(buf, (bs + 4095) // 4096)
    a := _check_header(dev, 1, "principal", out)
    if len(a) == 0:
        return out
    if a[0] != n - 1:
        append(out, "en-tête principal : copie de secours annoncée en " + str(a[0]) + " au lieu de " + str(n - 1))
    b := _check_header(dev, n - 1, "de secours", out)
    if len(b) > 0:
        if b[1] != a[1] or b[2] != a[2] or b[6] != a[6] or b[4] != a[4]:
            append(out, "les deux en-têtes diffèrent")
    count := a[4]
    esize := a[5]
    if esize < 128 or count > 4096:
        append(out, "taille ou nombre d'entrées invalide")
        return out
    blocks := (count * esize + bs - 1) // bs
    pages := (blocks * bs + 4095) // 4096
    tbl := hw.alloc_pages(pages)
    dev.read_blocks(a[3], blocks, tbl)
    if crc32(tbl, count * esize) != a[6]:
        append(out, "table principale : CRC incorrect")
    starts: list[int] := []
    ends: list[int] := []
    i := 0
    while i < count:
        e := tbl + i * esize
        if hw.peek64(e) != 0 or hw.peek64(e + 8) != 0:
            f := hw.peek64(e + 32)
            l := hw.peek64(e + 40)
            if f < a[1] or l > a[2] or l < f:
                append(out, "partition " + str(i + 1) + " hors de la zone utilisable (" + str(f) + ".." + str(l) + ")")
            k := 0
            while k < len(starts):
                if f <= ends[k] and l >= starts[k]:
                    append(out, "partition " + str(i + 1) + " chevauche une autre")
                k += 1
            append(starts, f)
            append(ends, l)
        i += 1
    if len(b) > 0:
        dev.read_blocks(b[3], blocks, tbl)
        if crc32(tbl, count * esize) != b[6]:
            append(out, "table de secours : CRC incorrect")
    hw.free_pages(tbl, pages)
    return out

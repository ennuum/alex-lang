# alex: native
# ALEX STANDARD LIBRARY — storage_driver.disk
#
# Un disque et ses partitions : lecture des tables de partitions MBR (DOS, 4 entrées principales) et GPT
# (UEFI : en-tête en LBA 1, entrées de 128 octets, noms UTF-16), création d'une table MBR, identité du disque
# (modèle, numéro de série, fournis par le pilote).
#
#   use storage_driver.disk as dk
#   d := dk.Disk(ata0)                 # tout BlockDevice
#   for p in d.partitions():           # PartitionEntry
#       print(p.describe())            # « 1 : FAT32 (LBA) début 2048, 204800 blocs »
#   part := d.open(1)                  # block_device.Partition
#   dk.write_mbr(ram, [[0x0C, 2048, 4096]], 0x1234ABCD)
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice, Partition

class PartitionEntry:
    index: int := 0
    scheme: str := ""            # "mbr" ou "gpt"
    type_id: int := 0            # type MBR (0x0C, 0x83...) ; GPT : premier mot du GUID de type
    type_guid: str := ""         # GPT : GUID de type (texte)
    start: int := 0
    count: int := 0
    bootable: bool := false
    label: str := ""

    func init(index: int, scheme: str, type_id: int, start: int, count: int):
        self.index = index
        self.scheme = scheme
        self.type_id = type_id
        self.type_guid = ""
        self.start = start
        self.count = count
        self.bootable = false
        self.label = ""

    func kind() -> str:
        if self.scheme == "gpt":
            return gpt_type_name(self.type_guid)
        return mbr_type_name(self.type_id)

    func describe() -> str:
        t := str(self.index) + " : " + self.kind() + " début " + str(self.start) + ", " + str(self.count) + " blocs"
        if self.bootable:
            t = t + ", amorçable"
        if self.label != "":
            t = t + " « " + self.label + " »"
        return t

func mbr_type_name(t: int) -> str:
    if t == 0x01:
        return "FAT12"
    if t == 0x04 or t == 0x06 or t == 0x0E:
        return "FAT16"
    if t == 0x0B:
        return "FAT32"
    if t == 0x0C:
        return "FAT32 (LBA)"
    if t == 0x07:
        return "NTFS / exFAT"
    if t == 0x05 or t == 0x0F:
        return "étendue"
    if t == 0x82:
        return "Linux swap"
    if t == 0x83:
        return "Linux"
    if t == 0x8E:
        return "Linux LVM"
    if t == 0xEE:
        return "GPT protecteur"
    if t == 0xEF:
        return "système EFI"
    if t == 0xA5:
        return "FreeBSD"
    return "type " + str(t)

func gpt_type_name(g: str) -> str:
    if g == "C12A7328-F81F-11D2-BA4B-00A0C93EC93B":
        return "système EFI"
    if g == "0FC63DAF-8483-4772-8E79-3D69D8477DE4":
        return "Linux"
    if g == "0657FD6D-A4AB-43C4-84E5-0933C84B4F4F":
        return "Linux swap"
    if g == "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7":
        return "données Microsoft"
    if g == "21686148-6449-6E6F-744E-656564454649":
        return "amorçage BIOS"
    return "GUID " + g

func _hex(v: int, digits: int) -> str:
    hexd := "0123456789ABCDEF"
    out := ""
    k := 0
    while k < digits:
        out = str(hexd[(v >> (4 * k)) & 15]) + out
        k += 1
    return out

# GUID (16 octets à addr, format mixte) en texte.
func guid_at(addr: int) -> str:
    a := hw.peek32(addr)
    b := hw.peek16(addr + 4)
    c := hw.peek16(addr + 6)
    t := _hex(a, 8) + "-" + _hex(b, 4) + "-" + _hex(c, 4) + "-"
    t = t + _hex(hw.peek8(addr + 8), 2) + _hex(hw.peek8(addr + 9), 2) + "-"
    k := 10
    while k < 16:
        t = t + _hex(hw.peek8(addr + k), 2)
        k += 1
    return t

class Disk:
    dev: BlockDevice
    model: str := ""
    serial: str := ""
    scheme: str := ""
    entries: list[PartitionEntry] := []
    disk_id: int := 0
    scanned: bool := false

    func init(dev: BlockDevice):
        self.dev = dev
        self.model = ""
        self.serial = ""
        self.scheme = ""
        self.entries = []
        self.disk_id = 0
        self.scanned = false

    func name() -> str:
        return self.dev.name()

    # Lit la table de partitions (une fois ; rescan() pour relire) ; renvoie les entrées.
    func partitions() -> list[PartitionEntry]:
        if self.scanned:
            return self.entries
        self.entries = []
        self.scheme = "aucune"
        bs := self.dev.block_size()
        buf := hw.alloc_pages((bs * 2 + 4095) // 4096)
        self.dev.read_blocks(0, 1, buf)
        if hw.peek16(buf + 510) == 0xAA55:
            self.scheme = "mbr"
            self.disk_id = hw.peek32(buf + 440)
            protective := false
            k := 0
            while k < 4:
                e := buf + 446 + 16 * k
                t := hw.peek8(e + 4)
                start := hw.peek32(e + 8)
                count := hw.peek32(e + 12)
                if t == 0xEE:
                    protective = true
                elif t != 0 and count > 0:
                    p := PartitionEntry(k + 1, "mbr", t, start, count)
                    p.bootable = hw.peek8(e) == 0x80
                    append(self.entries, p)
                k += 1
            if protective:
                self.entries = []
                self._read_gpt(buf)
        hw.free_pages(buf, (bs * 2 + 4095) // 4096)
        self.scanned = true
        return self.entries

    func _read_gpt(buf: int):
        bs := self.dev.block_size()
        self.dev.read_blocks(1, 1, buf)
        if hw.string_at(buf, 8) != "EFI PART":
            self.scheme = "gpt (en-tête invalide)"
            return
        self.scheme = "gpt"
        lba := hw.peek64(buf + 72)
        n := hw.peek32(buf + 80)
        esize := hw.peek32(buf + 84)
        if esize < 128 or n > 1024:
            return
        per := bs // esize
        blocks := (n + per - 1) // per
        tbl := hw.alloc_pages((blocks * bs + 4095) // 4096)
        self.dev.read_blocks(lba, blocks, tbl)
        i := 0
        while i < n:
            e := tbl + i * esize
            first := hw.peek64(e + 32)
            last := hw.peek64(e + 40)
            if hw.peek64(e) != 0 or hw.peek64(e + 8) != 0:
                p := PartitionEntry(i + 1, "gpt", hw.peek32(e), first, last - first + 1)
                p.type_guid = guid_at(e)
                label := ""
                k := 0
                while k < 36:
                    c := hw.peek16(e + 56 + 2 * k)
                    if c == 0:
                        break
                    if c < 128:
                        label = label + str(chr_of(c))
                    else:
                        label = label + "?"
                    k += 1
                p.label = label
                append(self.entries, p)
            i += 1
        hw.free_pages(tbl, (blocks * bs + 4095) // 4096)

    func rescan() -> list[PartitionEntry]:
        self.scanned = false
        return self.partitions()

    # Partition numéro index (1..) comme périphérique de blocs.
    func open(index: int) -> Partition:
        for p in self.partitions():
            if p.index == index:
                return Partition(self.dev, p.start, p.count, self.dev.name() + "p" + str(index))
        raise("DeviceNotFound", self.dev.name() + " : pas de partition " + str(index))

    func describe() -> str:
        parts := self.partitions()
        t := bd.describe(self.dev)
        if self.model != "":
            t = t + ", " + self.model
        if self.serial != "":
            t = t + " (n° " + self.serial + ")"
        t = t + ", table " + self.scheme
        for p in parts:
            t = t + "\n  " + p.describe()
        return t

func chr_of(c: int) -> str:
    table := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    if c >= 32 and c < 127:
        return str(table[c - 32])
    return "?"

# Écrit une table MBR : parts = [[type, début, nombre de blocs], ...] (4 au plus), la première amorçable si
# boot ; disk_id : identifiant du disque. Le reste du secteur 0 (code d'amorçage) est conservé.
func write_mbr(d: BlockDevice, parts: list[list[int]], disk_id: int):
    if len(parts) > 4:
        raise("ArgumentError", "write_mbr : 4 partitions principales au plus")
    bs := d.block_size()
    buf := hw.alloc_pages((bs + 4095) // 4096)
    d.read_blocks(0, 1, buf)
    hw.poke32(buf + 440, disk_id)
    k := 0
    while k < 4:
        e := buf + 446 + 16 * k
        hw.zero(e, 16)
        if k < len(parts):
            p := parts[k]
            if k == 0:
                hw.poke8(e, 0x80)
            hw.poke8(e + 1, 0xFE)
            hw.poke8(e + 2, 0xFF)
            hw.poke8(e + 3, 0xFF)
            hw.poke8(e + 4, p[0])
            hw.poke8(e + 5, 0xFE)
            hw.poke8(e + 6, 0xFF)
            hw.poke8(e + 7, 0xFF)
            hw.poke32(e + 8, p[1])
            hw.poke32(e + 12, p[2])
        k += 1
    hw.poke16(buf + 510, 0xAA55)
    d.write_blocks(0, 1, buf)
    d.flush()
    hw.free_pages(buf, (bs + 4095) // 4096)

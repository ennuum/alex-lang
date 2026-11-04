# Pilote ATA en mode PIO (bus primaire, disque maître : ports 0x1F0..0x1F7) : secteurs de 512 octets, LBA 28.
use hw

const DATA := 496      # 0x1F0
const COUNT := 498     # 0x1F2
const LBA0 := 499      # 0x1F3
const LBA1 := 500
const LBA2 := 501
const DRIVE := 502     # 0x1F6
const STATUS := 503    # 0x1F7 (lecture) / commande (écriture)
const BSY := 128
const DRQ := 8
const ERR := 1

sectors := 0           # taille du disque (IDENTIFY), 0 : absent

func _wait_ready():
    while (hw.inb(STATUS) & BSY) != 0:
        hw.pause()

func _wait_data():
    while true:
        s := hw.inb(STATUS)
        if (s & ERR) != 0:
            raise("DiskError", "erreur du contrôleur ATA (état " + str(s) + ")")
        if (s & BSY) == 0 and (s & DRQ) != 0:
            return

func _select(lba: int, cmd: int):
    _wait_ready()
    hw.outb(DRIVE, 224 | ((lba >> 24) & 15))
    hw.outb(COUNT, 1)
    hw.outb(LBA0, lba & 255)
    hw.outb(LBA1, (lba >> 8) & 255)
    hw.outb(LBA2, (lba >> 16) & 255)
    hw.outb(STATUS, cmd)

# Détecte le disque ; renvoie son nombre de secteurs (0 : pas de disque).
func init() -> int:
    hw.outb(DRIVE, 160)
    hw.outb(COUNT, 0)
    hw.outb(LBA0, 0)
    hw.outb(LBA1, 0)
    hw.outb(LBA2, 0)
    hw.outb(STATUS, 236) # IDENTIFY
    if hw.inb(STATUS) == 0:
        return 0
    _wait_ready()
    if hw.inb(LBA1) != 0 or hw.inb(LBA2) != 0: # pas un disque ATA
        return 0
    _wait_data()
    words: list[int] := [hw.inw(DATA) for i in 0..256]
    sectors = words[60] | (words[61] << 16)
    return sectors

func _check(lba: int):
    if lba < 0 or lba >= sectors:
        raise("DiskError", "secteur " + str(lba) + " hors du disque (" + str(sectors) + " secteurs)")

# Lit le secteur lba dans les 512 octets en buf.
func read(lba: int, buf: int):
    _check(lba)
    f := hw.disable_saved()
    _select(lba, 32)
    _wait_data()
    i := 0
    while i < 256:
        hw.poke16(buf + 2 * i, hw.inw(DATA))
        i += 1
    hw.restore(f)

# Écrit les 512 octets en buf dans le secteur lba (puis vide le cache du disque).
func write(lba: int, buf: int):
    _check(lba)
    f := hw.disable_saved()
    _select(lba, 48)
    _wait_data()
    i := 0
    while i < 256:
        hw.outw(DATA, hw.peek16(buf + 2 * i))
        i += 1
    hw.outb(STATUS, 231) # FLUSH CACHE
    _wait_ready()
    hw.restore(f)

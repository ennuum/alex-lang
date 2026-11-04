# alex: native
# ALEX STANDARD LIBRARY — storage_driver.ata
#
# Pilote ATA / IDE en mode PIO : deux canaux (primaire 0x1F0 / 0x3F6, secondaire 0x170 / 0x376, ou les ports
# des BAR d'un contrôleur PCI en mode natif), deux disques par canal (maître / esclave), IDENTIFY (modèle,
# numéro de série, capacité, LBA48), lecture / écriture de secteurs en LBA28 ou LBA48, vidage du cache,
# détection des lecteurs ATAPI (ignorés) et des canaux vides (bus flottant).
#
#   use storage_driver.ata as ata
#   disks := ata.probe_legacy()                  # list[AtaDisk] trouvés sur les deux canaux
#   d := disks[0]
#   print(d.model, d.block_count())
#   d.read_blocks(0, 1, tampon)
#
#   Pilote du cadre driver : AtaDriver (contrôleurs PCI de classe 01:01) ; après attach, disks() les donne.
#
# Erreurs : DeviceTimeout, DeviceIoError (bit ERR du registre d'état). Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice
use driver.driver_info as di
from driver.driver_info use DriverInfo, HwDevice
from driver.driver use Driver
use driver.driver_errors as de

const REG_DATA := 0
const REG_ERROR := 1
const REG_COUNT := 2
const REG_LBA0 := 3
const REG_LBA1 := 4
const REG_LBA2 := 5
const REG_DRIVE := 6
const REG_STATUS := 7          # lecture : état ; écriture : commande

const ST_ERR := 0x01
const ST_DRQ := 0x08
const ST_DF := 0x20
const ST_RDY := 0x40
const ST_BSY := 0x80

const CMD_READ := 0x20
const CMD_READ_EXT := 0x24
const CMD_WRITE := 0x30
const CMD_WRITE_EXT := 0x34
const CMD_FLUSH := 0xE7
const CMD_FLUSH_EXT := 0xEA
const CMD_IDENTIFY := 0xEC

const TRIES := 2000000

class AtaChannel:
    base: int := 0x1F0
    ctrl: int := 0x3F6
    irq: int := 14
    selected: int := -1

    func init(base: int, ctrl: int, irq: int):
        self.base = base
        self.ctrl = ctrl
        self.irq = irq
        self.selected = -1

    func status() -> int:
        return hw.inb(self.base + REG_STATUS)

    func alt_status() -> int:
        return hw.inb(self.ctrl)

    # ~400 ns : quatre lectures de l'état secondaire.
    func delay():
        k := 0
        while k < 4:
            hw.inb(self.ctrl)
            k += 1

    func select(slave: int, lba_high: int):
        v := 0xE0 | ((slave & 1) << 4) | (lba_high & 15)
        hw.outb(self.base + REG_DRIVE, v)
        self.delay()
        self.selected = slave

    func wait_not_busy() -> bool:
        i := 0
        while i < TRIES:
            s := self.alt_status()
            if s & ST_BSY == 0:
                return true
            i += 1
        return false

    # Attend DRQ (données prêtes) ; DeviceIoError si ERR / DF.
    func wait_data(who: str):
        i := 0
        while i < TRIES:
            s := self.alt_status()
            if s & ST_BSY == 0:
                if s & (ST_ERR | ST_DF) != 0:
                    de.io_error(who, "erreur " + str(hw.inb(self.base + REG_ERROR)), s)
                if s & ST_DRQ != 0:
                    return
            i += 1
        de.timeout(who, "DRQ")

    # Désactive (true) ou active les interruptions du canal (bit nIEN du registre de contrôle).
    func set_interrupts(enabled: bool):
        if enabled:
            hw.outb(self.ctrl, 0)
        else:
            hw.outb(self.ctrl, 2)

    func software_reset():
        hw.outb(self.ctrl, 4 | 2)
        self.delay()
        hw.outb(self.ctrl, 2)
        self.wait_not_busy()

class AtaDisk implements BlockDevice:
    channel: AtaChannel
    slave: int := 0
    label: str := ""
    model: str := ""
    serial: str := ""
    firmware: str := ""
    sectors: int := 0
    lba48: bool := false
    reads: int := 0
    writes: int := 0

    func init(channel: AtaChannel, slave: int, label: str):
        self.channel = channel
        self.slave = slave
        self.label = label
        self.model = ""
        self.serial = ""
        self.firmware = ""
        self.sectors = 0
        self.lba48 = false
        self.reads = 0
        self.writes = 0

    func name() -> str:
        return self.label

    func block_size() -> int:
        return 512

    func block_count() -> int:
        return self.sectors

    func read_only() -> bool:
        return false

    # IDENTIFY : renvoie vrai si un disque ATA répond (faux : absent, ATAPI, bus flottant).
    func identify() -> bool:
        c := self.channel
        if c.status() == 0xFF:
            return false
        c.select(self.slave, 0)
        b := c.base
        hw.outb(b + REG_COUNT, 0)
        hw.outb(b + REG_LBA0, 0)
        hw.outb(b + REG_LBA1, 0)
        hw.outb(b + REG_LBA2, 0)
        hw.outb(b + REG_STATUS, CMD_IDENTIFY)
        c.delay()
        if c.status() == 0:
            return false
        if not c.wait_not_busy():
            return false
        if hw.inb(b + REG_LBA1) != 0 or hw.inb(b + REG_LBA2) != 0:
            return false          # ATAPI / SATA en mode non ATA
        i := 0
        while i < TRIES:
            s := c.alt_status()
            if s & ST_ERR != 0:
                return false
            if s & ST_DRQ != 0:
                break
            i += 1
        if i == TRIES:
            return false
        words: list[int] := [hw.inw(b + REG_DATA) for k in 0..256]
        self.serial = _ident_string(words, 10, 20)
        self.firmware = _ident_string(words, 23, 27)
        self.model = _ident_string(words, 27, 47)
        self.lba48 = words[83] & 0x400 != 0
        if self.lba48:
            self.sectors = words[100] | (words[101] << 16) | (words[102] << 32) | (words[103] << 48)
        else:
            self.sectors = words[60] | (words[61] << 16)
        return self.sectors > 0

    func _command(lba: int, count: int, cmd28: int, cmd48: int):
        c := self.channel
        b := c.base
        if not c.wait_not_busy():
            de.timeout(self.label, "BSY")
        if self.lba48 and (lba + count > 0x0FFFFFFF or count > 256):
            c.select(self.slave, 0)
            hw.outb(b + REG_COUNT, (count >> 8) & 255)
            hw.outb(b + REG_LBA0, (lba >> 24) & 255)
            hw.outb(b + REG_LBA1, (lba >> 32) & 255)
            hw.outb(b + REG_LBA2, (lba >> 40) & 255)
            hw.outb(b + REG_COUNT, count & 255)
            hw.outb(b + REG_LBA0, lba & 255)
            hw.outb(b + REG_LBA1, (lba >> 8) & 255)
            hw.outb(b + REG_LBA2, (lba >> 16) & 255)
            hw.outb(b + REG_STATUS, cmd48)
        else:
            c.select(self.slave, (lba >> 24) & 15)
            hw.outb(b + REG_COUNT, count & 255)
            hw.outb(b + REG_LBA0, lba & 255)
            hw.outb(b + REG_LBA1, (lba >> 8) & 255)
            hw.outb(b + REG_LBA2, (lba >> 16) & 255)
            hw.outb(b + REG_STATUS, cmd28)

    func _max_chunk() -> int:
        if self.lba48:
            return 65536
        return 256

    func read_blocks(lba: int, count: int, buf: int) -> bool:
        bd.check_range(self, lba, count)
        f := hw.disable_saved()
        done := 0
        while done < count:
            n := count - done
            if n > self._max_chunk():
                n = self._max_chunk()
            self._command(lba + done, n & 0xFFFF, CMD_READ, CMD_READ_EXT)
            k := 0
            while k < n:
                self.channel.wait_data(self.label)
                dst := buf + (done + k) * 512
                i := 0
                while i < 256:
                    hw.poke16(dst + 2 * i, hw.inw(self.channel.base + REG_DATA))
                    i += 1
                k += 1
            done += n
        hw.restore(f)
        self.reads += count
        return true

    func write_blocks(lba: int, count: int, buf: int) -> bool:
        bd.check_range(self, lba, count)
        f := hw.disable_saved()
        done := 0
        while done < count:
            n := count - done
            if n > self._max_chunk():
                n = self._max_chunk()
            self._command(lba + done, n & 0xFFFF, CMD_WRITE, CMD_WRITE_EXT)
            k := 0
            while k < n:
                self.channel.wait_data(self.label)
                src := buf + (done + k) * 512
                i := 0
                while i < 256:
                    hw.outw(self.channel.base + REG_DATA, hw.peek16(src + 2 * i))
                    i += 1
                k += 1
            done += n
        self.channel.wait_not_busy()
        hw.restore(f)
        self.writes += count
        return true

    func flush() -> bool:
        c := self.channel
        c.select(self.slave, 0)
        if self.lba48:
            hw.outb(c.base + REG_STATUS, CMD_FLUSH_EXT)
        else:
            hw.outb(c.base + REG_STATUS, CMD_FLUSH)
        c.delay()
        if not c.wait_not_busy():
            de.timeout(self.label, "FLUSH CACHE")
        return c.status() & ST_ERR == 0

    func describe() -> str:
        t := bd.describe(self) + ", " + self.model
        if self.lba48:
            t = t + ", LBA48"
        return t

# Chaîne d'IDENTIFY : mots [from, to), octets échangés dans chaque mot, espaces de fin retirés.
func _ident_string(words: list[int], start: int, stop: int) -> str:
    chars := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    out := ""
    pending := ""
    k := start
    while k < stop:
        w := words[k]
        pair: list[int] := [(w >> 8) & 255, w & 255]
        for ch in pair:
            if ch == 32 or ch == 0:
                if out != "":
                    pending = pending + " "
            elif ch > 32 and ch < 127:
                out = out + pending + str(chars[ch - 32])
                pending = ""
        k += 1
    return out

# Disques des canaux donnés : list[AtaDisk] (noms ata0..ata3).
func probe_channels(channels: list[AtaChannel]) -> list[AtaDisk]:
    out: list[AtaDisk] := []
    n := 0
    for c in channels:
        c.set_interrupts(false)
        s := 0
        while s < 2:
            d := AtaDisk(c, s, "ata" + str(2 * n + s))
            if d.identify():
                append(out, d)
            s += 1
        n += 1
    return out

func legacy_channels() -> list[AtaChannel]:
    return [AtaChannel(0x1F0, 0x3F6, 14), AtaChannel(0x170, 0x376, 15)]

func probe_legacy() -> list[AtaDisk]:
    return probe_channels(legacy_channels())

# ---------------------------------------------------------------- pilote du cadre driver
class AtaDriver implements Driver:
    i: DriverInfo
    found: list[AtaDisk] := []

    func init():
        self.i = DriverInfo("ata-pio", "1.0", "contrôleur IDE / ATA en PIO", "pci")
        self.i.add_id(di.pci_class(0x01, 0x01))
        self.found = []

    func info() -> DriverInfo:
        return self.i

    # Canaux du contrôleur : mode natif (bits 0 / 2 de prog_if) -> ports des BAR, sinon ports historiques.
    func channels(dev: HwDevice) -> list[AtaChannel]:
        out: list[AtaChannel] := []
        if dev.prog_if & 1 != 0 and dev.io_base(0) > 0:
            append(out, AtaChannel(dev.io_base(0), dev.io_base(1) + 2, dev.irq))
        else:
            append(out, AtaChannel(0x1F0, 0x3F6, 14))
        if dev.prog_if & 4 != 0 and dev.io_base(2) > 0:
            append(out, AtaChannel(dev.io_base(2), dev.io_base(3) + 2, dev.irq))
        else:
            append(out, AtaChannel(0x170, 0x376, 15))
        return out

    func probe(dev: HwDevice) -> bool:
        for c in self.channels(dev):
            if c.status() != 0xFF:
                return true
        return false

    func attach(dev: HwDevice):
        p := dev.pci
        if p != null:
            p.enable_io()
        self.found = probe_channels(self.channels(dev))

    func detach(dev: HwDevice):
        self.found = []

    func status(dev: HwDevice) -> str:
        return str(len(self.found)) + " disque(s)"

    func disks() -> list[AtaDisk]:
        return self.found

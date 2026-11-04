# alex: native
# ALEX STANDARD LIBRARY — storage_driver.ahci
#
# Pilote AHCI (SATA) : contrôleur PCI de classe 01:06 / interface 01, registres en MMIO (BAR5, « ABAR »).
#   - initialisation du contrôleur (mode AHCI, interruptions coupées), ports implantés (PI), détection des
#     disques présents (SSTS.DET = 3) et de leur type (signature : SATA, ATAPI, multiplicateur) ;
#   - par port : liste de commandes (32 emplacements), zone des FIS reçus, tables de commande avec PRDT ;
#   - commandes ATA par FIS hôte -> périphérique : IDENTIFY, READ / WRITE DMA EXT (LBA48), FLUSH CACHE EXT ;
#   - fin de commande par scrutation de CI ; erreurs : IS.TFES et registre TFD.
#
#   use storage_driver.ahci as ahci
#   ctl := ahci.AhciController(hw.mmio(abar_phys))
#   ctl.setup()
#   for d in ctl.disks():           # AhciDisk (BlockDevice)
#       d.read_blocks(0, 8, tampon)
#
#   Pilote du cadre driver : AhciDriver (PCI 01:06:01).
#
# Erreurs : DeviceTimeout, DeviceIoError. Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice
use driver.driver_info as di
from driver.driver_info use DriverInfo, HwDevice
from driver.driver use Driver
use driver.driver_errors as de

const CAP := 0x00
const GHC := 0x04
const IS := 0x08
const PI := 0x0C
const VS := 0x10

const GHC_AE := 0x80000000
const GHC_IE := 0x2
const GHC_HR := 0x1

const P_CLB := 0x00
const P_CLBU := 0x04
const P_FB := 0x08
const P_FBU := 0x0C
const P_IS := 0x10
const P_IE := 0x14
const P_CMD := 0x18
const P_TFD := 0x20
const P_SIG := 0x24
const P_SSTS := 0x28
const P_SERR := 0x30
const P_CI := 0x38

const CMD_ST := 0x0001
const CMD_FRE := 0x0010
const CMD_FR := 0x4000
const CMD_CR := 0x8000

const SIG_SATA := 0x00000101
const SIG_ATAPI := 0xEB140101
const SIG_SEMB := 0xC33C0101
const SIG_PM := 0x96690101

const FIS_H2D := 0x27
const ATA_IDENTIFY := 0xEC
const ATA_READ_DMA_EXT := 0x25
const ATA_WRITE_DMA_EXT := 0x35
const ATA_FLUSH_EXT := 0xEA

const TRIES := 5000000
const MAX_BLOCKS := 128       # par commande (64 Kio : un tampon de rebond d'une PRD)

func signature_name(sig: int) -> str:
    if sig == SIG_SATA:
        return "SATA"
    if sig == SIG_ATAPI:
        return "SATAPI"
    if sig == SIG_SEMB:
        return "pont SEMB"
    if sig == SIG_PM:
        return "multiplicateur de ports"
    return "inconnu"

class AhciPort:
    abar: int := 0
    index: int := 0
    regs: int := 0
    clb: int := 0          # liste de commandes (1 Kio) + FIS reçus (256 o) + table de commande : une page
    fb: int := 0
    table: int := 0
    bounce: int := 0       # tampon de 64 Kio pour les transferts
    started: bool := false

    func init(abar: int, index: int):
        self.abar = abar
        self.index = index
        self.regs = abar + 0x100 + 0x80 * index
        self.started = false

    func read(reg: int) -> int:
        return hw.peek32(self.regs + reg)

    func write(reg: int, v: int):
        hw.poke32(self.regs + reg, v & 0xFFFFFFFF)

    func present() -> bool:
        return self.read(P_SSTS) & 15 == 3

    func signature() -> int:
        return self.read(P_SIG)

    func stop():
        self.write(P_CMD, self.read(P_CMD) & ~CMD_ST)
        de.wait_mmio32(self.regs + P_CMD, CMD_CR, 0, TRIES)
        self.write(P_CMD, self.read(P_CMD) & ~CMD_FRE)
        de.wait_mmio32(self.regs + P_CMD, CMD_FR, 0, TRIES)

    # Mémoire du port (liste de commandes, FIS reçus, table de commande, tampon) puis démarrage.
    func start():
        self.stop()
        page := hw.alloc_pages(1)
        self.clb = page
        self.fb = page + 1024
        self.table = page + 2048          # aligné sur 128 : CFIS 64 o, ACMD, PRDT à +0x80 (1 PRD)
        self.bounce = hw.alloc_pages(16)
        self.write(P_CLB, self.clb)
        self.write(P_CLBU, 0)
        self.write(P_FB, self.fb)
        self.write(P_FBU, 0)
        self.write(P_SERR, 0xFFFFFFFF)
        self.write(P_IS, 0xFFFFFFFF)
        self.write(P_IE, 0)
        self.write(P_CMD, self.read(P_CMD) | CMD_FRE)
        self.write(P_CMD, self.read(P_CMD) | CMD_ST)
        self.started = true

    # Exécute une commande ATA (emplacement 0) : bytes octets de données à la PRD (tampon de rebond).
    func command(cmd: int, lba: int, count: int, bytes: int, write: bool, who: str):
        if not de.wait_mmio32(self.regs + P_TFD, 0x88, 0, TRIES):
            de.timeout(who, "port occupé (TFD " + str(self.read(P_TFD)) + ")")
        h := self.clb
        flags := 5                       # longueur du FIS : 5 mots
        if write:
            flags = flags | 0x40
        prdtl := 0
        if bytes > 0:
            prdtl = 1
        hw.poke32(h, flags | (prdtl << 16))
        hw.poke32(h + 4, 0)
        hw.poke32(h + 8, self.table)
        hw.poke32(h + 12, 0)
        t := self.table
        hw.zero(t, 0x90)
        hw.poke8(t, FIS_H2D)
        hw.poke8(t + 1, 0x80)
        hw.poke8(t + 2, cmd)
        hw.poke8(t + 4, lba & 255)
        hw.poke8(t + 5, (lba >> 8) & 255)
        hw.poke8(t + 6, (lba >> 16) & 255)
        hw.poke8(t + 7, 0x40)
        hw.poke8(t + 8, (lba >> 24) & 255)
        hw.poke8(t + 9, (lba >> 32) & 255)
        hw.poke8(t + 10, (lba >> 40) & 255)
        hw.poke8(t + 12, count & 255)
        hw.poke8(t + 13, (count >> 8) & 255)
        if bytes > 0:
            hw.poke32(t + 0x80, self.bounce)
            hw.poke32(t + 0x84, 0)
            hw.poke32(t + 0x88, 0)
            hw.poke32(t + 0x8C, (bytes - 1) & 0x3FFFFF)
        self.write(P_IS, 0xFFFFFFFF)
        self.write(P_CI, 1)
        i := 0
        while i < TRIES:
            if self.read(P_CI) & 1 == 0:
                break
            if self.read(P_IS) & 0x40000000 != 0:
                de.io_error(who, "erreur de fichier de tâche", self.read(P_TFD))
            i += 1
        if i == TRIES:
            de.timeout(who, "commande " + str(cmd))
        if self.read(P_IS) & 0x40000000 != 0 or self.read(P_TFD) & 1 != 0:
            de.io_error(who, "commande " + str(cmd), self.read(P_TFD))

class AhciDisk implements BlockDevice:
    port: AhciPort
    label: str := ""
    model: str := ""
    serial: str := ""
    sectors: int := 0
    sector_size: int := 512
    reads: int := 0
    writes: int := 0

    func init(port: AhciPort, label: str):
        self.port = port
        self.label = label
        self.model = ""
        self.serial = ""
        self.sectors = 0
        self.sector_size = 512
        self.reads = 0
        self.writes = 0

    func name() -> str:
        return self.label

    func block_size() -> int:
        return self.sector_size

    func block_count() -> int:
        return self.sectors

    func read_only() -> bool:
        return false

    func identify() -> bool:
        self.port.command(ATA_IDENTIFY, 0, 0, 512, false, self.label)
        b := self.port.bounce
        words: list[int] := [hw.peek16(b + 2 * k) for k in 0..256]
        self.model = _swap_string(words, 27, 47)
        self.serial = _swap_string(words, 10, 20)
        if words[83] & 0x400 != 0:
            self.sectors = words[100] | (words[101] << 16) | (words[102] << 32) | (words[103] << 48)
        else:
            self.sectors = words[60] | (words[61] << 16)
        if words[106] & 0xC000 == 0x4000 and words[106] & 0x1000 != 0:
            self.sector_size = 2 * (words[117] | (words[118] << 16))
        return self.sectors > 0

    func read_blocks(lba: int, count: int, buf: int) -> bool:
        bd.check_range(self, lba, count)
        done := 0
        bs := self.sector_size
        limit := 65536 // bs
        while done < count:
            n := count - done
            if n > limit:
                n = limit
            self.port.command(ATA_READ_DMA_EXT, lba + done, n, n * bs, false, self.label)
            hw.copy(buf + done * bs, self.port.bounce, n * bs)
            done += n
        self.reads += count
        return true

    func write_blocks(lba: int, count: int, buf: int) -> bool:
        bd.check_range(self, lba, count)
        done := 0
        bs := self.sector_size
        limit := 65536 // bs
        while done < count:
            n := count - done
            if n > limit:
                n = limit
            hw.copy(self.port.bounce, buf + done * bs, n * bs)
            self.port.command(ATA_WRITE_DMA_EXT, lba + done, n, n * bs, true, self.label)
            done += n
        self.writes += count
        return true

    func flush() -> bool:
        self.port.command(ATA_FLUSH_EXT, 0, 0, 0, false, self.label)
        return true

    func describe() -> str:
        return bd.describe(self) + ", " + self.model + " (port " + str(self.port.index) + ")"

func _swap_string(words: list[int], start: int, stop: int) -> str:
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

class AhciController:
    abar: int := 0
    ports: list[AhciPort] := []
    found: list[AhciDisk] := []
    others: list[str] := []

    # abar : adresse (déjà passée par hw.mmio) des registres.
    func init(abar: int):
        self.abar = abar
        self.ports = []
        self.found = []
        self.others = []

    func read(reg: int) -> int:
        return hw.peek32(self.abar + reg)

    func write(reg: int, v: int):
        hw.poke32(self.abar + reg, v & 0xFFFFFFFF)

    func version() -> str:
        v := self.read(VS)
        return str((v >> 16) & 0xFFFF) + "." + str((v >> 8) & 255)

    func port_count() -> int:
        return (self.read(CAP) & 31) + 1

    func supports_64bit() -> bool:
        return self.read(CAP) & 0x80000000 != 0

    # Mode AHCI, interruptions coupées, ports présents démarrés et disques identifiés (noms sata0, sata1...).
    func setup():
        self.write(GHC, self.read(GHC) | GHC_AE)
        self.write(GHC, self.read(GHC) & ~GHC_IE)
        self.write(IS, 0xFFFFFFFF)
        implemented := self.read(PI)
        n := 0
        i := 0
        while i < 32:
            if implemented & (1 << i) != 0:
                p := AhciPort(self.abar, i)
                append(self.ports, p)
                if p.present():
                    sig := p.signature()
                    if sig == SIG_SATA:
                        p.start()
                        d := AhciDisk(p, "sata" + str(n))
                        if d.identify():
                            append(self.found, d)
                            n += 1
                    else:
                        append(self.others, "port " + str(i) + " : " + signature_name(sig))
            i += 1

    func disks() -> list[AhciDisk]:
        return self.found

    func describe() -> str:
        t := "AHCI " + self.version() + ", " + str(self.port_count()) + " ports, " + str(len(self.found)) + " disque(s)"
        for o in self.others:
            t = t + "\n  " + o
        return t

# ---------------------------------------------------------------- pilote du cadre driver
class AhciDriver implements Driver:
    i: DriverInfo
    ctl: AhciController?

    func init():
        self.i = DriverInfo("ahci", "1.0", "contrôleur SATA AHCI", "pci")
        self.i.add_id(di.pci_class_if(0x01, 0x06, 0x01))
        self.ctl = null

    func info() -> DriverInfo:
        return self.i

    func probe(dev: HwDevice) -> bool:
        return dev.mem_base(0) > 0

    func attach(dev: HwDevice):
        p := dev.pci
        if p != null:
            p.enable_memory()
            p.enable_bus_master()
        abar := dev.mem_base(0)
        if p != null:
            abar = p.bar_address(5)
        c := AhciController(hw.mmio(abar))
        c.setup()
        self.ctl = c

    func detach(dev: HwDevice):
        c := self.ctl
        if c != null:
            for d in c.found:
                d.port.stop()
        self.ctl = null

    func status(dev: HwDevice) -> str:
        c := self.ctl
        if c == null:
            return "arrêté"
        return c.describe()

    func disks() -> list[AhciDisk]:
        c := self.ctl
        if c == null:
            return []
        return c.found

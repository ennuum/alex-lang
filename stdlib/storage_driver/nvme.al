# alex: native
# ALEX STANDARD LIBRARY — storage_driver.nvme
#
# Pilote NVMe (PCI Express, classe 01:08 / interface 02), registres en MMIO (BAR0) :
#   - réinitialisation et activation du contrôleur (CC / CSTS), file d'administration (AQA, ASQ, ACQ) ;
#   - IDENTIFY du contrôleur (modèle, numéro de série, micrologiciel, nombre d'espaces de noms) et de chaque
#     espace de noms (capacité, taille de bloc d'après le format LBA actif) ;
#   - une paire de files d'entrées-sorties (soumission / complétion) créée par commandes d'administration ;
#   - lecture / écriture / vidage avec PRP1, PRP2 et liste PRP (tampon de rebond de 64 Kio) ;
#   - complétions par bit de phase, sonnettes (doorbells) avec leur pas (CAP.DSTRD).
#
#   use storage_driver.nvme as nvme
#   ctl := nvme.NvmeController(hw.mmio(bar0_phys))
#   ctl.setup()
#   ns := ctl.namespaces()[0]          # NvmeNamespace (BlockDevice)
#   ns.read_blocks(0, 8, tampon)
#
#   Pilote du cadre driver : NvmeDriver (PCI 01:08:02).
#
# Erreurs : DeviceTimeout, DeviceIoError (état de complétion). Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice
use driver.driver_info as di
from driver.driver_info use DriverInfo, HwDevice
from driver.driver use Driver
use driver.driver_errors as de

const REG_CAP := 0x00
const REG_VS := 0x08
const REG_CC := 0x14
const REG_CSTS := 0x1C
const REG_AQA := 0x24
const REG_ASQ := 0x28
const REG_ACQ := 0x30

const ADMIN_CREATE_SQ := 0x01
const ADMIN_CREATE_CQ := 0x05
const ADMIN_IDENTIFY := 0x06
const IO_FLUSH := 0x00
const IO_WRITE := 0x01
const IO_READ := 0x02

const QUEUE_SIZE := 64
const TRIES := 20000000
const BOUNCE_PAGES := 16

class NvmeQueue:
    id: int := 0
    sq: int := 0
    cq: int := 0
    size: int := 64
    tail: int := 0
    head: int := 0
    phase: int := 1
    sq_doorbell: int := 0
    cq_doorbell: int := 0
    next_cid: int := 0

    func init(id: int, size: int, regs: int, stride: int):
        self.id = id
        self.size = size
        self.sq = hw.alloc_pages((size * 64 + 4095) // 4096)
        self.cq = hw.alloc_pages((size * 16 + 4095) // 4096)
        self.tail = 0
        self.head = 0
        self.phase = 1
        self.sq_doorbell = regs + 0x1000 + (2 * id) * stride
        self.cq_doorbell = regs + 0x1000 + (2 * id + 1) * stride
        self.next_cid = 0

    # Soumet une commande et attend sa complétion ; renvoie [état, résultat (DW0)].
    func submit(opcode: int, nsid: int, prp1: int, prp2: int, c10: int, c11: int, c12: int, who: str) -> list[int]:
        e := self.sq + self.tail * 64
        hw.zero(e, 64)
        cid := self.next_cid
        self.next_cid = (self.next_cid + 1) & 0xFFFF
        hw.poke32(e, opcode | (cid << 16))
        hw.poke32(e + 4, nsid)
        hw.poke64(e + 24, prp1)
        hw.poke64(e + 32, prp2)
        hw.poke32(e + 40, c10)
        hw.poke32(e + 44, c11)
        hw.poke32(e + 48, c12)
        self.tail = (self.tail + 1) % self.size
        hw.poke32(self.sq_doorbell, self.tail)
        c := self.cq + self.head * 16
        i := 0
        while i < TRIES:
            if (hw.peek32(c + 12) >> 16) & 1 == self.phase:
                break
            i += 1
        if i == TRIES:
            de.timeout(who, "complétion de la commande " + str(opcode))
        dw3 := hw.peek32(c + 12)
        status := (dw3 >> 17) & 0x7FFF
        result := hw.peek32(c)
        self.head = (self.head + 1) % self.size
        if self.head == 0:
            self.phase = 1 - self.phase
        hw.poke32(self.cq_doorbell, self.head)
        if status != 0:
            de.io_error(who, "commande " + str(opcode) + " refusée", status)
        return [status, result]

class NvmeNamespace implements BlockDevice:
    ctl: NvmeController
    nsid: int := 1
    label: str := ""
    blocks: int := 0
    bsize: int := 512
    reads: int := 0
    writes: int := 0

    func init(ctl: NvmeController, nsid: int, label: str):
        self.ctl = ctl
        self.nsid = nsid
        self.label = label
        self.blocks = 0
        self.bsize = 512
        self.reads = 0
        self.writes = 0

    func name() -> str:
        return self.label

    func block_size() -> int:
        return self.bsize

    func block_count() -> int:
        return self.blocks

    func read_only() -> bool:
        return false

    func identify() -> bool:
        b := self.ctl.bounce
        self.ctl.admin.submit(ADMIN_IDENTIFY, self.nsid, b, 0, 0, 0, 0, self.label)
        self.blocks = hw.peek64(b)
        fmt := hw.peek8(b + 26) & 15
        lbads := (hw.peek32(b + 128 + 4 * fmt) >> 16) & 255
        if lbads >= 9:
            self.bsize = 1 << lbads
        return self.blocks > 0

    func _io(opcode: int, lba: int, n: int):
        self.ctl.io.submit(opcode, self.nsid, self.ctl.bounce, self.ctl.prp2_for(n * self.bsize), lba & 0xFFFFFFFF, (lba >> 32) & 0xFFFFFFFF, n - 1, self.label)

    func read_blocks(lba: int, count: int, buf: int) -> bool:
        bd.check_range(self, lba, count)
        limit := BOUNCE_PAGES * 4096 // self.bsize
        done := 0
        while done < count:
            n := count - done
            if n > limit:
                n = limit
            self._io(IO_READ, lba + done, n)
            hw.copy(buf + done * self.bsize, self.ctl.bounce, n * self.bsize)
            done += n
        self.reads += count
        return true

    func write_blocks(lba: int, count: int, buf: int) -> bool:
        bd.check_range(self, lba, count)
        limit := BOUNCE_PAGES * 4096 // self.bsize
        done := 0
        while done < count:
            n := count - done
            if n > limit:
                n = limit
            hw.copy(self.ctl.bounce, buf + done * self.bsize, n * self.bsize)
            self._io(IO_WRITE, lba + done, n)
            done += n
        self.writes += count
        return true

    func flush() -> bool:
        self.ctl.io.submit(IO_FLUSH, self.nsid, 0, 0, 0, 0, 0, self.label)
        return true

    func describe() -> str:
        return bd.describe(self) + ", espace de noms " + str(self.nsid) + " de " + self.ctl.model

class NvmeController:
    regs: int := 0
    stride: int := 4
    max_entries: int := 0
    timeout_ms: int := 0
    admin: NvmeQueue
    io: NvmeQueue
    bounce: int := 0
    prp_list: int := 0
    model: str := ""
    serial: str := ""
    firmware: str := ""
    ns_count: int := 0
    found: list[NvmeNamespace] := []

    # regs : adresse (déjà passée par hw.mmio) des registres (BAR0).
    func init(regs: int):
        self.regs = regs
        cap := hw.peek64(regs + REG_CAP)
        self.stride = 4 << ((cap >> 32) & 15)
        self.max_entries = (cap & 0xFFFF) + 1
        self.timeout_ms = ((cap >> 24) & 255) * 500
        self.admin = NvmeQueue(0, 32, regs, self.stride)
        self.io = NvmeQueue(1, QUEUE_SIZE, regs, self.stride)
        self.bounce = hw.alloc_pages(BOUNCE_PAGES)
        self.prp_list = hw.alloc_pages(1)
        self.model = ""
        self.serial = ""
        self.firmware = ""
        self.ns_count = 0
        self.found = []

    func version() -> str:
        v := hw.peek32(self.regs + REG_VS)
        return str((v >> 16) & 0xFFFF) + "." + str((v >> 8) & 255)

    # PRP2 pour un transfert de bytes octets depuis le tampon de rebond : 0, la deuxième page, ou une liste PRP.
    func prp2_for(bytes: int) -> int:
        pages := (bytes + 4095) // 4096
        if pages <= 1:
            return 0
        if pages == 2:
            return self.bounce + 4096
        k := 1
        while k < pages:
            hw.poke64(self.prp_list + 8 * (k - 1), self.bounce + 4096 * k)
            k += 1
        return self.prp_list

    func _wait_ready(want: int):
        if not de.wait_mmio32(self.regs + REG_CSTS, 1, want, TRIES):
            de.timeout("nvme", "CSTS.RDY = " + str(want))

    # Réinitialise, crée la file d'administration et une file d'E/S, identifie le contrôleur et ses espaces
    # de noms (nvme0n1, nvme0n2...).
    func setup():
        cc := hw.peek32(self.regs + REG_CC)
        if cc & 1 != 0:
            hw.poke32(self.regs + REG_CC, cc & ~1)
        self._wait_ready(0)
        a := self.admin
        hw.poke32(self.regs + REG_AQA, ((a.size - 1) << 16) | (a.size - 1))
        hw.poke64(self.regs + REG_ASQ, a.sq)
        hw.poke64(self.regs + REG_ACQ, a.cq)
        hw.poke32(self.regs + REG_CC, (4 << 20) | (6 << 16) | 1)
        self._wait_ready(1)
        if hw.peek32(self.regs + REG_CSTS) & 2 != 0:
            de.fail("nvme", "erreur fatale du contrôleur (CSTS.CFS)")
        b := self.bounce
        a.submit(ADMIN_IDENTIFY, 0, b, 0, 1, 0, 0, "nvme")
        self.serial = _ascii(b + 4, 20)
        self.model = _ascii(b + 24, 40)
        self.firmware = _ascii(b + 64, 8)
        self.ns_count = hw.peek32(b + 516)
        q := self.io
        a.submit(ADMIN_CREATE_CQ, 0, q.cq, 0, ((q.size - 1) << 16) | q.id, 1, 0, "nvme")
        a.submit(ADMIN_CREATE_SQ, 0, q.sq, 0, ((q.size - 1) << 16) | q.id, (q.id << 16) | 1, 0, "nvme")
        n := 1
        while n <= self.ns_count and n <= 16:
            ns := NvmeNamespace(self, n, "nvme0n" + str(n))
            if ns.identify():
                append(self.found, ns)
            n += 1

    func namespaces() -> list[NvmeNamespace]:
        return self.found

    func shutdown():
        cc := hw.peek32(self.regs + REG_CC)
        hw.poke32(self.regs + REG_CC, (cc & ~0xC000) | 0x4000)
        de.wait_mmio32(self.regs + REG_CSTS, 0xC, 0x8, TRIES)

    func describe() -> str:
        return "NVMe " + self.version() + " " + self.model + " (n° " + self.serial + ", micrologiciel " + self.firmware + "), " + str(len(self.found)) + " espace(s) de noms"

func _ascii(addr: int, n: int) -> str:
    chars := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    out := ""
    pending := ""
    k := 0
    while k < n:
        ch := hw.peek8(addr + k)
        if ch == 32 or ch == 0:
            if out != "":
                pending = pending + " "
        elif ch > 32 and ch < 127:
            out = out + pending + str(chars[ch - 32])
            pending = ""
        k += 1
    return out

# ---------------------------------------------------------------- pilote du cadre driver
class NvmeDriver implements Driver:
    i: DriverInfo
    ctl: NvmeController?

    func init():
        self.i = DriverInfo("nvme", "1.0", "contrôleur NVM Express", "pci")
        self.i.add_id(di.pci_class_if(0x01, 0x08, 0x02))
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
            p.disable_intx()
        c := NvmeController(hw.mmio(dev.mem_base(0)))
        c.setup()
        self.ctl = c

    func detach(dev: HwDevice):
        c := self.ctl
        if c != null:
            c.shutdown()
        self.ctl = null

    func status(dev: HwDevice) -> str:
        c := self.ctl
        if c == null:
            return "arrêté"
        return c.describe()

    func namespaces() -> list[NvmeNamespace]:
        c := self.ctl
        if c == null:
            return []
        return c.found

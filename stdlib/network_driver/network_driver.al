# alex: native
# ALEX STANDARD LIBRARY — network_driver
#
# Pilotes réseau d'un noyau Alex (--freestanding), et le pilote Intel PRO/1000 (e1000 : 82540EM de QEMU,
# 82545EM, 82574L...) :
#   - réinitialisation, adresse MAC (registres RAL/RAH ou EEPROM), lien (STATUS.LU), table de multidiffusion ;
#   - anneaux de réception et d'émission (descripteurs de 16 octets, tampons de 2048 octets, DMA) ;
#   - émission par copie dans le tampon du descripteur, fin d'émission par le bit DD ;
#   - réception par scrutation des descripteurs (DD, EOP, erreurs), recyclage des tampons ;
#   - interruptions (ICR / IMS) optionnelles, compteurs matériels (CRCERRS, MPC, GPRC, GPTC).
#
# | Module                           | Contenu                                                       |
# |----------------------------------|---------------------------------------------------------------|
# | network_driver.ethernet          | adresses MAC, en-tête, EtherType, CRC-32                      |
# | network_driver.network_buffer    | PacketBuffer (marges, push / pull), BufferPool                |
# | network_driver.network_packet    | ARP, IPv4, ICMP, UDP : construction, analyse, sommes          |
# | network_driver.network_device    | interface NetworkDevice, LoopbackDevice, NetInterface (IPv4)  |
# | network_driver.network_stats     | compteurs                                                     |
#
#   use network_driver
#   carte := network_driver.find_e1000()             # E1000Device? (bus PCI, pilote lié)
#   itf := NetInterface(carte, np.ip("10.0.2.15"), np.ip("10.0.2.2"))
#   print(itf.ping(itf.gateway, 1, 1000000))
#
# Erreurs : DeviceTimeout, DeviceNotFound. Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use pci.pci_config as cfg
use pci.pci_bus as pbus
from pci.pci_bus use PciBus
use driver.driver_info as di
from driver.driver_info use DriverInfo, HwDevice
from driver.driver use Driver
use driver.driver_errors as de
use driver.driver_manager as dmg
use network_driver.ethernet as eth
use network_driver.network_buffer as nbuf
from network_driver.network_buffer use PacketBuffer, BufferPool
use network_driver.network_stats as nst
from network_driver.network_stats use NetworkStats
use network_driver.network_device as nd
from network_driver.network_device use NetworkDevice

const CTRL := 0x0000
const STATUS := 0x0008
const EERD := 0x0014
const ICR := 0x00C0
const IMS := 0x00D0
const IMC := 0x00D8
const RCTL := 0x0100
const TCTL := 0x0400
const TIPG := 0x0410
const RDBAL := 0x2800
const RDBAH := 0x2804
const RDLEN := 0x2808
const RDH := 0x2810
const RDT := 0x2818
const TDBAL := 0x3800
const TDBAH := 0x3804
const TDLEN := 0x3808
const TDH := 0x3810
const TDT := 0x3818
const MTA := 0x5200
const RAL0 := 0x5400
const RAH0 := 0x5404
const CRCERRS := 0x4000
const MPC := 0x4010
const GPRC := 0x4074
const GPTC := 0x4080

const CTRL_SLU := 0x40
const CTRL_ASDE := 0x20
const CTRL_RST := 0x04000000
const RCTL_EN := 0x2
const RCTL_SBP := 0x4
const RCTL_UPE := 0x8
const RCTL_MPE := 0x10
const RCTL_BAM := 0x8000
const RCTL_SECRC := 0x04000000
const TCTL_EN := 0x2
const TCTL_PSP := 0x8

const RX_COUNT := 32
const TX_COUNT := 32

class E1000Device implements NetworkDevice:
    regs: int := 0
    label: str := ""
    address: int := 0
    rx_ring: int := 0
    tx_ring: int := 0
    rx_bufs: int := 0          # RX_COUNT tampons de 2048 octets contigus
    tx_bufs: int := 0
    rx_next: int := 0
    tx_next: int := 0
    pool: BufferPool
    counters: NetworkStats
    promiscuous: bool := false
    eeprom: bool := false

    # regs : adresse (déjà passée par hw.mmio) des registres (BAR0).
    func init(regs: int, label: str):
        self.regs = regs
        self.label = label
        self.pool = BufferPool(0)
        self.counters = NetworkStats()
        self.rx_next = 0
        self.tx_next = 0
        self.promiscuous = false
        self.eeprom = false

    func read(reg: int) -> int:
        return hw.peek32(self.regs + reg)

    func write(reg: int, v: int):
        hw.poke32(self.regs + reg, v & 0xFFFFFFFF)

    func _eeprom_word(addr: int) -> int:
        self.write(EERD, (addr << 8) | 1)
        i := 0
        while i < 100000:
            v := self.read(EERD)
            if v & 0x10 != 0:
                return (v >> 16) & 0xFFFF
            i += 1
        return -1

    func _read_mac() -> int:
        lo := self.read(RAL0)
        hi := self.read(RAH0)
        if hi & 0x80000000 != 0 and (lo != 0 or hi & 0xFFFF != 0):
            m := 0
            k := 0
            while k < 4:
                m = (m << 8) | ((lo >> (8 * k)) & 255)
                k += 1
            m = (m << 8) | (hi & 255)
            m = (m << 8) | ((hi >> 8) & 255)
            return m
        w0 := self._eeprom_word(0)
        if w0 < 0:
            return 0
        self.eeprom = true
        w1 := self._eeprom_word(1)
        w2 := self._eeprom_word(2)
        return ((w0 & 255) << 40) | ((w0 >> 8) << 32) | ((w1 & 255) << 24) | ((w1 >> 8) << 16) | ((w2 & 255) << 8) | (w2 >> 8)

    # Réinitialisation complète, anneaux, émission / réception activées, interruptions masquées.
    func setup():
        self.write(IMC, 0xFFFFFFFF)
        self.write(CTRL, self.read(CTRL) | CTRL_RST)
        de.io_delay(2000)
        if not de.wait_mmio32(self.regs + CTRL, CTRL_RST, 0, 1000000):
            de.timeout(self.label, "réinitialisation")
        self.write(IMC, 0xFFFFFFFF)
        self.read(ICR)
        self.write(CTRL, (self.read(CTRL) | CTRL_SLU | CTRL_ASDE) & ~0x80000000)
        self.address = self._read_mac()
        # adresse de réception 0 = notre MAC
        m := self.address
        self.write(RAL0, ((m >> 40) & 255) | (((m >> 32) & 255) << 8) | (((m >> 24) & 255) << 16) | (((m >> 16) & 255) << 24))
        self.write(RAH0, ((m >> 8) & 255) | ((m & 255) << 8) | 0x80000000)
        k := 0
        while k < 128:
            self.write(MTA + 4 * k, 0)
            k += 1
        # réception
        self.rx_ring = hw.alloc_pages(1)
        self.rx_bufs = hw.alloc_pages(RX_COUNT * 2048 // 4096)
        i := 0
        while i < RX_COUNT:
            d := self.rx_ring + 16 * i
            hw.poke64(d, self.rx_bufs + 2048 * i)
            hw.poke64(d + 8, 0)
            i += 1
        self.write(RDBAL, self.rx_ring)
        self.write(RDBAH, 0)
        self.write(RDLEN, RX_COUNT * 16)
        self.write(RDH, 0)
        self.write(RDT, RX_COUNT - 1)
        self.rx_next = 0
        self.write(RCTL, RCTL_EN | RCTL_BAM | RCTL_SECRC)
        # émission
        self.tx_ring = hw.alloc_pages(1)
        self.tx_bufs = hw.alloc_pages(TX_COUNT * 2048 // 4096)
        i = 0
        while i < TX_COUNT:
            d := self.tx_ring + 16 * i
            hw.poke64(d, self.tx_bufs + 2048 * i)
            hw.poke64(d + 8, 0)
            hw.poke8(d + 12, 1)          # DD : libre
            i += 1
        self.write(TDBAL, self.tx_ring)
        self.write(TDBAH, 0)
        self.write(TDLEN, TX_COUNT * 16)
        self.write(TDH, 0)
        self.write(TDT, 0)
        self.tx_next = 0
        self.write(TIPG, 0x0060200A)
        self.write(TCTL, TCTL_EN | TCTL_PSP | (0x10 << 4) | (0x40 << 12))

    func name() -> str:
        return self.label

    func mac() -> int:
        return self.address

    func mtu() -> int:
        return eth.MTU

    func link_up() -> bool:
        return self.read(STATUS) & 2 != 0

    func speed_mbps() -> int:
        s := (self.read(STATUS) >> 6) & 3
        if s == 0:
            return 10
        if s == 1:
            return 100
        return 1000

    func set_promiscuous(on: bool):
        self.promiscuous = on
        r := self.read(RCTL)
        if on:
            r = r | RCTL_UPE | RCTL_MPE
        else:
            r = r & ~(RCTL_UPE | RCTL_MPE)
        self.write(RCTL, r)

    # Copie la trame dans le tampon du prochain descripteur et l'émet ; faux si l'anneau est plein.
    func send(b: PacketBuffer) -> bool:
        if b.length > eth.MAX_FRAME:
            self.counters.tx_errors += 1
            return false
        d := self.tx_ring + 16 * self.tx_next
        if hw.peek8(d + 12) & 1 == 0:
            self.counters.tx_dropped += 1
            return false
        hw.copy(self.tx_bufs + 2048 * self.tx_next, b.data(), b.length)
        hw.poke64(d, self.tx_bufs + 2048 * self.tx_next)
        hw.poke16(d + 8, b.length)
        hw.poke8(d + 10, 0)
        hw.poke8(d + 11, 0x1 | 0x2 | 0x8)      # EOP | IFCS | RS
        hw.poke8(d + 12, 0)
        self.tx_next = (self.tx_next + 1) % TX_COUNT
        self.write(TDT, self.tx_next)
        self.counters.count_tx(b.length)
        return true

    # Attend que toutes les trames émises soient parties ; faux après tries tours.
    func flush_tx(tries: int) -> bool:
        i := 0
        while i < tries:
            if self.read(TDH) == self.read(TDT):
                return true
            hw.pause()
            i += 1
        return false

    func receive() -> PacketBuffer?:
        d := self.rx_ring + 16 * self.rx_next
        status := hw.peek8(d + 12)
        if status & 1 == 0:
            return null
        length := hw.peek16(d + 8)
        errors := hw.peek8(d + 13)
        out: PacketBuffer? := null
        if errors != 0 or status & 2 == 0:
            self.counters.rx_errors += 1
        else:
            b := self.pool.get()
            if b == null:
                self.counters.rx_dropped += 1
            else:
                b.reset_raw(0)
                b.copy_from(self.rx_bufs + 2048 * self.rx_next, length)
                dst := eth.dst_of(b.data())
                self.counters.count_rx(length, eth.is_broadcast(dst), eth.is_multicast(dst))
                out = b
        hw.poke8(d + 12, 0)
        old := self.rx_next
        self.rx_next = (self.rx_next + 1) % RX_COUNT
        self.write(RDT, old)
        return out

    func recycle(b: PacketBuffer):
        self.pool.put(b)

    func stats() -> NetworkStats:
        return self.counters

    # Compteurs du matériel (remis à zéro par leur lecture) : [erreurs CRC, manquées, reçues, émises].
    func hardware_counters() -> list[int]:
        return [self.read(CRCERRS), self.read(MPC), self.read(GPRC), self.read(GPTC)]

    # Interruptions : causes à signaler (masque IMS : 0x80 réception, 0x1 émission, 0x4 lien).
    func enable_interrupts(mask: int):
        self.write(IMS, mask)

    func interrupt_causes() -> int:
        self.counters.interrupts += 1
        return self.read(ICR)

    func describe() -> str:
        lien := "lien coupé"
        if self.link_up():
            lien = "lien à " + str(self.speed_mbps()) + " Mbit/s"
        return self.label + " " + eth.mac_text(self.address) + ", " + lien + " ; " + self.counters.describe()

# ---------------------------------------------------------------- pilote du cadre driver
class E1000Driver implements Driver:
    i: DriverInfo
    devices: list[E1000Device] := []

    func init():
        self.i = DriverInfo("e1000", "1.0", "Intel PRO/1000 (8254x, 82574)", "pci")
        for dev_id in [0x100E, 0x100F, 0x1004, 0x100C, 0x1015, 0x1019, 0x101E, 0x1026, 0x10D3, 0x10F5, 0x153A]:
            self.i.add_id(di.pci_id(0x8086, dev_id))
        self.devices = []

    func info() -> DriverInfo:
        return self.i

    func probe(dev: HwDevice) -> bool:
        return dev.mem_base(0) > 0

    func attach(dev: HwDevice):
        p := dev.pci
        if p != null:
            p.enable_memory()
            p.enable_bus_master()
        e := E1000Device(hw.mmio(dev.mem_base(0)), "eth" + str(len(self.devices)))
        e.setup()
        append(self.devices, e)

    func detach(dev: HwDevice):
        for e in self.devices:
            e.write(RCTL, 0)
            e.write(TCTL, 0)
        self.devices = []

    func status(dev: HwDevice) -> str:
        if len(self.devices) == 0:
            return "arrêté"
        return self.devices[0].describe()

# Première carte e1000 du bus PCI, prête (ou null).
func find_e1000() -> E1000Device?:
    m := dmg.DriverManager()
    d := E1000Driver()
    m.register(d)
    m.add_pci_bus(PciBus(cfg.PortConfig()))
    m.bind_all()
    if len(d.devices) == 0:
        return null
    return d.devices[0]

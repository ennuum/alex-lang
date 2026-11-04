# alex: native
# ALEX STANDARD LIBRARY — gpu_driver
#
# Pilotes graphiques d'un noyau Alex (--freestanding). Pilote fourni : carte Bochs / QEMU « stdvga »
# (PCI 1234:1111, aussi VirtualBox VBoxVGA en mode compatible) par l'interface DISPI (« BGA ») :
#   - détection (registre d'identification 0xB0C0..0xB0C5), mémoire vidéo (registre en blocs de 64 Kio) ;
#   - choix du mode (largeur, hauteur, 8 / 15 / 16 / 24 / 32 bits), tampon linéaire (BAR0) ;
#   - double tampon par décalage vertical (Y_OFFSET) : on dessine dans l'image cachée puis flip() ;
#   - registres par ports 0x1CE / 0x1CF, ou par MMIO (BAR2, décalage 0x500) quand la carte en a ;
#   - surfaces 2D (gpu_driver.gpu_command.Surface2D) sur l'image affichée / cachée, et gestion de la VRAM
#     restante (gpu_driver.gpu_memory_manager).
#
# | Module                             | Contenu                                                 |
# |------------------------------------|---------------------------------------------------------|
# | gpu_driver.gpu_capabilities        | GpuCapabilities, VideoMode                              |
# | gpu_driver.gpu_memory_manager      | GpuMemoryManager, VramBlock                             |
# | gpu_driver.gpu_command             | Surface2D, CommandBuffer, GpuEngine                     |
#
#   use gpu_driver
#   g := gpu_driver.find_bochs()                 # BochsGpu? (bus PCI)
#   g.set_mode(800, 600, 32, true)               # double tampon
#   s := g.back_surface()
#   s.clear(0x203040)
#   g.flip()
#
# Erreurs : UnsupportedDevice (mode impossible), DeviceNotFound. Compilable en natif (# alex: native).

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
from driver.driver_manager use DriverManager
use gpu_driver.gpu_capabilities as gc
from gpu_driver.gpu_capabilities use GpuCapabilities, VideoMode
use gpu_driver.gpu_memory_manager as gm
from gpu_driver.gpu_memory_manager use GpuMemoryManager
use gpu_driver.gpu_command as gcmd
from gpu_driver.gpu_command use Surface2D, CommandBuffer, GpuEngine

const DISPI_INDEX := 0x01CE
const DISPI_DATA := 0x01CF
const REG_ID := 0
const REG_XRES := 1
const REG_YRES := 2
const REG_BPP := 3
const REG_ENABLE := 4
const REG_BANK := 5
const REG_VIRT_WIDTH := 6
const REG_VIRT_HEIGHT := 7
const REG_X_OFFSET := 8
const REG_Y_OFFSET := 9
const REG_VIDEO_MEMORY_64K := 10
const ENABLED := 0x01
const GET_CAPS := 0x02
const LFB_ENABLED := 0x40
const NO_CLEAR := 0x80

class BochsGpu:
    lfb_phys: int := 0
    lfb: int := 0
    mmio: int := 0            # registres DISPI en MMIO (0 : ports)
    version: int := 0
    vram: int := 0
    width: int := 0
    height: int := 0
    bpp: int := 32
    double: bool := false
    shown: int := 0           # image affichée (0 / 1)
    memory: GpuMemoryManager
    engine: GpuEngine
    flips: int := 0

    # lfb_phys : adresse physique du tampon linéaire (BAR0) ; mmio_phys : BAR2 (0 : ports 0x1CE / 0x1CF).
    func init(lfb_phys: int, mmio_phys: int):
        self.lfb_phys = lfb_phys
        self.lfb = hw.mmio(lfb_phys)
        self.mmio = 0
        if mmio_phys != 0:
            self.mmio = hw.mmio(mmio_phys) + 0x500
        self.version = self.read(REG_ID)
        if self.version < 0xB0C0 or self.version > 0xB0CF:
            de.unsupported("bochs-vga", "identifiant DISPI " + str(self.version))
        self.vram = self.read(REG_VIDEO_MEMORY_64K) * 65536
        if self.vram == 0:
            self.vram = 16 * 1048576
        self.memory = GpuMemoryManager(self.vram, 0, 4096)
        self.engine = GpuEngine()
        self.flips = 0

    func read(reg: int) -> int:
        if self.mmio != 0:
            return hw.peek16(self.mmio + 2 * reg)
        hw.outw(DISPI_INDEX, reg)
        return hw.inw(DISPI_DATA)

    func write(reg: int, v: int):
        if self.mmio != 0:
            hw.poke16(self.mmio + 2 * reg, v)
            return
        hw.outw(DISPI_INDEX, reg)
        hw.outw(DISPI_DATA, v)

    func capabilities() -> GpuCapabilities:
        # résolution maximale : lue avec GET_CAPS (affichage coupé le temps de la lecture)
        old := self.read(REG_ENABLE)
        self.write(REG_ENABLE, old | GET_CAPS)
        mw := self.read(REG_XRES)
        mh := self.read(REG_YRES)
        self.write(REG_ENABLE, old)
        if mw == 0:
            mw = 2560
            mh = 1600
        c := GpuCapabilities("Bochs / QEMU VGA (DISPI " + str(self.version - 0xB0C0) + ")", self.vram, mw, mh)
        c.depths = [8, 15, 16, 24, 32]
        c.double_buffer = true
        c.version = self.version
        c.add_standard_modes()
        return c

    # Mode graphique ; double : deux images dans la VRAM (flip). UnsupportedDevice si impossible.
    func set_mode(width: int, height: int, bpp: int, double: bool):
        frames := 1
        if double:
            frames = 2
        if width * height * (bpp // 8) * frames > self.vram:
            de.unsupported("bochs-vga", "mode " + str(width) + "x" + str(height) + "x" + str(bpp) + " (mémoire vidéo)")
        self.write(REG_ENABLE, 0)
        self.write(REG_XRES, width)
        self.write(REG_YRES, height)
        self.write(REG_BPP, bpp)
        self.write(REG_VIRT_WIDTH, width)
        self.write(REG_VIRT_HEIGHT, height * frames)
        self.write(REG_X_OFFSET, 0)
        self.write(REG_Y_OFFSET, 0)
        self.write(REG_ENABLE, ENABLED | LFB_ENABLED)
        if self.read(REG_XRES) != width or self.read(REG_YRES) != height or self.read(REG_BPP) != bpp:
            de.unsupported("bochs-vga", "mode refusé par la carte")
        self.width = width
        self.height = height
        self.bpp = bpp
        self.double = double
        self.shown = 0
        self.memory.set_reserved(self.pitch() * height * frames)

    func disable():
        self.write(REG_ENABLE, 0)

    func enabled() -> bool:
        return self.read(REG_ENABLE) & ENABLED != 0

    func pitch() -> int:
        return self.width * (self.bpp // 8)

    func mode() -> VideoMode:
        return VideoMode(self.width, self.height, self.bpp)

    func _frame(i: int) -> Surface2D:
        return Surface2D(self.lfb + i * self.pitch() * self.height, self.width, self.height, self.pitch())

    # Image affichée.
    func front_surface() -> Surface2D:
        return self._frame(self.shown)

    # Image en préparation (la même que l'affichée sans double tampon).
    func back_surface() -> Surface2D:
        if self.double:
            return self._frame(1 - self.shown)
        return self._frame(self.shown)

    # Affiche l'image préparée (décalage vertical) ; renvoie l'image désormais cachée.
    func flip():
        if not self.double:
            return
        self.shown = 1 - self.shown
        self.write(REG_Y_OFFSET, self.shown * self.height)
        self.flips += 1

    func displayed_offset() -> int:
        return self.read(REG_Y_OFFSET)

    # Exécute un tampon de commandes sur l'image en préparation.
    func submit(cb: CommandBuffer) -> int:
        return self.engine.execute(cb, self.back_surface())

    # Surface hors écran (dans la VRAM restante), ou null si plus de place.
    func offscreen(width: int, height: int) -> Surface2D?:
        b := self.memory.allocate(width * height * 4, "surface")
        if b == null:
            return null
        return Surface2D(self.lfb + b.offset, width, height, width * 4)

    func describe() -> str:
        t := "Bochs VGA DISPI " + str(self.version - 0xB0C0) + ", " + str(self.vram // 1048576) + " Mio"
        if self.width > 0:
            t = t + ", mode " + self.mode().describe()
            if self.double:
                t = t + " (double tampon)"
        return t

# ---------------------------------------------------------------- pilote du cadre driver
class BochsGpuDriver implements Driver:
    i: DriverInfo
    gpus: list[BochsGpu] := []

    func init():
        self.i = DriverInfo("bochs-vga", "1.0", "carte Bochs / QEMU stdvga (DISPI)", "pci")
        self.i.add_id(di.pci_id(0x1234, 0x1111))
        self.i.add_id(di.pci_id(0x80EE, 0xBEEF))
        self.gpus = []

    func info() -> DriverInfo:
        return self.i

    func probe(dev: HwDevice) -> bool:
        return dev.mem_base(0) > 0

    func attach(dev: HwDevice):
        p := dev.pci
        mm := 0
        if p != null:
            p.enable_memory()
            p.enable_io()
            if dev.resource("mem", 1) != null:
                mm = dev.mem_base(1)
        append(self.gpus, BochsGpu(dev.mem_base(0), mm))

    func detach(dev: HwDevice):
        for g in self.gpus:
            g.disable()
        self.gpus = []

    func status(dev: HwDevice) -> str:
        if len(self.gpus) == 0:
            return "arrêté"
        return self.gpus[0].describe()

func find_bochs() -> BochsGpu?:
    m := DriverManager()
    d := BochsGpuDriver()
    m.register(d)
    m.add_pci_bus(PciBus(cfg.PortConfig()))
    m.bind_all()
    if len(d.gpus) == 0:
        return null
    return d.gpus[0]

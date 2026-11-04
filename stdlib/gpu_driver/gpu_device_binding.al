# alex: native
# ALEX STANDARD LIBRARY — gpu_driver.gpu_device_binding
#
# Liaison des cartes graphiques à leurs pilotes, avec ce qui est propre à l'affichage :
#   - classification PCI (classe 03) : VGA compatible (03:00, interface 00), contrôleur XGA, 3D (03:02),
#     autre ; carte d'amorçage (« boot VGA ») = celle dont un BAR contient le tampon d'image laissé par le
#     micrologiciel (GOP / VESA, adresse transmise par le chargeur) ou, à défaut, la première VGA compatible
#     dont le décodage mémoire est actif ;
#   - reprise (handover) du tampon d'image du micrologiciel : enregistrée une seule fois, par le pilote de la
#     carte qui le contient ; l'affichage provisoire (framebuffer simple) est alors abandonné ;
#   - conflits : deux cartes dont les BAR mémoire se recouvrent, ou une carte liée deux fois ;
#   - GpuBindingTable : candidats, liaisons (pilote, tampon linéaire, VRAM), carte principale, rapport.
#
#   use gpu_driver.gpu_device_binding as gb
#   t := gb.GpuBindingTable()
#   t.scan(gestionnaire.devices)                # HwDevice de classe 03
#   t.set_boot_framebuffer(0xFD000000, 1024 * 768 * 4)
#   p := t.primary()                            # HwDevice ou null
#   t.bind(p, "bochs-vga", p.mem_base(0), 16 * 1024 * 1024)
#   print(t.report())
#
# Erreurs : BindingError (carte déjà liée, carte hors table, reprise déjà faite). Compilable en natif.

from core use len
from collections use append
use driver.driver_info as di
from driver.driver_info use HwDevice

const KIND_VGA := 1
const KIND_XGA := 2
const KIND_3D := 3
const KIND_OTHER := 4

func kind_of(dev: HwDevice) -> int:
    if dev.cls != 0x03:
        return 0
    if dev.subclass == 0x00:
        return KIND_VGA
    if dev.subclass == 0x01:
        return KIND_XGA
    if dev.subclass == 0x02:
        return KIND_3D
    return KIND_OTHER

func kind_name(k: int) -> str:
    if k == KIND_VGA:
        return "VGA"
    if k == KIND_XGA:
        return "XGA"
    if k == KIND_3D:
        return "3D"
    if k == KIND_OTHER:
        return "affichage"
    return "non graphique"

class GpuBinding:
    device: HwDevice
    driver: str := ""
    lfb: int := 0
    vram: int := 0
    handover: bool := false

    func init(device: HwDevice, driver: str, lfb: int, vram: int):
        self.device = device
        self.driver = driver
        self.lfb = lfb
        self.vram = vram
        self.handover = false

    func describe() -> str:
        t := self.device.location + " -> " + self.driver + ", tampon " + str(self.lfb) + ", VRAM " + str(self.vram // 1048576) + " Mio"
        if self.handover:
            t = t + " (reprise du tampon du micrologiciel)"
        return t

class GpuBindingTable:
    candidates: list[HwDevice] := []
    bindings: list[GpuBinding] := []
    boot_fb: int := 0
    boot_fb_size: int := 0
    handed_over: bool := false
    log: list[str] := []

    func init():
        self.candidates = []
        self.bindings = []
        self.boot_fb = 0
        self.boot_fb_size = 0
        self.handed_over = false
        self.log = []

    func add(dev: HwDevice) -> bool:
        if kind_of(dev) == 0:
            return false
        for c in self.candidates:
            if c.location == dev.location:
                return false
        append(self.candidates, dev)
        return true

    # Retient les cartes graphiques de la liste ; renvoie leur nombre.
    func scan(devices: list[HwDevice]) -> int:
        n := 0
        for d in devices:
            if self.add(d):
                n += 1
        return n

    func set_boot_framebuffer(addr: int, size: int):
        self.boot_fb = addr
        self.boot_fb_size = size

    # Carte dont un BAR mémoire contient le tampon d'image du micrologiciel, ou null.
    func owner_of_boot_fb() -> HwDevice?:
        if self.boot_fb == 0:
            return null
        for c in self.candidates:
            for r in c.resources:
                if r.kind == "mem" and self.boot_fb >= r.start and self.boot_fb + self.boot_fb_size <= r.start + r.size:
                    return c
        return null

    func primary() -> HwDevice?:
        o := self.owner_of_boot_fb()
        if o != null:
            return o
        for c in self.candidates:
            if kind_of(c) == KIND_VGA:
                return c
        if len(self.candidates) > 0:
            return self.candidates[0]
        return null

    func binding(dev: HwDevice) -> GpuBinding?:
        for b in self.bindings:
            if b.device.location == dev.location:
                return b
        return null

    func bind(dev: HwDevice, driver: str, lfb: int, vram: int) -> GpuBinding:
        known := false
        for c in self.candidates:
            if c.location == dev.location:
                known = true
        if not known:
            raise("BindingError", dev.location + " : pas une carte graphique de la table")
        if self.binding(dev) != null:
            raise("BindingError", dev.location + " : carte déjà liée")
        b := GpuBinding(dev, driver, lfb, vram)
        o := self.owner_of_boot_fb()
        if o != null:
            if o.location == dev.location and not self.handed_over:
                b.handover = true
                self.handed_over = true
                append(self.log, "reprise du tampon d'image " + str(self.boot_fb) + " par " + driver)
        append(self.bindings, b)
        append(self.log, "liée " + b.describe())
        return b

    func unbind(dev: HwDevice) -> bool:
        keep: list[GpuBinding] := []
        found := false
        for b in self.bindings:
            if b.device.location == dev.location:
                found = true
                if b.handover:
                    self.handed_over = false
                    append(self.log, "tampon d'image rendu à l'affichage provisoire")
            else:
                append(keep, b)
        self.bindings = keep
        return found

    # Descriptions des conflits de ressources (vide : aucun).
    func conflicts() -> list[str]:
        out: list[str] := []
        i := 0
        while i < len(self.candidates):
            a := self.candidates[i]
            j := i + 1
            while j < len(self.candidates):
                b := self.candidates[j]
                for ra in a.resources:
                    for rb in b.resources:
                        if ra.kind == "mem" and rb.kind == "mem" and ra.size > 0 and rb.size > 0:
                            if ra.start < rb.start + rb.size and rb.start < ra.start + ra.size:
                                append(out, a.location + " et " + b.location + " : mémoire " + str(ra.start) + " / " + str(rb.start) + " se recouvrent")
                j += 1
            i += 1
        return out

    func report() -> str:
        t := "cartes graphiques : " + str(len(self.candidates)) + ", liées : " + str(len(self.bindings))
        p := self.primary()
        for c in self.candidates:
            t = t + "\n  " + c.location + " " + kind_name(kind_of(c))
            if p != null:
                pp := p
                if pp != null:
                    if pp.location == c.location:
                        t = t + " (principale)"
            b := self.binding(c)
            if b != null:
                bb := b
                if bb != null:
                    t = t + " : " + bb.driver
        return t

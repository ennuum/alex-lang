# ALEX STANDARD LIBRARY — hardware.gpu
#
# Cartes graphiques : contrôleurs d'affichage du bus PCI (classe 0x03) et cartes DRM du noyau
# (Linux : /sys/bus/pci/devices, /sys/class/drm). Pour chacune : fabricant, identifiants, pilote, carte DRM
# et nœud de rendu (/dev/dri/renderD*), mémoire vidéo quand le pilote la publie (amdgpu).
#
# Exemple
#   use hardware.gpu as gpu
#   for g in gpu.gpus():
#       print(g.vendor, g.device_id_hex(), g.driver, g.card)

from core use len, type
from collections use append, contains_key
use string as _s
use hardware._sys as _sys

_VENDORS := {4318: "NVIDIA", 4098: "AMD", 32902: "Intel", 6900: "Red Hat (virtio)", 4660: "QEMU", 5549: "VMware", 33006: "VirtualBox", 4139: "Matrox", 6659: "ASPEED", 5140: "Microsoft (Hyper-V)", 4203: "Apple", 20803: "Qualcomm", 5348: "Broadcom"}

# Nom du fabricant d'après son identifiant PCI, ou null.
func vendor_name(vendor_id):
    if contains_key(_VENDORS, vendor_id):
        return _VENDORS[vendor_id]
    return null

_KINDS := {0: "vga", 1: "xga", 2: "3d", 128: "display"}

class Gpu:
    func init():
        self.slot = null          # adresse PCI (« 0000:01:00.0 »), null hors PCI
        self.vendor_id = null
        self.device_id = null
        self.vendor = null        # « NVIDIA », « AMD », « Intel »...
        self.kind = null          # « vga », « 3d », « display »
        self.driver = null        # pilote du noyau (« amdgpu », « i915 », « nouveau », « virtio-pci »...)
        self.card = null          # carte DRM (« card0 »)
        self.render_node = null   # « /dev/dri/renderD128 »
        self.boot_vga = false     # carte utilisée au démarrage
        self.vram = null          # octets (si le pilote le publie)

    func vendor_id_hex():
        return _sys.hex4(self.vendor_id)

    func device_id_hex():
        return _sys.hex4(self.device_id)

func _drm_links(gpu, base):
    for name in _sys.list(base + "/drm"):
        if _s.starts_with(name, "card"):
            gpu.card = name
        elif _s.starts_with(name, "renderD"):
            gpu.render_node = "/dev/dri/" + name
    vram := _sys.dec(_sys.read(base + "/mem_info_vram_total"))
    if vram != null:
        gpu.vram = vram

# Cartes graphiques présentes (list de Gpu) ; [] hors Linux.
func gpus():
    out := []
    seen_cards := []
    for slot in _sys.list("/sys/bus/pci/devices"):
        base := "/sys/bus/pci/devices/" + slot
        cls := _sys.hex(_sys.read(base + "/class"))
        if cls == null or cls >> 16 != 3:
            continue
        g := Gpu()
        g.slot = slot
        g.vendor_id = _sys.hex(_sys.read(base + "/vendor"))
        g.device_id = _sys.hex(_sys.read(base + "/device"))
        g.vendor = vendor_name(g.vendor_id)
        sub := (cls >> 8) & 255
        if contains_key(_KINDS, sub):
            g.kind = _KINDS[sub]
        g.driver = _sys.link_name(base + "/driver")
        g.boot_vga = _sys.read(base + "/boot_vga") == "1"
        _drm_links(g, base)
        if g.card != null:
            append(seen_cards, g.card)
        append(out, g)
    # Cartes DRM hors PCI (processeurs graphiques intégrés des machines ARM...).
    for name in _sys.list("/sys/class/drm"):
        if not _s.starts_with(name, "card") or _s.contains(name, "-"):
            continue
        known := false
        for c in seen_cards:
            if c == name:
                known = true
        if known:
            continue
        g := Gpu()
        g.card = name
        g.driver = _sys.link_name("/sys/class/drm/" + name + "/device/driver")
        uevent := _sys.read("/sys/class/drm/" + name + "/device/uevent")
        if g.driver == null and uevent != null:
            for line in _s.split(uevent, "\n"):
                if _s.starts_with(line, "DRIVER="):
                    g.driver = _s.slice(line, 7)
        for r in _sys.list("/sys/class/drm/" + name + "/device/drm"):
            if _s.starts_with(r, "renderD"):
                g.render_node = "/dev/dri/" + r
        append(out, g)
    return out

func available():
    return len(gpus()) > 0

# Carte principale : celle du démarrage, sinon la première ; null s'il n'y en a pas.
func primary():
    all := gpus()
    for g in all:
        if g.boot_vga:
            return g
    if len(all) > 0:
        return all[0]
    return null

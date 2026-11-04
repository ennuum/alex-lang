# ALEX STANDARD LIBRARY — hardware.device_resource
#
# Ressources d'un périphérique telles que Linux les publie (lecture seule, sans privilège sauf mention) :
#   - fenêtres PCI du fichier /sys/.../resource (BAR 0 à 5, ROM d'extension, fenêtres de pont) : début, fin,
#     drapeaux (E/S, mémoire, préchargeable, 64 bits, lecture seule), taille ;
#   - interruption (irq), vecteurs MSI / MSI-X (dossier msi_irqs), nœud NUMA, processeurs proches
#     (local_cpulist), masque DMA (dma_mask_bits) ;
#   - qui revendique une zone : arbres /proc/iomem et /proc/ioports (adresses lisibles par root seulement :
#     sinon elles valent 0 et claims() le signale) ;
#   - conflicts : recouvrements entre les ressources de plusieurs périphériques.
#
#   use hardware.device as hd
#   use hardware.device_resource as dr
#   d := hd.from_path("/sys/bus/pci/devices/0000:00:02.0")
#   rs := dr.of_device(d)                 # ResourceSet
#   for r in rs.resources: print(r.describe())     # « BAR0 mem 0xfd000000-0xfdffffff (16 Mio) préchargeable »
#   print(rs.irq, rs.msi, rs.numa_node, dr.claims(rs))
#
# Erreurs : HardwareUnavailable (périphérique sans ressources lisibles).

from core use len, type
from collections use append, contains_key
use string as _s
use os as _os
use hardware._sys as _sys
use hardware.memory_map as _mm

const IORESOURCE_IO := 0x100
const IORESOURCE_MEM := 0x200
const IORESOURCE_PREFETCH := 0x2000
const IORESOURCE_READONLY := 0x4000
const IORESOURCE_MEM_64 := 0x100000

func _hex(v):
    digits := "0123456789abcdef"
    if v == 0:
        return "0x0"
    out := ""
    n := v
    while n > 0:
        out = str(digits[n % 16]) + out
        n = n // 16
    return "0x" + out

func _human(n):
    if n >= 1073741824 and n % 1073741824 == 0:
        return str(n // 1073741824) + " Gio"
    if n >= 1048576 and n % 1048576 == 0:
        return str(n // 1048576) + " Mio"
    if n >= 1024 and n % 1024 == 0:
        return str(n // 1024) + " Kio"
    return str(n) + " o"

class DeviceResource:
    # start, end inclus (comme sysfs) ; index : numéro de ligne du fichier resource.
    func init(kind, start, end, flags, index, name):
        self.kind = kind            # « io », « mem », « irq »
        self.start = start
        self.end = end
        self.flags = flags
        self.index = index
        self.name = name

    func size():
        if self.kind == "irq":
            return 1
        return self.end - self.start + 1

    func prefetchable():
        return self.flags & IORESOURCE_PREFETCH != 0

    func is64():
        return self.flags & IORESOURCE_MEM_64 != 0

    func read_only():
        return self.flags & IORESOURCE_READONLY != 0

    func overlaps(o):
        if self.kind != o.kind:
            return false
        return self.start <= o.end and o.start <= self.end

    func describe():
        if self.kind == "irq":
            return self.name + " irq " + str(self.start)
        t := self.name + " " + self.kind + " " + _hex(self.start) + "-" + _hex(self.end) + " (" + _human(self.size()) + ")"
        if self.prefetchable():
            t += " préchargeable"
        if self.is64():
            t += " 64 bits"
        if self.read_only():
            t += " lecture seule"
        return t

    func to_dict():
        return {"kind": self.kind, "start": self.start, "end": self.end, "size": self.size(), "name": self.name,
                "prefetchable": self.prefetchable(), "is64": self.is64()}

func _line_name(i):
    if i < 6:
        return "BAR" + str(i)
    if i == 6:
        return "ROM"
    return "fenêtre" + str(i - 7)

# Analyse le contenu d'un fichier resource de sysfs (lignes « début fin drapeaux » en hexadécimal).
func parse_resource_file(text):
    out := []
    if text == null:
        return out
    i := 0
    for line in _s.split(text, "\n"):
        w := _sys.split_words(_s.trim(line))
        if len(w) >= 3:
            s := _sys.hex(w[0])
            e := _sys.hex(w[1])
            f := _sys.hex(w[2])
            if f != 0 and not (s == 0 and e == 0):
                kind := "io" if f & IORESOURCE_IO != 0 else "mem"
                append(out, DeviceResource(kind, s, e, f, i, _line_name(i)))
            i += 1
    return out

class ResourceSet:
    func init(device_name):
        self.device = device_name
        self.resources = []
        self.irq = null
        self.msi = []
        self.numa_node = null
        self.local_cpus = null
        self.dma_bits = null

    func mem():
        return [r for r in self.resources if r.kind == "mem"]

    func io():
        return [r for r in self.resources if r.kind == "io"]

    func total_mem():
        t := 0
        for r in self.mem():
            t += r.size()
        return t

    func describe():
        t := self.device + " :"
        for r in self.resources:
            t += "\n  " + r.describe()
        if self.irq != null:
            t += "\n  irq " + str(self.irq)
        if len(self.msi) > 0:
            t += "\n  MSI " + _s.join(", ", [str(v) for v in self.msi])
        if self.numa_node != null and self.numa_node >= 0:
            t += "\n  nœud NUMA " + str(self.numa_node)
        if self.local_cpus != null:
            t += "\n  processeurs proches " + self.local_cpus
        if self.dma_bits != null:
            t += "\n  DMA " + str(self.dma_bits) + " bits"
        return t

# Ressources d'un hardware.device.Device (ou d'un chemin /sys).
func of_device(dev):
    path := dev if type(dev) == "str" else dev.syspath
    name := _os.basename(path)
    rs := ResourceSet(name)
    rs.resources = parse_resource_file(_sys.read(path + "/resource"))
    irq := _sys.dec(_sys.read(path + "/irq"))
    if irq != null and irq > 0:
        rs.irq = irq
    for n in _sys.list(path + "/msi_irqs"):
        v := _sys.dec(n)
        if v != null:
            append(rs.msi, v)
    rs.numa_node = _sys.dec(_sys.read(path + "/numa_node"))
    rs.local_cpus = _sys.read(path + "/local_cpulist")
    rs.dma_bits = _sys.dec(_sys.read(path + "/dma_mask_bits"))
    return rs

func _flatten(regions, out, parent):
    for r in regions:
        append(out, [r, parent])
        _flatten(r.children, out, r.name)

# Qui revendique chaque ressource : list de dict resource, claimed_by (noms de /proc/iomem ou /proc/ioports
# couvrant la zone, du plus large au plus précis). readable : faux si les adresses sont masquées (non root).
func claims(rs, iomem_text=null, ioports_text=null):
    mem_text := iomem_text if iomem_text != null else _sys.read("/proc/iomem")
    io_text := ioports_text if ioports_text != null else _sys.read("/proc/ioports")
    trees := {"mem": _mm.parse_iomem(mem_text), "io": _mm.parse_iomem(io_text)}
    out := []
    for r in rs.resources:
        flat := []
        _flatten(trees[r.kind], flat, null)
        names := []
        readable := false
        for pair in flat:
            reg := pair[0]
            if reg.start != 0 or reg.end != 1:
                readable = true
            if reg.start <= r.start and reg.end - 1 >= r.end:
                append(names, reg.name)
        append(out, {"resource": r.describe(), "claimed_by": names, "readable": readable})
    return out

# Recouvrements entre ressources de plusieurs ResourceSet : list de textes.
func conflicts(sets):
    out := []
    i := 0
    while i < len(sets):
        j := i + 1
        while j < len(sets):
            for a in sets[i].resources:
                for b in sets[j].resources:
                    if a.overlaps(b):
                        append(out, sets[i].device + " " + a.name + " et " + sets[j].device + " " + b.name + " se recouvrent (" + a.kind + " " + _hex(a.start) + ")")
            j += 1
        i += 1
    return out

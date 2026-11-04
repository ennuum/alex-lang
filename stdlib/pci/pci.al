# ALEX STANDARD LIBRARY — pci
#
# Bus PCI / PCI Express : énumérer les périphériques, lire leurs identifiants, classes, registres de base (BAR),
# capacités, et (avec les droits, ou dans un noyau) régler leur registre de commande.
#
# Trois façons d'atteindre l'espace de configuration (pci.pci_config.ConfigAccess) :
#   - SysfsConfig (ici) : sous Linux, les fichiers /sys/bus/pci/devices/*/config — sans privilège pour les 64
#     premiers octets (tout l'en-tête utile), en entier (256 / 4096 octets) pour root ;
#   - PortConfig : ports 0xCF8 / 0xCFC, dans un noyau Alex (--freestanding) ou dans la machine simulée (VM) ;
#   - EcamConfig : MMIO PCI Express (table ACPI MCFG), dans un noyau.
# Les mêmes PciDevice / PciBus servent dans les trois cas.
#
#   use pci
#   for d in pci.devices():                    # système hôte (Linux)
#       print(d.describe())                    # 00:02.0 Contrôleur VGA [0300]: Intel ... [8086:3e9b] (rev 02)
#   print(pci.lspci())                         # tout, comme la commande lspci
#   gpu := pci.find_class(0x03, 0x00)
#
# Dans un noyau (sous-ensemble natif) : utiliser directement pci.pci_bus.PciBus(pci.pci_config.PortConfig()) —
# ce module-ci lit /sys et n'est pas compilable avec --freestanding.
#
# Erreurs : HardwareError (hors Linux pour devices / lspci), IoError.

from core use len, type
from collections use append, contains_key, keys, sort
use string as _s
use io as _io
use os as _os
use hardware._sys as _sys
use pci.pci_config as cfg
from pci.pci_config use ConfigAccess
use pci.pci_device as pd
use pci.pci_bus as pbus
use pci.pci_ids as ids
use _native_net as _b

# ---- accès par /sys (Linux) ----
class SysfsConfig implements ConfigAccess:
    func init():
        self._cache = {}       # chemin -> octets lus (str)
        self._index = {}       # (bus, emplacement, fonction) -> dossier sysfs
        for name in _sys.list("/sys/bus/pci/devices"):
            # « 0000:00:1f.2 »
            parts := _s.split(name, ":")
            if len(parts) != 3:
                continue
            sf := _s.split(parts[2], ".")
            key := str(_sys.hex(parts[1])) + ":" + str(_sys.hex(sf[0])) + "." + sf[1]
            self._index[key] = "/sys/bus/pci/devices/" + name

    func _path(bus, dev, fn):
        k := str(bus) + ":" + str(dev) + "." + str(fn)
        if contains_key(self._index, k):
            return self._index[k]
        return null

    func _bytes(path):
        if not contains_key(self._cache, path):
            data := ""
            try:
                data = _b.from_bytes(_io.read_bytes(_sys.p(path + "/config")))
            catch e:
                data = ""
            self._cache[path] = data
        return self._cache[path]

    func read32(bus, dev, fn, offset):
        p := self._path(bus, dev, fn)
        if p == null:
            return 0xFFFFFFFF
        data := self._bytes(p)
        if offset + 4 > _b.blen(data):
            return 0     # au-delà de ce que le noyau laisse lire sans privilège
        b := _b.to_bytes(_b.bslice(data, offset, offset + 4))
        return b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)

    # Écriture : root seulement (sinon IoError) ; le cache est oublié.
    func write32(bus, dev, fn, offset, value):
        p := self._path(bus, dev, fn)
        if p == null:
            return
        data := [value & 255, (value >> 8) & 255, (value >> 16) & 255, (value >> 24) & 255]
        _io.write_bytes_at(_sys.p(p + "/config"), data, offset)
        if contains_key(self._cache, p):
            self._cache = {k: self._cache[k] for k in keys(self._cache) if k != p}

    # Vrai si au moins une fonction est visible.
    func available():
        return len(keys(self._index)) > 0

func supported():
    return _sys.is_linux() and _sys.exists("/sys/bus/pci/devices")

_bus := [null]

func _host_bus():
    if _bus[0] == null:
        if not supported():
            raise("HardwareError", "pci : /sys/bus/pci absent (Linux requis ; dans un noyau, utiliser pci.pci_bus)")
        _bus[0] = pbus.PciBus(SysfsConfig())
    return _bus[0]

# Relit le bus (après un branchement à chaud, ou set_root de hardware._sys).
func refresh():
    _bus[0] = null

# Fonctions PCI du système hôte (pci.pci_device.PciDevice), dans l'ordre des adresses.
func devices():
    return _host_bus().scan()

func find(vendor, device):
    return _host_bus().find(vendor, device)

func find_class(cls, subclass, prog_if=-1):
    return _host_bus().find_class(cls, subclass, prog_if)

# Pilote Linux d'une fonction (« e1000 », « nvme »...), ou null.
func driver_of(d):
    for name in _sys.list("/sys/bus/pci/devices"):
        parts := _s.split(name, ":")
        if len(parts) == 3 and _sys.hex(parts[1]) == d.bus:
            sf := _s.split(parts[2], ".")
            if _sys.hex(sf[0]) == d.slot and _sys.dec(sf[1]) == d.fn:
                return _sys.link_name("/sys/bus/pci/devices/" + name + "/driver")
    return null

# Texte façon lspci (une ligne par fonction ; verbose : BAR et capacités).
func lspci(verbose=false):
    lines := []
    for d in devices():
        append(lines, d.describe())
        if verbose:
            drv := driver_of(d)
            if drv != null:
                append(lines, "    Pilote : " + drv)
            if d.irq_pin != 0:
                append(lines, "    Interruption : broche " + str(_s.chr(64 + d.irq_pin)) + ", ligne " + str(d.irq_line))
            for c in d.capabilities():
                append(lines, "    Capacité [" + ids.hex8(c.offset) + "] " + c.name())
    return _s.join("\n", lines)

func vendor_name(v):
    return ids.vendor_name(v)

func class_name(cls, subclass, prog_if=0):
    return ids.class_name(cls, subclass, prog_if)

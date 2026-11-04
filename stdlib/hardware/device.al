# ALEX STANDARD LIBRARY — hardware.device
#
# Un périphérique tel que le noyau Linux le publie dans /sys : chemin, sous-système (pci, usb, block, net,
# input, sound, drm...), pilote, nœud /dev, attributs, identifiants, parent et enfants dans l'arbre des
# périphériques.
#
#   use hardware.device as device
#   for d in device.by_subsystem("net"):
#       print(d.name, d.driver, d.attribute("address"))        # eth0 virtio_net 52:54:00:12:34:56
#   d := device.from_class("block", "sda")
#   print(d.devnode, d.major_minor(), d.parent().subsystem)   # /dev/sda (8, 0) scsi
#
# Lecture seule, sans droits particuliers. ALEX_HW_ROOT (ou hardware._sys.set_root) fait lire une copie de /sys.
# Hors Linux, les listes sont vides.
#
# Erreurs : ArgumentError (périphérique absent pour from_path / from_class).

from core use len, type
from collections use append, contains_key, keys
use string as _s
use os as _os
use hardware._sys as _sys

class Device:
    # syspath : chemin sous /sys (« /sys/devices/pci0000:00/0000:00:02.0 » ou un lien de /sys/class/...).
    func init(syspath):
        self.syspath = syspath
        self.name = _os.basename(syspath)
        self.subsystem = _sys.link_name(syspath + "/subsystem")
        self.driver = _sys.link_name(syspath + "/driver")
        self.uevent = _parse_uevent(_sys.read(syspath + "/uevent"))
        self.devnode = null
        if contains_key(self.uevent, "DEVNAME"):
            self.devnode = "/dev/" + self.uevent["DEVNAME"]
        self.devtype = null
        if contains_key(self.uevent, "DEVTYPE"):
            self.devtype = self.uevent["DEVTYPE"]
        self.modalias = _sys.read(syspath + "/modalias")
        if self.modalias == null and contains_key(self.uevent, "MODALIAS"):
            self.modalias = self.uevent["MODALIAS"]

    # Attribut texte (fichier du dossier du périphérique), ou null.
    func attribute(attr):
        return _sys.read(self.syspath + "/" + attr)

    func attribute_int(attr):
        v := self.attribute(attr)
        if v == null:
            return null
        if _s.starts_with(v, "0x"):
            return _sys.hex(v)
        return _sys.dec(v)

    func attributes():
        out := []
        for n in _sys.list(self.syspath):
            full := _sys.p(self.syspath + "/" + n)
            if _os.isfile(full) and n != "uevent":
                append(out, n)
        return out

    # (majeur, mineur) du nœud /dev, ou null.
    func major_minor():
        if contains_key(self.uevent, "MAJOR") and contains_key(self.uevent, "MINOR"):
            return (_sys.dec(self.uevent["MAJOR"]), _sys.dec(self.uevent["MINOR"]))
        dev := self.attribute("dev")
        if dev != null and _s.contains(dev, ":"):
            parts := _s.split(dev, ":")
            return (_sys.dec(parts[0]), _sys.dec(parts[1]))
        return null

    # Identifiants vendeur / produit (PCI : vendor/device ; USB : idVendor/idProduct), ou null.
    func vendor_id():
        v := self.attribute_int("vendor")
        if v == null:
            v = _sys.hex(self.attribute("idVendor"))
        return v

    func product_id():
        v := self.attribute_int("device")
        if v == null:
            v = _sys.hex(self.attribute("idProduct"))
        return v

    # Chemin réel dans /sys/devices (suit les liens de /sys/class et /sys/bus).
    func real_path():
        t := _sys.link_name(self.syspath)
        if t == null:
            return self.syspath
        full := _resolve(self.syspath)
        return full

    func parent():
        rp := self.real_path()
        d := _os.dirname(rp)
        while d != "" and d != "/sys/devices" and d != "/sys" and d != "/":
            if _sys.exists(d + "/uevent"):
                return Device(d)
            d = _os.dirname(d)
        return null

    # Périphériques enfants (sous-dossiers ayant un uevent).
    func children():
        out := []
        rp := self.real_path()
        for n in _sys.list(rp):
            p := rp + "/" + n
            if n != "subsystem" and n != "driver" and n != "firmware_node" and n != "device" and _sys.exists(p + "/uevent") and _sys.link_name(p) == null:
                append(out, Device(p))
        return out

    func describe():
        t := self.name
        if self.subsystem != null:
            t = self.subsystem + ":" + t
        if self.driver != null:
            t = t + " [" + self.driver + "]"
        if self.devnode != null:
            t = t + " " + self.devnode
        return t

    func to_dict():
        return {"name": self.name, "syspath": self.syspath, "subsystem": self.subsystem, "driver": self.driver,
                "devnode": self.devnode, "devtype": self.devtype, "modalias": self.modalias}

func _parse_uevent(text):
    out := {}
    if text == null:
        return out
    for line in _s.split(text, "\n"):
        k := _s.find(line, "=")
        if k > 0:
            out[_s.substring(line, 0, k)] = _s.substring(line, k + 1, len(line))
    return out

# Chemin réel d'un lien de /sys (résolu par le système de fichiers, relatif à la racine de lecture).
func _resolve(path):
    full := _sys.p(path)
    r := _os.realpath(full)
    root := _sys.root()
    if root != "" and _s.starts_with(r, _os.realpath(root)):
        return _s.substring(r, len(_os.realpath(root)), len(r))
    return r

func from_path(syspath):
    if not _sys.exists(syspath):
        raise("ArgumentError", "hardware.device : '" + syspath + "' absent")
    return Device(syspath)

# Périphérique de /sys/class/<classe>/<nom>.
func from_class(cls, name):
    return from_path("/sys/class/" + cls + "/" + name)

# Tous les périphériques d'une classe (/sys/class/<s>) ou d'un bus (/sys/bus/<s>/devices).
func by_subsystem(subsystem):
    out := []
    base := "/sys/class/" + subsystem
    if not _sys.exists(base):
        base = "/sys/bus/" + subsystem + "/devices"
    for n in _sys.list(base):
        append(out, Device(base + "/" + n))
    return out

func classes():
    return _sys.list("/sys/class")

func buses():
    return _sys.list("/sys/bus")

# Périphérique qui possède le nœud /dev donné (« /dev/sda », « /dev/input/event3 »), ou null.
func from_devnode(node):
    for cls in classes():
        for n in _sys.list("/sys/class/" + cls):
            ue := _parse_uevent(_sys.read("/sys/class/" + cls + "/" + n + "/uevent"))
            if contains_key(ue, "DEVNAME") and "/dev/" + ue["DEVNAME"] == node:
                return Device("/sys/class/" + cls + "/" + n)
    return null

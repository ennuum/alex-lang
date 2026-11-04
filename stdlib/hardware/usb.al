# ALEX STANDARD LIBRARY — hardware.usb
#
# Périphériques USB branchés (Linux : /sys/bus/usb/devices) : identifiants fabricant / produit, noms, numéro
# de série, bus et adresse, vitesse, classe (clavier, stockage, audio, caméra...) et nœud /dev/bus/usb.
#
# Exemple
#   use hardware.usb as usb
#   for d in usb.devices():
#       print(d.id(), d.product, d.classes, d.speed_mbps)
#   cle := usb.find("0781")              # premier périphérique SanDisk, ou null

from core use len, type, to_int, to_float
from collections use append, contains_key
use string as _s
use hardware._sys as _sys

_CLASSES := {1: "audio", 2: "communication", 3: "hid", 5: "physical", 6: "image", 7: "printer", 8: "mass_storage", 9: "hub", 10: "cdc_data", 11: "smart_card", 13: "content_security", 14: "video", 15: "healthcare", 16: "audio_video", 17: "billboard", 18: "type_c_bridge", 220: "diagnostic", 224: "wireless", 239: "misc", 254: "application", 255: "vendor"}

# Nom d'une classe USB (« hid », « mass_storage »...), ou null.
func class_name(code):
    if contains_key(_CLASSES, code):
        return _CLASSES[code]
    return null

class UsbDevice:
    func init(sysname):
        self.sysname = sysname        # « 1-1.2 » (position sur l'arbre des concentrateurs), « usb1 » (racine)
        self.vendor_id = null
        self.product_id = null
        self.manufacturer = null
        self.product = null
        self.serial = null
        self.bus = null
        self.address = null
        self.speed_mbps = null        # 1.5, 12, 480, 5000...
        self.usb_version = null       # « 2.00 »
        self.device_class = null      # classe déclarée par le périphérique (souvent 0 : voir classes)
        self.classes = []             # classes de ses interfaces (« hid », « audio », « video »...)
        self.max_power_ma = null
        self.driver = null

    # « 046d:c52b »
    func id():
        return _sys.hex4(self.vendor_id) + ":" + _sys.hex4(self.product_id)

    func is_hub():
        return self.device_class == 9

    # Nœud du périphérique (accès direct, libusb) : /dev/bus/usb/BBB/AAA.
    func node():
        if self.bus == null or self.address == null:
            return null
        return "/dev/bus/usb/" + _pad3(self.bus) + "/" + _pad3(self.address)

    func name():
        if self.product != null:
            if self.manufacturer != null:
                return self.manufacturer + " " + self.product
            return self.product
        return self.id()

func _pad3(n):
    t := str(n)
    while len(t) < 3:
        t = "0" + t
    return t

func _speed(text):
    if text == null:
        return null
    try:
        v := to_float(text)
        if v == to_int(v):
            return to_int(v)
        return v
    catch e:
        return null

# Périphériques présents (list de UsbDevice), concentrateurs racines compris sauf hubs=false.
func devices(hubs=true):
    out := []
    entries := _sys.list("/sys/bus/usb/devices")
    for name in entries:
        if _s.contains(name, ":"):
            continue                                  # interface, pas un périphérique
        base := "/sys/bus/usb/devices/" + name
        d := UsbDevice(name)
        d.vendor_id = _sys.hex(_sys.read(base + "/idVendor"))
        d.product_id = _sys.hex(_sys.read(base + "/idProduct"))
        if d.vendor_id == null:
            continue
        d.manufacturer = _sys.read(base + "/manufacturer")
        d.product = _sys.read(base + "/product")
        d.serial = _sys.read(base + "/serial")
        d.bus = _sys.dec(_sys.read(base + "/busnum"))
        d.address = _sys.dec(_sys.read(base + "/devnum"))
        d.speed_mbps = _speed(_sys.read(base + "/speed"))
        v := _sys.read(base + "/version")
        if v != null:
            d.usb_version = _s.trim(v)
        d.device_class = _sys.hex(_sys.read(base + "/bDeviceClass"))
        mp := _sys.read(base + "/bMaxPower")
        if mp != null:
            d.max_power_ma = _sys.dec(_s.replace(mp, "mA", ""))
        d.driver = _sys.link_name(base + "/driver")
        for iface in entries:
            if _s.starts_with(iface, name + ":"):
                c := class_name(_sys.hex(_sys.read("/sys/bus/usb/devices/" + iface + "/bInterfaceClass")))
                if c != null and not _has(d.classes, c):
                    append(d.classes, c)
        if len(d.classes) == 0 and class_name(d.device_class) != null:
            append(d.classes, class_name(d.device_class))
        if hubs or not d.is_hub():
            append(out, d)
    return out

func _has(items, x):
    for i in items:
        if i == x:
            return true
    return false

# Premier périphérique de ce fabricant (et de ce produit), ou null. Identifiants en int (1133) ou en texte
# hexadécimal (« 046d »).
func find(vendor_id, product_id=null):
    v := vendor_id
    if type(v) == "str":
        v = _sys.hex(v)
    pr := product_id
    if type(pr) == "str":
        pr = _sys.hex(pr)
    for d in devices():
        if d.vendor_id == v and (pr == null or d.product_id == pr):
            return d
    return null

# Périphériques d'une classe (« hid », « mass_storage », « audio », « video »...).
func by_class(name):
    return [d for d in devices(false) if _has(d.classes, name)]

func available():
    return len(devices(false)) > 0

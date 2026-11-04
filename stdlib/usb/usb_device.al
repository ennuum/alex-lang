# ALEX STANDARD LIBRARY — usb.usb_device
#
# Un périphérique USB branché (Linux : /sys/bus/usb/devices/<bus>-<port...>) : identifiants, chaînes, vitesse,
# position (bus, ports), descripteurs COMPLETS lus dans le fichier « descriptors » de /sys (sans droits
# particuliers), configuration active, interfaces et pilotes du noyau qui les tiennent ; et son ouverture par
# usbfs (UsbHandle) pour lui parler directement : réclamer une interface (en détachant le pilote du noyau si
# demandé), transferts de contrôle, points d'accès, réinitialisation.
#
#   use usb.usb_device as udev
#   d := udev.from_sysname("1-1.2")
#   print(d.describe())
#   print(d.configuration().describe())        # interfaces et points d'accès
#   h := d.open()                              # UsbError si /dev/bus/usb/... est inaccessible (droits)
#   h.claim(0, true)                           # détache usbhid, par exemple
#   ep := h.endpoint(0x81)
#   print(ep.read(8, 1000).data)
#   h.close()
#
# ALEX_HW_ROOT (hardware._sys.set_root) fait lire une copie de /sys (tests).

from core use len, type
from collections use append, contains_key
use string as _s
use io as _io
use hardware._sys as _sys
use _native_fd as _f
use usb.usb_descriptor as ud
use usb.usb_transfer as ut
use usb.usb_endpoint as uep
use pci.pci_ids as _ids

func _pad3(n):
    t := str(n)
    while len(t) < 3:
        t = "0" + t
    return t

class UsbDevice:
    func init(sysname):
        base := "/sys/bus/usb/devices/" + sysname
        self.sysname = sysname
        self.syspath = base
        self.bus = _sys.dec(_sys.read(base + "/busnum"))
        self.address = _sys.dec(_sys.read(base + "/devnum"))
        self.vendor_id = _sys.hex(_sys.read(base + "/idVendor"))
        self.product_id = _sys.hex(_sys.read(base + "/idProduct"))
        self.manufacturer = _sys.read(base + "/manufacturer")
        self.product = _sys.read(base + "/product")
        self.serial = _sys.read(base + "/serial")
        self.speed = _sys.read(base + "/speed")             # « 480 », « 12 », « 5000 »...
        self.version = _sys.read(base + "/version")
        if self.version != null:
            self.version = _s.trim(self.version)
        self.active_configuration = _sys.dec(_sys.read(base + "/bConfigurationValue"))
        self.max_children = _sys.dec(_sys.read(base + "/maxchild"))
        self.raw = []
        try:
            self.raw = _io.read_bytes(_sys.p(base + "/descriptors"))
        catch e:
            self.raw = []
        self.descriptor = null
        if len(self.raw) >= 18:
            self.descriptor = ud.parse_device([self.raw[i] for i in 0..18])
        self._configs = null

    func id():
        return _sys.hex4(self.vendor_id) + ":" + _sys.hex4(self.product_id)

    func name():
        if self.product != null:
            if self.manufacturer != null:
                return self.manufacturer + " " + self.product
            return self.product
        v := _ids.usb_vendor_name(self.vendor_id)
        if v != null:
            return v + " " + self.id()
        return self.id()

    func node():
        if self.bus == null or self.address == null:
            return null
        return "/dev/bus/usb/" + _pad3(self.bus) + "/" + _pad3(self.address)

    func is_hub():
        return self.descriptor != null and self.descriptor.device_class == ud.CLASS_HUB

    func is_root_hub():
        return _s.starts_with(self.sysname, "usb")

    # Chemin des ports depuis le concentrateur racine (« 1-1.2 » -> [1, 2]).
    func port_path():
        if self.is_root_hub():
            return []
        k := _s.find(self.sysname, "-")
        return [_sys.dec(p) for p in _s.split(_s.slice(self.sysname, k + 1), ".")]

    func parent_sysname():
        if self.is_root_hub():
            return null
        k := -1
        i := 0
        for c in self.sysname:
            if c == '.':
                k = i
            i += 1
        if k >= 0:
            return _s.slice(self.sysname, 0, k)
        return "usb" + str(self.bus)

    # Toutes les configurations (usb_descriptor.ConfigurationDescriptor) décrites dans « descriptors ».
    func configurations():
        if self._configs != null:
            return self._configs
        out := []
        pos := 18
        while pos + 9 <= len(self.raw):
            if self.raw[pos + 1] != ud.DT_CONFIGURATION:
                break
            total := self.raw[pos + 2] | (self.raw[pos + 3] << 8)
            if total < 9 or pos + total > len(self.raw):
                break
            append(out, ud.parse_configuration([self.raw[i] for i in pos..pos + total]))
            pos += total
        self._configs = out
        return out

    # Configuration active (ou la première).
    func configuration():
        cs := self.configurations()
        for c in cs:
            if c.value == self.active_configuration:
                return c
        return cs[0] if len(cs) > 0 else null

    func interfaces():
        c := self.configuration()
        return [] if c == null else c.interfaces

    # Pilote du noyau de l'interface n (« usbhid », « usb-storage »...), ou null.
    func interface_driver(n):
        cfg := self.active_configuration if self.active_configuration != null else 1
        return _sys.link_name(self.syspath + ":" + str(cfg) + "." + str(n) + "/driver")

    func classes():
        out := []
        for i in self.interfaces():
            n := ud.class_name(i.iclass)
            if not _has(out, n):
                append(out, n)
        return out

    func open():
        return UsbHandle(self)

    func describe():
        t := "Bus " + _pad3(self.bus) + " Device " + _pad3(self.address) + ": ID " + self.id() + " " + self.name()
        if self.speed != null:
            t = t + " (" + self.speed + " Mbit/s)"
        return t

    func describe_full():
        lines := [self.describe()]
        if self.descriptor != null:
            append(lines, "  " + self.descriptor.describe())
        for c in self.configurations():
            for l in _s.split(c.describe(), "\n"):
                append(lines, "  " + l)
        return _s.join("\n", lines)

func _has(xs, v):
    for x in xs:
        if x == v:
            return true
    return false

func from_sysname(sysname):
    if _sys.read("/sys/bus/usb/devices/" + sysname + "/idVendor") == null:
        raise("ArgumentError", "usb : pas de périphérique « " + sysname + " »")
    return UsbDevice(sysname)

# ---------------------------------------------------------------- accès direct (usbfs)
class UsbHandle:
    func init(device):
        self.device = device
        node := device.node()
        if node == null:
            raise("UsbError", "usb : nœud du périphérique inconnu")
        fd := _f.open_device(_sys.p(node), true)
        if fd < 0:
            raise("UsbError", "usb : ouverture de " + node + " impossible (" + _f.errno_name(-fd) + " : " + _f.strerror(-fd) + ") ; voir hardware.permissions")
        self.fd = fd
        self.claimed = []
        self.closed = false

    # Réclame l'interface n ; detach : détache d'abord le pilote du noyau qui la tient.
    func claim(n, detach=false):
        if detach:
            _f.usb_detach(self.fd, n)
        r := _f.usb_claim(self.fd, n)
        if r < 0:
            raise("UsbError", "usb : interface " + str(n) + " non réclamée (" + _f.errno_name(-r) + ")")
        append(self.claimed, n)
        return self

    func release(n):
        _f.usb_release(self.fd, n)
        self.claimed = [x for x in self.claimed if x != n]

    func control(setup, data=null, timeout_ms=1000):
        return ut.control(self.fd, setup, data, timeout_ms)

    func string(index):
        return ut.get_string(self.fd, index)

    func set_configuration(value):
        return ut.control(self.fd, ud.set_configuration(value)).ok

    func set_interface(n, alternate):
        return ut.control(self.fd, ud.set_interface(n, alternate)).ok

    # Point d'accès d'adresse address (dans la configuration active).
    func endpoint(address):
        for i in self.device.interfaces():
            for e in i.endpoints:
                if e.address == address:
                    return uep.Endpoint(self, e)
        raise("ArgumentError", "usb : pas de point d'accès " + str(address))

    func reset():
        return _f.usb_reset(self.fd) == 0

    func close():
        if not self.closed:
            for n in self.claimed:
                _f.usb_release(self.fd, n)
            _f.close(self.fd)
            self.closed = true

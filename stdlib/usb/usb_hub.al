# ALEX STANDARD LIBRARY — usb.usb_hub
#
# Concentrateurs USB et topologie : contrôleurs racines (usb1, usb2...), concentrateurs, nombre de ports, ce
# qui est branché sur chaque port, état des ports (Linux : /sys/.../<hub>-portN : connect_type, over_current,
# disable), et arbre complet comme « lsusb -t ».
#
#   use usb.usb_hub as hub
#   for h in hub.hubs():
#       print(h.describe())                    # « usb1 : concentrateur racine, 12 ports (2 occupés) »
#       for p in h.ports():
#           print(p.number, p.device_name())
#   print(hub.tree())

from core use len
from collections use append
use string as _s
use hardware._sys as _sys
use usb.usb_device as udev
use usb.usb_descriptor as ud

class Port:
    func init(hub, number):
        self.hub = hub
        self.number = number
        self.device = null            # usb_device.UsbDevice branché, ou null
        self.connect_type = null      # « hotplug », « hardwired », « not used »...
        self.over_current = null

    func occupied():
        return self.device != null

    func device_name():
        return self.device.name() if self.device != null else "(libre)"

class UsbHub:
    func init(device):
        self.device = device
        self.port_count = device.max_children if device.max_children != null else 0

    func is_root():
        return self.device.is_root_hub()

    # Sysname du périphérique branché sur le port n (« 1-1 » pour usb1 port 1, « 1-1.3 » sous 1-1).
    func child_sysname(n):
        if self.is_root():
            return str(self.device.bus) + "-" + str(n)
        return self.device.sysname + "." + str(n)

    func ports():
        out := []
        k := 1
        while k <= self.port_count:
            p := Port(self, k)
            child := self.child_sysname(k)
            if _sys.read("/sys/bus/usb/devices/" + child + "/idVendor") != null:
                p.device = udev.UsbDevice(child)
            pdir := self._port_dir(k)
            if pdir != null:
                p.connect_type = _sys.read(pdir + "/connect_type")
                p.over_current = _sys.dec(_sys.read(pdir + "/over_current_count"))
            append(out, p)
            k += 1
        return out

    func _port_dir(n):
        base := self.device.syspath + "/" + self.device.sysname + ":1.0"
        name := self.device.sysname + "-port" + str(n)
        if self.is_root():
            name = "usb" + str(self.device.bus) + "-port" + str(n)
        p := base + "/" + name
        if _sys.exists(p):
            return p
        return null

    func used():
        n := 0
        for p in self.ports():
            if p.occupied():
                n += 1
        return n

    func describe():
        kind := "concentrateur racine" if self.is_root() else "concentrateur"
        return self.device.sysname + " : " + kind + " " + self.device.name() + ", " + str(self.port_count) + " ports (" + str(self.used()) + " occupés)"

# Tous les concentrateurs (racines d'abord).
func hubs():
    roots := []
    out := []
    for name in _sys.list("/sys/bus/usb/devices"):
        if _s.contains(name, ":"):
            continue
        if _sys.read("/sys/bus/usb/devices/" + name + "/idVendor") == null:
            continue
        d := udev.UsbDevice(name)
        if d.is_root_hub():
            append(roots, UsbHub(d))
        elif d.is_hub():
            append(out, UsbHub(d))
    for h in out:
        append(roots, h)
    return roots

func root_hubs():
    return [h for h in hubs() if h.is_root()]

# Arbre des périphériques, une ligne par périphérique, indentée selon la profondeur.
func tree():
    lines := []
    for r in root_hubs():
        _walk(r.device, 0, lines)
    return _s.join("\n", lines)

func _walk(d, depth, lines):
    pad := ""
    k := 0
    while k < depth:
        pad = pad + "    "
        k += 1
    port := ""
    pp := d.port_path()
    if len(pp) > 0:
        port = "port " + str(pp[len(pp) - 1]) + ": "
    cls := _s.join(", ", d.classes())
    append(lines, pad + "|__ " + port + d.name() + " [" + d.id() + "]" + (" (" + cls + ")" if cls != "" else ""))
    if d.is_hub() or d.is_root_hub():
        h := UsbHub(d)
        for p in h.ports():
            if p.occupied():
                _walk(p.device, depth + 1, lines)

# ALEX STANDARD LIBRARY — usb.usb_discovery
#
# Trouver des périphériques USB : liste complète, recherche par identifiants, par classe d'interface, par
# numéro de série, par prédicat ; attente d'un branchement ; suivi des branchements / retraits (async).
#
#   use usb.usb_discovery as disc
#   for d in disc.devices():
#       print(d.describe())
#   cle := disc.find(0x0781)                       # premier SanDisk
#   claviers := disc.by_class(ud.CLASS_HID)
#   d := await disc.wait_for(0x2341, 0x0043, 30)    # Arduino Uno, 30 s au plus (null sinon)
#   w := disc.Watcher()
#   w.on("added", (d) => print("branché", d.describe()))
#   await w.run(60)

from core use len, type
from collections use append, contains_key, keys
use string as _s
use asyncio
use hardware._sys as _sys
use usb.usb_device as udev
use usb.usb_descriptor as ud
use event.event_emitter as _ee

# Périphériques présents (usb_device.UsbDevice) ; hubs=false : sans les concentrateurs.
func devices(hubs=true):
    out := []
    for name in _sys.list("/sys/bus/usb/devices"):
        if _s.contains(name, ":"):
            continue
        if _sys.read("/sys/bus/usb/devices/" + name + "/idVendor") == null:
            continue
        d := udev.UsbDevice(name)
        if hubs or not (d.is_hub() or d.is_root_hub()):
            append(out, d)
    return out

func _id(v):
    if type(v) == "str":
        return _sys.hex(v)
    return v

# Premier périphérique (fabricant[, produit]) ; identifiants int ou texte hexadécimal ; null si absent.
func find(vendor_id, product_id=null):
    v := _id(vendor_id)
    p := _id(product_id)
    for d in devices():
        if d.vendor_id == v and (p == null or d.product_id == p):
            return d
    return null

func find_all(vendor_id, product_id=null):
    v := _id(vendor_id)
    p := _id(product_id)
    return [d for d in devices() if d.vendor_id == v and (p == null or d.product_id == p)]

func by_serial(serial):
    for d in devices():
        if d.serial == serial:
            return d
    return null

# Périphériques ayant une interface de cette classe (usb_descriptor.CLASS_HID...).
func by_class(cls):
    out := []
    for d in devices(false):
        dc := d.descriptor.device_class if d.descriptor != null else 0
        found := dc == cls
        for i in d.interfaces():
            if i.iclass == cls:
                found = true
        if found:
            append(out, d)
    return out

func matching(predicate):
    return [d for d in devices() if predicate(d)]

func _snapshot():
    out := {}
    for d in devices():
        out[d.sysname] = d
    return out

# Futur : le périphérique (vendeur, produit) dès qu'il est branché, ou null après timeout secondes.
async func wait_for(vendor_id, product_id=null, timeout=null, interval=0.5):
    start := asyncio.now()
    while true:
        d := find(vendor_id, product_id)
        if d != null:
            return d
        if timeout != null and asyncio.now() - start >= timeout:
            return null
        await asyncio.sleep(interval)

# Suivi des branchements : événements "added" / "removed" (usb_device.UsbDevice).
class Watcher:
    func init(interval=0.5):
        self.interval = interval
        self.emitter = _ee.EventEmitter()
        self.known = _snapshot()
        self.stopped = false

    func on(event_type, fn):
        return self.emitter.on(event_type, fn)

    # Compare à l'instantané précédent ; renvoie [ajoutés, retirés].
    func check():
        now := _snapshot()
        added := []
        removed := []
        for k in keys(now):
            if not contains_key(self.known, k):
                append(added, now[k])
        for k in keys(self.known):
            if not contains_key(now, k):
                append(removed, self.known[k])
        self.known = now
        for d in added:
            self.emitter.emit("added", d)
        for d in removed:
            self.emitter.emit("removed", d)
        return [added, removed]

    func stop():
        self.stopped = true

    async func run(duration=null):
        start := asyncio.now()
        while not self.stopped:
            self.check()
            if duration != null and asyncio.now() - start >= duration:
                break
            await asyncio.sleep(self.interval)

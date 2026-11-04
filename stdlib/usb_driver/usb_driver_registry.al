# alex: native
# ALEX STANDARD LIBRARY — usb_driver.usb_driver_registry
#
# Registre des pilotes de classe USB et liaison aux interfaces des périphériques énumérés : pour chaque
# interface (réglage 0) de chaque périphérique, le premier pilote dont matches() répond oui l'obtient.
# Les pilotes sont fournis par des FABRIQUES (une instance par interface liée).
#
#   r := UsbDriverRegistry()
#   r.add_keyboard()
#   r.add_mouse()
#   r.add_mass_storage()
#   r.bind(hc, dev)                       # périphérique énuméré
#   for b in r.bound:                     # UsbClassDriver
#       print(b.describe())
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use usb.usb_descriptor as ud
from usb.usb_descriptor use InterfaceDescriptor
use usb_driver.usb_host_controller as uhc
from usb_driver.usb_host_controller use HostController, UsbDev
use usb_driver.usb_class as uc
from usb_driver.usb_class use UsbClassDriver, HidKeyboard, HidMouse, MassStorage

class UsbDriverRegistry:
    factories: list[func() -> UsbClassDriver] := []
    names: list[str] := []
    use_keyboard: bool := false
    use_mouse: bool := false
    use_storage: bool := false
    bound: list[UsbClassDriver] := []
    keyboards: list[HidKeyboard] := []
    mice: list[HidMouse] := []
    disks: list[MassStorage] := []
    unclaimed: list[str] := []
    log: list[str] := []

    func init():
        self.factories = []
        self.names = []
        self.use_keyboard = false
        self.use_mouse = false
        self.use_storage = false
        self.bound = []
        self.keyboards = []
        self.mice = []
        self.disks = []
        self.unclaimed = []
        self.log = []

    # Pilote supplémentaire : factory() crée une instance (matches / attach / poll), essayée après les
    # pilotes fournis.
    func add(label: str, factory: func() -> UsbClassDriver):
        append(self.factories, factory)
        append(self.names, label)

    func add_keyboard():
        self.use_keyboard = true

    func add_mouse():
        self.use_mouse = true

    func add_mass_storage():
        self.use_storage = true

    func add_defaults():
        self.use_keyboard = true
        self.use_mouse = true
        self.use_storage = true

    func _attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor, drv: UsbClassDriver) -> bool:
        try:
            drv.attach(hc, dev, itf)
            append(self.bound, drv)
            append(self.log, dev.describe() + " interface " + str(itf.number) + " -> " + drv.name())
            return true
        catch e:
            append(self.log, dev.describe() + " interface " + str(itf.number) + " : " + drv.name() + " en échec (" + e.message + ")")
            return false

    func _bind_interface(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor) -> bool:
        if self.use_keyboard:
            k := HidKeyboard()
            if k.matches(dev, itf):
                if self._attach(hc, dev, itf, k):
                    append(self.keyboards, k)
                    return true
                return false
        if self.use_mouse:
            m := HidMouse()
            if m.matches(dev, itf):
                if self._attach(hc, dev, itf, m):
                    append(self.mice, m)
                    return true
                return false
        if self.use_storage:
            s := MassStorage("usb" + str(len(self.disks)))
            if s.matches(dev, itf):
                if self._attach(hc, dev, itf, s):
                    append(self.disks, s)
                    return true
                return false
        for f in self.factories:
            drv := f()
            if drv.matches(dev, itf):
                return self._attach(hc, dev, itf, drv)
        return false

    # Lie les interfaces de dev ; renvoie le nombre d'interfaces prises.
    func bind(hc: HostController, dev: UsbDev) -> int:
        n := 0
        for itf in dev.config.interfaces:
            if itf.alternate != 0:
                continue
            if self._bind_interface(hc, dev, itf):
                n += 1
            else:
                append(self.unclaimed, dev.describe() + " interface " + str(itf.number) + " (" + ud.class_name(itf.iclass) + ")")
        return n

    # Interroge tous les pilotes liés ; renvoie le nombre d'événements.
    func poll() -> int:
        n := 0
        for d in self.bound:
            n += d.poll()
        return n

    func describe() -> str:
        t := ""
        for d in self.bound:
            t = t + d.describe() + "\n"
        for u in self.unclaimed:
            t = t + u + " : sans pilote\n"
        return t

# ALEX STANDARD LIBRARY — usb.usb_configuration
#
# Configurations USB : analyse des octets bruts (y compris les ASSOCIATIONS d'interfaces, IAD, qui regroupent
# plusieurs interfaces en une seule fonction — webcam UVC, carte réseau CDC-NCM, série CDC-ACM), budget
# d'ALIMENTATION selon le port (100 mA bas courant, 500 mA USB 2, 900 mA USB 3) et la vitesse, choix de la
# configuration la mieux adaptée à une classe, et résumé de toutes les configurations d'un périphérique.
#
#   use usb.usb_configuration as uc
#   c := uc.parse(octets)                          # Configuration (descripteur + associations)
#   for a in c.associations:
#       print(a.first_interface, a.count, a.class_name())
#   print(c.power_ok("high"), c.max_power_ma())
#   meilleure := uc.choose(device.configurations(), usb_descriptor.CLASS_CDC)
#   print(uc.summary(device.configurations()))
#
# Erreurs : ArgumentError (descripteur invalide).

from core use len, type
from collections use append
use usb.usb_descriptor as ud
use usb.usb_interface as ui
use string as _s

class Association:
    func init(first_interface, count, fclass, subclass, protocol, string_index):
        self.first_interface = first_interface
        self.count = count
        self.fclass = fclass
        self.subclass = subclass
        self.protocol = protocol
        self.string_index = string_index

    func interfaces():
        return [self.first_interface + k for k in 0..self.count]

    func class_name():
        return ud.class_name(self.fclass)

    func describe():
        return "fonction " + self.class_name() + " : interfaces " + str(self.first_interface) + ".." + str(self.first_interface + self.count - 1)

class Configuration:
    func init(descriptor, associations):
        self.descriptor = descriptor
        self.associations = associations
        self.value = descriptor.value

    func max_power_ma():
        return self.descriptor.max_power_ma

    func interfaces():
        return ui.functions(self.descriptor)

    # Courant disponible sur un port selon la vitesse (USB 3 : 900 mA, USB 2 : 500 mA, bas courant : 100 mA).
    func port_budget(speed="high", low_power=false):
        if low_power:
            return 100
        if speed == "super":
            return 900
        return 500

    func power_ok(speed="high", low_power=false):
        if self.descriptor.self_powered():
            return true
        return self.max_power_ma() <= self.port_budget(speed, low_power)

    func association_of(interface_number):
        for a in self.associations:
            if interface_number >= a.first_interface and interface_number < a.first_interface + a.count:
                return a
        return null

    func has_class(iclass):
        for i in self.descriptor.interfaces:
            if i.iclass == iclass:
                return true
        for a in self.associations:
            if a.fclass == iclass:
                return true
        return false

    func describe():
        t := self.descriptor.describe()
        for a in self.associations:
            t += "\n  " + a.describe()
        return t

func parse_associations(raw):
    out := []
    pos := 0
    n := len(raw)
    while pos + 2 <= n:
        size := raw[pos]
        if size < 2 or pos + size > n:
            break
        if raw[pos + 1] == ud.DT_INTERFACE_ASSOCIATION and size >= 8:
            append(out, Association(raw[pos + 2], raw[pos + 3], raw[pos + 4], raw[pos + 5], raw[pos + 6], raw[pos + 7]))
        pos += size
    return out

func parse(raw):
    if len(raw) < 9 or raw[1] != ud.DT_CONFIGURATION:
        raise("ArgumentError", "descripteur de configuration invalide")
    return Configuration(ud.parse_configuration(raw), parse_associations(raw))

func wrap(descriptor, raw=null):
    a := []
    if raw != null:
        a = parse_associations(raw)
    return Configuration(descriptor, a)

# Configuration (descripteur) qui contient la classe demandée et respecte le budget d'alimentation, en
# préférant la moins gourmande ; null si aucune.
func choose(descriptors, iclass=null, speed="high"):
    best := null
    for d in descriptors:
        c := wrap(d)
        if iclass != null and not c.has_class(iclass):
            continue
        if not c.power_ok(speed):
            continue
        if best == null or d.max_power_ma < best.max_power_ma:
            best = d
    return best

func summary(descriptors):
    lines := []
    for d in descriptors:
        classes := []
        for i in d.interfaces:
            n := ud.class_name(i.iclass)
            if not (n in classes):
                append(classes, n)
        append(lines, "configuration " + str(d.value) + " : " + str(d.interface_count) + " interface(s), " + str(d.max_power_ma) + " mA, " + _s.join(", ", classes))
    return _s.join("\n", lines)

# ALEX STANDARD LIBRARY — hardware.bus
#
# Bus de périphériques du système hôte (Linux, /sys/bus) :
#   - Bus : périphériques et pilotes d'un bus (pci, usb, i2c, platform, virtio, hid, scsi...), pilote lié à
#     chaque périphérique, sonde automatique (drivers_autoprobe) ;
#   - liaison manuelle : bind / unbind d'un périphérique à un pilote, driver_override (PCI), rescan, retrait
#     (remove) — écritures dans /sys réservées à root : sans les droits, BusError avec la commande à lancer ;
#   - topologie : arbre PCI (ponts, ports racine) et USB (contrôleur, concentrateurs, ports « 1-1.2 »)
#     reconstruit à partir des chemins réels de /sys/devices.
#
#   use hardware.bus as hb
#   pci := hb.get("pci")
#   for d in pci.devices(): print(d.name + " -> " + str(pci.driver_of(d.name)))
#   print(pci.tree_text())
#   pci.unbind("0000:01:00.0")            # BusError (non root) : « echo 0000:01:00.0 > /sys/... »
#
# Erreurs : BusError (bus inconnu, écriture refusée), HardwareUnavailable (périphérique absent).

from core use len, type
from collections use append, contains_key
use string as _s
use os as _os
use io as _io
use hardware._sys as _sys
use hardware.device as _dev

const _SPECIAL := ["bind", "unbind", "new_id", "remove_id", "uevent", "module"]

func names():
    return _sys.list("/sys/bus")

func exists(name):
    return _sys.exists("/sys/bus/" + name)

func get(name):
    if not exists(name):
        raise("BusError", "bus « " + name + " » inconnu (" + _s.join(", ", names()) + ")")
    return Bus(name)

class Bus:
    func init(name):
        self.name = name
        self.path = "/sys/bus/" + name

    func device_names():
        return _sys.list(self.path + "/devices")

    func devices():
        return [_dev.Device(self.path + "/devices/" + n) for n in self.device_names()]

    func device(name):
        if not _sys.exists(self.path + "/devices/" + name):
            raise("HardwareUnavailable", self.name + " : périphérique « " + name + " » absent")
        return _dev.Device(self.path + "/devices/" + name)

    func drivers():
        return _sys.list(self.path + "/drivers")

    # Périphériques liés au pilote driver.
    func bound_to(driver):
        out := []
        for n in _sys.list(self.path + "/drivers/" + driver):
            if not (n in _SPECIAL) and _sys.link_name(self.path + "/drivers/" + driver + "/" + n) != null:
                if _sys.exists(self.path + "/devices/" + n):
                    append(out, n)
        return out

    func driver_of(name):
        return _sys.link_name(self.path + "/devices/" + name + "/driver")

    # Périphériques sans pilote.
    func unbound():
        return [n for n in self.device_names() if self.driver_of(n) == null]

    func autoprobe():
        v := _sys.read(self.path + "/drivers_autoprobe")
        return v == "1"

    # Table pilote -> périphériques.
    func bindings():
        out := {}
        for n in self.device_names():
            d := self.driver_of(n)
            k := d if d != null else "(aucun)"
            if not contains_key(out, k):
                out[k] = []
            append(out[k], n)
        return out

    func _write(rel, value):
        target := self.path + "/" + rel
        cmd := "echo " + value + " | sudo tee " + target
        if not _sys.exists(target):
            raise("BusError", target + " absent (opération non prise en charge par ce bus)")
        try:
            _io.write_at(_sys.p(target), value, 0)
        catch e:
            raise("BusError", "écriture refusée dans " + target + " (" + e.message + ") ; à lancer en root : " + cmd)
        return cmd

    func bind(device, driver):
        self.device(device)
        return self._write("drivers/" + driver + "/bind", device)

    func unbind(device):
        d := self.driver_of(device)
        if d == null:
            raise("BusError", device + " : aucun pilote lié")
        return self._write("drivers/" + d + "/unbind", device)

    # PCI : impose le pilote (« vfio-pci » pour donner la carte à une machine virtuelle).
    func override(device, driver):
        self.device(device)
        return self._write("devices/" + device + "/driver_override", driver)

    func rescan():
        return self._write("rescan", "1")

    func remove(device):
        self.device(device)
        return self._write("devices/" + device + "/remove", "1")

    # Arbre : list de [profondeur, nom, pilote], parents avant enfants, d'après les chemins réels.
    func tree():
        rows := []
        for n in self.device_names():
            rp := _dev._resolve(self.path + "/devices/" + n)
            parts := [p for p in _s.split(rp, "/") if p != ""]
            chain := []
            for p in parts:
                if p in self.device_names() or (_s.starts_with(p, "pci") and self.name == "pci") or (_s.starts_with(p, "usb") and self.name == "usb"):
                    append(chain, p)
            append(rows, [_s.join("/", chain), n])
        ordered := []
        for r in rows:
            k := 0
            while k < len(ordered) and ordered[k][0] <= r[0]:
                k += 1
            ordered = [ordered[i] for i in 0..k] + [r] + [ordered[i] for i in k..len(ordered)]
        rows = ordered
        out := []
        for r in rows:
            depth := len(_s.split(r[0], "/")) - 1
            if self.name == "pci":
                depth -= 1
            if depth < 0:
                depth = 0
            append(out, [depth, r[1], self.driver_of(r[1])])
        return out

    func tree_text():
        lines := []
        for row in self.tree():
            t := _s.repeat("  ", row[0]) + row[1]
            if row[2] != null:
                t += " [" + row[2] + "]"
            append(lines, t)
        return _s.join("\n", lines)

    func describe():
        return "bus " + self.name + " : " + str(len(self.device_names())) + " périphériques, " + str(len(self.drivers())) + " pilotes, " + str(len(self.unbound())) + " sans pilote"

func all():
    return [Bus(n) for n in names()]

func summary():
    return [b.describe() for b in all()]

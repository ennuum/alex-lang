# ALEX STANDARD LIBRARY — hardware.device_info
#
# Description lisible d'un périphérique (hardware.device.Device) : catégorie (stockage, réseau, affichage,
# entrée, son, USB, pont...), noms du fabricant et du modèle (tables PCI / USB : pci.pci_ids), et résumé.
#
#   use hardware.device_info as di
#   info := di.describe(d)                 # DeviceInfo
#   print(info.category, info.vendor, info.model, info.summary())
#   print(di.category_of("net"))           # « réseau »
#
# Les catégories s'appuient sur le sous-système et, pour PCI et USB, sur la classe déclarée.

from core use type
from collections use contains_key
use string as _s
use hardware._sys as _sys
use pci.pci_ids as _ids
use hardware.usb as _usb

_SUBSYSTEMS := {"block": "stockage", "nvme": "stockage", "scsi": "stockage", "ata": "stockage", "mmc": "stockage",
                "net": "réseau", "drm": "affichage", "graphics": "affichage", "backlight": "affichage",
                "input": "entrée", "hidraw": "entrée", "hid": "entrée", "sound": "son", "video4linux": "vidéo",
                "usb": "usb", "tty": "terminal", "serial": "série", "power_supply": "alimentation", "thermal": "thermique",
                "hwmon": "capteurs", "bluetooth": "bluetooth", "ieee80211": "réseau sans fil", "rtc": "horloge",
                "watchdog": "chien de garde", "leds": "voyants", "pci": "pci", "virtio": "virtio", "platform": "plate-forme",
                "acpi": "acpi", "cpu": "processeur", "memory": "mémoire", "dma": "dma", "iommu": "iommu", "misc": "divers"}

_PCI_CATEGORY := {1: "stockage", 2: "réseau", 3: "affichage", 4: "multimédia", 5: "mémoire", 6: "pont", 7: "communication",
                  8: "système", 9: "entrée", 12: "bus série", 13: "sans fil", 16: "chiffrement", 17: "acquisition",
                  18: "accélérateur"}

_USB_CATEGORY := {"hid": "entrée", "audio": "son", "video": "vidéo", "mass_storage": "stockage", "hub": "usb",
                  "printer": "impression", "communication": "communication", "wireless": "sans fil", "image": "image"}

func category_of(subsystem):
    if subsystem != null and contains_key(_SUBSYSTEMS, subsystem):
        return _SUBSYSTEMS[subsystem]
    return "autre"

class DeviceInfo:
    func init(device, category, vendor, model, class_name):
        self.device = device
        self.category = category
        self.vendor = vendor
        self.model = model
        self.class_name = class_name

    func summary():
        t := "[" + self.category + "] "
        if self.vendor != null:
            t = t + self.vendor + " "
        if self.model != null:
            t = t + self.model
        elif self.class_name != null:
            t = t + self.class_name
        else:
            t = t + self.device.name
        if self.device.driver != null:
            t = t + " (pilote " + self.device.driver + ")"
        return t

    func to_dict():
        return {"name": self.device.name, "category": self.category, "vendor": self.vendor, "model": self.model,
                "class": self.class_name, "driver": self.device.driver}

func describe(d):
    sub := d.subsystem
    category := category_of(sub)
    vendor := null
    model := null
    cls_name := null
    if sub == "pci":
        cls := _sys.hex(d.attribute("class"))
        v := _sys.hex(d.attribute("vendor"))
        p := _sys.hex(d.attribute("device"))
        if cls != null:
            base := (cls >> 16) & 255
            subc := (cls >> 8) & 255
            cls_name = _ids.class_name(base, subc, cls & 255)
            if contains_key(_PCI_CATEGORY, base):
                category = _PCI_CATEGORY[base]
        if v != null:
            vendor = _ids.vendor_name(v)
            if p != null:
                model = _ids.device_name(v, p)
    elif sub == "usb":
        v := _sys.hex(d.attribute("idVendor"))
        if v != null:
            vendor = d.attribute("manufacturer")
            if vendor == null:
                vendor = _ids.usb_vendor_name(v)
            model = d.attribute("product")
            c := _usb.class_name(_sys.hex(d.attribute("bDeviceClass")))
            if c != null:
                cls_name = c
                if contains_key(_USB_CATEGORY, c):
                    category = _USB_CATEGORY[c]
    else:
        model = d.attribute("device/model")
        if model == null:
            model = d.attribute("name")
        vendor = d.attribute("device/vendor")
        # périphérique de classe (net, block, sound...) porté par un appareil PCI ou virtio : noms de la table PCI
        if vendor != null and _s.starts_with(vendor, "0x"):
            v := _sys.hex(vendor)
            p := _sys.hex(d.attribute("device/device"))
            vendor = _ids.vendor_name(v)
            if model == null and p != null:
                model = _ids.device_name(v, p)
            if model == null or _s.starts_with(model, "périphérique "):
                sub_dev := _sys.link_name(d.syspath + "/device/subsystem")
                if sub_dev == "virtio":
                    up_v := _sys.hex(d.attribute("device/../vendor"))
                    up_p := _sys.hex(d.attribute("device/../device"))
                    if up_v != null and up_p != null:
                        model = _ids.device_name(up_v, up_p)
        if model == null:
            model = d.name
        elif model != d.name:
            model = model + " " + d.name
    return DeviceInfo(d, category, vendor, model, cls_name)

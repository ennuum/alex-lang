# ALEX STANDARD LIBRARY — usb
#
# USB depuis une application (Linux) :
#
# | Module               | Contenu                                                                       |
# |----------------------|-------------------------------------------------------------------------------|
# | usb.usb_descriptor   | descripteurs (périphérique, configuration, interface, point d'accès, HID,     |
# |                      | chaînes), paquets SETUP standard — aussi utilisé par les pilotes du noyau     |
# | usb.usb_device       | UsbDevice (/sys : identifiants, configurations), UsbHandle (usbfs)            |
# | usb.usb_endpoint     | Endpoint : lecture / écriture, message complet, levée du blocage              |
# | usb.usb_transfer     | contrôle, bloc, interruption ; TransferResult                                 |
# | usb.usb_hub          | concentrateurs, ports, arbre                                                  |
# | usb.usb_discovery    | recherche, attente d'un branchement, Watcher                                  |
#
#   use usb
#   print(usb.lsusb())                         # comme la commande lsusb
#   d := usb.find(0x2341)                      # Arduino
#   h := usb.open(d)
#
# Droits : l'accès direct (open) exige le droit d'écriture sur /dev/bus/usb/BBB/DDD (règle udev :
# hardware.permissions.udev_rule). Pilotes du noyau Alex : usb_driver.

from core use len
from collections use append
use string as _s
use usb.usb_device as udev
use usb.usb_discovery as disc
use usb.usb_hub as hub
use usb.usb_descriptor as ud

func devices(hubs=true):
    return disc.devices(hubs)

func find(vendor_id, product_id=null):
    return disc.find(vendor_id, product_id)

func by_class(cls):
    return disc.by_class(cls)

func open(device):
    return device.open()

func tree():
    return hub.tree()

func available():
    return len(disc.devices()) > 0

# Liste façon lsusb (verbose : descripteurs et points d'accès).
func lsusb(verbose=false):
    lines := []
    for d in disc.devices():
        if verbose:
            append(lines, d.describe_full())
        else:
            append(lines, d.describe())
    return _s.join("\n", lines)

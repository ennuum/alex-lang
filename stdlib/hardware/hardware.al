# ALEX STANDARD LIBRARY — hardware
#
# Point d'entrée du matériel vu depuis une APPLICATION (système hôte, Linux surtout) :
#
# | Module                     | Rôle                                                                     |
# |----------------------------|--------------------------------------------------------------------------|
# | hardware.hardware_info     | processeur, mémoire, micrologiciel, hyperviseur, noyau                   |
# | hardware.device            | un périphérique de /sys (sous-système, pilote, nœud /dev, attributs)     |
# | hardware.device_info       | sa description lisible (catégorie, fabricant, modèle)                    |
# | hardware.device_manager    | inventaire, regroupements, suivi des branchements                        |
# | hardware.memory_map        | carte de la mémoire physique et des projections d'un processus           |
# | hardware.permissions       | droits sur les nœuds /dev, groupes, capacités, règles udev               |
# | hardware.keyboard / mouse / screen / gpu / usb / audio / microphone / camera | inventaires spécialisés |
#
# Pour écrire des PILOTES (noyau Alex ou machine simulée) : pci, interrupt, dma, driver, storage_driver,
# network_driver, usb_driver, gpu_driver (docs/HARDWARE_DRIVERS.md).
#
#   use hardware
#   print(hardware.summary())                    # machine, processeur, mémoire, périphériques par catégorie
#   for d in hardware.devices("réseau"):
#       print(d.summary())
#   print(hardware.can_use("camera"))

from core use len, type
from collections use append, contains_key, keys, sort
use string as _s
use hardware.hardware_info as _hi
use hardware.device as _dev
use hardware.device_info as _di
use hardware.device_manager as _dm
use hardware.memory_map as _mm
use hardware.permissions as _perm

func info():
    return _hi.info()

func cpu():
    return _hi.cpu()

func memory():
    return _hi.memory()

func firmware():
    return _hi.firmware()

func hypervisor():
    return _hi.hypervisor()

func memory_map():
    return _mm.physical()

func manager(subsystems=null):
    return _dm.DeviceManager(subsystems)

# Descriptions (hardware.device_info.DeviceInfo) des périphériques suivis, éventuellement d'une catégorie
# (« stockage », « réseau », « affichage », « entrée », « son », « vidéo », « usb »...).
func devices(category=null):
    m := _dm.DeviceManager()
    out := []
    for d in m.all():
        i := _di.describe(d)
        if category == null or i.category == category:
            append(out, i)
    return out

func device(subsystem, name):
    return _dev.from_class(subsystem, name)

# Nombre de périphériques par catégorie.
func census():
    out := {}
    for i in devices():
        if not contains_key(out, i.category):
            out[i.category] = 0
        out[i.category] = out[i.category] + 1
    return out

# Le processus peut-il utiliser une catégorie de matériel (hardware.permissions : camera, gpu, audio, input,
# serial, usb, storage, kvm...) ? false si aucun nœud n'existe.
func can_use(category, want="rw"):
    return _perm.check_category(category).usable(want)

func identity():
    return _perm.current()

func summary():
    lines := [_hi.info().describe()]
    c := census()
    if len(c) > 0:
        ks := [k for k in keys(c)]
        sort(ks)
        append(lines, "Périphériques : " + _s.join(", ", [k + " " + str(c[k]) for k in ks]))
    return _s.join("\n", lines)

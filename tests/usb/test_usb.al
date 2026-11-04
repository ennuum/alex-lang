# Paquet usb (applications) sur une copie factice de /sys et /dev (tests/usb/make_fake_usb.py) : descripteurs,
# périphériques, configurations, concentrateurs et arbre, recherche, Watcher, erreurs d'accès direct.
from core use len
use os
use process
use hardware._sys as hsys
use usb
use usb.usb_descriptor as ud
use usb.usb_device as udev
use usb.usb_hub as hub
use usb.usb_discovery as disc
use usb.usb_transfer as ut

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

root := os.tmp_dir() + "/alex_usb_" + str(os.pid())
process.run("python3", ["tests/usb/make_fake_usb.py", root])
hsys.set_root(root)

ds := usb.devices()
check(len(ds) == 4, "4 périphériques")
check(len(usb.devices(false)) == 2, "2 sans les concentrateurs")
kb := usb.find(0x046d)
check(kb != null and kb.name() == "Logitech USB Keyboard" and kb.id() == "046d:c31c", "clavier trouvé")
check(kb.serial == "KB0001" and kb.node() == "/dev/bus/usb/001/002", "série et nœud")
check(kb.descriptor.vendor == 0x046d and kb.descriptor.max_packet0 == 64, "descripteur du périphérique")
cf := kb.configuration()
check(cf.value == 1 and cf.max_power_ma == 100 and cf.remote_wakeup(), "configuration")
itf := cf.find_interface(0)
check(itf.is_boot_keyboard() and itf.hid_report_length == 63, "interface HID d'amorçage")
ep := itf.endpoint(ud.EP_INTERRUPT, true)
check(ep.address == 0x81 and ep.packet_size() == 8 and ep.interval == 10, "point d'accès d'interruption")
check(kb.classes() == ["hid"], "classes")
cle := disc.find("0781", "5567")
check(cle != null and cle.port_path() == [2, 3] and cle.parent_sysname() == "1-2", "position de la clé")
st := cle.configuration().find_class(ud.CLASS_MASS_STORAGE)
check(st != null and st.protocol == 0x50 and len(st.endpoints) == 2, "stockage de masse (bloc)")
check(len(disc.by_class(ud.CLASS_HID)) == 1 and len(disc.by_class(ud.CLASS_MASS_STORAGE)) == 1, "par classe")
check(disc.by_serial("KB0001").sysname == "1-1", "par numéro de série")
hs := hub.hubs()
check(len(hs) == 2 and hs[0].is_root(), "concentrateurs")
racine := hs[0]
ps := racine.ports()
check(len(ps) == 2 and ps[0].device.sysname == "1-1" and ps[0].connect_type == "hotplug", "ports de la racine")
check(racine.used() == 2 and hs[1].used() == 1, "ports occupés")
arbre := usb.tree()
check(len(arbre) > 0, "arbre")
print(arbre)
print(usb.lsusb(true))
# accès direct : le nœud factice est un fichier ordinaire -> les ioctl échouent proprement
h := kb.open()
erreur := ""
try:
    h.claim(0)
catch e:
    erreur = e.type
check(erreur == "UsbError", "réclamation impossible sur un faux nœud")
r := h.control(ud.get_descriptor(ud.DT_DEVICE, 0, 18))
check(not r.ok and r.error == "ENOTTY", "contrôle refusé : " + r.describe())
h.close()
# branchements
w := disc.Watcher()
os.rmdir(root + "/sys/bus/usb/devices/1-2.3", true)
res := w.check()
check(len(res[1]) == 1 and res[1][0].sysname == "1-2.3", "retrait détecté")
os.rmdir(root, true)
print("usb : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")

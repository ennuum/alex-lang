# Sans OS (QEMU) : pile USB — contrôleur UHCI (PCI), énumération des ports, descripteurs, clavier HID
# (frappes envoyées par le moniteur de QEMU), stockage de masse (BOT / SCSI) utilisé comme disque.
use hw
use usb_driver
use driver.driver_errors as de
use storage_driver.block_device as bd
use storage_driver.disk as dk
from core use len

pile := usb_driver.start()
print(pile.describe())
for line in pile.registry.log:
    print(line)
for d in pile.devices:
    print(d.descriptor.describe())
    print(d.config.describe())
buf := hw.alloc_pages(4)
for disk in pile.registry.disks:
    print(disk.describe())
    disk.read_blocks(1, 1, buf)
    print("signature : " + hw.string_at(buf, 11))
    disk.read_blocks(98, 4, buf)
    print("motif : " + str(hw.peek8(buf + 2 * 512 + 200)))
    hw.store_string("USB écrit", buf)
    disk.write_blocks(600, 1, buf)
    disk.flush()
    hw.zero(buf, 512)
    disk.read_blocks(600, 1, buf)
    print("relu : " + hw.string_at(buf, 10))
    print(dk.Disk(disk).describe())
for k in pile.registry.keyboards:
    texte := ""
    tours := 0
    while tours < 60000 and len(texte) < 8:
        pile.poll()
        texte = texte + k.take_text()
        tours += 1
        de.io_delay(1000)
    print("clavier : " + texte)

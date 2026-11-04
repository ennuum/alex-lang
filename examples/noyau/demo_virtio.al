# Démonstration (et test) : disque virtio-blk de QEMU (`-device virtio-blk-pci`), système de fichiers FAT16
# par-dessus (bloc.al choisit le pilote), puis des processus chargés depuis ce disque, sur plusieurs cœurs.
use hw
use bus_pci as pci
use bloc
use fat
use smp
use processus
from processus use Process
from collections use append
from core use len
from string use strip

n := bloc.init()
print("pilote :", bloc.name())
print("secteurs :", n)
for d in pci.scan():
    if d.vendor == 6900:
        print("périphérique PCI virtio :", pci.hex4(d.device), d.kind())
fat.mount()
for e in fat.list(): # sans les tailles : celles des exécutables changent avec le compilateur
    print(" ", e.name)
print(strip(fat.read("HELLO.TXT")))

# Écriture sur plusieurs secteurs et grappes, relecture après remontage du volume.
texte := ""
for i in 0..300:
    texte += f"ligne {i} écrite par le pilote virtio-blk\n"
fat.write("VIRTIO.TXT", texte)
fat.mount()
relu := fat.read("VIRTIO.TXT")
print("écrit puis relu :", hw.byte_size(relu), "octets, identique :", relu == texte)

# Processus chargés depuis le disque virtio, en parallèle.
print("cœurs :", smp.start(100))
outputs: dict[int, str] := {}
func collector(k: int) -> func(str):
    func add(s: str):
        outputs[k] = outputs[k] + s
    return add
func no_input() -> str:
    return ""
ps: list[Process] := []
for k in 0..3:
    outputs[k] = ""
    append(ps, processus.spawn("CALCUL.ELF", ["500000", str(7 * (k + 1))], collector(k), no_input))
for k in 0..3:
    print(f"code {processus.wait(ps[k])}, {strip(outputs[k])}")
hw.exit(0)

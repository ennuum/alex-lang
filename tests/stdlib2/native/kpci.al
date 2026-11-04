from core use len
use pci.pci_config as cfg
use pci.pci_bus as pbus
use pci.pci_errors as perr
use pci.pci_bar as pb
use pci.pci_capability as pc
c := cfg.PortConfig()
for d in pbus.scan(c):
    print(d.describe())
    print(perr.describe_status(d.status()))
    for b in d.bars():
        print(pb.decode(d.read32(0x10)).kind_name())
    m := pc.msi(d)
    if m != null:
        print(m.requested_vectors())
    e := pc.pcie(d)
    if e != null:
        print(e.link_speed_name())
    print(len(pc.extended(d)))

from core use len
use dma
use dma.dma_errors as derr
use dma.dma_descriptor as dd
use dma.dma_coherency as dc
use dma.dma_mapping as dm
b := dma.alloc(8192)
sg := dma.scatter(65536, 65536)
sg.add(b.phys, 8192)
t := dma.alloc(4096)
print(dd.write_ahci_prdt(t.addr, sg, true))
print(dd.ahci_prdt_length(t.addr, 1))
lb := dma.alloc(4096)
p := dd.nvme_prp(b.phys, 8192, lb)
print(p[1])
print(len(derr.violations(b.phys + 1, 100, 0xFFFFFF, 4, 65536)))
z := dc.Ownership(dma.map(b.addr, 4096, dma.TO_DEVICE, dma.MASK_32))
z.cpu_write32(0, 7)
z.give_to_device()
try:
    z.cpu_read32(0)
catch e:
    print(e.type)
z.take_back()
print(z.cpu_read32(0))
l := dd.DescriptorLayout(16)
l.field("n", 8, 4)
l.write(t.addr, "n", 512)
print(l.read(t.addr, "n"))

# Sans OS (QEMU) : paquet dma compilé en natif — tampons, rebond, segments / PRD, réserve, anneau, moteur.
use hw
use dma
use dma.dma_buffer as db
use dma.dma_transfer as dt
from dma.dma_transfer use Transfer

dma.low_zone(0x20000, 0x60000)
b := dma.alloc(10000)
b.write32(16, 0xDEADBEEF)
print("tampon : " + str(b.addr % 4096) + " " + str(b.pages) + " " + str(b.read8(16) == 0xEF))
print("chaîne : " + str(b.write_str(100, "Bonjour")) + " " + b.read_str(100, 7))
high := hw.alloc_pages(1)       # tas des pages du noyau : au-delà de 32 Mio
hw.store_string("données hautes", high)
mp := dma.map(high, 15, dma.TO_DEVICE, dma.MASK_24)
mp.sync_for_device()
print("rebond : " + str(mp.bounced()) + " " + str(mp.device_addr < 0x1000000) + " " + hw.string_at(mp.device_addr, 15) + " " + str(db.low_zone_free()))
mp.unmap()
print("zone basse rendue : " + str(db.low_zone_free()))
sg := dma.scatter(8192, 65536)
sg.add(0xF000, 0x3000)
sg.add(0x12000, 0x5000)
prd := dma.alloc(4096)
n := sg.write_prd(prd.addr)
print("segments : " + str(n) + " " + str(sg.total()) + " " + str(prd.read16(8 * (n - 1) + 6)))
p := dma.pool(40)
x := p.alloc()
p.release(x)
print("réserve : " + str(p.alloc() == x) + " " + str(x % 64))
r := dma.ring(8, 16, 128)
print("anneau : " + str(r.phys() % 128) + " " + str(r.produce()) + " " + str(r.consume()))
src := dma.alloc(2500)
dst := dma.alloc(2500)
src.fill(0, 2500, 7)
e := dt.MemcpyEngine(1000)
t := Transfer(src.addr, dst.addr, 2500, dt.MEM_TO_MEM)
e.submit(t)
print("moteur : " + str(e.run_all()) + " " + str(dst.read8(2499)) + " " + dt.state_name(t.state))

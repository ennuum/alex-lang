# Paquet dma dans la machine simulée : tampons, rebond (masque 24 bits), listes de segments et tables PRD,
# réserve de descripteurs, anneau, moteur logiciel, contrôleur ISA 8237 (ports observés).
from core use len
from collections use append
use hw
use dma
use dma.dma_buffer as db
use dma.dma_mapping as dm
use dma.dma_transfer as dt

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

hw.sim_reset(64 * 1024 * 1024, 1024 * 1024)       # tas des pages à partir de 1 Mio
b := dma.alloc(10000)
check(b.addr % 4096 == 0 and b.phys == b.addr and b.pages == 3, "tampon aligné, 3 pages")
check(b.read64(0) == 0 and b.read8(9999) == 0, "mis à zéro")
b.write32(16, 0xDEADBEEF)
check(b.read32(16) == 0xDEADBEEF and b.read8(16) == 0xEF, "lecture / écriture petit-boutiste")
check(b.write_str(100, "Bonjour") == 7 and b.read_str(100, 7) == "Bonjour", "chaînes")
erreur := ""
try:
    b.read32(9998)
catch e:
    erreur = e.type
check(erreur == "MemoryError", "hors limites")
a := dma.alloc_aligned(4096, 65536)
check(a.phys % 65536 == 0, "alignement 64 Kio")
check(not a.crosses(65536) and a.fits(dma.MASK_24), "frontière et masque")

# ---- correspondances : zone haute (32 Mio) vue par un périphérique ISA (24 bits) -> rebond ----
high := 32 * 1024 * 1024
hw.store_string("données hautes", high)
mp := dma.map(high, 15, dma.TO_DEVICE, dma.MASK_24)
check(mp.bounced() and mp.device_addr < 0x1000000, "rebond sous 16 Mio")
mp.sync_for_device()
check(hw.string_at(mp.device_addr, 15) == "données hautes", "sync_for_device")
mp.unmap()
mp2 := dma.map(high + 4096, 8, dma.FROM_DEVICE, dma.MASK_24)
hw.store_string("RÉPONSE", mp2.device_addr)       # le périphérique écrit dans le tampon de rebond
mp2.sync_for_cpu()
check(hw.string_at(high + 4096, 8) == "RÉPONSE", "sync_for_cpu")
mp2.unmap()
mp3 := dma.map(b.addr, 64, dma.BIDIRECTIONAL, dma.MASK_32)
check(not mp3.bounced() and mp3.device_addr == b.addr, "pas de rebond sous 4 Gio")
mp4 := dm.map_region_bounded(0x1F000, 0x2000, dm.TO_DEVICE, dm.MASK_32, 65536)
check(mp4.bounced() and mp4.device_addr % 65536 == 0, "frontière de 64 Kio : rebond aligné")

# ---- segments ----
sg := dma.scatter(8192, 65536)
sg.add(0xF000, 0x3000)            # traverse 64 Kio à 0x10000
check(sg.count() == 2 and sg.segments[0].length == 0x1000 and sg.segments[1].addr == 0x10000, "découpe à la frontière")
sg.add(0x12000, 0x5000)           # contigu à 0x12000 : fusion jusqu'à 8 Kio
check(sg.total() == 0x8000, "total")
check(sg.segments[1].length == 8192, "fusion bornée par max_segment : " + str(sg.segments[1].length))
prd := dma.alloc(4096)
n := sg.write_prd(prd.addr)
check(n == sg.count() and prd.read32(0) == 0xF000 and prd.read16(4) == 0x1000, "table PRD")
check(prd.read16(8 * (n - 1) + 6) == 0x8000 and prd.read16(6) == 0, "fin de table")

# ---- réserve et anneau ----
p := dma.pool(40)
check(p.block == 64 and p.per_page == 64, "blocs de 64")
x := p.alloc()
y := p.alloc()
check(x % 64 == 0 and y != x and p.used == 2, "deux blocs")
p.release(x)
check(p.alloc() == x, "bloc réutilisé")
r := dma.ring(8, 16, 128)
check(r.phys() % 128 == 0 and r.bytes() == 128, "anneau")
for k in 0..8:
    r.produce()
check(r.full() and r.produce() == -1, "anneau plein")
check(r.consume() == 0 and r.space() == 1 and r.produce() == 0, "rotation")
check(r.desc(9) == r.desc(1), "indice modulo")

# ---- moteur logiciel ----
e := dt.MemcpyEngine(1000)
src := dma.alloc(2500)
dst := dma.alloc(2500)
src.fill(0, 2500, 7)
t := dt.Transfer(src.addr, dst.addr, 2500, dt.MEM_TO_MEM)
fini := []
t.then((tr) => append(fini, tr.id))
check(e.submit(t) and t.id == 1, "soumis")
e.poll()
check(t.done_bytes == 1000 and t.state == dt.RUNNING and t.progress() == 0.4, "progression")
e.run_all()
check(t.finished() and dst.read8(2499) == 7 and len(fini) == 1, "terminé, rappel")
check(dma.copy(dst.addr, b.addr + 100, 7) == 7 and dst.read_str(0, 7) == "Bonjour", "dma.copy")

# ---- 8237 ----
hw.sim_trace(true)
isa := dt.Isa8237()
isa.setup(2, 0x8000, 512, dt.ISA_WRITE, false)
isa.enable(2)
log := hw.sim_trace_log()
outs := [ev[1] for ev in log if ev[0] == "out"]
check(outs[0] == 0x0A and outs[1] == 0x0C and outs[2] == 4 and outs[4] == 0x81, "ports du canal 2")
vals := [ev[3] for ev in log if ev[0] == "out"]
check(vals[2] == 0 and vals[3] == 0x80 and vals[4] == 0 and vals[6] == 0xFF and vals[7] == 1, "adresse, page, compte 511")
check(vals[8] == 0x46 and vals[9] == 2, "mode écriture unique canal 2, démasqué")
erreur = ""
try:
    isa.setup(1, 0xFF00, 512, dt.ISA_READ, false)
catch e2:
    erreur = e2.type
check(erreur == "ArgumentError", "frontière de 64 Kio refusée")
hw.sim_trace(false)
print("dma simulé : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")

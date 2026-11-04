# Pilote Bochs (DISPI) et 2D logicielle dans la machine simulée : carte simulée (ports 0x1CE / 0x1CF,
# tampon linéaire en MMIO), modes, double tampon, tampon de commandes, mémoire vidéo, capacités.
from core use len
from collections use contains_key
use hw
use gpu_driver
use gpu_driver.gpu_command as gcmd
use gpu_driver.gpu_memory_manager as gmm
use gpu_driver.gpu_capabilities as gcap

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

class SimBga:
    func init():
        self.regs = {0: 0xB0C5, 10: 64}           # 4 Mio
        self.index = 0
        self.mem = {}
    func io_read(port, size):
        if port == 0x1CE:
            return self.index
        caps := contains_key(self.regs, 4) and self.regs[4] & 2 != 0
        if caps and self.index == 1:
            return 1600
        if caps and self.index == 2:
            return 1200
        if contains_key(self.regs, self.index):
            return self.regs[self.index]
        return 0
    func io_write(port, size, v):
        if port == 0x1CE:
            self.index = v
        else:
            self.regs[self.index] = v
    func mem_read(off, size):
        if contains_key(self.mem, off):
            return self.mem[off]
        return 0
    func mem_write(off, size, v):
        self.mem[off] = v

hw.sim_reset(16 * 1024 * 1024, 4 * 1024 * 1024)
carte := SimBga()
hw.sim_map_ports(0x1CE, 2, carte)
hw.sim_map_mmio(0xFD000000, 4 * 1024 * 1024, carte)
g := gpu_driver.BochsGpu(0xFD000000, 0)
check(g.version == 0xB0C5 and g.vram == 4194304, "détection DISPI 5, 4 Mio")
erreur := ""
try:
    g.set_mode(2048, 2048, 32, false)
catch e:
    erreur = e.type
check(erreur == "UnsupportedDevice", "mode trop grand refusé")
g.set_mode(32, 24, 32, true)
check(carte.regs[1] == 32 and carte.regs[2] == 24 and carte.regs[7] == 48 and carte.regs[4] == 0x41, "registres du mode")
s := g.back_surface()
check(s.base == g.lfb + 32 * 24 * 4, "image cachée après l'affichée")
cb := gcmd.CommandBuffer()
cb.clear(0x000010)
cb.fill_rect(4, 4, 8, 4, 0xFF0000)
cb.line(0, 0, 31, 23, 0xFFFFFF)
cb.blit(4, 4, 20, 10, 4, 4)
cb.fence(7)
check(g.submit(cb) == 5 and g.engine.fences == [7], "tampon de commandes")
check(s.pixel(5, 5) == 0xFF0000 and s.pixel(21, 11) == 0xFF0000 and s.pixel(0, 0) == 0xFFFFFF and s.pixel(31, 0) == 0x10, "points dessinés")
check(g.front_surface().pixel(5, 5) == 0, "image affichée intacte")
g.flip()
check(carte.regs[9] == 24 and g.front_surface().pixel(5, 5) == 0xFF0000, "flip")
check(s.fill_rect(-5, -5, 10, 10, 1) == 25, "découpe aux bords")
c1 := s.checksum(0, 0, 32, 24)
s.set_pixel(3, 3, 2)
check(s.checksum(0, 0, 32, 24) != c1, "somme de contrôle")
# mémoire vidéo
mm := gmm.GpuMemoryManager(1048576, 10000, 4096)
check(mm.reserved == 12288, "réserve arrondie")
a := mm.allocate(5000, "a")
b := mm.allocate(4096, "b")
check(a.offset == 12288 and b.offset == 20480, "allocations")
mm.release(a)
c := mm.allocate(4096, "c")
check(c.offset == 12288, "trou réutilisé")
check(mm.allocate(2000000, "trop") == null and mm.failures == 1, "plus de place")
check(not mm.set_reserved(16384) and mm.set_reserved(8192), "réserve et allocations")
# capacités
caps := g.capabilities()
check(caps.supports(640, 480, 32) and not caps.supports(640, 480, 12), "supports")
check(caps.best_mode(800, 600).describe() == "800x600x32", "meilleur mode")
check(caps.can_double_buffer(gcap.VideoMode(640, 480, 32)) and not caps.can_double_buffer(gcap.VideoMode(1024, 768, 32)), "double tampon possible")
print("gpu simulé : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")

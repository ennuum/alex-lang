# Sans OS (QEMU, carte stdvga) : pilote Bochs / QEMU (DISPI) — détection, capacités, mode 640x480x32 avec
# double tampon, dessin par tampon de commandes, relecture des points, flip, surface hors écran, VRAM.
use hw
use gpu_driver
use gpu_driver.gpu_command as gcmd
from gpu_driver.gpu_command use CommandBuffer
from core use len

g := gpu_driver.find_bochs()
if g == null:
    print("pas de carte Bochs")
else:
    print(g.describe())
    caps := g.capabilities()
    print(caps.describe())
    m := caps.best_mode(1000, 700)
    if m != null:
        print("meilleur mode sous 1000x700 : " + m.describe())
    g.set_mode(640, 480, 32, true)
    print(g.describe() + " ; activé " + str(g.enabled()))
    cb := CommandBuffer()
    cb.clear(gcmd.rgb(0, 0, 64))
    cb.fill_rect(100, 100, 200, 100, 0xFF8800)
    cb.line(0, 0, 639, 479, 0xFFFFFF)
    cb.pixel(5, 470, 0x00FF00)
    cb.blit(100, 100, 400, 300, 50, 50)
    cb.fence(1)
    print("commandes : " + str(g.submit(cb)) + ", barrières " + str(g.engine.fences))
    s := g.back_surface()
    print("points : " + str(s.pixel(150, 150)) + " " + str(s.pixel(320, 240)) + " " + str(s.pixel(5, 470)) + " " + str(s.pixel(420, 320)) + " " + str(s.pixel(600, 20)))
    avant := g.displayed_offset()
    g.flip()
    print("flip : décalage " + str(avant) + " -> " + str(g.displayed_offset()))
    print("image affichée = image dessinée : " + str(g.front_surface().checksum(0, 0, 640, 480) == s.checksum(0, 0, 640, 480)))
    o := g.offscreen(64, 64)
    if o != null:
        o.clear(0x123456)
        print("hors écran : " + str(o.pixel(10, 10)) + " ; " + g.memory.describe())

# Paquet gpu : informations (nvidia-smi analysé), mémoire du périphérique (types, capacité), calcul par noyaux
# en série et en parallèle (fils), noyau utilisateur, matmul, convolution, histogramme.
from core use len
use thread
use gpu
use gpu.gpu_info as gi
use gpu.gpu_memory as gm
use gpu.gpu_compute as gc
use gpu.gpu_device as gd

func cube(debut, fin, xs):
    return [xs[i] * xs[i] * xs[i] for i in debut..fin]

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

if thread.is_main():
    l := gi.parse_nvidia_line("00000000:01:00.0, NVIDIA GeForce RTX 3060, 550.54, 12288, 512, 3, 31, 210, 405, 15.2")
    check(l["name"] == "NVIDIA GeForce RTX 3060" and l["mem_total"] == 12884901888 and l["temp"] == 31.0 and l["util"] == 3, "ligne nvidia-smi")
    check(gi.parse_nvidia_line("x, y") == null, "ligne invalide")
    check(gi._active_clock("0: 500Mhz\n1: 1800Mhz *\n") == 1800, "fréquence amdgpu active")

    mem := gm.GpuMemory(64)
    a := mem.upload([1.5, 2.5, 3.5, 4.5], "float32", [2, 2])
    check(a.get(1, 0) == 3.5 and a.size_bytes() == 16 and mem.used == 16, "tampon 2x2")
    b := mem.upload([300, -1], "uint8")
    check(b.download() == [44, 255], "conversion uint8")
    i8 := mem.upload([200], "int8")
    check(i8.get(0) == -56, "conversion int8")
    erreur := ""
    try:
        mem.zeros("float64", [10])
    catch e:
        erreur = e.type
    check(erreur == "MemoryError", "capacité dépassée")
    mem.free(a)
    check(mem.used == 3 and mem.peak == 19 and mem.live() == 2, "libération")
    erreur = ""
    try:
        a.get(0)
    catch e2:
        erreur = e2.type
    check(erreur == "MemoryError", "tampon libéré")

    xs := [1.0 * i for i in 0..1000]
    ys := [2.0 for i in 0..1000]
    for backend in ["serial", "threads"]:
        dev := gc.ComputeDevice(backend, 2)
        s := dev.saxpy(3.0, xs, ys)
        check(len(s) == 1000 and s[10] == 32.0 and s[999] == 2999.0, backend + " : saxpy")
        check(dev.sum(xs) == 499500.0 and dev.dot(xs, ys) == 999000.0, backend + " : réductions")
        c := dev.dispatch(cube, 300, [xs], 64)
        check(len(c) == 300 and c[7] == 343.0, backend + " : noyau utilisateur")
        m := dev.matmul([1.0, 2.0, 3.0, 4.0, 5.0, 6.0], [7.0, 8.0, 9.0, 10.0, 11.0, 12.0], 2, 3, 2)
        check(m == [58.0, 64.0, 139.0, 154.0], backend + " : matmul " + str(m))
        img := [0.0 for i in 0..25]
        img[12] = 1.0
        conv := dev.convolve2d(img, 5, 5, [0.0, 1.0, 0.0, 1.0, 4.0, 1.0, 0.0, 1.0, 0.0], 3, 3)
        check(conv[12] == 4.0 and conv[7] == 1.0 and conv[0] == 0.0, backend + " : convolution")
        h := dev.histogram([i % 4 for i in 0..1000], 4)
        check(h == [250, 250, 250, 250], backend + " : histogramme")
        check(dev.map_lut([0, 1, 2], [10, 20, 30]) == [10, 20, 30], backend + " : table")
        dev.shutdown()
    d := gd.software(2)
    buf := d.memory.upload([1.0, 2.0, 3.0])
    check(d.compute.scale(2.0, buf.download()) == [2.0, 4.0, 6.0] and d.name() != "", "périphérique logiciel")
    d.close()
    check(len(gpu.list()) >= 0, "inventaire")
    print("gpu : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")

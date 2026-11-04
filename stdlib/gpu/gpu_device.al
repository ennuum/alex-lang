# ALEX STANDARD LIBRARY — gpu.gpu_device
#
# Un périphérique graphique / de calcul pour l'application : la carte (gpu.gpu_info) quand il y en a une, et
# le moyen d'y calculer (gpu.gpu_compute.ComputeDevice) et d'y placer des données (gpu.gpu_memory.GpuMemory).
# Sans carte, ou sans dorsal matériel, le périphérique « logiciel » (processeur, plusieurs fils) est fourni.
#
#   use gpu.gpu_device as gd
#   dev := gd.default()
#   print(dev.describe())
#   buf := dev.memory.upload([1.0, 2.0])
#   r := dev.compute.scale(3.0, buf.download())
#   dev.close()

from core use len
use os
use gpu.gpu_info as gi
use gpu.gpu_memory as gm
use gpu.gpu_compute as gc
use hardware.hardware_info as _hi

class GpuDevice:
    # info : gpu_info.GpuInfo ou null (périphérique logiciel) ; backend : "threads" ou "serial".
    func init(info=null, backend="threads", workers=null):
        self.info = info
        self.compute = gc.ComputeDevice(backend, workers)
        cap := null
        if info != null and info.vram_total != null:
            cap = info.vram_total
        if cap == null:
            m := _hi.memory()
            cap = m.available // 2 if m.available != null else 1073741824
        self.memory = gm.GpuMemory(cap)

    func is_software():
        return true

    func name():
        if self.info == null:
            return "logiciel (" + self.compute.name() + ")"
        return self.info.name() + " — calcul : " + self.compute.name()

    func describe():
        return self.name() + ", " + self.memory.describe()

    func close():
        self.compute.shutdown()

func devices(backend="threads", workers=null):
    out := [GpuDevice(g, backend, workers) for g in gi.gpus()]
    if len(out) == 0:
        out = [GpuDevice(null, backend, workers)]
    return out

func default(backend="threads", workers=null):
    g := gi.primary()
    return GpuDevice(g, backend, workers)

func software(workers=null):
    return GpuDevice(null, "threads", workers)

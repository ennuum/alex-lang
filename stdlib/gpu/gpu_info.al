# ALEX STANDARD LIBRARY — gpu.gpu_info
#
# Informations et télémétrie des cartes graphiques (Linux) : modèle (table PCI), pilote, mémoire vidéo totale
# et utilisée, charge, fréquences, température, puissance, version du pilote — lues dans /sys/class/drm
# (amdgpu, i915 / xe, nouveau, virtio) et ses capteurs hwmon, ou par « nvidia-smi » pour le pilote NVIDIA.
# Les valeurs inconnues valent null.
#
#   use gpu.gpu_info as gi
#   for g in gi.gpus():
#       print(g.describe())                 # « NVIDIA GeForce RTX 3060 (nvidia 550.54) : 12 Gio, 31 °C, 3 % »
#   print(gi.gpus()[0].refresh().temperature)

from core use len, to_int, to_float
from collections use append
use string as _s
use process
use hardware._sys as _sys
use hardware.gpu as _hg
use pci.pci_ids as _ids

class GpuInfo:
    func init(hw):
        self.hw = hw                       # hardware.gpu.Gpu
        self.vendor = hw.vendor
        self.vendor_id = hw.vendor_id
        self.device_id = hw.device_id
        self.model = _known_name(_ids.device_name(hw.vendor_id, hw.device_id)) if hw.vendor_id != null and hw.device_id != null else null
        self.driver = hw.driver
        self.driver_version = null
        self.card = hw.card
        self.render_node = hw.render_node
        self.slot = hw.slot
        self.vram_total = hw.vram
        self.vram_used = null
        self.busy_percent = null
        self.temperature = null            # °C
        self.core_mhz = null
        self.memory_mhz = null
        self.power_watts = null
        self.refresh()

    func name():
        if self.model != null:
            if self.vendor != null:
                return self.vendor + " " + self.model
            return self.model
        if self.vendor != null:
            return self.vendor + " " + _sys.hex4(self.device_id)
        return "carte inconnue"

    # Relit les capteurs ; renvoie self.
    func refresh():
        if self.card != null:
            base := "/sys/class/drm/" + self.card + "/device"
            v := _sys.dec(_sys.read(base + "/mem_info_vram_total"))
            if v != null:
                self.vram_total = v
            self.vram_used = _sys.dec(_sys.read(base + "/mem_info_vram_used"))
            self.busy_percent = _sys.dec(_sys.read(base + "/gpu_busy_percent"))
            for h in _sys.list(base + "/hwmon"):
                hp := base + "/hwmon/" + h
                t := _sys.dec(_sys.read(hp + "/temp1_input"))
                if t != null:
                    self.temperature = t / 1000.0
                p := _sys.dec(_sys.read(hp + "/power1_average"))
                if p != null:
                    self.power_watts = p / 1000000.0
                f := _sys.dec(_sys.read(hp + "/freq1_input"))
                if f != null:
                    self.core_mhz = f // 1000000
            mhz := _active_clock(_sys.read(base + "/pp_dpm_sclk"))
            if mhz != null:
                self.core_mhz = mhz
            mm := _active_clock(_sys.read(base + "/pp_dpm_mclk"))
            if mm != null:
                self.memory_mhz = mm
            cur := _sys.dec(_sys.read("/sys/class/drm/" + self.card + "/gt_cur_freq_mhz"))
            if cur != null:
                self.core_mhz = cur
        if self.driver == "nvidia":
            self._nvidia()
        return self

    func _nvidia():
        if process.which("nvidia-smi") == null:
            return
        r := process.Command("nvidia-smi").args(["--query-gpu=pci.bus_id,name,driver_version,memory.total,memory.used,utilization.gpu,temperature.gpu,clocks.gr,clocks.mem,power.draw", "--format=csv,noheader,nounits"]).run(null, 10)
        if r.code != 0:
            return
        for line in _s.split(r.stdout, "\n"):
            parsed := parse_nvidia_line(line)
            if parsed == null:
                continue
            if self.slot != null and not _s.ends_with(_s.lower(parsed["bus"]), _s.lower(self.slot)):
                continue
            self.model = parsed["name"]
            self.vendor = "NVIDIA"
            self.driver_version = parsed["driver"]
            self.vram_total = parsed["mem_total"]
            self.vram_used = parsed["mem_used"]
            self.busy_percent = parsed["util"]
            self.temperature = parsed["temp"]
            self.core_mhz = parsed["clock"]
            self.memory_mhz = parsed["mem_clock"]
            self.power_watts = parsed["power"]
            return

    func vram_free():
        if self.vram_total == null or self.vram_used == null:
            return null
        return self.vram_total - self.vram_used

    func describe():
        t := self.name()
        if self.driver != null:
            t = t + " (" + self.driver
            if self.driver_version != null:
                t = t + " " + self.driver_version
            t = t + ")"
        parts := []
        if self.vram_total != null:
            append(parts, _size(self.vram_total))
        if self.temperature != null:
            append(parts, str(to_int(self.temperature)) + " °C")
        if self.busy_percent != null:
            append(parts, str(self.busy_percent) + " %")
        if self.core_mhz != null:
            append(parts, str(self.core_mhz) + " MHz")
        if len(parts) > 0:
            t = t + " :"
            k := 0
            while k < len(parts):
                t = t + (" " if k == 0 else ", ") + parts[k]
                k += 1
        return t

func _known_name(name):
    if name == null or _s.starts_with(name, "périphérique "):
        return null
    return name

func _size(n):
    if n >= 1073741824:
        return str(n // 1073741824) + " Gio"
    return str(n // 1048576) + " Mio"

# Ligne active (marquée « * ») d'un fichier pp_dpm_* d'amdgpu : MHz, ou null.
func _active_clock(text):
    if text == null:
        return null
    for line in _s.split(text, "\n"):
        if _s.contains(line, "*"):
            k := _s.find(line, ":")
            m := _s.find(line, "Mhz")
            if m < 0:
                m = _s.find(line, "MHz")
            if k >= 0 and m > k:
                return to_int(_s.trim(_s.slice(line, k + 1, m)))
    return null

func _num(text):
    t := _s.trim(text)
    if t == "" or _s.contains(t, "N/A") or _s.contains(t, "["):
        return null
    try:
        return to_float(t)
    catch e:
        return null

# Une ligne CSV de nvidia-smi (requête de GpuInfo._nvidia) -> dict, ou null.
func parse_nvidia_line(line):
    p := [_s.trim(x) for x in _s.split(line, ",")]
    if len(p) < 10:
        return null
    mt := _num(p[3])
    mu := _num(p[4])
    return {"bus": p[0], "name": p[1], "driver": p[2],
            "mem_total": to_int(mt * 1048576) if mt != null else null,
            "mem_used": to_int(mu * 1048576) if mu != null else null,
            "util": to_int(_num(p[5])) if _num(p[5]) != null else null,
            "temp": _num(p[6]), "clock": to_int(_num(p[7])) if _num(p[7]) != null else null,
            "mem_clock": to_int(_num(p[8])) if _num(p[8]) != null else null, "power": _num(p[9])}

func gpus():
    return [GpuInfo(g) for g in _hg.gpus()]

func primary():
    gs := gpus()
    for g in gs:
        if g.hw.boot_vga:
            return g
    return gs[0] if len(gs) > 0 else null

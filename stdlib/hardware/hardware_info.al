# ALEX STANDARD LIBRARY — hardware.hardware_info
#
# Ce que la machine EST : processeur(s) (fabricant, modèle, cœurs, fils, fréquence, caches, jeux d'instructions),
# mémoire (totale, disponible, échange), micrologiciel et carte mère (DMI : fabricant, produit, BIOS), noyau,
# virtualisation (hyperviseur), zones NUMA. Linux : /proc/cpuinfo, /proc/meminfo, /sys/devices/system,
# /sys/class/dmi/id ; ailleurs, ce que os.system_info() donne.
#
#   use hardware.hardware_info as hi
#   c := hi.cpu()
#   print(c.model, c.cores, c.threads, c.mhz, c.has("avx2"))
#   m := hi.memory()
#   print(m.total_mib(), m.available_mib(), m.used_percent())
#   print(hi.summary())                          # texte de quelques lignes
#
# Toutes les valeurs absentes valent null. Lecture seule, sans droits (le numéro de série DMI exige root : null).
# ALEX_HW_ROOT (ou hardware._sys.set_root) fait lire une copie de /proc et /sys (tests).

from core use len, type, to_int, to_float
from collections use append, contains_key, keys, sort
use string as _s
use os as _os
use hardware._sys as _sys

# ---------------------------------------------------------------- processeur
class CacheInfo:
    func init(level, kind, size_kib, shared_by):
        self.level = level            # 1, 2, 3
        self.kind = kind              # "Data", "Instruction", "Unified"
        self.size_kib = size_kib
        self.shared_by = shared_by    # nombre de processeurs logiques qui la partagent

    func describe():
        return "L" + str(self.level) + " " + _s.lower(self.kind) + " " + str(self.size_kib) + " Kio"

class CpuInfo:
    func init():
        self.vendor = null            # GenuineIntel, AuthenticAMD, ARM...
        self.model = null             # « Intel(R) Core(TM) i7-8565U CPU @ 1.80GHz »
        self.family = null
        self.model_number = null
        self.stepping = null
        self.microcode = null
        self.arch = _os.arch()
        self.sockets = 1
        self.cores = null             # cœurs physiques (tous sockets)
        self.threads = null           # processeurs logiques
        self.mhz = null               # fréquence courante (moyenne)
        self.max_mhz = null           # fréquence maximale (cpufreq)
        self.bogomips = null
        self.flags = []               # sse4_2, avx2, aes, vmx...
        self.bugs = []
        self.address_bits = null      # [physiques, virtuelles]
        self.caches = []              # CacheInfo
        self.online = null            # « 0-7 »

    # Le processeur a-t-il ce jeu d'instructions / cette fonction (drapeau de /proc/cpuinfo) ?
    func has(flag):
        f := _s.lower(flag)
        for x in self.flags:
            if x == f:
                return true
        return false

    # Niveau x86-64 (1 à 4) d'après les drapeaux, ou null hors x86.
    func x86_level():
        if not self.has("lm"):
            return null
        level := 1
        if self.has("cx16") and self.has("lahf_lm") and self.has("popcnt") and self.has("sse4_1") and self.has("sse4_2") and self.has("ssse3"):
            level = 2
            if self.has("avx") and self.has("avx2") and self.has("bmi1") and self.has("bmi2") and self.has("f16c") and self.has("fma") and self.has("movbe") and self.has("xsave"):
                level = 3
                if self.has("avx512f") and self.has("avx512bw") and self.has("avx512cd") and self.has("avx512dq") and self.has("avx512vl"):
                    level = 4
        return level

    func virtualization():
        if self.has("vmx"):
            return "VT-x"
        if self.has("svm"):
            return "AMD-V"
        return null

    func describe():
        t := str(self.model)
        if self.cores != null:
            t = t + " — " + str(self.cores) + " cœurs / " + str(self.threads) + " fils"
        if self.mhz != null:
            t = t + ", " + str(to_int(self.mhz)) + " MHz"
        return t

    func to_dict():
        return {"vendor": self.vendor, "model": self.model, "arch": self.arch, "sockets": self.sockets, "cores": self.cores,
                "threads": self.threads, "mhz": self.mhz, "max_mhz": self.max_mhz, "flags": self.flags,
                "caches": [c.describe() for c in self.caches]}

func _kv(line):
    k := _s.find(line, ":")
    if k < 0:
        return null
    return [_s.trim(_s.slice(line, 0, k)), _s.trim(_s.slice(line, k + 1))]

func _to_float(text):
    if text == null or text == "":
        return null
    try:
        return to_float(text)
    catch e:
        return null

func _to_int(text):
    if text == null:
        return null
    t := _s.trim(text)
    if t == "":
        return null
    try:
        return to_int(t)
    catch e:
        return null

# Analyse un texte au format /proc/cpuinfo (x86 ou ARM) ; renvoie un CpuInfo.
func parse_cpuinfo(text):
    c := CpuInfo()
    if text == null:
        return c
    threads := 0
    mhz_sum := 0.0
    mhz_n := 0
    physical := {}
    cores := {}         # (socket, cœur) -> vrai
    socket := "0"
    for line in _s.split(text, "\n"):
        kv := _kv(line)
        if kv == null:
            continue
        k := kv[0]
        v := kv[1]
        if k == "processor":
            threads += 1
        elif k == "vendor_id" or k == "CPU implementer":
            if c.vendor == null:
                c.vendor = v
        elif k == "model name" or k == "Model" or k == "Hardware":
            if c.model == null:
                c.model = v
        elif k == "cpu family":
            c.family = _to_int(v)
        elif k == "model":
            c.model_number = _to_int(v)
        elif k == "stepping":
            c.stepping = _to_int(v)
        elif k == "microcode":
            c.microcode = v
        elif k == "cpu MHz":
            f := _to_float(v)
            if f != null:
                mhz_sum += f
                mhz_n += 1
        elif k == "bogomips" or k == "BogoMIPS":
            if c.bogomips == null:
                c.bogomips = _to_float(v)
        elif k == "flags" or k == "Features":
            if len(c.flags) == 0:
                c.flags = _sys.split_words(v)
        elif k == "bugs":
            if len(c.bugs) == 0:
                c.bugs = _sys.split_words(v)
        elif k == "physical id":
            socket = v
            physical[v] = true
        elif k == "core id":
            cores[socket + ":" + v] = true
        elif k == "address sizes":
            w := _sys.split_words(v)
            if len(w) >= 4:
                c.address_bits = [_to_int(w[0]), _to_int(w[3])]
    c.threads = threads
    if len(physical) > 0:
        c.sockets = len(physical)
    if len(cores) > 0:
        c.cores = len(cores)
    elif threads > 0:
        c.cores = threads
    if mhz_n > 0:
        c.mhz = mhz_sum / mhz_n
    if c.vendor != null and c.vendor == "0x41":
        c.vendor = "ARM"
    return c

func _size_kib(text):
    if text == null:
        return null
    t := _s.trim(text)
    mult := 1
    if _s.ends_with(t, "K"):
        t = _s.slice(t, 0, len(t) - 1)
    elif _s.ends_with(t, "M"):
        t = _s.slice(t, 0, len(t) - 1)
        mult = 1024
    return _to_int(t) * mult if _to_int(t) != null else null

func _cpu_list_count(text):
    # « 0-3,6,8-9 » -> 7
    if text == null or _s.trim(text) == "":
        return 0
    n := 0
    for part in _s.split(_s.trim(text), ","):
        k := _s.find(part, "-")
        if k < 0:
            n += 1
        else:
            n += _to_int(_s.slice(part, k + 1)) - _to_int(_s.slice(part, 0, k)) + 1
    return n

# Processeur de la machine (CpuInfo).
func cpu():
    c := parse_cpuinfo(_sys.read("/proc/cpuinfo"))
    if c.threads == 0 or c.threads == null:
        c.threads = _os.cpu_count()
        if c.cores == null or c.cores == 0:
            c.cores = c.threads
    base := "/sys/devices/system/cpu"
    c.online = _sys.read(base + "/online")
    mx := _to_int(_sys.read(base + "/cpu0/cpufreq/cpuinfo_max_freq"))
    if mx != null:
        c.max_mhz = mx / 1000.0
    for idx in _sys.list(base + "/cpu0/cache"):
        if not _s.starts_with(idx, "index"):
            continue
        d := base + "/cpu0/cache/" + idx
        level := _to_int(_sys.read(d + "/level"))
        kind := _sys.read(d + "/type")
        size := _size_kib(_sys.read(d + "/size"))
        shared := _cpu_list_count(_sys.read(d + "/shared_cpu_list"))
        if level != null:
            append(c.caches, CacheInfo(level, kind, size, shared))
    if c.model == null:
        info := _os.system_info()
        if contains_key(info, "cpu"):
            c.model = info["cpu"]
    return c

# ---------------------------------------------------------------- mémoire
class MemoryInfo:
    func init(values):
        self.values = values          # dict brut (Kio) de /proc/meminfo
        self.total = _get(values, "MemTotal")              # octets
        self.free = _get(values, "MemFree")
        self.available = _get(values, "MemAvailable")
        if self.available == null:
            self.available = self.free
        self.buffers = _get(values, "Buffers")
        self.cached = _get(values, "Cached")
        self.swap_total = _get(values, "SwapTotal")
        self.swap_free = _get(values, "SwapFree")
        self.huge_page_size = _get(values, "Hugepagesize")
        self.shared = _get(values, "Shmem")

    func used():
        if self.total == null or self.available == null:
            return null
        return self.total - self.available

    func used_percent():
        if self.total == null or self.total == 0 or self.used() == null:
            return null
        return 100.0 * self.used() / self.total

    func total_mib():
        return null if self.total == null else self.total // 1048576

    func available_mib():
        return null if self.available == null else self.available // 1048576

    func swap_used():
        if self.swap_total == null or self.swap_free == null:
            return null
        return self.swap_total - self.swap_free

    func describe():
        if self.total == null:
            return "mémoire inconnue"
        return str(self.total_mib()) + " Mio, " + str(self.available_mib()) + " Mio disponibles (" + str(to_int(self.used_percent())) + " % utilisés)"

    func to_dict():
        return {"total": self.total, "available": self.available, "free": self.free, "cached": self.cached,
                "swap_total": self.swap_total, "swap_free": self.swap_free}

func _get(values, key):
    if contains_key(values, key):
        return values[key]
    return null

# Analyse un texte au format /proc/meminfo ; valeurs en octets (sauf les compteurs sans unité).
func parse_meminfo(text):
    values := {}
    if text != null:
        for line in _s.split(text, "\n"):
            kv := _kv(line)
            if kv == null:
                continue
            w := _sys.split_words(kv[1])
            if len(w) == 0:
                continue
            n := _to_int(w[0])
            if n == null:
                continue
            if len(w) > 1 and _s.lower(w[1]) == "kb":
                n = n * 1024
            values[kv[0]] = n
    return MemoryInfo(values)

func memory():
    return parse_meminfo(_sys.read("/proc/meminfo"))

# Nœuds NUMA : list de dict node, cpus (texte), memory (octets).
func numa_nodes():
    out := []
    base := "/sys/devices/system/node"
    for n in (_sys.list(base)):
        if not _s.starts_with(n, "node"):
            continue
        mem := null
        info := _sys.read(base + "/" + n + "/meminfo")
        if info != null:
            for line in _s.split(info, "\n"):
                if _s.contains(line, "MemTotal:"):
                    w := _sys.split_words(_s.slice(line, _s.find(line, "MemTotal:") + 9))
                    mem = _to_int(w[0]) * 1024
        append(out, {"node": _to_int(_s.slice(n, 4)), "cpus": _sys.read(base + "/" + n + "/cpulist"), "memory": mem})
    return out

# ---------------------------------------------------------------- micrologiciel / carte mère (DMI)
class FirmwareInfo:
    func init():
        d := "/sys/class/dmi/id/"
        self.system_vendor = _sys.read(d + "sys_vendor")
        self.product = _sys.read(d + "product_name")
        self.product_version = _sys.read(d + "product_version")
        self.board_vendor = _sys.read(d + "board_vendor")
        self.board = _sys.read(d + "board_name")
        self.bios_vendor = _sys.read(d + "bios_vendor")
        self.bios_version = _sys.read(d + "bios_version")
        self.bios_date = _sys.read(d + "bios_date")
        self.chassis_type = _to_int(_sys.read(d + "chassis_type"))
        self.serial = _sys.read(d + "product_serial")      # root seulement
        self.uefi = _sys.exists("/sys/firmware/efi")

    # Type de boîtier SMBIOS (« portable », « bureau », « serveur »...).
    func chassis():
        t := self.chassis_type
        if t == null:
            return null
        if t == 3 or t == 4 or t == 6 or t == 7 or t == 13 or t == 15 or t == 16:
            return "bureau"
        if t == 8 or t == 9 or t == 10 or t == 14 or t == 31 or t == 32:
            return "portable"
        if t == 30:
            return "tablette"
        if t == 17 or t == 23 or t == 28 or t == 29:
            return "serveur"
        if t == 1:
            return "autre"
        return "type " + str(t)

    func describe():
        parts := []
        if self.system_vendor != null:
            append(parts, self.system_vendor)
        if self.product != null:
            append(parts, self.product)
        t := _s.join(" ", parts) if len(parts) > 0 else "machine inconnue"
        if self.bios_version != null:
            t = t + " (BIOS " + str(self.bios_vendor) + " " + self.bios_version + ")"
        if self.uefi:
            t = t + ", UEFI"
        return t

func firmware():
    return FirmwareInfo()

# ---------------------------------------------------------------- hyperviseur
# Nom de l'hyperviseur si la machine est virtuelle (kvm, vmware, hyperv, xen, qemu, virtualbox, firecracker...),
# "inconnu" si le processeur l'annonce sans que son nom soit lisible, null sur une machine réelle.
func hypervisor():
    t := _sys.read("/sys/hypervisor/type")
    if t != null:
        return t
    fw := firmware()
    name := _s.lower(str(fw.system_vendor) + " " + str(fw.product))
    for pair in [["qemu", "qemu"], ["kvm", "kvm"], ["vmware", "vmware"], ["virtualbox", "virtualbox"], ["innotek", "virtualbox"],
                 ["microsoft corporation", "hyperv"], ["xen", "xen"], ["amazon ec2", "kvm"], ["google", "kvm"], ["parallels", "parallels"]]:
        if _s.contains(name, pair[0]):
            return pair[1]
    c := cpu()
    if c.has("hypervisor"):
        iomem := _sys.read("/proc/iomem")
        if iomem != null and _s.contains(iomem, "AMZNC"):
            return "firecracker"
        return "inconnu"
    return null

# ---------------------------------------------------------------- noyau
func kernel():
    return {"name": _os.name(), "release": _sys.read("/proc/sys/kernel/osrelease"), "version": _sys.read("/proc/sys/kernel/version"),
            "hostname": _os.hostname(), "arch": _os.arch(), "uptime": _uptime()}

func _uptime():
    t := _sys.read("/proc/uptime")
    if t == null:
        return null
    return _to_float(_sys.split_words(t)[0])

# Charge moyenne [1 min, 5 min, 15 min], ou null.
func load_average():
    t := _sys.read("/proc/loadavg")
    if t == null:
        return null
    w := _sys.split_words(t)
    return [_to_float(w[0]), _to_float(w[1]), _to_float(w[2])]

# ---------------------------------------------------------------- résumé
class HardwareInfo:
    func init():
        self.cpu = cpu()
        self.memory = memory()
        self.firmware = firmware()
        self.kernel = kernel()
        self.hypervisor = hypervisor()
        self.numa = numa_nodes()

    func describe():
        lines := []
        append(lines, "Machine     : " + self.firmware.describe())
        if self.hypervisor != null:
            append(lines, "Virtuelle   : " + self.hypervisor)
        append(lines, "Processeur  : " + self.cpu.describe())
        if len(self.cpu.caches) > 0:
            append(lines, "Caches      : " + _s.join(", ", [c.describe() for c in self.cpu.caches]))
        lvl := self.cpu.x86_level()
        if lvl != null:
            append(lines, "Niveau      : x86-64-v" + str(lvl))
        append(lines, "Mémoire     : " + self.memory.describe())
        append(lines, "Noyau       : " + str(self.kernel["name"]) + " " + str(self.kernel["release"]) + " (" + str(self.kernel["arch"]) + ")")
        return _s.join("\n", lines)

    func to_dict():
        return {"cpu": self.cpu.to_dict(), "memory": self.memory.to_dict(), "firmware": self.firmware.describe(),
                "kernel": self.kernel, "hypervisor": self.hypervisor}

func info():
    return HardwareInfo()

func summary():
    return info().describe()

# ALEX STANDARD LIBRARY — system.system_info
#
# Description de la machine : système (nom, version du noyau, distribution), processeur (nombre de cœurs,
# modèle), mémoire (totale, disponible, échange), disques, charge et durée de fonctionnement.
#
# Les valeurs viennent du système (sysconf, statvfs, getloadavg) et, sous Linux, de /proc et /etc/os-release.
# Une information indisponible sur la plateforme vaut null (jamais d'erreur). Tailles en octets, durées en
# secondes.
#
# Exemple
#   use system.system_info as info
#   m := info.memory()
#   print(info.cpu_model(), info.cpu_count(), "cœurs")
#   print(info.format_bytes(m["available"]), "libres sur", info.format_bytes(m["total"]))
#   print(info.summary())

from core use len, type, to_int, to_float
from collections use append, contains_key
use string as _s
use os as _os
use file as _file
use _native_os as _osn

func _read(path):
    try:
        if _os.isfile(path):
            return _file.read(path)
    catch e:
        return null
    return null

func _try(f):
    try:
        return f()
    catch e:
        return null

# ---------------------------------------------------------------- système
# « linux », « macos », « windows »...
func platform():
    return _os.platform()

func name():
    return _try(_os.name)

# Version du noyau (« 6.8.0-45-generic »).
func kernel_version():
    return _try(_os.version)

func arch():
    return _try(_os.arch)

func hostname():
    return _try(_os.hostname)

func username():
    return _try(_os.username)

# Champs de /etc/os-release (Linux) : {"NAME": ..., "VERSION_ID": ..., "ID": ..., "PRETTY_NAME": ...} ; {} ailleurs.
func os_release():
    out := {}
    text := _read("/etc/os-release")
    if text == null:
        text = _read("/usr/lib/os-release")
    if text == null:
        return out
    for line in _s.split(text, "\n"):
        k := _s.find(line, "=")
        if k <= 0 or _s.starts_with(line, "#"):
            continue
        v := _s.slice(line, k + 1)
        if len(v) >= 2 and ((_s.starts_with(v, "\"") and _s.ends_with(v, "\"")) or (_s.starts_with(v, "'") and _s.ends_with(v, "'"))):
            v = _s.slice(v, 1, len(v) - 1)
        out[_s.slice(line, 0, k)] = v
    return out

# Nom lisible de la distribution (« Ubuntu 24.04.1 LTS »), ou null.
func distribution():
    r := os_release()
    if contains_key(r, "PRETTY_NAME"):
        return r["PRETTY_NAME"]
    if contains_key(r, "NAME"):
        return r["NAME"]
    return null

# ---------------------------------------------------------------- processeur
func cpu_count():
    return _try(_os.cpu_count)

# Modèle du processeur (« Intel(R) Xeon(R) ... »), ou null.
func cpu_model():
    text := _read("/proc/cpuinfo")
    if text == null:
        return null
    for line in _s.split(text, "\n"):
        k := _s.find(line, ":")
        if k < 0:
            continue
        key := _s.trim(_s.slice(line, 0, k))
        if key == "model name" or key == "Model" or key == "Hardware" or key == "cpu model":
            return _s.trim(_s.slice(line, k + 1))
    return null

# Charge moyenne [1 min, 5 min, 15 min] (nombre moyen de tâches prêtes), ou null (Windows).
func load_average():
    return _osn.load_average()

# ---------------------------------------------------------------- mémoire
func _meminfo():
    text := _read("/proc/meminfo")
    out := {}
    if text == null:
        return out
    for line in _s.split(text, "\n"):
        k := _s.find(line, ":")
        if k <= 0:
            continue
        parts := [p for p in _s.split(_s.trim(_s.slice(line, k + 1)), " ") if p != ""]
        if len(parts) == 0:
            continue
        v := _try(() => to_int(parts[0]))
        if v == null:
            continue
        if len(parts) > 1 and parts[1] == "kB":
            v = v * 1024
        out[_s.slice(line, 0, k)] = v
    return out

func _field(d, key):
    if contains_key(d, key):
        return d[key]
    return null

# Mémoire vive totale (octets), ou null.
func total_memory():
    return _try(_osn.total_memory)

# {"total", "available", "free", "used", "percent_used", "swap_total", "swap_free"} ; les champs inconnus
# sur la plateforme valent null (seul total est connu hors Linux).
func memory():
    m := _meminfo()
    total := _field(m, "MemTotal")
    if total == null:
        total = total_memory()
    available := _field(m, "MemAvailable")
    free := _field(m, "MemFree")
    used := null
    percent := null
    if total != null and available != null:
        used = total - available
        if total > 0:
            percent = to_int(used * 1000 / total) / 10.0
    return {"total": total, "available": available, "free": free, "used": used, "percent_used": percent, "swap_total": _field(m, "SwapTotal"), "swap_free": _field(m, "SwapFree")}

# ---------------------------------------------------------------- disques
# Espace du système de fichiers qui contient path : {"total", "used", "free", "available"} ou null.
func disk_usage(path="/"):
    r := _try(() => _osn.disk_usage(path))
    if r == null:
        return null
    return {"total": r[0], "used": r[0] - r[1], "free": r[1], "available": r[2]}

# Systèmes de fichiers montés (Linux) : list de {"device", "mount", "type"} ; [] ailleurs. Les systèmes
# virtuels (proc, sysfs, cgroup...) sont omis sauf all=true.
func mounts(all=false):
    out := []
    text := _read("/proc/mounts")
    if text == null:
        return out
    virtual := ["proc", "sysfs", "devpts", "cgroup", "cgroup2", "securityfs", "debugfs", "tracefs", "pstore", "bpf", "mqueue", "hugetlbfs", "configfs", "fusectl", "autofs", "binfmt_misc", "devtmpfs", "rpc_pipefs", "nsfs"]
    for line in _s.split(text, "\n"):
        parts := _s.split(line, " ")
        if len(parts) < 3:
            continue
        kind := parts[2]
        skip := false
        for v in virtual:
            if kind == v:
                skip = true
        if skip and not all:
            continue
        append(out, {"device": parts[0], "mount": _s.replace(parts[1], "\\040", " "), "type": kind})
    return out

# ---------------------------------------------------------------- temps
# Secondes écoulées depuis le démarrage de la machine, ou null.
func uptime():
    text := _read("/proc/uptime")
    if text == null:
        return null
    parts := _s.split(_s.trim(text), " ")
    return _try(() => to_float(parts[0]))

# Instant du démarrage (horodatage Unix, secondes), ou null.
func boot_time():
    u := uptime()
    if u == null:
        return null
    return _os.time() - u

# ---------------------------------------------------------------- présentation
# « 1.5 Gio », « 512 o »... (unités binaires).
func format_bytes(n):
    if n == null:
        return "?"
    units := ["o", "Kio", "Mio", "Gio", "Tio", "Pio"]
    v := to_float(n)
    i := 0
    while v >= 1024 and i < len(units) - 1:
        v = v / 1024
        i += 1
    if i == 0:
        return str(n) + " o"
    return str(to_int(v * 10 + 0.5) / 10.0) + " " + units[i]

# Tout ce qui précède en un dict.
func summary():
    out := {}
    out["platform"] = platform()
    out["name"] = name()
    out["distribution"] = distribution()
    out["kernel_version"] = kernel_version()
    out["arch"] = arch()
    out["hostname"] = hostname()
    out["username"] = username()
    out["cpu_count"] = cpu_count()
    out["cpu_model"] = cpu_model()
    out["load_average"] = load_average()
    out["memory"] = memory()
    out["disk"] = disk_usage("/")
    out["uptime"] = uptime()
    out["boot_time"] = boot_time()
    out["pid"] = _os.pid()
    return out

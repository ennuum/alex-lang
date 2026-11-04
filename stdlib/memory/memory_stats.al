# ALEX STANDARD LIBRARY — memory.memory_stats
#
# Mesures de la mémoire, en un seul endroit : registre natif (blocs gérés, brut, mappé), ramasse-miettes
# (objets ALEX), processus (résident, virtuel, pic — /proc/self/status) et machine (/proc/meminfo).
#
#   use memory.memory_stats as ms
#   s := ms.snapshot()
#   print(s.format())                         # tableau lisible
#   d := ms.measure(construire)               # [résultat, différence de mesures]
#   print(d[1].live_bytes, d[1].gc_live)      # octets natifs / objets ALEX créés (et restés) par construire()
#   print(ms.format_bytes(ms.system()["total"]))
#
# Champs d'un MemoryStats : live_bytes peak_bytes managed_blocks managed_bytes raw_blocks raw_bytes
# mapped_bytes total_allocs total_frees gc_live gc_collections rss vms rss_peak (null si indisponible).
# Erreurs : aucune (une information indisponible vaut null).

from core use len, type, to_int
from collections use append
use string as _s
use io as _io
use _native_memory as _m
use _native_gc as _gc
use _native_reflect as _r

func _get(d, k):
    if k in d:
        return d[k]
    return null

func _read(path):
    try:
        return _io.read_file(path)
    catch e:
        return null

func _kv(text):
    out := {}
    if text == null:
        return out
    for line in _s.split(text, "\n"):
        i := _s.find(line, ":")
        if i > 0:
            k := _s.substring(line, 0, i)
            v := _s.trim(_s.substring(line, i + 1, len(line)))
            parts := _s.split(v, " ")
            try:
                n := to_int(parts[0])
                if len(parts) > 1 and parts[1] == "kB":
                    n = n * 1024
                out[k] = n
            catch e:
                out[k] = v
    return out

class MemoryStats:
    func init(d=null):
        self.live_bytes = null
        self.peak_bytes = null
        self.managed_blocks = null
        self.managed_bytes = null
        self.raw_blocks = null
        self.raw_bytes = null
        self.mapped_bytes = null
        self.total_allocs = null
        self.total_frees = null
        self.gc_live = null
        self.gc_collections = null
        self.rss = null
        self.vms = null
        self.rss_peak = null
        if d != null:
            for k in d:
                _set(self, k, d[k])

    func to_dict():
        return {"live_bytes": self.live_bytes, "peak_bytes": self.peak_bytes, "managed_blocks": self.managed_blocks,
                "managed_bytes": self.managed_bytes, "raw_blocks": self.raw_blocks, "raw_bytes": self.raw_bytes,
                "mapped_bytes": self.mapped_bytes, "total_allocs": self.total_allocs, "total_frees": self.total_frees,
                "gc_live": self.gc_live, "gc_collections": self.gc_collections, "rss": self.rss, "vms": self.vms,
                "rss_peak": self.rss_peak}

    # Différence self - before (champ null si l'un des deux l'est).
    func diff(before):
        a := self.to_dict()
        b := before.to_dict()
        out := {}
        for k in a:
            if a[k] == null or b[k] == null:
                out[k] = null
            else:
                out[k] = a[k] - b[k]
        return MemoryStats(out)

    func format():
        lines := []
        d := self.to_dict()
        for k in d:
            v := d[k]
            txt := "?"
            if v != null:
                if _s.ends_with(k, "bytes") or k == "rss" or k == "vms" or k == "rss_peak":
                    txt = format_bytes(v)
                else:
                    txt = str(v)
            append(lines, _pad(k, 16) + txt)
        return _s.join("\n", lines)

    func __str__():
        return "MemoryStats(natif " + format_bytes(self.live_bytes) + ", objets " + str(self.gc_live) + ", résident " + format_bytes(self.rss) + ")"



func _set(obj, k, v):
    _r.set_field(obj, k, v)

func _pad(s, n):
    out := s
    while len(out) < n:
        out += " "
    return out

func snapshot():
    st := _m.stats()
    g := _gc.stats()
    proc := _kv(_read("/proc/self/status"))
    s := MemoryStats()
    s.live_bytes = _get(st, "live_bytes")
    s.peak_bytes = _get(st, "peak_bytes")
    s.managed_blocks = _get(st, "managed_blocks")
    s.managed_bytes = _get(st, "managed_bytes")
    s.raw_blocks = _get(st, "raw_blocks")
    s.raw_bytes = _get(st, "raw_bytes")
    s.mapped_bytes = _get(st, "mapped_bytes")
    s.total_allocs = _get(st, "total_allocs")
    s.total_frees = _get(st, "total_frees")
    s.gc_live = _get(g, "live")
    s.gc_collections = _get(g, "collections")
    s.rss = _get(proc, "VmRSS")
    s.vms = _get(proc, "VmSize")
    s.rss_peak = _get(proc, "VmHWM")
    return s

# [résultat de body(), différence des mesures avant/après].
func measure(body):
    before := snapshot()
    r := body()
    return [r, snapshot().diff(before)]

# Mémoire de la machine : {"total", "available", "free", "swap_total", "swap_free"} (octets, null si inconnu).
func system():
    m := _kv(_read("/proc/meminfo"))
    return {"total": _get(m, "MemTotal"), "available": _get(m, "MemAvailable"), "free": _get(m, "MemFree"),
            "swap_total": _get(m, "SwapTotal"), "swap_free": _get(m, "SwapFree"),
            "cached": _get(m, "Cached")}

func native():
    return _m.stats()

func gc():
    return _gc.stats()

func format_bytes(n):
    if n == null:
        return "?"
    neg := n < 0
    v := n
    if neg:
        v = -n
    units := ["o", "Kio", "Mio", "Gio", "Tio"]
    x := v * 1.0
    u := 0
    while x >= 1024 and u < len(units) - 1:
        x = x / 1024
        u += 1
    txt := ""
    if u == 0:
        txt = str(v) + " o"
    else:
        txt = str(to_int(x * 10 + 0.5) / 10) + " " + units[u]
    if neg:
        return "-" + txt
    return txt

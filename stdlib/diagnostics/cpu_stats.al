# ALEX STANDARD LIBRARY — diagnostics.cpu_stats
#
# Utilisation du processeur : temps CPU du processus et de ses fils système (utilisateur / noyau), taux
# d'occupation de la machine entre deux échantillons (global et par cœur, Linux : /proc/stat), charge moyenne,
# fréquence courante des cœurs, changements de contexte, et mesure du temps CPU d'une fonction.
#
#   use diagnostics.cpu_stats as cs
#   print(cs.process_times())          # {"user": 0.42, "system": 0.03, "total": 0.45} (secondes)
#   s := cs.CpuSampler()
#   travail()
#   print(s.usage())                   # {"total": 37.5, "cpus": [80.1, 12.0, ...]} (% depuis l'échantillon précédent)
#   m := cs.measure(calcul)            # {"wall": 1.2, "cpu": 1.19, "ratio": 0.99, "result": ...}
#   print(cs.load_average(), cs.frequencies(), cs.context_switches())
#
# Hors Linux, les informations indisponibles valent null (ou une liste vide).
# Erreurs : TypeError (fonction attendue).

from core use len, type, to_int, to_float
from collections use append
use string as _s
use io as _io
use os as _os

const CLOCK_TICKS := 100

func _read(path):
    try:
        return _io.read_file(path)
    catch e:
        return null

func _stat_fields(text):
    if text == null:
        return null
    i := len(text) - 1
    while i >= 0 and text[i] != ')':
        i -= 1
    if i < 0:
        return null
    return _s.split(_s.trim(_s.substring(text, i + 1, len(text))), " ")

# Temps CPU (secondes) du processus.
func process_times():
    f := _stat_fields(_read("/proc/self/stat"))
    if f == null or len(f) < 15:
        return {"user": null, "system": null, "total": null}
    u := to_int(f[11]) / CLOCK_TICKS
    s := to_int(f[12]) / CLOCK_TICKS
    return {"user": u, "system": s, "total": u + s, "children_user": to_int(f[13]) / CLOCK_TICKS, "children_system": to_int(f[14]) / CLOCK_TICKS}

func process_time():
    return process_times()["total"]

# Temps CPU par fil système du processus : [{tid, name, user, system}].
func thread_times():
    out := []
    if not _os.isdir("/proc/self/task"):
        return out
    for n in _os.list_dir("/proc/self/task"):
        txt := _read("/proc/self/task/" + n + "/stat")
        f := _stat_fields(txt)
        if f == null or len(f) < 13:
            continue
        a := _s.find(txt, "(")
        b := len(txt) - 1
        while b >= 0 and txt[b] != ')':
            b -= 1
        append(out, {"tid": to_int(n), "name": _s.substring(txt, a + 1, b), "user": to_int(f[11]) / CLOCK_TICKS, "system": to_int(f[12]) / CLOCK_TICKS})
    return out

# Compteurs bruts de /proc/stat : {"cpu": [user, nice, system, idle, iowait, irq, softirq, steal], "cpu0": [...]}.
func raw_counters():
    txt := _read("/proc/stat")
    out := {}
    if txt == null:
        return out
    for line in _s.split(txt, "\n"):
        if _s.starts_with(line, "cpu"):
            parts := [p for p in _s.split(line, " ") if p != ""]
            append_vals := [to_int(x) for x in parts[1:]]
            out[parts[0]] = append_vals
    return out

func _busy_idle(v):
    idle := v[3]
    if len(v) > 4:
        idle += v[4]
    total := 0
    for x in v:
        total += x
    # guest / guest_nice sont déjà comptés dans user / nice
    if len(v) > 8:
        total -= v[8]
    if len(v) > 9:
        total -= v[9]
    return [total - idle, total]

class CpuSampler:
    func init():
        self.prev = raw_counters()
        self.prev_proc = process_times()
        self.prev_wall = _os.monotonic_time()

    # % d'occupation depuis l'échantillon précédent (puis l'échantillon courant devient la référence).
    func usage():
        cur := raw_counters()
        out := {"total": null, "cpus": []}
        if "cpu" in cur and "cpu" in self.prev:
            out["total"] = _pct(self.prev["cpu"], cur["cpu"])
        i := 0
        while ("cpu" + str(i)) in cur:
            k := "cpu" + str(i)
            if k in self.prev:
                append(out["cpus"], _pct(self.prev[k], cur[k]))
            i += 1
        self.prev = cur
        return out

    # % d'un cœur utilisé par CE processus depuis l'échantillon précédent.
    func process_usage():
        p := process_times()
        w := _os.monotonic_time()
        r := null
        if p["total"] != null and self.prev_proc["total"] != null and w > self.prev_wall:
            r = (p["total"] - self.prev_proc["total"]) / (w - self.prev_wall) * 100.0
        self.prev_proc = p
        self.prev_wall = w
        return r

func _pct(a, b):
    x := _busy_idle(a)
    y := _busy_idle(b)
    dt := y[1] - x[1]
    if dt <= 0:
        return 0.0
    return to_int((y[0] - x[0]) * 1000.0 / dt + 0.5) / 10.0

# Occupation pendant interval secondes (bloquant).
func usage_over(interval=0.2):
    s := CpuSampler()
    _os.sleep(interval)
    return s.usage()

func load_average():
    txt := _read("/proc/loadavg")
    if txt == null:
        return null
    p := _s.split(txt, " ")
    return [to_float(p[0]), to_float(p[1]), to_float(p[2])]

func cpu_count():
    n := 0
    for k in raw_counters():
        if k != "cpu":
            n += 1
    if n == 0:
        return null
    return n

# Fréquences courantes (MHz) des cœurs, liste vide si inconnues.
func frequencies():
    out := []
    i := 0
    while true:
        txt := _read("/sys/devices/system/cpu/cpu" + str(i) + "/cpufreq/scaling_cur_freq")
        if txt == null:
            break
        append(out, to_int(_s.trim(txt)) / 1000.0)
        i += 1
    if len(out) > 0:
        return out
    info := _read("/proc/cpuinfo")
    if info == null:
        return out
    for line in _s.split(info, "\n"):
        if _s.starts_with(line, "cpu MHz"):
            append(out, to_float(_s.trim(_s.split(line, ":")[1])))
    return out

# Changements de contexte volontaires / forcés du processus.
func context_switches():
    txt := _read("/proc/self/status")
    out := {"voluntary": null, "involuntary": null}
    if txt == null:
        return out
    for line in _s.split(txt, "\n"):
        if _s.starts_with(line, "voluntary_ctxt_switches:"):
            out["voluntary"] = to_int(_s.trim(_s.split(line, ":")[1]))
        elif _s.starts_with(line, "nonvoluntary_ctxt_switches:"):
            out["involuntary"] = to_int(_s.trim(_s.split(line, ":")[1]))
    return out

# Temps réel et temps CPU d'un appel (la résolution CPU est d'environ 10 ms).
func measure(fn, args=null):
    if type(fn) != "function":
        raise("TypeError", "cpu_stats.measure : fonction attendue")
    a := args
    if a == null:
        a = []
    c0 := process_time()
    w0 := _os.monotonic_time()
    r := fn(*a)
    w := _os.monotonic_time() - w0
    c := null
    if c0 != null:
        c = process_time() - c0
    ratio := null
    if c != null and w > 0:
        ratio = c / w
    return {"wall": w, "cpu": c, "ratio": ratio, "result": r}

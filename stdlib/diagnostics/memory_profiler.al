# ALEX STANDARD LIBRARY — diagnostics.memory_profiler
#
# Profil mémoire : ce qu'un bloc de code alloue et retient (mémoire native, objets ALEX du ramasse-miettes,
# mémoire résidente du processus), suivi d'étapes nommées, chronologie d'échantillons et pic observé.
#
#   use diagnostics.memory_profiler as mp
#   r := mp.profile(() => construire_index(fichiers))
#   print(r.retained_objects, r.native_bytes, r.rss_delta)     # objets restés vivants, octets natifs...
#   prof := mp.MemoryProfiler()
#   prof.track("chargement", () => charger())
#   prof.track("indexation", () => indexer())
#   prof.sample("après indexation")
#   print(prof.report())                # tableau des étapes et des échantillons, pic de résident
#   print(mp.leak_check(() => requete(), 50))   # objets retenus après 50 répétitions (fuite si croissance)
#
# « Retenus » = objets encore vivants après une collecte forcée. Mesures en octets.
# Erreurs : TypeError (fonction attendue).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use memory.memory_stats as _ms
use _native_gc as _gc

class MemoryProfile:
    func init(name, before, after, objects_before, objects_after, result, duration):
        self.name = name
        d := after.diff(before)
        self.native_bytes = d.live_bytes
        self.native_allocs = d.total_allocs
        self.rss_delta = d.rss
        self.rss_after = after.rss
        self.retained_objects = objects_after - objects_before
        self.gc_collections = d.gc_collections
        self.result = result
        self.duration = duration

    func to_dict():
        return {"name": self.name, "native_bytes": self.native_bytes, "native_allocs": self.native_allocs,
                "rss_delta": self.rss_delta, "retained_objects": self.retained_objects,
                "gc_collections": self.gc_collections, "duration": self.duration}

    func __str__():
        return self.name + " : objets retenus " + str(self.retained_objects) + ", natif " + _ms.format_bytes(self.native_bytes) + ", résident " + _signed_bytes(self.rss_delta)

func _signed_bytes(n):
    if n == null:
        return "?"
    if n < 0:
        return "-" + _ms.format_bytes(-n)
    return "+" + _ms.format_bytes(n)

func live_objects():
    _gc.collect()
    st := _gc.stats()
    if type(st) == "dict" and "live" in st:
        return st["live"]
    s := _ms.snapshot()
    if s.gc_live == null:
        return 0
    return s.gc_live

func profile(fn, name="bloc"):
    if type(fn) != "function":
        raise("TypeError", "memory_profiler.profile : fonction attendue")
    o0 := live_objects()
    b := _ms.snapshot()
    t0 := _os.monotonic_time()
    r := fn()
    dt := _os.monotonic_time() - t0
    o1 := live_objects()
    a := _ms.snapshot()
    return MemoryProfile(name, b, a, o0, o1, r, dt)

# Répète fn et mesure les objets retenus : {"runs", "retained", "per_run", "suspect"}.
func leak_check(fn, runs=20, warmup=3):
    i := 0
    while i < warmup:
        fn()
        i += 1
    o0 := live_objects()
    i = 0
    while i < runs:
        fn()
        i += 1
    o1 := live_objects()
    per := (o1 - o0) / runs
    return {"runs": runs, "retained": o1 - o0, "per_run": per, "suspect": per >= 1}

class MemoryProfiler:
    func init():
        self.steps = []
        self.samples = []
        self.peak_rss = null
        self.sample("départ")

    func track(name, fn):
        p := profile(fn, name)
        append(self.steps, p)
        self._peak(p.rss_after)
        return p.result

    func sample(label=null):
        s := _ms.snapshot()
        objs := live_objects()
        l := label
        if l == null:
            l = "échantillon " + str(len(self.samples))
        append(self.samples, {"label": l, "time": _os.monotonic_time(), "rss": s.rss, "objects": objs, "native": s.live_bytes})
        self._peak(s.rss)
        return s

    func _peak(rss):
        if rss != null and (self.peak_rss == null or rss > self.peak_rss):
            self.peak_rss = rss

    func heaviest(n=3):
        out := self.steps[:]
        i := 1
        while i < len(out):
            v := out[i]
            j := i - 1
            while j >= 0 and _weight(out[j]) < _weight(v):
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = v
            i += 1
        return out[:n]

    func report():
        lines := ["Étapes :"]
        for p in self.steps:
            append(lines, "  " + str(p))
        append(lines, "Échantillons :")
        t0 := self.samples[0]["time"]
        for s in self.samples:
            append(lines, "  +" + str(to_int((s["time"] - t0) * 1000)) + " ms  " + s["label"] + " : résident " + _ms.format_bytes(s["rss"]) + ", objets " + str(s["objects"]))
        append(lines, "Pic résident observé : " + _ms.format_bytes(self.peak_rss))
        return _s.join("\n", lines)

func _weight(p):
    w := p.retained_objects
    if p.native_bytes != null:
        w += p.native_bytes // 64
    return w

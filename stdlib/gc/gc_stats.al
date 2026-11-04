# ALEX STANDARD LIBRARY — gc.gc_stats
#
# Statistiques du ramasse-miettes dans le temps : mesure d'un bloc de code (objets créés, libérés, collectes
# déclenchées), échantillonnage périodique et rapport.
#
#   use gc.gc_stats as gs
#   m := gs.measure(construire_index)
#   print(m["allocated"], m["collections"], m["retained"])   # créés, collectes, restés vivants
#   mon := gs.GcMonitor()
#   for lot in lots:
#       traiter(lot)
#       mon.sample()
#   print(mon.report())
#
# Erreurs : TypeError (fonction attendue).

from core use len, type, to_int
from collections use append
use string as _s
use _native_gc as _g
use os as _os

func snapshot():
    s := _g.stats()
    s["time"] = _os.monotonic_time()
    return s

# Écart entre deux instantanés.
func delta(before, after):
    return {"allocated": after["allocated"] - before["allocated"], "freed": after["freed"] - before["freed"],
            "collections": after["collections"] - before["collections"],
            "retained": after["live"] - before["live"], "seconds": after["time"] - before["time"],
            "peak": after["peak"]}

# Exécute body() et rend {"result", "allocated", "freed", "collections", "retained", "seconds", "peak"}.
func measure(body):
    if type(body) != "function":
        raise("TypeError", "gc_stats.measure : fonction attendue")
    a := snapshot()
    r := body()
    d := delta(a, snapshot())
    d["result"] = r
    return d

class GcMonitor:
    func init(label="gc"):
        self.label = label
        self.samples = [snapshot()]

    func sample():
        s := snapshot()
        append(self.samples, s)
        return s

    func count():
        return len(self.samples)

    # Écart entre le premier et le dernier échantillon.
    func total():
        return delta(self.samples[0], self.samples[len(self.samples) - 1])

    # Écarts successifs.
    func deltas():
        out := []
        i := 1
        while i < len(self.samples):
            append(out, delta(self.samples[i - 1], self.samples[i]))
            i += 1
        return out

    func max_live():
        m := 0
        for s in self.samples:
            if s["live"] > m:
                m = s["live"]
        return m

    func allocation_rate():
        t := self.total()
        if t["seconds"] <= 0:
            return 0.0
        return t["allocated"] / t["seconds"]

    func report():
        t := self.total()
        lines := [self.label + " : " + str(len(self.samples)) + " échantillons sur " + str(_round(t["seconds"], 3)) + " s",
                  "  objets créés      " + str(t["allocated"]),
                  "  objets libérés    " + str(t["freed"]),
                  "  collectes         " + str(t["collections"]),
                  "  vivants (max)     " + str(self.max_live()),
                  "  vivants (écart)   " + str(t["retained"])]
        return _s.join("\n", lines)

func _round(x, n):
    m := 1
    i := 0
    while i < n:
        m = m * 10
        i += 1
    return to_int(x * m + 0.5) / m

func collections():
    return _g.stats()["collections"]

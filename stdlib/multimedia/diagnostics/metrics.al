# ALEX STANDARD LIBRARY — multimedia.diagnostics.metrics
#
# Mesures de performance des traitements : compteurs (images décodées, paquets perdus), jauges (remplissage d'un
# tampon), chronométrages (durée de décodage par bloc : nombre, total, moyenne, min, max) et débit.
#
#   use multimedia.diagnostics.metrics as mm
#   m := mm.Metrics()
#   m.count("frames")
#   m.gauge("buffer_fill", 0.75)
#   t := m.start("decode")
#   ... travail ...
#   m.stop(t)
#   m.record("decode", 0.004)          # durée déjà mesurée
#   print(m.report())                  # {"counters": {...}, "gauges": {...}, "timings": {"decode": {...}}}
#
# L'horloge est injectable (tests) : Metrics(clock) avec clock() -> secondes.

from core use len
from collections use keys
use time as _t

class Metrics:
    func init(clock=null):
        self.clock = clock if clock != null else () => _t.perf_counter()
        self.counters = {}
        self.gauges = {}
        self.timings = {}
        self.created = self.clock()

    func count(name, n=1):
        if not (name in self.counters):
            self.counters[name] = 0
        self.counters[name] = self.counters[name] + n
        return self.counters[name]

    func counter(name):
        if name in self.counters:
            return self.counters[name]
        return 0

    func gauge(name, value):
        self.gauges[name] = value

    func start(name):
        return [name, self.clock()]

    func stop(handle):
        d := self.clock() - handle[1]
        self.record(handle[0], d)
        return d

    func record(name, seconds):
        if not (name in self.timings):
            self.timings[name] = {"count": 0, "total": 0.0, "min": seconds, "max": seconds}
        t := self.timings[name]
        t["count"] = t["count"] + 1
        t["total"] = t["total"] + seconds
        if seconds < t["min"]:
            t["min"] = seconds
        if seconds > t["max"]:
            t["max"] = seconds

    func mean(name):
        if not (name in self.timings) or self.timings[name]["count"] == 0:
            return 0.0
        return self.timings[name]["total"] / self.timings[name]["count"]

    # Débit d'un compteur depuis la création (unités par seconde).
    func rate(name):
        el := self.clock() - self.created
        if el <= 0:
            return 0.0
        return self.counter(name) / el

    func report():
        tm := {}
        for k in keys(self.timings):
            t := self.timings[k]
            tm[k] = {"count": t["count"], "total": t["total"], "mean": self.mean(k), "min": t["min"], "max": t["max"]}
        return {"counters": self.counters, "gauges": self.gauges, "timings": tm, "elapsed": self.clock() - self.created}

    func reset():
        self.counters = {}
        self.gauges = {}
        self.timings = {}
        self.created = self.clock()

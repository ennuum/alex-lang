# ALEX STANDARD LIBRARY — diagnostics.performance_counter
#
# Compteurs de performance : chronomètres de haute résolution (horloge monotone), compteurs nommés
# d'événements et de mesures (nombre, total, min, max, moyenne, débit), minuteries utilisables avec `with`.
#
#   use diagnostics.performance_counter as pc
#   sw := pc.Stopwatch().start()
#   travail()
#   print(sw.lap(), sw.elapsed())             # tour, temps écoulé (s)
#   pc.increment("requêtes")                  # compteur nommé
#   pc.record("latence", 0.012)               # mesure
#   with pc.timer("phase_1"):                 # durée enregistrée dans le compteur « phase_1 »
#       charger()
#   print(pc.get("latence").mean(), pc.get("requêtes").count)
#   print(pc.report())                        # tableau de tous les compteurs
#   r := pc.time_call(f, [1, 2])              # [secondes, résultat]
#
# Erreurs : ArgumentError (stop sans start), TypeError (fonction attendue).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os

func now():
    return _os.monotonic_time()

class Stopwatch:
    func init():
        self.started = null
        self.accumulated = 0.0
        self.laps = []
        self.last_lap = null

    func start():
        if self.started == null:
            self.started = now()
            self.last_lap = self.started
        return self

    func stop():
        if self.started == null:
            raise("ArgumentError", "Stopwatch.stop : chronomètre arrêté")
        t := now()
        self.accumulated += t - self.started
        self.started = null
        return self.accumulated

    func running():
        return self.started != null

    func elapsed():
        if self.started == null:
            return self.accumulated
        return self.accumulated + now() - self.started

    # Durée depuis le tour précédent (ou le départ).
    func lap():
        if self.started == null:
            raise("ArgumentError", "Stopwatch.lap : chronomètre arrêté")
        t := now()
        d := t - self.last_lap
        self.last_lap = t
        append(self.laps, d)
        return d

    func reset():
        self.started = null
        self.accumulated = 0.0
        self.laps = []
        self.last_lap = null
        return self

    func __enter__():
        return self.start()

    func __exit__(a, b, c):
        if self.started != null:
            self.stop()

class PerformanceCounter:
    func init(name, unit="s"):
        self.name = name
        self.unit = unit
        self.count = 0
        self.total = 0.0
        self.min = null
        self.max = null
        self.created = now()
        self.last = null

    func increment(n=1):
        self.count += n
        self.total += n
        self.last = n
        return self

    func record(value):
        self.count += 1
        self.total += value
        self.last = value
        if self.min == null or value < self.min:
            self.min = value
        if self.max == null or value > self.max:
            self.max = value
        return self

    func mean():
        if self.count == 0:
            return null
        return self.total / self.count

    # Événements par seconde depuis la création (ou le dernier reset).
    func rate():
        d := now() - self.created
        if d <= 0:
            return null
        return self.count / d

    func reset():
        self.count = 0
        self.total = 0.0
        self.min = null
        self.max = null
        self.last = null
        self.created = now()

    func to_dict():
        return {"name": self.name, "count": self.count, "total": self.total, "min": self.min, "max": self.max,
                "mean": self.mean(), "unit": self.unit}

    func __str__():
        return self.name + " : " + str(self.count) + " × , total " + _fmt(self.total, self.unit)

class _Timer:
    func init(counter):
        self.counter = counter
        self.t0 = null
        self.elapsed = null

    func __enter__():
        self.t0 = now()
        return self

    func __exit__(a, b, c):
        self.elapsed = now() - self.t0
        self.counter.record(self.elapsed)

_registry := {}
_order := []

func counter(name, unit="s"):
    if not (name in _registry):
        _registry[name] = PerformanceCounter(name, unit)
        append(_order, name)
    return _registry[name]

func get(name):
    if name in _registry:
        return _registry[name]
    return null

func increment(name, n=1):
    return counter(name, "").increment(n)

func record(name, value, unit="s"):
    return counter(name, unit).record(value)

func timer(name):
    return _Timer(counter(name, "s"))

func names():
    return _order[:]

func reset_all():
    for n in _order:
        _registry[n].reset()

func snapshot():
    return [_registry[n].to_dict() for n in _order]

func time_call(fn, args=null):
    if type(fn) != "function":
        raise("TypeError", "time_call : fonction attendue")
    a := args
    if a == null:
        a = []
    t0 := now()
    r := fn(*a)
    return [now() - t0, r]

func _fmt(v, unit):
    if v == null:
        return "-"
    if unit == "s":
        if v < 0.001:
            return str(to_int(v * 1000000 + 0.5)) + " µs"
        if v < 1:
            return str(to_int(v * 10000 + 0.5) / 10.0) + " ms"
        return str(to_int(v * 1000 + 0.5) / 1000.0) + " s"
    if type(v) == "float":
        return str(to_int(v * 1000 + 0.5) / 1000.0)
    return str(v)

func _pad(s, n):
    out := s
    while len(out) < n:
        out += " "
    return out

func report():
    lines := [_pad("compteur", 24) + _pad("nombre", 10) + _pad("total", 14) + _pad("moyenne", 14) + _pad("min", 12) + "max"]
    for n in _order:
        c := _registry[n]
        append(lines, _pad(n, 24) + _pad(str(c.count), 10) + _pad(_fmt(c.total, c.unit), 14) + _pad(_fmt(c.mean(), c.unit), 14) + _pad(_fmt(c.min, c.unit), 12) + _fmt(c.max, c.unit))
    return _s.join("\n", lines)

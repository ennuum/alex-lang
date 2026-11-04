# ALEX STANDARD LIBRARY — testing.benchmark
#
# Mesures de performance : exécutions répétées après échauffement, statistiques robustes (minimum, médiane,
# moyenne, écart-type, opérations par seconde), comparaison de variantes, tableau de résultats.
#
#   use testing.benchmark as bm
#   r := bm.run("tri", () => sorted(donnees), 50)     # 50 mesures (après 5 tours d'échauffement)
#   print(r.median, r.ops_per_second(), r)
#   r2 := bm.run_for("hash", () => hachage(x), 0.5)   # autant de tours que possible en 0,5 s
#   print(bm.compare([r, r2]))                        # tableau, facteur relatif au plus rapide
#   b := bm.Benchmark()
#   b.add("liste", construire_liste)
#   b.add("deque", construire_deque)
#   print(b.run(20).table())
#
# Les durées sont en secondes (horloge monotone). Une mesure inclut l'appel de la fonction : pour une
# opération très courte, la faire en boucle dans fn et diviser (paramètre per_call).
# Erreurs : TypeError (fonction attendue), ArgumentError (répétitions < 1).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os

func _sorted(xs):
    out := xs[:]
    i := 1
    while i < len(out):
        v := out[i]
        j := i - 1
        while j >= 0 and out[j] > v:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = v
        i += 1
    return out

func _sqrt(x):
    if x <= 0:
        return 0.0
    g := x
    i := 0
    while i < 40:
        g = (g + x / g) / 2
        i += 1
    return g

class BenchResult:
    func init(name, samples, per_call=1):
        self.name = name
        k := per_call
        if k < 1:
            k = 1
        self.samples = [s / k for s in samples]
        s := _sorted(self.samples)
        n := len(s)
        self.runs = n
        self.min = s[0]
        self.max = s[n - 1]
        if n % 2 == 1:
            self.median = s[n // 2]
        else:
            self.median = (s[n // 2 - 1] + s[n // 2]) / 2
        total := 0.0
        for x in s:
            total += x
        self.mean = total / n
        var := 0.0
        for x in s:
            var += (x - self.mean) * (x - self.mean)
        self.stddev = 0.0
        if n > 1:
            self.stddev = _sqrt(var / (n - 1))
        self.p95 = s[to_int((n - 1) * 0.95)]

    func ops_per_second():
        if self.median <= 0:
            return null
        return 1.0 / self.median

    # Coefficient de variation (stabilité de la mesure).
    func cv():
        if self.mean == 0:
            return 0.0
        return self.stddev / self.mean

    func to_dict():
        return {"name": self.name, "runs": self.runs, "min": self.min, "median": self.median, "mean": self.mean,
                "max": self.max, "stddev": self.stddev, "p95": self.p95}

    func __str__():
        return self.name + " : médiane " + format_duration(self.median) + " (min " + format_duration(self.min) + ", ±" + format_duration(self.stddev) + ", " + str(self.runs) + " tours)"

func format_duration(s):
    if s == null:
        return "?"
    if s < 0.000001:
        return str(to_int(s * 1000000000 + 0.5)) + " ns"
    if s < 0.001:
        return str(to_int(s * 10000000 + 0.5) / 10.0) + " µs"
    if s < 1:
        return str(to_int(s * 10000 + 0.5) / 10.0) + " ms"
    return str(to_int(s * 1000 + 0.5) / 1000.0) + " s"

func _need(fn, repeat):
    if type(fn) != "function":
        raise("TypeError", "benchmark : fonction attendue")
    if type(repeat) != "int" or repeat < 1:
        raise("ArgumentError", "benchmark : au moins une répétition")

func run(name, fn, repeat=20, warmup=5, per_call=1):
    _need(fn, repeat)
    i := 0
    while i < warmup:
        fn()
        i += 1
    samples := []
    i = 0
    while i < repeat:
        t0 := _os.monotonic_time()
        fn()
        append(samples, _os.monotonic_time() - t0)
        i += 1
    return BenchResult(name, samples, per_call)

# Mesure pendant duration secondes (au moins min_runs tours).
func run_for(name, fn, duration=1.0, min_runs=3, per_call=1):
    _need(fn, 1)
    fn()
    samples := []
    start := _os.monotonic_time()
    while len(samples) < min_runs or _os.monotonic_time() - start < duration:
        t0 := _os.monotonic_time()
        fn()
        append(samples, _os.monotonic_time() - t0)
    return BenchResult(name, samples, per_call)

# Durée d'un seul appel (et son résultat) : [secondes, résultat].
func time_it(fn):
    t0 := _os.monotonic_time()
    r := fn()
    return [_os.monotonic_time() - t0, r]

func _pad(s, n):
    out := s
    while len(out) < n:
        out += " "
    return out

# Tableau comparatif (médianes), avec le facteur par rapport au plus rapide.
func compare(results):
    best := null
    for r in results:
        if best == null or r.median < best.median:
            best = r
    lines := [_pad("nom", 20) + _pad("médiane", 14) + _pad("min", 14) + "relatif"]
    for r in results:
        rel := "1.00x"
        if best.median > 0 and not (r.name == best.name):
            rel = str(to_int(r.median / best.median * 100 + 0.5) / 100.0) + "x"
        lines = lines + [_pad(r.name, 20) + _pad(format_duration(r.median), 14) + _pad(format_duration(r.min), 14) + rel]
    return _s.join("\n", lines)

class Benchmark:
    func init(name="benchmark"):
        self.name = name
        self.cases = []
        self.results = []

    func add(name, fn):
        append(self.cases, [name, fn])
        return self

    func run(repeat=20, warmup=3):
        self.results = [run(c[0], c[1], repeat, warmup) for c in self.cases]
        return self

    func table():
        return compare(self.results)

    func fastest():
        best := null
        for r in self.results:
            if best == null or r.median < best.median:
                best = r
        return best

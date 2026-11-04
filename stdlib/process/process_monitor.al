# ALEX STANDARD LIBRARY — process.process_monitor
#
# Surveillance de processus dans le temps : échantillonnage du processeur (%), de la mémoire résidente et
# du nombre de fils d'exécution, historique borné, seuils déclenchant des alertes, détection de la fin.
#
#   use process.process_monitor as pmon
#   m := pmon.ProcessMonitor()
#   m.watch(pid, "serveur")
#   m.on_threshold("rss", 500 * 1024 * 1024, (nom, s) => alerter(nom + " dépasse 500 Mio"))
#   m.on_exit((nom, pid) => print(nom, "s'est arrêté"))
#   m.run(10.0, 1.0)                          # 10 s, un échantillon par seconde
#   print(m.stats("serveur"))                 # {"cpu_avg", "cpu_max", "rss_max", "samples", ...}
#
# Source : /proc (Linux) via process.process_info ; ailleurs les mesures indisponibles valent null.
# Erreurs : ArgumentError (métrique inconnue, nom en double), TypeError.

from core use len, type
from collections use append
use os as _os
use process.process_info as _pi

const METRICS := ["cpu", "rss", "vms", "threads"]

class Sample:
    func init(time, cpu, rss, vms, threads):
        self.time = time
        self.cpu = cpu
        self.rss = rss
        self.vms = vms
        self.threads = threads

    func get(metric):
        if metric == "cpu":
            return self.cpu
        if metric == "rss":
            return self.rss
        if metric == "vms":
            return self.vms
        return self.threads

class _Watched:
    func init(pid, name, keep):
        self.pid = pid
        self.name = name
        self.keep = keep
        self.samples = []
        self.alive = true
        self.last_cpu = null
        self.last_time = null

class ProcessMonitor:
    func init(keep=600):
        self.keep = keep
        self._w = {}
        self._order = []
        self._thresholds = []
        self._exit_handlers = []
        self.alerts = []

    func watch(pid, name=null):
        n := name
        if n == null:
            n = str(pid)
        if n in self._w:
            raise("ArgumentError", "ProcessMonitor.watch : nom '" + n + "' déjà surveillé")
        self._w[n] = _Watched(pid, n, self.keep)
        append(self._order, n)
        return n

    func unwatch(name):
        if name in self._w:
            del self._w[name]
            self._order = [x for x in self._order if x != name]

    func names():
        return self._order[:]

    # handler(nom, échantillon) quand metric dépasse limit.
    func on_threshold(metric, limit, handler):
        _need_metric(metric)
        append(self._thresholds, [metric, limit, handler])

    # handler(nom, pid) à la disparition d'un processus surveillé.
    func on_exit(handler):
        append(self._exit_handlers, handler)

    # Un échantillon pour chaque processus vivant ; renvoie {nom: Sample}.
    func sample():
        out := {}
        now := _os.monotonic_time()
        for n in self._order:
            w := self._w[n]
            if not w.alive:
                continue
            info := _pi.get_or_null(w.pid)
            if info == null or info.is_zombie():
                w.alive = false
                for h in self._exit_handlers:
                    h(n, w.pid)
                continue
            cpu := null
            ct := info.cpu_time()
            if ct != null and w.last_cpu != null and now > w.last_time:
                cpu = 100.0 * (ct - w.last_cpu) / (now - w.last_time)
            w.last_cpu = ct
            w.last_time = now
            s := Sample(now, cpu, info.rss, info.vms, info.threads)
            append(w.samples, s)
            if len(w.samples) > w.keep:
                w.samples = w.samples[len(w.samples) - w.keep:]
            for th in self._thresholds:
                v := s.get(th[0])
                if v != null and v > th[1]:
                    append(self.alerts, [n, th[0], v])
                    th[2](n, s)
            out[n] = s
        return out

    # Échantillonne pendant duration secondes (ou jusqu'à la fin de tous) toutes les interval secondes.
    func run(duration, interval=1.0):
        t0 := _os.monotonic_time()
        while _os.monotonic_time() - t0 < duration:
            self.sample()
            if len(self.alive()) == 0:
                return
            _os.sleep(interval)

    func alive():
        return [n for n in self._order if self._w[n].alive]

    func samples(name):
        return self._w[name].samples[:]

    func latest(name):
        s := self._w[name].samples
        if len(s) == 0:
            return null
        return s[len(s) - 1]

    # Bilan : moyennes et maxima des métriques mesurées.
    func stats(name):
        s := self._w[name].samples
        out := {"samples": len(s), "alive": self._w[name].alive, "pid": self._w[name].pid}
        for metric in METRICS:
            vals := [x.get(metric) for x in s if x.get(metric) != null]
            if len(vals) == 0:
                out[metric + "_avg"] = null
                out[metric + "_max"] = null
            else:
                total := 0
                mx := vals[0]
                for v in vals:
                    total += v
                    if v > mx:
                        mx = v
                out[metric + "_avg"] = total / len(vals)
                out[metric + "_max"] = mx
        return out

func _need_metric(m):
    for x in METRICS:
        if x == m:
            return
    raise("ArgumentError", "process_monitor : métrique inconnue '" + str(m) + "' (cpu, rss, vms, threads)")

# Surveille un seul processus pendant duration secondes ; renvoie ses statistiques.
func profile(pid, duration=1.0, interval=0.1):
    m := ProcessMonitor()
    n := m.watch(pid)
    m.run(duration, interval)
    return m.stats(n)

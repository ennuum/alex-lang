# ALEX STANDARD LIBRARY — process.process_manager
#
# Superviser plusieurs processus fils : démarrage, arrêt propre (TERM puis KILL), redémarrage automatique avec
# délai croissant, sortie capturée, événements ; et exécution parallèle bornée d'une liste de commandes.
#
#   use process.process_manager as pm
#   m := pm.ProcessManager()
#   m.add("web", ["python3", "-m", "http.server", "8000"], {"restart": "on_failure", "max_restarts": 5})
#   m.add("worker", "./worker --queue jobs", {"restart": "always", "output": "capture"})
#   m.on("exit", (ev) => print(ev["name"], ev["code"]))
#   m.start_all()
#   m.supervise(60)                        # surveille 60 s (redémarrages, sorties capturées, événements)
#   print(m.status())
#   m.stop_all(3)
#
#   results := pm.run_parallel([["gzip", "-k", "a"], ["gzip", "-k", "b"]], max_parallel=4)
#
# Options de add (dict, toutes facultatives) : "restart" (politique), "max_restarts" (3), "backoff" (0.5 s),
# "max_backoff" (30 s), "output" ("inherit", "null" ou "capture" : lignes gardées, voir logs), "keep_lines" (1000).
#
# Politique de redémarrage : "never" (défaut), "on_failure" (code non nul ou signal), "always". Le n-ième
# redémarrage attend backoff × 2^(n-1) secondes (au plus max_backoff). Au-delà de max_restarts, l'état passe à
# "failed". Événements : "start", "exit", "restart", "failed", "stop" ; le gestionnaire reçoit un dict
# {"name", "event", "code", "pid", "restarts"}.
#
# Commandes acceptées : [programme, arguments...], une ligne de texte (découpée sans shell, process.command.split)
# ou un objet process.Command / process.command.Command.
#
# Erreurs : ArgumentError (nom inconnu ou déjà utilisé, politique invalide), ProcessError, IoError.

from core use len, type
from collections use append, keys, contains_key, remove, pop
use string as _s
use os as _os
use process as _proc
use process.command as _cmd
use process.exit_code as _ec

const NEVER := "never"
const ON_FAILURE := "on_failure"
const ALWAYS := "always"

func _now():
    return _os.monotonic_time()

func _to_command(fn, command):
    t := type(command)
    if t == "str":
        return _cmd.parse(command)
    if t == "list":
        return _cmd.from_list(command)
    if t == "instance":
        return command
    raise("TypeError", "process_manager." + fn + " : commande attendue (liste, texte ou Command), obtenu '" + t + "'")

func _options(options):
    o := {"restart": NEVER, "max_restarts": 3, "backoff": 0.5, "max_backoff": 30.0, "output": "inherit", "keep_lines": 1000}
    if options == null:
        return o
    if type(options) != "dict":
        raise("TypeError", "ProcessManager.add : les options doivent être un dict")
    for k in keys(options):
        if not contains_key(o, k):
            raise("ArgumentError", "ProcessManager.add : option inconnue '" + str(k) + "'")
        o[k] = options[k]
    return o

class ManagedProcess:
    func init(name, command, restart, max_restarts, backoff, max_backoff, output, keep_lines):
        self.name = name
        self.command = command
        self.restart = restart
        self.max_restarts = max_restarts
        self.backoff = backoff
        self.max_backoff = max_backoff
        self.output = output          # "inherit", "null" ou "capture"
        self.keep_lines = keep_lines
        self.state = "stopped"        # stopped, running, exited, backoff, failed
        self.process = null
        self.pid = null
        self.restarts = 0
        self.last_code = null
        self.started_at = null
        self.next_start = null
        self.lines = []
        self._partial = {"stdout": "", "stderr": ""}
        self.stop_requested = false

    func running():
        return self.state == "running"

    func uptime():
        if self.state != "running" or self.started_at == null:
            return 0.0
        return _now() - self.started_at

    func describe():
        if self.state == "running":
            return "en cours (pid " + str(self.pid) + ")"
        if self.state == "backoff":
            return "redémarrage prévu (" + str(self.restarts) + " déjà)"
        if self.last_code != null:
            return self.state + " : " + _ec.describe(self.last_code)
        return self.state

    func _keep(stream, text):
        data := self._partial[stream] + text
        parts := _s.split(data, "\n")
        last := len(parts) - 1
        i := 0
        while i < last:
            append(self.lines, (stream, parts[i]))
            i += 1
        self._partial[stream] = parts[last]
        while len(self.lines) > self.keep_lines:
            pop(self.lines, 0)

    func _flush_partial():
        for stream in ["stdout", "stderr"]:
            if self._partial[stream] != "":
                append(self.lines, (stream, self._partial[stream]))
                self._partial[stream] = ""

class ProcessManager:
    func init():
        self._procs = {}
        self._order = []
        self._handlers = {}

    func on(event, handler):
        if not contains_key(self._handlers, event):
            self._handlers[event] = []
        append(self._handlers[event], handler)
        return self

    func _emit(mp, event, code=null):
        if contains_key(self._handlers, event):
            ev := {"name": mp.name, "event": event, "code": code, "pid": mp.pid, "restarts": mp.restarts}
            for h in self._handlers[event]:
                h(ev)

    func add(name, command, options=null):
        o := _options(options)
        restart := o["restart"]
        output := o["output"]
        if contains_key(self._procs, name):
            raise("ArgumentError", "ProcessManager.add : nom déjà utilisé '" + name + "'")
        if restart != NEVER and restart != ON_FAILURE and restart != ALWAYS:
            raise("ArgumentError", "ProcessManager.add : politique de redémarrage inconnue '" + str(restart) + "'")
        if output != "inherit" and output != "null" and output != "capture":
            raise("ArgumentError", "ProcessManager.add : sortie \"inherit\", \"null\" ou \"capture\" attendue")
        mp := ManagedProcess(name, _to_command("add", command), restart, o["max_restarts"], o["backoff"], o["max_backoff"], output,
                             o["keep_lines"])
        self._procs[name] = mp
        append(self._order, name)
        return mp

    func get(name):
        if not contains_key(self._procs, name):
            raise("ArgumentError", "ProcessManager : processus inconnu '" + str(name) + "'")
        return self._procs[name]

    func names():
        return [n for n in self._order]

    func remove(name):
        mp := self.get(name)
        if mp.running():
            self.stop(name)
        remove(self._procs, name)
        self._order = [n for n in self._order if n != name]

    func _launch(mp):
        c := mp.command
        if mp.output == "capture":
            c = c.stdout("pipe").stderr("pipe")
        elif mp.output == "null":
            c = c.stdout("null").stderr("null")
        mp.process = c.group().spawn()
        mp.pid = mp.process.pid()
        mp.state = "running"
        mp.started_at = _now()
        mp.stop_requested = false
        self._emit(mp, "start")

    func start(name):
        mp := self.get(name)
        if mp.running():
            return mp
        mp.restarts = 0
        self._launch(mp)
        return mp

    func start_all():
        for n in self._order:
            self.start(n)
        return self

    # Arrêt propre : TERM, puis KILL après grace secondes (tout le groupe du processus). Renvoie le code.
    func stop(name, grace=3.0):
        mp := self.get(name)
        if mp.state == "backoff":
            mp.state = "stopped"
            return mp.last_code
        if not mp.running():
            return mp.last_code
        mp.stop_requested = true
        code := mp.process.stop(grace, true)
        self._drain(mp)
        self._finish(mp, code)
        mp.state = "stopped"
        self._emit(mp, "stop", code)
        return code

    func stop_all(grace=3.0):
        # TERM à tous d'abord, puis attente commune : l'arrêt total dure au plus grace (+ KILL).
        for n in self._order:
            mp := self._procs[n]
            if mp.running():
                mp.stop_requested = true
                mp.process.kill("TERM", true)
        deadline := _now() + grace
        for n in self._order:
            mp := self._procs[n]
            if mp.running():
                left := deadline - _now()
                if left < 0:
                    left = 0
                code := mp.process.wait(left)
                if code == null:
                    mp.process.kill("KILL", true)
                    code = mp.process.wait()
                self._drain(mp)
                self._finish(mp, code)
                mp.state = "stopped"
                self._emit(mp, "stop", code)
            elif mp.state == "backoff":
                mp.state = "stopped"
        return self

    func restart(name, grace=3.0):
        self.stop(name, grace)
        return self.start(name)

    func _drain(mp):
        if mp.output != "capture" or mp.process == null:
            return
        for stream in ["stdout", "stderr"]:
            while true:
                chunk := mp.process.read(stream, 65536, 0)
                if chunk == null or chunk == "":
                    break
                mp._keep(stream, chunk)

    func _finish(mp, code):
        mp.last_code = code
        mp._flush_partial()
        mp.process.close()
        mp.process = null
        mp.pid = null

    func _should_restart(mp, code):
        if mp.stop_requested:
            return false
        if mp.restart == ALWAYS:
            return true
        return mp.restart == ON_FAILURE and code != 0

    # Un tour de surveillance : lit les sorties capturées, constate les fins, planifie et exécute les
    # redémarrages. Renvoie la liste des événements survenus.
    func poll():
        events := []
        for n in self._order:
            mp := self._procs[n]
            if mp.running():
                self._drain(mp)
                code := mp.process.poll()
                if code != null:
                    self._drain(mp)
                    self._finish(mp, code)
                    append(events, {"name": n, "event": "exit", "code": code})
                    self._emit(mp, "exit", code)
                    if self._should_restart(mp, code):
                        if mp.restarts >= mp.max_restarts:
                            mp.state = "failed"
                            append(events, {"name": n, "event": "failed", "code": code})
                            self._emit(mp, "failed", code)
                        else:
                            delay := mp.backoff
                            k := 0
                            while k < mp.restarts and delay < mp.max_backoff:
                                delay = delay * 2
                                k += 1
                            if delay > mp.max_backoff:
                                delay = mp.max_backoff
                            mp.state = "backoff"
                            mp.next_start = _now() + delay
                    else:
                        mp.state = "exited"
            elif mp.state == "backoff" and _now() >= mp.next_start:
                mp.restarts += 1
                self._launch(mp)
                append(events, {"name": n, "event": "restart", "code": mp.last_code})
                self._emit(mp, "restart", mp.last_code)
        return events

    # Vrai tant qu'un processus tourne ou attend son redémarrage.
    func active():
        for n in self._order:
            st := self._procs[n].state
            if st == "running" or st == "backoff":
                return true
        return false

    # Surveille pendant duration secondes (null : jusqu'à ce que plus rien ne tourne), tous les interval.
    func supervise(duration=null, interval=0.05):
        end := null
        if duration != null:
            end = _now() + duration
        while true:
            self.poll()
            if not self.active():
                return self
            if end != null and _now() >= end:
                return self
            _os.sleep(interval)

    # Attend la fin d'un processus (sans redémarrage) ; renvoie son code, ou null après timeout.
    func wait(name, timeout=null):
        mp := self.get(name)
        end := null
        if timeout != null:
            end = _now() + timeout
        while mp.running() or mp.state == "backoff":
            self.poll()
            if not (mp.running() or mp.state == "backoff"):
                break
            if end != null and _now() >= end:
                return null
            _os.sleep(0.02)
        return mp.last_code

    func wait_all(timeout=null):
        self.supervise(timeout)
        return not self.active()

    # Dernières lignes capturées : liste de (flux, ligne).
    func logs(name, stream=null):
        mp := self.get(name)
        if mp.running():
            self._drain(mp)
        if stream == null:
            return [l for l in mp.lines]
        return [l for l in mp.lines if l[0] == stream]

    func status():
        out := {}
        for n in self._order:
            mp := self._procs[n]
            out[n] = {"state": mp.state, "pid": mp.pid, "restarts": mp.restarts, "last_code": mp.last_code,
                      "uptime": mp.uptime(), "description": mp.describe()}
        return out

    func running():
        return [n for n in self._order if self._procs[n].running()]

# ---------------------------------------------------------------------
# Exécution parallèle bornée
# ---------------------------------------------------------------------

# Exécute les commandes, au plus max_parallel à la fois ; renvoie les process.Result dans l'ordre des commandes.
# timeout : délai de CHAQUE commande (TERM puis KILL, Result.timed_out). stop_on_error : n'en lance plus après
# un échec (les suivantes ont alors un Result de code null).
func run_parallel(commands, max_parallel=null, timeout=null, stop_on_error=false):
    if max_parallel == null:
        max_parallel = _os.cpu_count()
    if max_parallel < 1:
        raise("ArgumentError", "run_parallel : max_parallel >= 1 attendu")
    cmds := [_to_command("run_parallel", c) for c in commands]
    results := [null for c in cmds]
    running := []     # [index, Process, début, stdout, stderr, timed_out]
    next := 0
    failed := false
    while next < len(cmds) or len(running) > 0:
        while len(running) < max_parallel and next < len(cmds) and not failed:
            p := cmds[next].stdin("null").stdout("pipe").stderr("pipe").group().spawn()
            append(running, [next, p, _now(), [], [], false])
            next += 1
        if failed and len(running) == 0:
            break
        progressed := false
        still := []
        for r in running:
            p := r[1]
            for pair in [[3, "stdout"], [4, "stderr"]]:
                while true:
                    chunk := p.read(pair[1], 65536, 0)
                    if chunk == null or chunk == "":
                        break
                    append(r[pair[0]], chunk)
                    progressed = true
            code := p.poll()
            if code == null and timeout != null and _now() - r[2] > timeout:
                r[5] = true
                code = p.stop(1.0, true)
            if code != null:
                for pair in [[3, "stdout"], [4, "stderr"]]:
                    while true:
                        chunk := p.read(pair[1], 65536, 0.05)
                        if chunk == null or chunk == "":
                            break
                        append(r[pair[0]], chunk)
                p.close()
                results[r[0]] = _proc.Result(code, _s.join("", r[3]), _s.join("", r[4]), r[5])
                if stop_on_error and (code != 0 or r[5]):
                    failed = true
                progressed = true
            else:
                append(still, r)
        running = still
        if not progressed:
            _os.sleep(0.005)
    i := 0
    while i < len(results):
        if results[i] == null:
            results[i] = _proc.Result(null, "", "", false)
        i += 1
    return results

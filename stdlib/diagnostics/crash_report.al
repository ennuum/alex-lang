# ALEX STANDARD LIBRARY — diagnostics.crash_report
#
# Rapports de plantage : à partir d'une erreur rattrapée, un rapport complet et autonome — type et message,
# pile d'appels avec les lignes de source (et un extrait autour de la ligne fautive), contexte du processus
# (pid, arguments, dossier courant, plateforme), mémoire et ramasse-miettes au moment de l'erreur, variables
# d'environnement choisies — en texte lisible ou en JSON, enregistrable dans un dossier de rapports.
#
#   use diagnostics.crash_report as cr
#   try:
#       principal()
#   catch e:
#       r := cr.CrashReport(e, {"version": "1.4.2", "utilisateur": id})
#       print(r.to_text())
#       r.save("/var/log/monapp/plantages")        # plantage-AAAAMMJJ-HHMMSS-pid.json (+ .txt)
#   code := cr.guard(principal, "/tmp/plantages")   # exécute ; en cas d'erreur : rapport enregistré, code 1
#   print(cr.list_reports("/tmp/plantages"))
#
# Les valeurs de variables d'environnement dont le nom évoque un secret (PASSWORD, TOKEN, SECRET, KEY) sont
# masquées. Erreurs : IoError (dossier non inscriptible).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use io as _io
use json as _json
use time as _time
use diagnostics.stack_trace as _st
use memory.memory_stats as _ms
use _native_gc as _gc

const ENV_KEYS := ["PATH", "HOME", "USER", "LANG", "PWD", "SHELL", "ALEX_EXE", "ALEX_PATH"]
const SECRET_WORDS := ["PASSWORD", "PASSWD", "TOKEN", "SECRET", "KEY", "CREDENTIAL"]

func _safe(fn):
    try:
        return fn()
    catch e:
        return null

func _masked(name, value):
    up := _s.upper(name)
    for w in SECRET_WORDS:
        if _s.contains(up, w):
            return "***"
    return value

func _excerpt(file, line, around=3):
    if file == null or line == null or line < 1:
        return []
    lines := []
    try:
        lines = _s.split(_io.read_file(file), "\n")
    catch e:
        return []
    out := []
    a := line - around
    if a < 1:
        a = 1
    b := line + around
    if b > len(lines):
        b = len(lines)
    k := a
    while k <= b:
        mark := "   "
        if k == line:
            mark = ">> "
        append(out, mark + str(k) + " | " + lines[k - 1])
        k += 1
    return out

class CrashReport:
    func init(error, context=null, env_keys=null):
        self.error_type = error.type
        self.message = error.message
        self.trace = _st.from_error(error)
        self.context = context
        if self.context == null:
            self.context = {}
        self.time = _time.time()
        self.timestamp = _safe(() => _time.strftime("%Y-%m-%d %H:%M:%S", _time.time()))
        self.pid = _safe(() => _os.pid())
        self.args = _safe(() => _os.args())
        self.cwd = _safe(() => _os.cwd())
        self.platform = _safe(() => _os.platform())
        self.kernel = _safe(() => _os.version())
        self.executable = _safe(() => _os.executable())
        self.memory = _safe(() => _ms.snapshot().to_dict())
        self.gc = _safe(() => _gc.stats())
        keys := env_keys
        if keys == null:
            keys = ENV_KEYS
        self.env = {}
        for k in keys:
            v := _safe(() => _os.get_env(k, null))
            if v != null:
                self.env[k] = _masked(k, v)
        top := self.trace.top()
        self.excerpt = []
        if top != null:
            self.excerpt = _excerpt(top.file, top.line)

    func location():
        top := self.trace.top()
        if top == null:
            return null
        return top.location()

    func to_dict():
        return {"format": "alex-crash-report", "version": 1, "error": {"type": self.error_type, "message": self.message},
                "location": self.location(), "trace": self.trace.to_list(), "excerpt": self.excerpt,
                "time": self.time, "timestamp": self.timestamp, "process": {"pid": self.pid, "args": self.args,
                "cwd": self.cwd, "platform": self.platform, "kernel": self.kernel, "executable": self.executable},
                "memory": self.memory, "gc": self.gc, "env": self.env, "context": self.context}

    func to_json():
        return _json.pretty(self.to_dict())

    func to_text():
        lines := ["=== Rapport de plantage ALEX ===", "Date      : " + str(self.timestamp),
                  "Erreur    : " + self.error_type + " : " + str(self.message), "Lieu      : " + str(self.location()), ""]
        append(lines, self.trace.format(true))
        if len(self.excerpt) > 0:
            append(lines, "")
            append(lines, "Source :")
            for l in self.excerpt:
                append(lines, "  " + l)
        append(lines, "")
        append(lines, "Processus : pid " + str(self.pid) + ", " + str(self.platform) + " " + str(self.kernel))
        append(lines, "Arguments : " + str(self.args))
        append(lines, "Dossier   : " + str(self.cwd))
        if self.memory != null:
            append(lines, "Mémoire   : résident " + _ms.format_bytes(self.memory["rss"]) + ", natif " + _ms.format_bytes(self.memory["live_bytes"]) + ", objets " + str(self.memory["gc_live"]))
        if len(self.context) > 0:
            append(lines, "Contexte  :")
            for k in self.context:
                append(lines, "  " + k + " = " + str(self.context[k]))
        if len(self.env) > 0:
            append(lines, "Environnement :")
            for k in self.env:
                append(lines, "  " + k + "=" + str(self.env[k]))
        return _s.join("\n", lines)

    # Enregistre JSON (+ texte) dans folder ; chemin du JSON.
    func save(folder, with_text=true):
        if not _os.exists(folder):
            _os.mkdir_all(folder)
        stamp := _safe(() => _time.strftime("%Y%m%d-%H%M%S", self.time))
        if stamp == null:
            stamp = str(to_int(self.time))
        base := folder + "/plantage-" + stamp + "-" + str(self.pid) + "-" + str(to_int(_os.monotonic_time() * 1000) % 100000)
        _io.write_file(base + ".json", self.to_json())
        if with_text:
            _io.write_file(base + ".txt", self.to_text())
        return base + ".json"

func capture(error, context=null):
    return CrashReport(error, context)

# Exécute fn ; en cas d'erreur, enregistre un rapport dans folder (si donné), l'affiche sur la sortie
# d'erreur, et rend 1 (0 si tout va bien). rethrow : relance l'erreur après le rapport.
func guard(fn, folder=null, context=null, rethrow=false):
    try:
        fn()
        return 0
    catch e:
        r := CrashReport(e, context)
        path := null
        if folder != null:
            path = r.save(folder)
        _io.write_file("/dev/stderr", r.to_text() + "\n")
        if path != null:
            _io.write_file("/dev/stderr", "Rapport : " + path + "\n")
        if rethrow:
            raise(e.type, e.message)
        return 1

func list_reports(folder):
    if not _os.exists(folder):
        return []
    out := [n for n in _os.list_dir(folder) if _s.starts_with(n, "plantage-") and _s.ends_with(n, ".json")]
    return out

func load(path):
    d := _json.parse(_io.read_file(path))
    if not ("format" in d) or d["format"] != "alex-crash-report":
        raise("ValueError", "crash_report.load : ce n'est pas un rapport de plantage ALEX")
    return d

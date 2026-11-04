# ALEX STANDARD LIBRARY — diagnostics.profiler
#
# Profilage du temps d'exécution, de deux façons :
#   1. Profileur NATIF de la VM (`alexc run --profile=rapport.json`) : profile_script(fichier) exécute un
#      programme dans un processus fils avec le profileur intégré et relit son rapport — temps propre et
#      total, appels et instructions par fonction, lignes les plus coûteuses. Aucune modification du code.
#   2. Profileur par INSTRUMENTATION : Profiler.wrap(f) / Profiler.run(nom, f) mesurent des fonctions choisies
#      dans le programme courant (temps propre = temps total moins celui des fonctions profilées appelées).
#
#   use diagnostics.profiler as pf
#   rep := pf.profile_script("calcul.al", ["--taille", "1000"])
#   print(rep.format(10))                # 10 fonctions les plus coûteuses
#   print(rep.hottest_lines(5))
#   p := pf.Profiler()
#   lent := p.wrap(fonction_lente, "fonction_lente")
#   lent(3)
#   p.run("étape", () => traiter())
#   print(p.report())                    # appels, total, propre, moyenne
#   rep2 := pf.profile_source("func f(n) => n * 2\nfor i in 0..1000:\n    f(i)\n")
#
# Erreurs : TypeError (fonction attendue), IoError (exécutable alex introuvable), ProfilerError (programme
# profilé en échec : code de sortie et stderr dans le message).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use io as _io
use json as _json

class FunctionStats:
    func init(name, file=null, line=null):
        self.name = name
        self.file = file
        self.line = line
        self.calls = 0
        self.total = 0.0
        self.self_time = 0.0
        self.instructions = null

    func mean():
        if self.calls == 0:
            return 0.0
        return self.total / self.calls

    func to_dict():
        return {"name": self.name, "file": self.file, "line": self.line, "calls": self.calls, "total": self.total,
                "self": self.self_time, "instructions": self.instructions}

func _ms(x):
    if x == null:
        return "-"
    return str(to_int(x * 100000 + 0.5) / 100.0) + " ms"

func _pad(s, n):
    out := s
    while len(out) < n:
        out += " "
    return out

func _lpad(s, n):
    out := s
    while len(out) < n:
        out = " " + out
    return out

func _sort_by(items, key):
    out := items[:]
    i := 1
    while i < len(out):
        v := out[i]
        j := i - 1
        while j >= 0 and key(out[j]) < key(v):
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = v
        i += 1
    return out

class Profiler:
    func init():
        self.stats = {}
        self.order = []
        self.stack = []           # [stats, début, temps des enfants]
        self.enabled = true

    func _get(name):
        if not (name in self.stats):
            self.stats[name] = FunctionStats(name)
            append(self.order, name)
        return self.stats[name]

    func _enter(name):
        append(self.stack, [self._get(name), _os.monotonic_time(), 0.0])

    func _leave():
        fr := self.stack[len(self.stack) - 1]
        self.stack = self.stack[:len(self.stack) - 1]
        d := _os.monotonic_time() - fr[1]
        st := fr[0]
        st.calls += 1
        st.total += d
        st.self_time += d - fr[2]
        if len(self.stack) > 0:
            self.stack[len(self.stack) - 1][2] += d

    func call(name, fn, args):
        if not self.enabled:
            return fn(*args)
        self._enter(name)
        try:
            return fn(*args)
        finally:
            self._leave()

    func wrap(fn, name=null):
        if type(fn) != "function":
            raise("TypeError", "Profiler.wrap : fonction attendue")
        nm := name
        if nm == null:
            nm = "fonction_" + str(len(self.order) + 1)
        self._get(nm)
        return (*args) => self.call(nm, fn, args)

    func run(name, fn):
        return self.call(name, fn, [])

    func get(name):
        if name in self.stats:
            return self.stats[name]
        return null

    func reset():
        self.stats = {}
        self.order = []
        self.stack = []

    func functions():
        return _sort_by([self.stats[n] for n in self.order], (s) => s.self_time)

    func report(top=20):
        lines := [_pad("fonction", 28) + _lpad("appels", 8) + _lpad("total", 13) + _lpad("propre", 13) + _lpad("moyenne", 13)]
        for s in self.functions()[:top]:
            append(lines, _pad(s.name, 28) + _lpad(str(s.calls), 8) + _lpad(_ms(s.total), 13) + _lpad(_ms(s.self_time), 13) + _lpad(_ms(s.mean()), 13))
        return _s.join("\n", lines)

class ProfileReport:
    func init(d, stdout="", stderr="", code=0):
        self.raw = d
        self.elapsed = d["elapsed"]
        self.instructions = d["instructions"]
        self.functions = []
        for f in d["functions"]:
            st := FunctionStats(f["name"], f["file"], f["line"])
            st.calls = f["calls"]
            st.total = f["total"]
            st.self_time = f["self"]
            st.instructions = f["instructions"]
            append(self.functions, st)
        self.lines = d["lines"]
        self.stdout = stdout
        self.stderr = stderr
        self.exit_code = code

    func function(name):
        for f in self.functions:
            if f.name == name:
                return f
        return null

    func top(n=10):
        return _sort_by(self.functions, (s) => s.self_time)[:n]

    func hottest_lines(n=10):
        out := []
        for l in self.lines[:n]:
            where := l["file"]
            k := len(where) - 1
            while k >= 0 and where[k] != '/':
                k -= 1
            where = _s.substring(where, k + 1, len(where))
            append(out, where + ":" + str(l["line"]) + " (" + l["function"] + ") " + _ms(l["self"]) + ", " + str(l["instructions"]) + " instr.")
        return _s.join("\n", out)

    func format(n=10):
        lines := ["Profil : " + _ms(self.elapsed) + ", " + str(self.instructions) + " instructions",
                  _pad("fonction", 28) + _lpad("appels", 9) + _lpad("propre", 13) + _lpad("total", 13) + _lpad("instr.", 12)]
        for s in self.top(n):
            append(lines, _pad(s.name, 28) + _lpad(str(s.calls), 9) + _lpad(_ms(s.self_time), 13) + _lpad(_ms(s.total), 13) + _lpad(str(s.instructions), 12))
        return _s.join("\n", lines)

func alex_executable():
    exe := _os.executable()
    if exe != null and exe != "":
        return exe
    if _os.exists("/proc/self/exe"):
        return "/proc/self/exe"
    raise("IoError", "profiler : exécutable alex introuvable (variable ALEX_EXE)")

func _tmp(suffix):
    return "/tmp/alex_profile_" + str(_os.pid()) + "_" + str(to_int(_os.monotonic_time() * 1000000)) + suffix

# Exécute path avec le profileur natif ; ProfileReport.
func profile_script(path, args=null, allow_failure=false):
    out := _tmp(".json")
    a := ["run", "--profile=" + out, path]
    if args != null:
        a = a + args
    r := _os.run(alex_executable(), a)
    if not _os.exists(out):
        raise("ProfilerError", "profile_script : aucun rapport produit (code " + str(r["code"]) + ") : " + r["stderr"])
    d := _json.parse(_io.read_file(out))
    _os.remove(out)
    if r["code"] != 0 and not allow_failure:
        raise("ProfilerError", "profile_script : le programme a échoué (code " + str(r["code"]) + ") : " + _s.trim(r["stderr"]))
    return ProfileReport(d, r["stdout"], r["stderr"], r["code"])

func profile_source(source, args=null):
    path := _tmp(".al")
    _io.write_file(path, source)
    try:
        return profile_script(path, args)
    finally:
        _os.remove(path)

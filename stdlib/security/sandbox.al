# ALEX STANDARD LIBRARY — security.sandbox
#
# Exécution confinée de code non fiable, à deux niveaux :
#   1. Sandbox (processus) : le programme ALEX (ou une commande) tourne dans un PROCESSUS FILS avec limites du
#      noyau posées avant son démarrage (temps processeur, mémoire, taille des fichiers, descripteurs, nombre de
#      processus), délai réel, environnement vidé, dossier de travail temporaire jetable, et — si le noyau
#      l'autorise (espaces de noms utilisateur, `unshare`) — SANS RÉSEAU. Le résultat indique quelles
#      protections ont réellement été appliquées (enforced) : rien n'est simulé.
#   2. evaluate / run_restricted (dans le processus) : code ALEX compilé vers l'IR de compiler.ir et exécuté par
#      son interpréteur, SANS import ni accès à l'hôte : seules les fonctions fournies sont appelables, et le
#      nombre d'instructions est borné.
#
#   use security.sandbox as sb
#   s := sb.Sandbox()
#   s.cpu_seconds = 2
#   s.memory_mb = 256
#   s.network = false
#   r := s.run_source("print(1 + 1)\n")
#   print(r.ok(), r.stdout, r.enforced)      # true "2\n" {"cpu": true, "memory": true, "network": true, ...}
#   r2 := s.run_command("ls", ["-la"])
#   print(sb.evaluate("x * 2 + y", {"x": 20, "y": 2}))                  # 42
#   out := sb.run_restricted("func f(n) => n * n\nprint(f(7))\n")        # {"output": ["49"], "steps": ...}
#
# Windows : pas de limites du noyau (ulimit) ni d'isolement réseau ; seuls le délai réel, l'environnement vidé et
# le dossier jetable s'appliquent, et enforced le dit (cpu, memory, network... à false).
# Limites : le processus fils peut lire les fichiers lisibles par l'utilisateur (aucun système de fichiers
# privé n'est monté) ; pour un confinement fort, combiner avec un compte dédié ou un conteneur.
# Erreurs : SandboxError (programme refusé à la compilation, construction interdite), TimeoutError géré
# (timed_out dans le résultat), IrError (limite d'instructions dans run_restricted).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use io as _io
use process.process_builder as _pb
use compiler.parser as _ps
use compiler.ir as _ir
use compiler.type_checker as _tc

class SandboxResult:
    func init(code, stdout, stderr, timed_out, duration, enforced, command):
        self.code = code
        self.stdout = stdout
        self.stderr = stderr
        self.timed_out = timed_out
        self.duration = duration
        self.enforced = enforced
        self.command = command

    func ok():
        return self.code == 0 and not self.timed_out

    # Tué par un signal (code < 0, ou 128+n via sh) : nom probable de la limite atteinte.
    func killed_by():
        c := self.code
        if c > 128 and c < 160:
            c = -(c - 128)
        if c == -24:
            return "cpu"
        if c == -9:
            if self.timed_out:
                return "timeout"
            return "kill"
        if c == -25:
            return "file_size"
        if c == -11:
            return "memory"
        return null

    func __str__():
        return "SandboxResult(code " + str(self.code) + ", " + str(to_int(self.duration * 1000)) + " ms, délai dépassé " + str(self.timed_out) + ")"

_unshare := [null]

# Windows : ni ulimit (sh) ni unshare ; seuls le délai, l'environnement et le dossier jetable s'appliquent.
const _WIN := _os.platform() == "windows"
# Variables sans lesquelles un processus Windows ne démarre pas correctement (Winsock, dossiers temporaires).
const _WIN_ENV := ["SYSTEMROOT", "SystemRoot", "WINDIR", "TEMP", "TMP"]

func _tmp_name(prefix):
    return _os.join(_os.tmp_dir(), prefix + str(_os.pid()) + "_" + str(to_int(_os.monotonic_time() * 1000000) % 1000000000))

func network_isolation_available():
    if _WIN:
        return false
    if _unshare[0] == null:
        ok := false
        try:
            r := _os.run("unshare", ["-r", "-n", "true"])
            ok = r["code"] == 0
        catch e:
            ok = false
        _unshare[0] = ok
    return _unshare[0]

class Sandbox:
    func init():
        self.cpu_seconds = 5
        self.memory_mb = 512
        self.file_size_mb = 16
        self.max_files = 64
        self.max_processes = null
        self.timeout = 10.0
        self.network = false
        self.keep_env = ["PATH", "LANG"]
        self.env = {}
        self.workdir = null
        self.input = null

    func _builder(program, args):
        enforced := {"cpu": false, "memory": false, "file_size": false, "files": false, "processes": false,
                     "timeout": self.timeout != null, "network": self.network, "env": true, "workdir": true}
        prog := program
        argv := args
        if not self.network:
            if network_isolation_available():
                argv = ["-r", "-n", prog] + argv
                prog = "unshare"
                enforced["network"] = true
            else:
                enforced["network"] = false
        b := _pb.ProcessBuilder(prog, argv)
        if _WIN:
            b.clear_env()
            for k in self.keep_env + _WIN_ENV:
                v := _os.get_env(k, null)
                if v != null:
                    b.env(k, v)
            for k in self.env:
                b.env(k, self.env[k])
            if self.timeout != null:
                b.timeout(self.timeout, 0.5)
            if self.input != null:
                b.input(self.input)
            return [b, enforced]
        if self.cpu_seconds != null:
            b.limit("cpu", self.cpu_seconds, self.cpu_seconds + 1)
            enforced["cpu"] = true
        if self.memory_mb != null:
            b.limit("as", self.memory_mb * 1024, self.memory_mb * 1024)
            enforced["memory"] = true
        if self.file_size_mb != null:
            b.limit("fsize", self.file_size_mb * 2048, self.file_size_mb * 2048)
            enforced["file_size"] = true
        if self.max_files != null:
            b.limit("nofile", self.max_files, self.max_files)
            enforced["files"] = true
        if self.max_processes != null:
            b.limit("nproc", self.max_processes, self.max_processes)
            enforced["processes"] = true
        b.clear_env()
        for k in self.keep_env:
            v := _os.get_env(k, null)
            if v != null:
                b.env(k, v)
        for k in self.env:
            b.env(k, self.env[k])
        if self.timeout != null:
            b.timeout(self.timeout, 0.5)
        if self.input != null:
            b.input(self.input)
        return [b, enforced]

    func run_command(program, args=null):
        a := args
        if a == null:
            a = []
        tmp := self.workdir
        made := false
        if tmp == null:
            tmp = _tmp_name("alex_sandbox_")
            _os.mkdir_all(tmp)
            made = true
        bb := self._builder(program, a)
        b := bb[0]
        b.directory(tmp)
        t0 := _os.monotonic_time()
        r := null
        try:
            r = b.run()
        finally:
            if made:
                _rm_tree(tmp)
        return SandboxResult(r.code, r.stdout, r.stderr, r.timed_out, _os.monotonic_time() - t0, bb[1], b.to_list())

    # Exécute un texte source ALEX dans un processus confiné.
    func run_source(source, args=null):
        path := _tmp_name("alex_sandbox_src_") + ".al"
        _io.write_file(path, source)
        try:
            a := ["run", path]
            if args != null:
                a = a + args
            return self.run_command(_alex(), a)
        finally:
            _os.remove(path)

    func run_file(path, args=null):
        a := ["run", _os.absolute(path)]
        if args != null:
            a = a + args
        return self.run_command(_alex(), a)

func _alex():
    e := _os.executable()
    if e != null and e != "":
        return e
    return "/proc/self/exe"

func _rm_tree(path):
    if not _os.exists(path):
        return
    if _os.isdir(path):
        for n in _os.list_dir(path):
            _rm_tree(path + "/" + n)
        _os.rmdir(path)
    else:
        _os.remove(path)

# ---------------------------------------------------------------------------------------------------------
# Exécution restreinte dans le processus (IR)
# ---------------------------------------------------------------------------------------------------------

const SAFE_BUILTINS := ["len", "str", "abs", "min", "max", "range", "type", "append", "pop", "raise", "isinstance"]

func _restricted_builtins(allowed, extra):
    vm := _ir.Interpreter()
    out := {}
    for k in allowed:
        if k in vm.builtins:
            out[k] = vm.builtins[k]
    if extra != null:
        for k in extra:
            out[k] = extra[k]
    return out

func _forbid(program):
    for s in program.body:
        if s.kind == "Use" or s.kind == "FromUse":
            raise("SandboxError", "sandbox : les imports sont interdits (" + _s.join(".", s.path) + ")")

# Exécute source (ALEX, sous-ensemble de l'IR) : {"output": [...], "globals": {...}, "steps": n}.
func run_restricted(source, functions=null, max_steps=1000000, allowed=null):
    prog := null
    try:
        prog = _ps.parse(source, "<sandbox>")
    catch e:
        raise("SandboxError", "sandbox : " + e.message)
    _forbid(prog)
    al := allowed
    if al == null:
        al = SAFE_BUILTINS
    mod := null
    try:
        mod = _ir.lower(prog, "sandbox")
    catch e:
        raise("SandboxError", "sandbox : " + e.message)
    b := _restricted_builtins(al, functions)
    vm := _ir.Interpreter(null, max_steps)
    vm.builtins = b
    vm.capture()
    vm.run(mod)
    g := {}
    for k in vm.globals_of("sandbox"):
        g[k] = vm.globals_of("sandbox")[k]
    return {"output": vm.output, "globals": g, "steps": vm.steps}

# Évalue une expression avec des variables fournies (aucun autre nom accessible).
func evaluate(expression, variables=null, functions=null, max_steps=100000):
    e := null
    try:
        e = _ps.parse_expression(expression, "<expression>")
    catch err:
        raise("SandboxError", "sandbox : " + err.message)
    src := "__resultat := " + expression + "\n"
    vars := {}
    if variables != null:
        vars = variables
    fns := {}
    if functions != null:
        fns = functions
    for k in vars:
        fns[k] = vars[k]
    r := run_restricted(src, fns, max_steps, [])
    return r["globals"]["__resultat"]

# ALEX STANDARD LIBRARY — web.js.js_runtime_bridge
#
# Exécution de JavaScript dans un moteur EXTERNE installé (Node.js, Bun ou Deno) via web.process : détection et
# version du moteur, exécution d'un script ou d'un module, ÉVALUATION d'une expression avec retour de la
# valeur en ALEX (aller-retour JSON), appel d'une fonction JS avec des arguments ALEX, vérification de
# syntaxe par le moteur. Chaque exécution est un processus isolé avec délai maximal ; aucune donnée ALEX
# n'est interprétée comme du code (arguments transmis en JSON).
#
#   use web.js.js_runtime_bridge as rb
#   rt := rb.find_runtime()                  # Runtime (node, bun ou deno) ou null
#   rt.version()                             # ex. v22.11.0
#   rt.evaluate("[1, 2, 3].map(x => x * 2)") # [2, 4, 6]
#   rt.call("(a, b) => a + b", [20, 22])     # 42
#   rt.call("async (u) => (await Promise.resolve(u)).toUpperCase()", ["ada"])   # ADA
#   rt.run("console.log('bonjour')").stdout  # bonjour\n
#   rt.check_syntax("let = ;")               # (false, message d'erreur du moteur)
#   rb.available()                           # liste des moteurs trouvés
#
# Erreurs : JsBridgeError (moteur introuvable), JsRuntimeError (exception JS : message et pile ; délai dépassé).

from core use len, type
from collections use append
use string as _s
use json as _json
use io as _io
use os as _os
use process as _proc
use random as _random
use web.js.js_errors as _err
use web.js.js_validator as _val

const KINDS := ["node", "bun", "deno"]
const _MARK := "__ALEX_JS_RESULT__"
const _EXTRA_PATHS := ["/opt/node22/bin/node", "/usr/local/bin/node", "/usr/bin/node", "/opt/homebrew/bin/node", "/usr/local/bin/bun", "/usr/local/bin/deno"]

class RunResult:
    func init(code, stdout, stderr, timed_out):
        self.code = code
        self.stdout = stdout
        self.stderr = stderr
        self.timed_out = timed_out

    func ok():
        return self.code == 0 and not self.timed_out

class Runtime:
    func init(kind, path, timeout=30):
        if not (kind in KINDS):
            _err.bridge_error("Runtime", "moteur inconnu « " + str(kind) + " » (node, bun, deno)")
        self.kind = kind
        self.path = path
        self.timeout = timeout
        self.env = null
        self._version = null

    func version():
        if self._version == null:
            r := _proc.run(self.path, ["--version"], null, 10)
            v := _s.trim(r.stdout)
            if self.kind == "deno":
                v = _s.trim(_s.split(v, "\n")[0])
            self._version = v
        return self._version

    func _args(file):
        if self.kind == "deno":
            return ["run", "--quiet", "--no-prompt", file]
        if self.kind == "bun":
            return ["run", file]
        return [file]

    func _temp(code, ext=".mjs"):
        name := "alex_js_" + str(_os.pid()) + "_" + str(_random.getrandbits(40)) + ext
        path := _os.join(_os.tmp_dir(), name)
        _io.write_file(path, code)
        return path

    # Exécute un module ES (texte) ; stdin : texte transmis à l'entrée standard.
    func run(code, stdin=null, timeout=null):
        path := self._temp(code)
        r := null
        try:
            r = _proc.run(self.path, self._args(path), stdin, timeout if timeout != null else self.timeout, null, self.env)
        finally:
            try:
                _os.remove(path)
            catch e:
                pass
        return RunResult(r.code, r.stdout, r.stderr, r.timed_out)

    # Évalue une expression JS (await permis) et renvoie sa valeur en ALEX (via JSON ; undefined -> null).
    func evaluate(expression, timeout=null):
        return self._json_call("(async () => (" + str(expression) + "\n))()", [], timeout)

    # Appelle une fonction JS (source d'une fonction ou d'une fléchée) avec des arguments ALEX.
    func call(function_source, args=null, timeout=null):
        return self._json_call("(" + str(function_source) + "\n)(...__args)", args if args != null else [], timeout)

    # Exécute un corps de fonction async (instructions) ; sa valeur de return est renvoyée.
    func execute(body, args=null, timeout=null):
        return self._json_call("(async (...__a) => {\n" + str(body) + "\n})(...__args)", args if args != null else [], timeout)

    func _json_call(expr_code, args, timeout):
        payload := _json.stringify(args, null, false)
        wrapper := "const __args = JSON.parse(" + _json.stringify(payload, null, false) + ");\n" + "const __out = (t) => { console.log(\"" + _MARK + "\" + t); };\n" + "try {\n  const __v = await (" + expr_code + ");\n" + "  __out(JSON.stringify({ ok: true, value: __v === undefined ? null : __v }, (k, v) => typeof v === \"bigint\" ? v.toString() : v));\n" + "} catch (e) {\n  __out(JSON.stringify({ ok: false, name: (e && e.name) || \"Error\", message: String(e && e.message !== undefined ? e.message : e), stack: (e && e.stack) || \"\" }));\n}\n"
        r := self.run(wrapper, null, timeout)
        if r.timed_out:
            _err.runtime_error(self.kind, "délai dépassé (" + str(timeout if timeout != null else self.timeout) + " s)")
        line := null
        for l in _s.split(r.stdout, "\n"):
            if _s.starts_with(l, _MARK):
                line = l[len(_MARK):len(l)]
        if line == null:
            msg := _s.trim(r.stderr) if _s.trim(r.stderr) != "" else _s.trim(r.stdout)
            _err.runtime_error(self.kind, "échec d'exécution (code " + str(r.code) + ") : " + msg)
        d := _json.parse(line)
        if not d["ok"]:
            _err.runtime_error(self.kind, d["name"] + ": " + d["message"] + ("\n" + d["stack"] if d["stack"] != "" else ""))
        return d["value"]

    # (vrai, null) si le moteur accepte la syntaxe du module, sinon (faux, message).
    func check_syntax(code, module=true):
        if self.kind != "node":
            # bun et deno n'ont pas de vérification sans exécution : contrôle lexical de web.js.js_validator
            r0 := _val.validate(code)
            if r0.is_valid():
                return (true, null)
            return (false, str(r0.errors()[0]))
        path := self._temp(code, ".mjs" if module else ".cjs")
        r := null
        try:
            r = _proc.run(self.path, ["--check", path], null, 10)
        finally:
            try:
                _os.remove(path)
            catch e2:
                pass
        if r.code == 0:
            return (true, null)
        return (false, _s.trim(r.stderr))

    func __str__():
        return self.kind + " " + self.version()

func _candidate(kind):
    p := _proc.which(kind)
    if p != null:
        return p
    for x in _EXTRA_PATHS:
        if _s.ends_with(x, "/" + kind) and _os.exists(x):
            return x
    return null

# Premier moteur disponible selon l'ordre de préférence (variable ALEX_JS_RUNTIME : chemin ou nom imposé).
func find_runtime(prefer=null, timeout=30):
    forced := _os.getenv("ALEX_JS_RUNTIME")
    if forced != null and forced != "":
        kind := "node"
        for k in KINDS:
            if _s.contains(forced, k):
                kind = k
        path := forced if _s.contains(forced, "/") else _candidate(forced)
        if path != null:
            return Runtime(kind, path, timeout)
    order := prefer if prefer != null else KINDS
    for k in order:
        p := _candidate(k)
        if p != null:
            return Runtime(k, p, timeout)
    return null

func require_runtime(prefer=null, timeout=30):
    rt := find_runtime(prefer, timeout)
    if rt == null:
        _err.bridge_error("js_runtime_bridge", "aucun moteur JavaScript trouvé (node, bun ou deno dans le PATH, ou ALEX_JS_RUNTIME)")
    return rt

# Moteurs trouvés : liste de (nom, chemin).
func available():
    out := []
    for k in KINDS:
        p := _candidate(k)
        if p != null:
            append(out, (k, p))
    return out

# Raccourcis avec le premier moteur trouvé.
func evaluate(expression, timeout=30):
    return require_runtime(null, timeout).evaluate(expression)

func call(function_source, args=null, timeout=30):
    return require_runtime(null, timeout).call(function_source, args)

# ALEX STANDARD LIBRARY — process
#
# Lancer et piloter des processus fils, sans shell.
#
# Architecture
#   process.al        API publique ALEX (Command, Process, Result, run, ...).
#   _native_process   primitives système (runtime/alex/native/dyn_nat.al) : table de
#                     handles, pipes, délais, signaux. Deux implémentations :
#                     POSIX (fork/exec, poll) et Windows (CreateProcessW,
#                     tubes anonymes, objets Job pour les groupes ; kill(sig)
#                     termine le processus et rapporte le code -sig).
#
# Principes
#   - AUCUN shell : le programme est cherché dans le PATH, les arguments sont
#     passés tels quels. Pas d'échappement à faire, pas d'injection possible.
#   - Un code de sortie non nul n'est PAS une erreur (sauf check=true).
#     code < 0 : processus tué par le signal -code (sous Windows : par kill()).
#   - Les flux sont du texte UTF-8 ; un caractère n'est jamais coupé en deux
#     entre deux lectures.
#   - Pas de GC des handles : un Process se libère avec close(). run() et
#     check_output() le font eux-mêmes, y compris en cas d'erreur.
#
# Erreurs
#   IoError        programme introuvable, droits, pipe cassé...
#   TypeError      argument d'un mauvais type.
#   ArgumentError  valeur invalide (mode inconnu, signal inconnu, ...).
#   ProcessError   check=true et code de sortie non nul.
#   TimeoutError   check=true (ou check_output) et délai dépassé.
#
# Exemple
#   use process
#   r := process.run("git", ["rev-parse", "HEAD"])
#   if r.ok():
#       print(r.stdout)
#
#   p := process.Command("sort").stdin("pipe").stdout("pipe").spawn()
#   p.write("b\na\n")
#   p.close_stdin()
#   print(p.read_all())
#   p.wait()
#   p.close()

from core use len, type
from collections use append, keys
use string as _s
use os as _os
use _native_process as _p

# Modes pour stdin / stdout / stderr (ou un bout de tube d'io.pipe / un descripteur entier : io.pipe.pipeline).
const INHERIT := "inherit"
const PIPE := "pipe"
const DEVNULL := "null"
const STDOUT := "stdout"

# ---------------------------------------------------------------------
# Outils internes
# ---------------------------------------------------------------------

func _require():
    if not _p.supported():
        raise("IoError", "process : non supporté sur cette plateforme (utiliser os.run / os.spawn)")

func _mode(fn, value, label, allow_merge):
    if value == "inherit":
        return 0
    if value == "pipe":
        return 1
    if value == "null":
        return 2
    if value == "stdout" and allow_merge:
        return 3
    # Descripteur : un bout de tube d'io.pipe (champ fd) ou un entier.
    if type(value) == "int":
        if value < 0:
            raise("ArgumentError", "process." + fn + "() : descripteur négatif pour " + label)
        return [4, value]
    if type(value) != "str" and value != null:
        fd := null
        try:
            fd = value.fd
        catch e:
            fd = null
        if type(fd) == "int":
            return [4, fd]
    raise("ArgumentError", "process." + fn + "() : mode " + label + " invalide '" + str_of(value) + "'")

func str_of(v):
    if type(v) == "str":
        return v
    return "<" + type(v) + ">"

func _str_list(fn, value, label):
    if value == null:
        return []
    t := type(value)
    if t != "list" and t != "tuple":
        raise("TypeError", "process." + fn + "() : " + label + " doit être une list de str (obtenu '" + t + "')")
    return value

# Environnement final : hérité (sauf clear), puis surcharges. Une valeur null
# SUPPRIME la variable. Retourne null (= hériter tel quel) ou une list "K=V".
func _build_env(overrides, clear):
    if overrides == null and not clear:
        return null
    base := {}
    if not clear:
        base = _os.env()
    if overrides != null:
        if type(overrides) != "dict":
            raise("TypeError", "process : env doit être un dict (obtenu '" + type(overrides) + "')")
        for k in keys(overrides):
            base[k] = overrides[k]
    out := []
    for k in keys(base):
        if base[k] != null:
            append(out, k + "=" + base[k])
    return out

func _opt_timeout(t):
    if t == null:
        return null
    return t

# ---------------------------------------------------------------------
# Résultat
# ---------------------------------------------------------------------

class Result:
    func init(code, stdout, stderr, timed_out):
        self.code = code
        self.stdout = stdout
        self.stderr = stderr
        self.timed_out = timed_out

    # Succès : sortie normale (code 0) sans dépassement de délai.
    func ok():
        return self.code == 0 and not self.timed_out

    # Retourne self, ou lève ProcessError / TimeoutError.
    func check():
        if self.timed_out:
            raise("TimeoutError", "le processus a dépassé le délai imparti")
        if self.code != 0:
            raise("ProcessError", "code de sortie " + f"{self.code}" + " : " + _s.trim(self.stderr))
        return self

# ---------------------------------------------------------------------
# Processus en cours
# ---------------------------------------------------------------------

class Process:
    func init(handle, grouped=false):
        self._h = handle
        self._pid = _p.pid(handle)
        self._grouped = grouped
        self._closed = false

    func _live():
        if self._closed:
            raise("ArgumentError", "process : Process déjà fermé (close())")
        return self._h

    func pid():
        return self._pid

    # Code de sortie si terminé, sinon null. Ne bloque jamais.
    func poll():
        return _p.poll(self._live())

    func running():
        return self.poll() == null

    # Attend la fin. Retourne le code de sortie, ou null si `timeout`
    # (secondes) expire d'abord.
    func wait(timeout=null):
        return _p.wait(self._live(), _opt_timeout(timeout))

    # Envoie un signal (nom "TERM"/"KILL"/"INT"... ou numéro). Sans effet si le
    # processus est déjà attendu. group=true : tout le groupe, si le fils a été
    # lancé avec Command.group() ; sinon le signal ne vise que le fils.
    func kill(signal="TERM", group=false):
        try:
            _p.kill(self._live(), signal, group and self._grouped)
        catch e:
            # Windows : TerminateProcess refuse (accès refusé) un processus qui sort ou vient de sortir ; même
            # effet qu'un signal envoyé trop tard sous POSIX : rien. Une seconde de grâce pour le constater.
            if self.wait(1.0) == null:
                raise(e)
        return null

    func terminate(group=false):
        return self.kill("TERM", group)

    # Arrêt en douceur : TERM, puis KILL si le processus n'est pas sorti
    # après `grace` secondes. Retourne le code de sortie.
    func stop(grace=3.0, group=false):
        code := self.poll()
        if code != null:
            return code
        self.kill("TERM", group)
        code = self.wait(grace)
        if code != null:
            return code
        self.kill("KILL", group)
        return self.wait()

    # --- entrée ---------------------------------------------------------

    # Écrit toute la chaîne sur stdin (bloquant). Retourne le nombre d'octets.
    # Lève IoError si le fils a fermé son entrée.
    func write(data):
        return _p.write(self._live(), data)

    func write_line(text):
        return _p.write(self._live(), text + "\n")

    # Ferme stdin : le fils voit la fin de fichier.
    func close_stdin():
        _p.close_stdin(self._live())
        return null

    # --- sortie ---------------------------------------------------------

    # Lit jusqu'à `max` octets (au moins un caractère). Retourne :
    #   une str non vide, "" à la fin du flux, null si `timeout` expire.
    func read(stream="stdout", max=65536, timeout=null):
        return _p.read(self._live(), _stream_no(stream), max, _opt_timeout(timeout))

    # Une ligne SANS son retour à la ligne ("" = ligne vide). Retourne null à la
    # fin du flux ; lève TimeoutError si `timeout` expire avant une ligne
    # complète (les données déjà reçues sont conservées pour la lecture suivante).
    func read_line(stream="stdout", timeout=null):
        raw := self.read_line_raw(stream, timeout)
        if raw == null:
            raise("TimeoutError", "process : aucune ligne complète avant le délai")
        if raw == "":
            return null
        if _s.ends_with(raw, "\r\n"):
            return _s.substring(raw, 0, len(raw) - 2)
        if _s.ends_with(raw, "\n"):
            return _s.substring(raw, 0, len(raw) - 1)
        return raw

    # Ligne brute, '\n' inclus. "" = fin du flux ; null = timeout.
    func read_line_raw(stream="stdout", timeout=null):
        return _p.read_line(self._live(), _stream_no(stream), _opt_timeout(timeout))

    # Lit le flux jusqu'à sa fin (bloque tant que le fils ne ferme pas sa sortie).
    func read_all(stream="stdout"):
        parts := []
        while true:
            chunk := _p.read(self._live(), _stream_no(stream), 65536, null)
            if chunk == "":
                break
            append(parts, chunk)
        return _s.join("", parts)

    # Envoie `input` (puis ferme stdin), lit stdout ET stderr jusqu'à la fin,
    # sans interblocage. Avec `timeout`, rend ce qui a été lu et timed_out=true.
    # Retourne un Result (code = null tant que le processus n'est pas terminé).
    func communicate(input=null, timeout=null):
        r := _p.communicate(self._live(), input, _opt_timeout(timeout))
        code := null
        if not r["timed_out"]:
            code = _p.wait(self._live(), null)
        return Result(code, r["stdout"], r["stderr"], r["timed_out"])

    # Libère le handle et ferme les pipes. Ne tue ni n'attend le fils : appeler
    # wait() ou stop() avant. Idempotent.
    func close():
        if not self._closed:
            _p.release(self._h)
            self._closed = true
        return null

func _stream_no(stream):
    if stream == "stdout" or stream == 1:
        return 1
    if stream == "stderr" or stream == 2:
        return 2
    raise("ArgumentError", "process : flux invalide (attendu \"stdout\" ou \"stderr\")")

# ---------------------------------------------------------------------
# Commande (construction fluide)
# ---------------------------------------------------------------------

class Command:
    func init(program, args=null):
        self._program = program
        self._args = list_copy(_str_list("Command", args, "args"))
        self._cwd = null
        self._env = null
        self._clear_env = false
        self._in = "inherit"
        self._out = "inherit"
        self._err = "inherit"
        self._group = false

    func arg(value):
        append(self._args, value)
        return self

    func args(values):
        for v in _str_list("Command.args", values, "values"):
            append(self._args, v)
        return self

    func cwd(path):
        self._cwd = path
        return self

    # Surcharge l'environnement hérité (valeur null : supprime la variable).
    func env(overrides):
        self._env = overrides
        return self

    # N'hérite RIEN de l'environnement du parent (seulement env(...)).
    func clear_env():
        self._clear_env = true
        return self

    func stdin(mode):
        self._in = mode
        return self

    func stdout(mode):
        self._out = mode
        return self

    # mode "stdout" : fusionne stderr dans stdout (2>&1).
    func stderr(mode):
        self._err = mode
        return self

    # Démarre le fils dans son propre groupe de processus : stop(group=true) /
    # kill(..., group=true) atteignent alors aussi ses descendants.
    func group():
        self._group = true
        return self

    # Lance et rend la main immédiatement.
    func spawn():
        _require()
        h := _p.spawn(self._program, self._args, self._cwd,
                      _build_env(self._env, self._clear_env),
                      _mode("spawn", self._in, "stdin", false),
                      _mode("spawn", self._out, "stdout", false),
                      _mode("spawn", self._err, "stderr", true),
                      self._group)
        return Process(h, self._group)

    # Lance, envoie `input`, capture stdout/stderr, attend la fin.
    # Si `timeout` expire : TERM, puis KILL après `grace` secondes ;
    # Result.timed_out vaut true et code le signal reçu (négatif).
    func run(input=null, timeout=null, grace=2.0, check=false):
        if self._out == "inherit":
            self._out = "pipe"
        if self._err == "inherit":
            self._err = "pipe"
        if input != null:
            self._in = "pipe"
        elif self._in == "inherit":
            self._in = "null"
        if timeout != null:
            self._group = true # TERM/KILL doivent atteindre aussi les descendants
        p := self.spawn()
        result := null
        try:
            result = _run_to_end(p, input, timeout, grace)
        catch e:
            p.stop(grace, true)
            p.close()
            raise(e.type, e.message)
        p.close()
        if check:
            result.check()
        return result

func list_copy(items):
    out := []
    for x in items:
        append(out, x)
    return out

func _run_to_end(p, input, timeout, grace):
    r := p.communicate(input, timeout)
    if not r.timed_out:
        return r
    # Délai dépassé : arrêt escaladé, puis récupération de la sortie restante.
    code := p.stop(grace, true)
    rest := p.communicate(null, grace)
    return Result(code, r.stdout + rest.stdout, r.stderr + rest.stderr, true)

# ---------------------------------------------------------------------
# Raccourcis
# ---------------------------------------------------------------------

# Lance `program` (sans shell), attend la fin, capture stdout et stderr.
# Retourne un Result. cwd / env : voir Command. check=true : lève ProcessError
# (code != 0) ou TimeoutError.
func run(program, args=null, input=null, timeout=null, cwd=null, env=null, check=false):
    return Command(program, args).cwd(cwd).env(env).run(input, timeout, 2.0, check)

# Lance sans attendre ; flux hérités, sauf modes demandés. Retourne un Process.
func spawn(program, args=null, cwd=null, env=null, stdin="inherit", stdout="inherit", stderr="inherit"):
    return Command(program, args).cwd(cwd).env(env).stdin(stdin).stdout(stdout).stderr(stderr).spawn()

# stdout du programme (str) ; lève ProcessError si le code n'est pas 0.
func check_output(program, args=null, input=null, timeout=null, cwd=null, env=null):
    return run(program, args, input, timeout, cwd, env, true).stdout

# Chemin complet de l'exécutable `program` d'après PATH, ou null. Windows : PATH séparé par « ; », extensions de
# PATHEXT essayées quand le nom n'en a pas (`which("cmd")` -> C:\Windows\System32\cmd.exe), « \ » accepté.
func which(program):
    win := _os.platform() == "windows"
    if _s.contains(program, "/") or (win and _s.contains(program, "\\")):
        for c in _which_variants(program, win):
            if _which_ok(c, win):
                return c
        return null
    path := _os.getenv("PATH", "")
    if path == "":
        return null
    for dir in _s.split(path, ";" if win else ":"):
        dir = _s.trim(dir)
        if dir == "":
            continue
        for c in _which_variants(_os.join(dir, program), win):
            if _which_ok(c, win):
                return c
    return null

func _which_ok(path, win):
    if not _os.isfile(path):
        return false
    return win or _os.access(path, "x")

func _which_variants(path, win):
    if not win or _os.extension(path) != "":
        return [path]
    out := [path]
    exts := _os.getenv("PATHEXT", ".COM;.EXE;.BAT;.CMD")
    for e in _s.split(exts, ";"):
        if e != "":
            out = out + [path + _s.lower(e)]
    return out

# Nombre de handles actuellement ouverts (diagnostic : détecter les fuites).
func open_handles():
    return _p.live_count()

func supported():
    return _p.supported()

# ALEX STANDARD LIBRARY — process.process_builder
#
# ProcessBuilder : construire le lancement d'un processus pas à pas (comme java.lang.ProcessBuilder),
# puis le démarrer (ProcessHandle) ou l'exécuter jusqu'au bout (Result). Réunit en un seul objet ce que
# process.Command, process.environment, process_priority et process_limits font séparément.
#
#   use process.process_builder as pb
#   print(pb.ProcessBuilder("make").args(["-j4"]).run().code)   # méthodes chaînables
#   b := pb.ProcessBuilder("python3")
#   b.arg("script.py")
#   b.directory("/srv/app")
#   b.env("MODE", "prod")
#   b.priority(10)                          # nice appliqué au fils après son lancement
#   b.limit("cpu", 30)                      # 30 s de processeur au plus (prlimit sur le fils)
#   b.timeout(60)
#   b.redirect_output("sortie.log")         # stdout écrit dans un fichier à la fin
#   b.merge_stderr()                        # stderr mêlé à stdout
#   r := b.run()                            # Result(code, stdout, stderr, timed_out)
#   h := pb.ProcessBuilder("serveur").start()   # ProcessHandle
#   print(b.describe())                     # résumé lisible de la configuration
#
# Erreurs : celles de process (IoError, ProcessError, TimeoutError), PermissionError / LimitError
#           (priorité, limites), ArgumentError.

from core use len, type
from collections use append
use string as _s
use io as _io
use process as _p
use process.command as _cmd
use process.environment as _env
use process.process_handle as _ph
use process.process_priority as _prio
use process.process_limits as _lim

class ProcessBuilder:
    func init(program, args=null):
        if type(program) != "str" or program == "":
            raise("TypeError", "ProcessBuilder : programme (str non vide) attendu")
        self.program = program
        self._args = []
        if args != null:
            for a in args:
                append(self._args, _p.str_of(a))
        self._cwd = null
        self._env = _env.inherit()
        self._clear = false
        self._stdin = "inherit"
        self._stdout = "pipe"
        self._stderr = "pipe"
        self._timeout = null
        self._check = false
        self._grace = 2.0
        self._group = false
        self._priority = null
        self._limits = []
        self._input = null
        self._out_file = null
        self._err_file = null
        self._append = false

    func arg(value):
        append(self._args, _p.str_of(value))
        return self

    func args(values):
        for v in values:
            append(self._args, _p.str_of(v))
        return self

    func directory(path):
        self._cwd = path
        return self

    func env(name, value):
        self._env.set(name, value)
        return self

    func env_all(vars):
        self._env.update(vars)
        return self

    func unset_env(name):
        self._env.unset(name)
        return self

    # Environnement vide (seules les variables ajoutées ensuite).
    func clear_env():
        self._env = _env.empty()
        return self

    func environment():
        return self._env

    func stdin(mode):
        self._stdin = mode
        return self

    func stdout(mode):
        self._stdout = mode
        return self

    func stderr(mode):
        self._stderr = mode
        return self

    func inherit_io():
        self._stdin = "inherit"
        self._stdout = "inherit"
        self._stderr = "inherit"
        return self

    func merge_stderr():
        self._stderr = "stdout"
        return self

    func discard_output():
        self._stdout = "null"
        self._stderr = "null"
        return self

    func input(text):
        self._input = text
        self._stdin = "pipe"
        return self

    # Fichier recevant stdout (et stderr si merge_stderr) à la fin de run().
    func redirect_output(path, append_mode=false):
        self._out_file = path
        self._append = append_mode
        self._stdout = "pipe"
        return self

    func redirect_error(path):
        self._err_file = path
        self._stderr = "pipe"
        return self

    func timeout(seconds, grace=2.0):
        self._timeout = seconds
        self._grace = grace
        return self

    func check(enabled=true):
        self._check = enabled
        return self

    # Fils dans son propre groupe : les signaux atteignent aussi ses descendants.
    func new_group():
        self._group = true
        return self

    func priority(nice):
        self._priority = nice
        return self

    func limit(resource, soft, hard=null):
        append(self._limits, [resource, soft, hard])
        return self

    # Limites posées AVANT l'exécution du programme (pas de course) : `sh -c 'ulimit ...; exec "$@"'`.
    # Les ressources sans option ulimit portable sont appliquées par prlimit juste après le lancement.
    func _wrapped():
        script := ""
        for l in self._limits:
            flag := _ulimit_flag(l[0])
            if flag == null:
                continue
            soft := "unlimited"
            if l[1] != null:
                soft = str(l[1])
            if l[2] != null:
                # abaisser d'abord la limite souple (une limite dure ne peut pas passer sous la souple)
                script += "ulimit -S -" + flag + " " + soft + " 2>/dev/null; "
                script += "ulimit -H -" + flag + " " + str(l[2]) + " || exit 126; "
            script += "ulimit -S -" + flag + " " + soft + " || exit 126; "
        if script == "":
            return null
        return script + "exec \"$@\""

    func command():
        prog := self.program
        argv := self._args
        w := self._wrapped()
        if w != null:
            prog = "sh"
            argv = ["-c", w, "sh", self.program] + self._args
        c := _cmd.Command(prog, argv)
        if self._cwd != null:
            c.cwd(self._cwd)
        self._env.apply(c)
        c.stdin(self._stdin)
        c.stdout(self._stdout)
        c.stderr(self._stderr)
        if self._group:
            c.group()
        return c

    func _post_spawn(pid):
        if self._priority != null:
            _prio.set(self._priority, pid)
        for l in self._limits:
            if _ulimit_flag(l[0]) != null:
                continue
            if l[2] == null:
                _lim.set(l[0], l[1], "\u0000<inchangée>", pid)
            else:
                _lim.set(l[0], l[1], l[2], pid)

    # Démarre ; ProcessHandle (fils). Priorité et limites appliquées juste après le lancement.
    func start():
        p := self.command().spawn()
        try:
            self._post_spawn(p.pid())
        catch e:
            p.stop(0.5)
            p.close()
            raise(e)
        return _ph.of_process(p)

    # Exécute jusqu'au bout ; Result. Écrit les fichiers de redirection demandés.
    func run():
        p := self.command().spawn()
        r := null
        try:
            self._post_spawn(p.pid())
            r = p.communicate(self._input, self._timeout)
            if r.timed_out:
                code := p.stop(self._grace, self._group)
                r = _p.Result(code, r.stdout, r.stderr, true)
        finally:
            p.close()
        if self._out_file != null:
            if self._append:
                _io.append_file(self._out_file, r.stdout)
            else:
                _io.write_file(self._out_file, r.stdout)
        if self._err_file != null:
            _io.write_file(self._err_file, r.stderr)
        if self._check:
            r.check()
        return r

    func output():
        return self.check(true).run().stdout

    # Ligne de commande demandée (sans l'éventuel enrobage `sh -c ulimit`).
    func to_list():
        return [self.program] + self._args

    func describe():
        lines := ["commande    " + _cmd.join(self.to_list())]
        if self._cwd != null:
            append(lines, "dossier     " + self._cwd)
        append(lines, "flux        stdin=" + self._stdin + " stdout=" + self._stdout + " stderr=" + self._stderr)
        if self._timeout != null:
            append(lines, "délai       " + str(self._timeout) + " s")
        if self._priority != null:
            append(lines, "priorité    nice " + str(self._priority))
        for l in self._limits:
            append(lines, "limite      " + str(l[0]) + " = " + str(l[1]))
        if self._out_file != null:
            append(lines, "sortie      -> " + self._out_file)
        return _s.join("\n", lines)

    func copy():
        b := ProcessBuilder(self.program, self._args)
        b._cwd = self._cwd
        b._env = self._env.copy()
        b._stdin = self._stdin
        b._stdout = self._stdout
        b._stderr = self._stderr
        b._timeout = self._timeout
        b._check = self._check
        b._group = self._group
        b._priority = self._priority
        b._limits = self._limits[:]
        b._input = self._input
        b._out_file = self._out_file
        b._err_file = self._err_file
        return b

_flags := {"cpu": "t", "fsize": "f", "data": "d", "stack": "s", "core": "c", "nofile": "n", "as": "v"}

func _ulimit_flag(resource):
    n := _lim.name_of(_lim.resource(resource))
    if n in _flags:
        return _flags[n]
    return null

func builder(program, args=null):
    return ProcessBuilder(program, args)

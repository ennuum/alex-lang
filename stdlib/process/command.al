# ALEX STANDARD LIBRARY — process.command
#
# Construire, afficher, analyser et enchaîner des lignes de commande, SANS shell.
#
#   use process.command as command
#   c := command.Command("git").args(["log", "-n", "3"]).cwd("/src").timeout(5)
#   print(c.to_string())                    # git log -n 3
#   print(c.output())                       # stdout (ProcessError si le code n'est pas 0)
#   parts := command.split("grep -r 'mot clé' src")   # ["grep", "-r", "mot clé", "src"]
#   r := command.parse("ls -l /tmp").run()
#   p := command.Command("printf").args(["b\na\n"]).pipe(command.Command("sort")).run()
#   print(p.stdout)                          # "a\nb\n"
#
# Command (héritée de process.Command : arg, args, cwd, env, clear_env, stdin, stdout, stderr, group, spawn,
# run) ajoute : timeout, input, check, env_var, output, status, succeeds, pipe, program, arguments,
# to_string, to_list, copy. split / quote / join suivent les règles du shell POSIX (guillemets simples et
# doubles, barre oblique inverse) mais n'interprètent RIEN d'autre : ni variables, ni jokers, ni `;`/`|`.
#
# Erreurs : ArgumentError (ligne de commande mal formée : guillemet non fermé), TypeError, et celles de
# process (IoError, ProcessError, TimeoutError).

from core use len, type
from collections use append, keys
use string as _s
use process as _proc
from process._base use BaseCommand
use io.pipe as _pipe

# ---------------------------------------------------------------------
# Analyse et mise entre guillemets
# ---------------------------------------------------------------------

func _is_space(c):
    return c == ' ' or c == '\t' or c == '\n' or c == '\r'

# Découpe une ligne de commande en arguments (règles du shell POSIX pour les guillemets et « \ »).
func split(line):
    if type(line) != "str":
        raise("TypeError", "command.split : str attendue (obtenu '" + type(line) + "')")
    out := []
    cur := []
    has := false
    i := 0
    n := len(line)
    while i < n:
        c := line[i]
        if _is_space(c):
            if has:
                append(out, _s.join("", cur))
                cur = []
                has = false
            i += 1
            continue
        has = true
        if c == '\\':
            if i + 1 < n:
                append(cur, str(line[i + 1]))
                i += 2
                continue
            raise("ArgumentError", "command.split : « \\ » final sans caractère à protéger")
        if c == '\'':
            j := i + 1
            while j < n and line[j] != '\'':
                append(cur, str(line[j]))
                j += 1
            if j >= n:
                raise("ArgumentError", "command.split : guillemet simple non fermé (position " + str(i) + ")")
            i = j + 1
            continue
        if c == '"':
            j := i + 1
            while j < n and line[j] != '"':
                if line[j] == '\\' and j + 1 < n and (line[j + 1] == '"' or line[j + 1] == '\\' or line[j + 1] == '$' or line[j + 1] == '`'):
                    append(cur, str(line[j + 1]))
                    j += 2
                    continue
                append(cur, str(line[j]))
                j += 1
            if j >= n:
                raise("ArgumentError", "command.split : guillemet double non fermé (position " + str(i) + ")")
            i = j + 1
            continue
        append(cur, str(c))
        i += 1
    if has:
        append(out, _s.join("", cur))
    return out

func _safe_char(c):
    if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9'):
        return true
    return c == '-' or c == '_' or c == '.' or c == '/' or c == ':' or c == '=' or c == '+' or c == ',' or c == '@' or c == '%'

# Argument protégé pour un shell POSIX (inchangé s'il ne contient que des caractères sûrs).
func quote(arg):
    if type(arg) != "str":
        arg = str(arg)
    if arg == "":
        return "''"
    safe := true
    for c in arg:
        if not _safe_char(c):
            safe = false
            break
    if safe:
        return arg
    return "'" + _s.replace(arg, "'", "'\"'\"'") + "'"

# Ligne de commande affichable (et relisible par split) d'une liste d'arguments.
func join(args):
    return _s.join(" ", [quote(a) for a in args])

# ---------------------------------------------------------------------
# Commande
# ---------------------------------------------------------------------

class Command extends BaseCommand:
    func init(program, args=null):
        super.init(program, args)
        self._timeout = null
        self._input = null
        self._check = false

    # Délai total (secondes) de run() / output() / status().
    func timeout(seconds):
        self._timeout = seconds
        return self

    # Texte envoyé sur l'entrée standard par run().
    func input(text):
        self._input = text
        return self

    # run() lève ProcessError si le code de sortie n'est pas 0 (TimeoutError si le délai expire).
    func check(enabled=true):
        self._check = enabled
        return self

    # Une variable d'environnement (null : la supprimer pour le fils).
    func env_var(name, value):
        if self._env == null:
            self._env = {}
        self._env[name] = value
        return self

    func program():
        return self._program

    func arguments():
        return [a for a in self._args]

    # [programme, arguments...]
    func to_list():
        out := [self._program]
        for a in self._args:
            append(out, a)
        return out

    func to_string():
        return join(self.to_list())

    # Copie indépendante (mêmes réglages).
    func copy():
        c := Command(self._program, self._args)
        c._cwd = self._cwd
        if self._env != null:
            c._env = {}
            for k in keys(self._env):
                c._env[k] = self._env[k]
        c._clear_env = self._clear_env
        c._in = self._in
        c._out = self._out
        c._err = self._err
        c._group = self._group
        c._timeout = self._timeout
        c._input = self._input
        c._check = self._check
        return c

    # Exécute avec les réglages (input, timeout, check) ; renvoie un process.Result.
    func run(input=null, timeout=null, grace=2.0, check=null):
        if input == null:
            input = self._input
        if timeout == null:
            timeout = self._timeout
        if check == null:
            check = self._check
        return super.run(input, timeout, grace, check)

    # Sortie standard ; ProcessError si le code de sortie n'est pas 0.
    func output():
        return self.run(null, null, 2.0, true).stdout

    # Code de sortie (négatif : tué par un signal).
    func status():
        return self.run(null, null, 2.0, false).code

    func succeeds():
        return self.run(null, null, 2.0, false).ok()

    # Pipeline self | other (sans shell).
    func pipe(other):
        return Pipeline([self, other])

# Commande depuis une ligne de texte (découpée par split, jamais interprétée par un shell).
func parse(line):
    parts := split(line)
    if len(parts) == 0:
        raise("ArgumentError", "command.parse : ligne de commande vide")
    rest := []
    i := 1
    while i < len(parts):
        append(rest, parts[i])
        i += 1
    return Command(parts[0], rest)

# Commande depuis [programme, arguments...].
func from_list(argv):
    if type(argv) != "list" or len(argv) == 0:
        raise("ArgumentError", "command.from_list : liste [programme, arguments...] non vide attendue")
    rest := []
    i := 1
    while i < len(argv):
        append(rest, argv[i])
        i += 1
    return Command(argv[0], rest)

# ---------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------

class Pipeline:
    func init(commands):
        self.commands = []
        for c in commands:
            append(self.commands, c)
        self._timeout = null

    func pipe(other):
        append(self.commands, other)
        return self

    func timeout(seconds):
        self._timeout = seconds
        return self

    func to_string():
        return _s.join(" | ", [c.to_string() for c in self.commands])

    # Exécute la chaîne (io.pipe.pipeline) ; renvoie un PipelineResult (stdout, codes, timed_out, ok()).
    func run(input=null, check=false):
        lists := [c.to_list() for c in self.commands]
        if input == null and len(self.commands) > 0:
            input = self.commands[0]._input
        return _pipe.pipeline(lists, input, self._timeout, check)

    func output():
        return self.run(null, true).stdout

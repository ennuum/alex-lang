# ALEX STANDARD LIBRARY — process.environment
#
# Environnement des processus : celui du programme (lecture, modification, expansion « $VAR », voir
# system.environment) et des environnements construits pour un processus fils, sans toucher au programme.
#
#   use process.environment as env
#   e := env.inherit().set("LANG", "C").prepend_path("/opt/outils/bin").unset("DEBUG")
#   r := e.run("make", ["-j4"])                 # le fils voit l'environnement e
#   cmd := e.apply(process.Command("env"))      # ou : appliqué à une commande (clear_env + env)
#   print(env.get("HOME"), env.expand("${HOME}/données"))
#
# Environment est une valeur : set / unset / update / prepend_path... renvoient self pour l'enchaînement et ne
# modifient que l'objet (jamais l'environnement du programme).
#
# Erreurs : ArgumentError (nom de variable invalide), TypeError.

from core use len, type
from collections use append, keys, contains_key, remove
use string as _s
use os as _os
use system.environment as _sysenv
use process as _proc

# ---- environnement du programme (system.environment) ----
func get(name, fallback=null):
    return _sysenv.get(name, fallback)

func set(name, value):
    return _sysenv.set(name, value)

func unset(name):
    return _sysenv.unset(name)

func has(name):
    return _sysenv.has(name)

func all():
    return _sysenv.all()

func get_int(name, fallback=null):
    return _sysenv.get_int(name, fallback)

func get_bool(name, fallback=null):
    return _sysenv.get_bool(name, fallback)

func expand(text, vars=null):
    return _sysenv.expand(text, vars)

func with_vars(vars, fn):
    return _sysenv.with_vars(vars, fn)

func path_separator():
    return _sysenv.path_list_separator()

func _check_name(fn, name):
    if type(name) != "str":
        raise("TypeError", "process.environment." + fn + " : nom de variable (str) attendu")
    if name == "" or _s.contains(name, "=") or _s.contains(name, "\u0000"):
        raise("ArgumentError", "process.environment." + fn + " : nom de variable invalide '" + name + "'")

func _text(v):
    if v == true:
        return "1"
    if v == false:
        return "0"
    if type(v) == "str":
        return v
    return str(v)

# ---- environnement construit pour un processus fils ----
class Environment:
    func init(vars=null):
        self._vars = {}
        if vars != null:
            if type(vars) != "dict":
                raise("TypeError", "process.environment.Environment : dict attendu")
            for k in keys(vars):
                self.set(k, vars[k])

    func get(name, fallback=null):
        if contains_key(self._vars, name):
            return self._vars[name]
        return fallback

    func has(name):
        return contains_key(self._vars, name)

    func set(name, value):
        _check_name("set", name)
        if value == null:
            return self.unset(name)
        self._vars[name] = _text(value)
        return self

    func unset(name):
        if contains_key(self._vars, name):
            remove(self._vars, name)
        return self

    # Ajoute ou remplace plusieurs variables (valeur null : supprime).
    func update(vars):
        for k in keys(vars):
            self.set(k, vars[k])
        return self

    # Ne garde que les variables nommées (les autres disparaissent).
    func keep(names):
        out := {}
        for n in names:
            if contains_key(self._vars, n):
                out[n] = self._vars[n]
        self._vars = out
        return self

    func names():
        return [k for k in keys(self._vars)]

    func size():
        return len(keys(self._vars))

    # Liste de chemins (PATH) : ajout en tête / en fin, sans doublon.
    func prepend_path(dir, var="PATH"):
        return self._path_edit(dir, var, true)

    func append_path(dir, var="PATH"):
        return self._path_edit(dir, var, false)

    func _path_edit(dir, var, front):
        sep := _sysenv.path_list_separator()
        parts := []
        if contains_key(self._vars, var) and self._vars[var] != "":
            parts = _s.split(self._vars[var], sep)
        kept := []
        for p in parts:
            if p != dir:
                append(kept, p)
        if front:
            out := [dir]
            for p in kept:
                append(out, p)
            kept = out
        else:
            append(kept, dir)
        self._vars[var] = _s.join(sep, kept)
        return self

    # Développe « $NOM », « ${NOM:-défaut} » avec CET environnement.
    func expand(text):
        return _sysenv.expand(text, self._vars)

    func to_dict():
        out := {}
        for k in keys(self._vars):
            out[k] = self._vars[k]
        return out

    # ["NOM=valeur", ...] triés par nom (format execve).
    func to_list():
        names := self.names()
        out := []
        for k in _sorted(names):
            append(out, k + "=" + self._vars[k])
        return out

    func copy():
        return Environment(self._vars)

    # Différence avec un autre environnement : {"added": {...}, "removed": [...], "changed": {nom: [avant, après]}}
    func diff(other):
        added := {}
        removed := []
        changed := {}
        for k in keys(other._vars):
            if not contains_key(self._vars, k):
                added[k] = other._vars[k]
            elif self._vars[k] != other._vars[k]:
                changed[k] = [self._vars[k], other._vars[k]]
        for k in keys(self._vars):
            if not contains_key(other._vars, k):
                append(removed, k)
        return {"added": added, "removed": removed, "changed": changed}

    # Applique l'environnement à une process.Command (ou process.command.Command) : le fils n'hérite que de lui.
    func apply(command):
        return command.clear_env().env(self.to_dict())

    func run(program, args=null, input=null, timeout=null, cwd=null, check=false):
        return self.apply(_proc.Command(program, args).cwd(cwd)).run(input, timeout, 2.0, check)

    func spawn(program, args=null, cwd=null, stdin="inherit", stdout="inherit", stderr="inherit"):
        return self.apply(_proc.Command(program, args).cwd(cwd)).stdin(stdin).stdout(stdout).stderr(stderr).spawn()

func _sorted(items):
    out := [x for x in items]
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

# Copie de l'environnement du programme.
func inherit():
    return Environment(_os.env())

# Environnement vide (le fils ne reçoit rien).
func empty():
    return Environment()

# Environnement minimal et reproductible : PATH, HOME, LANG=C, plus vars.
func minimal(vars=null):
    e := Environment()
    e.set("PATH", _os.getenv("PATH", "/usr/local/bin:/usr/bin:/bin"))
    home := _os.getenv("HOME")
    if home != null:
        e.set("HOME", home)
    e.set("LANG", "C")
    e.set("LC_ALL", "C")
    if vars != null:
        e.update(vars)
    return e

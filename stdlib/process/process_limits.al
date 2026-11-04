# ALEX STANDARD LIBRARY — process.process_limits
#
# Limites de ressources d'un processus (rlimit) : temps processeur, mémoire, fichiers ouverts, taille des
# fichiers, processus... Chaque limite a une valeur SOUPLE (appliquée) et une valeur DURE (plafond de la
# souple ; seul root peut la relever). null = illimité.
#
#   use process.process_limits as lim
#   l := lim.get(lim.NOFILE)
#   print(l.soft, l.hard)                      # 1024 524288
#   lim.set(lim.NOFILE, 4096)                  # souple seulement (≤ dure)
#   lim.set(lim.CORE, 0, 0)                    # pas de fichier core
#   print(lim.all(enfant.pid()))               # {nom: Limit} d'un autre processus (/proc/<pid>/limits)
#   lim.with_limit(lim.CPU, 2, calcul)         # au plus 2 s de processeur pendant calcul()
#
# Lecture : /proc/<pid>/limits (Linux), sinon getrlimit ; écriture : prlimit / setrlimit (libc, via ffi).
# Erreurs : LimitError (souple > dure, ressource inconnue), PermissionError (hausse de la dure),
#           ProcessNotFoundError, IoError (plateforme).

from core use len, type, to_int
from collections use append
use string as _s
use io as _io
use os as _os
use process.process_errors as _e
use process._libc as _c

# Numéros Linux des ressources.
const CPU := 0          # secondes de processeur
const FSIZE := 1        # taille maximale d'un fichier écrit (octets)
const DATA := 2         # segment de données (octets)
const STACK := 3        # pile (octets)
const CORE := 4         # fichier core (octets)
const RSS := 5          # mémoire résidente (sans effet sur Linux récent)
const NPROC := 6        # processus de l'utilisateur
const NOFILE := 7       # descripteurs ouverts
const MEMLOCK := 8      # mémoire verrouillée (octets)
const AS := 9           # espace d'adressage (octets)
const LOCKS := 10
const SIGPENDING := 11
const MSGQUEUE := 12
const NICE := 13
const RTPRIO := 14
const RTTIME := 15

_names := ["cpu", "fsize", "data", "stack", "core", "rss", "nproc", "nofile", "memlock", "as", "locks",
           "sigpending", "msgqueue", "nice", "rtprio", "rttime"]

# Libellés de /proc/<pid>/limits.
_proc_labels := {"Max cpu time": 0, "Max file size": 1, "Max data size": 2, "Max stack size": 3,
                 "Max core file size": 4, "Max resident set": 5, "Max processes": 6, "Max open files": 7,
                 "Max locked memory": 8, "Max address space": 9, "Max file locks": 10, "Max pending signals": 11,
                 "Max msgqueue size": 12, "Max nice priority": 13, "Max realtime priority": 14,
                 "Max realtime timeout": 15}

class Limit:
    func init(resource, soft, hard):
        self.resource = resource
        self.name = name_of(resource)
        self.soft = soft
        self.hard = hard

    func is_unlimited():
        return self.soft == null

    func allows(value):
        return self.soft == null or value <= self.soft

    func __eq__(other):
        return isinstance(other, Limit) and other.resource == self.resource and other.soft == self.soft and other.hard == self.hard

    func __str__():
        return self.name + " : souple " + _show(self.soft) + ", dure " + _show(self.hard)

func _show(v):
    if v == null:
        return "illimitée"
    return str(v)

func name_of(resource):
    if type(resource) != "int" or resource < 0 or resource >= len(_names):
        raise(_e.LIMIT, "process_limits : ressource inconnue " + str(resource))
    return _names[resource]

# Ressource d'après son nom ("nofile", "NOFILE", "RLIMIT_NOFILE").
func resource(name):
    if type(name) == "int":
        name_of(name)
        return name
    n := _s.lower(name)
    if _s.starts_with(n, "rlimit_"):
        n = _s.substring(n, 7, len(n))
    i := 0
    while i < len(_names):
        if _names[i] == n:
            return i
        i += 1
    raise(_e.LIMIT, "process_limits : ressource inconnue '" + name + "'")

func resources():
    return _names[:]

func _parse_proc(text):
    out := {}
    for line in _s.split(text, "\n"):
        for label in _proc_labels:
            if _s.starts_with(line, label):
                rest := [x for x in _s.split(_s.substring(line, len(label), len(line)), " ") if x != ""]
                if len(rest) >= 2:
                    out[_proc_labels[label]] = [_val(rest[0]), _val(rest[1])]
    return out

func _val(t):
    if t == "unlimited":
        return null
    return to_int(t)

func _native_get(r):
    buf := _c.buffer(16)
    rc := _c.call("getrlimit", ["i32", "ptr"], "i32", [r, buf.address()], "process_limits.get")
    if rc != 0:
        buf.free()
        raise(_e.LIMIT, "process_limits.get : getrlimit a échoué")
    soft := buf.read("i64", 0)
    hard := buf.read("i64", 8)
    buf.free()
    if soft < 0:
        soft = null
    if hard < 0:
        hard = null
    return Limit(r, soft, hard)

# Limite d'une ressource pour pid (0 : ce programme).
func get(res, pid=0):
    r := resource(res)
    p := pid
    if p == 0:
        p = _os.pid()
    text := null
    try:
        text = _io.read_file("/proc/" + str(p) + "/limits")
    catch e:
        text = null
    if text != null:
        d := _parse_proc(text)
        if r in d:
            return Limit(r, d[r][0], d[r][1])
    if p != _os.pid():
        if not _os.process_exists(p):
            _e.not_found("process_limits.get", p)
        raise("IoError", "process_limits.get : limites d'un autre processus illisibles sur cette plateforme")
    return _native_get(r)

# Toutes les limites : {nom: Limit}.
func all(pid=0):
    out := {}
    for n in _names:
        try:
            out[n] = get(n, pid)
        catch e:
            if e.type == _e.NOT_FOUND:
                raise(e)
    return out

func _enc(v):
    if v == null:
        return -1
    return v

# Fixe la limite souple (null = illimitée) et, si elle est donnée, la dure ("unlimited" = illimitée ;
# omise : inchangée) de pid (0 : ce programme) ; renvoie l'ancienne Limit.
func set(res, soft, hard="\u0000<inchangée>", pid=0):
    r := resource(res)
    old := get(r, pid)
    h := hard
    if type(h) == "str" and h == "\u0000<inchangée>":
        h = old.hard
    elif type(h) == "str" and h == "unlimited":
        h = null
    if type(soft) == "str" and soft == "unlimited":
        soft = null
    if soft != null and h != null and soft > h:
        raise(_e.LIMIT, "process_limits.set : souple " + str(soft) + " > dure " + str(h))
    if (soft != null and soft < 0) or (h != null and h < 0):
        raise(_e.LIMIT, "process_limits.set : valeur négative")
    buf := _c.buffer(16)
    buf.write("i64", _enc(soft), 0)
    buf.write("i64", _enc(h), 8)
    p := pid
    if p == _os.pid():
        p = 0
    rc := _c.call("prlimit", ["i32", "i32", "ptr", "ptr"], "i32", [p, r, buf.address(), null], "process_limits.set")
    buf.free()
    if rc != 0:
        if p != 0 and not _os.process_exists(p):
            _e.not_found("process_limits.set", p)
        _e.permission("process_limits.set", "limite " + name_of(r))
    return old

# body() sous la limite souple soft, puis restauration.
func with_limit(res, soft, body):
    old := set(res, soft)
    try:
        return body()
    finally:
        set(res, old.soft, old.hard)

func supported():
    return _c.available() or _os.isdir("/proc/self")

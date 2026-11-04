# ALEX STANDARD LIBRARY — process.process_priority
#
# Priorité d'ordonnancement (« nice ») des processus : de -20 (la plus haute) à 19 (la plus basse), 0 par
# défaut. Baisser sa priorité est toujours permis ; l'augmenter (valeur plus petite) demande des droits
# (root / CAP_SYS_NICE) : PermissionError sinon.
#
#   use process.process_priority as prio
#   print(prio.get())                      # nice du programme
#   prio.set(10)                           # se rendre moins prioritaire (tâche de fond)
#   prio.set(prio.IDLE, enfant.pid())      # un autre processus
#   print(prio.name_of(prio.get()))        # "low"
#   prio.with_priority(prio.LOW, calcul)   # le temps d'un calcul, puis retour (si les droits le permettent)
#
# Niveaux nommés : REALTIME -20, HIGHEST -15, HIGH -5, NORMAL 0, LOW 10, IDLE 19.
# Lecture : /proc/<pid>/stat (Linux), sinon getpriority ; écriture : setpriority (libc, via ffi).
# Erreurs : PermissionError, ProcessNotFoundError, ArgumentError (hors -20..19), IoError (plateforme).

from core use len, type, to_int
use string as _s
use io as _io
use os as _os
use process.process_errors as _e
use process._libc as _c

const REALTIME := -20
const HIGHEST := -15
const HIGH := -5
const NORMAL := 0
const LOW := 10
const IDLE := 19
const MIN := -20
const MAX := 19

const _PRIO_PROCESS := 0
const _PRIO_PGRP := 1
const _PRIO_USER := 2

func _need_nice(fn, n):
    if type(n) != "int":
        raise("TypeError", fn + " : priorité entière attendue")
    if n < MIN or n > MAX:
        raise("ArgumentError", fn + " : priorité " + str(n) + " hors de " + str(MIN) + ".." + str(MAX))

func _from_proc(pid):
    text := null
    try:
        text = _io.read_file("/proc/" + str(pid) + "/stat")
    catch e:
        return null
    k := len(text) - 1
    while k >= 0 and text[k] != ')':
        k -= 1
    rest := [x for x in _s.split(_s.trim(_s.substring(text, k + 1, len(text))), " ") if x != ""]
    if len(rest) < 17:
        return null
    return to_int(rest[16])

# Valeur nice de pid (0 : le programme lui-même).
func get(pid=0):
    p := pid
    if p == 0:
        p = _os.pid()
    _e.need_pid("process_priority.get", p)
    v := _from_proc(p)
    if v != null:
        return v
    if not _os.process_exists(p):
        _e.not_found("process_priority.get", p)
    return _c.call("getpriority", ["i32", "i32"], "i32", [_PRIO_PROCESS, p], "process_priority.get")

# Change la valeur nice de pid (0 : le programme lui-même) ; renvoie l'ancienne.
func set(nice, pid=0):
    _need_nice("process_priority.set", nice)
    p := pid
    if p == 0:
        p = _os.pid()
    old := get(p)
    r := _c.call("setpriority", ["i32", "i32", "i32"], "i32", [_PRIO_PROCESS, p, nice], "process_priority.set")
    if r != 0:
        if not _os.process_exists(p):
            _e.not_found("process_priority.set", p)
        _e.permission("process_priority.set", "priorité " + str(nice) + " pour le pid " + str(p))
    return old

# Décale la priorité de delta (positif : moins prioritaire), bornée à -20..19.
func adjust(delta, pid=0):
    v := get(pid) + delta
    if v < MIN:
        v = MIN
    if v > MAX:
        v = MAX
    return set(v, pid)

# Priorité de tout un groupe de processus.
func set_group(nice, pgid):
    _need_nice("process_priority.set_group", nice)
    r := _c.call("setpriority", ["i32", "i32", "i32"], "i32", [_PRIO_PGRP, pgid, nice], "process_priority.set_group")
    if r != 0:
        _e.permission("process_priority.set_group", "priorité du groupe " + str(pgid))

func name_of(nice):
    if nice <= -20:
        return "realtime"
    if nice <= -10:
        return "highest"
    if nice < 0:
        return "high"
    if nice == 0:
        return "normal"
    if nice < 19:
        return "low"
    return "idle"

func from_name(name):
    m := {"realtime": REALTIME, "highest": HIGHEST, "high": HIGH, "normal": NORMAL, "low": LOW, "idle": IDLE}
    if not (name in m):
        raise("ArgumentError", "process_priority.from_name : niveau inconnu '" + str(name) + "'")
    return m[name]

# body() avec la priorité nice, puis restauration (si le système autorise le retour : remonter la
# priorité demande des droits — l'échec du retour est ignoré et signalé dans le résultat).
func with_priority(nice, body):
    old := set(nice)
    try:
        return body()
    finally:
        try:
            set(old)
        catch e:
            pass

func supported():
    return _c.available()

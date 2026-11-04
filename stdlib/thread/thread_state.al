# ALEX STANDARD LIBRARY — thread.thread_state
#
# États d'un fil : NEW (créé, pas démarré), RUNNING, FINISHED (fonction rendue), FAILED (erreur), et, pour
# les fils système observés dans /proc, SLEEPING / BLOCKED / STOPPED / ZOMBIE.
#
#   use thread
#   use thread.thread_state as ts
#   t := thread.Thread(travail)
#   print(ts.of(t))                               # new
#   t.start()
#   print(ts.of(t))                               # running
#   t.join()
#   print(ts.of(t), ts.is_terminal(ts.of(t)))     # finished true
#   for th in ts.os_states():                     # {tid: état} des fils système du processus
#       ...
#
# Erreurs : ArgumentError (état inconnu).

from core use type
use _native_thread as _nt
use thread.thread_info as _ti

const NEW := "new"
const RUNNING := "running"
const SLEEPING := "sleeping"
const BLOCKED := "blocked"
const STOPPED := "stopped"
const ZOMBIE := "zombie"
const FINISHED := "finished"
const FAILED := "failed"
const UNKNOWN := "unknown"

const ALL := ["new", "running", "sleeping", "blocked", "stopped", "zombie", "finished", "failed", "unknown"]

_codes := {"R": "running", "S": "sleeping", "D": "blocked", "T": "stopped", "t": "stopped", "Z": "zombie",
           "X": "finished", "I": "sleeping"}

func is_valid(state):
    for s in ALL:
        if s == state:
            return true
    return false

func is_terminal(state):
    return state == FINISHED or state == FAILED or state == ZOMBIE

func is_alive(state):
    return state == RUNNING or state == SLEEPING or state == BLOCKED or state == STOPPED

func describe(state):
    d := {"new": "créé, pas encore démarré", "running": "en cours", "sleeping": "en attente (sommeil, verrou, message)",
          "blocked": "attente non interruptible (entrée-sortie)", "stopped": "suspendu", "zombie": "terminé, non récupéré",
          "finished": "terminé normalement", "failed": "terminé par une erreur", "unknown": "état inconnu"}
    if not (state in d):
        raise("ArgumentError", "thread_state.describe : état inconnu '" + str(state) + "'")
    return d[state]

# État d'un concurrency.thread.Thread (ou de son identifiant ALEX).
func of(t):
    if type(t) == "int":
        if _nt.is_alive(t):
            return RUNNING
        return FINISHED
    if t.id == null:
        return NEW
    if t._result != null:
        if t._result[0]:
            return FINISHED
        return FAILED
    if t.is_alive():
        return RUNNING
    return FINISHED

# État d'un fil système d'après son code /proc.
func from_code(code):
    if code in _codes:
        return _codes[code]
    return UNKNOWN

# {tid: état} de tous les fils système du processus (vide hors Linux).
func os_states():
    out := {}
    for th in _ti.os_threads():
        out[th["tid"]] = from_code(th["state"])
    return out

func count_by_state():
    out := {}
    for k in _values(os_states()):
        if k in out:
            out[k] += 1
        else:
            out[k] = 1
    return out

func _values(d):
    return [d[k] for k in d]

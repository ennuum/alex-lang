# ALEX STANDARD LIBRARY — process.process_state
#
# États d'un processus et transitions permises, pour suivre le cycle de vie d'un fils ou décrire un
# processus quelconque (codes de /proc/<pid>/stat).
#
#   use process.process_state as ps
#   print(ps.from_code("S"))                  # "sleeping"
#   print(ps.describe(ps.ZOMBIE))             # « zombie : terminé, pas encore attendu par son parent »
#   m := ps.StateMachine()                    # created -> running -> exited
#   m.to(ps.RUNNING)
#   m.to(ps.EXITED)
#   m.to(ps.RUNNING)                          # InvalidStateError : un processus terminé ne repart pas
#   print(ps.of_pid(1))                       # état d'un pid, ou "unknown"
#
# Erreurs : InvalidStateError (transition interdite), ArgumentError (état inconnu).

from core use len, type
from collections use append
use io as _io
use string as _s
use os as _os

const CREATED := "created"      # construit, pas encore lancé
const RUNNING := "running"      # en cours d'exécution (ou prêt)
const SLEEPING := "sleeping"    # en attente interruptible
const WAITING := "waiting"      # attente non interruptible (disque, périphérique)
const STOPPED := "stopped"      # suspendu (SIGSTOP / SIGTSTP) ou tracé
const ZOMBIE := "zombie"        # terminé, pas encore attendu
const EXITED := "exited"        # terminé normalement (code connu)
const KILLED := "killed"        # terminé par un signal
const UNKNOWN := "unknown"

const ALL := ["created", "running", "sleeping", "waiting", "stopped", "zombie", "exited", "killed", "unknown"]

_codes := {"R": "running", "S": "sleeping", "D": "waiting", "Z": "zombie", "T": "stopped", "t": "stopped",
           "X": "exited", "I": "sleeping", "W": "waiting", "P": "stopped", "K": "waiting"}

_desc := {"created": "créé : pas encore lancé", "running": "en cours d'exécution", "sleeping": "en sommeil (attend un événement)",
          "waiting": "attente non interruptible (entrée-sortie)", "stopped": "suspendu (SIGSTOP) ou tracé",
          "zombie": "zombie : terminé, pas encore attendu par son parent", "exited": "terminé",
          "killed": "terminé par un signal", "unknown": "état inconnu"}

_next := {"created": ["running", "exited", "killed"],
          "running": ["sleeping", "waiting", "stopped", "zombie", "exited", "killed", "running"],
          "sleeping": ["running", "waiting", "stopped", "zombie", "exited", "killed", "sleeping"],
          "waiting": ["running", "sleeping", "stopped", "zombie", "exited", "killed", "waiting"],
          "stopped": ["running", "sleeping", "zombie", "exited", "killed", "stopped"],
          "zombie": ["exited", "killed"],
          "exited": [], "killed": [], "unknown": ALL}

func is_valid(state):
    for s in ALL:
        if s == state:
            return true
    return false

func _need(fn, state):
    if not is_valid(state):
        raise("ArgumentError", fn + " : état inconnu '" + str(state) + "'")

# Code d'état du noyau (« R », « S »...) -> état.
func from_code(code):
    if code in _codes:
        return _codes[code]
    return UNKNOWN

func describe(state):
    _need("process_state.describe", state)
    return _desc[state]

func is_alive(state):
    return state == RUNNING or state == SLEEPING or state == WAITING or state == STOPPED

func is_finished(state):
    return state == EXITED or state == KILLED or state == ZOMBIE

func can_transition(a, b):
    _need("can_transition", a)
    _need("can_transition", b)
    for x in _next[a]:
        if x == b:
            return true
    return false

# État d'un pid d'après /proc (Linux) ; UNKNOWN si indisponible, EXITED s'il n'existe plus.
func of_pid(pid):
    if _os.isdir("/proc/self"):
        try:
            text := _io.read_file("/proc/" + str(pid) + "/stat")
            k := len(text) - 1
            while k >= 0 and text[k] != ')':
                k -= 1
            rest := _s.trim(_s.substring(text, k + 1, len(text)))
            return from_code(_s.substring(rest, 0, 1))
        catch e:
            return EXITED
    if _os.process_exists(pid):
        return RUNNING
    return EXITED

# État d'après un code de sortie (convention du module process : négatif = signal).
func from_exit_code(code):
    if code == null:
        return RUNNING
    if code < 0:
        return KILLED
    return EXITED

class StateMachine:
    func init(initial=CREATED):
        _need("StateMachine", initial)
        self.state = initial
        self.history = [initial]

    func to(state):
        if not can_transition(self.state, state):
            raise("InvalidStateError", "processus : transition " + self.state + " -> " + state + " impossible")
        self.state = state
        append(self.history, state)
        return state

    func is_alive():
        return is_alive(self.state)

    func is_finished():
        return is_finished(self.state)

    func __str__():
        return "StateMachine(" + self.state + ")"

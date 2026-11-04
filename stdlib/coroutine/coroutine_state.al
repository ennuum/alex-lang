# ALEX STANDARD LIBRARY — coroutine.coroutine_state
#
# États d'une coroutine et transitions permises :
#
#   created --resume--> running --yield--> suspended --resume--> running ... --return--> done
#                          |                    |                                  \--erreur--> failed
#                          \------------------- close / cancel --------------------> closed / cancelled
#
#   use coroutine.coroutine_state as cs
#   print(cs.can_resume(cs.SUSPENDED), cs.is_finished(cs.DONE))   # true true
#   m := cs.StateTracker()
#   m.to(cs.RUNNING)
#
# Erreurs : CoroutineError (transition interdite), ArgumentError (état inconnu).

from collections use append
use coroutine.coroutine_errors as _e

const CREATED := "created"
const RUNNING := "running"
const SUSPENDED := "suspended"
const DONE := "done"
const FAILED := "failed"
const CLOSED := "closed"
const CANCELLED := "cancelled"

const ALL := ["created", "running", "suspended", "done", "failed", "closed", "cancelled"]

_next := {"created": ["running", "closed", "cancelled"],
          "running": ["suspended", "done", "failed", "closed", "cancelled"],
          "suspended": ["running", "closed", "cancelled"],
          "done": [], "failed": [], "closed": [], "cancelled": []}

func is_valid(state):
    return state in _next

func _need(state):
    if not is_valid(state):
        raise("ArgumentError", "coroutine_state : état inconnu '" + str(state) + "'")

func can_resume(state):
    _need(state)
    return state == CREATED or state == SUSPENDED

func is_finished(state):
    _need(state)
    return state == DONE or state == FAILED or state == CLOSED or state == CANCELLED

func is_active(state):
    return state == RUNNING or state == SUSPENDED

func can_transition(a, b):
    _need(a)
    _need(b)
    for x in _next[a]:
        if x == b:
            return true
    return false

class StateTracker:
    func init(initial=CREATED):
        _need(initial)
        self.state = initial
        self.history = [initial]

    func to(state):
        if not can_transition(self.state, state):
            _e.coroutine_error("coroutine", "transition " + self.state + " -> " + state + " impossible")
        self.state = state
        append(self.history, state)
        return state

# ALEX STANDARD LIBRARY — pipe.pipe_errors
#
# Erreurs des tubes :
#   BrokenPipeError   écriture alors que plus personne ne lit (EPIPE)
#   PipeClosedError   opération sur un bout déjà fermé
#   ProtocolError     message mal formé (pipe.pipe_stream)
#   TimeoutError      délai dépassé (lecture, ouverture d'un tube nommé)
#   IoError           autre erreur système
#
#   use pipe.pipe_errors as pe
#   try:
#       w.write("x")
#   catch e:
#       if pe.is_broken(e):
#           ...           # le lecteur est parti : arrêter proprement

from core use type
use string as _s

const BROKEN := "BrokenPipeError"
const CLOSED := "PipeClosedError"
const PROTOCOL := "ProtocolError"
const TIMEOUT := "TimeoutError"

func kinds():
    return [BROKEN, CLOSED, PROTOCOL, TIMEOUT, "IoError"]

# Vrai pour une erreur « plus de lecteur » (BrokenPipeError, ou IoError portant EPIPE).
func is_broken(e):
    if e.type == BROKEN:
        return true
    return e.type == "IoError" and _s.contains(e.message, "EPIPE")

func is_timeout(e):
    return e.type == TIMEOUT

func closed(fn):
    raise(CLOSED, fn + " : bout de tube déjà fermé")

func broken(fn):
    raise(BROKEN, fn + " : plus aucun lecteur sur le tube (EPIPE)")

# Relance e en BrokenPipeError s'il s'agit d'un EPIPE, telle quelle sinon.
func reraise(e, fn):
    if is_broken(e) and e.type != BROKEN:
        broken(fn)
    raise(e)

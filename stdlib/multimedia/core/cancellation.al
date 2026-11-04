# ALEX STANDARD LIBRARY — multimedia.core.cancellation
#
# Annulation coopérative des traitements multimédias, au-dessus de async.cancellation (mêmes jetons, utilisables
# aussi dans du code asynchrone). Les boucles longues (décodage, pipeline, lecture) appellent check(jeton) entre
# deux blocs : CancelledError dès que la source a annulé ; un jeton null n'annule jamais.
#
#   use multimedia.core.cancellation as mc
#   src := mc.source()
#   lecteur.run(src.token)              # ailleurs : src.cancel("arrêt demandé")
#   d := mc.Deadline(5.0)               # annulation à échéance, vérifiée à chaque check
#   d.check()                           # CancelledError une fois l'échéance passée
#
# Erreurs : CancelledError.

use async.cancellation as _c
use time as _t

func source():
    return _c.CancellationSource()

func never():
    return null

func is_cancelled(token):
    return token != null and token.cancelled()

func check(token):
    if token != null:
        token.raise_if_cancelled()

# Source annulée automatiquement quand `seconds` (horloge monotone) sont écoulées, constaté à chaque check().
class Deadline:
    func init(seconds):
        self._src = _c.CancellationSource()
        self.token = self._src.token
        self.at = _t.monotonic() + seconds

    func expired():
        if not self.token.cancelled() and _t.monotonic() >= self.at:
            self._src.cancel("délai dépassé")
        return self.token.cancelled()

    func check():
        self.expired()
        self.token.raise_if_cancelled()

    func cancel(reason=null):
        self._src.cancel(reason)

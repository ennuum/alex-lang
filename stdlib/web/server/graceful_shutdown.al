# ALEX STANDARD LIBRARY — web.server.graceful_shutdown
#
# Arrêt propre du serveur : sur demande (stop(), signal INT / TERM), le serveur cesse d'accepter des connexions,
# ferme les connexions inactives, termine les requêtes en cours en leur répondant « Connection: close », puis
# s'arrête — au plus tard après le délai de grâce, où les connexions restantes sont fermées.
#
#   use web.server.graceful_shutdown as gs
#   arret := gs.ShutdownController(10.0)
#   arret.install_signals()               # INT (Ctrl+C) et TERM déclenchent l'arrêt propre
#   ...
#   arret.poll()                          # dans la boucle : relève les signaux reçus
#   if arret.is_draining() and arret.should_finish(gestionnaire):
#       arret.finish()
#
# États : running -> draining -> stopped.

from core use len, type
use time as _time
use signal as _signal

const RUNNING := "running"
const DRAINING := "draining"
const STOPPED := "stopped"

class ShutdownController:
    func init(grace=10.0):
        self.grace = grace
        self.state = RUNNING
        self.deadline = null
        self.reason = null
        self.flags = []
        self.callbacks = []          # fonctions (raison) appelées au début de l'arrêt

    func is_running():
        return self.state == RUNNING

    func is_draining():
        return self.state == DRAINING

    func is_stopped():
        return self.state == STOPPED

    # Demande l'arrêt propre (sans effet s'il est déjà en cours) ; grace : délai propre à cet arrêt.
    func request(reason="stop", grace=null):
        if self.state != RUNNING:
            return
        self.state = DRAINING
        self.reason = reason
        self.deadline = _time.monotonic() + (grace if grace != null else self.grace)
        for cb in self.callbacks:
            try:
                cb(reason)
            catch e:
                ignored := e

    func on_shutdown(callback):
        self.callbacks = self.callbacks + [callback]
        return self

    # Secondes restantes du délai de grâce (0 hors arrêt).
    func remaining():
        if self.deadline == null:
            return 0.0
        r := self.deadline - _time.monotonic()
        return r if r > 0 else 0.0

    # Vrai quand l'arrêt peut se terminer : plus aucune requête en cours, ou délai de grâce écoulé.
    func should_finish(manager):
        if self.state != DRAINING:
            return self.state == STOPPED
        return manager.is_quiet() or self.remaining() <= 0

    func finish():
        self.state = STOPPED

    # Arrêt propre sur réception des signaux (INT et TERM par défaut) ; sans effet si les signaux ne sont pas
    # pris en charge sur la plate-forme. Rend true si l'installation a réussi.
    func install_signals(signals=null):
        sigs := signals if signals != null else ["INT", "TERM"]
        try:
            if not _signal.supported():
                return false
            for s in sigs:
                self.flags = self.flags + [(s, _signal.flag(s))]
            return true
        catch e:
            return false

    # Relève les signaux reçus (à appeler à chaque tour de boucle).
    func poll():
        for f in self.flags:
            if f[1].is_set():
                f[1].take()
                if self.state == RUNNING:
                    self.request("signal " + f[0])
                elif self.state == DRAINING:
                    self.deadline = _time.monotonic()      # second signal : arrêt immédiat

    func uninstall_signals():
        for f in self.flags:
            try:
                f[1].close()
            catch e:
                ignored := e
        self.flags = []

func controller(grace=10.0):
    return ShutdownController(grace)

# ALEX STANDARD LIBRARY — web.server.connection_manager
#
# ConnectionManager : l'ensemble des connexions ouvertes du serveur — admission (limite max_connections),
# correspondance socket -> connexion pour la boucle d'événements, expiration des délais (web.server.timeout),
# fermeture des connexions inactives lors d'un arrêt, et comptes pour les mesures.
#
#   use web.server.connection_manager as cm
#   m := cm.ConnectionManager(limits, timeouts, metrics)
#   if m.can_accept(): m.add(conn)
#   for c in m.expired(): ...          # (connexion, raison) dont un délai est écoulé
#   m.close_idle()                     # arrêt propre : ferme celles qui n'ont pas de requête en cours
#   m.count()

from core use len, type
from collections use append
use time as _time

class ConnectionManager:
    func init(limits, timeouts, metrics=null):
        self.limits = limits
        self.timeouts = timeouts
        self.metrics = metrics
        self.connections = []

    func count():
        return len(self.connections)

    func can_accept():
        return len(self.connections) < self.limits.max_connections

    func add(conn):
        append(self.connections, conn)
        if self.metrics != null:
            self.metrics.connection_opened()
        return conn

    # Retire et ferme une connexion.
    func remove(conn):
        kept := []
        found := false
        for c in self.connections:
            if c == conn:
                found = true
            else:
                append(kept, c)
        self.connections = kept
        if not conn.closed:
            conn.close()
        if found and self.metrics != null:
            self.metrics.connection_closed()

    # Retire une connexion SANS la fermer : elle quitte le HTTP (mise à niveau WebSocket).
    func detach(conn):
        kept := []
        for c in self.connections:
            if c != conn:
                append(kept, c)
        self.connections = kept

    func all():
        return self.connections + []

    # Connexions à surveiller en lecture (file de requêtes pas trop longue, pas en fermeture).
    func readable_candidates():
        out := []
        for c in self.connections:
            if not c.closed and not c.closing and len(c.queue) < self.limits.max_pipelined:
                append(out, c)
        return out

    # Connexion dont le socket brut est sock, ou null.
    func by_socket(sock):
        for c in self.connections:
            if c.raw_socket() == sock:
                return c
        return null

    # Connexions avec des données déjà disponibles (TLS déchiffré en attente, requêtes en file), hors celles qui
    # attendent un gestionnaire async.
    func with_pending_work():
        out := []
        for c in self.connections:
            if not c.closed and not c.is_waiting() and (c.has_request() or c.has_buffered_input()):
                append(out, c)
        return out

    # Paires (connexion, raison) dont un délai est écoulé.
    func expired(now=null):
        t := now if now != null else _time.monotonic()
        out := []
        for c in self.connections:
            if c.has_request() or c.is_waiting():
                continue
            r := self.timeouts.expired_reason(c, t)
            if r != null:
                append(out, (c, r))
        return out

    # Ferme les connexions sans requête en cours (arrêt propre) ; renvoie leur nombre.
    func close_idle():
        n := 0
        for c in self.all():
            if c.phase() == "idle" and not c.has_request() and not c.is_waiting():
                self.remove(c)
                n += 1
        return n

    func close_all():
        for c in self.all():
            self.remove(c)

    # Vrai si aucune connexion n'a de requête commencée, en file ou en cours de traitement async.
    func is_quiet():
        for c in self.connections:
            if c.has_request() or c.is_waiting() or c.phase() != "idle":
                return false
        return true

    func stats():
        phases := {"idle": 0, "header": 0, "body": 0}
        for c in self.connections:
            p := c.phase()
            if p in phases:
                phases[p] = phases[p] + 1
        waiting := 0
        for c in self.connections:
            if c.is_waiting():
                waiting += 1
        return {"open": len(self.connections), "phases": phases, "waiting": waiting}

# ALEX STANDARD LIBRARY — web.client.connection_pool
#
# ConnectionPool : réserve de connexions persistantes (keep-alive) du client, par destination
# (schéma, hôte, port, mandataire). Une connexion rendue après une réponse complète est gardée pour la requête
# suivante vers la même destination ; les connexions inactives depuis trop longtemps, fermées par le serveur ou
# en surnombre sont fermées.
#
#   use web.client.connection_pool as cp
#   pool := cp.ConnectionPool(8, 32, 60.0)
#   c := pool.acquire("https", "exemple.org", 443, tls_cfg, timeout_cfg, null)   # réutilisée ou neuve
#   ...
#   pool.release(c)          # remise dans la réserve (ou fermée si la réserve est pleine)
#   pool.discard(c)          # fermée (réponse incomplète, Connection: close...)
#   pool.stats()             # {"idle": 1, "opened": 1, "reused": 0, ...}
#   pool.close_all()
#
# Erreurs : celles de web.client.connection (à l'ouverture).

from core use len, type
from collections use append, keys
use web.client.connection as _conn

class ConnectionPool:
    func init(max_per_host=8, max_idle=32, idle_timeout=60.0):
        self.max_per_host = max_per_host
        self.max_idle = max_idle
        self.idle_timeout = idle_timeout
        self.idle = {}            # clé -> liste de Connection inactives (la plus récente à la fin)
        self.active = {}          # clé -> nombre de connexions prêtées
        self.opened = 0
        self.reused = 0
        self.closed = 0

    func _idle_count():
        n := 0
        for k in keys(self.idle):
            n += len(self.idle[k])
        return n

    # Ferme les connexions inactives depuis plus de idle_timeout secondes.
    func prune():
        for k in keys(self.idle):
            kept := []
            for c in self.idle[k]:
                if c.idle_time() > self.idle_timeout or c.is_closed():
                    c.close()
                    self.closed += 1
                else:
                    append(kept, c)
            self.idle[k] = kept

    # Connexion inactive réutilisable vers la destination, sinon null.
    func take(key):
        self.prune()
        if not (key in self.idle):
            return null
        lst := self.idle[key]
        while len(lst) > 0:
            c := lst[len(lst) - 1]
            lst = lst[0:len(lst) - 1]
            self.idle[key] = lst
            if c.is_reusable():
                c.reused = true
                self.reused += 1
                self._lend(key)
                return c
            self.closed += 1
        return null

    func _lend(key):
        self.active[key] = (self.active[key] if key in self.active else 0) + 1

    func _unlend(key):
        if key in self.active and self.active[key] > 0:
            self.active[key] = self.active[key] - 1

    # Connexion vers la destination : réutilisée si possible, sinon ouverte.
    func acquire(scheme, host, port, tls_cfg=null, timeout_cfg=null, proxy=null):
        key := _conn.connection_key(scheme, host, port, proxy)
        c := self.take(key)
        if c != null:
            return c
        c = _conn.open(scheme, host, port, tls_cfg, timeout_cfg, proxy)
        self.opened += 1
        self._lend(key)
        return c

    # Rend une connexion en bon état (réponse entièrement lue, keep-alive).
    func release(c):
        key := c.key()
        self._unlend(key)
        if c.is_closed():
            return
        lst := self.idle[key] if key in self.idle else []
        if len(lst) >= self.max_per_host or self._idle_count() >= self.max_idle:
            c.close()
            self.closed += 1
            return
        append(lst, c)
        self.idle[key] = lst

    # Ferme une connexion prêtée qui ne doit pas être réutilisée.
    func discard(c):
        self._unlend(c.key())
        if not c.is_closed():
            c.close()
            self.closed += 1

    func close_all():
        for k in keys(self.idle):
            for c in self.idle[k]:
                c.close()
                self.closed += 1
        self.idle = {}

    func stats():
        act := 0
        for k in keys(self.active):
            act += self.active[k]
        return {"idle": self._idle_count(), "active": act, "opened": self.opened, "reused": self.reused, "closed": self.closed}

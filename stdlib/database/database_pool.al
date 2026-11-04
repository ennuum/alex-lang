# ALEX STANDARD LIBRARY — database.database_pool
#
# Réserve (pool) de connexions réutilisables vers une même base : évite de rouvrir une connexion à chaque
# requête et borne leur nombre. Une connexion rendue est remise à zéro (transaction en cours annulée).
# Avec « memory:nom », toutes les connexions du pool partagent la même base en mémoire.
#
#   use database.database_pool as dp
#   pool := dp.DatabasePool("sqlite:app.db", 4)          # 4 connexions au plus
#   conn := pool.acquire()
#   conn.execute("SELECT 1")
#   pool.release(conn)
#   with pool.connection() as c:                          # rendue automatiquement en sortie
#       c.query("SELECT * FROM t")
#   print(pool.stats())     # {"size": 1, "idle": 1, "in_use": 0, "created": 1, "max_size": 4, "acquired": 2}
#   pool.close()
#
# Erreurs : PoolError (pool épuisé, fermé, connexion étrangère ou rendue deux fois), ConnectionError.

from core use len, type
from collections use append
use database.connection as _c

class _Lease:
    func init(pool):
        self.pool = pool
        self.conn = null

    func __enter__():
        self.conn = self.pool.acquire()
        return self.conn

    func __exit__(a, b, c):
        if self.conn != null:
            self.pool.release(self.conn)
            self.conn = null

class DatabasePool:
    # factory : URL (str) ou fonction sans argument rendant une Connection.
    func init(factory, max_size=5, min_size=0):
        if max_size < 1:
            raise("ArgumentError", "DatabasePool : max_size >= 1 attendu")
        self.factory = factory
        self.max_size = max_size
        self.idle = []
        self.busy = {}          # id -> Connection
        self.created = 0
        self.acquired = 0
        self.closed = false
        i := 0
        while i < min_size and i < max_size:
            append(self.idle, self._new())
            i += 1

    func _new():
        c := null
        if type(self.factory) == "str":
            c = _c.Connection(self.factory)
        else:
            f := self.factory
            c = f()
        self.created += 1
        return c

    func acquire():
        if self.closed:
            raise("PoolError", "DatabasePool : pool fermé")
        c := null
        while len(self.idle) > 0 and c == null:
            cand := self.idle[len(self.idle) - 1]
            self.idle = self.idle[:len(self.idle) - 1]
            if not cand.closed():
                c = cand
        if c == null:
            if len(self.busy) >= self.max_size:
                raise("PoolError", "DatabasePool : pool épuisé (" + str(self.max_size) + " connexions en cours)")
            c = self._new()
        self.busy[c.id] = c
        self.acquired += 1
        return c

    func release(conn):
        if not (conn.id in self.busy):
            raise("PoolError", "DatabasePool.release : connexion inconnue de ce pool, ou déjà rendue")
        del self.busy[conn.id]
        if self.closed or conn.closed():
            if not conn.closed():
                conn.close()
            return
        if conn.in_transaction():
            conn.rollback()
        append(self.idle, conn)

    func connection():
        return _Lease(self)

    func size():
        return len(self.idle) + len(self.busy)

    func stats():
        return {"size": self.size(), "idle": len(self.idle), "in_use": len(self.busy), "created": self.created,
                "max_size": self.max_size, "acquired": self.acquired}

    # Ferme les connexions libres ; celles en cours le seront à leur retour.
    func close():
        self.closed = true
        for c in self.idle:
            c.close()
        self.idle = []

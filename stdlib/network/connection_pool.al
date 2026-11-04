# ALEX STANDARD LIBRARY — network.connection_pool
#
# Réserve de connexions réutilisables (keep-alive) regroupées par destination : un client HTTP, gRPC ou autre
# évite une poignée de main TCP (et TLS) par requête.
#
#   ConnectionPool(max_per_key, max_idle_per_key, idle_timeout, max_uses)
#   pool.acquire(clé, fabrique)   connexion libre encore vivante, ou nouvelle par fabrique()
#   pool.release(clé, conn)       rend la connexion (réutilisable) ; pool.discard(clé, conn) la ferme
#   pool.lease(clé, fabrique)     même chose avec `with` : rendue automatiquement (fermée en cas d'erreur)
#   pool.close_idle(), close_all(), stats()
#
# Une connexion libre est vérifiée avant d'être reprise : si le pair l'a fermée (ou a envoyé des octets
# inattendus) pendant qu'elle dormait, elle est jetée et une autre est prise. Les connexions sont des
# network.tcp.Connection (TCP ou TLS).
#
# ALEX exécute un fil par VM : la réserve n'est pas partagée entre fils (concurrency.thread) ; avec async, une
# connexion empruntée n'est rendue qu'à la fin de son usage.
#
# Erreurs : PoolError (réserve fermée, limite de connexions simultanées atteinte).
#
# Exemple
#   use network.connection_pool as cp
#   pool := cp.ConnectionPool(4)
#   with pool.lease("tcp://exemple.org:80", () => tcp.connect("exemple.org", 80, 5.0)) as conn:
#       conn.write(...)

from core use len, type
from collections use append, keys, contains_key
use _native_net as _n
use time as _time
use network.socket as _sk
use network.tls as _tls

class _Entry:
    func init(conn):
        self.conn = conn
        self.created = _time.monotonic()
        self.last_used = self.created
        self.uses = 0

# Vrai si une connexion inactive est encore utilisable : ouverte, sans octet en attente ni fin de flux.
func is_alive(conn):
    if conn.is_closed() or conn.eof:
        return false
    if _n.blen(conn.buffer) > 0:
        return false
    s := conn.socket
    raw := s
    if isinstance(s, _tls.TlsSocket):
        if s.pending() > 0:
            return false
        raw = s.socket
    try:
        ready := _sk.wait([raw], "read", 0)
        return len(ready) == 0
    catch e:
        return false

class _Outcome:
    func init(value, reusable):
        self.value = value
        self.reusable = reusable

# Résultat de fn pour ConnectionPool.run avec la décision de réutilisation de la connexion.
func keep_alive(value, reusable):
    return _Outcome(value, reusable)

class Lease:
    func init(pool, key, conn):
        self.pool = pool
        self.key = key
        self.conn = conn
        self.reusable = true

    # Indique que la connexion ne doit pas être réutilisée (réponse « Connection: close », état incertain).
    func do_not_reuse():
        self.reusable = false

    func __enter__():
        return self.conn

    # `with` ne transmet pas l'exception éventuelle : une connexion dont l'état est douteux (octets non lus, fin
    # de flux, fermée) est jetée ; une réponse restée en attente sera détectée au prochain emprunt (is_alive).
    func __exit__(t, v, tb):
        c := self.conn
        if not self.reusable or c.is_closed() or c.eof or _n.blen(c.buffer) > 0:
            self.pool.discard(self.key, c)
        else:
            self.pool.release(self.key, c)
        return false

class ConnectionPool:
    # max_per_key : connexions simultanées par destination (empruntées + libres) ; max_idle_per_key : libres
    # gardées ; idle_timeout : secondes avant de fermer une connexion libre ; max_uses : réutilisations au plus
    # (null : sans limite) ; max_lifetime : âge maximal (secondes) d'une connexion, ou null.
    func init(max_per_key=10, max_idle_per_key=null, idle_timeout=60.0, max_uses=null, max_lifetime=null):
        if type(max_per_key) != "int" or max_per_key < 1:
            raise("ArgumentError", "connection_pool : max_per_key entier >= 1 attendu")
        self.max_per_key = max_per_key
        self.max_idle_per_key = max_idle_per_key
        if max_idle_per_key == null:
            self.max_idle_per_key = max_per_key
        self.idle_timeout = idle_timeout
        self.max_uses = max_uses
        self.max_lifetime = max_lifetime
        self.idle = {}          # clé -> list[_Entry]
        self.busy = {}          # clé -> list[_Entry]
        self.closed = false
        self.created = 0
        self.reused = 0
        self.discarded = 0

    func _list(table, key):
        if not contains_key(table, key):
            table[key] = []
        return table[key]

    func _expired(e, now):
        if self.idle_timeout != null and now - e.last_used > self.idle_timeout:
            return true
        if self.max_lifetime != null and now - e.created > self.max_lifetime:
            return true
        if self.max_uses != null and e.uses >= self.max_uses:
            return true
        return false

    # Connexion pour `key` : une libre encore vivante, sinon factory() (fonction sans argument).
    func acquire(key, factory):
        if self.closed:
            raise("PoolError", "connection_pool : réserve fermée")
        now := _time.monotonic()
        idle := self._list(self.idle, key)
        while len(idle) > 0:
            e := idle[len(idle) - 1]
            self.idle[key] = idle[0:len(idle) - 1]
            idle = self.idle[key]
            if self._expired(e, now) or not is_alive(e.conn):
                self._close(e.conn)
                self.discarded += 1
                continue
            e.uses += 1
            e.last_used = now
            append(self._list(self.busy, key), e)
            self.reused += 1
            return e.conn
        busy := self._list(self.busy, key)
        if len(busy) + len(idle) >= self.max_per_key:
            raise("PoolError", "connection_pool : " + str(self.max_per_key) + " connexions déjà empruntées pour " + str(key))
        conn := factory()
        e := _Entry(conn)
        e.uses = 1
        append(busy, e)
        self.created += 1
        return conn

    func _take_busy(key, conn):
        busy := self._list(self.busy, key)
        kept := []
        found := null
        for e in busy:
            if found == null and e.conn == conn:
                found = e
            else:
                append(kept, e)
        self.busy[key] = kept
        return found

    # Rend une connexion empruntée ; elle est gardée si elle est réutilisable, sinon fermée.
    func release(key, conn, reusable=true):
        e := self._take_busy(key, conn)
        if e == null:
            e = _Entry(conn)
        now := _time.monotonic()
        e.last_used = now
        idle := self._list(self.idle, key)
        if self.closed or not reusable or conn.is_closed() or self._expired(e, now) or len(idle) >= self.max_idle_per_key:
            self._close(conn)
            self.discarded += 1
            return
        append(idle, e)

    # Ferme une connexion empruntée (erreur, état incertain).
    func discard(key, conn):
        self._take_busy(key, conn)
        self._close(conn)
        self.discarded += 1

    func lease(key, factory):
        return Lease(self, key, self.acquire(key, factory))

    # Emprunte une connexion, appelle fn(conn) et rend la connexion ; en cas d'erreur elle est fermée et l'erreur
    # relancée. fn peut renvoyer (résultat, réutilisable) via keep_alive() pour refuser la réutilisation.
    func run(key, factory, fn):
        conn := self.acquire(key, factory)
        r := null
        try:
            r = fn(conn)
        catch e:
            self.discard(key, conn)
            raise(e)
        if isinstance(r, _Outcome):
            if r.reusable:
                self.release(key, conn)
            else:
                self.discard(key, conn)
            return r.value
        self.release(key, conn)
        return r

    func _close(conn):
        try:
            conn.close()
        catch e:
            ignored := e

    # Ferme les connexions libres expirées (toutes si force=true) ; rend leur nombre.
    func close_idle(force=false):
        now := _time.monotonic()
        n := 0
        for k in keys(self.idle):
            kept := []
            for e in self.idle[k]:
                if force or self._expired(e, now) or not is_alive(e.conn):
                    self._close(e.conn)
                    n += 1
                else:
                    append(kept, e)
            self.idle[k] = kept
        self.discarded += n
        return n

    # Ferme tout (libres et empruntées) et refuse les emprunts suivants.
    func close_all():
        for k in keys(self.idle):
            for e in self.idle[k]:
                self._close(e.conn)
        for k in keys(self.busy):
            for e in self.busy[k]:
                self._close(e.conn)
        self.idle = {}
        self.busy = {}
        self.closed = true

    func close():
        self.close_all()

    func idle_count(key=null):
        n := 0
        for k in keys(self.idle):
            if key == null or k == key:
                n += len(self.idle[k])
        return n

    func busy_count(key=null):
        n := 0
        for k in keys(self.busy):
            if key == null or k == key:
                n += len(self.busy[k])
        return n

    func stats():
        return {"idle": self.idle_count(), "busy": self.busy_count(), "created": self.created, "reused": self.reused, "discarded": self.discarded}

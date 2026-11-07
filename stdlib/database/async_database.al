# ALEX STANDARD LIBRARY — database.async_database
#
# Base de données attendue avec await, sans bloquer la boucle async (serveur web, tâches) : la connexion vit dans
# un fil dédié (thread.thread_pool, une réserve d'un fil par base), qui exécute les requêtes une à une ; la tâche
# qui attend cède la main pendant ce temps.
#
#   use database.async_database as adb
#   db := adb.open("sqlite:/var/lib/app/notes.db")
#   await db.script("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, titre TEXT)")
#   id := await db.insert("notes", {"titre": "Été"})
#   notes := await db.query("SELECT id, titre FROM notes WHERE id > ?", [0])     # liste de dict
#   n := await db.scalar("SELECT COUNT(*) FROM notes")
#   await db.transaction([["UPDATE notes SET titre = ? WHERE id = ?", ["x", 1]], ["DELETE FROM notes WHERE id = ?", [2]]])
#   await db.close()
#
# Toutes les requêtes d'une base passent par le même fil, dans l'ordre : pas de concurrence sur la connexion
# (ce que SQLite demande). transaction(instructions) exécute une liste [sql, paramètres] entre BEGIN et COMMIT
# (ROLLBACK si l'une échoue, et l'erreur est relancée). Les erreurs de la base sont relancées par await avec leur
# type (QueryError, IntegrityError...).
#
# URL : celles de database.connect (sqlite:chemin, alexdb:fichier.json, memory:, postgres://, alexdb://). Avec
# un serveur ALEX DB, transaction() part en une seule requête (BEGIN ... COMMIT) : atomique, sans verrou croisé. Une base « memory: » vit dans
# le fil de la base : elle est partagée par toutes les requêtes de cet AsyncDatabase, et perdue à close().
# Les valeurs passent d'un fil à l'autre par copie : paramètres et résultats sont des valeurs simples (null, bool,
# nombres, str, list, dict).

from core use len, type
use thread.thread_pool as _tp
use thread.offload as _offload
use database.database as _db

# Connexions ouvertes DANS le fil de la base (chaque fil a sa propre copie de ce module).
_CONNS := {}

class AsyncDatabase:
    func init(url="memory:"):
        self.url = url
        self.pool = _tp.ThreadPool(1, "db")
        self.closed = false

    func _run(op, a=null, b=null):
        if self.closed:
            raise("ConnectionError", "AsyncDatabase : base fermée")
        return _offload.run_on(self.pool, _op, [self.url, op, a, b])

    # Instruction quelconque ; {"rowcount", "lastrowid", "columns", "rows"} (rows : listes de valeurs).
    func execute(sql, params=null):
        return self._run("execute", sql, params)

    # Lignes sous forme de dict.
    func query(sql, params=null):
        return self._run("query", sql, params)

    # Première ligne (dict) ou null.
    func query_one(sql, params=null):
        return self._run("query_one", sql, params)

    # Première colonne de la première ligne, ou null.
    func scalar(sql, params=null):
        return self._run("scalar", sql, params)

    # Script de plusieurs instructions séparées par « ; ».
    func script(sql):
        return self._run("script", sql)

    # INSERT d'un dict ; identifiant de la ligne.
    func insert(table, values):
        return self._run("insert", table, values)

    # Liste [sql, paramètres] exécutée atomiquement ; liste des {"rowcount", "lastrowid"}.
    func transaction(statements):
        return self._run("transaction", statements)

    func tables():
        return self._run("tables")

    # Ferme la connexion et arrête le fil de la base.
    async func close():
        if self.closed:
            return
        await self._run("close")
        self.closed = true
        self.pool.shutdown(true)

func open(url="memory:"):
    return AsyncDatabase(url)

# ---------------------------------------------------------------- dans le fil de la base

func _conn(url):
    if not (url in _CONNS) or _CONNS[url] == null:
        _CONNS[url] = _db.connect(url)
    return _CONNS[url]

func _op(url, op, a, b):
    if op == "close":
        if url in _CONNS and _CONNS[url] != null:
            _CONNS[url].close()
            _CONNS[url] = null
        return null
    c := _conn(url)
    if op == "execute":
        r := c.execute(a, b)
        return {"rowcount": r.rowcount, "lastrowid": r.lastrowid, "columns": r.columns, "rows": r.rows}
    if op == "query":
        return c.query(a, b)
    if op == "query_one":
        return c.query_one(a, b)
    if op == "scalar":
        return c.scalar(a, b)
    if op == "script":
        c.executescript(a)
        return null
    if op == "insert":
        return c.insert(a, b)
    if op == "tables":
        return c.tables()
    if op == "transaction":
        b := c.batch(a)
        if b != null:
            return b
        out := []
        c.begin()
        try:
            for st in a:
                r := c.execute(st[0], st[1] if len(st) > 1 else null)
                out = out + [{"rowcount": r.rowcount, "lastrowid": r.lastrowid}]
            c.commit()
        catch e:
            if c.in_transaction():
                c.rollback()
            raise(e.type, e.message)
        return out
    raise("ArgumentError", "AsyncDatabase : opération inconnue " + str(op))

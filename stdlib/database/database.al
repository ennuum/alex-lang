# ALEX STANDARD LIBRARY — database.database
#
# Point d'entrée du paquet database : ouvrir une base, connaître les moteurs disponibles, et raccourcis.
#
#   use database.database as db
#   conn := db.connect("memory:")                         # moteur SQL embarqué (toujours disponible)
#   conn2 := db.connect("sqlite:/tmp/app.db")             # SQLite réel si libsqlite3 est installée
#   print(db.backends())                                  # ["alexdb", "sqlite"]
#   with db.connect("alexdb:donnees.json") as c:
#       c.executescript("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, texte TEXT);")
#       c.insert("notes", {"texte": "bonjour"})
#   print(db.run_script("memory:", "CREATE TABLE t (x INT); INSERT INTO t VALUES (1); SELECT x FROM t;").rows)
#
# Voir database.connection (Connection), database.query (construction de requêtes), database.transaction,
# database.prepared_statement, database.result_set, database.database_pool, database.database_errors.
# Erreurs : ConnectionError, QueryError, IntegrityError, TransactionError.

from core use len
use database.connection as _c
use database._sqlite as _lite
use database.database_pool as _pool

func connect(url="memory:"):
    return _c.Connection(url)

func memory(name=null):
    if name == null:
        return _c.Connection("memory:")
    return _c.Connection("memory:" + name)

func sqlite_available():
    return _lite.available()

func sqlite_version():
    if not _lite.available():
        return null
    return _lite.version()

func backends():
    if _lite.available():
        return ["alexdb", "sqlite"]
    return ["alexdb"]

func pool(url, max_size=5):
    return _pool.DatabasePool(url, max_size)

# Exécute un script sur une nouvelle connexion, la ferme ; résultat de la dernière instruction.
func run_script(url, sql):
    c := _c.Connection(url)
    try:
        return c.executescript(sql)
    finally:
        c.close()

# Copie toutes les tables (schéma simplifié et données) d'une connexion vers une autre.
func copy_tables(src, dst):
    n := 0
    for t in src.tables():
        cols := src.columns(t)
        defs := []
        for c in cols:
            d := _c.quote_identifier(c["name"])
            if c["type"] != "":
                d += " " + c["type"]
            if c["primary"]:
                d += " PRIMARY KEY"
            elif c["not_null"]:
                d += " NOT NULL"
            defs = defs + [d]
        dst.execute("CREATE TABLE IF NOT EXISTS " + _c.quote_identifier(t) + " (" + _join(defs) + ")")
        for r in src.query("SELECT * FROM " + _c.quote_identifier(t)):
            dst.insert(t, r)
            n += 1
    return n

func _join(xs):
    out := ""
    i := 0
    while i < len(xs):
        if i > 0:
            out += ", "
        out += xs[i]
        i += 1
    return out

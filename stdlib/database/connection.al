# ALEX STANDARD LIBRARY — database.connection
#
# Connexion à une base de données. Trois moteurs :
#   « alexdb »  moteur SQL embarqué écrit en ALEX (toujours disponible) : en mémoire, ou persistant dans un
#               fichier JSON réécrit atomiquement à chaque validation
#   « sqlite »  SQLite 3 réel par FFI (si libsqlite3 est installée) : fichiers .db standards, SQL complet
#   « postgres » serveur PostgreSQL, pilote écrit en ALEX (database._postgres) : postgres://u:mdp@hôte:5432/base
#   « alexdb-server » serveur ALEX DB (projet AlexDB, langage AQL), pilote écrit en ALEX (database._aqlp) :
#               alexdb://u:mdp@hôte:5442/base ; clé primaire INT omise attribuée par le serveur (last_insert_id)
# URL : "memory:" (privée), "memory:nom" (partagée dans le processus, p. ex. par un pool), "alexdb:chemin.json"
# (ou un chemin finissant par .json), "sqlite:chemin.db", "sqlite::memory:" (ou un chemin finissant par .db /
# .sqlite).
#
#   use database.connection as dc
#   conn := dc.Connection("memory:")
#   conn.execute("CREATE TABLE clients (id INTEGER PRIMARY KEY, nom TEXT NOT NULL, ville TEXT)")
#   id := conn.insert("clients", {"nom": "Ana", "ville": "Lyon"})          # identifiant attribué
#   conn.execute("INSERT INTO clients (nom) VALUES (?)", ["Bob"])
#   print(conn.query("SELECT * FROM clients WHERE ville = :v", {"v": "Lyon"}))   # liste de dicts
#   print(conn.scalar("SELECT COUNT(*) FROM clients"))                  # 2
#   conn.update("clients", {"ville": "Paris"}, "nom = ?", ["Bob"])
#   print(conn.tables(), conn.columns("clients"))
#   with dc.Connection("alexdb:/tmp/demo.json") as db:   # fermée (et enregistrée) en sortie
#       db.executescript("CREATE TABLE IF NOT EXISTS t (x INT); INSERT INTO t VALUES (1);")
#
# Hors transaction, chaque instruction est validée aussitôt (autocommit) ; begin / commit / rollback, ou
# database.transaction, pour grouper.
# Erreurs : ConnectionError (URL, ouverture, connexion fermée), QueryError, IntegrityError, TransactionError.

from core use len, type
from collections use append
use string as _s
use os as _os
use io as _io
use json as _json
use database._sql as _sql
use database._sqlite as _lite
use database._postgres as _pg
use database._aqlp as _aqlp
use database.result_set as _rs
use database.prepared_statement as _ps
use database.transaction as _tx

_shared := {}
_ids := [0]

class _AlexImpl:
    func init(path, shared_name):
        self.path = path
        self.engine = null
        self.cache = {}
        self.cache_order = []
        if shared_name != null:
            if not (shared_name in _shared):
                _shared[shared_name] = _sql.Engine()
            self.engine = _shared[shared_name]
        elif path != null and _os.exists(path):
            try:
                self.engine = _sql.engine_from_dict(_json.parse(_io.read_file(path)))
            catch e:
                raise("ConnectionError", "base '" + path + "' illisible : " + e.message)
        else:
            self.engine = _sql.Engine()
            if path != null:
                self.engine.dirty = true
                self.save()

    func parsed(sql):
        if sql in self.cache:
            return self.cache[sql]
        p := _sql.parse(sql)
        if len(self.cache_order) >= 256:
            old := self.cache_order[0]
            self.cache_order = self.cache_order[1:]
            nc := {}
            for k in self.cache:
                if k != old:
                    nc[k] = self.cache[k]
            self.cache = nc
        self.cache[sql] = p
        append(self.cache_order, sql)
        return p

    func run_parsed(stmts, params, conn):
        last := [[], [], 0]
        for st in stmts:
            try:
                last = self.engine.execute(st, params)
            finally:
                if not self.engine.in_transaction():
                    self.save()
        return conn._result(last, null)

    func save():
        if self.path == null or not self.engine.dirty:
            return
        tmp := self.path + ".tmp"
        _io.write_file(tmp, _json.stringify(_sql.engine_to_dict(self.engine)))
        _os.move(tmp, self.path)
        self.engine.dirty = false

    func tables():
        return [self.engine.tables[k].name for k in self.engine.tables]

    func columns(t):
        tb := self.engine.table(t)
        return [{"name": c["name"], "type": c["type"], "primary": c["primary"], "not_null": c["not_null"], "unique": c["unique"]} for c in tb.columns]

    func close():
        self.save()

class _SqliteImpl:
    func init(path):
        self.db = _lite.SqliteConnection(path)
        self.path = path

    func tables():
        r := self.db.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name", null)
        return [x[0] for x in r[1]]

    func columns(t):
        r := self.db.execute("PRAGMA table_info(\"" + _s.replace(t, "\"", "\"\"") + "\")", null)
        if len(r[1]) == 0:
            raise("QueryError", "table inconnue : " + t)
        return [{"name": x[1], "type": _s.upper(x[2]), "primary": x[5] != 0, "not_null": x[3] != 0, "unique": false} for x in r[1]]

    func close():
        self.db.close()

class _AqlpImpl:
    func init(url):
        self.db = _aqlp.AqlpConnection(url)

    func tables():
        return self.db.tables()

    func columns(t):
        return self.db.columns(t)

    func close():
        self.db.close()

class _PgImpl:
    func init(url):
        self.db = _pg.PgConnection(url)

    func tables():
        return self.db.tables()

    func columns(t):
        return self.db.columns(t)

    func close():
        self.db.close()

# [moteur, chemin, nom partagé] d'une URL.
func parse_url(url):
    if type(url) != "str":
        raise("ConnectionError", "URL de base de données str attendue")
    if url == "memory:" or url == ":memory:" or url == "alexdb::memory:" or url == "alexdb:":
        return ["alexdb", null, null]
    if _s.starts_with(url, "memory:"):
        return ["alexdb", null, _s.substring(url, 7, len(url))]
    if _s.starts_with(url, "alexdb://"):
        return ["alexdb-server", url, null]
    if _s.starts_with(url, "alexdb:"):
        return ["alexdb", _s.substring(url, 7, len(url)), null]
    if _s.starts_with(url, "postgres://") or _s.starts_with(url, "postgresql://"):
        return ["postgres", url, null]
    if _s.starts_with(url, "sqlite:"):
        p := _s.substring(url, 7, len(url))
        if _s.starts_with(p, "//"):
            p = _s.substring(p, 2, len(p))
        if p == "" or p == "memory:":
            p = ":memory:"
        return ["sqlite", p, null]
    if _s.ends_with(url, ".json"):
        return ["alexdb", url, null]
    if _s.ends_with(url, ".db") or _s.ends_with(url, ".sqlite") or _s.ends_with(url, ".sqlite3"):
        return ["sqlite", url, null]
    raise("ConnectionError", "URL de base de données non reconnue : '" + url + "' (memory:, alexdb:fichier.json, sqlite:fichier.db, postgres://..., alexdb://...)")

class Connection:
    func init(url="memory:"):
        u := parse_url(url)
        self.url = url
        self.backend = u[0]
        self.path = u[1]
        self._closed = false
        self.last_insert_id = null
        self.total_changes = 0
        self.statements = 0
        _ids[0] += 1
        self.id = _ids[0]
        if self.backend == "sqlite":
            self._impl = _SqliteImpl(u[1])
        elif self.backend == "postgres":
            self._impl = _PgImpl(u[1])
        elif self.backend == "alexdb-server":
            self._impl = _AqlpImpl(u[1])
        else:
            self._impl = _AlexImpl(u[1], u[2])

    # Vrai pour un pilote externe (SQLite, PostgreSQL, serveur ALEX DB) : self._impl.db suit le contrat des pilotes.
    func _driver():
        return self.backend != "alexdb"

    # Transaction d'un seul bloc ([sql, paramètres], ...) si le pilote sait l'envoyer en une fois (serveur ALEX
    # DB) ; null sinon (l'appelant fait BEGIN / instructions / COMMIT).
    func batch(statements):
        self._check_open()
        if self.backend != "alexdb-server" or self.in_transaction():
            return null
        for st in statements:
            if len(st) > 1 and st[1] != null and type(st[1]) != "list":
                return null
        out := self._impl.db.batch(statements)
        for r in out:
            self.total_changes += r["rowcount"]
            self.statements += 1
            if r["lastrowid"] != null:
                self.last_insert_id = r["lastrowid"]
        return out

    func _check_open():
        if self._closed:
            raise("ConnectionError", "connexion fermée")

    func _result(r, sql):
        lid := null
        if len(r[0]) == 0 and r[2] > 0:
            if self._driver():
                lid = self._impl.db.last_id()
            else:
                lid = self._impl.engine.last_id
            if sql == null or _s.starts_with(_s.upper(_s.trim(sql)), "INSERT"):
                self.last_insert_id = lid
            elif self.backend == "alexdb":
                self.last_insert_id = lid
        if len(r[0]) == 0:
            self.total_changes += r[2]
        self.statements += 1
        return _rs.ResultSet(r[0], r[1], r[2], self.last_insert_id)

    # Une instruction (ou plusieurs pour alexdb) ; ResultSet.
    func execute(sql, params=null):
        self._check_open()
        if self._driver():
            return self._result(self._impl.db.execute(sql, params), sql)
        return self._impl.run_parsed(self._impl.parsed(sql), params, self)

    func executemany(sql, param_sets):
        st := self.prepare(sql)
        try:
            return st.execute_many(param_sets)
        finally:
            st.close()

    # Script de plusieurs instructions séparées par « ; » (sans paramètres).
    func executescript(sql):
        self._check_open()
        if self._driver():
            return self._result(self._impl.db.script(sql), null)
        return self.execute(sql)

    func query(sql, params=null):
        return self.execute(sql, params).dicts()

    func query_one(sql, params=null):
        r := self.execute(sql, params).first()
        if r == null:
            return null
        return r.to_dict()

    func scalar(sql, params=null):
        return self.execute(sql, params).scalar()

    func prepare(sql):
        return _ps.PreparedStatement(self, sql)

    func begin():
        if self.in_transaction():
            raise("TransactionError", "BEGIN : une transaction est déjà ouverte")
        self.execute("BEGIN")
        return self

    func commit():
        if not self.in_transaction():
            raise("TransactionError", "COMMIT : aucune transaction ouverte")
        self.execute("COMMIT")
        return self

    func rollback():
        if not self.in_transaction():
            raise("TransactionError", "ROLLBACK : aucune transaction ouverte")
        self.execute("ROLLBACK")
        return self

    func savepoint(name):
        self.execute("SAVEPOINT " + quote_identifier(name))

    func release(name):
        self.execute("RELEASE SAVEPOINT " + quote_identifier(name))

    func rollback_to(name):
        self.execute("ROLLBACK TO SAVEPOINT " + quote_identifier(name))

    func in_transaction():
        self._check_open()
        if self._driver():
            return self._impl.db.in_transaction()
        return self._impl.engine.in_transaction()

    func transaction():
        return _tx.Transaction(self)

    func tables():
        self._check_open()
        return self._impl.tables()

    func has_table(name):
        for t in self.tables():
            if _s.lower(t) == _s.lower(name):
                return true
        return false

    func columns(table):
        self._check_open()
        return self._impl.columns(table)

    # INSERT d'un dict {colonne: valeur} ; identifiant de la ligne.
    func insert(table, values):
        cols := [k for k in values]
        sql := "INSERT INTO " + quote_identifier(table) + " (" + _s.join(", ", [quote_identifier(c) for c in cols]) + ") VALUES (" + _s.join(", ", ["?" for c in cols]) + ")"
        self.execute(sql, [values[c] for c in cols])
        return self.last_insert_id

    func insert_many(table, rows):
        n := 0
        for r in rows:
            self.insert(table, r)
            n += 1
        return n

    # UPDATE table SET ... WHERE where ; nombre de lignes modifiées.
    func update(table, values, where=null, params=null):
        cols := [k for k in values]
        sql := "UPDATE " + quote_identifier(table) + " SET " + _s.join(", ", [quote_identifier(c) + " = ?" for c in cols])
        ps := [values[c] for c in cols]
        if where != null:
            sql += " WHERE " + where
            if params != null:
                ps = ps + params
        return self.execute(sql, ps).rowcount

    func delete(table, where=null, params=null):
        sql := "DELETE FROM " + quote_identifier(table)
        if where != null:
            sql += " WHERE " + where
        return self.execute(sql, params).rowcount

    func closed():
        return self._closed

    func close():
        if not self._closed:
            if self.in_transaction():
                self.rollback()
            self._impl.close()
            self._closed = true

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.close()

    func __str__():
        return "Connection(" + self.url + ", " + self.backend + ")"

func _is_simple(name):
    if len(name) == 0:
        return false
    for c in name:
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or (c >= '0' and c <= '9')):
            return false
    return not (name[0] >= '0' and name[0] <= '9')

# Identifiant SQL sûr : tel quel s'il est simple, sinon entre guillemets doubles.
func quote_identifier(name):
    if _is_simple(name) and not (_s.upper(name) in _sql.KEYWORDS):
        return name
    return "\"" + _s.replace(name, "\"", "\"\"") + "\""

# Littéral SQL (pour journaux / scripts ; préférer les paramètres).
func quote_literal(v):
    if v == null:
        return "NULL"
    t := type(v)
    if t == "bool":
        if v:
            return "1"
        return "0"
    if t == "int" or t == "float":
        return str(v)
    return "'" + _s.replace(str(v), "'", "''") + "'"

func connect(url="memory:"):
    return Connection(url)

# Oublie une base « memory:nom » partagée.
func drop_shared(name):
    if name in _shared:
        del _shared[name]
        return true
    return false

# Tests : database.database, connection, query, transaction, prepared_statement, result_set, database_pool,
# database_errors (moteur alexdb, et SQLite s'il est installé).
from core use len, type
from collections use append
use check as t
use os
use io
use string
use database.database as db
use database.connection as dc
use database.query as q
use database.transaction as tx
use database.database_pool as dp
use database.database_errors as dbe
use database.result_set as rs

func scenario(url, label):
    c := db.connect(url)
    c.executescript("CREATE TABLE clients (id INTEGER PRIMARY KEY, nom TEXT NOT NULL UNIQUE, age INTEGER, ville TEXT DEFAULT 'Paris'); CREATE TABLE commandes (id INTEGER PRIMARY KEY, client_id INTEGER, total REAL);")
    t.check(c.has_table("clients"), label + " tables")
    t.eq(c.insert("clients", {"nom": "Ana", "age": 30}), 1, label + " insert id")
    c.execute("INSERT INTO clients (nom, age, ville) VALUES (?, ?, ?)", ["Bob", 25, "Lyon"])
    t.eq(c.last_insert_id, 2, label + " last_insert_id")
    c.execute("INSERT INTO clients (nom, age) VALUES (:n, :a)", {"n": "Céline", "a": 41})
    t.eq(c.executemany("INSERT INTO commandes (client_id, total) VALUES (?, ?)", [[1, 10.0], [1, 5.5], [2, 7.0]]), 3, label + " executemany")
    t.eq(c.scalar("SELECT COUNT(*) FROM clients"), 3, label + " scalar")
    r := c.execute("SELECT id, nom, ville FROM clients ORDER BY age DESC")
    t.eq(r.columns, ["id", "nom", "ville"], label + " colonnes")
    t.eq(r.column("nom"), ["Céline", "Ana", "Bob"], label + " tri")
    t.eq(r[0]["ville"], "Paris", label + " défaut")
    noms := []
    for ligne in r:
        append(noms, ligne[1])
    t.eq(len(noms), 3, label + " itération")
    t.eq(r.fetch_one()["nom"], "Céline", label + " fetch_one")
    t.eq(len(r.fetch_all()), 2, label + " fetch_all")
    agg := c.query("SELECT c.nom AS nom, SUM(o.total) AS s, COUNT(o.id) AS n FROM clients c LEFT JOIN commandes o ON o.client_id = c.id GROUP BY c.nom ORDER BY s DESC")
    t.eq(agg[0]["nom"], "Ana", label + " jointure + groupe")
    t.eq(agg[0]["s"], 15.5, label + " somme")
    t.eq(c.query_one("SELECT nom FROM clients WHERE nom LIKE ? AND age BETWEEN 20 AND 35 ORDER BY nom", ["%b%"])["nom"], "Bob", label + " like/between")
    t.eq(c.query_one("SELECT nom FROM clients WHERE id = 99"), null, label + " query_one vide")
    t.eq(c.update("clients", {"ville": "Nice"}, "nom = ?", ["Bob"]), 1, label + " update")
    t.eq(c.scalar("SELECT ville FROM clients WHERE id = 2"), "Nice", label + " update lu")
    t.raises(() => c.execute("INSERT INTO clients (nom) VALUES ('Ana')"), "IntegrityError", label + " unique")
    t.raises(() => c.execute("INSERT INTO clients (age) VALUES (3)"), "IntegrityError", label + " not null")
    t.raises(() => c.execute("SELEC 1"), "QueryError", label + " syntaxe")
    t.raises(() => c.execute("SELECT * FROM absente"), "QueryError", label + " table inconnue")
    t.raises(() => c.execute("SELECT * FROM clients WHERE id = ?"), "QueryError", label + " paramètre manquant")
    # transactions
    c.begin()
    c.execute("DELETE FROM commandes")
    t.check(c.in_transaction(), label + " en transaction")
    c.rollback()
    t.eq(c.scalar("SELECT COUNT(*) FROM commandes"), 3, label + " rollback")
    tx.run(c, (cc) => cc.execute("UPDATE clients SET age = age + 1"))
    t.eq(c.scalar("SELECT age FROM clients WHERE id = 1"), 31, label + " tx.run commit")
    msg := ""
    try:
        tx.run(c, (cc) => [cc.execute("UPDATE clients SET age = 0"), cc.execute("INSERT INTO clients (nom) VALUES ('Ana')")])
    catch e:
        msg = e.type
    t.eq(msg, "IntegrityError", label + " tx.run erreur relancée")
    t.eq(c.scalar("SELECT age FROM clients WHERE id = 1"), 31, label + " tx.run annulée")
    outer := c.transaction().begin()
    c.execute("INSERT INTO commandes (client_id, total) VALUES (3, 1.0)")
    inner := c.transaction().begin()
    t.check(inner.nested(), label + " savepoint")
    c.execute("INSERT INTO commandes (client_id, total) VALUES (3, 2.0)")
    inner.rollback()
    outer.commit()
    t.eq(c.scalar("SELECT SUM(total) FROM commandes WHERE client_id = 3"), 1.0, label + " savepoint annulé")
    with c.transaction() as tr:
        c.execute("DELETE FROM commandes")
    t.eq(c.scalar("SELECT COUNT(*) FROM commandes"), 4, label + " with sans commit = annulation")
    t.raises(() => c.commit(), "TransactionError", label + " commit sans transaction")
    # requêtes préparées et constructeur
    st := c.prepare("SELECT nom FROM clients WHERE id = ?")
    t.eq(st.execute([1]).scalar(), "Ana", label + " préparée 1")
    t.eq(st.execute([3]).scalar(), "Céline", label + " préparée 2")
    t.eq(st.param_count(), 1, label + " param_count")
    st.close()
    t.raises(() => st.execute([1]), "DatabaseError", label + " préparée fermée")
    qq := q.select("clients", ["nom"]).where("age > ?", [26]).where_in("ville", ["Paris", "Nice"]).order_by("nom", true)
    t.eq(qq.run(c).column("nom"), ["Céline", "Ana"], label + " query builder")
    t.eq(q.select("clients").where_eq("ville", "Nice").count(c), 1, label + " count")
    q.insert("clients", [{"nom": "Dan", "age": 19}, {"nom": "Eve", "age": 22}]).run(c)
    t.eq(q.update("clients").set({"ville": "Brest"}).where("age < ?", [23]).run(c).rowcount, 2, label + " update builder")
    t.eq(q.delete("clients").where_eq("nom", "Dan").run(c).rowcount, 1, label + " delete builder")
    t.eq(q.select("clients").order_by("id").page(2, 2).run(c).column("id"), [3, 5], label + " pagination")
    cols := c.columns("clients")
    t.eq(cols[0]["name"], "id", label + " columns")
    t.check(cols[0]["primary"], label + " primary")
    c.close()
    t.check(c.closed(), label + " fermée")
    t.raises(() => c.execute("SELECT 1"), "ConnectionError", label + " connexion fermée")

scenario("memory:", "alexdb")
if db.sqlite_available():
    scenario("sqlite::memory:", "sqlite")
else:
    print("(SQLite absent : scénario sqlite ignoré)")

# moteur embarqué : SQL plus large
m := db.connect("memory:")
r := m.execute("SELECT 1 + 2 * 3, 'a' || 'b', NULL IS NULL, 7 / 2, COALESCE(NULL, 4), CASE WHEN 2 > 1 THEN 'oui' ELSE 'non' END, ABS(-3), UPPER('x'), LENGTH('abc'), SUBSTR('bonjour', 2, 3), ROUND(2.567, 1)")
t.eq(r.rows[0], [7, "ab", true, 3, 4, "oui", 3, "X", 3, "onj", 2.6], "expressions SQL")
m.executescript("CREATE TABLE t (a INT, b TEXT); INSERT INTO t VALUES (1, 'x'), (2, 'y'), (2, 'y'), (NULL, 'z');")
t.eq(m.execute("SELECT DISTINCT a, b FROM t ORDER BY a").rowcount, 3, "distinct")
t.eq(m.scalar("SELECT COUNT(a) FROM t"), 3, "count ignore null")
t.eq(m.scalar("SELECT COUNT(*) FROM t WHERE a = NULL"), 0, "logique trivaluée")
t.eq(m.execute("SELECT b, COUNT(*) AS n FROM t GROUP BY b HAVING COUNT(*) > 1").rows, [["y", 2]], "having")
t.eq(m.scalar("SELECT GROUP_CONCAT(b, '-') FROM t"), "x-y-y-z", "group_concat")
t.eq(m.execute("SELECT a FROM t WHERE a IN (SELECT a FROM t WHERE b = 'x')").rows, [[1]], "sous-requête IN")
t.eq(m.scalar("SELECT (SELECT MAX(a) FROM t) + 1"), 3, "sous-requête scalaire")
t.eq(m.execute("SELECT a FROM t WHERE a IS NOT NULL ORDER BY a DESC LIMIT 1 OFFSET 1").rows, [[2]], "limit offset")

t.raises(() => m.execute("CREATE UNIQUE INDEX ix ON t (b)"), "IntegrityError", "index unique sur doublons")
m.execute("CREATE TABLE u (k TEXT, v INT, PRIMARY KEY (k))")
m.execute("INSERT INTO u VALUES ('a', 1)")
t.raises(() => m.execute("INSERT INTO u VALUES ('a', 2)"), "IntegrityError", "clé primaire composite/texte")
m.execute("DROP TABLE u")
t.check(not m.has_table("u"), "drop table")
t.eq(rs.ResultSet(["x"], [[1], [2]]).to_table(), "x\n-\n1\n2", "to_table")

# persistance JSON
path := "/tmp/alex_test_db_" + str(os.pid()) + ".json"
with db.connect("alexdb:" + path) as p1:
    p1.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, texte TEXT)")
    p1.insert("notes", {"texte": "bonjour"})
    p1.begin()
    p1.insert("notes", {"texte": "non validé"})
t.check(os.exists(path), "fichier créé")
p2 := db.connect(path)
t.eq(p2.query("SELECT texte FROM notes"), [{"texte": "bonjour"}], "persistance (transaction non validée perdue)")
t.eq(p2.insert("notes", {"texte": "deux"}), 2, "identifiant continué")
p2.close()
os.remove(path)

# pool + bases partagées
pool := dp.DatabasePool("memory:partagee", 2)
a := pool.acquire()
a.execute("CREATE TABLE IF NOT EXISTS k (v INT)")
a.execute("INSERT INTO k VALUES (5)")
b := pool.acquire()
t.eq(b.scalar("SELECT v FROM k"), 5, "base partagée")
t.raises(() => pool.acquire(), "PoolError", "pool épuisé")
pool.release(a)
t.raises(() => pool.release(a), "PoolError", "rendue deux fois")
b.begin()
pool.release(b)
t.check(not b.in_transaction(), "transaction annulée au retour")
with pool.connection() as cx:
    t.eq(cx.scalar("SELECT COUNT(*) FROM k"), 1, "lease")
st := pool.stats()
t.eq(st["created"], 2, "créées")
t.eq(st["in_use"], 0, "toutes rendues")
pool.close()
t.raises(() => pool.acquire(), "PoolError", "pool fermé")
dc.drop_shared("partagee")

# divers
t.raises(() => db.connect("ftp://x"), "ConnectionError", "URL inconnue")
t.eq(dc.quote_identifier("ma table"), "\"ma table\"", "quote_identifier")
t.eq(dc.quote_identifier("select"), "\"select\"", "quote mot-clé")
t.eq(dc.quote_literal("l'eau"), "'l''eau'", "quote_literal")
t.check(dbe.is_database_error("IntegrityError"), "is_database_error")
t.eq(dbe.from_sqlite_code(2067), "IntegrityError", "code sqlite étendu")
t.check("alexdb" in db.backends(), "backends")
t.eq(db.run_script("memory:", "CREATE TABLE z (x INT); INSERT INTO z VALUES (1); SELECT x FROM z;").rows, [[1]], "run_script")
src := db.connect("memory:")
src.executescript("CREATE TABLE a (id INTEGER PRIMARY KEY, n TEXT); INSERT INTO a (n) VALUES ('p'), ('q');")
dst := db.connect("memory:")
t.eq(db.copy_tables(src, dst), 2, "copy_tables")
t.eq(dst.scalar("SELECT n FROM a WHERE id = 2"), "q", "copie lue")

t.summary("test_database2")

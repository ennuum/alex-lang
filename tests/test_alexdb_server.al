# ALEX - tests du pilote du serveur ALEX DB (database._aqlp) contre un vrai serveur.
#   ALEX_TEST_ALEXDB=alexdb://admin:mdp@127.0.0.1:5442/alexdb ./alex test tests/test_alexdb_server.al
# L'URL est celle d'un super-utilisateur sur la base d'administration : le test crée et supprime sa base
# alex_t_pilote. Sans ALEX_TEST_ALEXDB, seuls les tests sans serveur tournent.
use os
use database.database as dbm
use database.connection as dc
use database._aqlp as aq
use database.async_database as adb
use database.transaction as dtx
from testing use assert_eq, assert_true, assert_null, assert_contains

func url():
    return os.getenv("ALEX_TEST_ALEXDB")

func base():
    adm := dbm.connect(url())
    adm.execute("DROP DATABASE IF EXISTS alex_t_pilote")
    adm.execute("CREATE DATABASE alex_t_pilote")
    adm.close()
    p := aq.parse_url(url())
    return dbm.connect("alexdb://" + p["user"] + ":" + p["password"] + "@" + p["host"] + ":" + str(p["port"]) + "/alex_t_pilote")

func test_url():
    p := aq.parse_url("alexdb://al%40ice:p%3Ass@db.exemple:6543/ma%20base?connect_timeout=3&lock_timeout=0.5")
    assert_eq([p["user"], p["password"], p["host"], p["port"], p["database"], p["timeout"], p["lock_timeout"]], ["al@ice", "p:ss", "db.exemple", 6543, "ma base", 3.0, 0.5])
    q := aq.parse_url("alexdb://bob@[::1]")
    assert_eq([q["host"], q["port"], q["database"]], ["::1", 5442, "alexdb"])
    assert_eq(aq.redact("alexdb://u:secret@h:1/b"), "alexdb://u@h:1/b")
    assert_eq(dc.parse_url("alexdb://u@h/b")[0], "alexdb-server")
    assert_eq(dc.parse_url("alexdb:notes.json")[0], "alexdb")                 # moteur embarqué inchangé
    assert_true("alexdb-server" in dbm.backends())
    try:
        aq.parse_url("alexdb://h/b?sslmode=require")
        assert_true(false, "paramètre inconnu accepté")
    catch e:
        assert_eq(e.type, "ConnectionError")

func test_serveur_injoignable():
    try:
        dbm.connect("alexdb://a:b@127.0.0.1:1/x?connect_timeout=1")
        assert_true(false, "connexion acceptée")
    catch e:
        assert_eq(e.type, "ConnectionError")

func test_crud_identifiants_erreurs():
    if url() == null:
        return
    c := base()
    c.execute("CREATE TABLE alex_t_users (id INT PRIMARY KEY, nom TEXT NOT NULL UNIQUE, solde FLOAT, actif BOOL DEFAULT TRUE)")
    assert_eq(c.insert("alex_t_users", {"nom": "ana", "solde": 10}), 1)
    assert_eq(c.insert("alex_t_users", {"nom": "bob"}), 2)
    assert_eq(c.last_insert_id, 2)
    assert_eq(c.query_one("SELECT nom, solde, actif FROM alex_t_users WHERE id = ?", [1]), {"nom": "ana", "solde": 10.0, "actif": true})
    assert_eq(c.scalar("SELECT COUNT(*) FROM alex_t_users WHERE nom = :n", {"n": "bob"}), 1)
    assert_eq(c.update("alex_t_users", {"solde": 5.5}, "nom = ?", ["bob"]), 1)
    st := c.prepare("INSERT INTO alex_t_users (nom) VALUES (?)")
    assert_eq(st.execute_many([["cy"], ["di"]]), 2)
    st.close()
    assert_eq(c.delete("alex_t_users", "id > ?", [3]), 1)
    assert_eq(c.insert("alex_t_users", {"nom": "ed"}), 5)               # 4 supprimé : jamais réattribué
    try:
        c.insert("alex_t_users", {"nom": "ana"})
        assert_true(false, "doublon accepté")
    catch e:
        assert_eq(e.type, "IntegrityError")
        assert_contains(e.message, "ConstraintError")
    try:
        c.execute("SELECT * FROM absente")
        assert_true(false, "table inconnue acceptée")
    catch e:
        assert_eq(e.type, "QueryError")
    assert_true(c.has_table("alex_t_users"))
    assert_eq([x["name"] for x in c.columns("alex_t_users")], ["id", "nom", "solde", "actif"])
    c.close()

func echouer(c):
    c.insert("alex_t_k", {"v": 2})
    raise("ValueError", "annule")

func test_transactions_et_verrous():
    if url() == null:
        return
    c := base()
    c.execute("CREATE TABLE alex_t_k (id INT PRIMARY KEY, v INT NOT NULL)")
    t := c.transaction().begin()
    c.insert("alex_t_k", {"v": 1})
    t.commit()
    assert_eq(c.scalar("SELECT COUNT(*) FROM alex_t_k"), 1)
    try:
        dtx.run(c, (k) => echouer(k))
    catch e:
        assert_eq(e.type, "ValueError")
    assert_eq(c.scalar("SELECT COUNT(*) FROM alex_t_k"), 1)
    assert_true(not c.in_transaction())
    # une autre connexion tient la table : réessai jusqu'à lock_timeout, puis LockError
    other := dbm.connect(c.url + "?lock_timeout=0.2")
    c.begin()
    c.insert("alex_t_k", {"v": 3})
    try:
        other.insert("alex_t_k", {"v": 4})
        assert_true(false, "verrou ignoré")
    catch e:
        assert_contains(e.message, "LockError")
    c.commit()
    assert_eq(other.insert("alex_t_k", {"v": 4}), 3)
    assert_true(other._impl.db.retries > 0)
    # bloc atomique en une requête
    r := c.batch([["INSERT INTO alex_t_k (v) VALUES (?)", [5]], ["UPDATE alex_t_k SET v = v * ? WHERE id = ?", [10, 4]]])
    assert_eq(r, [{"rowcount": 1, "lastrowid": 4}, {"rowcount": 1, "lastrowid": null}])
    assert_eq(c.scalar("SELECT v FROM alex_t_k WHERE id = 4"), 50)
    try:
        c.batch([["INSERT INTO alex_t_k (v) VALUES (?)", [6]], ["INSERT INTO alex_t_k (v) VALUES (NULL)", null]])
        assert_true(false, "bloc invalide accepté")
    catch e:
        assert_eq(e.type, "IntegrityError")
    assert_eq(c.scalar("SELECT COUNT(*) FROM alex_t_k"), 4)
    c.close()
    other.close()

async func test_async():
    if url() == null:
        return
    c := base()
    u := c.url
    c.close()
    db := adb.open(u)
    await db.script("CREATE TABLE alex_t_a (id INT PRIMARY KEY, t TEXT); CREATE INDEX alex_t_a_t ON alex_t_a (t)")
    assert_eq(await db.insert("alex_t_a", {"t": "x"}), 1)
    r := await db.transaction([["INSERT INTO alex_t_a (t) VALUES (?)", ["y"]], ["DELETE FROM alex_t_a WHERE t = ?", ["x"]]])
    assert_eq(r, [{"rowcount": 1, "lastrowid": 2}, {"rowcount": 1, "lastrowid": null}])
    assert_eq(await db.query("SELECT id, t FROM alex_t_a"), [{"id": 2, "t": "y"}])
    await db.close()

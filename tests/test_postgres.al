# ALEX - tests du pilote PostgreSQL (database._postgres) contre un vrai serveur.
#   ALEX_TEST_POSTGRES=postgres://postgres:mdp@127.0.0.1:5432/base ./alex test tests/test_postgres.al
# Facultatifs : ALEX_TEST_POSTGRES_MD5 (utilisateur en md5), ALEX_TEST_POSTGRES_TRUST (sans mot de passe).
# Sans ALEX_TEST_POSTGRES, les tests sont ignorés (aucun serveur).
use os
use string as s
use database.database as dbm
use database._postgres as pg
use database.async_database as adb
from collections use append
from testing use assert_eq, assert_true, assert_null, assert_contains

func url(var="ALEX_TEST_POSTGRES"):
    return os.getenv(var)

func ouvrir():
    c := dbm.connect(url())
    c.executescript("DROP TABLE IF EXISTS alex_t_items; DROP TABLE IF EXISTS alex_t_users")
    c.execute("CREATE TABLE alex_t_users (id BIGSERIAL PRIMARY KEY, nom TEXT NOT NULL UNIQUE, actif BOOLEAN NOT NULL DEFAULT TRUE, solde NUMERIC(10,2), cree TIMESTAMPTZ DEFAULT now(), data JSONB)")
    return c

func test_url():
    p := pg.parse_url("postgresql://al%40ice:p%3Ass@db.exemple:6543/ma%20base?sslmode=require&connect_timeout=3")
    assert_eq([p["user"], p["password"], p["host"], p["port"], p["database"], p["sslmode"], p["timeout"]], ["al@ice", "p:ss", "db.exemple", 6543, "ma base", "require", 3.0])
    q := pg.parse_url("postgres://bob@[::1]/")
    assert_eq([q["host"], q["port"], q["database"]], ["::1", 5432, "bob"])

func test_reperes():
    assert_eq(pg.convert_placeholders("SELECT ? , '?' , \"a?\" , x::int -- ?\n , ?", [1, 2]), ["SELECT $1 , '?' , \"a?\" , x::int -- ?\n , $2", [1, 2]])
    assert_eq(pg.convert_placeholders("WHERE a = :v OR b = :v AND c = :w", {"v": 1, "w": 2}), ["WHERE a = $1 OR b = $1 AND c = $2", [1, 2]])
    assert_eq(pg.convert_placeholders("WHERE a = $1", [5]), ["WHERE a = $1", [5]])

func test_authentifications():
    if url() == null:
        return
    for var in ["ALEX_TEST_POSTGRES", "ALEX_TEST_POSTGRES_MD5", "ALEX_TEST_POSTGRES_TRUST"]:
        if url(var) != null:
            c := dbm.connect(url(var))
            assert_eq(c.scalar("SELECT 1 + 1"), 2)
            c.close()
    mauvais := s.replace(url(), ":" + pg.parse_url(url())["password"] + "@", ":faux@")
    try:
        dbm.connect(mauvais)
        assert_true(false, "connexion avec un mauvais mot de passe acceptée")
    catch e:
        assert_eq(e.type, "ConnectionError")
        assert_contains(e.message, "28P01")

func test_types_et_parametres():
    if url() == null:
        return
    c := dbm.connect(url())
    r := c.query_one("SELECT ?::int AS i, ?::float8 AS f, ?::bool AS b, ?::text AS t, NULL AS z, 12.50::numeric AS n, '{\"a\":1}'::jsonb AS j, ?::text IS NULL AS vide", [7, 2.5, true, "été ' \" ?", null])
    assert_eq(r, {"i": 7, "f": 2.5, "b": true, "t": "été ' \" ?", "z": null, "n": 12.5, "j": "{\"a\": 1}", "vide": true})
    assert_eq(c.scalar("SELECT :a::int * :a::int", {"a": 9}), 81)
    c.close()

func test_crud_transactions_erreurs():
    if url() == null:
        return
    c := ouvrir()
    id := c.insert("alex_t_users", {"nom": "awa", "solde": 10.5})
    assert_true(id >= 1)
    id2 := c.insert("alex_t_users", {"nom": "kofi"})
    assert_eq(id2, id + 1)
    assert_eq(c.update("alex_t_users", {"actif": false}, "id = ?", [id2]), 1)
    assert_eq(c.query("SELECT nom, actif, solde FROM alex_t_users ORDER BY id"), [{"nom": "awa", "actif": true, "solde": 10.5}, {"nom": "kofi", "actif": false, "solde": null}])
    try:
        c.insert("alex_t_users", {"nom": "awa"})
        assert_true(false, "doublon accepté")
    catch e:
        assert_eq(e.type, "IntegrityError")
        assert_contains(e.message, "23505")
    c.begin()
    assert_true(c.in_transaction())
    c.insert("alex_t_users", {"nom": "temporaire"})
    c.rollback()
    assert_true(not c.in_transaction())
    assert_eq(c.scalar("SELECT COUNT(*) FROM alex_t_users"), 2)
    c.begin()
    try:
        c.execute("SELECT * FROM table_absente")
    catch e:
        assert_eq(e.type, "QueryError")
        assert_contains(e.message, "42P01")
    assert_true(c.in_transaction())                  # transaction en échec : ROLLBACK requis
    c.rollback()
    assert_eq(c.scalar("SELECT 1"), 1)               # la connexion reste utilisable
    assert_eq(c.delete("alex_t_users", "nom = ?", ["kofi"]), 1)
    c.close()

func test_script_tables_colonnes_volume():
    if url() == null:
        return
    c := ouvrir()
    c.executescript("CREATE TABLE alex_t_items (id SERIAL PRIMARY KEY, v TEXT); INSERT INTO alex_t_items (v) SELECT 'élément ' || g FROM generate_series(1, 2000) g")
    assert_true("alex_t_items" in c.tables())
    cols := c.columns("alex_t_users")
    assert_eq(cols[0]["name"], "id")
    assert_true(cols[0]["primary"])
    rows := c.query("SELECT id, v FROM alex_t_items ORDER BY id")
    assert_eq(len(rows), 2000)
    assert_eq(rows[1999]["v"], "élément 2000")
    st := c.prepare("INSERT INTO alex_t_items (v) VALUES (?)")
    assert_eq(st.execute_many([["a"], ["b"], ["c"]]), 3)
    assert_eq(c.scalar("SELECT COUNT(*) FROM alex_t_items"), 2003)
    c.executescript("DROP TABLE alex_t_items; DROP TABLE alex_t_users")
    c.close()

async func test_async_database():
    if url() == null:
        return
    db := adb.open(url())
    await db.script("DROP TABLE IF EXISTS alex_t_async; CREATE TABLE alex_t_async (id BIGSERIAL PRIMARY KEY, nom TEXT UNIQUE)")
    a := await db.insert("alex_t_async", {"nom": "un"})
    res := await db.transaction([["INSERT INTO alex_t_async (nom) VALUES (?)", ["deux"]], ["INSERT INTO alex_t_async (nom) VALUES (?)", ["trois"]]])
    assert_eq(len(res), 2)
    try:
        await db.transaction([["INSERT INTO alex_t_async (nom) VALUES (?)", ["quatre"]], ["INSERT INTO alex_t_async (nom) VALUES (?)", ["un"]]])
        assert_true(false, "erreur attendue")
    catch e:
        assert_contains(e.message, "23505")
    assert_eq(await db.scalar("SELECT COUNT(*) FROM alex_t_async"), 3)
    assert_eq((await db.query_one("SELECT nom FROM alex_t_async WHERE id = ?", [a]))["nom"], "un")
    await db.script("DROP TABLE alex_t_async")
    await db.close()

# ALEX_TEST_POSTGRES_TLS=1 : le serveur accepte TLS (ssl = on) avec un certificat auto-signé.
func test_tls():
    if url() == null or os.getenv("ALEX_TEST_POSTGRES_TLS") == null:
        return
    c := dbm.connect(url() + ("&" if s.contains(url(), "?") else "?") + "sslmode=require")
    assert_eq(c.scalar("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()"), true)
    c.close()
    try:
        dbm.connect(url() + ("&" if s.contains(url(), "?") else "?") + "sslmode=verify-full")
        assert_true(false, "certificat auto-signé accepté en verify-full")
    catch e:
        assert_contains(e.message, "certificate verify failed")

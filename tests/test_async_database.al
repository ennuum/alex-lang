# ALEX - tests de database.async_database : requêtes attendues avec await, exécutées dans le fil de la base.
#   ./alex test tests/test_async_database.al
use os
use time
use asyncio as aio
use database.database as dbm
use database.async_database as adb
from testing use assert_eq, assert_true, assert_null, assert_contains

func sqlite_url():
    return "sqlite:" + os.join(os.tmp_dir(), "alex_adb_" + str(os.pid()) + ".db")

async func test_crud_alexdb_memoire():
    db := adb.open("memory:")
    await db.script("CREATE TABLE notes (id INTEGER PRIMARY KEY, titre TEXT)")
    a := await db.insert("notes", {"titre": "Été"})
    b := await db.insert("notes", {"titre": "Hiver"})
    assert_true(b > a)
    assert_eq(await db.scalar("SELECT COUNT(*) FROM notes"), 2)
    assert_eq((await db.query_one("SELECT titre FROM notes WHERE id = ?", [a]))["titre"], "Été")
    assert_null(await db.query_one("SELECT titre FROM notes WHERE id = ?", [999]))
    rows := await db.query("SELECT id, titre FROM notes ORDER BY id")
    assert_eq(len(rows), 2)
    r := await db.execute("UPDATE notes SET titre = ? WHERE id = ?", ["Printemps", a])
    assert_eq(r["rowcount"], 1)
    await db.close()

async func test_sqlite_transaction_et_erreurs():
    if not ("sqlite" in dbm.backends()):
        return
    url := sqlite_url()
    db := adb.open(url)
    await db.script("CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT UNIQUE)")
    res := await db.transaction([["INSERT INTO t (v) VALUES (?)", ["a"]], ["INSERT INTO t (v) VALUES (?)", ["b"]]])
    assert_eq(len(res), 2)
    assert_eq(await db.scalar("SELECT COUNT(*) FROM t"), 2)
    # violation d'unicité au milieu : rien n'est gardé, l'erreur est relancée
    erreur := null
    try:
        await db.transaction([["INSERT INTO t (v) VALUES (?)", ["c"]], ["INSERT INTO t (v) VALUES (?)", ["a"]]])
    catch e:
        erreur = e
    assert_true(erreur != null)
    assert_eq(await db.scalar("SELECT COUNT(*) FROM t WHERE v = 'c'"), 0)
    # erreur de syntaxe : type conservé
    try:
        await db.query("SELEC nimporte quoi")
        assert_true(false, "erreur attendue")
    catch e:
        assert_contains(e.message, "offload")
    await db.close()
    os.remove(os.join(os.tmp_dir(), "alex_adb_" + str(os.pid()) + ".db"))

async func test_base_fermee():
    db := adb.open("memory:")
    await db.close()
    try:
        await db.query("SELECT 1")
        assert_true(false, "erreur attendue")
    catch e:
        assert_eq(e.type, "ConnectionError")

async func tic(compteur, duree):
    t0 := time.monotonic()
    while time.monotonic() - t0 < duree:
        await aio.sleep(0.01)
        compteur[0] = compteur[0] + 1

async func test_requete_longue_ne_bloque_pas():
    if not ("sqlite" in dbm.backends()):
        return
    db := adb.open("sqlite::memory:")
    compteur := [0]
    ticker := tic(compteur, 10.0)
    t0 := time.monotonic()
    n := await db.scalar("WITH RECURSIVE c(x) AS (SELECT 1 UNION ALL SELECT x + 1 FROM c WHERE x < 3000000) SELECT COUNT(*) FROM c")
    dt := time.monotonic() - t0
    aio.cancel(ticker)
    assert_eq(n, 3000000)
    # pendant la requête, la boucle a continué : environ une impulsion toutes les 10 ms
    assert_true(dt > 0.2, "requête trop courte pour la mesure : " + str(dt))
    assert_true(compteur[0] >= dt / 0.01 * 0.5, "impulsions : " + str(compteur[0]) + " en " + str(dt) + " s")
    await db.close()

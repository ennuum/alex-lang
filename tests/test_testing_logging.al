# ALEX - tests des modules testing et logging (ALEX pur). Lancer depuis la racine : ./alex run tests/test_testing_logging.al
use testing
use logging
use io
use os
from core use len
from collections use append
from testing use assert_eq, assert_true, assert_raises, assert_near, assert_contains, assert_ne, assert_null, assert_not_null, assert_false

# --- testing : les assertions lèvent bien AssertionError -------------------------------------------------------
func t_assertions():
    assert_raises(() => testing.assert_true(false), "AssertionError", "true attendu")
    assert_raises(() => testing.assert_true(1), "AssertionError")
    assert_raises(() => testing.assert_false(true), "AssertionError")
    assert_raises(() => testing.assert_eq(1, 2), "AssertionError", "obtenu 1, attendu 2")
    assert_raises(() => testing.assert_eq("a", "b", "ctx"), "AssertionError", "ctx")
    assert_raises(() => testing.assert_ne(1, 1), "AssertionError", "égales")
    assert_raises(() => testing.assert_null(3), "AssertionError")
    assert_raises(() => testing.assert_not_null(null), "AssertionError")
    assert_raises(() => testing.assert_near(1.0, 1.1, 0.01), "AssertionError", "proche")
    assert_raises(() => testing.assert_contains([1, 2], 3), "AssertionError", "contient")
    assert_raises(() => testing.fail("boum"), "AssertionError", "boum")
    testing.assert_near(1.0, 1.0000000001)
    testing.assert_near(5, 4, 1)
    testing.assert_contains("abc", "b")
    testing.assert_contains([1, 2], 2)
    testing.assert_contains({"k": 1}, "k")
    testing.assert_eq([1, [2, "x"]], [1, [2, "x"]])

func t_assert_raises():
    e := testing.assert_raises(() => 1 / 0, "ZeroDivisionError")
    assert_eq(e.type, "ZeroDivisionError")
    assert_raises(() => testing.assert_raises(() => 1, "ValueError"), "AssertionError", "aucune levée")
    assert_raises(() => testing.assert_raises(() => 1 / 0, "ValueError"), "AssertionError", "ZeroDivisionError")
    assert_raises(() => testing.assert_raises(() => 1 / 0, null, "zzz"), "AssertionError", "ne contient pas")

# --- testing : exécuteur ------------------------------------------------------------------------------------
func t_runner():
    log := []
    func ok():
        append(log, "ok")
    func ko():
        testing.assert_eq(1, 2)
    func boom():
        1 / 0
    n := testing.run_tests([["a", ok], ["b", ko], ["c", boom], ["d", ok, "raison"]], false)
    assert_eq(n, 2)
    s := testing.summary()
    assert_eq(s["passed"], 1)
    assert_eq(s["failed"], 1)
    assert_eq(s["errors"], 1)
    assert_eq(s["skipped"], 1)
    assert_eq(s["total"], 4)
    assert_eq(log, ["ok"])

func t_fixtures():
    log := []
    testing.reset()
    testing.before_each(() => append(log, "b"))
    testing.after_each(() => append(log, "a"))
    testing.test("un", () => append(log, "1"))
    testing.test("deux", () => append(log, "2"))
    testing.skip("trois", () => append(log, "3"), "non")
    n := testing.run(false)
    assert_eq(n, 0)
    assert_eq(log, ["b", "1", "a", "b", "2", "a"])
    log2 := []
    testing.reset()
    testing.test("alpha", () => append(log2, "alpha"))
    testing.test("beta", () => append(log2, "beta"))
    testing.run(false, "alp")
    assert_eq(log2, ["alpha"])
    testing.reset()
    testing.before_each(() => 1 / 0)
    testing.test("x", () => null)
    assert_eq(testing.run(false), 1)
    assert_eq(testing.summary()["errors"], 1)
    testing.reset()
    assert_raises(() => testing.test(1, () => null), "TypeError")

# --- logging --------------------------------------------------------------------------------------------------
func fresh():
    logging.reset()
    logging.set_clock(() => 1759786200)
    logging.clear_handlers()
    lines := []
    logging.add_handler((line, rec) => append(lines, line))
    return lines

func t_logging_base():
    lines := fresh()
    logging.info("démarrage")
    logging.debug("caché")
    logging.warning("attention")
    assert_eq(lines, ["2025-10-06 21:30:00 INFO     root: démarrage", "2025-10-06 21:30:00 WARNING  root: attention"])
    logging.set_level("DEBUG")
    logging.debug("visible")
    logging.error("e")
    logging.critical("c")
    assert_eq(len(lines), 5)
    assert_eq(lines[2], "2025-10-06 21:30:00 DEBUG    root: visible")
    assert_eq(lines[4], "2025-10-06 21:30:00 CRITICAL root: c")
    logging.set_level("error")
    logging.warning("non")
    assert_eq(len(lines), 5)
    logging.set_level(10)
    assert_eq(logging.get_level(), 10)
    logging.log("INFO", "via log")
    assert_eq(len(lines), 6)
    logging.info(42)
    assert_contains(lines[6], "root: 42")

func t_loggers():
    lines := fresh()
    db := logging.get_logger("db")
    assert_true(db == logging.get_logger("db"))
    db.info("a")
    assert_contains(lines[0], "INFO     db: a")
    db.set_level("ERROR")
    db.warning("masqué")
    assert_eq(len(lines), 1)
    assert_false(db.enabled("warning"))
    assert_true(db.enabled("error"))
    logging.set_level("DEBUG")
    app := logging.get_logger("app")
    sub := logging.get_logger("app.db")
    app.set_level("WARNING")
    sub.info("masqué par le parent")
    sub.error("passe")
    assert_eq(len(lines), 2)
    assert_contains(lines[1], "ERROR    app.db: passe")
    other := logging.get_logger("zzz")
    other.debug("hérite du racine")
    assert_eq(len(lines), 3)

func t_format_horloge():
    lines := fresh()
    logging.set_format("[{level}] {name}/{message} @{time}")
    logging.info("x")
    assert_eq(lines[0], "[INFO    ] root/x @2025-10-06 21:30:00")
    assert_eq(logging.format_time(0), "1970-01-01 00:00:00")
    assert_eq(logging.format_time(951782400), "2000-02-29 00:00:00")
    assert_eq(logging.format_time(1709164800 + 86399), "2024-02-29 23:59:59")
    assert_eq(logging.format_time(4102444800), "2100-01-01 00:00:00")
    assert_eq(logging.format_time(1.9), "1970-01-01 00:00:01")

func t_record_handler():
    logging.reset()
    logging.set_clock(() => 0)
    logging.clear_handlers()
    got := []
    logging.add_handler((line, rec) => append(got, rec))
    logging.get_logger("n").warning("m")
    assert_eq(got[0]["name"], "n")
    assert_eq(got[0]["level"], "WARNING")
    assert_eq(got[0]["levelno"], 30)
    assert_eq(got[0]["message"], "m")

func t_fichier_erreurs():
    p := os.join(os.tmp_dir(), "alex_test_log_" + str(os.pid()) + ".log")
    if io.file_exists(p):
        io.delete_file(p)
    logging.reset()
    logging.set_clock(() => 0)
    logging.clear_handlers()
    logging.add_file(p)
    logging.info("un")
    logging.error("deux")
    assert_eq(io.read_file(p), "1970-01-01 00:00:00 INFO     root: un\n1970-01-01 00:00:00 ERROR    root: deux\n")
    io.delete_file(p)
    assert_raises(() => logging.set_level("NOPE"), "ValueError")
    assert_raises(() => logging.set_level(1.5), "TypeError")
    assert_raises(() => logging.get_logger(""), "TypeError")
    assert_raises(() => logging.add_handler(5), "TypeError")
    logging.reset()

testing.test("assertions", t_assertions)
testing.test("assert_raises", t_assert_raises)
testing.test("exécuteur", t_runner)
testing.test("fixtures et filtre", t_fixtures)
testing.test("logging : base", t_logging_base)
testing.test("logging : loggers et héritage", t_loggers)
testing.test("logging : format et horloge", t_format_horloge)
testing.test("logging : record", t_record_handler)
testing.test("logging : fichier et erreurs", t_fichier_erreurs)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) en échec")
print("TESTING/LOGGING: OK")

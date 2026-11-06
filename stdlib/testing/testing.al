# ALEX STANDARD LIBRARY — testing
# Petit framework de tests unitaires en ALEX pur.
#
#   use testing
#   testing.test("addition", () => testing.assert_eq(1 + 1, 2))
#   testing.test("division", func():
#       testing.assert_raises(() => 1 / 0, "ZeroDivisionError"))      # (corps de lambda = expression)
#   testing.skip("plus tard", () => null, "pas encore prêt")
#   failed := testing.run()          # affiche un rapport ; renvoie le nombre d'échecs + erreurs
#
# ASSERTIONS (lèvent AssertionError avec un message lisible ; `msg` optionnel s'ajoute au message)
#   assert_true(cond, msg)   assert_false(cond, msg)   assert_eq(actual, expected, msg)   assert_ne(a, b, msg)
#   assert_null(x, msg)      assert_not_null(x, msg)   assert_near(a, b, eps, msg)   assert_contains(conteneur, x, msg)
#   assert_raises(fn, kind, fragment) -> l'exception : fn() doit lever ; si `kind` est donné, e.type == kind ;
#                                         si `fragment` est donné, e.message doit le contenir.
#   fail(msg)
# ENREGISTREMENT ET EXÉCUTION
#   test(name, fn)            enregistre un test (fn sans argument)
#   skip(name, fn, reason)    enregistre un test ignoré
#   before_each(fn) / after_each(fn)   fixtures exécutées autour de chaque test (before_each échoue => test en erreur)
#   run(verbose, only)        exécute les tests enregistrés ; `only` = fragment du nom à filtrer ; renvoie le nombre
#                             d'échecs et d'erreurs. Échec = AssertionError ; erreur = toute autre exception.
#   run_tests(list)           variante sans registre global : liste de paires (nom, fn).
#   run_async(verbose, only) / run_tests_async(list)   idem, et attend les tests `async func` (await) ; à appeler
#                             avec await. `alexc test` l'utilise tout seul dès qu'un fichier contient « async func test_ ».
#   reset()                   vide le registre.
#   summary()                 dict {"passed","failed","errors","skipped","total"} du dernier run.
# Sortie : une ligne [OK] / [ÉCHEC] / [ERREUR] / [IGNORÉ] par test, puis un résumé.
# Avec la variable d'environnement ALEX_TEST_REPORT=1 (posée par `alexc test`), chaque résultat est aussi écrit
# sous la forme d'une ligne « @@ALEXTEST {json} » lue par l'exécuteur de tests et par ALEX Studio.

from core use len, type
from collections use append, clear, contains_key
use string
use os
use json
use asyncio as _aio

_state := {"tests": [], "before": [], "after": [], "last": {"passed": 0, "failed": 0, "errors": 0, "skipped": 0, "total": 0}}

func _show(v):
    if type(v) == "str":
        return "\"" + v + "\""
    return str(v)

func _fail_with(message, msg):
    if msg != null:
        message = message + " — " + msg
    raise("AssertionError", message)

func fail(msg=null):
    _fail_with("échec explicite", msg)

func assert_true(cond, msg=null):
    if cond != true:
        _fail_with("true attendu, obtenu " + _show(cond), msg)

func assert_false(cond, msg=null):
    if cond != false:
        _fail_with("false attendu, obtenu " + _show(cond), msg)

func assert_eq(actual, expected, msg=null):
    if actual != expected:
        _fail_with("obtenu " + _show(actual) + ", attendu " + _show(expected), msg)

func assert_ne(a, b, msg=null):
    if a == b:
        _fail_with("les deux valeurs sont égales : " + _show(a), msg)

func assert_null(x, msg=null):
    if x != null:
        _fail_with("null attendu, obtenu " + _show(x), msg)

func assert_not_null(x, msg=null):
    if x == null:
        _fail_with("une valeur non nulle était attendue", msg)

# |a - b| <= eps (défaut 1e-9).
func assert_near(a, b, eps=null, msg=null):
    e := eps
    if e == null:
        e = 0.000000001
    d := a - b
    if d < 0:
        d = -d
    if d > e:
        _fail_with(_show(a) + " n'est pas proche de " + _show(b) + " (écart " + str(d) + " > " + str(e) + ")", msg)

# Conteneur : str (sous-chaîne), list/tuple (élément) ou dict (clé).
func assert_contains(container, x, msg=null):
    found := false
    t := type(container)
    if t == "str":
        found = string.contains(container, x)
    elif t == "dict":
        found = contains_key(container, x)
    else:
        for item in container:
            if item == x:
                found = true
                break
    if not found:
        _fail_with(_show(container) + " ne contient pas " + _show(x), msg)

# fn() doit lever une exception ; renvoie celle-ci.
func assert_raises(fn, kind=null, fragment=null):
    caught := null
    try:
        fn()
    catch e:
        caught = e
    if caught == null:
        _fail_with("une exception était attendue" + _kind_suffix(kind) + ", aucune levée", null)
    if kind != null and caught.type != kind:
        _fail_with("exception de type " + kind + " attendue, obtenu " + str(caught.type) + " (" + str(caught.message) + ")", null)
    if fragment != null and not string.contains(str(caught.message), fragment):
        _fail_with("le message " + _show(str(caught.message)) + " ne contient pas " + _show(fragment), null)
    return caught

func _kind_suffix(kind):
    if kind == null:
        return ""
    return " (" + kind + ")"

# --- registre ----------------------------------------------------------------------------------------------

func test(name, fn):
    if type(name) != "str" or type(fn) != "function":
        raise("TypeError", "testing.test(name, fn) : une str et une fonction sont attendues")
    append(_state["tests"], [name, fn, null])

func skip(name, fn, reason=null):
    if type(name) != "str":
        raise("TypeError", "testing.skip : nom str attendu")
    r := reason
    if r == null:
        r = "ignoré"
    append(_state["tests"], [name, fn, r])

func before_each(fn):
    append(_state["before"], fn)

func after_each(fn):
    append(_state["after"], fn)

func reset():
    _state["tests"] = []
    _state["before"] = []
    _state["after"] = []

func summary():
    s := _state["last"]
    return {"passed": s["passed"], "failed": s["failed"], "errors": s["errors"], "skipped": s["skipped"], "total": s["total"]}

# --- exécution ---------------------------------------------------------------------------------------------

func _run_one(fn):
    err := null
    for hook in _state["before"]:
        try:
            hook()
        catch e:
            err = ["ERREUR", "before_each : " + str(e.type) + " : " + str(e.message)]
            break
    if err == null:
        try:
            r := fn()
            if _aio.is_future(r):
                _aio.cancel(r)
                raise("TestError", "test async : lancer avec await testing.run_async() (alexc test le fait tout seul)")
        catch e:
            err = _classify(e)
    for hook in _state["after"]:
        try:
            hook()
        catch e:
            if err == null:
                err = ["ERREUR", "after_each : " + str(e.type) + " : " + str(e.message)]
    return err

# Comme _run_one, en attendant le test (et les fixtures) s'ils rendent une tâche.
async func _run_one_async(fn):
    err := null
    for hook in _state["before"]:
        try:
            h := hook()
            if _aio.is_future(h):
                await h
        catch e:
            err = ["ERREUR", "before_each : " + str(e.type) + " : " + str(e.message)]
            break
    if err == null:
        try:
            r := fn()
            if _aio.is_future(r):
                await r
        catch e:
            err = _classify(e)
    for hook in _state["after"]:
        try:
            h := hook()
            if _aio.is_future(h):
                await h
        catch e:
            if err == null:
                err = ["ERREUR", "after_each : " + str(e.type) + " : " + str(e.message)]
    return err

func _classify(e):
    if e.type == "AssertionError":
        return ["ÉCHEC", str(e.message)]
    return ["ERREUR", str(e.type) + " : " + str(e.message)]

func _report(name, status, message, duration):
    if os.getenv("ALEX_TEST_REPORT") == "1":
        print("@@ALEXTEST " + json.stringify({"name": name, "status": status, "message": message, "duration": duration}))

# Exécute une liste de [nom, fn] ou [nom, fn, raison_skip] ; renvoie le nombre d'échecs + erreurs.
func run_tests(tests, verbose=true):
    acc := _new_acc()
    for t in tests:
        if _skipped(acc, t, verbose):
            continue
        t1 := os.monotonic_time()
        res := _run_one(t[1])
        _record(acc, t[0], res, os.monotonic_time() - t1, verbose)
    return _finish(acc, verbose)

# Variante async : les tests `async func` sont attendus. À appeler avec await.
async func run_tests_async(tests, verbose=true):
    acc := _new_acc()
    for t in tests:
        if _skipped(acc, t, verbose):
            continue
        t1 := os.monotonic_time()
        res := await _run_one_async(t[1])
        _record(acc, t[0], res, os.monotonic_time() - t1, verbose)
    return _finish(acc, verbose)

func _new_acc():
    return {"passed": 0, "failed": 0, "errors": 0, "skipped": 0, "problems": [], "t0": os.monotonic_time()}

func _skipped(acc, t, verbose):
    if len(t) > 2 and t[2] != null:
        acc["skipped"] = acc["skipped"] + 1
        if verbose:
            print("  [IGNORÉ]  " + t[0] + " (" + t[2] + ")")
        _report(t[0], "skipped", t[2], 0.0)
        return true
    return false

func _record(acc, name, res, dt1, verbose):
    if res == null:
        acc["passed"] = acc["passed"] + 1
        if verbose:
            print("  [OK]      " + name)
        _report(name, "passed", "", dt1)
        return
    if res[0] == "ÉCHEC":
        acc["failed"] = acc["failed"] + 1
        _report(name, "failed", res[1], dt1)
    else:
        acc["errors"] = acc["errors"] + 1
        _report(name, "error", res[1], dt1)
    append(acc["problems"], [name, res])
    if verbose:
        print("  [" + res[0] + "]  " + name)
        print("      " + res[1])

func _finish(acc, verbose):
    dt := os.monotonic_time() - acc["t0"]
    passed := acc["passed"]
    failed := acc["failed"]
    errors := acc["errors"]
    skipped := acc["skipped"]
    total := passed + failed + errors + skipped
    _state["last"] = {"passed": passed, "failed": failed, "errors": errors, "skipped": skipped, "total": total}
    if verbose:
        line := str(passed) + " réussi(s), " + str(failed) + " échec(s), " + str(errors) + " erreur(s), " + str(skipped) + " ignoré(s) sur " + str(total) + " (" + str(dt) + " s)"
        print("")
        print(line)
    return failed + errors

# Exécute les tests enregistrés (filtrés par un fragment de nom). Renvoie le nombre d'échecs + erreurs.
func run(verbose=true, only=null):
    selected := []
    for t in _state["tests"]:
        if only == null or string.contains(t[0], only):
            append(selected, t)
    return run_tests(selected, verbose)

# Comme run, en attendant les tests async (await testing.run_async()).
async func run_async(verbose=true, only=null):
    selected := []
    for t in _state["tests"]:
        if only == null or string.contains(t[0], only):
            append(selected, t)
    return await run_tests_async(selected, verbose)

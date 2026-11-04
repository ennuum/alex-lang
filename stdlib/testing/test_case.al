# ALEX STANDARD LIBRARY — testing.test_case
#
# TestCase : tests regroupés en CLASSE, à la xUnit. Chaque méthode dont le nom commence par « test_ » est un
# test ; set_up() / tear_down() encadrent chacun d'eux, set_up_class() / tear_down_class() la classe entière.
# Les méthodes d'assertion (assert_equal, assert_raises...) délèguent à testing.assertions.
#
#   use testing.test_case as tc
#   from testing.test_case use TestCase
#   class PileTest extends TestCase:
#       func set_up():
#           self.pile = Stack()
#       func test_push():
#           self.pile.push(1)
#           self.assert_equal(self.pile.size(), 1)
#       func test_pop_vide():
#           self.assert_raises(() => self.pile.pop(), "EmptyCollectionError")
#       func test_plus_tard():
#           self.skip("pas encore écrit")
#   rapport := tc.run_case(PileTest())          # TestReport
#
# Les tests s'exécutent dans l'ordre alphabétique de leurs noms. Un test peut être marqué « lent » par la
# méthode tags() : {"test_x": ["lent"]} (filtrable par TestSuite / TestRunner).
# Erreurs : SkipTest (skip), AssertionError (assertions).

from core use len, type
from collections use append
use string as _s
use _native_reflect as _r
use reflection.method_info as _mi
use testing.assertions as _a
use testing.testing_errors as _e
use testing.test_runner as _tr

class TestCase:
    func set_up():
        return null

    func tear_down():
        return null

    func set_up_class():
        return null

    func tear_down_class():
        return null

    # {nom_de_test: [étiquettes]} (à redéfinir).
    func tags():
        return {}

    func case_name():
        return _r.display_name(_r.type_name(self))

    func skip(reason="ignoré"):
        _e.skip(reason)

    func fail(msg="échec explicite"):
        _e.fail(msg)

    func assert_equal(a, b, msg=null):
        _a.equal(a, b, msg)

    func assert_not_equal(a, b, msg=null):
        _a.not_equal(a, b, msg)

    func assert_true(c, msg=null):
        _a.is_true(c, msg)

    func assert_false(c, msg=null):
        _a.is_false(c, msg)

    func assert_null(v, msg=null):
        _a.is_null(v, msg)

    func assert_not_null(v, msg=null):
        _a.not_null(v, msg)

    func assert_almost_equal(a, b, rel_tol=0.000000001, msg=null):
        _a.almost_equal(a, b, rel_tol, 0.0, msg)

    func assert_raises(fn, kind=null, fragment=null):
        return _a.raises(fn, kind, fragment)

    func assert_contains(c, x, msg=null):
        _a.contains(c, x, msg)

    func assert_length(c, n, msg=null):
        _a.length(c, n, msg)

    func assert_instance_of(v, type_name, msg=null):
        _a.instance_of(v, type_name, msg)

    func assert_matches(text, pattern, msg=null):
        _a.matches(text, pattern, msg)

# Noms des tests d'une instance de TestCase (méthodes test_*), triés.
func test_names(case):
    out := []
    for n in _mi.names(case):
        if _s.starts_with(n, "test_"):
            append(out, n)
    i := 1
    while i < len(out):
        v := out[i]
        j := i - 1
        while j >= 0 and out[j] > v:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = v
        i += 1
    return out

# Exécute tous les tests d'une instance ; TestReport.
func run_case(case, only=null, verbose=false):
    return _tr.TestRunner(verbose).run_case(case, only)

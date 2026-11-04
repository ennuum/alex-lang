# Tests : testing.assertions, test_case, test_suite, test_runner, test_report, mock, benchmark, property_test.
from core use len, type
from collections use append
use check as t
use string
use testing.testing_errors as te
use testing.assertions as a
use testing.test_report as rep
use testing.test_suite as ts
use testing.test_runner as tr
use testing.test_case as tc
use testing.mock as mk
use testing.benchmark as bm
use testing.property_test as pt
from testing.test_case use TestCase

# assertions
t.raises(() => a.equal(1, 2), "AssertionError", "equal échoue")
a.equal([1, 2], [1, 2])
t.raises(() => a.almost_equal(1.0, 1.1), "AssertionError", "almost_equal")
a.almost_equal(0.1 + 0.2, 0.3)
a.raises(() => raise("ValueError", "x"), "ValueError")
t.raises(() => a.raises(() => 1, "ValueError"), "AssertionError", "raises sans erreur")
a.contains([1, 2, 3], 2)
a.same_items([3, 1, 2], [1, 2, 3])
a.dict_contains({"a": 1, "b": 2}, {"a": 1})
a.between(5, 1, 10)
a.starts_with("bonjour", "bon")
msg := ""
try:
    a.equal({"a": 1}, {"a": 2})
catch e:
    msg = e.message
t.check(string.contains(msg, "a"), "explain_difference : " + msg)

# TestCase / runner
journal := []

class Exemple extends TestCase:
    func set_up():
        self.v = 10
    func tear_down():
        append(journal, "td")
    func test_ok():
        self.assert_equal(self.v, 10)
    func test_echec():
        self.assert_equal(self.v, 11)
    func test_erreur():
        raise("ValueError", "boum")
    func test_saute():
        self.skip("plus tard")
    func aide():
        return 1

r := tc.run_case(Exemple())
c := r.counts()
t.eq(c["passed"], 1, "passed")
t.eq(c["failed"], 1, "failed")
t.eq(c["errors"], 1, "errors")
t.eq(c["skipped"], 1, "skipped")
t.eq(len(journal), 4, "tear_down à chaque test")
t.check(not r.ok(), "rapport non ok")
t.eq(r.summary_line("x"), "x : 1 OK, 2 échecs", "summary_line")
t.eq(ts.test_methods(Exemple()), ["test_echec", "test_erreur", "test_ok", "test_saute"], "test_methods")
t.check(string.contains(r.to_junit(), "<testsuite"), "junit")
t.check(string.contains(r.to_json(), "passed"), "json")

s := ts.TestSuite("fonctions")
s.add("un", () => a.is_true(true))
s.add("deux", () => a.is_true(false), ["lent"])
s.add_case(Exemple())
t.eq(s.size(), 6, "suite size")
t.eq(s.filter(null, ["lent"]).size(), 5, "exclude tag")
r2 := tr.TestRunner(false, false, "un").run(s)
t.eq(r2.counts()["total"], 1, "pattern")
r3 := tr.TestRunner(false, true).run(s)
t.check(r3.counts()["total"] < 6, "fail_fast")
both := rep.TestReport("total")
both.merge(r)
both.merge(r2)
t.eq(both.counts()["total"], 5, "merge")

# mock
m := mk.Mock(42)
t.eq(m(1, 2), 42, "mock retour")
m("x")
m.assert_called_times(2)
m.assert_called_with(["x"])
m.assert_any_call([1, 2])
t.raises(() => m.assert_called_with([9]), "MockError", "assert_called_with")
seq := mk.Mock(null, [1, 2])
t.eq([seq(), seq()], [1, 2], "side_effect liste")
t.raises(() => seq(), "MockError", "side_effect épuisé")
t.raises(() => mk.Mock(null, null, ["IoError", "coupé"])(), "IoError", "raises")
sp := mk.spy((x) => x * 2)
t.eq(sp(4), 8, "spy")
t.eq(sp.calls, [[4]], "spy calls")

class Client:
    func init():
        self.base = "prod"
    func envoyer(x):
        return "réel " + x

cl := Client()
fake := mk.Mock("faux")
t.eq(mk.patch_method(cl, "envoyer", fake, () => cl.envoyer("a")), "faux", "patch_method")
t.eq(cl.envoyer("a"), "réel a", "restauré")
mk.patch(cl, "base", "test", () => t.eq(cl.base, "test", "patch champ"))
t.eq(cl.base, "prod", "champ restauré")
t.raises(() => mk.patch_method(cl, "absent", fake, () => 1), "AttributeError", "patch_method absent")
st := mk.Stub({"solde": 100, "debiter": (n) => n > 0})
t.eq(st.call("solde"), 100, "stub valeur")
t.check(st.call("debiter", 5), "stub fonction")
t.eq(st.calls_to("debiter"), [[5]], "stub log")

# benchmark
b := bm.run("somme", () => 1 + 1, 10, 2)
t.eq(b.runs, 10, "runs")
t.check(b.min <= b.median and b.median <= b.max, "ordre stats")
t.check(b.stddev >= 0, "stddev")
b2 := bm.run_for("vide", () => null, 0.05)
t.check(b2.runs >= 3, "run_for")
t.check(string.contains(bm.compare([b, b2]), "relatif"), "compare")
bench := bm.Benchmark().add("a", () => 1).add("b", () => 2).run(5)
t.check(bench.fastest() != null, "fastest")
t.eq(bm.format_duration(0.0025), "2.5 ms", "format_duration")
t.raises(() => bm.run("x", 3), "TypeError", "fonction attendue")

# property
pt.for_all([pt.integers(), pt.integers()], (x, y) => x + y == y + x, 100)
res := pt.check([pt.integers(0, 1000)], (n) => n < 100)
t.check(not res.ok, "contre-exemple trouvé")
t.eq(res.counterexample, [100], "réduction entier")
res2 := pt.check([pt.lists(pt.integers(0, 50))], (xs) => len(xs) < 3)
t.check(not res2.ok, "liste")
t.eq(len(res2.counterexample[0]), 3, "liste réduite à 3")
res3 := pt.check([pt.text(0, 10, "abc")], (s) => not string.contains(s, "c"), 200, 7)
t.eq(res3.counterexample, ["c"], "texte réduit")
t.raises(() => pt.for_all([pt.booleans()], (bo) => bo), "PropertyError", "for_all lève")
d := pt.check([pt.dicts(pt.text(1, 2, "xy"), pt.booleans())], (dd) => type(dd) == "dict")
t.check(d.ok, "dicts")
o := pt.check([pt.one_of([pt.just(null), pt.integers(0, 3)])], (v) => v == null or v <= 3)
t.check(o.ok, "one_of")
pt.for_all([pt.integers(-10, 10)], (n) => pt.assume(n != 0) == null and 10 // n * n <= 10 + 10)
e1 := pt.check([pt.integers()], (n) => n * 0 == 0, 50, 1)
e2 := pt.check([pt.integers()], (n) => n * 0 == 0, 50, 1)
t.eq(e1.seed, e2.seed, "graine")

t.summary("test_testing2")

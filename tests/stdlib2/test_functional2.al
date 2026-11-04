# Tests : functional.function, closure, lambda, bind, compose, optional, either, functional_errors.
from core use len, type
from collections use append
use check as t
use functional
use functional.function as fn
use functional.closure as cl
use functional.lambda as L
use functional.bind as b
use functional.compose as c
use functional.optional as opt
use functional.either as ei

class Pt:
    func init(x):
        self.x = x
    func scaled(k):
        return self.x * k

func add3(a, b2, c2=0):
    return a + b2 + c2

# function
t.eq(fn.arity(add3), [2, 3], "arity")
t.eq(fn.name_of(add3), "add3", "name_of")
t.eq(fn.name_of((x) => x), "<lambda>", "name_of lambda")
double := fn.Function((x) => x * 2, "double")
inc := fn.Function((x) => x + 1, "inc")
t.eq(double.then(inc)(5), 11, "then")
t.eq(double.then(inc).name, "double>>inc", "nom composé")
t.eq(double.compose(inc)(5), 12, "compose")
moins := fn.Function((a, b2) => a - b2)
t.eq(moins.flip()(1, 10), 9, "flip")
t.eq(moins.partial(10)(3), 7, "partial")
t.eq(moins.partial_right(1)(10), 9, "partial_right")
t.eq(moins.apply([7, 2]), 5, "apply")
cnt := double.counted()
cnt(1)
cnt(2)
t.eq(cnt.calls, 2, "counted")
memo_calls := [0]
func slow(x):
    memo_calls[0] += 1
    return x * x
ms := fn.Function(slow).memoized()
ms(4)
ms(4)
t.eq(memo_calls[0], 1, "memoized")
t.check(not fn.Function((x) => x > 0).negate()(5), "negate")
t.eq(fn.constant(7)(1, 2), 7, "constant")
t.eq(fn.times(3, (i) => i * 10), [0, 10, 20], "times")
t.raises(() => fn.Function(3), "TypeError", "Function(non fonction)")

# closure
nid := cl.counter(100)
t.eq([nid(), nid(), nid()], [100, 101, 102], "counter")
loads := [0]
func load():
    loads[0] += 1
    return "cfg"
lz := cl.Lazy(load)
t.check(not lz.is_evaluated(), "Lazy non évaluée")
t.eq(lz.peek("x"), "x", "peek")
t.eq(lz.get(), "cfg", "Lazy get")
lz.get()
t.eq(loads[0], 1, "Lazy calcule une fois")
lz.reset()
lz.get()
t.eq(loads[0], 2, "Lazy reset")
t.eq(lz.map((s) => s + "!").get(), "cfg!", "Lazy map")
init_calls := [0]
func initialiser():
    init_calls[0] += 1
    return init_calls[0]
o := cl.once(initialiser)
o()
t.eq(o(), 1, "once")
t.eq(init_calls[0], 1, "once exécute une fois")
acc := cl.accumulator(0, (a, x) => a + x)
acc(5)
t.eq(acc(3), 8, "accumulator")
tg := cl.toggle("a", "b")
t.eq([tg(), tg(), tg()], ["a", "b", "a"], "toggle")
bf := cl.before(2, (x) => x)
t.eq([bf(1), bf(2), bf(3)], [1, 2, 2], "before")
af := cl.after(2, (x) => x)
t.eq([af(1), af(2)], [null, 2], "after")
gen := cl.generator([1, 2])
t.eq([gen(), gen(), gen()], [1, 2, null], "generator")
bx := cl.Box(1)
bx.update((v) => v + 1)
t.eq(bx.get(), 2, "Box")
pair := cl.counting((x) => x)
pair[0](1)
pair[0](1)
t.eq(pair[1](), 2, "counting")

# lambda
t.eq(functional.map([1, 2, 3], L.mul(10)), [10, 20, 30], "mul")
t.eq(functional.filter([1, 5, 12], L.both(L.gt(0), L.lt(10))), [1, 5], "both")
people := [{"nom": "a", "age": 20}, {"nom": "b", "age": 12}]
t.eq(functional.map(functional.filter(people, L.key_ge("age", 18)), L.key("nom")), ["a"], "key/key_ge")
t.eq(functional.map([Pt(1), Pt(2)], L.field("x")), [1, 2], "field")
t.eq(functional.map([Pt(1), Pt(2)], L.call_method("scaled", 3)), [3, 6], "call_method")
t.raises(() => L.call_method("nope")(Pt(1)), "AttributeError", "méthode absente")
t.eq(functional.reduce([3, 1, 2], L.maximum(), 0), 3, "maximum")
t.check(L.any_of(L.eq(1), L.eq(2))(2), "any_of")
t.check(not L.all_of(L.gt(0), L.lt(2))(5), "all_of")
t.eq(L.key_or("z", 0)({"a": 1}), 0, "key_or")
t.check(L.is_in([1, 2])(2), "is_in")
t.check(L.not_(L.is_null())(3), "not_ / is_null")
t.eq(L.compose_pred(L.gt(2), L.length())("abc"), true, "compose_pred")

# bind
diff := (a, b2) => a - b2
t.eq(b.bind(diff, b._1, 10)(25), 15, "bind _1, 10")
t.eq(b.bind(diff, 10, b._1)(3), 7, "bind 10, _1")
t.eq(b.bind(diff, b._2, b._1)(1, 5), 4, "bind _2, _1")
t.eq(b.bind(add3, 1)(2, 3), 6, "arguments en plus")
t.raises(() => b.bind(diff, b._2, b._1)(1), "BindError", "espace réservé manquant")
t.eq(b.bind_front(add3, 1, 2)(3), 6, "bind_front")
t.eq(b.bind_back(diff, 1)(10), 9, "bind_back")
pm := b.bind_method(Pt(4), "scaled")
t.eq(pm(2), 8, "bind_method")
t.eq(b.bound(diff, b._1, 2).required, 1, "Bound.required")
t.check(b.is_placeholder(b.placeholder(3)), "placeholder")

# compose
norm := c.pipe((s) => s.strip(), (s) => s.lower())
t.eq(norm("  Bonjour "), "bonjour", "pipe")
t.eq(c.compose((x) => x + 1, (x) => x * 2)(5), 11, "compose")
t.eq(c.compose()(4), 4, "compose vide")
avg := c.converge((s, n) => s / n, [(xs) => functional.sum(xs), (xs) => len(xs)])
t.eq(avg([2, 4]), 3.0, "converge")
sg := c.cond([[(x) => x < 0, (x) => "négatif"], [(x) => x == 0, (x) => "nul"]], (x) => "positif")
t.eq([sg(-1), sg(0), sg(5)], ["négatif", "nul", "positif"], "cond")
p := c.Pipeline().then((x) => x + 1).then((x) => x * 2)
t.eq(p.run(3), 8, "Pipeline")
t.eq(p.size(), 2, "Pipeline.size")
t.eq(c.juxt((x) => x + 1, (x) => x * 2)(3), [4, 6], "juxt")
t.eq(c.when((x) => x > 0, (x) => -x)(5), -5, "when")
t.eq(c.unless((x) => x > 0, (x) => -x)(5), 5, "unless")
t.eq(c.iterate_until((x) => x * 2, (x) => x > 100, 1), 128, "iterate_until")
t.eq(c.fix_point((x) => (x + 2 / x) / 2 if x > 0 else 1.0, 1.0) > 1.4142, true, "fix_point")
t.eq(c.spread(add3)([1, 2, 3]), 6, "spread")
t.eq(c.gather((xs) => len(xs))(1, 2, 3), 3, "gather")
logged := []
t.eq(c.tap((x) => append(logged, x))(9), 9, "tap")
t.eq(logged, [9], "tap effet")

# optional
o1 := opt.of_nullable(null)
t.check(o1.is_empty(), "of_nullable(null)")
t.eq(o1.or_else("anonyme"), "anonyme", "or_else")
t.raises(() => o1.get(), "EmptyOptionalError", "get vide")
t.eq(opt.of(5).flat_map((x) => opt.of(x * 2)).get(), 10, "flat_map")
t.eq(opt.of({"nom": ""}).map((u) => u["nom"]).filter((n) => n != "").or_else("?"), "?", "map/filter")
t.eq(opt.of(3).map((x) => null).is_present(), false, "map -> null")
t.raises(() => opt.of(null), "ArgumentError", "of(null)")
t.check(opt.of(1) == opt.of(1), "égalité")
t.check(not (opt.of(1) == opt.empty()), "inégalité")
t.eq(str(opt.first_present([opt.empty(), opt.of(3)])), "Optional(3)", "first_present")
t.eq(opt.values([opt.of(1), opt.empty(), opt.of(2)]), [1, 2], "values")
t.check(opt.attempt((x) => 1 / x, 0).is_empty(), "attempt erreur")
t.eq(opt.get_key({"a": 1}, "a").get(), 1, "get_key")
t.raises(() => opt.empty().or_raise("KeyError", "absente"), "KeyError", "or_raise")
seen := []
opt.of(2).if_present((v) => append(seen, v))
t.eq(seen, [2], "if_present")

# either
func parse_age(s):
    if not s.isdigit():
        return ei.left("pas un nombre : " + s)
    return ei.right(int(s))
r := parse_age("42").map((n) => n + 1).filter_or((n) => n < 150, "improbable")
t.eq(r.fold((err) => "erreur " + err, (v) => "âge " + str(v)), "âge 43", "fold right")
r2 := parse_age("x").map((n) => n + 1)
t.check(r2.is_left(), "left traverse map")
t.eq(r2.left(), "pas un nombre : x", "left")
t.raises(() => r2.right(), "EitherError", "right sur Left")
t.eq(parse_age("999").filter_or((n) => n < 150, "improbable").left(), "improbable", "filter_or")
tc := ei.try_call((a, b2) => a / b2, 1, 0)
t.eq(tc.left()["type"], "ZeroDivisionError", "try_call")
t.eq(str(ei.sequence([ei.right(1), ei.right(2)])), "Right([1, 2])", "sequence")
t.eq(ei.sequence([ei.right(1), ei.left("e")]).left(), "e", "sequence left")
t.eq(ei.partition([ei.left(1), ei.right(2), ei.left(3)]), [[1, 3], [2]], "partition")
t.eq(ei.left(1).swap().right(), 1, "swap")
t.eq(ei.left("e").recover((e) => 0).right(), 0, "recover")
t.check(ei.right(1) == ei.right(1), "égalité Either")
t.eq(ei.cond(false, 1, "non").left(), "non", "cond")

t.summary("functional2")

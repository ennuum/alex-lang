# ALEX STANDARD LIBRARY — testing.property_test
#
# Tests de PROPRIÉTÉS (à la QuickCheck / Hypothesis) : au lieu de quelques exemples choisis à la main, on
# énonce une propriété vraie pour TOUTES les entrées, et le module l'essaie sur des centaines d'entrées
# aléatoires (reproductibles par graine). En cas d'échec, le contre-exemple est RÉDUIT (shrinking) au plus
# simple possible avant d'être rapporté.
#
#   use testing.property_test as pt
#   pt.for_all([pt.lists(pt.integers())], (xs) => sorted(sorted(xs)) == sorted(xs))     # idempotence du tri
#   pt.for_all([pt.integers(), pt.integers()], (a, b) => a + b == b + a, 500)
#   r := pt.check([pt.text()], (s) => len(s) < 5)          # PropertyResult (sans lever)
#   print(r.ok, r.counterexample)                           # false ["aaaaa"] (réduit)
#   g := pt.one_of([pt.integers(0, 9), pt.just(null)])
#   pt.for_all([pt.dicts(pt.text(1, 3), pt.booleans())], ma_propriete, 100, 42)   # graine 42
#
# Générateurs : integers(lo, hi), floats(lo, hi), booleans(), text(min, max, alphabet), lists(g, min, max),
# dicts(gk, gv, max), tuples([g...]), one_of([g...]), sampled_from(valeurs), just(v), map(g, f), filter(g, p).
# Erreurs : PropertyError (for_all : contre-exemple trouvé ; le message donne l'entrée réduite et la graine).

from core use len, type
from collections use append
use string as _s
use random as _rnd
use testing.testing_errors as _e

class Gen:
    # draw(rng) -> valeur ; shrink(valeur) -> liste de valeurs plus simples.
    func init(draw, shrink=null, name="gen"):
        self.draw = draw
        self.shrink = shrink
        self.name = name

    func shrinks(v):
        if self.shrink == null:
            return []
        return self.shrink(v)

func _int_shrinks(lo):
    func sh(v):
        out := []
        target := 0
        if lo != null and lo > 0:
            target = lo
        if v != target:
            append(out, target)
            half := target + (v - target) // 2
            if half != v and half != target:
                append(out, half)
            if v > target:
                append(out, v - 1)
            else:
                append(out, v + 1)
        return out
    return sh

func integers(lo=-1000, hi=1000):
    return Gen((g) => _rnd.randint(lo, hi, g), _int_shrinks(lo), "integers")

func floats(lo=-1000.0, hi=1000.0):
    func sh(v):
        if v == 0.0:
            return []
        if lo > 0:
            return [lo * 1.0]
        return [0.0, v / 2]
    return Gen((g) => _rnd.uniform(lo, hi, g), sh, "floats")

func booleans():
    return Gen((g) => _rnd.random(g) < 0.5, (v) => [false] if v else [], "booleans")

const ALPHABET := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 éàç"

func text(min_len=0, max_len=10, alphabet=ALPHABET):
    func draw(g):
        n := _rnd.randint(min_len, max_len, g)
        out := ""
        i := 0
        while i < n:
            out += str(alphabet[_rnd.randbelow(len(alphabet), g)])
            i += 1
        return out
    func sh(v):
        out := []
        if len(v) > min_len:
            append(out, _s.substring(v, 0, min_len))
            append(out, _s.substring(v, 0, len(v) - 1))
            append(out, _s.substring(v, 1, len(v)))
        simple := ""
        for c in v:
            simple += str(alphabet[0])
        if simple != v:
            append(out, simple)
        return out
    return Gen(draw, sh, "text")

func lists(elem, min_len=0, max_len=10):
    func draw(g):
        n := _rnd.randint(min_len, max_len, g)
        return [elem.draw(g) for i in 0..n]
    func sh(v):
        out := []
        if len(v) > min_len:
            append(out, v[:min_len])
            append(out, v[:len(v) - 1])
            append(out, v[1:])
        i := 0
        while i < len(v):
            for s in elem.shrinks(v[i]):
                c := v[:]
                c[i] = s
                append(out, c)
            i += 1
        return out
    return Gen(draw, sh, "lists")

func dicts(keys, values, max_len=5):
    func draw(g):
        n := _rnd.randint(0, max_len, g)
        d := {}
        i := 0
        while i < n:
            d[keys.draw(g)] = values.draw(g)
            i += 1
        return d
    func sh(v):
        out := []
        for k in v:
            c := {}
            for k2 in v:
                if not (k2 == k):
                    c[k2] = v[k2]
            append(out, c)
        return out
    return Gen(draw, sh, "dicts")

func tuples(gens):
    return Gen((g) => [x.draw(g) for x in gens], null, "tuples")

func one_of(gens):
    return Gen((g) => gens[_rnd.randbelow(len(gens), g)].draw(g), null, "one_of")

func sampled_from(values):
    return Gen((g) => values[_rnd.randbelow(len(values), g)], null, "sampled_from")

func just(v):
    return Gen((g) => v, null, "just")

func map(gen, f):
    return Gen((g) => f(gen.draw(g)), null, "map")

func filter(gen, pred, max_tries=100):
    func draw(g):
        i := 0
        while i < max_tries:
            v := gen.draw(g)
            if pred(v):
                return v
            i += 1
        raise(_e.PROPERTY, "filter : aucune valeur acceptée en " + str(max_tries) + " essais")
    return Gen(draw, null, "filter")

class PropertyResult:
    func init(ok, runs, counterexample, original, error, seed, shrink_steps):
        self.ok = ok
        self.runs = runs
        self.counterexample = counterexample
        self.original = original
        self.error = error
        self.seed = seed
        self.shrink_steps = shrink_steps

    func __str__():
        if self.ok:
            return "propriété vérifiée sur " + str(self.runs) + " cas (graine " + str(self.seed) + ")"
        return "contre-exemple " + str(self.counterexample) + " après " + str(self.runs) + " cas (graine " + str(self.seed) + ", " + str(self.shrink_steps) + " réductions) : " + str(self.error)

func _holds(prop, args):
    try:
        r := prop(*args)
        if r == false:
            return [false, "la propriété a rendu false"]
        return [true, null]
    catch e:
        if e.type == _e.SKIP:
            return [true, null]
        return [false, e.type + " : " + e.message]

func _shrink(gens, prop, args, max_steps):
    cur := args
    err := null
    steps := 0
    improved := true
    while improved and steps < max_steps:
        improved = false
        i := 0
        while i < len(gens) and not improved:
            for cand in gens[i].shrinks(cur[i]):
                trial := cur[:]
                trial[i] = cand
                h := _holds(prop, trial)
                if not h[0]:
                    cur = trial
                    err = h[1]
                    steps += 1
                    improved = true
                    break
            i += 1
    return [cur, err, steps]

# Vérifie prop(*valeurs) sur runs tirages ; PropertyResult (ne lève pas).
func check(gens, prop, runs=100, seed=null, max_shrinks=200):
    sd := seed
    if sd == null:
        sd = 12345
    g := _rnd.new(sd)
    k := 0
    while k < runs:
        args := [x.draw(g) for x in gens]
        h := _holds(prop, args)
        if not h[0]:
            s := _shrink(gens, prop, args, max_shrinks)
            err := s[1]
            if err == null:
                err = h[1]
            return PropertyResult(false, k + 1, s[0], args, err, sd, s[2])
        k += 1
    return PropertyResult(true, runs, null, null, null, sd, 0)

# Comme check, mais lève PropertyError avec le contre-exemple réduit.
func for_all(gens, prop, runs=100, seed=null):
    r := check(gens, prop, runs, seed)
    if not r.ok:
        raise(_e.PROPERTY, str(r))
    return r

# Écarte le cas courant (précondition non remplie) : le tirage est ignoré.
func assume(cond):
    if not cond:
        _e.skip("hypothèse non remplie")

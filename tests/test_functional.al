# =============================================================================
# ALEX - tests du module functional (ALEX pur).
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/test_functional.al
# =============================================================================
use functional
use functional as fn
use string
from functional use map, filter, reduce, seq
from core use len, type
from collections use append, clear, keys

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

# Vrai si f() lève une erreur dont le texte contient `fragment`.
func raises(f, fragment):
    try:
        f()
    catch e:
        return has(f"{e}", fragment)
    return false

func has(text, fragment):
    n := len(text)
    m := len(fragment)
    i := 0
    while i + m <= n:
        j := 0
        while j < m and text[i + j] == fragment[j]:
            j = j + 1
        if j == m:
            return true
        i = i + 1
    return false

func run(name, f):
    clear(notes)
    before := stats[1]
    f()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")

func double(x):
    return x * 2

func is_even(x):
    return x % 2 == 0

func add(a, b):
    return a + b

# --- construction ----------------------------------------------------------

func t_construction():
    check_eq(fn.range_list(0, 5), [0, 1, 2, 3, 4], "range_list")
    check_eq(fn.range_list(2, 8, 3), [2, 5], "pas 3")
    check_eq(fn.range_list(5, 0, -2), [5, 3, 1], "pas négatif")
    check_eq(fn.range_list(3, 3), [], "vide")
    check_eq(fn.range_list(5, 0), [], "borne inversée")
    check_eq(fn.repeat("x", 3), ["x", "x", "x"], "repeat")
    check_eq(fn.repeat(1, 0), [], "repeat 0")
    check_eq(fn.iterate(double, 1, 5), [1, 2, 4, 8, 16], "iterate")
    check_eq(fn.iterate(double, 1, 0), [], "iterate 0")
    check_eq(raises(() => fn.range_list(0, 5, 0), "ValueError"), true, "pas nul")
    check_eq(raises(() => fn.range_list(0.5, 5), "TypeError"), true, "range float")
    check_eq(raises(() => fn.repeat(1, -1), "ValueError"), true, "repeat négatif")

# --- transformation --------------------------------------------------------

func t_transform():
    check_eq(map([1, 2, 3], double), [2, 4, 6], "map fonction nommée")
    check_eq(map([1, 2, 3], x => x + 1), [2, 3, 4], "map lambda")
    check_eq(map([], double), [], "map vide")
    check_eq(map((1, 2), double), [2, 4], "map tuple")
    check_eq(map("abc", c => c + c), ["aa", "bb", "cc"], "map str")
    check_eq(filter([1, 2, 3, 4], is_even), [2, 4], "filter")
    check_eq(filter([1, 3], is_even), [], "filter rien")
    check_eq(fn.reject([1, 2, 3, 4], is_even), [1, 3], "reject")
    check_eq(fn.flat_map([1, 2, 3], x => [x, x * 10]), [1, 10, 2, 20, 3, 30], "flat_map")
    check_eq(fn.flat_map([1, 2], x => (x, x)), [1, 1, 2, 2], "flat_map tuples")
    check_eq(reduce([1, 2, 3, 4], add, 0), 10, "reduce")
    check_eq(reduce([], add, 7), 7, "reduce vide => init")
    check_eq(reduce([1, 2, 3], (a, b) => a - b, 10), 4, "reduce à gauche")
    check_eq(fn.fold_right([1, 2, 3], (x, acc) => x - acc, 0), 2, "fold_right")
    check_eq(fn.fold_right(["a", "b", "c"], (x, acc) => acc + x, ""), "cba", "fold_right str")
    check_eq(fn.scan([1, 2, 3, 4], add, 0), [1, 3, 6, 10], "scan")
    check_eq(fn.sum([1, 2, 3]), 6, "sum")
    check_eq(fn.sum([]), 0, "sum vide")
    check_eq(fn.sum([1, 2, 3], x => x * x), 14, "sum avec f")
    check_eq(fn.prod([1, 2, 3, 4]), 24, "prod")
    check_eq(fn.prod([]), 1, "prod vide")
    check_eq(fn.count_if([1, 2, 3, 4, 6], is_even), 3, "count_if")
    seen := []
    check_eq(fn.for_each([1, 2, 3], x => append(seen, x * 2)), null, "for_each renvoie null")
    check_eq(seen, [2, 4, 6], "for_each effets")

func t_no_mutation():
    src := [3, 1, 2]
    map(src, double)
    filter(src, is_even)
    fn.sort_by(src)
    fn.reverse(src)
    fn.take(src, 1)
    fn.drop(src, 1)
    fn.unique(src)
    fn.concat(src, [9])
    fn.flatten([src])
    check_eq(src, [3, 1, 2], "entrée intacte")
    d := {"a": 1}
    fn.map_values(d, double)
    fn.filter_dict(d, (k, v) => false)
    check_eq(d, {"a": 1}, "dict intact")
    r := fn.take(src, 10)
    append(r, 99)
    check_eq(src, [3, 1, 2], "résultat indépendant de l'entrée")

# --- paires et indices -----------------------------------------------------

func t_pairs():
    check_eq(fn.zip([1, 2, 3], ["a", "b", "c"]), [(1, "a"), (2, "b"), (3, "c")], "zip")
    check_eq(fn.zip([1, 2, 3], ["a"]), [(1, "a")], "zip court à droite")
    check_eq(fn.zip([1], [1, 2, 3]), [(1, 1)], "zip court à gauche")
    check_eq(fn.zip([], [1]), [], "zip vide")
    check_eq(fn.zip_with([1, 2, 3], [10, 20, 30], add), [11, 22, 33], "zip_with")
    check_eq(fn.zip_with([1, 2], [10], add), [11], "zip_with court")
    check_eq(fn.unzip([(1, "a"), (2, "b")]), [[1, 2], ["a", "b"]], "unzip")
    check_eq(fn.unzip([]), [[], []], "unzip vide")
    check_eq(fn.unzip(fn.zip([1, 2], [3, 4])), [[1, 2], [3, 4]], "unzip(zip)")
    check_eq(fn.enumerate(["a", "b"]), [(0, "a"), (1, "b")], "enumerate")
    check_eq(fn.enumerate(["a", "b"], 1), [(1, "a"), (2, "b")], "enumerate start")
    check_eq(fn.pairwise([1, 2, 3, 4]), [(1, 2), (2, 3), (3, 4)], "pairwise")
    check_eq(fn.pairwise([1]), [], "pairwise court")
    check_eq(fn.pairwise([]), [], "pairwise vide")

# --- découpage -------------------------------------------------------------

func t_slicing():
    check_eq(fn.take([1, 2, 3, 4], 2), [1, 2], "take")
    check_eq(fn.take([1, 2], 5), [1, 2], "take trop")
    check_eq(fn.take([1, 2], 0), [], "take 0")
    check_eq(fn.take([1, 2], -3), [], "take négatif")
    check_eq(fn.drop([1, 2, 3, 4], 2), [3, 4], "drop")
    check_eq(fn.drop([1, 2], 5), [], "drop trop")
    check_eq(fn.drop([1, 2], 0), [1, 2], "drop 0")
    check_eq(fn.drop([1, 2], -1), [1, 2], "drop négatif")
    check_eq(fn.take_while([1, 2, 5, 1], x => x < 3), [1, 2], "take_while")
    check_eq(fn.take_while([5, 1], x => x < 3), [], "take_while rien")
    check_eq(fn.take_while([1, 2], x => x < 3), [1, 2], "take_while tout")
    check_eq(fn.drop_while([1, 2, 5, 1], x => x < 3), [5, 1], "drop_while")
    check_eq(fn.drop_while([1, 2], x => x < 3), [], "drop_while tout")
    check_eq(fn.split_at([1, 2, 3, 4], 1), [[1], [2, 3, 4]], "split_at")
    check_eq(fn.chunk([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]], "chunk")
    check_eq(fn.chunk([1, 2, 3, 4], 2), [[1, 2], [3, 4]], "chunk exact")
    check_eq(fn.chunk([], 3), [], "chunk vide")
    check_eq(fn.window([1, 2, 3, 4], 2), [[1, 2], [2, 3], [3, 4]], "window 2")
    check_eq(fn.window([1, 2, 3], 3), [[1, 2, 3]], "window = taille")
    check_eq(fn.window([1, 2], 3), [], "window trop grand")
    check_eq(raises(() => fn.chunk([1], 0), "ValueError"), true, "chunk 0")
    check_eq(raises(() => fn.window([1], 0), "ValueError"), true, "window 0")
    check_eq(raises(() => fn.take([1], "a"), "TypeError"), true, "take non entier")

# --- recherche -------------------------------------------------------------

func t_search():
    check_eq(fn.find([1, 3, 4, 6], is_even), 4, "find")
    check_eq(fn.find([1, 3], is_even), null, "find absent")
    check_eq(fn.find([1, 3], is_even, -1), -1, "find défaut")
    check_eq(fn.find_index([1, 3, 4], is_even), 2, "find_index")
    check_eq(fn.find_index([1, 3], is_even), -1, "find_index absent")
    check_eq(fn.any_of([1, 2], is_even), true, "any_of")
    check_eq(fn.any_of([], is_even), false, "any_of vide")
    check_eq(fn.all_of([2, 4], is_even), true, "all_of")
    check_eq(fn.all_of([2, 3], is_even), false, "all_of non")
    check_eq(fn.all_of([], is_even), true, "all_of vide")
    check_eq(fn.none_of([1, 3], is_even), true, "none_of")
    check_eq(fn.none_of([1, 2], is_even), false, "none_of non")
    check_eq(fn.partition([1, 2, 3, 4, 5], is_even), [[2, 4], [1, 3, 5]], "partition")
    check_eq(fn.partition([], is_even), [[], []], "partition vide")

# --- groupement ------------------------------------------------------------

func t_grouping():
    g := fn.group_by([1, 2, 3, 4, 5, 6], x => x % 3)
    check_eq(g[0], [3, 6], "group_by 0")
    check_eq(g[1], [1, 4], "group_by 1")
    check_eq(g[2], [2, 5], "group_by 2")
    check_eq(len(g), 3, "3 groupes")
    check_eq(fn.group_by([], x => x), {}, "group_by vide")
    words := fn.group_by(["pomme", "poire", "kiwi", "banane"], w => str(w[0]))
    check_eq(words["p"], ["pomme", "poire"], "clé str")
    check_eq(fn.count_by([1, 2, 3, 4, 5], is_even), {true: 2, false: 3}, "count_by")
    check_eq(fn.frequencies(["a", "b", "a", "c", "a"]), {"a": 3, "b": 1, "c": 1}, "frequencies")
    check_eq(fn.unique([3, 1, 3, 2, 1]), [3, 1, 2], "unique ordre conservé")
    check_eq(fn.unique([]), [], "unique vide")
    check_eq(fn.unique([(1, 2), (1, 2), (2, 1)]), [(1, 2), (2, 1)], "unique tuples")
    check_eq(fn.unique_by(["a", "B", "A", "b"], s => lower_char(s)), ["a", "B"], "unique_by")

func lower_char(s):
    if s == "A":
        return "a"
    if s == "B":
        return "b"
    return s

# --- tri -------------------------------------------------------------------

func t_sort():
    check_eq(fn.sort_by([3, 1, 2]), [1, 2, 3], "tri naturel")
    check_eq(fn.sorted([3, 1, 2]), [1, 2, 3], "sorted")
    check_eq(fn.sort_by([3, 1, 2], null, true), [3, 2, 1], "décroissant")
    check_eq(fn.sort_by([], null), [], "tri vide")
    check_eq(fn.sort_by([1]), [1], "tri 1 élément")
    check_eq(fn.sort_by(["b", "c", "a"]), ["a", "b", "c"], "tri str")
    check_eq(fn.sort_by([2.5, 1, 3]), [1, 2.5, 3], "tri mixte int/float")
    check_eq(fn.sort_by([-3, 5, 0, -1]), [-3, -1, 0, 5], "tri négatifs")
    check_eq(fn.sort_by([(2, "a"), (1, "b")], p => p[0]), [(1, "b"), (2, "a")], "tri par clé")
    # stabilité : égalité de clé => ordre d'origine
    data := [(1, "a"), (0, "b"), (1, "c"), (0, "d"), (1, "e")]
    check_eq(fn.sort_by(data, p => p[0]), [(0, "b"), (0, "d"), (1, "a"), (1, "c"), (1, "e")], "stable croissant")
    check_eq(fn.sort_by(data, p => p[0], true), [(1, "a"), (1, "c"), (1, "e"), (0, "b"), (0, "d")], "stable décroissant")
    gens := [("Bob", 31), ("Ana", 25), ("Cléa", 31), ("Dan", 25), ("Ana", 31)]
    par_nom := fn.sort_by(gens, p => p[0])
    check_eq(fn.sort_by(par_nom, p => p[1]), [("Ana", 25), ("Dan", 25), ("Ana", 31), ("Bob", 31), ("Cléa", 31)], "tri en deux passes")
    check_eq(raises(() => fn.sort_by([(1, 2), (1, 3)]), "TypeError"), true, "tuples non comparables")
    big := []
    i := 0
    while i < 500:
        append(big, (i * 37) % 101)
        i = i + 1
    s := fn.sort_by(big)
    ok := true
    j := 1
    while j < len(s):
        if s[j - 1] > s[j]:
            ok = false
        j = j + 1
    check_eq(ok, true, "500 éléments triés")
    check_eq(len(s), 500, "500 éléments conservés")
    check_eq(fn.min_by([3, 1, 2]), 1, "min_by")
    check_eq(fn.max_by([3, 1, 2]), 3, "max_by")
    check_eq(fn.min_by(["bb", "a", "ccc"], x => len(x)), "a", "min_by clé")
    check_eq(fn.max_by(["bb", "a", "ccc"], x => len(x)), "ccc", "max_by clé")
    check_eq(fn.min_by(["ab", "cd"], x => len(x)), "ab", "min_by égalité : premier")
    check_eq(fn.max_by(["ab", "cd"], x => len(x)), "ab", "max_by égalité : premier")
    check_eq(fn.min_by([], null, 0), 0, "min_by vide + défaut")
    check_eq(raises(() => fn.min_by([]), "IndexError"), true, "min_by vide")
    check_eq(raises(() => fn.max_by([]), "IndexError"), true, "max_by vide")

# --- listes ----------------------------------------------------------------

func t_lists():
    check_eq(fn.reverse([1, 2, 3]), [3, 2, 1], "reverse")
    check_eq(fn.reverse([]), [], "reverse vide")
    check_eq(fn.concat([1], [2, 3]), [1, 2, 3], "concat")
    check_eq(fn.concat([], []), [], "concat vide")
    check_eq(fn.flatten([1, [2, [3, [4]]]]), [1, 2, [3, [4]]], "flatten 1 niveau")
    check_eq(fn.flatten([1, [2, [3, [4]]]], 2), [1, 2, 3, [4]], "flatten 2 niveaux")
    check_eq(fn.flatten([1, [2, [3, [4]]]], -1), [1, 2, 3, 4], "flatten tout")
    check_eq(fn.flatten([1, [2, [3]]], 0), [1, [2, [3]]], "flatten 0")
    check_eq(fn.flatten([]), [], "flatten vide")
    check_eq(fn.flatten(["ab", [1]]), ["ab", 1], "flatten n'ouvre pas les str")
    check_eq(fn.flatten([(1, 2), [3]]), [1, 2, 3], "flatten tuples")
    check_eq(fn.interleave([1, 2, 3], [10, 20]), [1, 10, 2, 20, 3], "interleave")
    check_eq(fn.interleave([1], [10, 20, 30]), [1, 10, 20, 30], "interleave droite")
    check_eq(fn.interleave([], []), [], "interleave vide")
    check_eq(fn.intersperse([1, 2, 3], 0), [1, 0, 2, 0, 3], "intersperse")
    check_eq(fn.intersperse([1], 0), [1], "intersperse 1")
    check_eq(fn.intersperse([], 0), [], "intersperse vide")

# --- combinatoire ----------------------------------------------------------

func t_combinatorics():
    check_eq(fn.cross([1, 2], ["a", "b"]), [(1, "a"), (1, "b"), (2, "a"), (2, "b")], "cross")
    check_eq(fn.cross([], [1]), [], "cross vide")
    check_eq(fn.combinations([1, 2, 3], 2), [[1, 2], [1, 3], [2, 3]], "combinations 2")
    check_eq(fn.combinations([1, 2, 3], 0), [[]], "combinations 0")
    check_eq(fn.combinations([1, 2, 3], 3), [[1, 2, 3]], "combinations n")
    check_eq(fn.combinations([1, 2], 3), [], "combinations k > n")
    check_eq(len(fn.combinations(fn.range_list(0, 8), 4)), 70, "C(8,4) = 70")
    check_eq(fn.permutations([1, 2, 3]), [[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]], "permutations")
    check_eq(fn.permutations([]), [[]], "permutations vide")
    check_eq(fn.permutations([7]), [[7]], "permutations 1")
    check_eq(len(fn.permutations([1, 2, 3, 4, 5])), 120, "5! = 120")
    check_eq(raises(() => fn.combinations([1], -1), "ValueError"), true, "k négatif")

# --- dictionnaires ---------------------------------------------------------

func t_dicts():
    check_eq(fn.map_values({"a": 1, "b": 2}, double), {"a": 2, "b": 4}, "map_values")
    check_eq(fn.map_values({}, double), {}, "map_values vide")
    check_eq(fn.filter_dict({"a": 1, "b": 2, "c": 3}, (k, v) => v > 1), {"b": 2, "c": 3}, "filter_dict valeur")
    check_eq(fn.filter_dict({"a": 1, "b": 2}, (k, v) => k == "a"), {"a": 1}, "filter_dict clé")
    check_eq(fn.from_pairs([("a", 1), ("b", 2)]), {"a": 1, "b": 2}, "from_pairs")
    check_eq(fn.from_pairs([("a", 1), ("a", 2)]), {"a": 2}, "from_pairs doublon")
    check_eq(fn.from_pairs([]), {}, "from_pairs vide")

# --- combinateurs ----------------------------------------------------------

func t_combinators():
    f := fn.compose(x => x + 1, x => x * 2)
    check_eq(f(5), 11, "compose : f(g(x))")
    check_eq(fn.compose_all([x => x + 1, x => x * 2, x => x - 3])(10), 15, "compose_all")
    check_eq(fn.compose_all([])(7), 7, "compose_all vide = identité")
    check_eq(fn.pipe(3, [x => x + 1, x => x * 2]), 8, "pipe")
    check_eq(fn.pipe(3, []), 3, "pipe vide")
    check_eq(fn.pipeline([x => x + 1, x => x * 2])(3), 8, "pipeline")
    check_eq(fn.partial(add, 10)(5), 15, "partial")
    check_eq(fn.partial2((a, b, c) => a * 100 + b * 10 + c, 1, 2)(3), 123, "partial2")
    check_eq(fn.partial_right((a, b) => a - b, 1)(10), 9, "partial_right")
    check_eq(fn.flip((a, b) => a - b)(1, 10), 9, "flip")
    check_eq(fn.curry2(add)(1)(2), 3, "curry2")
    check_eq(fn.curry3((a, b, c) => a + b * c)(1)(2)(3), 7, "curry3")
    add5 := fn.curry2(add)(5)
    check_eq(map([1, 2], add5), [6, 7], "curry2 réutilisable")
    check_eq(fn.constant(4)("ignoré"), 4, "constant")
    check_eq(fn.negate(is_even)(3), true, "negate")
    check_eq(filter([1, 2, 3, 4], fn.negate(is_even)), [1, 3], "negate dans filter")
    trace := []
    check_eq(fn.pipe(2, [fn.tap(x => append(trace, x)), double, fn.tap(x => append(trace, x))]), 4, "tap transparent")
    check_eq(trace, [2, 4], "tap effets")
    check_eq(raises(() => fn.compose(1, double), "TypeError"), true, "compose non fonction")
    check_eq(raises(() => map([1], 5), "TypeError"), true, "map non fonction")
    check_eq(raises(() => map(5, double), "TypeError"), true, "map non liste")
    check_eq(raises(() => fn.pipe(1, [double, 3]), "TypeError"), true, "pipe non fonction")

func t_once_memoize():
    calls := [0]
    func costly(x):
        calls[0] = calls[0] + 1
        return x * x
    m := fn.memoize(costly)
    check_eq(m(4), 16, "memoize valeur")
    check_eq(m(4), 16, "memoize valeur 2")
    check_eq(m(5), 25, "memoize autre")
    check_eq(calls[0], 2, "memoize : 2 calculs")
    check_eq(fn.memoize(x => x)((1, 2)), (1, 2), "memoize clé tuple")
    nul := [0]
    mn := fn.memoize(x => count_null(nul))
    mn(1)
    mn(1)
    check_eq(nul[0], 1, "memoize cache aussi null")
    c2 := [0]
    m2 := fn.memoize2((a, b) => count2(c2, a, b))
    check_eq(m2(1, 2), 3, "memoize2")
    check_eq(m2(1, 2), 3, "memoize2 cache")
    check_eq(m2(2, 1), 3, "memoize2 ordre")
    check_eq(c2[0], 2, "memoize2 : 2 calculs")
    c3 := [0]
    o := fn.once(x => count3(c3, x))
    check_eq(o(1), 1, "once 1er")
    check_eq(o(2), 1, "once ignore la suite")
    check_eq(c3[0], 1, "once : 1 appel")
    # memoize rend fib exponentiel => linéaire
    fibm := [null]
    func fib(n):
        if n < 2:
            return n
        return fibm[0](n - 1) + fibm[0](n - 2)
    fibm[0] = fn.memoize(fib)
    check_eq(fibm[0](60), 1548008755920, "fib(60) mémoïsé")

func count_null(box):
    box[0] = box[0] + 1
    return null

func count2(box, a, b):
    box[0] = box[0] + 1
    return a + b

func count3(box, x):
    box[0] = box[0] + 1
    return x

# --- Seq -------------------------------------------------------------------

func t_seq():
    r := seq([5, 3, 8, 1]).filter(x => x > 2).map(x => x * 10).sort_by().to_list()
    check_eq(r, [30, 50, 80], "chaîne filter/map/sort_by")
    check_eq(seq([1, 2, 3, 4]).reject(is_even).to_list(), [1, 3], "reject")
    check_eq(seq([1, 2]).flat_map(x => [x, x]).to_list(), [1, 1, 2, 2], "flat_map")
    check_eq(seq([1, 2, 3, 4, 5]).take(3).drop(1).to_list(), [2, 3], "take/drop")
    check_eq(seq([1, 2, 5, 1]).take_while(x => x < 3).to_list(), [1, 2], "take_while")
    check_eq(seq([1, 2, 5, 1]).drop_while(x => x < 3).to_list(), [5, 1], "drop_while")
    check_eq(seq(["a", "b"]).enumerate(1).to_list(), [(1, "a"), (2, "b")], "enumerate")
    check_eq(seq([1, 2]).zip(["a", "b"]).to_list(), [(1, "a"), (2, "b")], "zip")
    check_eq(seq([1, 2, 3]).chunk(2).to_list(), [[1, 2], [3]], "chunk")
    check_eq(seq([1, 2, 3]).window(2).to_list(), [[1, 2], [2, 3]], "window")
    check_eq(seq([[1], [2, [3]]]).flatten(-1).to_list(), [1, 2, 3], "flatten")
    check_eq(seq([1, 1, 2]).unique().to_list(), [1, 2], "unique")
    check_eq(seq([1, 2, 3]).reverse().to_list(), [3, 2, 1], "reverse")
    check_eq(seq([1]).concat([2]).to_list(), [1, 2], "concat")
    check_eq(seq([1, 2, 3]).scan(add, 0).to_list(), [1, 3, 6], "scan")
    check_eq(seq([1, 2, 3, 4]).reduce(add, 0), 10, "reduce")
    check_eq(seq([1, 2, 3]).sum(), 6, "sum")
    check_eq(seq([1, 2, 3]).sum(x => x * 2), 12, "sum f")
    check_eq(seq([1, 2, 3]).count(), 3, "count")
    check_eq(seq([1, 2, 3]).find(x => x > 1), 2, "find")
    check_eq(seq([1, 2, 3]).find(x => x > 5, 0), 0, "find défaut")
    check_eq(seq([1, 2]).any_of(is_even), true, "any_of")
    check_eq(seq([1, 3]).all_of(is_even), false, "all_of")
    check_eq(seq([1, 2, 3]).group_by(is_even)[true], [2], "group_by")
    check_eq(seq([3, 1, 2]).min_by(), 1, "min_by")
    check_eq(seq([3, 1, 2]).max_by(), 3, "max_by")
    check_eq(seq([]).first(), null, "first vide")
    check_eq(seq([]).first(9), 9, "first défaut")
    check_eq(seq([4, 5]).first(), 4, "first")
    check_eq(seq([4, 5]).last(), 5, "last")
    check_eq(seq([]).last(7), 7, "last défaut")
    check_eq(seq("abc").map(c => c + "!").to_list(), ["a!", "b!", "c!"], "Seq sur str")
    src := [3, 1, 2]
    s := seq(src)
    s2 := s.map(double)
    check_eq(s.to_list(), [3, 1, 2], "Seq immuable")
    check_eq(s2.to_list(), [6, 2, 4], "nouveau Seq")
    append(src, 9)
    check_eq(s.to_list(), [3, 1, 2], "Seq copie l'entrée")
    out := s.to_list()
    append(out, 5)
    check_eq(s.count(), 3, "to_list renvoie une copie")
    seen := []
    seq([1, 2]).tap(x => append(seen, x)).map(double)
    check_eq(seen, [1, 2], "tap")
    check_eq(isinstance(s, functional.Seq), true, "isinstance Seq")

# --- scénarios -------------------------------------------------------------

func t_scenarios():
    # mots les plus fréquents
    text := ["a", "b", "a", "c", "b", "a"]
    freq := fn.frequencies(text)
    top := fn.sort_by(keys(freq), k => freq[k], true)
    check_eq(fn.take(top, 2), ["a", "b"], "top 2 fréquences")
    # triplets pythagoriciens
    triples := seq(fn.cross(fn.range_list(1, 21), fn.range_list(1, 21))).filter(p => p[0] < p[1]).map(p => (p[0], p[1], p[0] * p[0] + p[1] * p[1])).filter(t => is_square(t[2])).count()
    check_eq(triples, 7, "couples (a,b) avec c entier")
    # matrice transposée par zip répété
    m := [[1, 2, 3], [4, 5, 6]]
    t := map(fn.range_list(0, 3), j => map(m, row => row[j]))
    check_eq(t, [[1, 4], [2, 5], [3, 6]], "transposée")
    # moyenne mobile
    avg := map(fn.window([1, 2, 3, 4, 5], 3), w => fn.sum(w) / 3)
    check_eq(avg, [2.0, 3.0, 4.0], "moyenne mobile")
    # compter les anagrammes via group_by + tri de caractères
    words := ["listen", "silent", "enlist", "google", "gogole"]
    groups := fn.group_by(words, w => string.join("", fn.sort_by(w)))
    check_eq(len(groups), 2, "2 familles d'anagrammes")

func is_square(n):
    r := 0
    while r * r < n:
        r = r + 1
    return r * r == n

run("construction", t_construction)
run("transformation", t_transform)
run("pas de mutation des entrées", t_no_mutation)
run("paires et indices", t_pairs)
run("découpage", t_slicing)
run("recherche", t_search)
run("groupement", t_grouping)
run("tri", t_sort)
run("listes", t_lists)
run("combinatoire", t_combinatorics)
run("dictionnaires", t_dicts)
run("combinateurs", t_combinators)
run("once / memoize", t_once_memoize)
run("Seq (chaînage)", t_seq)
run("scénarios", t_scenarios)

total := stats[0] + stats[1]
print("")
print("=== FUNCTIONAL ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total})")
if stats[1] > 0:
    raise("AssertionError", f"{stats[1]} vérification(s) en échec")
print("TOUS LES TESTS FUNCTIONAL PASSENT")

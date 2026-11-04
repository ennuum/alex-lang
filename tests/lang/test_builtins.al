# =============================================================================
# ALEX - builtins implicites (sans aucun import) : len, abs, min, max, sum, sorted, range, zip, ...
# et méthodes de list / dict / str (xs.append(1), s.upper(), d.get(k, 0)).
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_builtins.al
# =============================================================================
stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] += 1
    else:
        stats[1] += 1
        notes.append(f"{label} : obtenu {actual}, attendu {expected}")

func check_raises(fn, kind, label):
    raised := ""
    try:
        fn()
    catch e:
        raised = e.type
    check_eq(raised, kind, label)

func run(name, fn):
    notes.clear()
    before := stats[1]
    fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [ok]     {name}")

func t_fonctions():
    check_eq(len([1, 2, 3]), 3, "len")
    check_eq(abs(-4), 4, "abs int")
    check_eq(abs(-2.5), 2.5, "abs float")
    check_eq(min(3, 1, 2), 1, "min varargs")
    check_eq(max(3, 1, 2), 3, "max varargs")
    check_eq(min([4, 2, 8]), 2, "min liste")
    check_eq(max((4, 2, 8)), 8, "max tuple")
    check_eq(sum([1, 2, 3]), 6, "sum")
    check_eq(sum([1, 2, 3], 10), 16, "sum start")
    check_eq(range(4), [0, 1, 2, 3], "range(n)")
    check_eq(range(2, 5), [2, 3, 4], "range(a, b)")
    check_eq(range(10, 0, -3), [10, 7, 4, 1], "range pas négatif")
    check_eq(sorted([3, 1, 2]), [1, 2, 3], "sorted")
    check_eq(sorted([3, 1, 2], reverse=true), [3, 2, 1], "sorted reverse")
    check_eq(sorted(["bb", "a", "ccc"], key=(s) => len(s)), ["a", "bb", "ccc"], "sorted key")
    check_eq(reversed([1, 2, 3]), [3, 2, 1], "reversed")
    check_eq(enumerate(["a", "b"]), [(0, "a"), (1, "b")], "enumerate")
    check_eq(enumerate(["a"], 5), [(5, "a")], "enumerate start")
    check_eq(zip([1, 2, 3], ["a", "b"]), [(1, "a"), (2, "b")], "zip")
    check_eq(map((x) => x * 2, [1, 2, 3]), [2, 4, 6], "map")
    check_eq(filter((x) => x > 1, [1, 2, 3]), [2, 3], "filter")
    check_eq(divmod(17, 5), (3, 2), "divmod")
    check_eq(int("42"), 42, "int(str)")
    check_eq(int(3.9), 3, "int(float)")
    check_eq(float("2.5"), 2.5, "float(str)")
    check_eq(bool(0), false, "bool(0)")
    check_eq(list((1, 2)), [1, 2], "list(tuple)")
    check_eq(tuple([1, 2]), (1, 2), "tuple(list)")
    check_eq(dict([("a", 1)])["a"], 1, "dict(paires)")
    check_eq(all([true, true]), true, "all")
    check_eq(any([false, true]), true, "any")
    check_eq(ord("A"), 65, "ord")
    check_eq(str(chr(66)), "B", "chr")
    check_eq(round(2.6), 3, "round")
    check_eq(round(3.14159, 2), 3.14, "round ndigits")
    check_raises(() => max([]), "ValueError", "max vide")
    for i, x in enumerate(["u", "v"]):
        check_eq(i < 2, true, "for enumerate")

func t_methodes_list():
    xs := [3, 1, 2]
    xs.append(9)
    check_eq(xs, [3, 1, 2, 9], "append")
    xs.sort()
    check_eq(xs, [1, 2, 3, 9], "sort")
    xs.sort(null, true)
    check_eq(xs, [9, 3, 2, 1], "sort reverse")
    xs.reverse()
    check_eq(xs, [1, 2, 3, 9], "reverse")
    check_eq(xs.pop(), 9, "pop")
    check_eq(xs.pop(0), 1, "pop(0)")
    xs.insert(1, 7)
    check_eq(xs, [2, 7, 3], "insert")
    xs.extend([4, 5])
    check_eq(xs, [2, 7, 3, 4, 5], "extend")
    xs.remove(7)
    check_eq(xs.index(3), 1, "index")
    check_eq(xs.count(4), 1, "count")
    ys := xs.copy()
    ys.clear()
    check_eq(len(xs), 4, "copy indépendant")
    check_eq(len(ys), 0, "clear")
    check_raises(() => [].pop(), "IndexError", "pop vide")
    check_raises(() => [1].remove(5), "ValueError", "remove absent")

func t_methodes_dict():
    d := {"a": 1, "b": 2}
    check_eq(d.get("a"), 1, "get")
    check_eq(d.get("z", 0), 0, "get défaut")
    check_eq(len(d.keys()), 2, "keys")
    check_eq(sorted(d.values()), [1, 2], "values")
    check_eq(len(d.items()), 2, "items")
    d.update({"c": 3})
    check_eq(d["c"], 3, "update")
    check_eq(d.setdefault("z", 26), 26, "setdefault")
    check_eq(d.pop("a"), 1, "pop")
    check_eq("a" in d, false, "pop retire")
    e := d.copy()
    e.clear()
    check_eq(len(d) > 0, true, "copy indépendant")
    check_eq(len(e), 0, "clear")

func t_methodes_str():
    check_eq("abc".upper(), "ABC", "upper")
    check_eq("ABC".lower(), "abc", "lower")
    check_eq("  x ".strip(), "x", "strip")
    check_eq("  x ".lstrip(), "x ", "lstrip")
    check_eq("  x ".rstrip(), "  x", "rstrip")
    check_eq("a b  c".split(), ["a", "b", "c"], "split()")
    check_eq("a,b".split(","), ["a", "b"], "split(sep)")
    check_eq("-".join(["a", "b", "c"]), "a-b-c", "join")
    check_eq(", ".join([1, 2]), "1, 2", "join non-str")
    check_eq("aXb".replace("X", "-"), "a-b", "replace")
    check_eq("hello".startswith("he"), true, "startswith")
    check_eq("hello".endswith("lo"), true, "endswith")
    check_eq("hello".find("l"), 2, "find")
    check_eq("banana".count("a"), 3, "count")
    check_eq("123".isdigit(), true, "isdigit")
    check_eq("12a".isdigit(), false, "isdigit non")
    check_eq("abc".isalpha(), true, "isalpha")
    check_eq("7".zfill(3), "007", "zfill")
    check_eq("ab".ljust(4, "."), "ab..", "ljust")
    check_eq("ab".rjust(4), "  ab", "rjust")
    s := "Bonjour"
    check_eq(s.upper().lower(), "bonjour", "chaînage")

# une définition locale gagne sur le builtin
func pow(a):
    return a * a

func t_shadowing():
    check_eq(pow(5), 25, "pow redéfini par le module")
    max := 7
    check_eq(max, 7, "variable locale max")

print("== builtins implicites ==")
run("fonctions", t_fonctions)
run("méthodes de list", t_methodes_list)
run("méthodes de dict", t_methodes_dict)
run("méthodes de str", t_methodes_str)
run("redéfinition locale", t_shadowing)
print(f"{stats[0]} vérifications réussies, {stats[1]} échec(s)")
if stats[1] > 0:
    raise("AssertionError", "test_builtins : échecs")

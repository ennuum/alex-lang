# =============================================================================
# ALEX - tests du module json (ALEX pur).
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/test_json.al
# =============================================================================
use json
use string
use io
use os
from core use len, type
from collections use append, clear

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

# Vrai si fn() lève une erreur dont le texte contient `fragment`.
func raises(fn, fragment):
    try:
        fn()
    catch e:
        return string_has(f"{e}", fragment)
    return false

func string_has(text, fragment):
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

func run(name, fn):
    clear(notes)
    before := stats[1]
    fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")

func bad(text):
    return () => json.parse(text)

# --- parse : scalaires -----------------------------------------------------

func t_scalars():
    check_eq(json.parse("null"), null, "null")
    check_eq(json.parse("true"), true, "true")
    check_eq(json.parse("false"), false, "false")
    check_eq(json.parse("0"), 0, "0")
    check_eq(json.parse("-0"), 0, "-0")
    check_eq(json.parse("42"), 42, "entier")
    check_eq(json.parse("-17"), -17, "entier négatif")
    check_eq(type(json.parse("42")), "int", "type int")
    check_eq(json.parse("2.5"), 2.5, "float")
    check_eq(type(json.parse("1.0")), "float", "1.0 est float")
    check_eq(json.parse("-0.25"), -0.25, "float négatif")
    check_eq(json.parse("1e2"), 100.0, "exposant")
    check_eq(json.parse("1E2"), 100.0, "exposant E")
    check_eq(json.parse("1e+2"), 100.0, "exposant +")
    check_eq(json.parse("25e-1"), 2.5, "exposant négatif")
    check_eq(json.parse("1.5e1"), 15.0, "fraction + exposant")
    check_eq(type(json.parse("1e2")), "float", "exposant => float")
    check_eq(json.parse("  \n\t 7 \r\n"), 7, "espaces autour")
    check_eq(json.parse("\"abc\""), "abc", "chaîne")
    check_eq(json.parse("\"\""), "", "chaîne vide")
    check_eq(json.parse("\"héllo — ok\""), "héllo — ok", "UTF-8 brut")

# --- parse : échappements --------------------------------------------------

func t_escapes():
    check_eq(json.parse("\"a\\\"b\""), "a\"b", "\\\"")
    check_eq(json.parse("\"a\\\\b\""), "a\\b", "\\\\")
    check_eq(json.parse("\"a\\/b\""), "a/b", "\\/")
    check_eq(json.parse("\"l1\\nl2\""), "l1\nl2", "\\n")
    check_eq(json.parse("\"a\\tb\""), "a\tb", "\\t")
    check_eq(json.parse("\"a\\rb\""), "a\rb", "\\r")
    check_eq(json.parse("\"\\u0041\""), "A", "\\u ASCII")
    check_eq(json.parse("\"\\u007e\""), "~", "\\u minuscule hex")
    check_eq(json.parse("\"\\u007E\""), "~", "\\u majuscule hex")
    check_eq(json.parse("\"\\u00e9\""), "é", "\\u Latin-1")
    check_eq(json.parse("\"\\u00FF\""), "ÿ", "\\u 255")
    check_eq(json.parse("\"\\u20ac\""), "€", "\\u euro")
    check_eq(json.parse("\"\\u2019\""), "’", "\\u apostrophe")
    check_eq(json.parse("\"caf\\u00e9!\""), "café!", "\\u au milieu")
    check_eq(json.parse("\"\\u000a\""), "\n", "\\u000a")
    check_eq(len(json.parse("\"\\u0000\"")), 1, "\\u0000")
    check_eq(json.parse("\"\\u4e2d\\u6587\""), "中文", "\\u CJK")
    check_eq(json.parse("\"\\ud83d\\ude00\""), "😀", "paire de substitution")
    check_eq(json.parse("\"a\\uD834\\uDD1Eb\""), "a𝄞b", "paire au milieu")
    check_eq(string.ord(json.parse("\"\\b\"")[0]), 8, "\\b")
    check_eq(string.ord(json.parse("\"\\f\"")[0]), 12, "\\f")
    check_eq(string.ord(json.parse("\"\\u0001\"")[0]), 1, "\\u0001")

# --- parse : structures ----------------------------------------------------

func t_structures():
    check_eq(json.parse("[]"), [], "tableau vide")
    check_eq(json.parse("[ ]"), [], "tableau vide espacé")
    check_eq(json.parse("{}"), {}, "objet vide")
    check_eq(json.parse("{ }"), {}, "objet vide espacé")
    check_eq(json.parse("[1,2,3]"), [1, 2, 3], "tableau")
    check_eq(json.parse("[1, [2, [3, []]]]"), [1, [2, [3, []]]], "imbriqué")
    check_eq(json.parse("[null,true,false]"), [null, true, false], "littéraux")
    o := json.parse("{\"a\": 1, \"b\": [true, {\"c\": null}], \"d\": \"x\"}")
    check_eq(o["a"], 1, "objet a")
    check_eq(o["b"][0], true, "objet b[0]")
    check_eq(o["b"][1]["c"], null, "objet b[1].c")
    check_eq(o["d"], "x", "objet d")
    check_eq(len(o), 3, "3 clés")
    dup := json.parse("{\"k\": 1, \"k\": 2}")
    check_eq(dup["k"], 2, "clé dupliquée : la dernière gagne")
    check_eq(json.parse("{\"é\": 1}")["é"], 1, "clé UTF-8")
    multi := json.parse("{\n  \"a\": [\n    1,\n    2\n  ]\n}\n")
    check_eq(multi["a"], [1, 2], "multiligne")

# --- parse : erreurs -------------------------------------------------------

func t_parse_errors():
    cases := ["", "   ", "{", "}", "[", "]", "[1,", "[1 2]", "[1,]", "{\"a\"}", "{\"a\":}", "{\"a\":1,}",
              "{a: 1}", "{'a': 1}", "'x'", "\"abc", "tru", "nul", "True", "NaN", "Infinity", "01", "1.", ".5", "-",
              "1e", "1e+", "+1", "--1", "0x10", "[1] x", "{} {}", "\"a\\qb\"", "\"\\u12\"", "\"\\u12g4\"",
              "\"\\ud83d\"", "\"\\ude00\"", "\"\\ud83dx\"", "\"\\ud83d\\u0041\"", "\"a\nb\"", "\"a\tb\"", "[1;2]", "{\"a\" 1}"]
    for c in cases:
        check_eq(raises(bad(c), "JSONError"), true, f"rejeté : {c}")
    check_eq(raises(() => json.parse(5), "JSONError"), true, "parse(5) rejeté")
    check_eq(raises(() => json.parse(null), "JSONError"), true, "parse(null) rejeté")

func t_error_position():
    check_eq(raises(bad("[1, 2,\n  oops]"), "ligne 2, colonne 3"), true, "position ligne/colonne")
    check_eq(raises(bad("{\"a\": 1} x"), "ligne 1, colonne 10"), true, "texte superflu")
    check_eq(raises(bad("[1 2]"), "colonne 4"), true, "séparateur manquant")

func t_is_valid():
    check_eq(json.is_valid("{\"a\": [1, 2]}"), true, "valide")
    check_eq(json.is_valid("[1, 2"), false, "invalide")
    check_eq(json.is_valid(""), false, "vide invalide")
    check_eq(json.is_valid("null"), true, "null valide")

# --- stringify -------------------------------------------------------------

func t_stringify_scalars():
    check_eq(json.stringify(null), "null", "null")
    check_eq(json.stringify(true), "true", "true")
    check_eq(json.stringify(false), "false", "false")
    check_eq(json.stringify(42), "42", "int")
    check_eq(json.stringify(-3), "-3", "int négatif")
    check_eq(json.stringify(2.5), "2.5", "float")
    check_eq(json.stringify("abc"), "\"abc\"", "str")
    check_eq(json.stringify(""), "\"\"", "str vide")
    check_eq(json.stringify("a\"b"), "\"a\\\"b\"", "guillemet")
    check_eq(json.stringify("a\\b"), "\"a\\\\b\"", "antislash")
    check_eq(json.stringify("a\nb\tc\rd"), "\"a\\nb\\tc\\rd\"", "\\n \\t \\r")
    check_eq(json.stringify("é€"), "\"é€\"", "UTF-8 conservé")
    check_eq(len(json.stringify("\0")), 8, "NUL => \\u0000")
    check_eq(json.stringify(str(string.chr(1))), "\"\\u0001\"", "contrôle => \\u0001")
    check_eq(json.stringify(str(string.chr(8)) + str(string.chr(12))), "\"\\b\\f\"", "\\b \\f")
    rt := "t" + str(string.chr(1)) + str(string.chr(31)) + "é😀"
    check_eq(json.parse(json.stringify(rt)), rt, "aller-retour contrôle")

func t_stringify_structures():
    check_eq(json.stringify([]), "[]", "[]")
    check_eq(json.stringify({}), "{}", "{}")
    check_eq(json.stringify([1, 2, 3]), "[1,2,3]", "liste")
    check_eq(json.stringify((1, "a")), "[1,\"a\"]", "tuple => tableau")
    check_eq(json.stringify({"b": 1, "a": 2}), "{\"a\":2,\"b\":1}", "clés triées")
    check_eq(json.stringify({"b": 1, "a": [true, null]}), "{\"a\":[true,null],\"b\":1}", "imbriqué")
    check_eq(json.stringify({"z": 1, "y": 2, "x": 3, "w": 4, "v": 5, "u": 6, "t": 7}),
             "{\"t\":7,\"u\":6,\"v\":5,\"w\":4,\"x\":3,\"y\":2,\"z\":1}", "tri de 7 clés")
    check_eq(json.stringify({"b": 1, "a": 2}, null, false) != null, true, "sort_keys=false accepté")
    check_eq(json.parse(json.stringify({"b": 1, "a": 2}, null, false)), {"a": 2, "b": 1}, "sort_keys=false relisible")

func t_pretty():
    check_eq(json.pretty([]), "[]", "pretty []")
    check_eq(json.pretty({}), "{}", "pretty {}")
    check_eq(json.pretty([1, 2]), "[\n  1,\n  2\n]", "pretty liste")
    check_eq(json.pretty({"a": 1}), "{\n  \"a\": 1\n}", "pretty objet")
    check_eq(json.pretty({"a": [1], "b": {}}), "{\n  \"a\": [\n    1\n  ],\n  \"b\": {}\n}", "pretty imbriqué")
    check_eq(json.stringify([1, [2]], 4), "[\n    1,\n    [\n        2\n    ]\n]", "indent 4")
    check_eq(json.stringify([1], 0), "[\n1\n]", "indent 0 : sauts de ligne sans retrait")

func t_stringify_errors():
    check_eq(raises(() => json.stringify({1: "a"}), "JSONError"), true, "clé int")
    check_eq(raises(() => json.stringify(1.5 * 10.0 ** 400), "JSONError"), true, "inf")
    check_eq(raises(() => json.stringify((10.0 ** 400) - (10.0 ** 400)), "JSONError"), true, "nan")
    check_eq(raises(() => json.stringify(() => 1), "JSONError"), true, "fonction")
    check_eq(raises(() => json.stringify([1], -1), "JSONError"), true, "indent négatif")
    check_eq(raises(() => json.stringify([1], "x"), "JSONError"), true, "indent non entier")
    cyc := [1]
    cyc[0] = cyc
    check_eq(raises(() => json.stringify(cyc), "profondeur"), true, "liste cyclique")
    cd := {}
    cd["me"] = cd
    check_eq(raises(() => json.stringify(cd), "profondeur"), true, "dict cyclique")

func t_depth():
    s := ""
    i := 0
    while i < 101:
        s = s + "["
        i = i + 1
    i = 0
    while i < 101:
        s = s + "]"
        i = i + 1
    check_eq(raises(bad(s), "profondeur"), true, "101 niveaux refusés")
    ok := ""
    i = 0
    while i < 50:
        ok = ok + "["
        i = i + 1
    i = 0
    while i < 50:
        ok = ok + "]"
        i = i + 1
    check_eq(json.is_valid(ok), true, "50 niveaux acceptés")
    s100 := string_rep("[", 100) + string_rep("]", 100)
    check_eq(json.is_valid(s100), true, "100 niveaux acceptés")
    deep := json.parse(s100)
    check_eq(json.stringify(deep), s100, "100 niveaux re-sérialisés")
    check_eq(raises(() => json.stringify([deep]), "profondeur"), true, "101 niveaux refusés à l'écriture")

func string_rep(s, n):
    out := ""
    i := 0
    while i < n:
        out = out + s
        i = i + 1
    return out

# --- aller-retour ----------------------------------------------------------

func t_roundtrip():
    docs := [
        "null", "true", "0", "-5", "2.5", "\"x\"", "[]", "{}",
        "[1,2,[3,[4,[5]]]]",
        "{\"a\":{\"b\":{\"c\":[1,2,{\"d\":null}]}}}",
        "{\"s\":\"ligne1\\nligne2\\t\\\"q\\\" \\\\ é €\"}",
        "[true,false,null,0,1.5,-2.25,\"\"]"
    ]
    for d in docs:
        v := json.parse(d)
        check_eq(json.stringify(v), d, f"compact : {d}")
        check_eq(json.parse(json.pretty(v)), v, f"pretty relisible : {d}")
        check_eq(json.parse(json.stringify(v)), v, f"valeur identique : {d}")

func t_big_document():
    items := []
    i := 0
    while i < 300:
        append(items, {"id": i, "name": f"item{i}", "tags": ["a", "b", i], "ok": i % 2 == 0, "x": i * 0.5})
        i = i + 1
    text := json.stringify({"items": items})
    back := json.parse(text)
    check_eq(len(back["items"]), 300, "300 éléments")
    check_eq(back["items"][299]["name"], "item299", "dernier nom")
    check_eq(back["items"][10]["x"], 5.0, "flottant")
    check_eq(json.stringify(back), text, "stable")

# --- fichiers --------------------------------------------------------------

func t_files():
    path := "alex_json_test.tmp"
    data := {"nom": "Alex", "n": [1, 2, 3], "ok": true}
    json.save(path, data)
    check_eq(io.file_exists(path), true, "fichier créé")
    check_eq(json.load(path), data, "load(save(x)) == x")
    io.write_file(path, "[1, 2")
    check_eq(raises(() => json.load(path), "JSONError"), true, "load invalide")
    io.delete_file(path)
    check_eq(io.file_exists(path), false, "nettoyage")

run("parse : scalaires", t_scalars)
run("parse : échappements", t_escapes)
run("parse : structures", t_structures)
run("parse : erreurs", t_parse_errors)
run("parse : position des erreurs", t_error_position)
run("is_valid", t_is_valid)
run("stringify : scalaires", t_stringify_scalars)
run("stringify : structures", t_stringify_structures)
run("pretty / indent", t_pretty)
run("stringify : erreurs", t_stringify_errors)
run("profondeur", t_depth)
run("aller-retour", t_roundtrip)
run("gros document", t_big_document)
run("load / save", t_files)

total := stats[0] + stats[1]
print("")
print("=== JSON ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total})")
if stats[1] > 0:
    raise("AssertionError", f"{stats[1]} vérification(s) en échec")
print("TOUS LES TESTS JSON PASSENT")

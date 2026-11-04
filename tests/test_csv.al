# ALEX - tests du module csv (ALEX pur). Lancer depuis la racine : ./alex run tests/test_csv.al
use csv
use io
use os
use testing
from testing use assert_eq, assert_raises

func t_1():
    assert_eq(csv.parse("a,b\n1,2\n"), [["a", "b"], ["1", "2"]])
    assert_eq(csv.parse("a,b\n1,2"), [["a", "b"], ["1", "2"]])
    assert_eq(csv.parse("a,b\r\n1,2\r\n"), [["a", "b"], ["1", "2"]])
    assert_eq(csv.parse("a\rb"), [["a"], ["b"]])
    assert_eq(csv.parse(""), [])
    assert_eq(csv.parse("a"), [["a"]])
    assert_eq(csv.parse("a,"), [["a", ""]])
    assert_eq(csv.parse(",,"), [["", "", ""]])
    assert_eq(csv.parse("a,b\n\nc,d\n"), [["a", "b"], [""], ["c", "d"]])

testing.test("parse simple", t_1)

func t_2():
    assert_eq(csv.parse("\"x,y\",\"he said \"\"hi\"\"\"\n"), [["x,y", "he said \"hi\""]])
    assert_eq(csv.parse("\"multi\nline\",z\n"), [["multi\nline", "z"]])
    assert_eq(csv.parse("\"\",a"), [["", "a"]])
    assert_eq(csv.parse("a,\"b\""), [["a", "b"]])
    assert_eq(csv.parse("\"a\",\n"), [["a", ""]])

testing.test("guillemets", t_2)

func t_3():
    assert_eq(csv.parse("a;b;c\n1;2;3", ";"), [["a", "b", "c"], ["1", "2", "3"]])
    assert_eq(csv.parse("a\tb", "\t"), [["a", "b"]])
    assert_eq(csv.parse("'a,b';c", ";", "'"), [["a,b", "c"]])
    assert_raises(() => csv.parse("a", ",,"), "TypeError")
    assert_raises(() => csv.parse("a", ",", ","), "ValueError")

testing.test("délimiteur personnalisé", t_3)

func t_4():
    assert_eq(csv.parse("é,😀\n"), [["é", "😀"]])

testing.test("unicode", t_4)

func t_5():
    assert_raises(() => csv.parse("\"abc"), "CSVError", "guillemet non fermé")
    assert_raises(() => csv.parse("a\"b"), "CSVError", "inattendu")
    assert_raises(() => csv.parse("\"a\"b"), "CSVError", "après un champ")
    assert_raises(() => csv.parse("x\n\"abc"), "CSVError", "ligne 2")
    assert_raises(() => csv.parse(5), "TypeError")

testing.test("erreurs de parse", t_5)

func t_6():
    assert_eq(csv.parse_dict("nom,age\nAda,36\n\nHopper,85"), [{"nom": "Ada", "age": "36"}, {"nom": "Hopper", "age": "85"}])
    assert_eq(csv.parse_dict(""), [])
    assert_raises(() => csv.parse_dict("a,b\n1"), "CSVError", "champ")
    assert_raises(() => csv.parse_dict("a,a\n1,2"), "CSVError", "dupliqué")

testing.test("parse_dict", t_6)

func t_7():
    assert_eq(csv.stringify([["a", 1, 2.5, true], ["b,c", null, "q\"x", "l1\nl2"]]), "a,1,2.5,true\n\"b,c\",,\"q\"\"x\",\"l1\nl2\"\n")
    assert_eq(csv.stringify([]), "")
    assert_eq(csv.stringify([("a", "b")], ";"), "a;b\n")
    assert_eq(csv.stringify([["a"]], ",", "\"", "\r\n"), "a\r\n")
    assert_eq(csv.stringify_dict([{"b": 1, "a": "x"}]), "a,b\nx,1\n")
    assert_eq(csv.stringify_dict([{"a": 1}, {"b": 2}], ["a", "b"]), "a,b\n1,\n,2\n")
    assert_raises(() => csv.stringify([[[1]]]), "TypeError")
    assert_raises(() => csv.stringify("x"), "TypeError")

testing.test("stringify", t_7)

func t_8():
    rows := [["id", "texte"], ["1", "a,b"], ["2", "\"q\""], ["3", "l1\nl2"], ["4", ""], ["5", "é😀"]]
    assert_eq(csv.parse(csv.stringify(rows)), rows)

testing.test("aller-retour", t_8)

func t_9():
    p := os.join(os.tmp_dir(), "alex_test_csv_" + str(os.pid()) + ".csv")
    rows := [["a", "b"], ["1", "x,y"]]
    csv.save(p, rows)
    assert_eq(csv.load(p), rows)
    assert_eq(csv.load_dict(p), [{"a": "1", "b": "x,y"}])
    io.delete_file(p)

testing.test("load / save", t_9)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) csv en échec")
print("CSV: OK")

# ALEX - tests du module path (ALEX pur). Lancer depuis la racine : ./alex run tests/test_path.al
use path
use testing
from testing use assert_eq, assert_true, assert_false, assert_raises

func t_1():
    assert_eq(path.join("a", "b", "c.txt", win=false), "a/b/c.txt")
    assert_eq(path.join(["a", "", "b"], win=false), "a/b")
    assert_eq(path.join("a", "/abs", "b", win=false), "/abs/b")
    assert_eq(path.join("a/", "b", win=false), "a/b")
    assert_eq(path.join("a", "b", win=true), "a\\b")
    assert_eq(path.join("C:", "x", win=true), "C:x")
    assert_eq(path.join("a", "C:\\x", "y", win=true), "C:\\x\\y")

testing.test("join", t_1)

func t_2():
    assert_eq(path.normalize("a/./b/../c//d/", win=false), "a/c/d")
    assert_eq(path.normalize("/../a", win=false), "/a")
    assert_eq(path.normalize("../../x/..", win=false), "../..")
    assert_eq(path.normalize("", win=false), ".")
    assert_eq(path.normalize("a/..", win=false), ".")
    assert_eq(path.normalize("/", win=false), "/")
    assert_eq(path.normalize("C:/a/../b\\c", win=true), "C:\\b\\c")
    assert_eq(path.normalize("C:\\..\\x", win=true), "C:\\x")

testing.test("normalize", t_2)

func t_3():
    assert_eq(path.dirname("/a/b/c", win=false), "/a/b")
    assert_eq(path.dirname("c", win=false), "")
    assert_eq(path.dirname("/c", win=false), "/")
    assert_eq(path.dirname("a/b/", win=false), "a")
    assert_eq(path.basename("a/b/", win=false), "b")
    assert_eq(path.basename("/", win=false), "")
    assert_eq(path.basename("C:\\x\\y.txt", win=true), "y.txt")
    assert_eq(path.split("a/b/c", win=false), ("a/b", "c"))

testing.test("dirname basename split", t_3)

func t_4():
    assert_eq(path.extension("x/y.tar.gz", win=false), ".gz")
    assert_eq(path.stem("x/y.tar.gz", win=false), "y.tar")
    assert_eq(path.extension(".bashrc", win=false), "")
    assert_eq(path.stem(".bashrc", win=false), ".bashrc")
    assert_eq(path.extension("noext", win=false), "")
    assert_eq(path.with_extension("a/b.txt", ".md", win=false), "a/b.md")
    assert_eq(path.with_extension("a/b", ".md", win=false), "a/b.md")
    assert_eq(path.with_extension("a/b.txt", "", win=false), "a/b")
    assert_eq(path.with_name("a/b.txt", "c.md", win=false), "a/c.md")
    assert_eq(path.with_name("b.txt", "c.md", win=false), "c.md")
    assert_raises(() => path.with_extension("a", "md", win=false), "ValueError")
    assert_raises(() => path.with_name("a/b", "x/y", win=false), "ValueError")

testing.test("extension stem", t_4)

func t_5():
    assert_true(path.is_absolute("/a", false))
    assert_false(path.is_absolute("a/b", false))
    assert_true(path.is_absolute("C:\\x", true))
    assert_true(path.is_absolute("\\x", true))
    assert_false(path.is_absolute("C:x", true))
    assert_eq(path.parts("/a/b", false), ["/", "a", "b"])
    assert_eq(path.parts("a//b/", false), ["a", "b"])
    assert_eq(path.parts("C:\\a\\b", true), ["C:\\", "a", "b"])

testing.test("absolu et parts", t_5)

func t_6():
    assert_eq(path.relative_to("/a/b/c", "/a", win=false), "b/c")
    assert_eq(path.relative_to("/a", "/a/b/c", win=false), "../..")
    assert_eq(path.relative_to("/a/x", "/a/b", win=false), "../x")
    assert_eq(path.relative_to("/a", "/a", win=false), ".")
    assert_eq(path.relative_to("x/y", "x", win=false), "y")
    assert_raises(() => path.relative_to("/a", "b", win=false), "ValueError")
    assert_true(path.is_subpath("/a/b", "/a", false))
    assert_true(path.is_subpath("/a", "/a", false))
    assert_false(path.is_subpath("/ab", "/a", false))
    assert_false(path.is_subpath("/a/../b", "/a", false))
    assert_eq(path.common_prefix(["/a/b/c", "/a/b/d", "/a/b"], win=false), "/a/b")
    assert_eq(path.common_prefix(["/a", "/b"], win=false), "/")
    assert_eq(path.common_prefix(["a", "b"], win=false), "")
    assert_eq(path.common_prefix([], win=false), "")

testing.test("relative_to et sous-chemins", t_6)

func t_7():
    assert_true(path.glob_match("*.al", "main.al"))
    assert_false(path.glob_match("*.al", "main.alx"))
    assert_true(path.glob_match("a?[b-d]*", "axcZZ"))
    assert_false(path.glob_match("[!a]*", "abc"))
    assert_true(path.glob_match("*", ""))
    assert_true(path.glob_match("a*b*c", "aXXbYYc"))
    assert_false(path.glob_match("a*b*c", "aXXbYY"))
    assert_true(path.glob_match("[[]x", "[x"))

testing.test("glob_match", t_7)

# Valeur non typée : un littéral de mauvais type serait refusé à la compilation (TypeCheckError).
func _untyped(v):
    return v

func t_8():
    assert_raises(() => path.join(1, win=false), "TypeError")
    assert_raises(() => path.normalize(_untyped(null), false), "TypeError")

testing.test("types", t_8)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) path en échec")
print("PATH: OK")

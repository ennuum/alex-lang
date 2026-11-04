# ALEX - tests du module regex (ALEX pur). Lancer depuis la racine : ./alex run tests/test_regex.al
use regex
use string
use testing
from core use len
from testing use assert_eq, assert_true, assert_false, assert_null, assert_not_null, assert_raises

func t_base():
    assert_true(regex.test("abc", "xxabcxx"))
    assert_false(regex.test("abc", "xxabxcxx"))
    assert_true(regex.test("^[a-z]+@[a-z]+\\.com$", "ada@exemple.com"))
    assert_false(regex.test("^a$", "ab"))
    assert_true(regex.test("", "anything"))
    assert_true(regex.test("a.c", "abc"))
    assert_false(regex.test("a.c", "a\nc"))
    assert_true(regex.test("a.c", "a\nc", "s"))

func t_classes():
    assert_eq(regex.find_all("[a-c]+", "abcxyzcab"), ["abc", "cab"])
    assert_eq(regex.find_all("[^a-c ]+", "ab xy c"), ["xy"])
    assert_eq(regex.find_all("\\d+", "a12b345"), ["12", "345"])
    assert_eq(regex.find_all("\\D+", "a12b"), ["a", "b"])
    assert_eq(regex.find_all("\\w+", "un deux_2 é"), ["un", "deux_2", "é"])
    assert_eq(regex.find_all("\\s+", "a  b\tc"), ["  ", "\t"])
    assert_eq(regex.find_all("[\\d.]+", "v1.25 x"), ["1.25"])
    assert_eq(regex.find_all("[]a]+", "a]b"), ["a]"])
    assert_eq(regex.find_all("[a-]+", "a-b"), ["a-"])
    assert_eq(regex.find_all("[é-ü]+", "aéüb"), ["éü"])

func t_quantifieurs():
    assert_eq(regex.find_all("a{2}", "aaaaa"), ["aa", "aa"])
    assert_eq(regex.find_all("a{2,}", "aaaaa a"), ["aaaaa"])
    assert_eq(regex.find_all("a{1,2}", "aaaaa"), ["aa", "aa", "a"])
    assert_eq(regex.find_all("ab?c", "ac abc abbc"), ["ac", "abc"])
    assert_eq(regex.find_all("<.+?>", "<a><b>"), ["<a>", "<b>"])
    assert_eq(regex.find_all("<.+>", "<a><b>"), ["<a><b>"])
    assert_eq(regex.find_all("a*?b", "aab"), ["aab"])
    assert_eq(regex.find_all("a{,2}", "a{,2}"), ["a{,2}"])
    assert_eq(regex.find_all("x{", "x{"), ["x{"])
    assert_eq(regex.find_all("(ab)+", "ababab ab"), ["ababab", "ab"])
    assert_eq(regex.find_all("(?:ab){2}", "ababab"), ["abab"])

func t_groupes():
    m := regex.search("(\\d+)-(?P<mois>\\d+)", "le 12-05 ok")
    assert_eq(m["text"], "12-05")
    assert_eq(m["start"], 3)
    assert_eq(m["end"], 8)
    assert_eq(m["groups"], ["12", "05"])
    assert_eq(m["named"], {"mois": "05"})
    n := regex.search("(?<a>x)|(y)", "y")
    assert_eq(n["groups"], [null, "y"])
    assert_eq(n["named"]["a"], null)
    assert_eq(regex.search("(a)|b", "b")["groups"], [null])
    assert_eq(regex.search("(a*)*b", "aab")["text"], "aab")
    assert_eq(regex.search("(a|ab)(c|bcd)(d*)", "abcd")["groups"], ["a", "bcd", ""])

func t_alternance_ancres():
    assert_eq(regex.find_all("cat|dog", "cat dog bird"), ["cat", "dog"])
    assert_true(regex.test("^(a|b)*c$", "ababc"))
    assert_eq(regex.find_all("^a", "a\na"), ["a"])
    assert_eq(regex.find_all("^a", "a\na", "m"), ["a", "a"])
    assert_eq(regex.find_all("a$", "a\na", "m"), ["a", "a"])
    assert_eq(regex.find_all("\\bfoo\\b", "foo foobar foo"), ["foo", "foo"])
    assert_eq(regex.find_all("\\Boo", "foo oo"), ["oo"])

func t_backref_lookahead():
    assert_eq(regex.search("(\\w)\\1", "abccd")["text"], "cc")
    assert_null(regex.search("(\\w)\\1", "abcd"))
    assert_eq(regex.find_all("foo(?=bar)", "foobar foobaz"), ["foo"])
    assert_eq(regex.find_all("foo(?!bar)", "foobar foobaz"), ["foo"])
    assert_eq(regex.search("(?=(\\d+))\\d", "a12")["groups"], ["12"])
    assert_eq(regex.search("(a)\\1", "AA", "i")["text"], "AA")

func t_drapeaux():
    assert_true(regex.test("hello", "HeLLo", "i"))
    assert_false(regex.test("hello", "HeLLo"))
    assert_eq(regex.find_all("[a-z]+", "ABC def", "i"), ["ABC", "def"])
    assert_true(regex.test("É", "é", "i"))
    assert_raises(() => regex.test("a", "a", "x"), "RegexError", "drapeau")

func t_match_fullmatch():
    assert_not_null(regex.match_start("a+b", "aabxx"))
    assert_null(regex.match_start("b", "ab"))
    assert_not_null(regex.fullmatch("a+b", "aaab"))
    assert_null(regex.fullmatch("a+b", "aaabc"))
    assert_not_null(regex.fullmatch("a|ab", "ab"))
    assert_eq(regex.fullmatch("(a+)(a)?", "aaa")["text"], "aaa")

func t_search_start():
    assert_eq(regex.search("a", "aXa", "", 1)["start"], 2)
    assert_null(regex.search("a", "aXa", "", 3))
    assert_raises(() => regex.search("a", "a", "", -1), "ValueError")

func t_vides():
    assert_eq(regex.find_all("a*", "baac"), ["", "aa", "", ""])
    assert_eq(len(regex.finditer("", "abc")), 4)
    assert_eq(regex.replace("x*", "abc", "-"), "-a-b-c-")
    assert_eq(regex.split("", "abc"), ["a", "b", "c"])

func t_replace():
    assert_eq(regex.replace("(\\w+)@", "ada@x", "<\\1>@"), "<ada>@x")
    assert_eq(regex.replace("a", "aaa", "b", 2), "bba")
    assert_eq(regex.replace("(?P<n>\\d)", "a1b2", "[\\g<n>]"), "a[1]b[2]")
    assert_eq(regex.replace("\\d", "a1", "\\0\\0"), "a11")
    assert_eq(regex.replace("a", "a", "\\\\"), "\\")
    assert_eq(regex.replace("(x)|(y)", "y", "[\\1]"), "[]")
    assert_eq(regex.replace("\\d+", "a1b22", m => str(len(m["text"]))), "a1b2")
    assert_eq(regex.replace("é", "été", "e"), "ete")
    assert_raises(() => regex.replace("a", "a", "\\2"), "RegexError", "invalide")
    assert_raises(() => regex.replace("a", "a", 5), "TypeError")

func t_split():
    assert_eq(regex.split("\\s*,\\s*", "a , b,c"), ["a", "b", "c"])
    assert_eq(regex.split("(,)", "a,b"), ["a", ",", "b"])
    assert_eq(regex.split(",", "a,b,c", 1), ["a", "b,c"])
    assert_eq(regex.split(",", ""), [""])
    assert_eq(regex.split(",", ",a,"), ["", "a", ""])

func t_escape_compile():
    assert_eq(regex.escape("a.b*c"), "a\\.b\\*c")
    assert_true(regex.test(regex.escape("1+1=2?"), "1+1=2?"))
    rx := regex.compile("(\\d+)")
    assert_eq(regex.find_all(rx, "a1b22"), ["1", "22"])
    assert_eq(regex.compile("(\\d+)"), rx)

func t_erreurs():
    for bad in ["(", ")", "a)", "[a", "*a", "a**", "a++", "\\", "(?x)", "[z-a]", "a{3,2}", "(?P<n)", "(?P<1a>x)", "(?P<n>a)(?P<n>b)", "+", "?", "^*", "(?=a)*"]:
        assert_raises(() => regex.compile(bad), "RegexError")
    assert_raises(() => regex.compile(5), "TypeError")
    assert_raises(() => regex.test("a", 5), "TypeError")

func t_pratique():
    email := "^[\\w.+-]+@[\\w-]+(\\.[\\w-]+)+$"
    assert_true(regex.test(email, "ada.lovelace+x@mail.exemple.fr"))
    assert_false(regex.test(email, "ada@@x.fr"))
    ip := "^(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})$"
    assert_eq(regex.search(ip, "192.168.0.1")["groups"], ["192", "168", "0", "1"])
    assert_eq(regex.find_all("\\b[A-ZÉ][a-zé]+\\b", "Alex et Éric vont à Paris"), ["Alex", "Éric", "Paris"])
    long := string.repeat("ab", 3000)
    assert_eq(len(regex.search("(ab)*", long)["text"]), 6000)
    assert_eq(len(regex.search(".*b", long)["text"]), 6000)
    assert_eq(len(regex.search("[ab]+", long)["text"]), 6000)

testing.test("base", t_base)
testing.test("classes", t_classes)
testing.test("quantificateurs", t_quantifieurs)
testing.test("groupes", t_groupes)
testing.test("alternance et ancres", t_alternance_ancres)
testing.test("références arrière et lookahead", t_backref_lookahead)
testing.test("drapeaux", t_drapeaux)
testing.test("match_start / fullmatch", t_match_fullmatch)
testing.test("search start", t_search_start)
testing.test("correspondances vides", t_vides)
testing.test("replace", t_replace)
testing.test("split", t_split)
testing.test("escape / compile", t_escape_compile)
testing.test("erreurs de motif", t_erreurs)
testing.test("cas pratiques", t_pratique)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) regex en échec")
print("REGEX: OK")

# ALEX - tests du module xml (ALEX pur). Lancer depuis la racine : ./alex run tests/test_xml.al
use xml
use io
use os
use testing
from core use len
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises

func t_1():
    d := xml.parse("<livre id=\"7\" t='a&amp;b'><titre>Alex &amp; co</titre><vide/></livre>")
    assert_eq(d["tag"], "livre")
    assert_eq(xml.attr(d, "id"), "7")
    assert_eq(xml.attr(d, "t"), "a&b")
    assert_eq(xml.attr(d, "zz", "dflt"), "dflt")
    assert_eq(xml.text(xml.find(d, "titre")), "Alex & co")
    assert_eq(len(xml.children(d)), 2)
    assert_eq(xml.find(d, "vide")["children"], [])
    assert_null(xml.find(d, "absent"))

testing.test("parse de base", t_1)

func t_2():
    d := xml.parse("<?xml version=\"1.0\"?>\n<!DOCTYPE a>\n<!-- c -->\n<a><!-- x -->t<![CDATA[<raw> & ]]>u</a>\n<!-- fin -->")
    assert_eq(d["tag"], "a")
    assert_eq(xml.text(d), "t<raw> & u")
    assert_eq(d["children"], ["t<raw> & u"])

testing.test("prologue, commentaires, doctype, CDATA", t_2)

func t_3():
    assert_eq(xml.unescape("&lt;&gt;&amp;&quot;&apos;"), "<>&\"'")
    assert_eq(xml.unescape("&#233;&#xE9;&#x1F600;"), "éé😀")
    assert_eq(xml.escape("a<b>&\"c\""), "a&lt;b&gt;&amp;\"c\"")
    assert_eq(xml.escape("\"x\"\n", true), "&quot;x&quot;&#10;")
    assert_raises(() => xml.unescape("&foo;"), "XMLError", "inconnue")
    assert_raises(() => xml.unescape("&amp"), "XMLError")
    assert_raises(() => xml.unescape("&#;"), "XMLError")
    assert_raises(() => xml.unescape("&#xD800;"), "XMLError")

testing.test("entités", t_3)

func t_4():
    d := xml.parse("<a>\n  <b>x</b>\n  <c> y </c>\n</a>")
    assert_eq(len(d["children"]), 2)
    assert_eq(xml.text(xml.find(d, "c")), " y ")
    k := xml.parse("<a> <b/> </a>", true)
    assert_eq(len(k["children"]), 3)

testing.test("espaces", t_4)

func t_5():
    d := xml.parse("<r><i n=\"1\"/><g><i n=\"2\"/></g><i n=\"3\"/></r>")
    assert_eq(len(xml.find_all(d, "i")), 3)
    assert_eq(len(xml.children(d, "i")), 2)
    assert_eq(xml.attr(xml.find_all(d, "i")[1], "n"), "2")

testing.test("navigation", t_5)

func t_6():
    d := xml.parse("<a z=\"1\" b=\"x&quot;y\"><t>1 &lt; 2</t><e/></a>")
    assert_eq(xml.stringify(d), "<a b=\"x&quot;y\" z=\"1\"><t>1 &lt; 2</t><e/></a>")
    assert_eq(xml.parse(xml.stringify(d)), d)
    assert_eq(xml.stringify(xml.element("a"), true), "<?xml version=\"1.0\" encoding=\"UTF-8\"?><a/>")
    e := xml.element("a", {"k": "v"}, ["texte", xml.element("b", null, "x")])
    assert_eq(xml.stringify(e), "<a k=\"v\">texte<b>x</b></a>")
    assert_raises(() => xml.stringify({"tag": "a"}), "XMLError")
    assert_raises(() => xml.stringify(xml.element("a", {"k": 1})), "XMLError")

testing.test("stringify", t_6)

func t_7():
    d := xml.parse("<a><b><c>t</c></b><d/></a>")
    assert_eq(xml.pretty(d), "<a>\n  <b>\n    <c>t</c>\n  </b>\n  <d/>\n</a>\n")
    assert_eq(xml.pretty(d, 4), "<a>\n    <b>\n        <c>t</c>\n    </b>\n    <d/>\n</a>\n")

testing.test("pretty", t_7)

func t_8():
    for bad in ["", "   ", "<a>", "<a></b>", "<a x=1/>", "<a/><b/>", "x<a/>", "<a>&foo;</a>", "<a x=\"1\" x=\"2\"/>", "<a>\n<b></a>", "<a", "<a x=\"1/>", "<!-- x", "<a><![CDATA[x</a>", "<1a/>", "<a x=\"<\"/>", "<a x=\"1\"y=\"2\"/>"]:
        assert_raises(() => xml.parse(bad), "XMLError", "ligne")
    assert_raises(() => xml.parse(3), "TypeError")
    assert_true(xml.is_valid("<a/>"))
    assert_false(xml.is_valid("<a>"))

testing.test("erreurs", t_8)

func t_9():
    d := xml.parse("<é:tag attr=\"😀\">ça va</é:tag>")
    assert_eq(d["tag"], "é:tag")
    assert_eq(xml.attr(d, "attr"), "😀")
    assert_eq(xml.text(d), "ça va")

testing.test("unicode et noms", t_9)

func t_10():
    p := os.join(os.tmp_dir(), "alex_test_xml_" + str(os.pid()) + ".xml")
    d := xml.parse("<a><b k=\"1\">x</b></a>")
    xml.save(p, d)
    assert_eq(xml.load(p), d)
    io.delete_file(p)

testing.test("load / save", t_10)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) xml en échec")
print("XML: OK")

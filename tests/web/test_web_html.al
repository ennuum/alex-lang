# ALEX - tests du paquet web.html. Lancer depuis la racine : ./alex run tests/web/test_web_html.al
use testing
use web.html as html
use web.html.html_escape as esc
use web.html.element as el
use web.html.element_factory as f
use web.html.attributes as at
use web.html.document as dm
use web.html.html_parser as hp
use web.html.html_serializer as ser
use web.html.html_writer as hw
use web.html.html_validate as hval
use web.html.semantic_elements as se
use web.html.metadata as md
use web.html.head as hd
use web.html.body as bd
use web.html.links as ln
use web.html.images as im
use web.html.tables as tb
use web.html.lists as ls
use web.html.forms as fm
use web.html.scripts as js
use web.html.stylesheets as css
use web.html.iframe as fr
use web.html.comment_node as cn
use web.html.raw_html as raw
from core use len
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises

func t_escape():
    assert_eq(esc.escape("<a href=\"x\">'"), "&lt;a href=&quot;x&quot;&gt;&#39;")
    assert_eq(esc.escape_text("a < b & \"c\""), "a &lt; b &amp; \"c\"")
    assert_eq(esc.unescape("caf&eacute; &amp; th&#xE9; &copy fin &notin; &#x1F600;"), "café & thé © fin ∉ 😀")
    assert_eq(esc.unescape("?a=1&copy=2", true), "?a=1&copy=2")
    assert_eq(esc.unescape("&#128;&#0;"), "€\uFFFD")
    assert_eq(esc.entity("hellip"), "…")
    assert_eq(esc.strip_tags("<b>gras</b> &amp; co<script>x<y</script> fin"), "gras & co fin")
    assert_eq(esc.escape_script("x='</script><!--'"), "x='<\\/script><\\!--'")
    assert_eq(esc.escape_json_for_script("{\"a\":\"</script>&\"}"), "{\"a\":\"\\u003c/script\\u003e\\u0026\"}")
    assert_eq(cn.CommentNode("a --> b").to_html(), "<!--a - -> b-->")

testing.test("échappement", t_escape)

func t_tree():
    ul := el.Element("ul", {"class": "menu"})
    ul.append(el.Element("li", null, ["Accueil"])).append(el.Element("li", {"class": "actif", "data_x": 3}, ["Contact & <plus>"]))
    assert_eq(ul.to_html(), "<ul class=\"menu\"><li>Accueil</li><li class=\"actif\" data-x=\"3\">Contact &amp; &lt;plus&gt;</li></ul>")
    assert_eq(ul.find("li.actif").text_content(), "Contact & <plus>")
    assert_true(ul.first_element().closest("ul") == ul)
    div := el.Element("div", {"id": "main"}, [el.Element("p", null, ["un ", el.Element("b", null, "gras")]), ul, el.Element("br")])
    assert_eq(len(div.find_all("ul > li")), 2)
    assert_eq(div.find("li:nth-child(2)").text_content(), "Contact & <plus>")
    assert_true(div.find("p + ul") == ul)
    assert_eq(len(div.find_all("p ~ *")), 2)
    assert_eq(div.find("[data-x=\"3\"]").tag, "li")
    assert_eq(div.find("li:not(.actif)").text_content(), "Accueil")
    assert_eq(div.find("li:last-child").path(), "div#main > ul:nth-child(2) > li:nth-child(2)")
    assert_eq(len(div.find_all("p, br")), 2)
    assert_raises(() => el.Element("br").append("x"), "HtmlError")
    assert_raises(() => el.Element("a b"), "HtmlTagError")
    assert_raises(() => div.find("p >"), "HtmlError")
    c := div.clone()
    assert_eq(c.to_html(), div.to_html())
    b := div.find("b")
    b.unwrap()
    assert_eq(div.find("p").to_html(), "<p>un gras</p>")
    ul.find("li").remove()
    assert_eq(len(ul.children), 1)
    assert_raises(() => ul.append(div), "HtmlError")

testing.test("arbre et sélecteurs", t_tree)

func t_attributes():
    a := at.Attributes({"id": "menu", "class": ["nav", "dark"], "hidden": false, "disabled": true})
    a.add_class("open")
    a.set_style("color", "red")
    a.set_data("user-id", 42)
    a.set_aria("expanded", false)
    assert_eq(a.render(), " id=\"menu\" class=\"nav dark open\" disabled style=\"color: red\" data-user-id=\"42\" aria-expanded=\"false\"")
    assert_true(a.has_class("dark"))
    assert_false(a.has("hidden"))
    a.toggle_class("dark")
    assert_eq(a.classes(), ["nav", "open"])
    assert_eq(a.dataset(), {"user-id": "42"})
    assert_raises(() => a.set("on click", "x"), "HtmlAttributeError")

testing.test("attributs", t_attributes)

func t_document():
    doc := dm.Document("Mon site", "fr")
    doc.body().append(f.h("h1", "Bienvenue"))
    assert_eq(doc.to_html(), "<!DOCTYPE html><html lang=\"fr\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Mon site</title></head><body><h1>Bienvenue</h1></body></html>")
    assert_eq(doc.title(), "Mon site")
    assert_eq(doc.charset(), "utf-8")
    p := doc.pretty()
    assert_true(len(p) > 0)
    assert_eq(f.from_spec(["ul", ["li", "un"], ["li", {"class": "b"}, "deux"]]).to_html(), "<ul><li>un</li><li class=\"b\">deux</li></ul>")
    nav := f.tag_builder("nav")
    assert_eq(nav({"id": "n"}, ["x"]).to_html(), "<nav id=\"n\">x</nav>")
    assert_eq(f.make("p", "texte", {"class": "x"}).to_html(), "<p class=\"x\">texte</p>")
    assert_eq(ser.serialize(el.Element("br"), ser.Options(false, "  ", false, true)), "<br />")

testing.test("document et fabrique", t_document)

func t_parser():
    doc := hp.parse("<title>T &amp; U</title><p>Un<p>Deux &amp; trois<ul><li>a<li>b</ul><table><tr><td>1<td>2</table><script>if (a<b) x='</div>';</script><img src=x alt='y'/></span>")
    assert_eq(doc.title(), "T & U")
    assert_eq(len(doc.find_all("p")), 2)
    assert_eq(len(doc.find_all("li")), 2)
    assert_eq(len(doc.find_all("table > tbody > tr > td")), 2)
    assert_eq(doc.find("script").text_content(), "if (a<b) x='</div>';")
    codes := []
    for i in doc.issues:
        codes = codes + [i.code]
    assert_true("orphan-end-tag" in codes)
    assert_true("missing-doctype" in codes)
    d2 := hp.parse("<!DOCTYPE html><html lang=fr><head><meta charset=utf-8><title>X</title></head><body class=a><h1>Titre<h2>Sous</h2><dl><dt>t<dd>d<dt>t2</dl><select><option>1<option>2</select></body></html>")
    assert_eq(d2.to_html(), "<!DOCTYPE html><html lang=\"fr\"><head><meta charset=\"utf-8\"><title>X</title></head><body class=\"a\"><h1>Titre</h1><h2>Sous</h2><dl><dt>t</dt><dd>d</dd><dt>t2</dt></dl><select><option>1</option><option>2</option></select></body></html>")
    nodes := hp.parse_fragment("<b>gras</b> et <i>italique</i>")
    assert_eq(len(nodes), 3)
    assert_eq(hp.parse_element("<a href='/x?a=1&amp;b=2'>lien</a>").get("href"), "/x?a=1&b=2")
    assert_raises(() => hp.parse("<div></span></div>", true), "HtmlParseError")
    assert_eq(hp.to_text("<p>a &lt; b</p><style>x</style><p>c</p>"), "a < bc")
    rt := hp.parse("<p class=x>a<br>b</p>")
    assert_eq(hp.parse(rt.to_html()).to_html(), rt.to_html())

testing.test("analyseur", t_parser)

func t_sanitize():
    s := hp.sanitize("<p onclick='x()'>ok<script>mal()</script><a href='javascript:x'>l</a><a href=\"https://e.org\">e</a><img src=\"x.png\" alt=a onerror=x></p><style>x</style><iframe src=x></iframe>")
    assert_eq(s, "<p>ok<a>l</a><a href=\"https://e.org\" rel=\"nofollow noopener noreferrer\">e</a><img src=\"x.png\" alt=\"a\"></p>")
    assert_eq(hp.sanitize("<a href=' JaVa\tScRiPt:alert(1)'>x</a>"), "<a>x</a>")
    assert_eq(html.sanitize("<b onclick=x>ok</b><script>mal()</script>"), "<b>ok</b>")

testing.test("assainissement", t_sanitize)

func t_writer():
    w := hw.HtmlWriter(false)
    w.doctype().open("html", {"lang": "fr"}).open("body")
    w.element("h1", {"class": "t"}, "Résultats < 2024")
    w.open("p").text("un ").element("b", null, "gras").close("p")
    w.close_all()
    assert_eq(w.to_string(), "<!DOCTYPE html><html lang=\"fr\"><body><h1 class=\"t\">Résultats &lt; 2024</h1><p>un <b>gras</b></p></body></html>")
    parts := []
    w2 := hw.HtmlWriter(false, (m) => parts.append(m))
    w2.open("div").element("br").text("x").close()
    assert_eq(len(parts), 4)
    assert_raises(() => hw.HtmlWriter().open("div").close("span"), "HtmlError")

testing.test("écriture en flux", t_writer)

func t_validate():
    doc := hp.parse("<html><head></head><body><h1>T</h1><h3>x</h3><img src=a.png><a href='javascript:x()'>l</a><p id=a>1</p><p id=a>2</p><input type=texte name=q><label for=zz>L</label><button></button><iframe src=x sandbox='allow-scripts allow-same-origin foo'></iframe><input type=checkbox disabled=false id=c><label for=c>ok</label><font>f</font><li>x</li></body></html>")
    codes := []
    for i in hval.validate(doc):
        codes = codes + [i.code]
    for code in ["doctype", "html-lang", "charset", "title", "img-alt", "unsafe-url", "duplicate-id", "input-type", "control-label", "button-name", "iframe-title", "iframe-sandbox", "boolean-false", "obsolete-element", "list-item-parent", "heading-order", "label-for"]:
        assert_true(code in codes, "code attendu : " + code)
    assert_false(hval.is_valid(doc))
    assert_raises(() => hval.check(doc), "HtmlValidationError")
    good := bd.page("Accueil", [se.h1("Titre"), se.p("Texte")], "fr", null, null, "Description")
    assert_true(hval.is_valid(good))
    assert_eq(len(hval.validate(good)), 0)

testing.test("validation", t_validate)

func t_builders():
    art := se.article({"id": "a1"}, [se.h2("T"), se.p(["x ", se.strong("y")]), se.time("2024-05-01", "1er mai"), se.code_block("print(1)", "alex")])
    assert_eq(art.to_html(), "<article id=\"a1\"><h2>T</h2><p>x <strong>y</strong></p><time datetime=\"2024-05-01\">1er mai</time><pre><code class=\"language-alex\">print(1)</code></pre></article>")
    assert_raises(() => se.heading(7, "x"), "HtmlError")
    assert_eq(html.render(md.open_graph({"title": "T", "image": ["a.png", "b.png"]})), "<meta property=\"og:title\" content=\"T\"><meta property=\"og:image\" content=\"a.png\"><meta property=\"og:image\" content=\"b.png\">")
    assert_eq(md.json_ld({"name": "</script>"}).to_html(), "<script type=\"application/ld+json\">{\"name\":\"\\u003c/script\\u003e\"}</script>")
    doc := dm.Document("T")
    hd.add_stylesheet(doc, "/a.css")
    hd.add_stylesheet(doc, "/a.css")
    hd.set_description(doc, "D1")
    hd.set_description(doc, "D2")
    assert_eq(len(doc.find_all("link[rel=stylesheet]")), 1)
    assert_eq(hd.get_meta(doc, "description"), "D2")
    assert_eq(ln.mailto("a@b.org", null, "Une question ?").get("href"), "mailto:a@b.org?subject=Une%20question%20%3F")
    assert_eq(ln.tel("+33 1 23").get("href"), "tel:+33123")
    assert_eq(ln.external("https://x.org").get("rel"), "noopener noreferrer")
    page := hp.parse("<base href='https://e.org/a/'><a href='b'>b</a><img src='/i.png' alt=''>")
    ln.absolutize(page)
    assert_eq(ln.hrefs(page), ["https://e.org/a/b"])
    assert_eq(im.img("/c.jpg", "Chat", 800, 600).to_html(), "<img src=\"/c.jpg\" alt=\"Chat\" width=\"800\" height=\"600\" loading=\"lazy\" decoding=\"async\">")
    assert_raises(() => im.img("/c.jpg", null), "HtmlError")
    assert_eq(im.srcset([("a.jpg", 400), ("b.jpg", 2.0)]), "a.jpg 400w, b.jpg 2x")
    assert_eq(im.data_uri([137, 80, 78, 71]), "data:image/png;base64,iVBORw==")
    t := tb.from_rows([["Ville", "Habitants"], ["Paris", 2133111]], "Villes")
    assert_eq(tb.to_records(t), [{"Ville": "Paris", "Habitants": "2133111"}])
    assert_eq(ls.to_tree(ls.tree([("Fruits", ["Pomme", "Poire"]), "Pain"])), [("Fruits", ["Pomme", "Poire"]), "Pain"])
    assert_eq(ls.dl_to_dict(ls.dl({"A": "a", "B": ["b1", "b2"]})), {"A": "a", "B": "b1"})
    assert_eq(js.script("/a.js").to_html(), "<script src=\"/a.js\" defer></script>")
    assert_eq(js.inline("x='</script>'").to_html(), "<script>x='<\\/script>'</script>")
    assert_eq(css.rules({"body": {"margin": 0, "font_family": "system-ui"}}), "body { margin: 0; font-family: system-ui }")
    assert_eq(fr.iframe("https://e.org/w", "Météo").get("sandbox"), "")
    assert_raises(() => fr.iframe("x", "t", ["allow-scripts", "allow-same-origin"]), "HtmlError")
    assert_raises(() => fr.iframe("x", null), "HtmlError")
    assert_eq(raw.RawHtml("<b>x</b>").text_content(), "x")

testing.test("constructeurs spécialisés", t_builders)

func t_forms():
    f1 := fm.form("/i", "post", [fm.csrf_field("tok"), fm.field("Courriel", fm.email("email", null, true), "Aide"), fm.select_field("Pays", "pays", [("fr", "France"), ("be", "Belgique")], "be"), fm.checkbox("cgu", "oui", false, "J'accepte"), fm.radio_group("Taille", "t", ["S", "M"], "M"), fm.textarea("msg", "salut"), fm.file("doc"), fm.submit()])
    assert_eq(f1.get("enctype"), "multipart/form-data")
    assert_eq(fm.form_data(f1), [("csrf_token", "tok"), ("email", ""), ("pays", "be"), ("t", "M"), ("msg", "salut")])
    assert_eq(fm.fill(f1, {"email": "zoe@e.org", "cgu": true, "pays": "fr"}), 3)
    assert_eq(fm.form_data(f1), [("csrf_token", "tok"), ("email", "zoe@e.org"), ("pays", "fr"), ("cgu", "oui"), ("t", "M"), ("msg", "salut")])
    e := fm.set_error(f1, "email", "Déjà pris")
    assert_eq(e.get("aria-invalid"), "true")
    assert_true(e.get("aria-describedby") != null)
    fm.clear_errors(f1)
    assert_null(f1.find("p.field-error"))
    assert_raises(() => fm.form("/x", "put"), "HtmlError")
    assert_raises(() => fm.input_element("texte"), "HtmlError")
    assert_true(hval.is_valid(f1))

testing.test("formulaires", t_forms)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) web.html en échec")
print("web.html : OK")

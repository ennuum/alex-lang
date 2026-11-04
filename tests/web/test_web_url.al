# ALEX - tests du paquet web.url. Lancer depuis la racine : ./alex run tests/web/test_web_url.al
use testing
use web.url as url
use web.url.percent_encoding as pe
use web.url.form_url_encoding as form
use web.url.host as host
use web.url.port as port
use web.url.path as path
use web.url.query as query
use web.url.query_params as qp
use web.url.fragment as fragment
use web.url.relative_url as rel
use web.url.url_normalization as norm
use web.url.url_builder as ub
use web.url.url_errors as ue
from core use len
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises

func t_percent():
    assert_eq(pe.encode("a b/é"), "a%20b%2F%C3%A9")
    assert_eq(pe.encode("a b/é", "/"), "a%20b/%C3%A9")
    assert_eq(pe.encode_path("/a b/?x"), "/a%20b/%3Fx")
    assert_eq(pe.encode_component("a&b=c d~"), "a%26b%3Dc%20d~")
    assert_eq(pe.decode("caf%C3%A9+noir"), "café+noir")
    assert_eq(pe.decode("caf%C3%A9+noir", true), "café noir")
    assert_eq(pe.normalize("%7e%2f"), "~%2F")
    assert_eq(pe.decode("%FF%41"), "�A")
    assert_raises(() => pe.decode("%G1", false, true), "UrlEncodingError")
    assert_raises(() => pe.decode("%FF", false, true), "UrlEncodingError")
    assert_true(pe.is_well_formed("a%20b"))
    assert_false(pe.is_well_formed("a%2"))

testing.test("encodage pour cent", t_percent)

func t_form():
    assert_eq(form.encode({"q": "chat noir", "page": 2}), "q=chat+noir&page=2")
    assert_eq(form.encode({"tag": ["a", "b"], "ok": true, "vide": null}), "tag=a&tag=b&ok=true&vide=")
    assert_eq(form.decode("q=chat+noir&x&y=%C3%A9&&"), [("q", "chat noir"), ("x", ""), ("y", "é")])
    assert_eq(form.decode_dict("a=1&a=2&b=3"), {"a": "2", "b": "3"})
    assert_eq(form.decode_multi("a=1&a=2&b=3"), {"a": ["1", "2"], "b": ["3"]})

testing.test("application/x-www-form-urlencoded", t_form)

func t_host():
    x := host.parse("Bücher.Example")
    assert_eq(x.kind, "domain")
    assert_eq(x.text, "xn--bcher-kva.example")
    assert_eq(host.to_ascii("münchen.de"), "xn--mnchen-3ya.de")
    assert_eq(host.to_ascii("日本語.jp"), "xn--wgv71a119e.jp")
    assert_eq(host.to_unicode("xn--wgv71a119e.jp"), "日本語.jp")
    assert_eq(host.parse("[2001:DB8::0:1]").serialize(), "[2001:db8::1]")
    assert_eq(host.parse("[2001:db8:0:0:1:0:0:1]").serialize(), "[2001:db8::1:0:0:1]")
    assert_eq(host.parse("[::ffff:192.168.0.1]").serialize(), "[::ffff:c0a8:1]")
    assert_eq(host.parse("0x7f.1").text, "127.0.0.1")
    assert_eq(host.parse("192.168.1").text, "192.168.0.1")
    assert_true(host.is_ip("::1"))
    assert_false(host.is_ipv4("a.b"))
    assert_true(host.parse("localhost").is_loopback())
    assert_raises(() => host.parse("a b"), "UrlHostError")
    assert_raises(() => host.parse("1.2.3.256"), "UrlHostError")
    assert_raises(() => host.parse("[1::2::3]"), "UrlHostError")
    assert_true(host.is_valid_domain("exemple.org"))
    assert_false(host.is_valid_domain("exa_mple.org"))

testing.test("hôtes : IDNA, IPv4, IPv6", t_host)

func t_port_path():
    assert_eq(port.parse("8080"), 8080)
    assert_null(port.parse(""))
    assert_raises(() => port.parse("70000"), "UrlPortError")
    assert_raises(() => port.parse("8a"), "UrlPortError")
    assert_eq(port.serialize("http", 80), "")
    assert_eq(port.effective("https", null), 443)
    assert_eq(path.remove_dot_segments("/a/b/c/./../../g"), "/a/g")
    assert_eq(path.remove_dot_segments("mid/content=5/../6"), "mid/6")
    assert_eq(path.join("/api/", "v1", "/users"), "/api/v1/users")
    assert_eq(path.decoded_segments("/docs/caf%C3%A9"), ["docs", "café"])
    assert_eq(path.from_segments(["docs", "a b", "x/y"]), "/docs/a%20b/x%2Fy")
    assert_eq(path.relative("/a/b/c", "/a/d/e"), "../d/e")
    assert_eq(path.parent("/a/b/"), "/a/")
    assert_true(path.starts_with_segments("/api/x", "/api"))
    assert_false(path.starts_with_segments("/apix", "/api"))

testing.test("ports et chemins", t_port_path)

func t_query():
    p := qp.parse("q=chat+noir&tag=a&tag=b")
    assert_eq(p.get("q"), "chat noir")
    assert_eq(p.get_all("tag"), ["a", "b"])
    assert_eq(p.get_int("page", 1), 1)
    p.set("q", "chien")
    p.add("tag", "c")
    p.remove("tag", "a")
    assert_eq(p.to_string(), "q=chien&tag=b&tag=c")
    assert_raises(() => qp.parse("n=x").get_int("n"), "ValueError")
    assert_eq(query.merge("a=1&b=2", {"b": 3, "c": 4, "a": null}), "b=3&c=4")
    assert_eq(query.sorted("b=2&a=1"), "a=1&b=2")
    assert_eq(fragment.to_element_id("Résumé 2024 !"), "résumé-2024")

testing.test("requête et paramètres", t_query)

func t_parse():
    u := url.parse("https://Bücher.example:443/a b/./c?x=1&y=é#top")
    assert_eq(u.href(), "https://xn--bcher-kva.example/a%20b/c?x=1&y=%C3%A9#top")
    assert_eq(u.effective_port(), 443)
    assert_eq(u.param("y"), "é")
    assert_eq(u.origin(), "https://xn--bcher-kva.example")
    assert_eq(u.target(), "/a%20b/c?x=1&y=%C3%A9")
    assert_eq(url.parse("HTTP://user:pa ss@h:8080").href(), "http://user:pa%20ss@h:8080/")
    assert_eq(url.parse("http:example.com/x").href(), "http://example.com/x")
    assert_eq(url.parse("mailto:Joe@Example.org").href(), "mailto:Joe@Example.org")
    assert_eq(url.parse("urn:isbn:0451450523").path, "isbn:0451450523")
    assert_eq(url.parse("  http://h/\ta\nb  ").href(), "http://h/ab")
    assert_eq(url.parse("http://h\\a\\b").href(), "http://h/a/b")
    assert_eq(url.parse("/docs", "http://h/a/b").href(), "http://h/docs")
    assert_null(url.try_parse("http://[::1"))
    assert_null(url.try_parse("relatif/sans/base"))
    assert_true(url.is_web_url("https://exemple.org"))
    assert_false(url.is_web_url("ftp://exemple.org"))
    assert_raises(() => url.parse("http://"), "UrlHostError")
    assert_raises(() => url.parse("1http://x"), "UrlError")

testing.test("analyse d'URL", t_parse)

func t_with():
    u := url.parse("http://h/a?x=1#f")
    assert_eq(u.with_param("page", 2).href(), "http://h/a?x=1&page=2#f")
    assert_eq(u.without_param("x").href(), "http://h/a#f")
    assert_eq(u.with_host("::1").href(), "http://[::1]/a?x=1#f")
    assert_eq(u.with_port(8080).with_path("b c").href(), "http://h:8080/b%20c?x=1#f")
    assert_eq(u.with_scheme("https").with_port(443).href(), "https://h/a?x=1#f")
    assert_eq(u.with_userinfo("zoé", "s3cr3t").redacted(), "http://zo%C3%A9:***@h/a?x=1#f")
    assert_eq(u.without_fragment().without_query().href(), "http://h/a")
    assert_eq(u.with_segments(["x/y", "z"]).path, "/a/x%2Fy/z")
    assert_eq(url.from_parts("https", "exemple.org", null, "/a", {"q": "chat noir"}, "f").href(), "https://exemple.org/a?q=chat+noir#f")
    assert_eq(str(u), "http://h/a?x=1#f")

testing.test("copies modifiées (with_*)", t_with)

func t_rfc3986():
    base := "http://a/b/c/d;p?q"
    cases := [["g:h", "g:h"], ["g", "http://a/b/c/g"], ["./g", "http://a/b/c/g"], ["g/", "http://a/b/c/g/"], ["/g", "http://a/g"], ["//g", "http://g/"], ["?y", "http://a/b/c/d;p?y"], ["g?y", "http://a/b/c/g?y"], ["#s", "http://a/b/c/d;p?q#s"], ["g#s", "http://a/b/c/g#s"], [";x", "http://a/b/c/;x"], ["", "http://a/b/c/d;p?q"], [".", "http://a/b/c/"], ["..", "http://a/b/"], ["../g", "http://a/b/g"], ["../..", "http://a/"], ["../../../g", "http://a/g"], ["/./g", "http://a/g"], ["/../g", "http://a/g"], ["g.", "http://a/b/c/g."], ["..g", "http://a/b/c/..g"], ["./../g", "http://a/b/g"], ["g/../h", "http://a/b/c/h"], ["g;x=1/../y", "http://a/b/c/y"], ["g?y/./x", "http://a/b/c/g?y/./x"], ["g#s/../x", "http://a/b/c/g#s/../x"]]
    for c in cases:
        assert_eq(rel.resolve(base, c[0]), c[1], "résolution de « " + c[0] + " »")
    assert_eq(rel.relativize("https://h/a/b/c", "https://h/a/d?x=1"), "../d?x=1")
    assert_eq(rel.relativize("https://h/a", "http://h/a"), "http://h/a")
    assert_eq(rel.relativize("https://h/a", "https://o/a"), "//o/a")
    assert_true(rel.is_relative("../x"))

testing.test("résolution relative (RFC 3986 §5.4)", t_rfc3986)

func t_normalize():
    assert_eq(norm.normalize("HTTP://Exemple.ORG:80/a/./b/../%7euser/?"), "http://exemple.org/a/~user/?")
    assert_eq(norm.normalize("http://h/a/?b=2&a=1&utm_source=x#x", norm.aggressive()), "http://h/a/?a=1&b=2")
    assert_true(norm.equivalent("http://h:80/a", "HTTP://H/a"))
    assert_false(norm.equivalent("http://h/a", "http://h/b"))
    assert_eq(norm.normalize("http://www.h/index.html", norm.Options(false, false, false, false, true, true)), "http://h/")

testing.test("normalisation", t_normalize)

func t_builder():
    b := ub.UrlBuilder("https", "api.exemple.org")
    b.segment("v1").segment("utilisateurs").segment("Zoé Martin")
    b.param("champs", "nom,email").param("tag", ["a", "b"]).fragment("résumé")
    assert_eq(b.build().href(), "https://api.exemple.org/v1/utilisateurs/Zo%C3%A9%20Martin?champs=nom%2Cemail&tag=a&tag=b#r%C3%A9sum%C3%A9")
    b2 := ub.from_url("http://h/a%2Fb?x=1")
    assert_eq(b2.build_string(), "http://h/a%2Fb?x=1")
    assert_eq(b2.clear_params().port(8080).path("/b/").build_string(), "http://h:8080/b/")
    assert_raises(() => ub.UrlBuilder("https").build(), "UrlError")

testing.test("UrlBuilder", t_builder)

func t_errors():
    assert_true(ue.is_url_error("UrlHostError"))
    assert_false(ue.is_url_error("ValueError"))
    assert_eq(len(ue.kinds()), 5)

testing.test("erreurs", t_errors)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) web.url en échec")
print("web.url : OK")

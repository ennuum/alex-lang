# ALEX - tests du paquet web.http. Lancer depuis la racine : ./alex run tests/web/test_web_http.al
use testing
use web.http as http
use web.http.method as method
use web.http.status_code as status
use web.http.version as version
use web.http.headers as hd
use web.http.header_name as hn
use web.http.header_value as hv
use web.http.content_type as ct
use web.http.content_length as cl
use web.http.date_header as dh
use web.http.request_target as rt
use web.http.message_body as mb
use web.http.request as rq
use web.http.response as rs
use web.http.protocol_parser as pp
use web.http.protocol_writer as pw
use web.http.http_errors as he
from core use len
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises

func status_of(fn):
    try:
        fn()
        return 0
    catch e:
        return he.status_for(e)

func t_basics():
    assert_eq(method.normalize("get"), "GET")
    assert_true(method.is_idempotent("PUT"))
    assert_false(method.is_safe("POST"))
    assert_eq(method.after_redirect("POST", 303), "GET")
    assert_eq(method.after_redirect("POST", 307), "POST")
    assert_eq(method.allow_header(["GET", "POST"]), "GET, POST, HEAD")
    assert_raises(() => method.check("GE T"), "HttpMethodError")
    assert_eq(status.reason(404), "Not Found")
    assert_eq(status.describe(418), "418 I'm a teapot")
    assert_eq(status.reason(499), "Client Error")
    assert_false(status.allows_body(304))
    assert_true(status.is_retryable(503))
    v := version.parse("HTTP/1.1")
    assert_true(v.is_http11())
    assert_true(version.HTTP_1_0 < v)
    assert_false(version.is_supported("HTTP/2"))
    assert_eq(status_of(() => version.require_supported("HTTP/2")), 505)

testing.test("méthodes, statuts, versions", t_basics)

func t_headers():
    h := hd.Headers({"Content-Type": "text/html", "X-Ids": ["1", "2"]})
    h.add("Set-Cookie", "a=1")
    h.add("set-cookie", "b=2")
    h.set("Content-Length", 42)
    assert_eq(h.get("content-type"), "text/html")
    assert_eq(h.get_all("SET-COOKIE"), ["a=1", "b=2"])
    assert_eq(h.get_list("x-ids"), ["1", "2"])
    assert_eq(h.get_int("content-length"), 42)
    assert_eq(h.to_dict()["set-cookie"], ["a=1", "b=2"])
    assert_eq(h.redacted().get("set-cookie"), "***")
    assert_eq(h.wire_size(), len(h.to_wire()))
    h2 := hd.Headers({"Connection": "keep-alive, X-Secret", "X-Secret": "1", "Keep-Alive": "timeout=5", "Accept": "*/*"})
    assert_eq(h2.end_to_end().names(), ["Accept"])
    assert_raises(() => h.add("X", "a\r\nInjected: 1"), "HttpHeaderError")
    assert_raises(() => h.add("Mauvais Nom", "x"), "HttpHeaderError")
    assert_eq(hn.canonical("www-authenticate"), "WWW-Authenticate")
    assert_eq(hn.canonical("x-request-id"), "X-Request-Id")
    p := hd.parse_lines("A: 1\r\nB:  deux  \r\n")
    assert_eq(p.get("b"), "deux")
    assert_raises(() => hd.parse_lines("A: 1\r\n  repli\r\n"), "HttpHeaderError")

testing.test("en-têtes", t_headers)

func t_values():
    assert_eq(hv.parse_parameters("text/html; charset=\"utf-8\""), ("text/html", {"charset": "utf-8"}))
    assert_eq(hv.split_list("a, \"b, c\", d"), ["a", "\"b, c\"", "d"])
    assert_eq(hv.parse_quality_list("br;q=0.5, gzip, *;q=0"), [("gzip", 1.0), ("br", 0.5), ("*", 0.0)])
    assert_eq(hv.best_match("fr-CA, fr;q=0.9, en;q=0.5", ["en", "fr"]), "fr")
    assert_eq(hv.best_match("text/*", ["application/json", "text/html"]), "text/html")
    assert_eq(hv.parse_directives("max-age=60, no-store, private=\"a, b\""), {"max-age": "60", "no-store": null, "private": "a, b"})
    assert_eq(hv.parse_parameters("attachment; filename*=UTF-8''caf%C3%A9.pdf; filename=\"cafe.pdf\"")[1]["filename"], "café.pdf")
    assert_eq(hv.format_parameters("attachment", {"filename": "café.pdf"}), "attachment; filename*=UTF-8''caf%C3%A9.pdf")
    assert_eq(hv.unquote("\"a \\\"b\\\"\""), "a \"b\"")
    assert_true(hv.list_contains("keep-alive, Upgrade", "upgrade"))

testing.test("valeurs d'en-têtes", t_values)

func t_types_dates():
    m := ct.parse("Text/HTML; Charset=\"UTF-8\"")
    assert_eq(m.essence(), "text/html")
    assert_eq(m.charset(), "utf-8")
    assert_true(m.matches("text/*"))
    assert_true(ct.parse("application/ld+json").is_json())
    assert_eq(str(ct.text("html")), "text/html; charset=utf-8")
    assert_eq(ct.guess("photo.JPG"), "image/jpeg")
    assert_eq(ct.guess("x.unknown"), "application/octet-stream")
    assert_eq(ct.guess_with_charset("a.css"), "text/css; charset=utf-8")
    assert_raises(() => ct.parse("texte"), "HttpHeaderError")
    assert_eq(cl.parse("42, 42"), 42)
    assert_eq(status_of(() => cl.parse("-1")), 400)
    assert_eq(status_of(() => cl.parse("1, 2")), 400)
    assert_eq(cl.of("été"), 5)
    assert_eq(dh.format(784111777), "Sun, 06 Nov 1994 08:49:37 GMT")
    assert_eq(dh.parse("Sun, 06 Nov 1994 08:49:37 GMT"), 784111777)
    assert_eq(dh.parse("Sunday, 06-Nov-94 08:49:37 GMT"), 784111777)
    assert_eq(dh.parse("Sun Nov  6 08:49:37 1994"), 784111777)
    assert_null(dh.parse("hier"))
    assert_null(dh.parse("Sun, 31 Feb 1994 08:49:37 GMT"))
    assert_eq(dh.retry_after_seconds("120"), 120)
    assert_eq(dh.retry_after_seconds("Sun, 06 Nov 1994 08:49:37 GMT", 784111700), 77)

testing.test("types de médias, longueurs, dates", t_types_dates)

func t_target():
    t := rt.parse("/docs/caf%C3%A9?page=2")
    assert_eq(t.form, "origin")
    assert_eq(t.decoded_path(), "/docs/café")
    assert_eq(t.params().get_int("page"), 2)
    assert_eq(rt.parse("/a/b/../c").normalized_path(), "/a/c")
    assert_eq(rt.parse("example.org:443", "CONNECT").host, "example.org")
    assert_eq(rt.parse("*", "OPTIONS").form, "asterisk")
    assert_eq(rt.parse("http://h:8080/p?q", "GET").port, 8080)
    assert_eq(status_of(() => rt.parse("*", "GET")), 400)
    assert_eq(status_of(() => rt.parse("/" + "a" * 9000)), 414)
    assert_eq(status_of(() => rt.parse("/a b")), 400)
    assert_eq(rt.build("/a b", {"q": "x y"}), "/a%20b?q=x+y")

testing.test("cible de requête", t_target)

func t_body():
    assert_eq(mb.encode_chunked("Bonjour", 4), "4\r\nBonj\r\n3\r\nour\r\n0\r\n\r\n")
    r := mb.decode_chunked("4\r\nBonj\r\n3\r\nour\r\n0\r\nX-T: 1\r\n\r\nSUITE")
    assert_eq(r.body, "Bonjour")
    assert_eq(r.consumed, 30)
    assert_eq(r.trailers.get("x-t"), "1")
    d := mb.ChunkedDecoder()
    assert_eq(d.feed("4\r\nBo"), "Bo")
    assert_eq(d.feed("nj\r\n0\r\n\r\n"), "nj")
    assert_true(d.done)
    assert_eq(status_of(() => mb.decode_chunked("zz\r\n")), 400)
    assert_eq(status_of(() => mb.decode_chunked("4\r\nabcdX")), 400)
    assert_eq(status_of(() => mb.decode_chunked("10\r\n" + "a" * 16 + "\r\n0\r\n\r\n", 8)), 413)
    assert_eq(mb.json_body({"ok": true, "b": [1, "x"]}), ("{\"ok\":true,\"b\":[1,\"x\"]}", "application/json"))
    assert_eq(mb.response_framing("HEAD", 200, hd.Headers({"Content-Length": "5"})), "none")
    assert_eq(mb.response_framing("GET", 200, hd.Headers()), "close")
    assert_eq(status_of(() => mb.request_framing(hd.Headers({"Transfer-Encoding": "gzip"}))), 400)
    assert_eq(status_of(() => mb.request_framing(hd.Headers({"Transfer-Encoding": "gzip, chunked"}))), 501)

testing.test("corps et chunked", t_body)

func t_messages():
    req := rq.Request("POST", "/articles?brouillon=1", {"Host": "exemple.org", "Content-Type": "application/json", "Cookie": "a=1; b=\"2\"", "Authorization": "Basic dXNlcjpwYXNz", "Accept": "application/json"}, "{\"titre\":\"Été\"}")
    assert_eq(req.path(), "/articles")
    assert_eq(req.query_param("brouillon"), "1")
    assert_eq(req.json()["titre"], "Été")
    assert_eq(req.url().href(), "http://exemple.org/articles?brouillon=1")
    assert_eq(req.cookies(), {"a": "1", "b": "2"})
    assert_eq(req.basic_auth(), ("user", "pass"))
    assert_true(req.accepts("application/json"))
    assert_false(req.accepts("text/html"))
    assert_eq(rq.basic_auth_header("user", "pass"), "Basic dXNlcjpwYXNz")
    f := rq.Request("POST", "/f", {"Host": "h", "Content-Type": "application/x-www-form-urlencoded"}, "a=1&b=%C3%A9")
    assert_eq(f.param("b"), "é")
    r := rs.json({"id": 7}, 201)
    r.set_cookie("sid", "abc def", 3600, "/", null, true, true, "Lax")
    assert_eq(r.header("set-cookie"), "sid=abc%20def; Max-Age=3600; Path=/; Secure; HttpOnly; SameSite=Lax")
    assert_eq(rs.parse_set_cookie("sid=x; Path=/; HttpOnly")["attributes"]["httponly"], true)
    assert_eq(rs.redirect("/a b", 301).location(), "/a%20b")
    assert_raises(() => rs.redirect("/x", 200), "HttpError")
    assert_eq(rs.error(404, "absent").body, "404 Not Found\nabsent\n")
    assert_raises(() => rs.error(500).raise_for_status(), "HttpStatusError")

testing.test("requêtes et réponses", t_messages)

func t_parser():
    p := pp.RequestParser()
    reqs := p.feed("GET /a HTTP/1.1\r\nHost: h\r\n\r\nPOST /b HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0")
    assert_eq(len(reqs), 1)
    reqs = p.feed("\r\n\r\n\r\nGET /c HTTP/1.1\r\nHost: h\r\n\r\n")
    assert_eq(len(reqs), 2)
    assert_eq(reqs[0].body, "abc")
    assert_eq(reqs[1].target, "/c")
    bad := ["GET / HTTP/1.1\r\n\r\n", "GET  / HTTP/1.1\r\nHost: h\r\n\r\n", "POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n", "GET / HTTP/1.1\r\nHost : h\r\n\r\n", "GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n", "GET / HTTP/1.1\r\nHost: h\r\nX: a\r\n b\r\n\r\n"]
    for b in bad:
        assert_eq(status_of(() => http.parse_request(b)), 400, "refus de " + b)
    assert_eq(status_of(() => http.parse_request("GET / HTTP/2.0\r\nHost: h\r\n\r\n")), 505)
    lim := http.limits(20, 100, 3, 10)
    assert_eq(status_of(() => http.parse_request("GET /" + "a" * 50 + " HTTP/1.1\r\n\r\n", lim)), 414)
    assert_eq(status_of(() => http.parse_request("GET / HTTP/1.1\r\nHost: h\r\nA: 1\r\nB: 2\r\nC: 3\r\n\r\n", lim)), 431)
    assert_eq(status_of(() => http.parse_request("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 11\r\n\r\nhello world", lim)), 413)
    r := http.parse_response("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.0 200 OK\r\n\r\ncorps jusqu'à la fermeture")
    assert_eq(r.status, 200)
    assert_eq(r.body, "corps jusqu'à la fermeture")
    h := http.parse_response("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n", "HEAD")
    assert_eq(h.body, "")
    rp := pp.ResponseParser("GET")
    rp.feed("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc")
    assert_raises(() => rp.finish(), "HttpParseError")

testing.test("analyseur incrémental", t_parser)

func t_writer():
    req := http.parse_request("GET /bonjour?nom=Zo%C3%A9 HTTP/1.1\r\nHost: h\r\n\r\n")
    wire := http.write_response(http.json({"salut": req.query_param("nom")}), req)
    back := http.parse_response(wire)
    assert_eq(back.json_value()["salut"], "Zoé")
    assert_eq(back.header("content-length"), "16")
    assert_true(back.headers.has("date"))
    r := pw.prepare_response(rs.text("x"), "HEAD", "HTTP/1.0", true)
    assert_eq(r.version, "HTTP/1.0")
    assert_eq(r.header("connection"), "keep-alive")
    assert_eq(pw.write_response(r, "HEAD"), pw.write_response_head(r))
    nc := pw.prepare_response(rs.Response(304, "ignoré"), "GET", "HTTP/1.1", true)
    assert_eq(nc.body, "")
    assert_null(nc.header("content-length"))
    q := rq.Request("POST", "/x", {"Host": "h"}, "abc")
    assert_eq(http.write_request(q), "POST /x HTTP/1.1\r\nHost: h\r\nContent-Length: 3\r\n\r\nabc")
    assert_raises(() => pw.request_line("GET", "/a b"), "HttpError")

testing.test("écriture des messages", t_writer)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) web.http en échec")
print("web.http : OK")

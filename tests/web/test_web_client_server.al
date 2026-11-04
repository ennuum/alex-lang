# ALEX - tests de web.server et web.client ensemble : un serveur web.server dans un fil, le client web.client et
# des connexions TCP brutes dans le fil principal (pipelining, requêtes malformées, limites, délais, arrêt
# propre), puis HTTPS avec un certificat auto-signé si OpenSSL et l'outil openssl sont présents.
# Lancer depuis la racine : ./alex run tests/web/test_web_client_server.al
use testing
use os
use io
use time
use concurrency.thread as thread
use network.tcp as tcp
use web.server as server
use web.server.request_dispatch as rd
use web.server.server_limits as sl
use web.server.timeout as st
use web.server.tls_server as ts
use web.server.static_files as sf
use web.client as http
use web.client.http_client as hc
use web.client.client_errors as ce
use web.client.retry_policy as rp
use web.http.protocol_parser as pp
use web.http.response as rs
from core use len
from testing use assert_eq, assert_true, assert_false, assert_null, assert_raises

DIR := os.join(os.tmp_dir(), "alex_web_test_" + str(os.pid()))
ROOT := os.join(DIR, "public")
SRV := [null]
FLAKY := [0]

# ---------------------------------------------------------------- application de test

func boom(req):
    raise("ValueError", "panne volontaire")

func stop_handler(req):
    SRV[0].stop()
    return "arrêt"

func flaky(req):
    FLAKY[0] = FLAKY[0] + 1
    if FLAKY[0] % 2 == 1:
        r := rs.error(503)
        r.headers.set("Retry-After", "0")
        return r
    return "réussi après reprise"

func slow(req):
    time.sleep(0.4)
    return "lent"

func set_cookie(req):
    r := rs.text("ok")
    r.set_cookie("sid", "xyz", 3600)
    return r

func make_app():
    app := server.App()
    app.middleware(rd.request_id())
    app.middleware(rd.compress(64))
    app.get("/", (req) => "<h1>Accueil</h1>")
    app.get("/articles/{id:int}", (req) => {"id": req.route_params["id"], "q": req.query_param("q")}, "article")
    app.post("/echo", (req) => (req.text(), 201, {"X-Echo": "1"}))
    app.post("/json", (req) => req.json())
    app.post("/form", (req) => req.form().to_dict())
    app.post("/upload", (req) => {"type": req.header("content-type")[0:19], "taille": len(req.body)})
    app.get("/redir", (req) => rs.redirect("/", 302))
    app.post("/see-other", (req) => rs.redirect("/methode", 303))
    app.get("/methode", (req) => req.method)
    app.get("/boucle", (req) => rs.redirect("/boucle", 302))
    app.get("/big", (req) => "x" * 5000)
    app.get("/cookie", set_cookie)
    app.get("/lire-cookie", (req) => req.cookie("sid", "aucun"))
    app.get("/boom", boom)
    app.get("/flaky", flaky)
    app.get("/slow", slow)
    app.get("/absent-abort", (req) => server.abort(410, "parti"))
    app.get("/stop", stop_handler)
    app.get("/fichiers/{chemin:path}", (req) => req.route_params["chemin"])
    app.get("/nom", (req) => req.state["route_name"] if "route_name" in req.state else "-", "nom")
    app.static("/static", ROOT, null, true)
    return app

func serve_main():
    srv := server.Server(make_app(), server.config("127.0.0.1", 0)).start()
    SRV[0] = srv
    thread.send(srv.port())
    srv.serve_forever()
    return srv.errors

func serve_limited():
    app := server.App()
    app.get("/", (req) => "racine " + req.version)
    app.post("/echo", (req) => (req.text(), 201))
    app.get("/slow", slow)
    app.get("/stop", stop_handler)
    cfg := server.config("127.0.0.1", 0)
    cfg.limits = sl.Limits(256, 1024, 20, 100, 4, 2, 16)
    cfg.timeouts = st.Timeouts(1.0, 2.0, 1.5, 5.0, 5.0, 3.0)
    cfg.keep_alive.max_requests = 2
    cfg.allowed_hosts = ["h", "127.0.0.1"]
    srv := server.Server(app, cfg).start()
    SRV[0] = srv
    thread.send(srv.port())
    srv.serve_forever()
    return srv.stats()

func serve_tls():
    app := server.App()
    app.get("/", (req) => {"secure": req.secure, "scheme": req.state["scheme"]})
    cfg := server.config("127.0.0.1", 0)
    cfg.tls = ts.development_certificate(os.join(DIR, "certs"))
    srv := server.Server(app, cfg).start()
    thread.send(srv.port())
    srv.serve(2, 20)
    return srv.metrics.tls_handshake_failures

# ---------------------------------------------------------------- outils

func responses(c, n, timeout=3.0):
    p := pp.ResponseParser("GET")
    out := []
    while len(out) < n:
        d := c.socket.recv(65536, timeout)
        if d == "":
            for m in p.finish():
                out = out + [m]
            break
        for m in p.feed(d):
            out = out + [m]
    return out

func closed_by_server(c, timeout=3.0):
    try:
        return c.socket.recv(100, timeout) == ""
    catch e:
        return e.type == "NetworkError"

func raw_status(port, data):
    c := tcp.connect("127.0.0.1", port, 3.0)
    c.write(data)
    rs1 := responses(c, 1, 5.0)
    c.close()
    if len(rs1) == 0:
        return 0
    return rs1[0].status

# ---------------------------------------------------------------- tests

if thread.is_main():
    os.mkdir_all(os.join(ROOT, "docs"))
    io.write_file(os.join(ROOT, "site.css"), "body{color:red}\n")
    io.write_file(os.join(ROOT, "docs", "data.txt"), "abcdefghij")
    io.write_file(os.join(DIR, "secret.txt"), "secret")

    t := thread.spawn(serve_main, [])
    port := t.receive(10.0)
    base := "http://127.0.0.1:" + str(port)

    func t_routes():
        r := http.get(base + "/")
        assert_eq(r.status, 200)
        assert_eq(r.text(), "<h1>Accueil</h1>")
        assert_eq(r.header("content-type"), "text/html; charset=utf-8")
        assert_true(r.header("x-request-id") != null)
        r = http.get(base + "/articles/42", params={"q": "été"})
        assert_eq(r.json(), {"id": 42, "q": "été"})
        assert_eq(http.get(base + "/articles/abc").status, 404)
        r = http.get(base + "/fichiers/a/b%20c/d.txt")
        assert_eq(r.text(), "a/b c/d.txt")
        assert_eq(http.get(base + "/nom").text(), "nom")
        r = http.request("DELETE", base + "/")
        assert_eq(r.status, 405)
        assert_eq(r.header("allow"), "GET, HEAD")
        r = http.head(base + "/")
        assert_eq(r.status, 200)
        assert_eq(r.body, "")
        r = http.options(base + "/")
        assert_eq(r.status, 204)
        r = http.get(base + "/absent", headers={"Accept": "application/json"})
        assert_eq(r.json()["status"], 404)
        r = http.get(base + "/absent", headers={"Accept": "text/html"})
        assert_true("404" in r.text() and "<!DOCTYPE html>" in r.text())
        assert_eq(http.get(base + "/boom").status, 500)
        assert_eq(http.get(base + "/absent-abort").status, 410)
        assert_eq(http.get(base + "/articles/7/", follow_redirects=false).status, 308)

    testing.test("routes, méthodes, erreurs", t_routes)

    func t_bodies():
        r := http.post(base + "/echo", body="données brutes", content_type="text/plain")
        assert_eq(r.status, 201)
        assert_eq(r.text(), "données brutes")
        assert_eq(r.header("x-echo"), "1")
        assert_eq(http.post(base + "/json", json={"a": [1, 2], "b": "é"}).json(), {"a": [1, 2], "b": "é"})
        assert_eq(http.post(base + "/form", form={"nom": "Zoé", "n": 3}).json(), {"nom": "Zoé", "n": "3"})
        up := http.post(base + "/upload", form={"titre": "x"}, files=[("f", "a.txt", "contenu", "text/plain")])
        assert_eq(up.json()["type"], "multipart/form-data")
        r = http.get(base + "/big")
        assert_eq(len(r.text()), 5000)
        assert_null(r.header("content-encoding"))
        assert_raises(() => http.Client(max_response_size=100).get(base + "/big", ), "ClientResponseError")

    testing.test("corps : texte, JSON, formulaire, multipart, gzip", t_bodies)

    func t_client():
        r := http.get(base + "/redir")
        assert_eq(r.status, 200)
        assert_eq(len(r.history), 1)
        r = http.post(base + "/see-other", body="x")
        assert_eq(r.text(), "GET")
        assert_raises(() => http.get(base + "/boucle"), "TooManyRedirects")
        http.get(base + "/cookie")
        assert_eq(http.get(base + "/lire-cookie").text(), "xyz")
        assert_eq(http.shared().cookies.get("sid"), "xyz")
        c := http.Client(base_url=base + "/articles/", retries=2, headers={"Accept": "application/json"})
        assert_eq(c.get("5").json()["id"], 5)
        assert_eq(c.build("GET", "6").param("q", "z").send().json(), {"id": 6, "q": "z"})
        assert_eq(c.get(base + "/flaky").text(), "réussi après reprise")
        c.close()
        c2 := http.Client(retries=false)
        assert_eq(c2.get(base + "/flaky").status, 503)
        c2.close()
        assert_raises(() => http.get(base + "/slow", timeout=0.1), "ClientTimeoutError")
        assert_raises(() => http.get("http://127.0.0.1:1/", timeout=2), "ClientConnectionError")
        target := os.join(DIR, "copie.css")
        http.download(base + "/static/site.css", target)
        assert_eq(io.read_file(target), "body{color:red}\n")
        st0 := http.shared().stats()
        assert_true(st0["reused"] > 0)

    testing.test("client : redirections, cookies, reprises, délais, réserve", t_client)

    func t_static():
        r := http.get(base + "/static/site.css")
        assert_eq(r.text(), "body{color:red}\n")
        assert_eq(r.header("content-type"), "text/css; charset=utf-8")
        assert_eq(http.get(base + "/static/site.css", headers={"If-None-Match": r.header("etag")}).status, 304)
        assert_eq(http.get(base + "/static/site.css", headers={"If-Modified-Since": r.header("last-modified")}).status, 304)
        r = http.get(base + "/static/docs/data.txt", headers={"Range": "bytes=2-4"})
        assert_eq(r.status, 206)
        assert_eq(r.text(), "cde")
        assert_eq(r.header("content-range"), "bytes 2-4/10")
        assert_eq(http.get(base + "/static/docs/data.txt", headers={"Range": "bytes=-3"}).text(), "hij")
        assert_eq(http.get(base + "/static/docs/data.txt", headers={"Range": "bytes=20-"}).status, 416)
        r = http.get(base + "/static/docs", follow_redirects=false)
        assert_eq(r.status, 301)
        assert_eq(r.header("location"), "/static/docs/")
        assert_true("data.txt" in http.get(base + "/static/docs/").text())
        assert_eq(http.get(base + "/static/../secret.txt").status, 404)
        assert_eq(http.get(base + "/static/%2e%2e/secret.txt").status, 404)
        assert_eq(http.get(base + "/static/docs%2f..%2f..%2fsecret.txt").status, 404)
        assert_eq(sf.parse_range("bytes=0-0,5-6", 10), null)

    testing.test("fichiers statiques", t_static)

    func t_stop():
        assert_eq(http.get(base + "/stop").text(), "arrêt")
        errs := t.join(10.0)
        assert_eq(len(errs), 1)

    testing.test("arrêt du serveur", t_stop)

    func t_raw():
        t2 := thread.spawn(serve_limited, [])
        port2 := t2.receive(10.0)
        c := tcp.connect("127.0.0.1", port2, 3.0)
        c.write("GET / HTTP/1.1\r\nHost: h\r\n\r\nGET / HTTP/1.1\r\nHost: h\r\n\r\n")
        rs2 := responses(c, 2)
        assert_eq(len(rs2), 2)
        assert_eq(rs2[0].body, "racine HTTP/1.1")
        assert_true(rs2[1].headers.has_token("connection", "close"))
        assert_true(closed_by_server(c))
        c.close()
        assert_eq(raw_status(port2, "N IMPORTE QUOI\r\n\r\n"), 400)
        assert_eq(raw_status(port2, "GET / HTTP/1.1\r\n\r\n"), 400)
        assert_eq(raw_status(port2, "POST /echo HTTP/1.1\r\nHost: h\r\nContent-Length: 500\r\n\r\n"), 413)
        assert_eq(raw_status(port2, "GET / HTTP/1.1\r\nHost: h\r\nX-Gros: " + "a" * 2000 + "\r\n\r\n"), 431)
        assert_eq(raw_status(port2, "GET /" + "a" * 400 + " HTTP/1.1\r\nHost: h\r\n\r\n"), 414)
        assert_eq(raw_status(port2, "GET / HTTP/1.1\r\nHost: evil.example\r\n\r\n"), 421)
        assert_eq(raw_status(port2, "GET / HTTP/1.1\r\nHo"), 408)
        assert_eq(raw_status(port2, "POST /echo HTTP/1.1\r\nHost: h\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n"), 400)
        assert_eq(raw_status(port2, "GET / HTTP/3\r\nHost: h\r\n\r\n"), 505)
        c = tcp.connect("127.0.0.1", port2, 3.0)
        c.write("GET / HTTP/1.0\r\nHost: h\r\n\r\n")
        rs2 = responses(c, 1)
        assert_eq(rs2[0].version, "HTTP/1.0")
        assert_true(closed_by_server(c))
        c.close()
        c = tcp.connect("127.0.0.1", port2, 3.0)
        c.write("POST /echo HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n")
        assert_eq(responses(c, 1)[0].body, "abcde")
        c.close()
        c = tcp.connect("127.0.0.1", port2, 3.0)
        c.write("POST /echo HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\nExpect: 100-continue\r\n\r\n")
        assert_eq(c.read_line(3.0), "HTTP/1.1 100 Continue")
        c.read_line(3.0)
        c.write("hello")
        p := pp.ResponseParser("GET")
        got := p.feed(c.buffer) if c.buffer != "" else []
        while len(got) == 0:
            got = p.feed(c.socket.recv(4096, 3.0))
        assert_eq(got[0].body, "hello")
        c.close()
        c = tcp.connect("127.0.0.1", port2, 3.0)
        c.write("GET / HTTP/1.1\r\nHost: h\r\n\r\n")
        responses(c, 1)
        t0 := time.monotonic()
        assert_true(closed_by_server(c, 5.0))
        assert_true(time.monotonic() - t0 > 1.0)
        c.close()
        conns := []
        for i in [1, 2, 3, 4]:
            x := tcp.connect("127.0.0.1", port2, 3.0)
            x.write("GET / HTTP/1.1\r\nHost: h\r\n\r\n")
            responses(x, 1)
            conns = conns + [x]
        assert_eq(raw_status(port2, "GET / HTTP/1.1\r\nHost: h\r\n\r\n"), 503)
        for x in conns:
            x.close()
        time.sleep(0.3)
        a := tcp.connect("127.0.0.1", port2, 3.0)
        b := tcp.connect("127.0.0.1", port2, 3.0)
        b.write("GET /stop HTTP/1.1\r\nHost: h\r\n\r\nGET /slow HTTP/1.1\r\nHost: h\r\n\r\n")
        rs3 := responses(b, 2, 5.0)
        assert_eq(len(rs3), 2)
        assert_eq(rs3[1].body, "lent")
        assert_true(rs3[1].headers.has_token("connection", "close"))
        assert_true(closed_by_server(a, 5.0))
        s := t2.join(10.0)
        assert_true(s["requests"] >= 10)

    testing.test("protocole brut : pipelining, limites, délais, arrêt propre", t_raw)

    func t_tls():
        t3 := thread.spawn(serve_tls, [])
        port3 := t3.receive(20.0)
        url := "https://localhost:" + str(port3) + "/"
        assert_raises(() => http.get(url), "ClientTlsError")
        c := http.Client(ca_file=os.join(DIR, "certs", "localhost.pem"))
        r := c.get(url)
        assert_eq(r.json(), {"secure": true, "scheme": "https"})
        c.close()
        assert_eq(t3.join(30.0), 1)

    if ts.supported() and os.exists("/usr/bin/openssl"):
        testing.test("HTTPS (certificat auto-signé)", t_tls)
    else:
        testing.skip("HTTPS (certificat auto-signé)", t_tls, "OpenSSL ou l'outil openssl absent")

    failed := testing.run()
    http.close()
    os.rmdir(DIR, true)
    if failed > 0:
        raise("AssertionError", str(failed) + " test(s) web.client / web.server en échec")
    print("web.client + web.server : OK")

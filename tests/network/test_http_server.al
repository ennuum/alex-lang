# Test de network.http_server : serveur Alex (dans un fil) contre network.http_client, des connexions TCP brutes
# (pipelining, requêtes malformées), curl (si présent) et un client WebSocket ; puis HTTPS avec un certificat
# généré par network.certificates (si openssl est présent).

from core use len, type
from collections use append
use string as s
use io
use os
use process as proc
use concurrency.thread as thread
use network.http_server as hs
use network.http_client as hc
use network.tcp as tcp
use network.websocket as ws
use network.certificates as certs
use network.utils as nu

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

const STATIC_DIR := "/tmp/alex_http_server_static"

func boom(req):
    raise("ValueError", "panne volontaire")

func ws_echo(req, sock):
    while true:
        m := sock.receive(5.0)
        if m == null:
            return
        sock.send_text("écho : " + m.text())

func make_app():
    app := hs.App()
    app.get("/", (req) => "accueil")
    app.get("/articles/{id:int}", (req) => {"id": req.params["id"], "q": req.param("q")})
    app.get("/fichiers/{chemin*}", (req) => req.params["chemin"])
    app.get("/uuid/{u:uuid}", (req) => req.params["u"])
    app.post("/echo", (req) => hs.text(req.text()))
    app.post("/json", (req) => (req.json(), 201))
    app.post("/form", (req) => req.form())
    app.post("/upload", (req) => {"nom": req.file("f").filename, "taille": req.file("f").size(), "titre": req.form()["titre"]})
    app.get("/cookie", (req) => hs.text("ok").set_cookie("sid", "xyz", 3600))
    app.get("/lire-cookie", (req) => req.cookie("sid", "aucun"))
    app.get("/boom", boom)
    app.get("/vide", (req) => null)
    app.get("/redir", (req) => hs.redirect("/"))
    app.get("/gros", (req) => hs.text("x" * 5000))
    app.get("/stop", stop_handler)
    app.route(["GET", "POST"], "/multi", (req) => req.method)
    app.static("/static", STATIC_DIR)
    app.websocket("/ws", ws_echo)
    app.use_middleware(hs.compress(256))
    app.use_middleware(hs.cors(["https://exemple.org"]))
    return app

STOP := [null]

func stop_handler(req):
    STOP[0].stop()
    return "arrêt"

func serve_main(cert, key):
    srv := hs.Server(make_app(), "127.0.0.1", 0, cert, key, 4096, 4096, 2.0)
    STOP[0] = srv
    thread.send(srv.port())
    srv.serve_forever(0.2)
    errs := srv.errors
    srv.close()
    return errs

func raw_exchange(port, data, wait=2.0):
    c := tcp.connect("127.0.0.1", port, 2.0)
    c.write(data)
    out := ""
    try:
        out = c.read_all(wait)
    catch e:
        out = out + "<" + e.type + ">"
    c.close()
    return out

if thread.is_main():
    os.mkdir_all(STATIC_DIR + "/sous")
    io.write_file(STATIC_DIR + "/a.txt", "0123456789")
    io.write_file(STATIC_DIR + "/sous/index.html", "<p>index</p>")
    io.write_file("/tmp/alex_http_server_secret.txt", "secret")

    t := thread.spawn(serve_main, [null, null])
    port := t.receive(10.0)
    base := "http://127.0.0.1:" + str(port)
    c := hc.Client(base + "/", null, 5.0)

    check_eq(c.get("").text(), "accueil", "route racine")
    a := c.get("articles/42", {"q": "x"})
    check_eq([a.status, a.json()["id"], a.json()["q"]], [200, 42, "x"], "paramètre int + requête")
    check_eq(c.get("articles/abc").status, 404, "paramètre int invalide -> 404")
    check_eq(c.get("fichiers/a/b/c.txt").text(), "a/b/c.txt", "paramètre {reste*}")
    check_eq(c.get("uuid/123e4567-E89B-12d3-a456-426614174000").text(), "123e4567-e89b-12d3-a456-426614174000", "paramètre uuid")
    m := c.delete("articles/1")
    check_eq([m.status, m.header("allow")], [405, "GET"], "405 + Allow")
    check_eq(c.post("echo", "données é").text(), "données é", "POST texte")
    j := c.post("json", null, {"x": [1, 2]})
    check_eq([j.status, j.json()["x"]], [201, [1, 2]], "JSON + statut (tuple)")
    check_eq(c.post("json", "{pas du json").status, 400, "JSON invalide -> 400")
    check_eq(c.post("form", {"a": "1", "b": "é"}).json(), {"a": "1", "b": "é"}, "formulaire urlencoded")
    up := c.post("upload", null, null, {"titre": "T"}, {"f": hc.File("x.bin", nu.from_bytes([1, 2, 3, 0]))}).json()
    check_eq([up["nom"], up["taille"], up["titre"]], ["x.bin", 4, "T"], "multipart")
    c.get("cookie")
    check_eq(c.get("lire-cookie").text(), "xyz", "cookie posé puis relu")
    b := c.get("boom")
    check_eq(b.status, 500, "exception -> 500")
    check_eq(c.get("vide").status, 204, "null -> 204")
    check_eq(c.get("inconnu").status, 404, "404")
    rd := c.get("redir")
    check_eq([rd.text(), len(rd.history)], ["accueil", 1], "redirection")
    check_eq([c.get("multi").text(), c.post("multi").text()], ["GET", "POST"], "route multi-méthodes")
    hd := c.head("gros", null, {"Accept-Encoding": "identity"})
    check_eq([hd.status, hd.header("content-length"), hd.content()], [200, "5000", ""], "HEAD : longueur sans corps")
    gz := c.get("gros")
    check_eq([gz.header("content-encoding"), len(gz.text())], ["gzip", 5000], "compression gzip")

    # keep-alive : toutes ces requêtes sont passées par une seule connexion
    check_eq(c.pool.stats()["created"], 1, "keep-alive : une seule connexion pour tout le client")

    # fichiers statiques
    st := c.get("static/a.txt")
    check_eq([st.status, st.text(), st.content_type()], [200, "0123456789", "text/plain"], "fichier statique")
    etag := st.header("etag")
    check_eq(c.get("static/a.txt", null, {"If-None-Match": etag}).status, 304, "ETag -> 304")
    rg := c.get("static/a.txt", null, {"Range": "bytes=2-4"})
    check_eq([rg.status, rg.text(), rg.header("content-range")], [206, "234", "bytes 2-4/10"], "plage 206")
    check_eq(c.get("static/a.txt", null, {"Range": "bytes=50-"}).status, 416, "plage hors limites -> 416")
    mr := c.get("static/a.txt", null, {"Range": "bytes=0-0,9-9"})
    check(mr.status == 206 and s.starts_with(mr.content_type(), "multipart/byteranges"), "plusieurs plages -> multipart/byteranges")
    check_eq(c.get("static/sous/").text(), "<p>index</p>", "index d'un dossier")
    check_eq(c.get("static/sous").status, 200, "dossier sans « / » : redirection puis index")
    trav := raw_exchange(port, "GET /static/../alex_http_server_secret.txt HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    check(s.starts_with(trav, "HTTP/1.1 404"), "remontée de dossier refusée")
    trav2 := raw_exchange(port, "GET /static/%2e%2e/alex_http_server_secret.txt HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    check(s.starts_with(trav2, "HTTP/1.1 404"), "remontée encodée refusée")

    # CORS
    pre := c.options("echo", {"Origin": "https://exemple.org", "Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "X-Test"})
    check_eq([pre.status, pre.header("access-control-allow-origin"), pre.header("access-control-allow-headers")], [204, "https://exemple.org", "X-Test"], "CORS : requête préalable")
    check_eq(c.get("", null, {"Origin": "https://evil.example"}).header("access-control-allow-origin"), null, "CORS : origine refusée")

    # connexions brutes : pipelining, erreurs de protocole
    pipe := raw_exchange(port, "GET / HTTP/1.1\r\nHost: x\r\n\r\nGET /articles/7 HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    check(s.contains(pipe, "accueil") and s.contains(pipe, "\"id\":7"), "pipelining : deux réponses")
    check(s.starts_with(raw_exchange(port, "N'IMPORTE QUOI\r\n\r\n"), "HTTP/1.1 400"), "requête malformée -> 400")
    check(s.starts_with(raw_exchange(port, "GET / HTTP/1.1\r\n\r\n"), "HTTP/1.1 400"), "Host manquant -> 400")
    check(s.starts_with(raw_exchange(port, "GET / HTTP/2.0\r\nHost: x\r\n\r\n"), "HTTP/1.1 505"), "version -> 505")
    check(s.starts_with(raw_exchange(port, "GET / HTTP/1.1\r\nHost: x\r\nX-Gros: " + "a" * 5000 + "\r\n\r\n"), "HTTP/1.1 431"), "en-têtes trop longs -> 431")
    check(s.starts_with(raw_exchange(port, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 99999\r\n\r\n"), "HTTP/1.1 413"), "corps trop grand -> 413")
    check(s.contains(raw_exchange(port, "POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n3\r\nabc\r\n2;x=1\r\nde\r\n0\r\n\r\n"), "\r\n\r\nabcde"), "corps chunked")
    check(s.starts_with(raw_exchange(port, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n"), "HTTP/1.1 400"), "CL + TE -> 400 (anti contrebande)")
    check(s.contains(raw_exchange(port, "GET / HTTP/1.0\r\n\r\n"), "Connection: close"), "HTTP/1.0 : fermeture")
    check(s.starts_with(raw_exchange(port, "POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nab", 4.0), "HTTP/1.1 408"), "corps incomplet -> 408")
    # deux connexions ouvertes en même temps (multiplexage)
    k1 := tcp.connect("127.0.0.1", port, 2.0)
    k2 := tcp.connect("127.0.0.1", port, 2.0)
    k1.write("GET /articles/1 HTTP/1.1\r\nHost: x\r\n\r\n")
    k2.write("GET /articles/2 HTTP/1.1\r\nHost: x\r\n\r\n")
    check_eq(k2.read_line(3.0), "HTTP/1.1 200 OK", "deux clients simultanés : 2")
    check_eq(k1.read_line(3.0), "HTTP/1.1 200 OK", "deux clients simultanés : 1")
    k1.close()
    k2.close()

    # WebSocket
    w := ws.connect("ws://127.0.0.1:" + str(port) + "/ws", null, null, 5.0)
    w.send_text("salut")
    check_eq(w.receive(5.0).text(), "écho : salut", "WebSocket : écho")
    w.close()
    check_eq(c.get("ws").status, 426, "WebSocket sans mise à niveau -> 426")

    # curl
    if proc.which("curl") != null:
        r := proc.Command("curl").args(["-s", "-F", "titre=C", "-F", "f=@" + STATIC_DIR + "/a.txt", base + "/upload"]).stdout("pipe").run(null, 10.0)
        check_eq(r.stdout, "{\"nom\":\"a.txt\",\"taille\":10,\"titre\":\"C\"}", "curl : multipart")
        r2 := proc.Command("curl").args(["-s", "-H", "Expect: 100-continue", "--data-binary", "corps attendu", base + "/echo"]).stdout("pipe").run(null, 10.0)
        check_eq(r2.stdout, "corps attendu", "curl : Expect 100-continue")
    c.get("stop")
    errs := t.join(10.0)
    check_eq(errs, ["ValueError: panne volontaire"], "erreurs des gestionnaires")
    c.close()

    # HTTPS
    if proc.which("openssl") != null:
        cert := "/tmp/alex_http_server_cert.pem"
        key := "/tmp/alex_http_server_key.pem"
        certs.generate_self_signed(cert, key, "localhost", ["localhost", "127.0.0.1"], 2)
        t2 := thread.spawn(serve_main, [cert, key])
        sport := t2.receive(10.0)
        sc := hc.Client("https://127.0.0.1:" + str(sport) + "/", null, 5.0, true, cert)
        check_eq(sc.get("").text(), "accueil", "HTTPS : GET vérifié")
        check_eq(sc.get("articles/3").json()["id"], 3, "HTTPS : keep-alive")
        bad := hc.Client("https://127.0.0.1:" + str(sport) + "/", null, 5.0)
        e := "aucune"
        try:
            bad.get("")
        catch err:
            e = err.type
        check_eq(e, "TlsError", "HTTPS : certificat inconnu refusé")
        fc := certs.fetch("127.0.0.1", sport)
        check_eq([fc.subject_cn(), fc.matches_hostname("127.0.0.1")], ["localhost", true], "certificates.fetch")
        sc.get("stop")
        t2.join(10.0)
        sc.close()

    print(f"http_server : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_http_server : échecs")

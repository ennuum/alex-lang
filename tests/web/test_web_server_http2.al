# ALEX - tests de HTTP/2 dans web.server (web.server.http2) : h2c par préface, flux multiplexés servis en parallèle
# par des gestionnaires async, corps de requête, gros corps de réponse et contrôle de flux, fichiers, HEAD, 404,
# réponse en flux (SSE), HTTP/1.1 toujours servi sur le même port, préface invalide. Client : network.grpc.H2Connection.
# Lancer depuis la racine : ./alex run tests/web/test_web_server_http2.al
use io
use os
use time
use asyncio as aio
use string as s
use concurrency.thread as thread
use network.tcp as tcp
use network.grpc as g
use web.server as server
use web.server.streaming as st
use web.client as http
from core use len, to_int
from collections use append

const GROS := "/tmp/alex-test-h2-gros.bin"

async func lent(req):
    await aio.sleep(0.3)
    return "lent " + req.query_param("n", "?")

async func trois(req, flux):
    i := 0
    while i < 3:
        await flux.send({"n": i}, "tick", i)
        await aio.sleep(0.02)
        i += 1

func make_app():
    app := server.App()
    app.get("/", (req) => "bonjour en " + req.version)
    app.post("/echo", (req) => "reçu " + str(s.byte_len(req.body)) + " octets : " + s.byte_slice(req.body, 0, 10))
    app.get("/lent", lent)
    app.get("/grand", (req) => s.repeat("abcdefghij", 30000))
    app.get("/sse", st.sse(trois))
    app.get("/entetes", (req) => req.header("x-essai") + "|" + req.header("cookie") + "|" + req.header("host"))
    app.static("/f", "/tmp")
    return app

# Requête sur une connexion HTTP/2 ouverte ; rend [statut, en-têtes dict, corps].
func ouvrir(port):
    c := tcp.connect("127.0.0.1", port, 5.0)
    h := g.H2Connection(c, true)
    h.start()
    return h

func envoyer(h, method, path, body=null, extra=null):
    stm := h.new_stream()
    hs := [[":method", method], [":scheme", "http"], [":authority", "localhost"], [":path", path]]
    if extra != null:
        for e in extra:
            append(hs, e)
    if body == null:
        h.send_headers(stm.id, hs, true)
    else:
        h.send_headers(stm.id, hs, false)
        h.send_data(stm.id, body, true, 5.0)
    return stm

func reponse(h, stm):
    data := []
    h.wait_until(() => stm.ended or stm.reset_code != null, 10.0)
    append(data, stm.take_data())
    d := {}
    for e in stm.headers:
        d[e[0]] = e[1]
    return [to_int(d[":status"]), d, s.join("", data)]

func requete(port, method, path, body=null, extra=null):
    h := ouvrir(port)
    r := reponse(h, envoyer(h, method, path, body, extra))
    h.close()
    return r

func scenario(port):
    out := {}
    out["get"] = requete(port, "GET", "/")
    out["post"] = requete(port, "POST", "/echo", s.repeat("é", 50000))
    out["grand"] = requete(port, "GET", "/grand")
    out["fichier"] = requete(port, "GET", "/f/alex-test-h2-gros.bin")
    out["head"] = requete(port, "HEAD", "/f/alex-test-h2-gros.bin")
    out["absent"] = requete(port, "GET", "/nulle-part")
    out["entetes"] = requete(port, "GET", "/entetes", null, [["x-essai", "oui"], ["cookie", "a=1"], ["cookie", "b=2"]])
    out["sse"] = requete(port, "GET", "/sse")
    # cinq requêtes lentes multiplexées sur la même connexion
    h := ouvrir(port)
    t0 := time.monotonic()
    flux := []
    i := 0
    while i < 5:
        append(flux, envoyer(h, "GET", "/lent?n=" + str(i)))
        i += 1
    corps := []
    for f in flux:
        append(corps, reponse(h, f)[2])
    out["multiplex"] = [corps, time.monotonic() - t0]
    h.close()
    out["http1"] = http.get("http://127.0.0.1:" + str(port) + "/").text()
    # préface correcte puis trame interdite (DATA sur le flux 0) : GOAWAY et fermeture
    c := tcp.connect("127.0.0.1", port, 5.0)
    c.write("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" + s.byte_pack([0, 0, 0, 4, 0, 0, 0, 0, 0]) + s.byte_pack([0, 0, 0, 0, 0, 0, 0, 0, 0]))
    recu := ""
    while true:
        d := c.socket.recv(4096, 3.0)
        if d == "":
            break
        recu = recu + d
    c.close()
    out["preface"] = recu
    return out

async func drive(srv, t, limit=60.0):
    t0 := time.monotonic()
    while t.is_alive() and time.monotonic() - t0 < limit:
        await srv.serve_for_async(0.01)

ECHECS := []

func check(nom, ok, detail=null):
    if ok:
        print("  [OK]      " + nom)
    else:
        print("  [ÉCHEC]   " + nom + (" : " + str(detail) if detail != null else ""))
        append(ECHECS, nom)

if thread.is_main():
    io.write_file(GROS, s.repeat("0123456789", 50000))
    srv := server.Server(make_app(), server.config("127.0.0.1", 0)).start()
    t := thread.spawn(scenario, [srv.port()])
    await drive(srv, t)
    r := t.join(2.0)
    srv.close()
    check("scénario terminé", r != null)
    if r != null:
        check("GET : 200, corps, version vue par l'application", r["get"][0] == 200 and r["get"][2] == "bonjour en HTTP/2" and r["get"][1]["content-length"] == "17", r["get"])
        check("POST : corps de 100 000 octets en plusieurs trames DATA", r["post"][2] == "reçu 100000 octets : ééééé", r["post"])
        check("réponse de 300 000 octets (contrôle de flux)", r["grand"][0] == 200 and s.byte_len(r["grand"][2]) == 300000, s.byte_len(r["grand"][2]))
        check("fichier de 500 000 octets", r["fichier"][0] == 200 and r["fichier"][2] == io.read_file(GROS) and r["fichier"][1]["content-length"] == "500000", s.byte_len(r["fichier"][2]))
        check("HEAD : en-têtes sans corps", r["head"][0] == 200 and r["head"][2] == "" and r["head"][1]["content-length"] == "500000", r["head"])
        check("404", r["absent"][0] == 404, r["absent"][0])
        check("en-têtes : cookies recollés, Host depuis :authority", r["entetes"][2] == "oui|a=1; b=2|localhost", r["entetes"][2])
        check("SSE sur HTTP/2", r["sse"][0] == 200 and s.contains(r["sse"][2], "event: tick\nid: 2\ndata: {\"n\":2}") and s.starts_with(r["sse"][1]["content-type"], "text/event-stream"), r["sse"])
        m := r["multiplex"]
        check("5 requêtes lentes (0,3 s) multiplexées : servies en parallèle", m[0] == ["lent 0", "lent 1", "lent 2", "lent 3", "lent 4"] and m[1] < 1.0, m)
        check("HTTP/1.1 toujours servi sur le même port", r["http1"] == "bonjour en HTTP/1.1", r["http1"])
        p := r["preface"]
        check("trame interdite : GOAWAY (PROTOCOL_ERROR) puis fermeture", s.contains(p, "DATA sur un flux inconnu"), s.byte_unpack(s.byte_slice(p, 0, 12)))
    check("métriques : sessions HTTP/2 comptées", srv.metrics.http2_sessions == 10, srv.metrics.http2_sessions)
    check("seule erreur consignée : la trame interdite", len(srv.errors) == 1 and s.contains(srv.errors[0], "DATA sur un flux inconnu"), srv.errors)
    io.delete_file(GROS)
    print(str(len(ECHECS)) + " échec(s)")
    if len(ECHECS) > 0:
        raise("AssertionError", str(len(ECHECS)) + " test(s) HTTP/2 en échec")

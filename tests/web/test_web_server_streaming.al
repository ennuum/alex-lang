# ALEX - tests des réponses en flux et des Server-Sent Events de web.server (web.server.streaming) : format SSE,
# reprise par Last-Event-ID, maintien de connexion, flux brut chunked et HTTP/1.0, HTTP servi pendant un flux,
# client qui part, exception du producteur, arrêt du serveur, boucle synchrone refusée.
# Lancer depuis la racine : ./alex run tests/web/test_web_server_streaming.al
use time
use asyncio as aio
use string as s
use concurrency.thread as thread
use network.tcp as tcp
use web.server as server
use web.server.streaming as st
use web.http.protocol_parser as pp
use web.client as http
from core use len, to_int
from collections use append

PRODUCTEURS := {"infini_fini": false}

async func trois(req, flux):
    debut := to_int(flux.last_event_id) + 1 if flux.last_event_id != null else 1
    i := debut
    while i < debut + 3:
        await flux.send({"n": i}, "tick", i)
        await aio.sleep(0.02)
        i += 1
    await flux.send("deux\nlignes")

async func infini(req, flux):
    while not flux.closed:
        await flux.send("x")
        await aio.sleep(0.1)
    PRODUCTEURS["infini_fini"] = true

async func lent(req, flux):
    await aio.sleep(0.7)
    await flux.send("fin")

async func csv(req, flux):
    await flux.write("a,b\n")
    await aio.sleep(0.01)
    await flux.write("1,2\n")
    await flux.write("3,4\n")

async func panne(req, flux):
    await flux.write("début ")
    raise("ValueError", "panne du producteur")

func make_app():
    app := server.App()
    app.get("/trois", st.sse(trois))
    app.get("/infini", st.sse(infini))
    app.get("/lent", st.sse(lent, 0.2))
    app.get("/csv", st.stream(csv, "text/csv"))
    app.get("/panne", st.stream(panne, "text/plain"))
    app.get("/http", (req) => "http ok")
    return app

# ---------------------------------------------------------------- clients

func requete(port, path, headers="", version="HTTP/1.1"):
    c := tcp.connect("127.0.0.1", port, 3.0)
    c.write("GET " + path + " " + version + "\r\nHost: x\r\n" + headers + "\r\n")
    p := pp.ResponseParser("GET")
    out := []
    while len(out) == 0:
        d := c.socket.recv(65536, 10.0)
        if d == "":
            for m in p.finish():
                append(out, m)
            break
        for m in p.feed(d):
            append(out, m)
    c.close()
    r := out[0]
    return [r.status, r.headers.get("content-type"), r.headers.get("transfer-encoding"), r.body]

func client_infini_puis_part(port):
    c := tcp.connect("127.0.0.1", port, 3.0)
    c.write("GET /infini HTTP/1.1\r\nHost: x\r\n\r\n")
    recu := ""
    while s.count(recu, "data: x") < 3:
        recu = recu + c.socket.recv(65536, 5.0)
    t0 := time.monotonic()
    r := http.get("http://127.0.0.1:" + str(port) + "/http")
    dt := time.monotonic() - t0
    c.close()
    return [r.text(), dt, s.count(recu, "data: x") >= 3]

func client_attend(port, path):
    c := tcp.connect("127.0.0.1", port, 3.0)
    c.write("GET " + path + " HTTP/1.1\r\nHost: x\r\n\r\n")
    recu := ""
    while true:
        d := c.socket.recv(65536, 10.0)
        if d == "":
            break
        recu = recu + d
    c.close()
    return recu

# ---------------------------------------------------------------- outils

async func drive(srv, threads, limit=20.0):
    t0 := time.monotonic()
    while time.monotonic() - t0 < limit:
        alive := false
        for t in threads:
            if t.is_alive():
                alive = true
        if not alive:
            return
        await srv.serve_for_async(0.05)

FAILED := [0]

func check(name, cond, detail=""):
    if cond:
        print("  ok   " + name)
    else:
        FAILED[0] = FAILED[0] + 1
        print("  ÉCHEC " + name + " : " + str(detail))

if thread.is_main():
    srv := server.Server(make_app(), server.config("127.0.0.1", 0)).start()
    port := srv.port()
    ts := [thread.spawn(requete, [port, "/trois"]), thread.spawn(requete, [port, "/trois", "Last-Event-ID: 41\r\n"]), thread.spawn(requete, [port, "/csv"]), thread.spawn(requete, [port, "/csv", "", "HTTP/1.0"]), thread.spawn(requete, [port, "/panne"]), thread.spawn(requete, [port, "/lent"]), thread.spawn(client_infini_puis_part, [port])]
    await drive(srv, ts)
    r := []
    for t in ts:
        append(r, t.join(5.0))
    sse := r[0]
    check("SSE : statut et type", sse[0] == 200 and s.starts_with(sse[1], "text/event-stream") and sse[2] == "chunked", sse)
    check("SSE : événements, identifiants, données JSON", s.starts_with(sse[3], "event: tick\nid: 1\ndata: {\"n\":1}\n\nevent: tick\nid: 2\n"), sse[3])
    check("SSE : données sur plusieurs lignes", s.ends_with(sse[3], "data: deux\ndata: lignes\n\n"), sse[3])
    check("SSE : reprise par Last-Event-ID", s.starts_with(r[1][3], "event: tick\nid: 42\n"), r[1][3])
    check("flux brut chunked", r[2][0] == 200 and r[2][1] == "text/csv" and r[2][2] == "chunked" and r[2][3] == "a,b\n1,2\n3,4\n", r[2])
    check("flux HTTP/1.0 : délimité par la fermeture", r[3][2] == null and r[3][3] == "a,b\n1,2\n3,4\n", r[3])
    check("exception du producteur : flux terminé, erreur consignée", r[4][3] == "début " and len(srv.errors) == 1 and "panne du producteur" in srv.errors[0], [r[4], srv.errors])
    check("SSE : commentaire de maintien pendant l'attente", ": keepalive\n\n" in r[5][3] and s.ends_with(r[5][3], "data: fin\n\n"), r[5][3])
    check("HTTP servi pendant un flux ouvert", r[6][0] == "http ok" and r[6][1] < 0.5 and r[6][2], r[6])
    t0 := time.monotonic()
    while (len(srv.streams) > 0 or not PRODUCTEURS["infini_fini"]) and time.monotonic() - t0 < 5.0:
        await srv.serve_for_async(0.05)
    check("client parti : producteur arrêté, flux retiré", PRODUCTEURS["infini_fini"] and len(srv.streams) == 0, [PRODUCTEURS, len(srv.streams)])
    check("mesure streams_opened", srv.metrics.streams_opened == 7, srv.metrics.streams_opened)

    # arrêt du serveur pendant un flux : le producteur voit flux.closed, le client voit la fin
    PRODUCTEURS["infini_fini"] = false
    ta := thread.spawn(client_attend, [port, "/infini"])
    t1 := time.monotonic()
    while srv.metrics.streams_opened < 8 and time.monotonic() - t1 < 10.0:
        await srv.serve_for_async(0.05)
    await srv.serve_for_async(0.3)
    srv.stop()
    await srv.serve_forever_async()
    recu := ta.join(10.0)
    await aio.sleep(0.3)
    check("arrêt du serveur : flux terminé proprement (0\\r\\n\\r\\n)", s.ends_with(recu, "0\r\n\r\n") and "data: x" in recu, recu)
    check("arrêt du serveur : producteur arrêté", PRODUCTEURS["infini_fini"], PRODUCTEURS)
    srv.close()

    # boucle synchrone : refus explicite
    srv2 := server.Server(make_app(), server.config("127.0.0.1", 0)).start()
    t2 := thread.spawn(requete, [srv2.port(), "/csv"])
    srv2.serve(1, 10.0)
    check("flux sous boucle synchrone : 500", t2.join(10.0)[0] == 500)
    srv2.close()

    if FAILED[0] > 0:
        raise("AssertionError", str(FAILED[0]) + " vérification(s) de flux en échec")
    print("web.server streaming : OK")

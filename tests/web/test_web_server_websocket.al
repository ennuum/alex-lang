# ALEX - tests du WebSocket de web.server (sessions async) : écho texte / binaire / fragmenté, paramètres de
# route, sous-protocole, origine refusée, message du serveur à l'ouverture, exception du gestionnaire (1011),
# taille maximale (1009), HTTP servi pendant les sessions, arrêt du serveur (1001), boucle synchrone refusée.
# Lancer depuis la racine : ./alex run tests/web/test_web_server_websocket.al
use time
use asyncio as aio
use concurrency.thread as thread
use network.websocket as wsc
use web.server as server
use web.client as http
from core use len
from collections use append

async func echo(req, ws):
    await ws.send_text("bienvenue " + req.route_params["salon"] + " " + str(req.query_param("nom")))
    while true:
        m := await ws.receive()
        if m == null:
            return
        if m.kind == "binary":
            await ws.send_binary(m.data)
        else:
            await ws.send_text("écho : " + m.text())

async func boom(req, ws):
    m := await ws.receive()
    raise("ValueError", "panne dans la session")

async func attente(req, ws):
    await ws.receive()

func make_app():
    app := server.App()
    app.websocket("/ws/{salon}", echo, ["chat.v2", "chat.v1"])
    app.websocket("/boom", boom)
    app.websocket("/prive", echo, null, 16777216, ["https://bon.exemple"])
    app.websocket("/petit", attente, null, 64)
    app.websocket("/attente", attente)
    app.get("/http", (req) => "http ok")
    return app

# ---------------------------------------------------------------- clients (fils)

func client_echo(port):
    c := wsc.connect("ws://127.0.0.1:" + str(port) + "/ws/general?nom=Zo%C3%A9", null, ["chat.v1"])
    out := [c.subprotocol, c.receive(5.0).text()]
    c.send_text("salut")
    append(out, c.receive(5.0).text())
    c.send_binary("\x00\x01\x02")
    m := c.receive(5.0)
    append(out, [m.kind, m.data == "\x00\x01\x02"])
    c.send_text("un long message en morceaux", 5)
    append(out, c.receive(5.0).text())
    c.close()
    append(out, c.close_code)
    return out

func client_boom(port):
    c := wsc.connect("ws://127.0.0.1:" + str(port) + "/boom")
    c.send_text("x")
    m := c.receive(5.0)
    return [m, c.close_code]

func client_origine(port):
    try:
        wsc.connect("ws://127.0.0.1:" + str(port) + "/prive", null, null, 5.0, 16777216, "https://pirate.exemple")
        return "accepté"
    catch e:
        return "refusé : " + str(e.message)

func client_trop_grand(port):
    c := wsc.connect("ws://127.0.0.1:" + str(port) + "/petit")
    c.send_text("x" * 200)
    m := c.receive(5.0)
    return [m, c.close_code]

func client_http_pendant(port):
    c := wsc.connect("ws://127.0.0.1:" + str(port) + "/attente")
    time.sleep(0.2)
    t0 := time.monotonic()
    r := http.get("http://127.0.0.1:" + str(port) + "/http")
    dt := time.monotonic() - t0
    c.send_text("fin")
    c.close()
    return [r.text(), dt]

func client_arret(port):
    c := wsc.connect("ws://127.0.0.1:" + str(port) + "/attente")
    m := c.receive(10.0)
    return [m, c.close_code]

func client_sync(port):
    try:
        wsc.connect("ws://127.0.0.1:" + str(port) + "/attente", null, null, 5.0)
        return "accepté"
    catch e:
        return "refusé"

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

func new_server():
    cfg := server.config("127.0.0.1", 0)
    return server.Server(make_app(), cfg).start()

FAILED := [0]

func check(name, cond, detail=""):
    if cond:
        print("  ok   " + name)
    else:
        FAILED[0] = FAILED[0] + 1
        print("  ÉCHEC " + name + " : " + str(detail))

if thread.is_main():
    srv := new_server()
    port := srv.port()
    ts := [thread.spawn(client_echo, [port]), thread.spawn(client_boom, [port]), thread.spawn(client_origine, [port]), thread.spawn(client_trop_grand, [port]), thread.spawn(client_http_pendant, [port])]
    await drive(srv, ts)
    r := []
    for t in ts:
        append(r, t.join(5.0))
    e := r[0]
    check("sous-protocole négocié", e[0] == "chat.v1", e)
    check("message du serveur à l'ouverture, paramètres de route et de requête", e[1] == "bienvenue general Zoé", e)
    check("écho texte", e[2] == "écho : salut", e)
    check("écho binaire", e[3] == ["binary", true], e)
    check("message fragmenté réassemblé", e[4] == "écho : un long message en morceaux", e)
    check("fermeture normale (1000)", e[5] == 1000, e)
    check("exception du gestionnaire : 1011", r[1][0] == null and r[1][1] == 1011, r[1])
    check("erreur consignée", len(srv.errors) == 1 and "panne dans la session" in srv.errors[0], srv.errors)
    check("origine refusée (403)", r[2] != "accepté" and "403" in r[2], r[2])
    check("message trop grand : 1009", r[3][0] == null and r[3][1] == 1009, r[3])
    check("HTTP servi pendant une session ouverte", r[4][0] == "http ok" and r[4][1] < 0.5, r[4])
    tw := time.monotonic()
    while len(srv.websockets) > 0 and time.monotonic() - tw < 5.0:
        await srv.serve_for_async(0.05)
    check("sessions terminées et retirées", len(srv.websockets) == 0, len(srv.websockets))
    check("mesure websockets_opened", srv.metrics.websockets_opened == 4, srv.metrics.websockets_opened)

    # arrêt du serveur pendant une session : le client reçoit 1001
    ta := thread.spawn(client_arret, [port])
    t0 := time.monotonic()
    while srv.metrics.websockets_opened < 5 and time.monotonic() - t0 < 10.0:
        await srv.serve_for_async(0.05)
    srv.stop()
    await srv.serve_forever_async()
    ra := ta.join(10.0)
    check("arrêt du serveur : 1001 envoyé aux sessions", ra[0] == null and ra[1] == 1001, ra)
    srv.close()

    # boucle synchrone : poignée de main refusée
    srv2 := new_server()
    t2 := thread.spawn(client_sync, [srv2.port()])
    srv2.serve(1, 10.0)
    check("WebSocket sous boucle synchrone refusé", t2.join(10.0) == "refusé")
    srv2.close()

    if FAILED[0] > 0:
        raise("AssertionError", str(FAILED[0]) + " vérification(s) WebSocket en échec")
    print("web.server websocket : OK")

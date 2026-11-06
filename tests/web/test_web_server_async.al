# ALEX - tests des gestionnaires async de web.server : le serveur tourne dans le fil principal avec sa boucle
# async (serve_for_async), les clients dans des fils (web.client, TCP brut). Vérifie qu'un gestionnaire lent
# n'immobilise pas les autres connexions, l'ordre des réponses en pipelining, les erreurs, l'annulation quand le
# client part, et le refus explicite d'un gestionnaire async servi par une boucle synchrone.
# Lancer depuis la racine : ./alex run tests/web/test_web_server_async.al
use time
use asyncio as aio
use concurrency.thread as thread
use network.tcp as tcp
use web.server as server
use web.client as http
use web.http.protocol_parser as pp
from core use len
from testing use assert_eq, assert_true

# ---------------------------------------------------------------- application

async func lent(req):
    await aio.sleep(0.6)
    return "lent"

async func lent_court(req):
    await aio.sleep(0.2)
    return {"ordre": 1}

async func async_boom(req):
    await aio.sleep(0.01)
    raise("ValueError", "panne async")

async func async_abort(req):
    await aio.sleep(0.01)
    server.abort(404, "rien ici")

async func async_tuple(req):
    await aio.sleep(0.01)
    return ("créé", 201, {"X-Async": "oui"})

func make_app():
    app := server.App()
    app.get("/lent", lent)
    app.get("/lent-court", lent_court)
    app.get("/rapide", (req) => "rapide")
    app.get("/boom", async_boom)
    app.get("/abort", async_abort)
    app.get("/tuple", async_tuple)
    return app

async func app_fonction(req):
    await aio.sleep(0.05)
    return {"chemin": req.path()}

# ---------------------------------------------------------------- clients (dans des fils)

func client_lent(port):
    t0 := time.monotonic()
    r := http.get("http://127.0.0.1:" + str(port) + "/lent")
    return [r.status, r.text(), time.monotonic() - t0]

func client_rapides(port):
    time.sleep(0.1)
    t0 := time.monotonic()
    n := 0
    i := 0
    while i < 5:
        r := http.get("http://127.0.0.1:" + str(port) + "/rapide")
        if r.status == 200 and r.text() == "rapide":
            n += 1
        i += 1
    return [n, time.monotonic() - t0]

func client_erreurs(port):
    base := "http://127.0.0.1:" + str(port)
    a := http.get(base + "/boom")
    b := http.get(base + "/abort", headers={"Accept": "application/json"})
    c := http.get(base + "/tuple")
    return [a.status, b.status, b.json()["message"], c.status, c.text(), c.header("x-async")]

func read_responses(c, n, timeout=5.0):
    p := pp.ResponseParser("GET")
    out := []
    while len(out) < n:
        d := c.socket.recv(65536, timeout)
        if d == "":
            break
        for m in p.feed(d):
            out = out + [m]
    return out

func client_pipeline(port):
    c := tcp.connect("127.0.0.1", port, 3.0)
    c.write("GET /lent-court HTTP/1.1\r\nHost: x\r\n\r\nGET /rapide HTTP/1.1\r\nHost: x\r\n\r\n")
    rs := read_responses(c, 2)
    c.close()
    out := []
    for r in rs:
        out = out + [[r.status, r.body]]
    return out

func client_part(port):
    c := tcp.connect("127.0.0.1", port, 3.0)
    c.write("GET /lent HTTP/1.1\r\nHost: x\r\n\r\n")
    time.sleep(0.05)
    c.close()
    return true

func client_simple(port, path):
    r := http.get("http://127.0.0.1:" + str(port) + path)
    return [r.status, r.text()]

# ---------------------------------------------------------------- outils

# Sert de façon async tant qu'un des fils est vivant (au plus limit secondes).
async func drive(srv, threads, limit=15.0):
    t0 := time.monotonic()
    while time.monotonic() - t0 < limit:
        alive := false
        for t in threads:
            if t.is_alive():
                alive = true
        if not alive:
            return
        await srv.serve_for_async(0.05)

func new_server(app):
    cfg := server.config("127.0.0.1", 0)
    cfg.access_log = false
    return server.Server(app, cfg).start()

FAILED := [0]
PASSED := [0]

func check(name, fn):
    try:
        fn()
        PASSED[0] = PASSED[0] + 1
        print("  ok   " + name)
    catch e:
        FAILED[0] = FAILED[0] + 1
        print("  ÉCHEC " + name + " : " + str(e.type) + " : " + str(e.message))

# ---------------------------------------------------------------- tests

if thread.is_main():
    srv := new_server(make_app())
    port := srv.port()

    # 1. un gestionnaire lent n'immobilise pas les autres connexions
    ta := thread.spawn(client_lent, [port])
    tb := thread.spawn(client_rapides, [port])
    await drive(srv, [ta, tb])
    ra := ta.join(5.0)
    rb := tb.join(5.0)
    func t_concurrence():
        assert_eq(ra[0], 200)
        assert_eq(ra[1], "lent")
        assert_true(ra[2] >= 0.55)
        assert_eq(rb[0], 5)
        # sans async, les 5 requêtes rapides attendraient la fin de /lent (~0,5 s) ; ici elles passent pendant
        assert_true(rb[1] < 0.35)
    check("un gestionnaire async lent ne bloque pas les autres requêtes", t_concurrence)

    # 2. erreurs, abort et formes de résultat dans un gestionnaire async
    tc := thread.spawn(client_erreurs, [port])
    await drive(srv, [tc])
    rc := tc.join(5.0)
    func t_erreurs():
        assert_eq(rc[0], 500)
        assert_eq(rc[1], 404)
        assert_eq(rc[2], "rien ici")
        assert_eq(rc[3], 201)
        assert_eq(rc[4], "créé")
        assert_eq(rc[5], "oui")
        found := false
        for e in srv.errors:
            if "panne async" in e:
                found = true
        assert_true(found)
    check("exceptions, abort et (corps, statut, en-têtes) en async", t_erreurs)

    # 3. pipelining : la réponse rapide attend la réponse async qui la précède
    tp := thread.spawn(client_pipeline, [port])
    await drive(srv, [tp])
    rp := tp.join(5.0)
    func t_pipeline():
        assert_eq(len(rp), 2)
        assert_eq(rp[0][0], 200)
        assert_eq(rp[0][1], "{\"ordre\":1}")
        assert_eq(rp[1][1], "rapide")
    check("pipelining : réponses dans l'ordre des requêtes", t_pipeline)

    # 4. le client part pendant l'attente : la tâche est annulée, rien ne reste en attente
    tq := thread.spawn(client_part, [port])
    await drive(srv, [tq])
    tq.join(5.0)
    await srv.serve_for_async(0.3)
    func t_depart():
        assert_eq(len(srv.waiting), 0)
        assert_eq(srv.manager.count(), 0)
        assert_eq(srv.metrics.async_cancelled, 1)
    check("client parti pendant l'attente : tâche abandonnée, connexion libérée", t_depart)
    srv.close()

    # 5. application = simple async func
    srv2 := new_server(app_fonction)
    t5 := thread.spawn(client_simple, [srv2.port(), "/x/y"])
    await drive(srv2, [t5])
    r5 := t5.join(5.0)
    srv2.close()
    func t_fonction():
        assert_eq(r5[0], 200)
        assert_eq(r5[1], "{\"chemin\":\"/x/y\"}")
    check("application réduite à une async func", t_fonction)

    # 6. boucle synchrone : refus explicite (500) au lieu d'une connexion figée
    srv3 := new_server(make_app())
    t6 := thread.spawn(client_simple, [srv3.port(), "/lent"])
    srv3.serve(1, 10.0)
    r6 := t6.join(5.0)
    srv3.close()
    func t_sync():
        assert_eq(r6[0], 500)
        assert_true(len(srv3.errors) == 1 and "boucle synchrone" in srv3.errors[0])
    check("gestionnaire async servi par une boucle synchrone : 500 explicite", t_sync)

    # 7. les routes synchrones restent servies par la boucle async
    srv4 := new_server(make_app())
    t7 := thread.spawn(client_simple, [srv4.port(), "/rapide"])
    await drive(srv4, [t7])
    r7 := t7.join(5.0)
    srv4.close()
    check("routes synchrones sous la boucle async", () => assert_eq(r7, [200, "rapide"]))

    print("")
    print(str(PASSED[0]) + " réussi(s), " + str(FAILED[0]) + " échec(s)")
    if FAILED[0] > 0:
        raise("AssertionError", str(FAILED[0]) + " test(s) web.server async en échec")
    print("web.server async : OK")

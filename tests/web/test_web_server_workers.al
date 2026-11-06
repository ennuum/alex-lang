# ALEX - tests de web.server.workers : ce fichier est à la fois le test (maître) et l'ouvrier (relancé par le
# Supervisor avec ALEX_WEB_WORKER). Vérifie la répartition des connexions entre ouvriers sur un même port, la
# relance d'un ouvrier tué, l'arrêt propre de tous, et l'arrêt d'un ouvrier orphelin (maître disparu).
# Lancer depuis la racine : ./alex run tests/web/test_web_server_workers.al
use os
use time
use asyncio as aio
use process as proc
use network.tcp as tcp
use network.utils as nu
use web.server as server
use web.server.workers as workers
use web.http.protocol_parser as pp
from core use len, to_int
from collections use append

func make_app():
    app := server.App()
    app.get("/pid", (req) => str(os.pid()))
    app.get("/index", (req) => str(workers.worker_index()))
    return app

# Une requête sur une connexion neuve (pour que le noyau puisse choisir un autre ouvrier).
func fetch(port, path):
    c := tcp.connect("127.0.0.1", port, 3.0)
    c.write("GET " + path + " HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    p := pp.ResponseParser("GET")
    out := []
    while len(out) == 0:
        d := c.socket.recv(65536, 5.0)
        if d == "":
            for m in p.finish():
                append(out, m)
            break
        for m in p.feed(d):
            append(out, m)
    c.close()
    return out[0].body if len(out) > 0 else null

func distinct_pids(port, n):
    seen := []
    i := 0
    while i < n:
        b := fetch(port, "/pid")
        if b != null and not (b in seen):
            append(seen, b)
        i += 1
    return seen

FAILED := [0]

func check(name, cond, detail=""):
    if cond:
        print("  ok   " + name)
    else:
        FAILED[0] = FAILED[0] + 1
        print("  ÉCHEC " + name + " " + str(detail))

if workers.is_worker():
    await workers.serve(make_app(), "127.0.0.1", 0, 1, null, true)
else:
    # 1. deux ouvriers, un port, des connexions réparties
    sup := workers.Supervisor(2, "127.0.0.1", 0).start()
    check("les ouvriers écoutent", sup.wait_ready(30.0) and sup.ready_count() == 2, sup.ready_count())
    pids := distinct_pids(sup.port, 60)
    check("connexions servies par 2 processus distincts", len(pids) == 2, pids)
    check("aucun ouvrier n'est le maître", not (str(os.pid()) in pids), pids)
    idx := fetch(sup.port, "/index")
    check("index d'ouvrier transmis", idx == "0" or idx == "1", idx)

    # 2. un ouvrier tué est relancé
    victim := sup.workers[0]
    old := victim.pid()
    victim.process.kill("KILL")
    victim.process.wait(5.0)
    t0 := time.monotonic()
    while sup.restarts() == 0 and time.monotonic() - t0 < 10.0:
        sup.step()
        time.sleep(0.1)
    check("ouvrier tué relancé", sup.restarts() == 1 and victim.pid() != old, [old, victim.pid()])
    check("2 ouvriers prêts après relance", sup.wait_ready(30.0) and sup.alive_count() == 2, sup.pids())
    check("le service continue", len(distinct_pids(sup.port, 40)) >= 1)

    # 3. arrêt propre : tous les ouvriers sortent, le port se ferme
    port := sup.port
    t1 := time.monotonic()
    sup.stop(10.0)
    check("arrêt propre de tous les ouvriers", sup.alive_count() == 0, sup.pids())
    check("arrêt en moins de 5 s", time.monotonic() - t1 < 5.0, time.monotonic() - t1)
    check("port fermé après l'arrêt", not nu.is_port_open("127.0.0.1", port, 0.5))

    # 4. orphelin : le « maître » annoncé aux ouvriers disparaît -> ils s'arrêtent seuls
    faux_maitre := proc.spawn("sleep", ["2"])
    sup2 := workers.Supervisor(1, "127.0.0.1", 0, null, {"ALEX_WEB_MASTER": str(faux_maitre.pid())}).start()
    check("ouvrier de l'orphelin prêt", sup2.wait_ready(30.0))
    faux_maitre.wait(5.0)
    t2 := time.monotonic()
    while sup2.workers[0].running() and time.monotonic() - t2 < 8.0:
        time.sleep(0.1)
    check("ouvrier orphelin arrêté seul", not sup2.workers[0].running())
    sup2.stopping = true
    sup2.stop(2.0)

    if FAILED[0] > 0:
        raise("AssertionError", str(FAILED[0]) + " vérification(s) web.server.workers en échec")
    print("web.server.workers : OK")

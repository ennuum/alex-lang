# ALEX - tests de thread.offload dans web.server : calcul délégué à des fils, attendu sans bloquer le serveur.
# Lancer depuis la racine : ./alex run tests/web/test_web_server_offload.al
use time
use asyncio as aio
use concurrency.thread as thread
use web.server as server
use thread.offload as offload
use web.client as http
use tests.web.offload_calc as calc
from core use len
from collections use append

async func route_lourd(req):
    n := await offload.run(calc.lourd, [0.6])
    return {"n": n}

async func route_boum(req):
    return await offload.run(calc.boum, ["panne dans le fil"])

func make_app():
    app := server.App()
    app.get("/lourd", route_lourd)
    app.get("/boum", route_boum)
    app.get("/rapide", (req) => "rapide")
    return app

func client_get(port, path, wait):
    time.sleep(wait)
    t0 := time.monotonic()
    r := http.get("http://127.0.0.1:" + str(port) + path)
    return [r.status, r.text(), time.monotonic() - t0]

async func drive(srv, threads, limit=30.0):
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
    # sans serveur : la tâche se relève elle-même
    check("sans serveur : résultat", (await offload.run(calc.carre, [12])) == 144)
    try:
        await offload.run(calc.boum, ["hors serveur"])
        check("sans serveur : exception relancée", false)
    catch e:
        check("sans serveur : exception relancée (même type)", e.type == "ValueError" and "hors serveur" in e.message, e.message)

    srv := server.Server(make_app(), server.config("127.0.0.1", 0)).start()
    p := srv.port()
    # un calcul de 0,6 s en cours ; les requêtes rapides passent pendant ce temps
    ts := [thread.spawn(client_get, [p, "/lourd", 0.0]), thread.spawn(client_get, [p, "/rapide", 0.2]), thread.spawn(client_get, [p, "/boum", 0.0])]
    await drive(srv, ts)
    r := [t.join(5.0) for t in ts]
    check("calcul délégué : résultat", r[0][0] == 200 and "n" in r[0][1], r[0])
    check("requête rapide servie pendant le calcul", r[1][1] == "rapide" and r[1][2] < 0.25, r[1])
    check("exception du fil : 500 et erreur consignée", r[2][0] == 500 and len(srv.errors) == 1 and "panne dans le fil" in srv.errors[0], [r[2][0], srv.errors])

    # deux calculs en parallèle (2 cœurs au moins) : durée totale bien inférieure à 2 x 0,6 s
    if thread.cpu_count() >= 2:
        t0 := time.monotonic()
        ts2 := [thread.spawn(client_get, [p, "/lourd", 0.0]), thread.spawn(client_get, [p, "/lourd", 0.0])]
        await drive(srv, ts2)
        dt := time.monotonic() - t0
        r2 := [t.join(5.0) for t in ts2]
        check("deux calculs en parallèle sur deux fils", r2[0][0] == 200 and r2[1][0] == 200 and dt < 1.05, dt)
    check("aucun calcul en attente à la fin", offload.pending() == 0, offload.pending())
    srv.close()
    offload.shutdown()
    if FAILED[0] > 0:
        raise("AssertionError", str(FAILED[0]) + " vérification(s) offload en échec")
    print("web.server offload : OK")

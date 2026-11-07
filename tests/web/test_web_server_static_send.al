# ALEX - tests de l'envoi des fichiers statiques par web.server : un gros fichier envoyé à un client lent part en
# arrière-plan sans bloquer les autres requêtes, arrive complet ; versions précompressées (.br, .gz) choisies selon
# Accept-Encoding, Vary, Range et fichiers plus anciens.
# Lancer depuis la racine : ./alex run tests/web/test_web_server_static_send.al
use os
use io
use time
use string as s
use concurrency.thread as thread
use network.tcp as tcp
use web.server as server
use web.server.static_files as sf
from core use len, to_int
from collections use append

const DOSSIER := "/tmp/alex-test-static-send"
const TAILLE := 6000000

func preparer():
    if not os.exists(DOSSIER):
        os.mkdir(DOSSIER)
    morceau := s.repeat("0123456789abcdef", 4096)              # 64 Kio
    parts := []
    i := 0
    while i * 65536 < TAILLE:
        append(parts, morceau)
        i += 1
    io.write_file(os.join(DOSSIER, "gros.bin"), s.byte_slice(s.join("", parts), 0, TAILLE))
    io.write_file(os.join(DOSSIER, "site.css"), "body { color: red }\n")
    io.write_file(os.join(DOSSIER, "site.css.gz"), "GZ")
    io.write_file(os.join(DOSSIER, "site.css.br"), "BR")
    io.write_file(os.join(DOSSIER, "vieux.js.gz"), "périmé")
    time.sleep(1.1)
    io.write_file(os.join(DOSSIER, "vieux.js"), "neuf")         # plus récent que vieux.js.gz : la version .gz est ignorée

func make_app():
    app := server.App()
    app.static("/s", DOSSIER)
    app.get("/vite", (req) => "vite")
    return app

# Requête brute ; rend [statut, en-têtes en minuscules (texte), corps].
func requete(port, path, headers=""):
    c := tcp.connect("127.0.0.1", port, 5.0)
    c.write("GET " + path + " HTTP/1.1\r\nHost: x\r\nConnection: close\r\n" + headers + "\r\n")
    recu := ""
    while true:
        d := c.socket.recv(65536, 5.0)
        if d == "":
            break
        recu = recu + d
    c.close()
    k := s.byte_find(recu, "\r\n\r\n", 0)
    tete := s.byte_slice(recu, 0, k)
    return [to_int(s.substring(tete, 9, 12)), s.lower(tete), s.byte_slice(recu, k + 4, s.byte_len(recu))]

# Client lent : demande le gros fichier, ne lit rien pendant 1,5 s, puis lit tout.
func client_lent(port):
    c := tcp.connect("127.0.0.1", port, 5.0)
    c.write("GET /s/gros.bin HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    time.sleep(1.5)
    total := 0
    recu := ""
    while true:
        d := c.socket.recv(262144, 5.0)
        if d == "":
            break
        if s.byte_len(recu) < 200:
            recu = recu + d
        total += s.byte_len(d)
    c.close()
    return total

# Pendant que le client lent bloque son socket, une requête rapide doit répondre vite.
func client_rapide(port):
    time.sleep(0.4)
    t0 := time.monotonic()
    r := requete(port, "/vite")
    return [r[2], time.monotonic() - t0]

async func drive(srv, threads, limit=30.0):
    t0 := time.monotonic()
    while time.monotonic() - t0 < limit:
        vivant := false
        for t in threads:
            if t.is_alive():
                vivant = true
        if not vivant:
            return
        await srv.serve_for_async(0.02)

ECHECS := []

func check(nom, ok, detail=null):
    if ok:
        print("  [OK]      " + nom)
    else:
        print("  [ÉCHEC]   " + nom + (" : " + str(detail) if detail != null else ""))
        append(ECHECS, nom)

if thread.is_main():
    preparer()
    srv := server.Server(make_app(), server.config("127.0.0.1", 0)).start()
    port := srv.port()
    ts := [thread.spawn(client_lent, [port]), thread.spawn(client_rapide, [port])]
    await drive(srv, ts)
    total := ts[0].join(1.0)
    rapide := ts[1].join(1.0)
    entete := 200
    check("gros fichier complet (en-têtes + 6 000 000 octets)", total != null and total > TAILLE and total < TAILLE + 400, total)
    check("requête rapide servie pendant l'envoi bloqué", rapide != null and rapide[0] == "vite" and rapide[1] < 0.5, rapide)
    vars := [["gzip, deflate, br", "br", "BR"], ["gzip", "gzip", "GZ"], ["br;q=0, gzip", "gzip", "GZ"], ["*", "br", "BR"], ["gzip;q=0", null, "body { color: red }\n"], ["", null, "body { color: red }\n"]]
    resultats := []
    for v in vars:
        append(resultats, thread.spawn(requete, [port, "/s/site.css", ("Accept-Encoding: " + v[0] + "\r\n") if v[0] != "" else ""]))
    append(resultats, thread.spawn(requete, [port, "/s/site.css", "Accept-Encoding: gzip\r\nRange: bytes=0-3\r\n"]))
    append(resultats, thread.spawn(requete, [port, "/s/vieux.js", "Accept-Encoding: gzip\r\n"]))
    await drive(srv, resultats)
    i := 0
    for v in vars:
        r := resultats[i].join(1.0)
        enc := v[1]
        ok := r[0] == 200 and r[2] == v[2] and s.contains(r[1], "vary: accept-encoding") and s.contains(r[1], "content-type: text/css")
        if enc != null:
            ok = ok and s.contains(r[1], "content-encoding: " + enc)
        else:
            ok = ok and not s.contains(r[1], "content-encoding")
        check("Accept-Encoding « " + v[0] + " » -> " + str(enc), ok, r)
        i += 1
    r := resultats[i].join(1.0)
    check("Range : fichier d'origine", r[0] == 206 and r[2] == "body" and not s.contains(r[1], "content-encoding"), r)
    r = resultats[i + 1].join(1.0)
    check("version précompressée plus ancienne ignorée", r[2] == "neuf" and not s.contains(r[1], "content-encoding"), r)
    check("aucune erreur serveur", len(srv.errors) == 0, srv.errors)
    srv.close()
    print(str(len(ECHECS)) + " échec(s)")
    if len(ECHECS) > 0:
        raise("AssertionError", str(len(ECHECS)) + " test(s) d'envoi statique en échec")

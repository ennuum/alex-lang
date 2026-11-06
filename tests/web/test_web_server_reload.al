# ALEX - tests du rechargement à chaud de web.server.workers : un programme serveur écrit dans un dossier
# temporaire est servi par un Supervisor qui surveille ses fichiers ; modifier le fichier change la réponse ; une
# erreur de syntaxe n'arrête pas la surveillance ; la correction relance le service.
# Lancer depuis la racine : ./alex run tests/web/test_web_server_reload.al
use os
use io
use time
use network.tcp as tcp
use web.server.workers as workers
use web.http.protocol_parser as pp
from core use len
from collections use append

DIR := os.join(os.tmp_dir(), "alex_reload_" + str(os.pid()))
PROG := os.join(DIR, "app.al")
ALEX := os.getenv("ALEX_EXE") if os.getenv("ALEX_EXE") != null else "alex"

func programme(message):
    return "use web.server as server\nuse web.server.workers as workers\napp := server.App()\napp.get(\"/\", (req) => \"" + message + "\")\nawait workers.serve(app, \"127.0.0.1\", 0, 1, null, true)\n"

func fetch(port):
    try:
        c := tcp.connect("127.0.0.1", port, 1.0)
        c.write("GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
        p := pp.ResponseParser("GET")
        out := []
        while len(out) == 0:
            d := c.socket.recv(65536, 3.0)
            if d == "":
                for m in p.finish():
                    append(out, m)
                break
            for m in p.feed(d):
                append(out, m)
        c.close()
        return out[0].body if len(out) > 0 else null
    catch e:
        return null

# Fait tourner la surveillance jusqu'à ce que / réponde attendu (au plus limit secondes).
func until(sup, attendu, limit=30.0):
    t0 := time.monotonic()
    while time.monotonic() - t0 < limit:
        sup.step()
        sup.reload_if_changed(2.0)
        if fetch(sup.port) == attendu:
            return true
        time.sleep(0.2)
    return false

FAILED := [0]

func check(name, cond, detail=""):
    if cond:
        print("  ok   " + name)
    else:
        FAILED[0] = FAILED[0] + 1
        print("  ÉCHEC " + name + " : " + str(detail))

os.mkdir_all(DIR)
io.write_file(PROG, programme("version 1"))
sup := workers.Supervisor(1, "127.0.0.1", 0, [ALEX, "run", PROG, "--"])
sup.watch([DIR], true)
sup.start()
check("première version servie", sup.wait_ready(30.0) and fetch(sup.port) == "version 1")
time.sleep(1.1)
io.write_file(PROG, programme("version 2"))
check("modification : nouvelle version servie", until(sup, "version 2"), fetch(sup.port))
check("un rechargement compté", sup.reloads == 1, sup.reloads)
time.sleep(1.1)
io.write_file(PROG, "ceci n'est pas du ALEX valide (\n")
t0 := time.monotonic()
while time.monotonic() - t0 < 8.0 and not sup.workers[0].given_up:
    sup.step()
    sup.reload_if_changed(2.0)
    time.sleep(0.2)
check("erreur de syntaxe : ouvrier abandonné, maître toujours là", sup.workers[0].given_up and fetch(sup.port) == null)
time.sleep(1.1)
io.write_file(PROG, programme("version 3"))
check("correction : service relancé", until(sup, "version 3"), fetch(sup.port))
sup.stop(5.0)
check("arrêt", sup.alive_count() == 0)
os.rmdir(DIR, true)
if FAILED[0] > 0:
    raise("AssertionError", str(FAILED[0]) + " vérification(s) de rechargement en échec")
print("web.server.workers rechargement : OK")

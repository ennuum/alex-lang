# Test de network.http_client (et de url, http_headers, http_cookies, compression, http_multipart,
# connection_pool, retry, proxy) contre un serveur HTTP/1.1 de référence en Python (multi-fils, keep-alive),
# et contre un mandataire CONNECT écrit en Alex.

from core use len, type
from collections use append
use string as s
use process as proc
use io
use os
use concurrency.thread as thread
use network.http_client as hc
use network.retry as rt
use network.proxy as px
use network.security as sec
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

func error_of(f):
    try:
        f()
    catch e:
        return e.type
    return "aucune erreur"

# Mandataire CONNECT dans un fil (le fil a sa propre VM : il ouvre lui-même son socket).
func tunnel_main(n):
    t := px.TunnelServer("127.0.0.1", 0)
    thread.send(t.port())
    t.serve(n)
    t.close()
    return t.tunnels

if thread.is_main():
    if proc.which("python3") == null:
        print("test_http_client : python3 absent, test ignoré")
    else:
        py := proc.Command("python3").args(["tests/network/http_client_test_server.py"]).stdout("pipe").stderr("null").spawn()
        port := s.trim(py.read_line("stdout", 10.0))
        base := "http://127.0.0.1:" + port + "/"
        c := hc.Client(base, {"X-Client": "alex"}, 5.0)

        # requêtes de base, paramètres, en-têtes
        r := c.get("echo", {"x": "1", "y": "é"})
        e := r.json()
        check_eq(r.status, 200, "GET statut")
        check_eq(e["query"], "x=1&y=%C3%A9", "paramètres encodés")
        check_eq(e["headers"]["x-client"], "alex", "en-tête par défaut du client")
        check_eq(e["headers"]["connection"], "keep-alive", "keep-alive annoncé")
        check_eq(e["headers"]["accept-encoding"], "gzip, deflate", "Accept-Encoding")
        check_eq(r.content_type(), "application/json", "content_type()")
        check(r.elapsed >= 0, "elapsed")

        # réutilisation des connexions
        ids := []
        for i in 0..4:
            append(ids, c.get("conn").text())
        check_eq([ids[1], ids[2], ids[3]], [ids[0], ids[0], ids[0]], "keep-alive : même connexion")
        check(c.pool.stats()["reused"] >= 3, "réserve : réutilisations comptées")
        check_eq(c.get("closeidle").text(), "puis fermeture", "réponse avant fermeture")
        check_eq(c.get("echo").status, 200, "connexion fermée par le serveur : reprise transparente")

        # corps
        check_eq(c.post("echo", "brut").json()["body"], "brut", "POST str")
        p := c.post("echo", null, {"nom": "Alex", "n": [1, 2]}).json()
        check_eq([p["body"], p["headers"]["content-type"]], ["{\"n\":[1,2],\"nom\":\"Alex\"}", "application/json"], "POST JSON")
        f := c.post("echo", {"a": "1 2", "b": "é"}).json()
        check_eq([f["body"], f["headers"]["content-type"]], ["a=1+2&b=%C3%A9", "application/x-www-form-urlencoded"], "POST formulaire")
        check_eq(c.put("echo", "x").json()["method"], "PUT", "PUT")
        check_eq(c.patch("echo", null, {"k": 1}).json()["method"], "PATCH", "PATCH")
        check_eq(c.delete("echo").json()["method"], "DELETE", "DELETE")
        check_eq(c.options("echo").json()["method"], "OPTIONS", "OPTIONS")
        h := c.head("echo")
        check_eq([h.status, h.content()], [200, ""], "HEAD sans corps")
        up := c.post("upload", null, null, {"titre": "Vacances été"}, {"photo": hc.File("plage.jpg", nu.from_bytes([0, 1, 2, 255, 13, 10]))}).json()
        check_eq(up["titre"], "Vacances été", "multipart : champ")
        check_eq([up["photo"]["filename"], up["photo"]["size"], up["photo"]["type"]], ["plage.jpg", 6, "image/jpeg"], "multipart : fichier")
        check_eq(up["photo"]["sha256"], sec.digest_hex(nu.from_bytes([0, 1, 2, 255, 13, 10])), "multipart : octets intacts")

        # corps de réponse
        check_eq(c.get("chunked").text(), "morceau 1, morceau 2 — été, fin", "chunked")
        check_eq(c.get("close").text(), "corps jusqu'à la fermeture", "jusqu'à la fermeture")
        check_eq(c.get("gzip").text(), "compressé gzip " * 50, "gzip décodé")
        check_eq(c.get("deflate").text(), "compressé deflate " * 50, "deflate décodé")
        big := c.get("big")
        check_eq(nu.byte_len(big.content()), 1048576, "1 Mio")
        check_eq(nu.byte_at(big.content(), 1000), 1000 % 251, "1 Mio : contenu")
        st := c.get("big", null, null, null, true)
        total := 0
        chunks := 0
        while true:
            d := st.read_chunk(100000)
            if d == null:
                break
            total += nu.byte_len(d)
            chunks += 1
        check_eq(total, 1048576, "flux : taille")
        check(chunks >= 11, "flux : plusieurs morceaux")
        dl := "/tmp/alex_http_client_dl.bin"
        c.download("big", dl)
        check_eq(os.size(dl), 1048576, "download vers un fichier")
        os.remove(dl)
        small := hc.Client(base, null, 5.0, true, null, null, true, true, 10, null, null, null, null, null, 1000)
        check_eq(error_of(() => small.get("big")), "HttpError", "max_body")
        small.close()

        # redirections
        rr := c.get("redirect/3")
        check_eq([rr.status, len(rr.history), rr.url], [200, 3, base + "echo"], "redirections suivies, historique")
        check_eq(c.request("GET", "redirect/1", null, null, null, null, null, null, null, false, false).status, 302, "redirection non suivie")
        so := c.post("see-other", "corps").json()
        check_eq([so["method"], so["body"]], ["GET", ""], "303 -> GET sans corps")
        t7 := c.post("temporary", "gardé").json()
        check_eq([t7["method"], t7["body"]], ["POST", "gardé"], "307 garde méthode et corps")
        other := "http://localhost:" + port + "/echo"
        cr := c.get("cross", {"to": other}, {"Authorization": "Bearer secret", "Cookie": "a=1"}).json()
        check_eq([cr["headers"]["authorization"] if "authorization" in cr["headers"] else null], [null], "Authorization retiré vers une autre origine")
        check(not ("cookie" in cr["headers"]), "Cookie retiré vers une autre origine")
        few := hc.Client(base, null, 5.0, true, null, null, true, true, 2)
        check_eq(error_of(() => few.get("redirect/5")), "HttpError", "trop de redirections")
        few.close()

        # statuts
        n4 := c.get("status/404")
        check_eq([n4.status, n4.reason, n4.ok()], [404, "Not Found", false], "404")
        check_eq(error_of(() => n4.raise_for_status()), "HttpError", "raise_for_status")
        check_eq(c.get("status/204").content(), "", "204")

        # cookies
        c.get("cookie/set", {"sid": "abc", "theme": "sombre"})
        ck := c.get("cookie/get").text()
        check(s.contains(ck, "sid=abc") and s.contains(ck, "theme=sombre"), "cookies renvoyés")
        check_eq(c.cookies.get("sid"), "abc", "bocal")

        # authentification
        check_eq(c.get("basic").status, 401, "Basic absent")
        ba := hc.Client(base, null, 5.0, true, null, ("alice", "secret"))
        check_eq(ba.get("basic").text(), "bienvenue alice", "Basic")
        check_eq(ba.get("digest").text(), "digest ok", "Digest (MD5, qop=auth)")
        check_eq(ba.get("digest").text(), "digest ok", "Digest : nonce réutilisé (nc=2)")
        ba.close()
        check_eq(hc.Client("http://alice:secret@127.0.0.1:" + port + "/", null, 5.0).get("basic").status, 200, "identifiants dans l'URL")

        # nouvelles tentatives
        waits := []
        rp := rt.RetryPolicy(4, 0.0)
        rc := hc.Client(base, null, 5.0, true, null, null, true, true, 10, rp)
        check_eq(rc.get("retry", {"key": "a"}).text(), "réussi après 3 essais", "503 retenté (Retry-After)")
        rc.close()
        check_eq(c.get("retry", {"key": "b"}).status, 503, "sans politique : pas de nouvel essai")

        # délais et erreurs
        check_eq(error_of(() => c.get("slow", null, null, 0.5)), "TimeoutError", "délai de lecture")
        check_eq(error_of(() => hc.Client(null, null, 2.0).get("http://127.0.0.1:1/")), "NetworkError", "connexion refusée")
        check_eq(error_of(() => c.get("ftp://x/")), "HttpError", "schéma refusé")
        check_eq(error_of(() => c.get("echo", null, {"X": "a\r\nInjecté: 1"})), "HttpError", "injection d'en-tête refusée")

        # crochets
        seen := []
        c.add_hook("request", (m, u, hh) => seen.append(m + " " + u))
        c.add_hook("response", (resp) => seen.append(str(resp.status)))
        c.get("echo")
        check_eq(seen, ["GET " + base + "echo", "200"], "crochets requête / réponse")

        # mandataire CONNECT écrit en Alex (dans un fil) : http:// passe en forme absolue, donc un tunnel
        # n'est utilisé que pour https ; ici on vérifie le tunnel TCP brut avec proxy.connect
        tw := thread.spawn(tunnel_main, [1])
        pport := tw.receive(5.0)
        tc := px.connect("http://127.0.0.1:" + str(pport), "127.0.0.1", port, 5.0)
        tc.write("GET /echo HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
        check_eq(tc.read_line(5.0), "HTTP/1.1 200 OK", "tunnel CONNECT Alex")
        tc.read_all(5.0)
        tc.close()
        check_eq(tw.join(10.0), 1, "mandataire : un tunnel servi")

        c.close()
        check_eq(c.pool.stats()["idle"], 0, "close() vide la réserve")
        hc.get(base + "shutdown")
        py.wait(10.0)
        py.close()

    print(f"http_client : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_http_client : échecs")

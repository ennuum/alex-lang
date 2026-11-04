# Test du module network.http.
# 1. Outils d'URL (fonctions pures).
# 2. Client Alex contre un serveur de référence en Python (tests/network/http_test_server.py).
# 3. Serveur Alex contre curl (si présent), et client Alex contre un serveur Alex dans un processus fils.
# Les parties 2 et 3 sont ignorées si python3 / curl sont absents.

from core use len, type
from collections use append, keys, contains_key
use string as s
use os
use process as proc
use network.http as http

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

last_message := [""]
func error_of(f):
    try:
        f()
    catch e:
        last_message[0] = e.message
        return e.type
    return "aucune erreur"

# ---------------------------------------------------------------- 1. URL
check_eq(http.url_encode("a b&c=d/é~_.-"), "a%20b%26c%3Dd%2F%C3%A9~_.-", "url_encode")
check_eq(http.url_encode("a b", true), "a+b", "url_encode formulaire")
check_eq(http.url_decode("a%20b%26%C3%A9"), "a b&é", "url_decode")
check_eq(http.url_decode("a+b", true), "a b", "url_decode formulaire")
check_eq(http.url_decode("100%"), "100%", "url_decode « % » final")
check_eq(http.parse_query("a=1&b=x+y&c=%C3%A9&d"), {"a": "1", "b": "x y", "c": "é", "d": ""}, "parse_query")
check_eq(http.parse_query(http.encode_query({"nom": "Zoé Δ", "n": 3})), {"nom": "Zoé Δ", "n": "3"}, "encode_query aller-retour")
check_eq(http.encode_query({"t": ["a", "b"]}), "t=a&t=b", "encode_query liste")

u := http.parse_url("http://exemple.org:8080/a/b.html?x=1&y=2#haut")
check_eq([u.scheme, u.host, u.port, u.path, u.query, u.fragment], ["http", "exemple.org", 8080, "/a/b.html", "x=1&y=2", "haut"], "parse_url complète")
check_eq(u.target(), "/a/b.html?x=1&y=2", "Url.target")
check_eq(u.authority(), "exemple.org:8080", "Url.authority")
check_eq(http.parse_url("http://exemple.org").target(), "/", "chemin par défaut")
check_eq(http.parse_url("http://exemple.org?q=1").target(), "/?q=1", "requête sans chemin")
check_eq(http.parse_url("https://exemple.org/").port, 443, "port https par défaut")
check_eq(http.parse_url("HTTP://Exemple.org/").scheme, "http", "schéma en minuscules")
v6 := http.parse_url("http://[::1]:9000/x")
check_eq([v6.host, v6.port, v6.authority()], ["::1", 9000, "[::1]:9000"], "parse_url IPv6")
check_eq(http.parse_url("http://user:pw@hote/").host, "hote", "parse_url avec identifiants")
check_eq(error_of(() => http.parse_url("ftp://x/")), "HttpError", "schéma non pris en charge")
check_eq(error_of(() => http.parse_url("exemple.org/")), "HttpError", "sans schéma")
check_eq(error_of(() => http.parse_url("http://h:99999/")), "HttpError", "port hors limites")
check_eq(error_of(() => http.parse_url("http://h:abc/")), "HttpError", "port non numérique")
check_eq(error_of(() => http.parse_url("http:///chemin")), "HttpError", "hôte manquant")
check_eq(error_of(() => http.parse_url(42)), "TypeError", "URL non str")
b := http.parse_url("http://h:81/a/b/c?q")
check_eq(http.resolve_url(b, "d"), "http://h:81/a/b/d", "resolve_url relative")
check_eq(http.resolve_url(b, "/x"), "http://h:81/x", "resolve_url absolue au serveur")
check_eq(http.resolve_url(b, "//autre/y"), "http://autre/y", "resolve_url sans schéma")
check_eq(http.resolve_url(b, "http://z/"), "http://z/", "resolve_url absolue")
check_eq(http.reason_phrase(404), "Not Found", "reason_phrase")
check_eq(error_of(() => http.get("https://127.0.0.1:1/", null, 2.0)), "NetworkError", "https : serveur absent")
check_eq(error_of(() => http.post("http://127.0.0.1:1/", 42)), "TypeError", "corps non str")
check_eq(error_of(() => http.get("http://127.0.0.1:1/", null, 2.0)), "NetworkError", "serveur absent")

# ---------------------------------------------------------------- 2. client contre Python
func have(program):
    return proc.which(program) != null

if have("python3"):
    py := proc.Command("python3").args(["tests/network/http_test_server.py"]).stdout("pipe").stderr("null").spawn()
    port := s.trim(py.read_line("stdout", 10.0))
    base := "http://127.0.0.1:" + port
    r := http.get(base + "/echo?x=1&y=%C3%A9", {"X-Essai": "oui"})
    check_eq(r.status, 200, "GET : statut")
    check(r.ok(), "GET : ok()")
    check_eq(r.header("Content-Type"), "application/json", "en-tête insensible à la casse")
    e := r.json()
    check_eq(e["method"], "GET", "méthode reçue")
    check_eq(e["query"], "x=1&y=%C3%A9", "requête reçue")
    check_eq(e["headers"]["x-essai"], "oui", "en-tête envoyé")
    check_eq(e["headers"]["host"], "127.0.0.1:" + port, "Host envoyé")
    check_eq(e["headers"]["connection"], "close", "Connection: close")
    p := http.post_json(base + "/echo", {"nom": "Alex", "n": [1, 2]}).json()
    check_eq(p["method"], "POST", "post_json : méthode")
    check_eq(p["headers"]["content-type"], "application/json", "post_json : type")
    check_eq(p["body"], "{\"n\":[1,2],\"nom\":\"Alex\"}", "post_json : corps")
    check_eq(http.post_form(base + "/echo", {"a": "1 2"}).json()["body"], "a=1+2", "post_form")
    check_eq(http.put(base + "/echo", "données").json()["body"], "données", "PUT")
    check_eq(http.delete(base + "/echo").json()["method"], "DELETE", "DELETE")
    h := http.head(base + "/utf8")
    check_eq([h.status, h.body], [200, ""], "HEAD : pas de corps")
    c := http.get(base + "/chunked")
    check_eq(c.text(), "morceau 1, morceau 2 — été, fin", "corps chunked (avec extensions et trailer)")
    check_eq(http.get(base + "/close").text(), "corps jusqu'à la fermeture", "corps jusqu'à la fermeture")
    check_eq(http.get(base + "/utf8").text(), "Bonjour, ça marche : 日本語 ✓", "texte UTF-8")
    bin := http.get(base + "/binary").bytes()
    check_eq(len(bin), 256, "binaire : taille")
    check_eq([bin[0], bin[10], bin[13], bin[255]], [0, 10, 13, 255], "binaire : octets intacts")
    rr := http.get(base + "/redirect/3")
    check_eq([rr.status, http.parse_url(rr.url).path], [200, "/echo"], "trois redirections suivies")
    check_eq(http.request("GET", base + "/redirect/1", null, null, 5.0, false).status, 302, "redirection non suivie")
    check_eq(error_of(() => http.get(base + "/redirect-loop")), "HttpError", "boucle de redirections")
    so := http.post(base + "/see-other", "corps")
    check_eq([so.json()["method"], so.json()["body"]], ["GET", ""], "303 : GET sans corps")
    t7 := http.post(base + "/temporary", "gardé")
    check_eq([t7.json()["method"], t7.json()["body"]], ["POST", "gardé"], "307 : méthode et corps gardés")
    check_eq(http.get(base + "/relative").json()["query"], "rel=1", "redirection relative")
    n4 := http.get(base + "/status/404")
    check_eq([n4.status, n4.reason, n4.text(), n4.ok()], [404, "Not Found", "statut 404", false], "404")
    check_eq(error_of(() => n4.raise_for_status()), "HttpError", "raise_for_status")
    check_eq(http.get(base + "/status/204").body, "", "204 sans corps")
    check_eq(error_of(() => http.get(base + "/slow", null, 0.5)), "TimeoutError", "délai de réponse")
    http.get(base + "/shutdown")
    py.wait(10.0)
    py.close()
else:
    print("test_http : python3 absent, client contre Python ignoré")

# ---------------------------------------------------------------- 3a. serveur Alex contre curl
func handler(req):
    if req.path == "/bonjour":
        return http.text("Bonjour " + req.param("nom", "inconnu") + " !\n", 200, {"X-Serveur": "alex"})
    if req.path == "/json":
        v := req.json()
        return http.json_response({"recu": v["valeur"], "methode": req.method}, 201)
    if req.path == "/panne":
        raise("ValueError", "panne volontaire")
    return http.text("introuvable\n", 404)

if have("curl"):
    srv := http.Server("127.0.0.1", 0)
    url := srv.url()
    func curl(args):
        p := proc.Command("curl").args(args).stdout("pipe").spawn()
        srv.handle_one(handler, 10.0)
        out := p.read_all()
        p.wait(10.0)
        p.close()
        return out
    out := curl(["-s", "-i", url + "bonjour?nom=Z%C3%A9lie"])
    check(s.starts_with(out, "HTTP/1.1 200 OK\r\n"), "curl : statut")
    check(s.contains(out, "X-Serveur: alex\r\n"), "curl : en-tête du gestionnaire")
    check(s.contains(out, "Content-Length: 17\r\n"), "curl : Content-Length (octets)")
    check(s.ends_with(out, "\r\n\r\nBonjour Zélie !\n"), "curl : corps")
    out = curl(["-s", "-X", "POST", "-H", "Content-Type: application/json", "-d", "{\"valeur\": 42}", url + "json"])
    check_eq(out, "{\"methode\":\"POST\",\"recu\":42}", "curl : POST JSON")
    out = curl(["-s", "-o", "/dev/null", "-w", "%{http_code}", url + "panne"])
    check_eq(out, "500", "curl : exception -> 500")
    check_eq(len(srv.errors), 1, "erreur du gestionnaire notée")
    check(s.contains(srv.errors[0], "panne volontaire"), "message de l'erreur notée")
    out = curl(["-s", "-o", "/dev/null", "-w", "%{http_code}", url + "absent"])
    check_eq(out, "404", "curl : 404")
    out = curl(["-s", "-I", url + "bonjour"])
    check(s.starts_with(out, "HTTP/1.1 200 OK"), "curl : HEAD")
    check_eq(srv.handled, 5, "requêtes traitées")
    # Requête mal formée : 400.
    raw := proc.Command("python3").args(["-c", "import socket,sys; c=socket.create_connection(('127.0.0.1'," + str(srv.port()) + ")); c.sendall(b'N IMPORTE QUOI\\r\\n\\r\\n'); print(c.recv(100).decode().split(chr(13))[0])"]).stdout("pipe").spawn()
    srv.handle_one(handler, 10.0)
    check_eq(s.trim(raw.read_all()), "HTTP/1.1 400 Bad Request", "requête mal formée : 400")
    raw.wait(10.0)
    raw.close()
    srv.close()
else:
    print("test_http : curl absent, serveur contre curl ignoré")

# ---------------------------------------------------------------- 3b. client Alex contre serveur Alex
alex := "./alex"
if not os.exists(alex):
    alex = "alex"
child := proc.Command(alex).args(["run", "tests/network/http_alex_server.al"]).stdout("pipe").spawn()
aport := s.trim(child.read_line("stdout", 20.0))
abase := "http://127.0.0.1:" + aport
check_eq(http.get(abase + "/bonjour?nom=%C3%89lodie").text(), "Bonjour Élodie !\n", "Alex ↔ Alex : GET")
j := http.post_json(abase + "/json", {"x": 1})
check_eq([j.status, j.json()["x"], j.json()["vu_par_le_serveur"]], [201, 1, true], "Alex ↔ Alex : POST JSON")
check_eq(http.post_form(abase + "/form", {"a": "é", "b": "x&y"}).text(), "é|x&y", "Alex ↔ Alex : formulaire")
rd := http.get(abase + "/redirige")
check_eq(rd.text(), "Bonjour redirigé !\n", "Alex ↔ Alex : redirection")
check_eq(http.get(abase + "/erreur").status, 500, "Alex ↔ Alex : exception -> 500")
check_eq(http.get(abase + "/vide").status, 204, "Alex ↔ Alex : null -> 204")
check_eq(http.get(abase + "/absent").status, 404, "Alex ↔ Alex : 404")
check_eq(http.get(abase + "/stop").text(), "arrêt\n", "Alex ↔ Alex : arrêt")
child.wait(10.0)
child.close()

print(f"http : {stats[0]} vérifications OK, {stats[1]} échec(s)")
for n in notes:
    print("  ÉCHEC " + n)
if stats[1] > 0:
    raise("TestError", "test_http : échecs")

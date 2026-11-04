# Test du module network.tls et de https dans network.http.
# 1. Usage et erreurs (sans réseau).
# 2. Client Alex contre un serveur TLS de référence en Python (tests/network/tls_test_server.py).
# 3. Serveur Alex contre un client Python (autre pile TLS : ssl de Python).
# 4. Client Alex contre serveur Alex (processus fils), TLS brut et HTTPS.
# Le certificat de test est généré par openssl au début ; sans openssl ou python3 les parties concernées sont
# ignorées ; sans OpenSSL (libssl) le test s'ignore entièrement (network.tls.supported() == false).

from core use len, type, to_int
from collections use append, keys, contains_key
use string as s
use os
use filesystem as fs
use process as proc
use network.tls as tls
use network.tcp as tcp
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

func have(program):
    return proc.which(program) != null

func finish():
    print(f"tls : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_tls : échecs")

if not tls.supported():
    print("test_tls : TLS indisponible (" + tls.why() + "), test ignoré")
else:
    # ------------------------------------------------------------ 1. usage et erreurs
    check(s.contains(tls.library_version(), "OpenSSL"), "library_version")
    check_eq(tls.open_count(), 0, "aucune session au départ")
    check_eq(error_of(() => tls.listen("127.0.0.1", 0)), "ArgumentError", "listen sans certificat")
    check_eq(error_of(() => tls.listen("127.0.0.1", 0, "/inexistant/c.pem", "/inexistant/k.pem")), "ArgumentError", "listen : fichiers illisibles")
    check_eq(error_of(() => tls.connect("127.0.0.1", 1, 1.0)), "NetworkError", "connexion refusée")
    check_eq(error_of(() => tls.connect("127.0.0.1", 1, 1.0, "oui")), "TypeError", "verify non booléen")
    check_eq(error_of(() => tls.connect("127.0.0.1", 1, 1.0, true, null, "http/1.1")), "TypeError", "alpn non liste")
    check_eq(error_of(() => tls.connect("127.0.0.1", 1, 1.0, true, null, [""])), "TypeError", "alpn : protocole vide")
    check_eq(error_of(() => tls.connect("127.0.0.1", 1, -1.0)), "ArgumentError", "délai négatif")

    # Serveur muet (TCP simple) : la poignée de main dépasse son délai.
    quiet := tcp.listen("127.0.0.1", 0)
    check_eq(error_of(() => tls.connect("127.0.0.1", quiet.port(), 0.4)), "TimeoutError", "poignée de main : délai dépassé")
    quiet.close()

    if not have("openssl"):
        print("test_tls : openssl absent, suite avec certificat ignorée")
        finish()
    else:
        tmp := os.tmp_dir() + "/alex_tls_test_" + str(os.pid())
        fs.remove_tree(tmp, true)
        os.mkdir_all(tmp)
        cert := tmp + "/cert.pem"
        key := tmp + "/key.pem"
        gen := proc.run("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "2", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"], null, 60.0)
        check_eq(gen.code, 0, "openssl : certificat de test généré")

        # -------------------------------------------------------- 2. client Alex contre Python
        if have("python3"):
            py := proc.Command("python3").args(["tests/network/tls_test_server.py", cert, key]).stdout("pipe").stderr("null").spawn()
            port := to_int(s.trim(py.read_line("stdout", 10.0)))
            c := tls.connect("127.0.0.1", port, 5.0, true, cert, ["http/1.1"])
            sk := c.socket
            check(s.starts_with(sk.version, "TLSv1."), "version négociée " + sk.version)
            check(sk.cipher != "", "chiffrement négocié")
            check_eq(sk.alpn, "http/1.1", "ALPN négocié")
            check_eq(sk.verify_result, 0, "certificat vérifié")
            check(s.contains(sk.peer_subject, "CN=localhost"), "sujet du certificat du serveur")
            c.write_line("echo héllo ✓ 日本語")
            check_eq(c.read_line(5.0), "héllo ✓ 日本語", "écho UTF-8 chiffré")
            c.write_line("info")
            info := s.split(c.read_line(5.0), "|")
            check_eq([info[1], s.starts_with(info[0], "TLSv1.")], ["http/1.1", true], "le serveur voit la même négociation")
            c.write_line("big 200000")
            big := c.read_line(10.0)
            check_eq(len(big), 200000, "200 000 octets reçus (plusieurs enregistrements TLS)")
            payload := s.repeat("z", 300000)
            c.write_line("recv 300000")
            c.write(payload, 10.0)
            check_eq(c.read_line(10.0), "300000", "300 000 octets envoyés et reçus intacts par le serveur")
            # délai : rien à lire, la connexion reste utilisable après
            check_eq(error_of(() => c.read_line(0.3)), "TimeoutError", "lecture : délai dépassé")
            check_eq(c.socket.try_recv(), null, "try_recv : rien de prêt")
            c.write_line("echo encore")
            check_eq(c.read_line(5.0), "encore", "connexion utilisable après un délai")
            c.write_line("bye")
            check_eq(c.read_line(5.0), null, "fin du flux après close_notify")
            check(c.socket.received_close_notify(), "close_notify reçu")
            c.close()
            c.close()
            check(c.is_closed(), "fermeture idempotente")
            check_eq(error_of(() => c.write("x")), "ArgumentError", "écriture sur une session fermée")

            a := tls.connect("127.0.0.1", port, 5.0, true, cert)
            a.write_line("abort")
            check_eq(error_of(() => a.read_line(5.0)), "TlsError", "coupure sans close_notify refusée (strict_eof)")
            a.close()
            l := tls.connect("127.0.0.1", port, 5.0, true, cert, null, 0, null, null, null, false)
            l.write_line("abort")
            check_eq(l.read_line(5.0), null, "strict_eof=false : coupure vue comme fin de flux")
            l.close()

            check_eq(error_of(() => tls.connect("127.0.0.1", port, 5.0, true, cert, null, 0, "autre.exemple")), "TlsError", "nom différent refusé")
            check(s.contains(last_message[0], "mismatch"), "message : nom ne correspond pas (" + last_message[0] + ")")
            check_eq(error_of(() => tls.connect("127.0.0.1", port, 5.0)), "TlsError", "certificat auto-signé refusé par défaut")
            check(s.contains(last_message[0], "self-signed") or s.contains(last_message[0], "self signed"), "message : auto-signé (" + last_message[0] + ")")
            check_eq(error_of(() => tls.connect("127.0.0.1", port, 5.0, true, tmp + "/absent.pem")), "ArgumentError", "fichier d'autorités illisible")
            v := tls.connect("127.0.0.1", port, 5.0, false)
            v.write_line("echo sans verification")
            check_eq(v.read_line(5.0), "sans verification", "verify=false : connexion sans contrôle")
            v.write_line("bye")
            v.close()
            n := tls.connect("localhost", port, 5.0, true, cert)
            check(s.contains(n.socket.peer_subject, "localhost"), "connexion par nom d'hôte (SNI et nom vérifiés)")
            n.write_line("bye")
            n.close()

            # ---- https dans network.http
            base := "https://127.0.0.1:" + str(port)
            r := http.get(base + "/hello", null, 5.0, true, cert)
            check_eq([r.status, r.text()], [200, "bonjour TLS ✓"], "https GET")
            check_eq(http.get(base + "/chunked", null, 5.0, true, cert).text(), "hello, woré", "https : corps chunked")
            check_eq(http.get(base + "/untilclose", null, 5.0, true, cert).text(), "corps jusqu'a la fermeture propre", "https : corps jusqu'à close_notify")
            check_eq(error_of(() => http.get(base + "/truncated", null, 5.0, true, cert)), "TlsError", "https : corps tronqué détecté")
            body := http.get(base + "/big", null, 10.0, true, cert).bytes()
            check_eq(len(body), 300000, "https : 300 000 octets")
            check_eq([body[0], body[250], body[251], body[299999]], [0, 250, 0, 299999 % 251], "https : octets intacts")
            check_eq(error_of(() => http.get(base + "/hello", null, 5.0)), "TlsError", "https : certificat inconnu refusé par défaut")
            check_eq(http.get(base + "/hello", null, 5.0, false).status, 200, "https : verify=false")
            auth := {"Authorization": http.basic_auth("u", "p"), "Cookie": "sid=1", "X-Garde": "oui"}
            h1 := http.get(base + "/headers", auth, 5.0, true, cert).json()
            check_eq([h1["authorization"], h1["cookie"], h1["x-garde"]], ["Basic dTpw", "sid=1", "oui"], "en-têtes envoyés")
            h2 := http.get(base + "/redirect-same", auth, 5.0, true, cert).json()
            check_eq(h2["authorization"], "Basic dTpw", "redirection même origine : Authorization gardée")
            h3 := http.get(base + "/redirect-other", auth, 5.0, true, cert).json()
            check_eq([contains_key(h3, "authorization"), contains_key(h3, "cookie"), h3["x-garde"]], [false, false, "oui"], "autre origine : Authorization et Cookie retirés")
            check(s.starts_with(h3["host"], "localhost:"), "la redirection a bien changé d'hôte")
            check_eq(http.bearer_auth("abc"), "Bearer abc", "bearer_auth")
            check_eq(error_of(() => http.basic_auth("a:b", "x")), "ArgumentError", "basic_auth : « : » refusé")
            http.get(base + "/shutdown", null, 5.0, true, cert)
            py.wait(10.0)
            py.close()
        else:
            print("test_tls : python3 absent, client contre Python ignoré")

        # -------------------------------------------------------- 3. serveur Alex contre client Python
        if have("python3"):
            srv := tls.listen("127.0.0.1", 0, cert, key, ["h2", "http/1.1"])
            sp := srv.port()
            func py_client(mode):
                return proc.Command("python3").args(["tests/network/tls_test_client.py", str(sp), cert, mode]).stdout("pipe").stderr("null").spawn()
            cl := py_client("line")
            conn := srv.accept(15.0)
            check_eq(conn.read_line(5.0), "salut é", "serveur Alex : ligne reçue du client Python")
            conn.write_line("OK é")
            check_eq(conn.socket.alpn, "http/1.1", "serveur Alex : ALPN choisi")
            check_eq(conn.read_line(5.0), null, "serveur Alex : close_notify du client")
            conn.close()
            out := s.split(s.trim(cl.read_all()), "|")
            check_eq([out[0], out[1]], ["OK é", "http/1.1"], "client Python : réponse et ALPN")
            check(s.starts_with(out[2], "TLSv1."), "client Python : version TLS")
            cl.wait(10.0)
            cl.close()

            bad := py_client("badca")
            check_eq(error_of(() => srv.accept(15.0)), "TlsError", "poignée de main refusée par le client (autorité inconnue)")
            check_eq(s.trim(bad.read_all()), "refused", "client Python : certificat refusé")
            bad.wait(10.0)
            bad.close()
            plain := py_client("plain")
            check_eq(error_of(() => srv.accept(15.0)), "TlsError", "client non TLS : poignée de main refusée")
            plain.wait(10.0)
            plain.close()
            check_eq(srv.failed, 2, "poignées de main refusées comptées")

            # serve() ignore le client en échec et sert le suivant
            noise := py_client("plain")
            good := py_client("line")
            seen := []
            func on_conn(c):
                append(seen, c.read_line(5.0))
                c.write_line("serve")
            check_eq(tls.serve(srv, on_conn, 1), 1, "serve : une connexion servie malgré un client en échec")
            check_eq(seen, ["salut é"], "serve : message reçu")
            check(s.starts_with(s.trim(good.read_all()), "serve|"), "serve : réponse reçue par le bon client")
            good.wait(10.0)
            good.close()
            noise.kill()
            noise.wait(10.0)
            noise.close()
            srv.close()
        else:
            print("test_tls : python3 absent, serveur contre client Python ignoré")

        # -------------------------------------------------------- 4. Alex contre Alex (processus fils)
        alex := "./alex"
        if not os.exists(alex):
            alex = "alex"
        child := proc.Command(alex).args(["run", "tests/network/tls_alex_server.al", cert, key]).stdout("pipe").stderr("null").spawn()
        cport := to_int(s.trim(child.read_line("stdout", 20.0)))
        a2 := tls.connect("127.0.0.1", cport, 10.0, true, cert, ["http/1.1"])
        a2.write_line("echo bonjour é")
        check_eq(a2.read_line(10.0), "BONJOUR é", "Alex ↔ Alex : écho (upper ne touche que l'ASCII)")
        a2.write_line("big 150000")
        check_eq(len(a2.read_line(10.0)), 150000, "Alex ↔ Alex : 150 000 octets")
        a2.write_line("info")
        check(s.ends_with(a2.read_line(10.0), "|http/1.1"), "Alex ↔ Alex : ALPN")
        a2.write_line("bye")
        check_eq(a2.read_line(10.0), null, "Alex ↔ Alex : fin du flux")
        a2.close()
        a3 := tls.connect("127.0.0.1", cport, 10.0, true, cert)
        a3.write_line("stop")
        a3.close()
        child.wait(15.0)
        child.close()

        hchild := proc.Command(alex).args(["run", "tests/network/https_alex_server.al", cert, key]).stdout("pipe").stderr("pipe").spawn()
        hline := hchild.read_line("stdout", 20.0)
        if hline == null:
            print("enfant HTTPS : " + str(hchild.read_all("stderr")))
        hport := s.trim(hline)
        hbase := "https://127.0.0.1:" + hport
        check_eq(http.get(hbase + "/bonjour?nom=Zo%C3%A9", null, 10.0, true, cert).text(), "Bonjour Zoé en TLS !\n", "HTTPS Alex ↔ Alex : GET")
        j := http.post_json(hbase + "/json", {"x": 1}, null, 10.0, true, cert)
        check_eq([j.status, j.json()["x"], j.json()["tls"]], [201, 1, true], "HTTPS Alex ↔ Alex : POST JSON")
        check_eq(error_of(() => http.get(hbase + "/bonjour", null, 10.0)), "TlsError", "HTTPS Alex ↔ Alex : certificat inconnu refusé")
        check_eq(http.get(hbase + "/stop", null, 10.0, true, cert).text(), "arrêt\n", "HTTPS Alex ↔ Alex : arrêt")
        hchild.wait(15.0)
        hchild.close()

        check_eq(tls.open_count(), 0, "toutes les sessions TLS sont fermées")
        fs.remove_tree(tmp, true)
        finish()

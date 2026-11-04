# Test du module network.websocket.
# 1. Unités (sans réseau) : clé RFC, URL, encodage des trames.
# 2. Client Alex contre un serveur de référence en Python (ws_test_server.py, RFC 6455 écrit à la main), en ws:// et wss://.
# 3. Serveur Alex contre un client de référence en Python (ws_test_client.py) : validations côté serveur.
# 4. Alex contre Alex (processus fils), ws:// et wss://.
# Sans python3 les parties 2 et 3 sont ignorées ; sans openssl / libssl les parties wss le sont.

from core use len, type, to_int
from collections use append, contains_key
use string as s
use os
use filesystem as fs
use process as proc
use _native_net as n
use network.websocket as ws
use network.tls as tls

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

func spawn_py(script, extra):
    argv := ["tests/network/" + script]
    for x in extra:
        append(argv, x)
    return proc.Command("python3").args(argv).stdout("pipe").stderr("null").spawn()

# ---------------------------------------------------------------- 1. unités
check_eq(ws.accept_key("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", "Sec-WebSocket-Accept de la RFC 6455")
u := ws.parse_url("ws://exemple.org/chat?salle=1#ancre")
check_eq([u.secure, u.host, u.port, u.target], [false, "exemple.org", 80, "/chat?salle=1"], "parse_url ws://")
u2 := ws.parse_url("WSS://exemple.org:8443")
check_eq([u2.secure, u2.port, u2.target], [true, 8443, "/"], "parse_url wss:// avec port, sans chemin")
check_eq(ws.parse_url("wss://h/x").port, 443, "wss : port 443 par défaut")
check_eq(error_of(() => ws.parse_url("http://exemple.org/")), "WebSocketError", "schéma http refusé")
check_eq(error_of(() => ws.parse_url(12)), "TypeError", "URL non str")
check_eq([ws.valid_close_code(1000), ws.valid_close_code(1005), ws.valid_close_code(1006), ws.valid_close_code(1015), ws.valid_close_code(3000), ws.valid_close_code(4999), ws.valid_close_code(5000), ws.valid_close_code("1000")], [true, false, false, false, true, true, false, false], "codes de fermeture valides")

srv_side := ws.WebSocket(null, false)
check_eq(n.to_bytes(srv_side._frame(1, "Hello")), [129, 5, 72, 101, 108, 108, 111], "trame serveur « Hello » (exemple de la RFC)")
f200 := n.to_bytes(srv_side._frame(2, s.repeat("a", 200)))
check_eq([f200[0], f200[1], f200[2], f200[3], len(f200)], [130, 126, 0, 200, 204], "longueur sur 16 bits")
f70k := n.to_bytes(srv_side._frame(2, s.repeat("a", 70000)))
check_eq([f70k[1], f70k[2], f70k[8], f70k[9], len(f70k)], [127, 0, 17, 112, 70010], "longueur sur 64 bits (70000 = 0x11170)")
check_eq(n.to_bytes(srv_side._frame(1, "ab", false)), [1, 2, 97, 98], "trame non finale (FIN=0)")
cli_side := ws.WebSocket(null, true)
fc := n.to_bytes(cli_side._frame(1, "Hello"))
check_eq([fc[0], fc[1], len(fc)], [129, 133, 11], "trame client : bit de masque et clé de 4 octets")
key := n.bslice(n.from_bytes(fc), 2, 6)
check_eq(n.mask(n.bslice(n.from_bytes(fc), 6, 11), key), "Hello", "la charge utile masquée se démasque")
check_eq(n.mask(n.from_bytes([127, 159, 77, 81, 88]), n.from_bytes([55, 250, 33, 61])), "Hello", "exemple masqué de la RFC (37 fa 21 3d)")
check_eq(error_of(() => srv_side.send_text(5)), "TypeError", "send_text : str attendue")
check_eq(error_of(() => srv_side.send_text(n.from_bytes([255, 254]))), "ArgumentError", "send_text : UTF-8 invalide refusé")
check_eq(error_of(() => srv_side.send_binary(5)), "TypeError", "send_binary : type invalide")
check_eq(error_of(() => srv_side.ping(s.repeat("p", 126))), "ArgumentError", "ping : 125 octets au plus")
check_eq([n.utf8_valid("é✓日本語😀"), n.utf8_valid(n.from_bytes([255])), n.utf8_valid(n.from_bytes([192, 128])), n.utf8_valid(n.from_bytes([237, 160, 128])), n.utf8_valid(n.from_bytes([226, 130])), n.utf8_valid("")], [true, false, false, false, false, true], "utf8_valid (surlongue, substitut, tronqué)")
check_eq(error_of(() => ws.connect("ws://127.0.0.1:1/", null, null, 1.0)), "NetworkError", "connexion refusée")
check_eq(error_of(() => ws.connect("ws://127.0.0.1:1/", {"Upgrade": "x"}, null, 1.0)), "NetworkError", "en-tête réservé : vérifié après la connexion")

# ---------------------------------------------------------------- certificat pour wss
tmp := os.tmp_dir() + "/alex_ws_test_" + str(os.pid())
cert := tmp + "/cert.pem"
key_file := tmp + "/key.pem"
tls_ok := tls.supported() and have("openssl")
if tls_ok:
    fs.remove_tree(tmp, true)
    os.mkdir_all(tmp)
    gen := proc.run("openssl", ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key_file, "-out", cert, "-days", "2", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1"], null, 60.0)
    check_eq(gen.code, 0, "openssl : certificat de test")

# ---------------------------------------------------------------- 2. client Alex contre Python
if have("python3"):
    py := spawn_py("ws_test_server.py", [])
    port := to_int(s.trim(py.read_line("stdout", 10.0)))
    base := "ws://127.0.0.1:" + str(port)

    c := ws.connect(base + "/echo")
    c.send_text("héllo ✓ 日本語")
    m := c.receive(5.0)
    check_eq([m.kind, m.text()], ["text", "héllo ✓ 日本語"], "écho texte UTF-8")
    c.send_binary([0, 1, 2, 255, 128])
    m = c.receive(5.0)
    check_eq([m.kind, m.bytes()], ["binary", [0, 1, 2, 255, 128]], "écho binaire")
    c.send_text("fragmenté é ✓ en morceaux", 5)
    check_eq(c.receive(5.0).text(), "fragmenté é ✓ en morceaux", "message envoyé en fragments, renvoyé entier")
    c.ping("salut")
    c.send_text("après le ping")
    check_eq(c.receive(5.0).text(), "après le ping", "le pong est absorbé, le message suivant arrive")
    c.send_text("")
    check_eq(c.receive(5.0).text(), "", "message vide")
    data := s.repeat("0123456789", 7000)
    c.send_binary(data)
    back := c.receive(10.0)
    check_eq([back.size(), back.data == data], [70000, true], "70 000 octets aller-retour (longueur 64 bits, masquage)")
    check_eq(error_of(() => c.receive(0.3)), "TimeoutError", "receive : délai d'inactivité")
    c.send_text("toujours là")
    check_eq(c.receive(5.0).text(), "toujours là", "connexion utilisable après un délai")
    c.close(1000, "terminé")
    check_eq([c.is_closed(), c.close_code], [true, 1000], "close : le serveur renvoie le même code")
    check_eq(error_of(() => c.send_text("x")), "WebSocketError", "envoi après fermeture")
    check_eq(c.receive(1.0), null, "receive après fermeture : null")

    c = ws.connect(base + "/fragment")
    c.send_text("go")
    check_eq(c.receive(5.0).text(), "héllo wörld", "réassemblage de 3 fragments avec un ping entre eux")
    check_eq(c.receive(5.0).text(), "pong:mid", "le ping intercalé a reçu son pong")
    c.close()

    c = ws.connect(base + "/big")
    c.send_text("go")
    b1 := c.receive(10.0)
    ok := b1.size() == 70000
    bytes1 := b1.bytes()
    check_eq([ok, bytes1[0], bytes1[251], bytes1[69999]], [true, 0, 0, 69999 % 251], "trame serveur de 70 000 octets (longueur 64 bits)")
    check_eq(c.receive(5.0).size(), 200, "message binaire de 200 octets")
    e := c.receive(5.0)
    check_eq([e.kind, e.size()], ["text", 0], "message texte vide reçu")
    c.close()

    c = ws.connect(base + "/ping")
    check_eq(c.receive(5.0).text(), "pong-ok:abc", "ping du serveur : pong automatique avec les mêmes données")
    check_eq(c.pings, 1, "compteur de pings")
    c.close()

    c = ws.connect(base + "/close")
    check_eq(c.receive(5.0), null, "fermeture initiée par le serveur : receive renvoie null")
    check_eq([c.close_code, c.close_reason, c.is_closed()], [1001, "partir", true], "code et motif de fermeture reçus")

    c = ws.connect(base + "/abrupt")
    check_eq(c.receive(5.0), null, "connexion coupée sans trame close : null")
    check_eq(c.close_code, 1006, "code 1006 (fermeture anormale)")

    c = ws.connect(base + "/badmask")
    check_eq(error_of(() => c.receive(5.0)), "WebSocketError", "trame masquée venant du serveur refusée")
    check_eq(c.is_closed(), true, "connexion fermée après l'erreur de protocole")
    c = ws.connect(base + "/badutf8")
    check_eq(error_of(() => c.receive(5.0)), "WebSocketError", "texte non UTF-8 refusé")
    check(s.contains(last_message[0], "UTF-8"), "message : UTF-8")

    check_eq(error_of(() => ws.connect(base + "/reject")), "WebSocketError", "poignée de main refusée (403)")
    check(s.contains(last_message[0], "403"), "message : statut 403")
    check_eq(error_of(() => ws.connect(base + "/badaccept")), "WebSocketError", "Sec-WebSocket-Accept faux refusé")
    check(s.contains(last_message[0], "Accept"), "message : Accept")
    check_eq(error_of(() => ws.connect(base + "/unoffered", null, ["chat"])), "WebSocketError", "sous-protocole non proposé refusé")

    c = ws.connect(base + "/protocol", null, ["autre", "chat"])
    check_eq([c.subprotocol, c.receive(5.0).text()], ["chat", "chat"], "sous-protocole négocié")
    c.close()

    c = ws.connect(base + "/headers", {"X-Jeton": "abc"}, null, 10.0, 1000, "http://exemple.org")
    h := c.receive(5.0).text()
    check(s.contains(h, "\"x-jeton\": \"abc\""), "en-tête personnalisé envoyé")
    check(s.contains(h, "\"origin\": \"http://exemple.org\""), "Origin envoyé")
    check(s.contains(h, "\"sec-websocket-version\": \"13\""), "version 13 annoncée")
    check(s.contains(h, "127.0.0.1:" + str(port)), "Host avec le port")
    c.close()
    check_eq(error_of(() => ws.connect(base + "/echo", {"Sec-WebSocket-Key": "x"})), "ArgumentError", "en-tête Sec-WebSocket-* réservé")
    c = ws.connect(base + "/echo", null, null, 10.0, 100)
    c.send_binary(s.repeat("x", 500))
    check_eq(error_of(() => c.receive(5.0)), "WebSocketError", "message au-delà de max_message refusé")
    check(s.contains(last_message[0], "max_message"), "message : max_message")

    ws.connect(base + "/shutdown")
    py.wait(10.0)
    py.close()

    if tls_ok:
        spy := spawn_py("ws_test_server.py", [cert, key_file])
        sport := to_int(s.trim(spy.read_line("stdout", 10.0)))
        sc := ws.connect("wss://127.0.0.1:" + str(sport) + "/echo", null, null, 10.0, 1048576, null, true, cert)
        sc.send_text("chiffré é")
        check_eq(sc.receive(5.0).text(), "chiffré é", "wss:// : écho")
        sc.send_binary(s.repeat("w", 70000))
        check_eq(sc.receive(10.0).size(), 70000, "wss:// : 70 000 octets")
        sc.close()
        check_eq(error_of(() => ws.connect("wss://127.0.0.1:" + str(sport) + "/echo")), "TlsError", "wss:// : certificat inconnu refusé")
        ws.connect("wss://127.0.0.1:" + str(sport) + "/shutdown", null, null, 10.0, 1048576, null, false).close()
        spy.wait(10.0)
        spy.close()
else:
    print("test_websocket : python3 absent, client contre Python ignoré")

# ---------------------------------------------------------------- 3. serveur Alex contre client Python
if have("python3"):
    srv := ws.Server("127.0.0.1", 0, ["chat"], "/ws", null, 1000)
    sp := srv.port()
    check_eq(srv.url("/ws"), "ws://127.0.0.1:" + str(sp) + "/ws", "Server.url")
    func client(mode):
        return proc.Command("python3").args(["tests/network/ws_test_client.py", str(sp), mode]).stdout("pipe").stderr("null").spawn()

    cl := client("basic")
    sc := srv.accept(15.0)
    m1 := sc.receive(5.0)
    check_eq(m1.text(), "salut é", "serveur : message masqué du client Python")
    sc.send_text("écho:" + m1.text())
    check_eq(sc.receive(5.0).text(), "abcd", "serveur : message fragmenté du client réassemblé")
    sc.send_text("ok")
    check_eq(sc.receive(5.0), null, "serveur : fermeture reçue (ping traité entre-temps)")
    check_eq([sc.pings, sc.close_code, sc.close_reason, sc.is_closed()], [1, 1000, "fin", true], "serveur : ping, code et motif de fermeture")
    check_eq(s.trim(cl.read_all()), "écho:salut é|ok|op10:p1|close:1000", "client Python : réponses reçues")
    cl.wait(10.0)
    cl.close()

    for case in [["unmasked", "close:1002"], ["badutf8", "close:1007"], ["toobig", "close:1009"], ["badopcode", "close:1002"], ["badclosecode", "close:1002"]]:
        cl = client(case[0])
        sc = srv.accept(15.0)
        check_eq(error_of(() => sc.receive(5.0)), "WebSocketError", "serveur : " + case[0] + " lève WebSocketError")
        check_eq(s.trim(cl.read_all()), case[1], "serveur : " + case[0] + " -> code de fermeture envoyé")
        cl.wait(10.0)
        cl.close()
        sc.close()

    cl = client("proto")
    sc = srv.accept(15.0)
    check_eq(sc.subprotocol, "chat", "serveur : sous-protocole choisi")
    check_eq(s.trim(cl.read_all()), "chat", "client Python : sous-protocole reçu")
    cl.wait(10.0)
    cl.close()
    sc.close()

    before := srv.rejected
    cl = client("badhandshake")
    check_eq(error_of(() => srv.accept(15.0)), "WebSocketError", "serveur : requête sans Upgrade refusée")
    check_eq(s.trim(cl.read_all()), "HTTP/1.1 426 Upgrade Required", "client : réponse 426")
    cl.wait(10.0)
    cl.close()
    cl = client("badpath")
    check_eq(error_of(() => srv.accept(15.0)), "WebSocketError", "serveur : mauvais chemin refusé")
    check_eq(s.trim(cl.read_all()), "HTTP/1.1 404 Not Found", "client : réponse 404")
    cl.wait(10.0)
    cl.close()
    check_eq(srv.rejected - before, 2, "serveur : poignées de main refusées comptées")
    srv.close()
else:
    print("test_websocket : python3 absent, serveur contre client Python ignoré")

# ---------------------------------------------------------------- 4. Alex contre Alex
alex := "./alex"
if not os.exists(alex):
    alex = "alex"
func run_pair(secure):
    extra := []
    scheme := "ws"
    if secure:
        extra = [cert, key_file]
        scheme = "wss"
    argv := ["run", "tests/network/ws_alex_server.al"]
    for x in extra:
        append(argv, x)
    child := proc.Command(alex).args(argv).stdout("pipe").stderr("pipe").spawn()
    line := child.read_line("stdout", 20.0)
    if line == null:
        print("enfant WebSocket : " + str(child.read_all("stderr")))
    url := scheme + "://127.0.0.1:" + s.trim(line) + "/chat"
    label := scheme + " Alex ↔ Alex : "
    c := ws.connect(url, null, ["chat"], 10.0, 1048576, null, true, cert)
    check_eq(c.subprotocol, "chat", label + "sous-protocole")
    c.send_text("bonjour é")
    check_eq(c.receive(10.0).text(), "echo:bonjour é", label + "écho texte")
    c.send_binary([9, 8, 7, 0, 255])
    check_eq(c.receive(10.0).bytes(), [9, 8, 7, 0, 255], label + "écho binaire")
    c.send_text("frag")
    check_eq(c.receive(10.0).text(), "fragmenté é ✓", label + "texte fragmenté par le serveur")
    c.send_text("big")
    check_eq(c.receive(10.0).size(), 70000, label + "70 000 octets du serveur")
    c.send_binary(s.repeat("q", 200000))
    check_eq(c.receive(15.0).size(), 200000, label + "200 000 octets aller-retour")
    c.send_text("close")
    check_eq(c.receive(10.0), null, label + "fermeture lancée par le serveur")
    check_eq([c.close_code, c.close_reason], [4001, "demandé"], label + "code et motif 4001")
    c2 := ws.connect(url, null, null, 10.0, 1048576, null, true, cert)
    c2.send_text("stop")
    c2.close()
    check_eq(error_of(() => ws.connect(s.replace(url, "/chat", "/autre"), null, null, 5.0, 1048576, null, true, cert)), "NetworkError", label + "serveur arrêté")
    child.wait(15.0)
    child.close()

run_pair(false)
if tls_ok:
    run_pair(true)
    check_eq(tls.open_count(), 0, "toutes les sessions TLS sont fermées")
    fs.remove_tree(tmp, true)

print(f"websocket : {stats[0]} vérifications OK, {stats[1]} échec(s)")
for note in notes:
    print("  ÉCHEC " + note)
if stats[1] > 0:
    raise("TestError", "test_websocket : échecs")

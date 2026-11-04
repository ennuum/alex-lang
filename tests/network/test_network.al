# Test des modules network.socket, network.dns, network.tcp et network.udp (boucle locale uniquement).
# Client et serveur dans le même processus : le système accepte la connexion dans la file d'attente avant
# accept(), les envois tiennent dans les tampons ; tout se déroule donc en séquence.

from core use len, type
from collections use append
use string as s
use network.socket as sk
use network.dns as dns
use network.tcp as tcp
use network.udp as udp

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

# Type de l'erreur levée par f(), "aucune erreur" sinon ; message dans last_message.
last_message := [""]
func error_of(f):
    try:
        f()
    catch e:
        last_message[0] = e.message
        return e.type
    return "aucune erreur"

base_sockets := sk.open_count()

# ---------------------------------------------------------------- dns
check(dns.is_ipv4("127.0.0.1"), "is_ipv4 127.0.0.1")
check(dns.is_ipv4("255.255.255.255"), "is_ipv4 255.255.255.255")
check(not dns.is_ipv4("256.0.0.1"), "is_ipv4 256")
check(not dns.is_ipv4("1.2.3"), "is_ipv4 3 parties")
check(not dns.is_ipv4("01.2.3.4"), "is_ipv4 zéro initial")
check(not dns.is_ipv4("a.b.c.d"), "is_ipv4 lettres")
check(dns.is_ipv6("::1"), "is_ipv6 ::1")
check(dns.is_ipv6("::"), "is_ipv6 ::")
check(dns.is_ipv6("fe80::1:2"), "is_ipv6 fe80::1:2")
check(dns.is_ipv6("2001:db8:0:0:0:0:2:1"), "is_ipv6 complète")
check(dns.is_ipv6("::ffff:192.0.2.1"), "is_ipv6 fin IPv4")
check(not dns.is_ipv6("1::2::3"), "is_ipv6 deux ::")
check(not dns.is_ipv6("12345::"), "is_ipv6 groupe trop long")
check(not dns.is_ipv6("1:2:3:4:5:6:7"), "is_ipv6 7 groupes")
check(not dns.is_ipv6("g::1"), "is_ipv6 g")
check(s.contains(s.join(",", dns.resolve("localhost")), "127.0.0.1") or s.contains(s.join(",", dns.resolve("localhost")), "::1"), "resolve localhost")
check_eq(dns.resolve("127.0.0.1"), ["127.0.0.1"], "resolve d'une adresse numérique")
check_eq(dns.resolve_one("127.0.0.1", 4), "127.0.0.1", "resolve_one")
la := dns.lookup("127.0.0.1", 80)
check_eq(len(la), 1, "lookup : une adresse")
check_eq(la[0].family, 4, "lookup : famille")
check_eq(la[0].str(), "127.0.0.1:80", "Address.str")
check_eq(sk.format_address("::1", 8080), "[::1]:8080", "format_address IPv6")
check_eq(error_of(() => dns.resolve("nexistepas.invalid")), "DnsError", "nom introuvable -> DnsError")
check_eq(error_of(() => dns.resolve("")), "ArgumentError", "nom vide")
check_eq(error_of(() => dns.resolve(42)), "TypeError", "nom non str")
check_eq(error_of(() => dns.reverse("localhost")), "ArgumentError", "reverse d'un nom")
rv := dns.reverse("127.0.0.1")
check(rv == null or type(rv) == "str", "reverse 127.0.0.1")

# ---------------------------------------------------------------- tcp : échanges
srv := tcp.listen("127.0.0.1", 0)
port := srv.port()
check(port > 0, "port attribué")
check_eq(srv.address()[0], "127.0.0.1", "adresse d'écoute")
c := tcp.connect("127.0.0.1", port, 2.0)
a := srv.accept(2.0)
check_eq(c.peer_address()[1], port, "peer_address du client")
check_eq(a.local_address()[1], port, "local_address côté serveur")
check_eq(a.peer_address()[1], c.local_address()[1], "ports appariés")

c.write("première ligne\r\nseconde")
c.write(" ligne\nsans fin")
check_eq(a.read_line(2.0), "première ligne", "read_line (\\r\\n)")
check_eq(a.read_line(2.0), "seconde ligne", "read_line sur deux envois")
c.write(";champ2;")
check_eq(a.read_until(";", 2.0), "sans fin", "read_until")
check_eq(a.read_until(";", 2.0), "champ2", "read_until suivant")
c.write("0123456789")
check_eq(a.read_exact(4, 2.0), "0123", "read_exact")
check_eq(a.read(3, 2.0), "456", "read(max)")
check_eq(a.read(100, 2.0), "789", "read le reste")

# UTF-8 : un caractère coupé entre deux envois n'est jamais rendu à moitié.
c.write_bytes([195])
c.write_bytes([169, 116, 195, 169])
check_eq(a.read(100, 2.0), "été", "read : caractère coupé en deux envois")
c.write("€uro")
check_eq(a.read_exact(3, 2.0), "€", "read_exact d'un caractère de 3 octets")
check_eq(a.read(100, 2.0), "uro", "suite")

# Binaire : octets 0..255 sans transformation.
c.write_bytes([0, 255, 10, 13, 128])
check_eq(a.read_exact_bytes(5, 2.0), [0, 255, 10, 13, 128], "octets bruts")

# Réponse du serveur, puis fin d'envoi : read_all et fin du flux.
a.write_line("réponse")
check_eq(c.read_line(2.0), "réponse", "write_line / read_line")
a.write("fin du flux")
a.close_write()
check_eq(c.read_all(2.0), "fin du flux", "read_all jusqu'à la fermeture")
check_eq(c.read_line(2.0), null, "read_line après la fin : null")
check_eq(c.read(10, 2.0), "", "read après la fin : vide")
check_eq(error_of(() => c.read_exact(1, 2.0)), "NetworkError", "read_exact après la fin")

# Délais.
check_eq(error_of(() => srv.accept(0.2)), "TimeoutError", "accept : délai dépassé")
check_eq(error_of(() => a.read_line(0.2)), "TimeoutError", "read_line : délai dépassé")
check_eq(error_of(() => srv.accept(0)), "TimeoutError", "accept sans attente")
check(s.contains(last_message[0], "EAGAIN"), "message EAGAIN")
c.close()
a.close()
check(c.is_closed(), "is_closed")
check_eq(error_of(() => c.write("x")), "ArgumentError", "écriture sur un socket fermé")
c.close() # idempotent

# Connexion refusée.
check_eq(error_of(() => tcp.connect("127.0.0.1", 1, 2.0)), "NetworkError", "connexion refusée")
check(s.contains(last_message[0], "ECONNREFUSED"), "message ECONNREFUSED")
check_eq(error_of(() => tcp.connect("nexistepas.invalid", 80, 1.0)), "DnsError", "connect : nom introuvable")

# wait : le serveur est prêt à accepter quand un client attend.
c2 := tcp.connect("localhost", port, 2.0)
ready := sk.wait([srv.socket], "read", 2.0)
check_eq(len(ready), 1, "wait : connexion en attente")
a2 := srv.accept(1.0)
check_eq(len(sk.wait([a2.socket], "read", 0.1)), 0, "wait : rien à lire")
c2.write("x")
check_eq(len(sk.wait([a2.socket], "read", 2.0)), 1, "wait : données prêtes")
check_eq(a2.socket.try_recv(), "x", "try_recv")
check_eq(a2.socket.try_recv(), null, "try_recv sans données")
c2.close()
a2.close()

# serve : le client se connecte et écrit avant que le serveur n'accepte.
log := []
func echo_handler(conn):
    line := conn.read_line(2.0)
    append(log, line)
    conn.write_line("écho : " + line)
c3 := tcp.connect("127.0.0.1", port, 2.0)
c3.write_line("salut")
check_eq(tcp.serve(srv, echo_handler, 1), 1, "serve : une connexion")
check_eq(c3.read_line(2.0), "écho : salut", "serve : réponse")
check_eq(log, ["salut"], "serve : gestionnaire appelé")
c3.close()
func failing_handler(conn):
    raise("ValueError", "requête invalide")
c4 := tcp.connect("127.0.0.1", port, 2.0)
check_eq(error_of(() => tcp.serve(srv, failing_handler, 1)), "ValueError", "serve : erreur du gestionnaire")
c4.close()
errors := []
func note_error(e, conn):
    append(errors, e.message)
c5 := tcp.connect("127.0.0.1", port, 2.0)
check_eq(tcp.serve(srv, failing_handler, 1, note_error), 1, "serve : on_error")
check_eq(errors, ["requête invalide"], "serve : erreur transmise")
c5.close()
srv.close()

# Adresse occupée (sans reuse_address la seconde écoute échoue).
l1 := tcp.listen("127.0.0.1", 0)
check_eq(error_of(() => tcp.listen("127.0.0.1", l1.port(), 8, false)), "NetworkError", "port déjà utilisé")
check(s.contains(last_message[0], "EADDRINUSE"), "message EADDRINUSE")
l1.close()

# IPv6 (si la boucle locale ::1 existe sur la machine).
v6 := null
try:
    v6 = tcp.listen("::1", 0)
catch e:
    v6 = null
if v6 != null:
    c6 := tcp.connect("::1", v6.port(), 2.0)
    a6 := v6.accept(2.0)
    c6.write_line("v6")
    check_eq(a6.read_line(2.0), "v6", "IPv6 : échange")
    check_eq(a6.peer_address()[0], "::1", "IPv6 : adresse du client")
    c6.close()
    a6.close()
    v6.close()
else:
    check(true, "IPv6 indisponible : ignoré")
    check(true, "IPv6 indisponible : ignoré")

# ---------------------------------------------------------------- udp
rx := udp.bind("127.0.0.1", 0)
check_eq(rx.try_receive(), null, "try_receive sans datagramme")
check_eq(udp.send("bonjour", "127.0.0.1", rx.port()), 7, "send : octets")
d := rx.receive(2.0)
check_eq(d.text(), "bonjour", "datagramme reçu")
check_eq(d.host, "127.0.0.1", "expéditeur")
tx := udp.open()
tx.send_to([1, 2, 3, 0, 255], "localhost", rx.port())
d2 := rx.receive(2.0)
check_eq(d2.bytes(), [1, 2, 3, 0, 255], "datagramme binaire")
check_eq(d2.size(), 5, "taille")
check(d2.port > 0, "port de l'expéditeur")
rx.send_to("réponse", d2.host, d2.port)
check_eq(tx.receive(2.0).text(), "réponse", "réponse à l'expéditeur")
check_eq(error_of(() => rx.receive(0.2)), "TimeoutError", "receive : délai dépassé")
tx.set_broadcast(true)
check(true, "set_broadcast")
tx.close()
rx.close()

# ---------------------------------------------------------------- erreurs d'usage
check_eq(error_of(() => sk.Socket(5, "tcp")), "ArgumentError", "famille invalide")
check_eq(error_of(() => sk.Socket(4, "sctp")), "ArgumentError", "type invalide")
check_eq(error_of(() => tcp.listen("127.0.0.1", 70000)), "ArgumentError", "port hors limites")
check_eq(error_of(() => tcp.connect("127.0.0.1", 80, -1)), "ArgumentError", "délai négatif")
t := sk.Socket(4, "tcp")
check_eq(error_of(() => t.send(123)), "TypeError", "send d'un int")
check_eq(error_of(() => t.set_option("inconnue", true)), "ArgumentError", "option inconnue")
t.close()

check_eq(sk.open_count(), base_sockets, "aucun socket laissé ouvert")

print(f"network : {stats[0]} vérifications OK, {stats[1]} échec(s)")
for n in notes:
    print("  ÉCHEC " + n)
if stats[1] > 0:
    raise("TestError", "test_network : échecs")

# Test des modules réseau « système » : core (fonctionnalités, STARTTLS), network_interface, routing,
# multicast, network_monitor, connection_pool, proxy (SOCKS5 contre un mandataire Python, CONNECT), async_client,
# webbrowser (sans lancer de navigateur), firewall sur un écouteur réel.

from core use len, type
from collections use append, keys
use string as s
use process as proc
use time
use asyncio
use network.core as net
use network.tcp as tcp
use network.tls as tls
use network.network_interface as ni
use network.routing as routing
use network.multicast as mc
use network.network_monitor as nm
use network.connection_pool as cp
use network.proxy as px
use network.async_client as ac
use network.webbrowser as wb
use network.firewall as fwm
use network.certificates as certs
use concurrency.thread as thread

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

# Serveur de ligne « STARTTLS » (dans un fil) : répond en clair, puis passe en TLS et fait écho.
func starttls_server(cert, key):
    l := tcp.listen("127.0.0.1", 0)
    thread.send(l.port())
    c := l.accept(10.0)
    c.write("220 prêt\r\n")
    if c.read_line(5.0) == "STARTTLS":
        c.write("220 go\r\n")
        c = net.accept_tls(c, cert, key)
        c.write("chiffré : " + c.read_line(5.0) + "\n")
    c.close()
    l.close()
    return true

async func echo(conn):
    line := await conn.read_line(5.0)
    await conn.write(s.upper(line) + "\n")

async func async_part():
    srv2 := ac.AsyncServer("127.0.0.1", 0, echo)
    serving := srv2.serve(3)
    clients := []
    for i in 0..3:
        clients.append(client_task(srv2.port(), "client" + str(i)))
    res := await ac.gather(clients)
    await serving
    srv2.close()
    return res

async func client_task(port, name):
    c2 := await ac.connect("127.0.0.1", port, 2.0)
    await c2.write(name + "\n")
    r := await c2.read_line(5.0)
    c2.close()
    return r

if thread.is_main():
    f := net.features()
    check(f["tcp"] and f["udp"], "core : fonctionnalités")
    e := net.endpoint("tls://exemple.org:8443")
    check_eq([e.host, e.port, e.secure, e.key()], ["exemple.org", 8443, true, "tls://exemple.org:8443"], "core : endpoint")

    # interfaces et routage du système
    itfs := ni.interfaces()
    check(len(itfs) >= 1, "interfaces : au moins une")
    lo := ni.loopback()
    check(lo != null and lo.is_up() and len(lo.ipv4()) >= 1 and lo.ipv4()[0].address == "127.0.0.1", "interfaces : boucle locale")
    check(ni.interface_for("127.0.0.1").is_loopback(), "interfaces : interface_for")
    check(ni.counters()["lo"]["rx_bytes"] >= 0, "interfaces : compteurs")
    rs := routing.routes(4)
    if len(rs) > 0:
        dr := routing.default_route(4)
        if dr != null:
            check(routing.lookup("203.0.113.9") != null and dr.is_default(), "routage : route par défaut")
        check_eq(routing.lookup(ni.addresses(4)[0]).is_default(), false, "routage : réseau local direct")

    # multicast (boucle locale, interface de la machine)
    addrs := ni.addresses(4)
    itf := ""
    if len(addrs) > 0:
        itf = addrs[0]
    try:
        r1 := mc.MulticastSocket("239.255.42.42", 0, itf)
        port := r1.local_port()
        r2 := mc.MulticastSocket("239.255.42.42", port, itf)
        snd := mc.sender("239.255.42.42", port, 1, itf)
        snd.send("à tous")
        check_eq([r1.receive(2.0).text(), r2.receive(2.0).text()], ["à tous", "à tous"], "multicast : deux abonnés reçoivent")
        r1.close()
        r2.close()
        snd.close()
    catch err:
        print("test_network_system : multicast indisponible ici (" + err.message + ")")
    check_eq(error_of(() => mc.MulticastSocket("10.0.0.1", 5000)), "ArgumentError", "multicast : groupe invalide")

    # surveillance
    srv := tcp.listen("127.0.0.1", 0)
    p := srv.port()
    check(nm.tcp_ping("127.0.0.1", p) != null, "monitor : tcp_ping")
    check_eq(nm.tcp_ping("127.0.0.1", 1, 0.5), null, "monitor : port fermé")
    st := nm.probe("127.0.0.1", p, 3, 0.01)
    check_eq([st.received, st.loss], [3, 0.0], "monitor : sondes")
    check(nm.is_listening(p), "monitor : port en écoute (/proc/net/tcp)")
    mon := nm.Monitor()
    mon.add_tcp("local", "127.0.0.1", p, 0)
    changes := []
    mon.on_change((t, a, b) => changes.append(t.name + ":" + b))
    mon.check_all()
    srv.close()
    mon.check_all()
    check_eq(changes, ["local:up", "local:down"], "monitor : changements d'état")

    # réserve de connexions
    l2 := tcp.listen("127.0.0.1", 0)
    pool := cp.ConnectionPool(2)
    fac := () => tcp.connect("127.0.0.1", l2.port(), 2.0)
    a := pool.acquire("k", fac)
    l2.accept(1.0)
    pool.release("k", a)
    check(pool.acquire("k", fac) == a, "pool : réutilisation")
    pool.acquire("k", fac)
    check_eq(error_of(() => pool.acquire("k", fac)), "PoolError", "pool : limite")
    pool.close_all()
    l2.close()

    # pare-feu sur un écouteur réel
    fw := fwm.Firewall("allow")
    fw.add("deny in tcp from 127.0.0.1")
    g := fw.guard(tcp.listen("127.0.0.1", 0))
    cc := tcp.connect("127.0.0.1", g.port(), 1.0)
    check_eq(error_of(() => g.accept(0.5)), "TimeoutError", "pare-feu : connexion refusée en silence")
    check_eq(g.dropped, 1, "pare-feu : compte des refus")
    cc.close()
    g.close()

    # mandataire SOCKS5 (Python ; CONNECT est vérifié par test_http_client)
    target := tcp.listen("127.0.0.1", 0)
    if proc.which("python3") != null:
        sp := proc.Command("python3").args(["tests/network/socks5_server.py", "3", "alice:secret"]).stdout("pipe").stderr("pipe").spawn()
        sport := s.trim(sp.read_line("stdout", 10.0))
        conn := px.connect("socks5h://alice:secret@127.0.0.1:" + sport, "localhost", target.port(), 5.0)
        peer := target.accept(2.0)
        conn.write("par SOCKS5\n")
        check_eq(peer.read_line(2.0), "par SOCKS5", "proxy : SOCKS5 avec mot de passe (nom résolu par le mandataire)")
        peer.write("retour\n")
        check_eq(conn.read_line(2.0), "retour", "proxy : SOCKS5 dans l'autre sens")
        conn.close()
        peer.close()
        check_eq(error_of(() => px.connect("socks5h://alice:faux@127.0.0.1:" + sport, "localhost", target.port(), 5.0)), "ProxyError", "proxy : SOCKS5 mauvais mot de passe")
        check_eq(error_of(() => px.connect("socks5://alice:secret@127.0.0.1:" + sport, "127.0.0.1", 1, 5.0)), "ProxyError", "proxy : SOCKS5 destination refusée")
        sp.wait(10.0)
        check(s.contains(sp.read_all("stderr"), "domaine localhost"), "proxy : socks5h transmet le nom")
        sp.close()
    target.close()
    check_eq(px.proxy_for("http://127.0.0.1:8080/"), null, "proxy : jamais pour la boucle locale")

    # STARTTLS (core.start_tls / accept_tls)
    if proc.which("openssl") != null and tls.supported():
        cert := "/tmp/alex_sys_cert.pem"
        key := "/tmp/alex_sys_key.pem"
        certs.generate_self_signed(cert, key, "localhost", ["localhost", "127.0.0.1"], 2)
        th := thread.spawn(starttls_server, [cert, key])
        sport2 := th.receive(10.0)
        c := tcp.connect("127.0.0.1", sport2, 5.0)
        check_eq(c.read_line(5.0), "220 prêt", "STARTTLS : bannière en clair")
        c.write("STARTTLS\r\n")
        c.read_line(5.0)
        c = net.start_tls(c, "localhost", true, cert)
        check(net.is_secure(c), "STARTTLS : connexion chiffrée")
        c.write("secret\n")
        check_eq(c.read_line(5.0), "chiffré : secret", "STARTTLS : échange chiffré")
        c.close()
        th.join(10.0)

    # async : serveur et clients concurrents
    check_eq(await async_part(), ["CLIENT0", "CLIENT1", "CLIENT2"], "async : trois clients concurrents")

    # navigateur : commande calculée sans lancement
    wb.register("faux", ["echo", "--url=%s"], true)
    check_eq(wb.command_for("https://exemple.org/x?a=1"), ["echo", "--url=https://exemple.org/x?a=1"], "webbrowser : commande")
    check_eq(error_of(() => wb.open("javascript:alert(1)")), "ValueError", "webbrowser : schéma refusé")
    check(s.starts_with(wb.file_url("/tmp/a b.html"), "file:///tmp/a%20b.html"), "webbrowser : file_url")

    print(f"network (système) : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_network_system : échecs")

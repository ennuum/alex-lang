# Tests : TLS 1.3 en ALEX pur — crypto.der / crypto.x509 (clés, certificats, chaînes), network.tls13 (ordonnancement
# des clés contre la RFC 8448, poignées de main client et serveur en boucle locale : suites, groupes,
# HelloRetryRequest, ALPN, certificats EC / RSA / chaîne, gros transferts, KeyUpdate, refus), crypto.accel.
# Données : data/tls/ (certificats valables jusqu'en 2126, produits par OpenSSL).
#   alexc run tests/stdlib2/test_tls13.al          (ALEX_CRYPTO_ACCEL=0 : tout le calcul en Alex)
from core use len, to_int
from collections use append
use check as t
use io
use os
use string as s
use crypto
use crypto.accel as ax
use crypto.x509 as x509
use crypto.hkdf as hkdf
use crypto.x25519 as x25519
use network.tcp as tcp
use network.tls13 as tls13
use concurrency.thread as thread
use thread.offload as offload
use asyncio as aio
use time

const D := "tests/stdlib2/data/tls/"

func hx(t):
    return crypto.hex_decode(s.replace(t, " ", ""))

func eh(b):
    return crypto.hex_encode(b)

func pem(n):
    return io.read_raw(D + n)

# ---------------------------------------------------------------- RFC 8448, 3 (1-RTT simple)

CH := hx("01 00 00 c0 03 03 cb 34 ec b1 e7 81 63 ba 1c 38 c6 da cb 19 6a 6d ff a2 1a 8d 99 12 ec 18 a2 ef 62 83 02 4d ec e7 00 00" +
         "06 13 01 13 03 13 02 01 00 00 91 00 00 00 0b 00 09 00 00 06 73 65 72 76 65 72 ff 01 00 01 00 00 0a 00 14 00 12 00 1d 00" +
         "17 00 18 00 19 01 00 01 01 01 02 01 03 01 04 00 23 00 00 00 33 00 26 00 24 00 1d 00 20 99 38 1d e5 60 e4 bd 43 d2 3d 8e" +
         "43 5a 7d ba fe b3 c0 6e 51 c1 3c ae 4d 54 13 69 1e 52 9a af 2c 00 2b 00 03 02 03 04 00 0d 00 20 00 1e 04 03 05 03 06 03" +
         "02 03 08 04 08 05 08 06 04 01 05 01 06 01 02 01 04 02 05 02 06 02 02 02 00 2d 00 02 01 01 00 1c 00 02 40 01")
SH := hx("02 00 00 56 03 03 a6 af 06 a4 12 18 60 dc 5e 6e 60 24 9c d3 4c 95 93 0c 8a c5 cb 14 34 da c1 55 77 2e d3 e2 69 28 00 13" +
         "01 00 00 2e 00 33 00 24 00 1d 00 20 c9 82 88 76 11 20 95 fe 66 76 2b db f7 c6 72 e1 56 d6 cc 25 3b 83 3d f1 dd 69 b1 b0" +
         "4e 75 1f 0f 00 2b 00 02 03 04")
t.eq(len(CH), 196, "RFC 8448 ClientHello")
hello := tls13._parse_client_hello(CH[4:len(CH)])
t.eq(hello.server_name, "server", "SNI lu")
t.eq(hello.suites, [4865, 4867, 4866], "suites du client")
t.eq(tls13._choose_suite(hello), 4865, "suite : préférence du serveur")
t.eq(hello.shares[0][0], 29, "part x25519")
t.eq(eh(hello.shares[0][1]), "99381de560e4bd43d23d8e435a7dbafeb3c06e51c13cae4d5413691e529aaf2c", "part du client")
t.eq(tls13._choose_group(hello)[0], 29, "groupe choisi")
t.check(772 in hello.versions, "TLS 1.3 proposé")
ikm := x25519.shared(hx("b1580eeadf6dd589b8ef4f2d5652578cc810e9980191ec8d058308cea216a21e"), hello.shares[0][1])
t.eq(eh(ikm), "8bd4054fb55b9d63fdfbacf9f04b9f0d35e6d63f537563efd46272900f89492d", "secret ECDHE (serveur)")
t.eq(eh(x25519.shared(hx("49af42ba7f7994852d713ef2784bcbcaa7911de26adc5642cb634540e7ea5005"), hx("c9828876112095fe66762bdbf7c672e156d6cc253b833df1dd69b1b04e751f0f"))), eh(ikm), "secret ECDHE (client)")
z := [0] * 32
early := hkdf.extract("sha256", z, z)
t.eq(eh(early), "33ad0a1c607ec03b09e6cd9893680ce210adf300aa1f2660e1b22e10f170f92a", "secret early")
derived := tls13.derive_secret("sha256", early, "derived", crypto.sha256_bytes([]))
t.eq(eh(derived), "6f2615a108c702c5678f54fc9dbab69716c076189c48250cebeac3576c3611ba", "derived")
hs := hkdf.extract("sha256", derived, ikm)
t.eq(eh(hs), "1dc826e93606aa6fdc0aadc12f741b01046aa6b99f691ed221a9f0ca043fbeac", "secret de poignée de main")
th := crypto.sha256_bytes(CH + SH)
c_hs := tls13.derive_secret("sha256", hs, "c hs traffic", th)
s_hs := tls13.derive_secret("sha256", hs, "s hs traffic", th)
t.eq(eh(c_hs), "b3eddb126e067f35a780b3abf45e2d8f3b1a950738f52e9600746a0e27a55a21", "c hs traffic")
t.eq(eh(s_hs), "b67b7d690cc16c4e75e54213cb2d37b4e9c912bcded9105d42befd59d391ad38", "s hs traffic")
t.eq(eh(tls13.expand_label("sha256", s_hs, "key", [], 16)), "3fce516009c21727d0f2e4e86ee403bc", "clé du serveur")
t.eq(eh(tls13.expand_label("sha256", s_hs, "iv", [], 12)), "5d313eb2671276ee13000b30", "iv du serveur")
t.eq(eh(tls13.expand_label("sha256", c_hs, "key", [], 16)), "dbfaa693d1762c5b666af5d950258d01", "clé du client")
t.eq(eh(tls13.expand_label("sha256", c_hs, "iv", [], 12)), "5bd3c71b836e0b76bb73265f", "iv du client")
t.raises(() => tls13._parse_client_hello(CH[4:100]), "TlsAlert", "ClientHello tronqué : decode_error")

# ---------------------------------------------------------------- clés et certificats

cp := x509.load_certificates(pem("p256.pem"))[0]
kp := x509.load_private_key(pem("p256.key"))
t.eq([cp.subject_cn, cp.dns_names, len(cp.ip_addresses), cp.key_kind, cp.curve, kp.kind, kp.curve], ["localhost", ["localhost"], 1, "ec", "P-256", "ec", "P-256"], "certificat et clé P-256")
t.eq(s.substring(cp.not_after, 0, 4), "2126", "date en GeneralizedTime")
t.check(x509.key_matches(cp, kp) and x509.key_matches(cp, x509.load_private_key(pem("p256_sec1.key"))), "PKCS#8 et SEC1")
cr := x509.load_certificates(pem("rsa.pem"))[0]
kr := x509.load_private_key(pem("rsa_pkcs1.key"))
t.check(kr.kind == "rsa" and kr.bits == 2048 and x509.key_matches(cr, kr), "RSA PKCS#1")
t.check(not x509.key_matches(cp, kr) and not x509.key_matches(cr, kp), "clés croisées refusées")
t.check(x509.key_matches(x509.load_certificates(pem("p384.pem"))[0], x509.load_private_key(pem("p384.key"))), "P-384")
t.raises(() => x509.load_private_key(pem("ed25519.key")), "ValueError", "Ed25519 refusée")
t.raises(() => x509.load_private_key(pem("p256_chiffree.key")), "ValueError", "clé chiffrée refusée")
t.raises(() => x509.load_certificates("rien"), "ValueError", "aucun certificat")
t.raises(() => x509.pem_blocks("-----BEGIN CERTIFICATE-----\nAAAA\n"), "ValueError", "PEM non terminé")
chain := x509.load_certificates(pem("chaine.pem"))
root := x509.load_trust(pem("root.pem"))
t.eq([len(chain), chain[1].is_ca, chain[0].signature_algorithm, chain[1].signature_algorithm], [2, true, ["ec", "sha256"], ["pkcs1", "sha384"]], "chaîne lue")
t.check(x509.verify_chain(chain, root, "www.exemple.test"), "chaîne vérifiée (racine RSA, intermédiaire P-384)")
t.check(x509.verify_chain(chain, root, "exemple.test"), "nom exact")
t.raises(() => x509.verify_chain(chain, root, "a.b.exemple.test"), "ValueError", "joker sur un seul niveau")
t.raises(() => x509.verify_chain([chain[0]], root, "www.exemple.test"), "ValueError", "intermédiaire manquant")
t.check(x509.verify_chain([chain[0]], [chain[1]], "www.exemple.test"), "intermédiaire pris pour ancre")
t.raises(() => x509.verify_chain(chain, root, "www.exemple.test", "2200-01-01T00:00:00Z"), "ValueError", "expiré")
t.raises(() => x509.verify_chain(chain, [cp], "www.exemple.test"), "ValueError", "mauvaise ancre")
t.check(x509.verify_chain([cp], [cp], "127.0.0.1"), "certificat épinglé, adresse IP")
pss := x509.load_certificates(pem("pss.pem"))[0]
t.check(pss.signature_algorithm[0] == "pss" and x509.signed_by(pss, pss), "signature RSA-PSS (sel lu dans les paramètres)")
t.eq([x509.utc_text(0), x509.utc_text(951782400), x509.utc_text(4102444799)], ["1970-01-01T00:00:00Z", "2000-02-29T00:00:00Z", "2099-12-31T23:59:59Z"], "dates UTC")
t.raises(() => tls13.ServerContext(D + "p256.pem", D + "rsa.key"), "ValueError", "clé différente du certificat")

# ---------------------------------------------------------------- poignées de main en boucle locale

# Client (dans un fil) : [infos] ou ["erreur", type, message].
func client(port, opts):
    try:
        c := tcp.connect("127.0.0.1", port, 10.0)
        ts := tls13.wrap_client(c.socket, opts["host"], opts["alpn"], 20.0, opts["verify"], opts["ca"])
        conn := tcp.Connection(ts)
        conn.write("bonjour\n")
        out := [ts.version, ts.cipher, ts.alpn, ts.group, conn.read_line(20.0)]
        if opts["big"] > 0:
            conn.write(s.repeat("a", opts["big"]) + "\n")
            got := conn.read_line(30.0, opts["big"] + 10)
            ts.key_update(true)
            conn.write("apres\n")
            append(out, s.byte_len(got))
            append(out, conn.read_line(20.0))
        conn.close()
        return out
    catch e:
        return ["erreur", e.type, e.message]

# Serveur (fil principal) pour une connexion ; rend [infos serveur] ou ["erreur", type, message].
func serveur(lst, ctx, big):
    sock := lst.socket.accept(20.0)[0]
    try:
        ts := tls13.wrap_server(sock, ctx, 20.0)
        conn := tcp.Connection(ts)
        l := conn.read_line(20.0)
        conn.write("re " + l + " sni=" + str(ts.server_name) + "\n")
        if big > 0:
            l2 := conn.read_line(30.0, big + 10)
            conn.write(s.repeat("b", s.byte_len(l2)) + "\n")
            conn.write("fin " + conn.read_line(20.0) + "\n")
        conn.close()
        return [ts.cipher, ts.group, ts.signature_scheme]
    catch e:
        try:
            sock.close()
        catch e2:
            ignored := e2
        return ["erreur", e.type, e.message]

func session(cert, key, opts, server_opts=null, alpn=null, big=0):
    lst := tcp.listen("127.0.0.1", 0)
    ctx := tls13.ServerContext(D + cert, D + key, alpn, server_opts)
    o := {"host": "localhost", "alpn": null, "verify": true, "ca": D + cert, "big": big}
    for k in opts:
        o[k] = opts[k]
    f := thread.spawn(client, [lst.port(), o])
    srv := serveur(lst, ctx, big)
    cli := f.join(60.0)
    lst.close()
    return [cli, srv]

r := session("p256.pem", "p256.key", {"alpn": ["h2", "http/1.1"]}, null, ["h2", "http/1.1"])
t.eq(r[0], ["TLSv1.3", "TLS_AES_128_GCM_SHA256", "h2", "x25519", "re bonjour sni=localhost"], "P-256 : client")
t.eq(r[1], ["TLS_AES_128_GCM_SHA256", "x25519", 1027], "P-256 : serveur (ecdsa_secp256r1_sha256)")
r = session("rsa.pem", "rsa.key", {"alpn": ["http/1.1"]}, {"suites": [4867]}, ["h2", "http/1.1"])
t.eq([r[0][1], r[0][2], r[1][2]], ["TLS_CHACHA20_POLY1305_SHA256", "http/1.1", 2052], "RSA-PSS, ChaCha20-Poly1305")
r = session("p384.pem", "p384.key", {}, {"suites": [4866], "groups": [24]})
t.eq([r[0][1], r[0][3], r[1][2]], ["TLS_AES_256_GCM_SHA384", "secp384r1", 1283], "P-384, AES-256 : HelloRetryRequest")
r = session("chaine.pem", "feuille.key", {"ca": D + "root.pem"}, {"groups": [23]})
t.eq([r[0][3], r[0][4]], ["secp256r1", "re bonjour sni=localhost"], "chaîne jusqu'à la racine, HelloRetryRequest vers P-256")
r = session("p256.pem", "p256.key", {}, null, null, 120000)
t.eq(r[0][5:7], [120000, "fin apres"], "120 Ko dans chaque sens puis KeyUpdate")
r = session("p256.pem", "p256.key", {"alpn": ["spdy/1"]}, null, ["h2"])
t.check(r[0][0] == "erreur" and s.contains(r[0][2], "no_application_protocol") and r[1][0] == "erreur", "ALPN sans protocole commun")
r = session("p256.pem", "p256.key", {"host": "example.org"})
t.check(r[0][0] == "erreur" and s.contains(r[0][2], "ne couvre pas") and s.contains(r[1][2], "unknown_ca"), "nom refusé par le client")
r = session("p256.pem", "p256.key", {"ca": D + "rsa.pem"})
t.check(r[0][0] == "erreur" and s.contains(r[0][2], "aucune autorité"), "autorité inconnue")
r = session("p256.pem", "p256.key", {"verify": false, "ca": null, "host": "nimporte"})
t.eq(r[0][4], "re bonjour sni=nimporte", "verify=false")

# client qui parle HTTP en clair au port TLS
func clair(port):
    c := tcp.connect("127.0.0.1", port, 10.0)
    c.write("GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    got := c.socket.recv(100, 10.0)
    c.close()
    return got
lst := tcp.listen("127.0.0.1", 0)
fil := thread.spawn(clair, [lst.port()])
res := serveur(lst, tls13.context(D + "p256.pem", D + "p256.key"), 0)
fil.join(20.0)
lst.close()
t.check(res[0] == "erreur" and s.contains(res[2], "ne parle pas TLS"), "requête en clair refusée")

# poignée de main serveur sans attente (server_step) : calcul sur un fil de thread.offload
class FilOffload:
    func init():
        self.soumis = 0

    func submit(fn, args):
        self.soumis += 1
        return offload.submit(fn, args)

    func done(h):
        offload.poll()
        return aio.done(h)

    func result(h):
        return aio.result(h)

func serveur_nb(lst, ctx):
    sock := lst.socket.accept(20.0)[0]
    ts := tls13.TlsSocket13(sock, ctx)
    ex := FilOffload()
    etats := []
    t0 := time.monotonic()
    while time.monotonic() - t0 < 20.0:
        r := ts.server_step(ex)
        if len(etats) == 0 or etats[len(etats) - 1] != r:
            append(etats, r)
        if r == "done":
            break
        time.sleep(0.001)
    conn := tcp.Connection(ts)
    l := conn.read_line(20.0)
    conn.write("re " + l + " sni=" + str(ts.server_name) + "\n")
    conn.close()
    return [etats, ex.soumis, ts.cipher]

for cert in [["p256.pem", "p256.key", {}], ["rsa.pem", "rsa.key", {"groups": [23]}]]:
    lst2 := tcp.listen("127.0.0.1", 0)
    ctx2 := tls13.ServerContext(D + cert[0], D + cert[1], ["http/1.1"], cert[2])
    f2 := thread.spawn(client, [lst2.port(), {"host": "localhost", "alpn": ["http/1.1"], "verify": true, "ca": D + cert[0], "big": 0}])
    sr := serveur_nb(lst2, ctx2)
    cr := f2.join(30.0)
    lst2.close()
    t.eq(cr[4], "re bonjour sni=localhost", "server_step " + cert[0] + " : échange")
    t.check(sr[1] == 1 and "busy" in sr[0] and sr[0][len(sr[0]) - 1] == "done", "server_step " + cert[0] + " : calcul sur un fil " + str(sr[0]))

t.check(ax.has("x25519") or os.getenv("ALEX_CRYPTO_ACCEL") == "0", "calcul du runtime disponible")
t.summary("test_tls13")

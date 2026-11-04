# Test de network.protobuf, grpc (HPACK, HTTP/2), grpc_client et grpc_server : vecteurs de la RFC 7541,
# encodage protobuf, client Alex contre un serveur gRPC en Go (net/http h2c), client Go contre le serveur Alex,
# Alex contre Alex (h2c et TLS avec ALPN h2). Les parties Go sont ignorées si `go` est absent.

from core use len, type
from collections use append
use string as s
use json
use os
use process as proc
use concurrency.thread as thread
use _native_net as _n
use network.protobuf as pb
use network.grpc as g
use network.grpc_client as gc
use network.grpc_server as gs
use network.encoding as enc
use network.certificates as certs

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

const PROTO := """
syntax = "proto3";
package demo;
message Req { string texte = 1; }
message Rep { string texte = 1; int32 taille = 2; }
service Echo {
  rpc Unary (Req) returns (Rep);
  rpc Stream (Req) returns (stream Rep);
  rpc Collect (stream Req) returns (Rep);
  rpc Bidi (stream Req) returns (stream Rep);
  rpc Fail (Req) returns (Rep);
  rpc Big (Req) returns (Rep);
  rpc Stop (Req) returns (Rep);
  rpc Slow (Req) returns (Rep);
}
"""

STOP := [null]

func unary(req, ctx):
    ctx.set_header_metadata({"x-vu": ctx.metadata["x-client"] if "x-client" in ctx.metadata else "?"})
    ctx.set_trailing_metadata({"x-fin": "oui", "x-bin": "\u{0}\u{1}"})
    return {"texte": "écho : " + req["texte"], "taille": len(req["texte"])}

func stream(req, ctx):
    for i in 1..3:
        ctx.send({"texte": "n=" + str(i), "taille": i})
    return [{"texte": "n=3", "taille": 3}]

func collect(reqs, ctx):
    parts := []
    for r in reqs:
        append(parts, r["texte"])
    return {"texte": s.join("+", parts), "taille": len(reqs)}

func bidi(reqs, ctx):
    out := []
    for r in reqs:
        append(out, {"texte": s.upper(r["texte"])})
    return out

func failing(req, ctx):
    ctx.abort(g.NOT_FOUND, "absent é")

func crash(req, ctx):
    raise("ValueError", "panne")

func stop(req, ctx):
    STOP[0].stop()
    return {"texte": "arrêt"}

func serve_main(cert, key):
    schema := pb.parse_proto(PROTO)
    srv := gs.Server("127.0.0.1", 0, cert, key)
    STOP[0] = srv
    srv.add_service(schema, "demo.Echo", {"Unary": unary, "Stream": stream, "Collect": collect, "Bidi": bidi, "Fail": failing, "Big": crash, "Stop": stop})
    thread.send(srv.port())
    srv.serve_forever(0.2)
    errs := srv.errors
    srv.close()
    return errs

if thread.is_main():
    schema := pb.parse_proto(PROTO)

    # HPACK : RFC 7541 C.4 (Huffman, table dynamique)
    d := g.HpackDecoder()
    d.decode(_n.to_bytes(enc.hex_decode("828684418cf1e3c2e5f23a6ba0ab90f4ff")))
    d.decode(_n.to_bytes(enc.hex_decode("828684be5886a8eb10649cbf")))
    h3 := d.decode(_n.to_bytes(enc.hex_decode("828785bf408825a849e95ba97d7f8925a849e95bb8e8b4bf")))
    check_eq(h3[4], ["custom-key", "custom-value"], "HPACK C.4.3")
    check_eq(d.size, 164, "HPACK : taille de la table dynamique")
    check_eq(enc.hex_encode(_n.from_bytes(g.huffman_encode("www.example.com"))), "f1e3c2e5f23a6ba0ab90f4ff", "Huffman")
    blk := g.HpackEncoder().encode([[":method", "POST"], ["x-é", "valeur é"], ["authorization", "s"]])
    check_eq(g.HpackDecoder().decode(blk), [[":method", "POST"], ["x-é", "valeur é"], ["authorization", "s"]], "HPACK aller-retour")

    # protobuf
    o := schema.encode("Rep", {"texte": "a", "taille": 300})
    check_eq(enc.hex_encode(o), "0a016110ac02", "protobuf : octets")
    check_eq(schema.decode("Rep", o), {"texte": "a", "taille": 300}, "protobuf : décodage")
    check_eq(schema.decode("Rep", ""), {"texte": "", "taille": 0}, "protobuf : valeurs par défaut")
    check_eq(schema.service("Echo").method("Collect").kind(), "client_streaming", "protobuf : service")

    # gRPC : encadrement, statuts, délais
    msgs := g.unframe_messages(g.frame_message("abc") + g.frame_message(""))
    check_eq(msgs[0], ["abc", ""], "encadrement gRPC")
    check_eq([g.encode_timeout(0.25), g.parse_timeout("2S"), g.parse_timeout("100m")], ["250m", 2.0, 0.1], "grpc-timeout")

    go := proc.which("go")
    peer := null
    if go != null:
        peer = "/tmp/alex_grpc_peer"
        b := proc.Command("go").args(["build", "-o", peer, "tests/network/grpc_peer.go"]).env({"GO111MODULE": "off", "GOCACHE": "/tmp/alex_gocache"}).stdout("pipe").stderr("pipe").run(null, 300.0)
        if b.code != 0:
            print("test_grpc : compilation du pair Go impossible, interopérabilité ignorée : " + b.stderr)
            peer = null

    if peer != null:
        # client Alex -> serveur Go
        srv := proc.Command(peer).args(["serve"]).stdout("pipe").stderr("null").spawn()
        port := s.trim(srv.read_line("stdout", 20.0))
        ch := gc.Channel("127.0.0.1:" + port, false, null, true, {"x-client": "alex"})
        stub := gc.Stub(ch, schema, "demo.Echo")
        r := stub.call("Unary", {"texte": "Ada"})
        check_eq([r["texte"], r["taille"]], ["écho : Ada", 3], "Go : appel unaire")
        check_eq(ch.last_call.metadata["x-vu"], "alex", "Go : métadonnées envoyées")
        check_eq(ch.last_call.trailing_metadata["x-fin"], "oui", "Go : métadonnées de fin")
        st := stub.call("Stream", {"texte": "x"})
        check_eq([len(st), st[0]["texte"], st[2]["taille"]], [3, "n=1", 3], "Go : flux serveur")
        co := stub.call("Collect", [{"texte": "a"}, {"texte": "b"}])
        check_eq([co["texte"], co["taille"]], ["a+b", 2], "Go : flux client")
        big := stub.call("Big", {"texte": ""})
        check_eq(len(big["texte"]), 300000, "Go : réponse de 300 ko (contrôle de flux)")
        try:
            stub.call("Fail", {"texte": "x"})
            check(false, "Go : faute attendue")
        catch e:
            check_eq(g.status_of(e), (g.NOT_FOUND, "absent é"), "Go : statut NOT_FOUND + message")
        try:
            ch.unary("/demo.Echo/Absente", "")
            check(false, "Go : UNIMPLEMENTED attendu")
        catch e:
            check_eq(g.status_of(e)[0], g.UNIMPLEMENTED, "Go : méthode inconnue")
        check(ch.ping() >= 0, "Go : PING HTTP/2")
        check_eq([ch.calls, ch.h2 != null], [6, true], "Go : six appels sur une même connexion")
        stub.call("Stop", {"texte": ""})
        ch.close()
        srv.wait(10.0)
        srv.close()

    # serveur Alex dans un fil
    t := thread.spawn(serve_main, [null, null])
    aport := t.receive(10.0)
    if peer != null:
        out := proc.Command(peer).args(["client", "127.0.0.1:" + str(aport)]).stdout("pipe").stderr("pipe").run(null, 60.0)
        j := json.parse(out.stdout)
        check_eq([j["unary"]["Status"], j["unary"]["Texts"], j["unary"]["Header"]], ["0", ["écho : Go"], "go"], "serveur Alex <- Go : unaire")
        check_eq(j["stream"]["Texts"], ["n=1", "n=2", "n=3"], "serveur Alex <- Go : flux serveur (send + retour)")
        check_eq(j["collect"]["Texts"], ["a+b+c"], "serveur Alex <- Go : flux client")
        check_eq([j["big"]["Status"], j["big"]["Texts"]], ["0", ["200008"]], "serveur Alex <- Go : requête de 200 ko (longueur de l'écho)")
        check_eq([j["fail"]["Status"], j["fail"]["Message"]], ["5", "absent %C3%A9"], "serveur Alex <- Go : statut")
        check_eq(j["unknown"]["Status"], "12", "serveur Alex <- Go : UNIMPLEMENTED")
        check_eq(j["stop"]["Status"], "0", "serveur Alex <- Go : arrêt")
    else:
        ch2 := gc.Channel("127.0.0.1:" + str(aport))
        gc.Stub(ch2, schema, "demo.Echo").call("Stop", {"texte": ""})
        ch2.close()
    errs := t.join(30.0)
    check_eq(len(errs), 0, "serveur Alex : aucune erreur interne")

    # Alex <-> Alex, en clair puis en TLS (ALPN h2)
    for secure in [false, true]:
        cert := null
        key := null
        if secure:
            if proc.which("openssl") == null:
                continue
            cert = "/tmp/alex_grpc_cert.pem"
            key = "/tmp/alex_grpc_key.pem"
            certs.generate_self_signed(cert, key, "localhost", ["localhost", "127.0.0.1"], 2)
        t2 := thread.spawn(serve_main, [cert, key])
        p2 := t2.receive(10.0)
        label := "h2c"
        if secure:
            label = "TLS"
        ch3 := gc.Channel("127.0.0.1:" + str(p2), secure, cert)
        stub3 := gc.Stub(ch3, schema, "demo.Echo")
        r3 := stub3.call("Unary", {"texte": "été"}, {"x-client": "alex"})
        check_eq([r3["texte"], ch3.last_call.metadata["x-vu"], ch3.last_call.trailing_metadata["x-bin"]], ["écho : été", "alex", "\u{0}\u{1}"], "Alex ↔ Alex (" + label + ") : unaire + métadonnées")
        check_eq(len(stub3.call("Stream", {"texte": "x"})), 3, "Alex ↔ Alex (" + label + ") : flux serveur")
        b3 := stub3.call("Bidi", [{"texte": "a"}, {"texte": "b"}])
        check_eq([b3[0]["texte"], b3[1]["texte"]], ["A", "B"], "Alex ↔ Alex (" + label + ") : bidirectionnel")
        try:
            stub3.call("Big", {"texte": "x"})
        catch e:
            st3 := g.status_of(e)
            check_eq([st3[0], st3[1]], [g.UNKNOWN, "ValueError : panne"], "Alex ↔ Alex (" + label + ") : exception -> UNKNOWN")
        large := stub3.call("Unary", {"texte": "z" * 150000})
        check_eq(large["taille"], 150000, "Alex ↔ Alex (" + label + ") : 150 ko dans chaque sens")
        stub3.call("Stop", {"texte": ""})
        ch3.close()
        e3 := t2.join(30.0)
        check_eq(e3, ["ValueError: panne"], "Alex ↔ Alex (" + label + ") : erreurs du serveur")

    print(f"grpc : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_grpc : échecs")

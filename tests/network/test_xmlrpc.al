# Test de network.xmlrpc, xmlrpc_client et xmlrpc_server : conversion des types, fautes ; client Alex contre le
# serveur XML-RPC de Python ; client Python contre le serveur Alex (dans un fil) ; Alex contre Alex.

from core use len, type
from collections use append
use string as s
use json
use process as proc
use concurrency.thread as thread
use network.xmlrpc as rpc
use network.xmlrpc_client as xc
use network.xmlrpc_server as xs
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

func panne():
    raise("ValueError", "en panne")

func binaire(b):
    return rpc.Binary(nu.from_bytes(b.bytes()[::-1]))

func serve_main(n):
    d := xs.Dispatcher()
    d.register("somme", (a, b) => a + b, "Somme", [["int", "int", "int"]])
    d.register("echo", (x) => x)
    d.register("panne", panne)
    d.register("binaire", binaire)
    d.register_introspection()
    d.register_multicall()
    srv := xs.Server("127.0.0.1", 0, d)
    thread.send(srv.port())
    srv.serve(n)
    srv.close()
    return d.errors

if thread.is_main():
    # conversion
    x := rpc.dumps([1, "a<b", 0.1 + 0.2, true, null, [1, [2]], {"k": "v"}, 4294967296, rpc.DateTime(2026, 1, 2, 3, 4, 5), rpc.Binary("\u{0}\u{FF}")], "m.n")
    r := rpc.loads(x)
    check_eq(r[1], "m.n", "nom de méthode")
    p := r[0]
    check_eq([p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7]], [1, "a<b", 0.1 + 0.2, true, null, [1, [2]], {"k": "v"}, 4294967296], "types simples et composés")
    check_eq(p[8].iso(), "20260102T03:04:05", "dateTime.iso8601")
    check_eq(p[9].data, "\u{0}\u{FF}", "base64")
    check(s.contains(x, "<i8>4294967296</i8>"), "<i8> hors de 32 bits")
    check(s.contains(x, "<double>0.30000000000000004</double>"), "double exact")
    check_eq(error_of(() => rpc.loads(rpc.dumps_fault(3, "x"))), "XmlRpcFault", "faute levée")
    check_eq(error_of(() => rpc.dumps([float("nan")])), "TypeError", "NaN refusé")
    check_eq(error_of(() => rpc.loads("<a/>")), "ProtocolError", "racine invalide")
    check_eq(error_of(() => rpc.loads("<methodResponse><params><param><value><int>x</int></value></param></params></methodResponse>")), "ProtocolError", "entier invalide")
    check_eq(rpc.loads("<methodResponse><params><param><value>brut</value></param></params></methodResponse>")[0][0], "brut", "valeur sans type = string")

    d := xs.Dispatcher()
    d.register("double", (n) => n * 2)
    check_eq(rpc.loads(d.dispatch(rpc.dumps([21], "double")))[0][0], 42, "dispatch local")
    check_eq(error_of(() => rpc.loads(d.dispatch("<pas xml"))), "XmlRpcFault", "XML illisible -> faute")
    try:
        rpc.loads(d.dispatch(rpc.dumps([], "absente")))
    catch e:
        check_eq(rpc.fault_of(e).code, -32601, "méthode inconnue -> -32601")

    if proc.which("python3") != null:
        # client Alex -> serveur Python
        py := proc.Command("python3").args(["tests/network/xmlrpc_peer.py", "serve"]).stdout("pipe").stderr("null").spawn()
        port := s.trim(py.read_line("stdout", 10.0))
        prox := xc.ServerProxy("http://127.0.0.1:" + port + "/")
        check_eq(prox.call("somme", 2, 40), 42, "Python : somme")
        check_eq(prox.method("inverse")("été"), "été"[::-1], "Python : chaîne Unicode")
        t := prox.call("types")
        check_eq([t["entier"], t["réel"], t["liste"], t["vrai"], t["grand"]], [7, 0.5, [1, "x", null], true, 2147483647], "Python : types")
        check_eq(prox.call("binaire", rpc.Binary("\u{1}\u{2}")).data, "\u{2}\u{1}", "Python : base64")
        check_eq(prox.call("date", rpc.DateTime(2026, 10, 11, 12, 0, 0)), "20261011T12:00:00", "Python : dateTime")
        try:
            prox.call("faute")
            check(false, "Python : faute attendue")
        catch e:
            f := rpc.fault_of(e)
            check_eq([f.code, f.message], [42, "faute voulue"], "Python : faute")
        check(len(prox.list_methods()) >= 8, "Python : introspection")
        mc := xc.MultiCall(prox)
        mc.add("somme", 1, 2)
        mc.add("faute")
        mc.add("inverse", "abc")
        res := mc.run()
        check_eq([res[0].get(), res[1].ok(), res[1].fault.code, res[2].get()], [3, false, 42, "cba"], "Python : multicall")
        prox.call("stop")
        prox.close()
        py.wait(10.0)
        py.close()

        # client Python -> serveur Alex
        th := thread.spawn(serve_main, [10])
        aport := th.receive(10.0)
        url := "http://127.0.0.1:" + str(aport) + "/RPC2"
        out := proc.Command("python3").args(["tests/network/xmlrpc_peer.py", "client", url]).stdout("pipe").run(null, 30.0)
        j := json.parse(out.stdout)
        check_eq(j["somme"], 5, "serveur Alex : somme")
        check_eq(j["echo"], {"a": [1, 2.5, "é", null, true]}, "serveur Alex : écho de types")
        check(len(j["methods"]) >= 7, "serveur Alex : listMethods")
        check_eq(j["inconnue"], -32601, "serveur Alex : méthode inconnue")
        check_eq(j["arite"], -32602, "serveur Alex : nombre de paramètres")
        check_eq(j["panne"], [-32500, "ValueError : en panne"], "serveur Alex : exception -> faute")
        check_eq(j["multi"], [2, 4], "serveur Alex : multicall")
        check_eq(j["bin"], "ff0100", "serveur Alex : base64")
        # Alex -> Alex
        ap := xc.ServerProxy(url)
        check_eq(ap.call("somme", 20, 22), 42, "Alex ↔ Alex")
        check_eq(ap.method_signature("somme"), [["int", "int", "int"]], "Alex ↔ Alex : signature")
        errs := th.join(20.0)
        check_eq(errs, ["ValueError: en panne"], "erreurs du serveur Alex")
        ap.close()
    else:
        print("test_xmlrpc : python3 absent, interopérabilité ignorée")

    print(f"xmlrpc : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_xmlrpc : échecs")

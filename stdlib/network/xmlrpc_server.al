# ALEX STANDARD LIBRARY — network.xmlrpc_server
#
# Serveur XML-RPC : répartiteur de méthodes (Dispatcher) indépendant du transport, et serveur HTTP prêt à
# l'emploi (sur network.http_server : connexions persistantes, HTTPS, intergiciels).
#
#   d := Dispatcher()
#   d.register("exemple.somme", (a, b) => a + b, "Somme de deux entiers", [["int", "int", "int"]])
#   d.register_introspection()          system.listMethods, system.methodHelp, system.methodSignature
#   d.register_multicall()              system.multicall
#   d.dispatch(xml) -> xml              une requête XML-RPC -> sa réponse (fautes comprises)
#   srv := Server("127.0.0.1", 8000, d) ; srv.serve_forever()      ou d.mount(app, "/RPC2") sur une App
#
# Fautes renvoyées : -32700 (XML illisible), -32600 (message XML-RPC invalide), -32601 (méthode inconnue),
# -32602 (nombre de paramètres), et pour une exception du gestionnaire : le code d'une faute levée par
# network.xmlrpc.raise_fault, sinon -32500 avec « Type : message ».
#
# Exemple
#   use network.xmlrpc_server as xs
#   d := xs.Dispatcher()
#   d.register("pow", (x, y) => x ** y)
#   d.register_introspection()
#   xs.Server("127.0.0.1", 8000, d).serve_forever()

from core use len, type, arity
from collections use append, keys, contains_key
use string as _s
use network.xmlrpc as _rpc
use network.http_server as _hs

class _Method:
    func init(fn, help, signature):
        self.fn = fn
        self.help = help
        self.signature = signature

class Dispatcher:
    # allow_none : renvoyer null en <nil/> ; expose_errors : mettre le message des exceptions dans les fautes
    # (false : « erreur interne » seulement, pour ne rien divulguer).
    func init(allow_none=true, expose_errors=true):
        self.methods = {}
        self.allow_none = allow_none
        self.expose_errors = expose_errors
        self.errors = []          # exceptions des gestionnaires (« Type: message »)
        self.calls = 0

    # Enregistre une fonction sous `name`. help : texte ; signature : liste de [retour, param1, ...].
    func register(name, fn, help="", signature=null):
        if type(name) != "str" or name == "":
            raise("ArgumentError", "xmlrpc_server.register : nom de méthode str non vide attendu")
        self.methods[name] = _Method(fn, help, signature)
        return self

    # Enregistre plusieurs fonctions : dict nom -> fonction (préfixe facultatif « objet. »).
    func register_all(functions, prefix=""):
        for k in keys(functions):
            self.register(prefix + k, functions[k])
        return self

    func unregister(name):
        if contains_key(self.methods, name):
            d := {}
            for k in keys(self.methods):
                if k != name:
                    d[k] = self.methods[k]
            self.methods = d

    func register_introspection():
        me := self
        self.register("system.listMethods", () => me.list_methods(), "Liste des méthodes du serveur.", [["array"]])
        self.register("system.methodHelp", (n) => me._help(n), "Aide d'une méthode.", [["string", "string"]])
        self.register("system.methodSignature", (n) => me._signature(n), "Signatures d'une méthode.", [["array", "string"]])
        return self

    func register_multicall():
        me := self
        self.register("system.multicall", (calls) => me._multicall(calls), "Plusieurs appels en un seul (tableau de {methodName, params}).", [["array", "array"]])
        return self

    func list_methods():
        out := []
        for k in keys(self.methods):
            append(out, k)
        # tri par insertion (noms)
        i := 1
        while i < len(out):
            x := out[i]
            j := i - 1
            while j >= 0 and out[j] > x:
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = x
            i += 1
        return out

    func _help(name):
        if not contains_key(self.methods, name):
            _rpc.raise_fault(_rpc.METHOD_NOT_FOUND, "méthode inconnue « " + str(name) + " »")
        return self.methods[name].help

    func _signature(name):
        if not contains_key(self.methods, name):
            _rpc.raise_fault(_rpc.METHOD_NOT_FOUND, "méthode inconnue « " + str(name) + " »")
        s := self.methods[name].signature
        if s == null:
            return "undef"
        return s

    func _multicall(calls):
        if type(calls) != "list":
            _rpc.raise_fault(_rpc.INVALID_PARAMS, "system.multicall : tableau attendu")
        out := []
        for c in calls:
            try:
                if type(c) != "dict" or not contains_key(c, "methodName"):
                    _rpc.raise_fault(_rpc.INVALID_PARAMS, "élément de multicall sans methodName")
                if c["methodName"] == "system.multicall":
                    _rpc.raise_fault(_rpc.INVALID_PARAMS, "system.multicall récursif refusé")
                params := []
                if contains_key(c, "params"):
                    params = c["params"]
                append(out, [self.call(c["methodName"], params)])
            catch e:
                f := self._fault_for(e)
                append(out, {"faultCode": f.code, "faultString": f.message})
        return out

    # Appelle une méthode enregistrée (XmlRpcFault si elle est inconnue ou si l'arité ne convient pas).
    func call(name, params):
        if not contains_key(self.methods, name):
            _rpc.raise_fault(_rpc.METHOD_NOT_FOUND, "méthode inconnue « " + str(name) + " »")
        m := self.methods[name]
        ar := arity(m.fn)
        if ar != null and (len(params) < ar[0] or len(params) > ar[1]):
            expected := str(ar[0])
            if ar[1] != ar[0]:
                expected = str(ar[0]) + ".." + str(ar[1])
                if ar[1] > 1000:
                    expected = "au moins " + str(ar[0])
            _rpc.raise_fault(_rpc.INVALID_PARAMS, name + " : " + expected + " paramètre(s) attendu(s), " + str(len(params)) + " reçu(s)")
        self.calls += 1
        return m.fn(*params)

    func _fault_for(e):
        f := _rpc.fault_of(e)
        if f != null:
            return f
        append(self.errors, e.type + ": " + e.message)
        if self.expose_errors:
            return _rpc.Fault(_rpc.APPLICATION_ERROR, e.type + " : " + e.message)
        return _rpc.Fault(_rpc.APPLICATION_ERROR, "erreur interne du serveur")

    # Réponse XML-RPC (texte) à une requête XML-RPC (texte) ; ne lève jamais.
    func dispatch(body):
        parsed := null
        try:
            parsed = _rpc.loads(body)
        catch e:
            if e.type == "XmlError":
                return _rpc.dumps_fault(_rpc.PARSE_ERROR, "XML illisible : " + e.message)
            return _rpc.dumps_fault(_rpc.INVALID_XMLRPC, "requête XML-RPC invalide : " + e.message)
        if parsed[1] == null:
            return _rpc.dumps_fault(_rpc.INVALID_XMLRPC, "requête XML-RPC invalide : <methodCall> attendu")
        try:
            result := self.call(parsed[1], parsed[0])
            return _rpc.dumps_response(result, self.allow_none)
        catch e:
            if e.type == "TypeError" and _s.starts_with(e.message, "xmlrpc :"):
                append(self.errors, e.type + ": " + e.message)
                return _rpc.dumps_fault(_rpc.INTERNAL_ERROR, "résultat non représentable : " + e.message)
            f := self._fault_for(e)
            return _rpc.dumps_fault(f.code, f.message)

    # Gestionnaire network.http_server pour ce répartiteur (POST seulement).
    func handler():
        me := self
        return (req) => _handle_http(me, req)

    # Monte le répartiteur sur une App de network.http_server à l'adresse `path`.
    func mount(app, path="/RPC2"):
        app.route(["POST"], path, self.handler())
        return app

func _handle_http(d, req):
    if req.method != "POST":
        r := _hs.text("XML-RPC : POST attendu\n", 405)
        r.headers.set("Allow", "POST")
        return r
    return _hs.Response(200, d.dispatch(req.body), null, "text/xml; charset=utf-8")

class Server:
    # Serveur HTTP(S) XML-RPC sur host:port ; paths : chemins servis (« / » et « /RPC2 » par défaut).
    func init(host="127.0.0.1", port=8000, dispatcher=null, paths=null, cert_file=null, key_file=null, log=false):
        self.dispatcher = dispatcher
        if dispatcher == null:
            self.dispatcher = Dispatcher()
            self.dispatcher.register_introspection()
            self.dispatcher.register_multicall()
        self.app = _hs.App()
        ps := paths
        if ps == null:
            ps = ["/", "/RPC2"]
        for p in ps:
            self.app.route(["POST"], p, self.dispatcher.handler())
        if log:
            self.app.use_middleware(_hs.logger())
        self.http = _hs.Server(self.app, host, port, cert_file, key_file)

    func register(name, fn, help="", signature=null):
        self.dispatcher.register(name, fn, help, signature)
        return self

    func port():
        return self.http.port()

    func url(path="/RPC2"):
        return self.http.url(path)

    func serve_forever(poll=0.5):
        self.http.serve_forever(poll)

    func serve(count, poll=0.5):
        self.http.serve(count, poll)

    func stop():
        self.http.stop()

    func close():
        self.http.close()

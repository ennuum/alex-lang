# ALEX STANDARD LIBRARY — network.xmlrpc_client
#
# Client XML-RPC sur HTTP / HTTPS (network.http_client : connexion persistante, mandataires, authentification).
#
#   p := ServerProxy("http://hôte:8000/RPC2")
#   p.call("exemple.somme", 1, 2)          appel ; XmlRpcFault si le serveur répond par une faute
#   somme := p.method("exemple.somme")     fonction prête à appeler : somme(1, 2)
#   p.list_methods() / method_help(nom) / method_signature(nom)    introspection (system.*)
#   m := MultiCall(p) ; m.add("a", 1) ; m.add("b") ; m.run()     plusieurs appels en un aller-retour
#
# Erreurs : XmlRpcFault (faute du serveur, voir network.xmlrpc.fault_of), HttpError (statut HTTP d'erreur),
# ProtocolError (réponse XML-RPC mal formée), NetworkError, TimeoutError...
#
# Exemple
#   use network.xmlrpc_client as xc
#   p := xc.ServerProxy("http://127.0.0.1:8000/")
#   print(p.call("pow", 2, 10))           # 1024

from core use len, type
from collections use append
use string as _s
use network.xmlrpc as _rpc
use network.http_client as _hc
use network.url as _url

class ServerProxy:
    # url : point d'accès (identifiants « http://u:p@hôte/ » acceptés) ; allow_none : envoyer null en <nil/> ;
    # headers : en-têtes supplémentaires ; timeout, verify, ca_file : voir network.http_client.Client.
    func init(url, allow_none=true, timeout=30.0, headers=null, verify=true, ca_file=null, auth=null, client=null):
        self.url = _url.parse(url)
        if self.url.scheme != "http" and self.url.scheme != "https":
            raise("UrlError", "xmlrpc_client : URL http(s) attendue (obtenu « " + url + " »)")
        self.allow_none = allow_none
        self.client = client
        if client == null:
            self.client = _hc.Client(null, headers, timeout, verify, ca_file, auth, false)
        self.calls = 0

    func _post(body):
        r := self.client.post(self.url.str(), body, null, null, null, {"Content-Type": "text/xml; charset=utf-8", "Accept": "text/xml"})
        if r.status != 200:
            raise("HttpError", "xmlrpc_client : HTTP " + str(r.status) + " " + r.reason + " (" + self.url.redacted().str() + ")")
        return r.text()

    # Appelle `method` avec les paramètres donnés ; rend la valeur de la réponse.
    func call(method, *params):
        return self.call_list(method, params)

    func call_list(method, params):
        body := _rpc.dumps(params, method, self.allow_none)
        self.calls += 1
        result := _rpc.loads(self._post(body))
        values := result[0]
        if len(values) != 1:
            raise("ProtocolError", "xmlrpc_client : la réponse doit porter exactement une valeur (" + str(len(values)) + ")")
        return values[0]

    # Fonction qui appelle `method` : p.method("a.b")(1, 2).
    func method(name):
        proxy := self
        return (*args) => proxy.call_list(name, args)

    func list_methods():
        return self.call("system.listMethods")

    func method_help(name):
        return self.call("system.methodHelp", name)

    func method_signature(name):
        return self.call("system.methodSignature", name)

    func close():
        self.client.close()

    func __enter__():
        return self

    func __exit__(t, v, tb):
        self.close()
        return false

# Résultat d'un appel d'un MultiCall : valeur, ou faute.
class CallResult:
    func init(value, fault):
        self.value = value
        self.fault = fault        # network.xmlrpc.Fault ou null

    func ok():
        return self.fault == null

    # Valeur, ou lève la faute (XmlRpcFault).
    func get():
        if self.fault != null:
            _rpc.raise_fault(self.fault.code, self.fault.message)
        return self.value

# Regroupe plusieurs appels en un seul aller-retour (system.multicall).
class MultiCall:
    func init(proxy):
        self.proxy = proxy
        self.calls = []

    func add(method, *params):
        p := []
        for x in params:
            append(p, x)
        append(self.calls, {"methodName": method, "params": p})
        return self

    # Liste de CallResult, dans l'ordre des add().
    func run():
        raw := self.proxy.call("system.multicall", self.calls)
        out := []
        for item in raw:
            if type(item) == "dict":
                code := 0
                msg := ""
                if "faultCode" in item:
                    code = item["faultCode"]
                if "faultString" in item:
                    msg = item["faultString"]
                append(out, CallResult(null, _rpc.Fault(code, msg)))
            elif type(item) == "list" and len(item) == 1:
                append(out, CallResult(item[0], null))
            else:
                raise("ProtocolError", "xmlrpc_client : réponse de system.multicall mal formée")
        self.calls = []
        return out

# Appel unique sans garder de proxy.
func call(url, method, *params):
    p := ServerProxy(url)
    try:
        r := p.call_list(method, params)
        p.close()
        return r
    catch e:
        p.close()
        raise(e)

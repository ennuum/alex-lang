# ALEX STANDARD LIBRARY — web.js.js_interop
#
# Interopérabilité navigateur <-> serveur ALEX par appels de procédure distants JSON-RPC 2.0 : registre de
# fonctions ALEX exposées (paramètres par position ou par nom, valeurs par défaut, notifications, lots),
# traitement des requêtes avec les codes d'erreur standard, montage sur un web.server Router, et GÉNÉRATION
# du client JavaScript (module ES, fonctions async, espaces de noms « user.get ») et de déclarations TypeScript.
#
#   use web.js.js_interop as rpc
#   reg := rpc.Registry()
#   reg.register("somme", (a, b) => a + b, ["a", "b"])
#   reg.register("user.saluer", (nom) => "Bonjour " + nom, ["nom"], "Salue quelqu'un")
#   reg.handle_text("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"somme\",\"params\":[20,22]}")
#   # {"jsonrpc":"2.0","id":1,"result":42}
#   reg.handle({"jsonrpc": "2.0", "id": 2, "method": "somme", "params": {"b": 2, "a": 1}})["result"]   # 3
#   reg.mount(router, "/rpc")                    # POST /rpc sur un web.server.request_dispatch.Router
#   reg.client_js("/rpc")                        # export async function somme(a, b) { … } export const user = {…}
#   reg.typescript()                             # export declare function somme(a: unknown, b: unknown): Promise<unknown>;
#
# Erreurs : JsBridgeError (enregistrement invalide) ; côté protocole, les erreurs deviennent des réponses
# JSON-RPC (-32700 analyse, -32600 requête, -32601 méthode, -32602 paramètres, -32603 interne, -32000 application).

from core use len, type
from collections use append, keys
use string as _s
use json as _json
use web.js.js_errors as _err
use web.js.js_types as _t
use web.http.response as _resp

const PARSE_ERROR := -32700
const INVALID_REQUEST := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602
const INTERNAL_ERROR := -32603
const APPLICATION_ERROR := -32000

# Erreur applicative à lever depuis une méthode exposée : code, message, données facultatives.
func rpc_error(message, code=-32000, data=null):
    raise("RpcError", _json.stringify({"code": code, "message": message, "data": data}, null, false))

class Method:
    func init(name, fn, params, description, defaults):
        self.name = name
        self.fn = fn
        self.params = params
        self.description = description
        self.defaults = defaults

    func describe():
        return {"name": self.name, "params": self.params, "description": self.description}

func _valid_name(name):
    if len(name) == 0 or _s.starts_with(name, "rpc."):
        return false
    for part in _s.split(name, "."):
        if not _t.is_identifier_name(part):
            return false
    return true

func _apply(fn, args):
    n := len(args)
    if n == 0:
        return fn()
    if n == 1:
        return fn(args[0])
    if n == 2:
        return fn(args[0], args[1])
    if n == 3:
        return fn(args[0], args[1], args[2])
    if n == 4:
        return fn(args[0], args[1], args[2], args[3])
    if n == 5:
        return fn(args[0], args[1], args[2], args[3], args[4])
    if n == 6:
        return fn(args[0], args[1], args[2], args[3], args[4], args[5])
    _err.bridge_error("js_interop", "au plus 6 paramètres par méthode")

class Registry:
    func init():
        self.methods = {}
        self.order = []
        self.debug = false            # vrai : détail des exceptions internes dans error.data
        self.discover = true          # méthode rpc.discover (liste des méthodes)

    # params : noms des paramètres (pour l'appel par nom et le client généré) ; defaults : dict nom -> valeur.
    func register(name, fn, params=null, description=null, defaults=null):
        if not _valid_name(name):
            _err.bridge_error("Registry.register", "nom de méthode invalide « " + str(name) + " »")
        if name in self.methods:
            _err.bridge_error("Registry.register", "méthode « " + name + " » déjà enregistrée")
        ps := params if params != null else []
        for p in ps:
            if not _t.is_identifier(p):
                _err.bridge_error("Registry.register", "nom de paramètre invalide « " + str(p) + " »")
        self.methods[name] = Method(name, fn, ps, description, defaults if defaults != null else {})
        append(self.order, name)
        return self

    func unregister(name):
        if name in self.methods:
            kept := {}
            for k in keys(self.methods):
                if k != name:
                    kept[k] = self.methods[k]
            self.methods = kept
            out := []
            for n in self.order:
                if n != name:
                    append(out, n)
            self.order = out
        return self

    func names():
        return self.order

    func _error(id, code, message, data=null):
        e := {"code": code, "message": message}
        if data != null:
            e["data"] = data
        return {"jsonrpc": "2.0", "id": id, "error": e}

    # Arguments positionnels depuis params (liste ou dict) ; null si incompatibles.
    func _arguments(m, params):
        if params == null:
            params = []
        if type(params) == "list":
            if len(m.params) > 0 and len(params) > len(m.params):
                return null
            args := []
            for p in params:
                append(args, p)
            i := len(args)
            while i < len(m.params):
                nm := m.params[i]
                if not (nm in m.defaults):
                    return null
                append(args, m.defaults[nm])
                i += 1
            return args
        if type(params) == "dict":
            for k in keys(params):
                if not (k in m.params):
                    return null
            args := []
            for nm in m.params:
                if nm in params:
                    append(args, params[nm])
                elif nm in m.defaults:
                    append(args, m.defaults[nm])
                else:
                    return null
            return args
        return null

    # Traite une requête décodée (dict) ou un lot (liste) ; renvoie la réponse (dict / liste) ou null
    # (notification(s) uniquement).
    func handle(request):
        if type(request) == "list":
            if len(request) == 0:
                return self._error(null, INVALID_REQUEST, "lot vide")
            out := []
            for r in request:
                x := self._one(r)
                if x != null:
                    append(out, x)
            return out if len(out) > 0 else null
        return self._one(request)

    func _one(req):
        if type(req) != "dict" or not ("method" in req) or type(req["method"]) != "str" or ("jsonrpc" in req and req["jsonrpc"] != "2.0"):
            return self._error(req["id"] if type(req) == "dict" and "id" in req else null, INVALID_REQUEST, "requête JSON-RPC invalide")
        is_notification := not ("id" in req)
        id := req["id"] if "id" in req else null
        if id != null and type(id) != "str" and type(id) != "int" and type(id) != "float":
            return self._error(null, INVALID_REQUEST, "identifiant invalide")
        name := req["method"]
        if name == "rpc.discover" and self.discover:
            out := []
            for n in self.order:
                append(out, self.methods[n].describe())
            return null if is_notification else {"jsonrpc": "2.0", "id": id, "result": out}
        if not (name in self.methods):
            return null if is_notification else self._error(id, METHOD_NOT_FOUND, "méthode inconnue « " + name + " »")
        m := self.methods[name]
        args := self._arguments(m, req["params"] if "params" in req else null)
        if args == null:
            return null if is_notification else self._error(id, INVALID_PARAMS, "paramètres invalides pour « " + name + " »" + (" (attendus : " + _s.join(", ", m.params) + ")" if len(m.params) > 0 else ""))
        result := null
        try:
            result = _apply(m.fn, args)
        catch e:
            if e.type == "RpcError":
                d := _json.parse(e.message)
                return null if is_notification else self._error(id, d["code"], d["message"], d["data"])
            data := (str(e.type) + " : " + str(e.message)) if self.debug else null
            return null if is_notification else self._error(id, INTERNAL_ERROR, "erreur interne", data)
        if is_notification:
            return null
        return {"jsonrpc": "2.0", "id": id, "result": result}

    # Requête texte -> réponse texte ("" pour une notification).
    func handle_text(text):
        req := null
        try:
            req = _json.parse(text)
        catch e:
            return _json.stringify(self._error(null, PARSE_ERROR, "JSON invalide"), null, false)
        r := self.handle(req)
        if r == null:
            return ""
        return _json.stringify(r, null, false)

    # Gestionnaire HTTP (web.http Request -> Response).
    func http_handler(req):
        body := self.handle_text(req.text())
        if body == "":
            return _resp.no_content()
        return _resp.text(body, 200, {"Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store"})

    func mount(router, path="/rpc"):
        router.post(path, (req) => self.http_handler(req))
        return router

    # ------------------------------------------------------------ client JavaScript

    func client_js(endpoint="/rpc", module=true, credentials="same-origin"):
        lines := []
        append(lines, "// Client JSON-RPC généré par ALEX (web.js.js_interop) — ne pas modifier.")
        append(lines, "let __id = 0;")
        append(lines, "const __trim = (a) => { while (a.length && a[a.length - 1] === undefined) a.pop(); return a; };")
        append(lines, "async function __rpc(method, params) {")
        append(lines, "  const res = await fetch(" + _t.quote(endpoint) + ", {")
        append(lines, "    method: \"POST\",")
        append(lines, "    credentials: " + _t.quote(credentials) + ",")
        append(lines, "    headers: { \"Content-Type\": \"application/json\", \"Accept\": \"application/json\" },")
        append(lines, "    body: JSON.stringify({ jsonrpc: \"2.0\", id: ++__id, method, params })")
        append(lines, "  });")
        append(lines, "  if (res.status === 204) return undefined;")
        append(lines, "  const data = await res.json();")
        append(lines, "  if (data.error) {")
        append(lines, "    const err = new Error(data.error.message);")
        append(lines, "    err.code = data.error.code;")
        append(lines, "    err.data = data.error.data;")
        append(lines, "    throw err;")
        append(lines, "  }")
        append(lines, "  return data.result;")
        append(lines, "}")
        groups := {}
        group_order := []
        exported := []
        for name in self.order:
            m := self.methods[name]
            ps := _s.join(", ", m.params)
            parts := _s.split(name, ".")
            if len(parts) == 1:
                append(lines, "")
                if m.description != null:
                    append(lines, "/** " + _s.replace(m.description, "*/", "* /") + " */")
                append(lines, ("export " if module else "") + "async function " + _t.safe_identifier(name) + "(" + ps + ") {")
                append(lines, "  return __rpc(" + _t.quote(name) + ", __trim([" + ps + "]));")
                append(lines, "}")
                append(exported, _t.safe_identifier(name))
            else:
                g := parts[0]
                if not (g in groups):
                    groups[g] = []
                    append(group_order, g)
                append(groups[g], m)
        for g in group_order:
            append(lines, "")
            entries := []
            for m in groups[g]:
                rest := m.name[len(g) + 1:len(m.name)]
                ps := _s.join(", ", m.params)
                append(entries, "  " + _t.property_key(rest) + ": (" + ps + ") => __rpc(" + _t.quote(m.name) + ", __trim([" + ps + "]))")
            append(lines, ("export " if module else "") + "const " + _t.safe_identifier(g) + " = Object.freeze({")
            append(lines, _s.join(",\n", entries))
            append(lines, "});")
            append(exported, _t.safe_identifier(g))
        if not module:
            append(lines, "")
            append(lines, "window.alexRpc = { " + _s.join(", ", exported) + " };")
        return _s.join("\n", lines) + "\n"

    # Déclarations TypeScript (.d.ts) du client généré.
    func typescript():
        lines := []
        groups := {}
        group_order := []
        for name in self.order:
            m := self.methods[name]
            ps := []
            for p in m.params:
                append(ps, p + ("?" if p in m.defaults else "") + ": unknown")
            sig := "(" + _s.join(", ", ps) + "): Promise<unknown>"
            parts := _s.split(name, ".")
            if len(parts) == 1:
                append(lines, "export declare function " + _t.safe_identifier(name) + sig + ";")
            else:
                g := parts[0]
                if not (g in groups):
                    groups[g] = []
                    append(group_order, g)
                append(groups[g], "  readonly " + _t.property_key(name[len(g) + 1:len(name)]) + ": (" + _s.join(", ", ps) + ") => Promise<unknown>;")
        for g in group_order:
            append(lines, "export declare const " + _t.safe_identifier(g) + ": {")
            for l in groups[g]:
                append(lines, l)
            append(lines, "};")
        return _s.join("\n", lines) + "\n"

# Requête JSON-RPC (dict).
func request(method, params=null, id=1):
    r := {"jsonrpc": "2.0", "method": method}
    if params != null:
        r["params"] = params
    r["id"] = id
    return r

# Notification JSON-RPC (sans id : aucune réponse attendue).
func notification(method, params=null):
    r := {"jsonrpc": "2.0", "method": method}
    if params != null:
        r["params"] = params
    return r

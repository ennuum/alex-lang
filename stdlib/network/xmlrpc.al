# ALEX STANDARD LIBRARY — network.xmlrpc
#
# XML-RPC (spécification de 1999, avec les extensions courantes <nil/> et <i8>) : conversion entre valeurs ALEX
# et messages XML, fautes. Le client est dans network.xmlrpc_client, le serveur dans network.xmlrpc_server.
#
#   Correspondance des types
#     int -> <int> (ou <i8> hors de 32 bits)     bool -> <boolean>      str -> <string>      float -> <double>
#     null -> <nil/>                              list / tuple -> <array> dict -> <struct> (clés str)
#     DateTime -> <dateTime.iso8601>              Binary -> <base64>
#
#   dumps(params, method=null)          appel (method donné) ou réponse
#   dumps_fault(code, message)          réponse de faute
#   loads(xml) -> (params, method)      lève XmlRpcFault si le message est une faute
#   Fault : code, message ; fault_of(erreur) -> Fault d'une XmlRpcFault attrapée
#
# Erreurs : XmlRpcFault (faute renvoyée par le serveur ; message « [code] texte »), XmlError (XML invalide),
# ProtocolError (message XML-RPC mal formé), TypeError (valeur non représentable).
#
# Exemple
#   use network.xmlrpc as rpc
#   x := rpc.dumps([1, "deux", {"trois": 3.0}], "exemple.somme")
#   params, method := rpc.loads(x)

from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use network.xml_parser as _xp
use network.xml_writer as _xw
use network.encoding as _enc
use time as _time

# Codes de faute conventionnels (spécification « xmlrpc-epi » d'interopérabilité).
const PARSE_ERROR := -32700
const UNSUPPORTED_ENCODING := -32701
const INVALID_CHARACTER := -32702
const INVALID_XMLRPC := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602
const INTERNAL_ERROR := -32603
const APPLICATION_ERROR := -32500
const SYSTEM_ERROR := -32400
const TRANSPORT_ERROR := -32300

const MAX_INT := 2147483647
const MIN_INT := -2147483648

func _proto(message):
    raise("ProtocolError", "xmlrpc : " + message)

# Date et heure XML-RPC (sans fuseau, comme la spécification) : « 20260411T08:30:00 ».
class DateTime:
    func init(year, month=1, day=1, hour=0, minute=0, second=0):
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second

    func iso():
        return _pad(self.year, 4) + _pad(self.month, 2) + _pad(self.day, 2) + "T" + _pad(self.hour, 2) + ":" + _pad(self.minute, 2) + ":" + _pad(self.second, 2)

    func str():
        return self.iso()

    func __str__():
        return self.iso()

    func __eq__(other):
        if not isinstance(other, DateTime):
            return false
        return self.iso() == other.iso()

func _pad(n, w):
    s := str(n)
    while len(s) < w:
        s = "0" + s
    return s

# DateTime depuis « 20260411T08:30:00 », « 2026-04-11T08:30:00 » (séparateurs et fuseau tolérés).
func parse_datetime(text):
    t := _s.trim(text)
    digits := []
    for c in t:
        if c >= '0' and c <= '9':
            append(digits, str(c))
        elif c == '+' or c == 'Z' or (c == '-' and len(digits) >= 14):
            break
    d := _s.join("", digits)
    if len(d) < 8:
        _proto("date invalide « " + text + " »")
    while len(d) < 14:
        d += "0"
    return DateTime(to_int(_s.substring(d, 0, 4)), to_int(_s.substring(d, 4, 6)), to_int(_s.substring(d, 6, 8)), to_int(_s.substring(d, 8, 10)), to_int(_s.substring(d, 10, 12)), to_int(_s.substring(d, 12, 14)))

# DateTime d'un horodatage Unix (UTC).
func datetime_from_timestamp(ts):
    secs := to_int(ts)
    days := secs // 86400
    rem := secs - days * 86400
    ymd := _time.civil_from_days(days)
    return DateTime(ymd[0], ymd[1], ymd[2], rem // 3600, (rem % 3600) // 60, rem % 60)

# Données binaires (transportées en base64).
class Binary:
    func init(data):
        self.data = data
        if type(data) == "list":
            self.data = _n.from_bytes(data)

    func bytes():
        return _n.to_bytes(self.data)

    func __eq__(other):
        return isinstance(other, Binary) and other.data == self.data

class Fault:
    func init(code, message):
        self.code = code
        self.message = message

    func str():
        return "[" + str(self.code) + "] " + str(self.message)

# Lève la faute comme exception XmlRpcFault (« [code] message »).
func raise_fault(code, message):
    raise("XmlRpcFault", "[" + str(code) + "] " + str(message))

# Fault d'une exception XmlRpcFault attrapée (null pour une autre erreur).
func fault_of(e):
    if e.type != "XmlRpcFault":
        return null
    m := e.message
    if _s.starts_with(m, "["):
        k := _s.find(m, "]")
        if k > 0:
            code := 0
            try:
                code = to_int(_s.substring(m, 1, k))
            catch err:
                code = 0
            return Fault(code, _s.trim(_s.substring(m, k + 1, len(m))))
    return Fault(0, m)

# ---------------------------------------------------------------- écriture

func _value(v, out, allow_none, depth):
    if depth > 100:
        raise("TypeError", "xmlrpc : imbrication trop profonde (référence circulaire ?)")
    t := type(v)
    append(out, "<value>")
    if v == null:
        if not allow_none:
            raise("TypeError", "xmlrpc : null non représentable (allow_none=false)")
        append(out, "<nil/>")
    elif t == "bool":
        if v:
            append(out, "<boolean>1</boolean>")
        else:
            append(out, "<boolean>0</boolean>")
    elif t == "int":
        if v > MAX_INT or v < MIN_INT:
            append(out, "<i8>" + str(v) + "</i8>")
        else:
            append(out, "<int>" + str(v) + "</int>")
    elif t == "float":
        r := _n.repr_float(v)
        if r == "nan" or r == "inf" or r == "-inf":
            raise("TypeError", "xmlrpc : " + r + " non représentable")
        append(out, "<double>" + r + "</double>")
    elif t == "str" or t == "char":
        append(out, "<string>" + _xw.escape(str(v)) + "</string>")
    elif t == "list" or t == "tuple":
        append(out, "<array><data>")
        for x in v:
            _value(x, out, allow_none, depth + 1)
        append(out, "</data></array>")
    elif t == "dict":
        append(out, "<struct>")
        for k in keys(v):
            if type(k) != "str":
                raise("TypeError", "xmlrpc : clé de struct str attendue (obtenu '" + type(k) + "')")
            append(out, "<member><name>" + _xw.escape(k) + "</name>")
            _value(v[k], out, allow_none, depth + 1)
            append(out, "</member>")
        append(out, "</struct>")
    elif isinstance(v, DateTime):
        append(out, "<dateTime.iso8601>" + v.iso() + "</dateTime.iso8601>")
    elif isinstance(v, Binary):
        append(out, "<base64>" + _enc.base64_encode(v.data) + "</base64>")
    elif isinstance(v, Fault):
        raise("TypeError", "xmlrpc : une Fault ne s'envoie que par dumps_fault")
    else:
        raise("TypeError", "xmlrpc : type non représentable '" + t + "'")
    append(out, "</value>")

# Message XML-RPC : appel de `method` avec params, ou (method null) réponse portant params[0].
func dumps(params, method=null, allow_none=true):
    if type(params) != "list" and type(params) != "tuple":
        raise("TypeError", "xmlrpc.dumps : liste de paramètres attendue")
    out := ["<?xml version=\"1.0\"?>\n"]
    if method != null:
        _xw.check_name(_s.replace(_s.replace(method, ".", "_"), "/", "_"))
        append(out, "<methodCall><methodName>" + _xw.escape(method) + "</methodName><params>")
    else:
        if len(params) != 1:
            raise("ArgumentError", "xmlrpc.dumps : une réponse porte exactement une valeur")
        append(out, "<methodResponse><params>")
    for p in params:
        append(out, "<param>")
        _value(p, out, allow_none, 0)
        append(out, "</param>")
    if method != null:
        append(out, "</params></methodCall>\n")
    else:
        append(out, "</params></methodResponse>\n")
    return _s.join("", out)

# Réponse d'une seule valeur.
func dumps_response(value, allow_none=true):
    return dumps([value], null, allow_none)

func dumps_fault(code, message):
    out := ["<?xml version=\"1.0\"?>\n<methodResponse><fault>"]
    _value({"faultCode": code, "faultString": str(message)}, out, true, 0)
    append(out, "</fault></methodResponse>\n")
    return _s.join("", out)

# ---------------------------------------------------------------- lecture

func _parse_value(el):
    kids := el.elements()
    if len(kids) == 0:
        return el.text()            # chaîne sans balise de type
    if len(kids) > 1:
        _proto("<value> à plusieurs enfants")
    v := kids[0]
    name := v.local
    txt := v.text()
    if name == "string":
        return txt
    if name == "int" or name == "i4" or name == "i8" or name == "i2" or name == "i1" or name == "biginteger":
        t := _s.trim(txt)
        neg := _s.starts_with(t, "-")
        d := t
        if neg or _s.starts_with(t, "+"):
            d = _s.substring(t, 1, len(t))
        if d == "":
            _proto("entier vide")
        for c in d:
            if c < '0' or c > '9':
                _proto("entier invalide « " + t + " »")
        return to_int(t)
    if name == "boolean":
        t := _s.trim(txt)
        if t == "1" or t == "true":
            return true
        if t == "0" or t == "false":
            return false
        _proto("booléen invalide « " + t + " »")
    if name == "double" or name == "float" or name == "bigdecimal":
        try:
            return to_float(_s.trim(txt))
        catch e:
            _proto("réel invalide « " + txt + " »")
    if name == "nil":
        return null
    if name == "dateTime.iso8601":
        return parse_datetime(txt)
    if name == "base64":
        try:
            return Binary(_enc.base64_decode(txt))
        catch e:
            _proto("base64 invalide")
    if name == "array":
        data := v.elements("data")
        if len(data) != 1:
            _proto("<array> sans <data>")
        out := []
        for x in data[0].elements("value"):
            append(out, _parse_value(x))
        return out
    if name == "struct":
        out := {}
        for m in v.elements("member"):
            n := m.elements("name")
            val := m.elements("value")
            if len(n) != 1 or len(val) != 1:
                _proto("<member> mal formé")
            out[n[0].text()] = _parse_value(val[0])
        return out
    _proto("type inconnu <" + name + ">")

# (params, method) d'un message XML-RPC ; method null pour une réponse. Une réponse de faute lève XmlRpcFault.
func loads(text):
    doc := _xp.parse(text, true)
    root := doc.root
    if root.local == "methodCall":
        mn := root.elements("methodName")
        if len(mn) != 1:
            _proto("<methodName> manquant")
        method := _s.trim(mn[0].text())
        return (_params(root), method)
    if root.local == "methodResponse":
        f := root.elements("fault")
        if len(f) == 1:
            vals := f[0].elements("value")
            if len(vals) != 1:
                _proto("<fault> mal formé")
            fv := _parse_value(vals[0])
            if type(fv) != "dict" or not contains_key(fv, "faultCode"):
                _proto("<fault> sans faultCode")
            fs := ""
            if contains_key(fv, "faultString"):
                fs = fv["faultString"]
            raise_fault(fv["faultCode"], fs)
        return (_params(root), null)
    _proto("racine <methodCall> ou <methodResponse> attendue (obtenu <" + root.local + ">)")

func _params(root):
    out := []
    ps := root.elements("params")
    if len(ps) == 0:
        return out
    for p in ps[0].elements("param"):
        vs := p.elements("value")
        if len(vs) != 1:
            _proto("<param> sans <value>")
        append(out, _parse_value(vs[0]))
    return out

# ALEX STANDARD LIBRARY — web.js.js_bridge
#
# Pont de DONNÉES entre ALEX et le JavaScript d'une page : sérialisation sûre dans <script> (pas d'évasion
# par « </script> », U+2028 / U+2029 échappés), données JSON embarquées lues par le client, globales et
# constantes de module, types JS spéciaux (Date, Map, Set, Uint8Array, RegExp, BigInt, undefined), balises
# <script> avec nonce, empreintes CSP « sha256-… ».
#
#   use web.js.js_bridge as jb
#   jb.json_for_script({"html": "</script><b>"})      # {"html":"</script><b>"}
#   jb.data_script({"user": "Ada"}, "donnees")        # <script type="application/json" id="donnees">…</script>
#   jb.read_data_script_js("donnees")                 # JSON.parse(document.getElementById("donnees").textContent)
#   jb.assign_global("APP.config", {"debug": false})  # window.APP = window.APP || {}; window.APP.config = {debug: false};
#   jb.to_js({"quand": jb.Date("2026-10-29T10:00:00Z"), "ids": jb.Set([1, 2]), "n": jb.BigInt(10)})
#   # {quand: new Date("2026-10-29T10:00:00Z"), ids: new Set([1, 2]), n: 10n}
#   jb.inline_script("console.log('ok')", "abc123")   # <script nonce="abc123">console.log('ok')</script>
#   jb.csp_hash("console.log('ok')")                  # 'sha256-…' (pour script-src)
#
# Erreurs : JsValueError (valeur non convertible), JsError (nom de globale invalide).

from core use len, type, to_int
from collections use append, keys
use string as _s
use json as _json
use crypto as _crypto
use web.js.js_errors as _err
use web.js.js_types as _t
use web.js.js_value as _jv
use web.html.html_escape as _hesc

# ---------------------------------------------------------------- types JavaScript spéciaux

class Date:
    # iso : texte ISO 8601 (ou nombre de millisecondes depuis l'époque Unix).
    func init(iso):
        self.value = iso

    func to_js(indent=null, level=0):
        if type(self.value) == "int" or type(self.value) == "float":
            return "new Date(" + _t.number(self.value) + ")"
        return "new Date(" + _t.quote(str(self.value)) + ")"

class Map:
    # entries : dict ou liste de (clé, valeur) (clés de tout type).
    func init(entries):
        self.entries = entries

    func to_js(indent=null, level=0):
        pairs := []
        if type(self.entries) == "dict":
            for k in keys(self.entries):
                append(pairs, [k, self.entries[k]])
        else:
            for e in self.entries:
                append(pairs, [e[0], e[1]])
        return "new Map(" + _jv.to_js(pairs, indent) + ")"

class Set:
    func init(items):
        self.items = items

    func to_js(indent=null, level=0):
        return "new Set(" + _jv.to_js(self.items, indent) + ")"

class Bytes:
    # values : liste d'entiers 0..255 ou texte (encodé en UTF-8).
    func init(values, kind="Uint8Array"):
        self.values = values
        self.kind = kind

    func to_js(indent=null, level=0):
        v := self.values
        if type(v) == "str":
            v = _s.byte_unpack(v)
        for b in v:
            if type(b) != "int" or b < 0 or b > 255:
                _err.value_error("js_bridge.Bytes", "octet invalide : " + str(b))
        return "new " + self.kind + "(" + _jv.to_js(v) + ")"

class RegExp:
    func init(pattern, flags=""):
        for f in flags:
            if not (f in ['d', 'g', 'i', 'm', 's', 'u', 'v', 'y']):
                _err.value_error("js_bridge.RegExp", "drapeau inconnu « " + str(f) + " »")
        self.pattern = pattern
        self.flags = flags

    func to_js(indent=null, level=0):
        return "new RegExp(" + _t.quote(self.pattern) + (", " + _t.quote(self.flags) if self.flags != "" else "") + ")"

class BigInt:
    func init(n):
        self.n = to_int(n)

    func to_js(indent=null, level=0):
        return str(self.n) + "n"

class Symbol:
    func init(description, registered=false):
        self.description = description
        self.registered = registered

    func to_js(indent=null, level=0):
        return ("Symbol.for(" if self.registered else "Symbol(") + _t.quote(self.description) + ")"

# Littéral JavaScript (types spéciaux compris) ; script_safe par défaut : utilisable dans <script>.
func to_js(value, indent=null, script_safe=true):
    return _jv.to_js(value, indent, false, false, script_safe)

func undefined():
    return _t.UNDEFINED

# ---------------------------------------------------------------- JSON dans une page

# JSON compact sûr dans <script> ou un attribut : < > & U+2028 U+2029 échappés en \uXXXX.
func json_for_script(value, sort_keys=false):
    t := _json.stringify(_jv.to_json_compatible(value), null, sort_keys)
    out := []
    for c in t:
        o := _s.ord(c)
        if c == '<':
            append(out, "\\u003c")
        elif c == '>':
            append(out, "\\u003e")
        elif c == '&':
            append(out, "\\u0026")
        elif o == 0x2028:
            append(out, "\\u2028")
        elif o == 0x2029:
            append(out, "\\u2029")
        else:
            append(out, str(c))
    return _s.join("", out)

# Bloc de données <script type="application/json"> (non exécuté, lu par JSON.parse côté client).
func data_script(value, id):
    return "<script type=\"application/json\" id=\"" + _hesc.escape_attribute(str(id)) + "\">" + json_for_script(value) + "</script>"

# Code client lisant un bloc de données.
func read_data_script_js(id):
    return "JSON.parse(document.getElementById(" + _t.quote(str(id)) + ").textContent)"

# Affectation de globale : « a.b.c » crée les objets intermédiaires.
func assign_global(path, value, root="window"):
    parts := _s.split(str(path), ".")
    for p in parts:
        if not _t.is_identifier_name(p):
            _err.js_error("js_bridge.assign_global", "nom invalide « " + p + " »")
    lines := []
    cur := root
    i := 0
    while i < len(parts) - 1:
        cur = cur + "." + parts[i]
        append(lines, cur + " = " + cur + " || {};")
        i += 1
    append(lines, cur + "." + parts[len(parts) - 1] + " = " + to_js(value) + ";")
    return _s.join(" ", lines)

func module_constant(name, value, exported=true):
    if not _t.is_identifier(name):
        _err.js_error("js_bridge.module_constant", "nom invalide « " + name + " »")
    return ("export " if exported else "") + "const " + name + " = " + to_js(value) + ";"

# Appel « fonction(arg1, arg2) » avec des arguments ALEX convertis.
func call_expression(function_path, args=null):
    parts := []
    for a in (args if args != null else []):
        append(parts, to_js(a))
    return str(function_path) + "(" + _s.join(", ", parts) + ")"

# ---------------------------------------------------------------- balises <script>

func _safe_code(code):
    # « </script » et « <!-- » ne doivent pas apparaître tels quels dans un script en ligne
    t := _s.replace(str(code), "</script", "<\\/script")
    t = _s.replace(t, "</SCRIPT", "<\\/SCRIPT")
    return _s.replace(t, "<!--", "<\\!--")

func inline_script(code, nonce=null, module=false):
    attrs := ""
    if module:
        attrs = attrs + " type=\"module\""
    if nonce != null:
        attrs = attrs + " nonce=\"" + _hesc.escape_attribute(nonce) + "\""
    return "<script" + attrs + ">" + _safe_code(code) + "</script>"

func external_script(src, module=false, defer=true, integrity=null, crossorigin=null):
    attrs := " src=\"" + _hesc.escape_attribute(src) + "\""
    if module:
        attrs = attrs + " type=\"module\""
    elif defer:
        attrs = attrs + " defer"
    if integrity != null:
        attrs = attrs + " integrity=\"" + _hesc.escape_attribute(integrity) + "\""
    if crossorigin != null:
        attrs = attrs + " crossorigin=\"" + _hesc.escape_attribute(crossorigin) + "\""
    return "<script" + attrs + "></script>"

# Code exécuté une fois le DOM prêt.
func on_ready(code):
    return "document.readyState === \"loading\" ? document.addEventListener(\"DOMContentLoaded\", () => {\n" + str(code) + "\n}) : (() => {\n" + str(code) + "\n})();"

# Empreinte CSP d'un script en ligne : 'sha256-<base64>'.
func csp_hash(code):
    digest := _crypto.sha256_bytes(_s.byte_unpack(str(code)))
    return "'sha256-" + _crypto.base64_encode(digest) + "'"

# Valeur d'intégrité (SRI) d'un fichier : sha256-<base64>.
func sri_hash(content):
    data := content if type(content) == "list" else _s.byte_unpack(str(content))
    return "sha256-" + _crypto.base64_encode(_crypto.sha256_bytes(data))

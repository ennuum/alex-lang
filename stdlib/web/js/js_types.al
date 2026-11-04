# ALEX STANDARD LIBRARY — web.js.js_types
#
# Types et lexique de JavaScript : mots réservés, identifiants valides, chaînes littérales (guillemets,
# échappements, ASCII seul), nombres (NaN, Infinity, entiers sûrs), clés de propriétés, valeur undefined,
# correspondance typeof des valeurs ALEX.
#
#   use web.js.js_types as jt
#   jt.is_identifier("$el"), jt.is_identifier("class")     # true false
#   jt.quote("L'été \"chaud\"\n")                          # "L'été \"chaud\"\n"
#   jt.quote("x", "'")                                     # 'x'
#   jt.quote("é", "\"", true)                              # "é"
#   jt.number(1.0), jt.number(0.1), jt.number(1/0)         # 1 0.1 Infinity
#   jt.property_key("data-x"), jt.property_key("nom")      # "data-x" nom
#   jt.typeof(jt.UNDEFINED), jt.typeof([1]), jt.typeof(null)   # undefined object object
#   jt.safe_identifier("2e classe")                        # _2e_classe
#
# Erreurs : JsValueError (identifiant impossible à former).

from core use len, type, to_int
from collections use append
use string as _s
use web.js.js_errors as _err

const KEYWORDS := ["break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "export", "extends", "false", "finally", "for", "function", "if", "import", "in", "instanceof", "new", "null", "return", "super", "switch", "this", "throw", "true", "try", "typeof", "var", "void", "while", "with"]
const STRICT_RESERVED := ["enum", "implements", "interface", "let", "package", "private", "protected", "public", "static", "yield", "await"]
const CONTEXTUAL := ["as", "async", "from", "get", "of", "set", "target", "meta", "accessor"]
const GLOBALS := ["undefined", "NaN", "Infinity", "globalThis", "window", "document", "console", "Object", "Array", "String", "Number", "Boolean", "Symbol", "BigInt", "Math", "JSON", "Date", "RegExp", "Error", "Promise", "Map", "Set", "WeakMap", "WeakSet", "Proxy", "Reflect", "Intl", "fetch", "setTimeout", "setInterval", "clearTimeout", "clearInterval", "queueMicrotask", "structuredClone", "eval", "isNaN", "isFinite", "parseInt", "parseFloat", "encodeURIComponent", "decodeURIComponent", "encodeURI", "decodeURI", "atob", "btoa"]

# Valeur undefined de JavaScript (distincte de null) ; une seule instance : UNDEFINED.
class Undefined:
    func init():
        self.kind = "undefined"

    func __str__():
        return "undefined"

    func __eq__(other):
        return isinstance(other, Undefined)

const UNDEFINED := Undefined()

func is_undefined(v):
    return isinstance(v, Undefined)

func is_reserved(word, strict=true):
    if word in KEYWORDS:
        return true
    return strict and word in STRICT_RESERVED

func _start_char(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '$' or c == '_' or _s.ord(c) >= 128

func _part_char(c):
    return _start_char(c) or (c >= '0' and c <= '9') or _s.ord(c) == 0x200C or _s.ord(c) == 0x200D

# Nom d'identifiant (IdentifierName : les mots réservés sont permis, ex. comme nom de propriété).
func is_identifier_name(text):
    if type(text) != "str" or len(text) == 0:
        return false
    if not _start_char(text[0]):
        return false
    for c in text:
        if not _part_char(c):
            return false
    return true

# Identifiant utilisable comme nom de variable (pas un mot réservé).
func is_identifier(text, strict=true):
    return is_identifier_name(text) and not is_reserved(text, strict)

# Identifiant valide dérivé d'un texte quelconque (caractères invalides -> « _ », préfixe si nécessaire).
func safe_identifier(text):
    out := []
    for c in str(text):
        append(out, str(c) if _part_char(c) else "_")
    t := _s.join("", out)
    if t == "":
        _err.value_error("js_types.safe_identifier", "identifiant vide")
    if not _start_char(t[0]):
        t = "_" + t
    if is_reserved(t):
        t = t + "_"
    return t

func _hex(n, width):
    digits := "0123456789abcdef"
    out := []
    v := n
    while v > 0:
        append(out, str(digits[v % 16]))
        v = v / 16
        v = to_int(v)
    while len(out) < width:
        append(out, "0")
    r := []
    i := len(out) - 1
    while i >= 0:
        append(r, out[i])
        i -= 1
    return _s.join("", r)

func _u(code):
    if code > 0xFFFF:
        v := code - 0x10000
        hi := 0xD800 + to_int(v / 0x400)
        lo := 0xDC00 + v % 0x400
        return "\\u" + _hex(hi, 4) + "\\u" + _hex(lo, 4)
    return "\\u" + _hex(code, 4)

# Littéral de chaîne JavaScript ; q : " ' ou ` ; ascii : non-ASCII en \uXXXX ; script_safe : « </ » échappé.
func quote(text, q="\"", ascii=false, script_safe=false):
    t := str(text)
    out := [q]
    n := len(t)
    i := 0
    while i < n:
        c := t[i]
        o := _s.ord(c)
        if c == '\\':
            append(out, "\\\\")
        elif str(c) == q:
            append(out, "\\" + q)
        elif q == "`" and c == '$' and i + 1 < n and t[i + 1] == '{':
            append(out, "\\$")
        elif c == '\n':
            append(out, "\\n")
        elif c == '\r':
            append(out, "\\r")
        elif c == '\t':
            append(out, "\\t")
        elif o == 8:
            append(out, "\\b")
        elif o == 12:
            append(out, "\\f")
        elif o == 11:
            append(out, "\\v")
        elif o < 32 or o == 127:
            append(out, "\\x" + _hex(o, 2))
        elif o == 0x2028 or o == 0x2029:
            append(out, _u(o))
        elif ascii and o > 126:
            append(out, _u(o))
        elif script_safe and c == '<' and i + 1 < n and (t[i + 1] == '/' or t[i + 1] == '!'):
            append(out, "<\\")
        else:
            append(out, str(c))
        i += 1
    append(out, q)
    return _s.join("", out)

# Guillemets choisis pour minimiser les échappements (" par défaut).
func quote_best(text, ascii=false):
    t := str(text)
    dq := 0
    sq := 0
    for c in t:
        if c == '"':
            dq += 1
        elif c == '\'':
            sq += 1
    return quote(t, "'" if dq > sq else "\"", ascii)

const MAX_SAFE_INTEGER := 9007199254740991

func is_nan(x):
    return type(x) == "float" and x != x

func is_infinite(x):
    return type(x) == "float" and (x > 1.7976931348623157e308 or x < -1.7976931348623157e308)

# Littéral numérique JavaScript (bool refusé ; NaN et Infinity gérés ; 1.0 -> 1).
func number(x):
    if type(x) == "int":
        return str(x)
    if type(x) != "float":
        _err.value_error("js_types.number", "nombre attendu, reçu " + type(x))
    if x != x:
        return "NaN"
    if x > 1.7976931348623157e308:
        return "Infinity"
    if x < -1.7976931348623157e308:
        return "-Infinity"
    if x == 0.0:
        return "0"
    t := str(x)
    if _s.ends_with(t, ".0"):
        t = t[0:len(t) - 2]
    if _s.contains(t, "e+"):
        t = _s.replace(t, "e+", "e")
    return t

func is_canonical_index(text):
    if text == "0":
        return true
    if len(text) == 0 or text[0] == '0':
        return false
    for c in text:
        if c < '0' or c > '9':
            return false
    return len(text) < 16

# Clé de propriété d'un littéral objet : identifiant tel quel, index entier tel quel, sinon chaîne.
func property_key(name, ascii=false):
    if type(name) == "int":
        return str(name)
    t := str(name)
    if is_identifier_name(t) or is_canonical_index(t):
        return t
    return quote(t, "\"", ascii)

# Accès à une propriété : « .nom » si possible, sinon « ["nom"] ».
func property_access(name):
    t := str(name)
    if type(name) == "int":
        return "[" + t + "]"
    if is_identifier_name(t):
        return "." + t
    return "[" + quote(t) + "]"

# typeof JavaScript d'une valeur ALEX convertie.
func typeof(v):
    if is_undefined(v):
        return "undefined"
    t := type(v)
    if t == "bool":
        return "boolean"
    if t == "int" or t == "float":
        return "number"
    if t == "str":
        return "string"
    if t == "function":
        return "function"
    return "object"

# Nom du type JavaScript équivalent (Array, Object, Map...) pour les messages.
func js_type_name(v):
    if v == null:
        return "null"
    if is_undefined(v):
        return "undefined"
    t := type(v)
    if t == "list" or t == "tuple":
        return "Array"
    if t == "dict":
        return "Object"
    if t == "bool":
        return "Boolean"
    if t == "int" or t == "float":
        return "Number"
    if t == "str":
        return "String"
    return t

# Vraisemblance JavaScript (truthy) d'une valeur ALEX.
func truthy(v):
    if v == null or is_undefined(v) or v == false:
        return false
    t := type(v)
    if (t == "int" or t == "float") and (v == 0 or v != v):
        return false
    if t == "str" and v == "":
        return false
    return true

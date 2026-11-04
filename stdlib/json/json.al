# ALEX STANDARD LIBRARY — json
# Analyse et sérialisation JSON (RFC 8259) en ALEX pur. Aucune dépendance native (hors io pour load/save).
#
#   use json
#   v := json.parse("{\"nom\": \"Alex\", \"tags\": [1, 2.5, true, null]}")
#   print(v["nom"], v["tags"][1])            # Alex 2.5
#   print(json.stringify(v))                 # {"nom":"Alex","tags":[1,2.5,true,null]}
#   print(json.pretty(v))                    # indenté de 2 espaces
#
# CORRESPONDANCE DES TYPES
#   null <-> null   true/false <-> bool   entier <-> int   nombre à fraction/exposant <-> float
#   chaîne <-> str  tableau <-> list (un tuple est sérialisé comme tableau)   objet <-> dict
#
# ERREURS
#   Toute erreur lève raise("JSONError", message). Pour parse, le message contient « ligne L, colonne C ».
#   stringify refuse : clés de dict non str, nan/inf, valeurs non JSON (fonction, instance...), profondeur > 100 niveaux
#   (ce qui détecte aussi les structures cycliques). Les caractères de contrôle sont échappés : \n \t \r \b \f ou \u00XX.
#
# LIMITES CONNUES
#   - \uXXXX est décodé pour tout le plan Unicode (string.chr), paires de substitution UTF-16 (\uD83D\uDE00) comprises ;
#     une moitié de paire isolée lève JSONError.
#   - str(float) du runtime ne garantit pas l'aller-retour exact (15 chiffres significatifs).
#   - Les dicts itèrent dans l'ordre d'insertion ; stringify trie les clés par défaut (sort_keys=true), sort_keys=false garde cet ordre.

from core use len, type, to_int, to_float
from collections use append, keys
use string
use io
use _native_string as _ns

const MAX_DEPTH := 100

const _DIGITS := "0123456789"
const _HEX := "0123456789abcdef"

# --- utilitaires -------------------------------------------------------------------------------------------

func _fail(message):
    raise("JSONError", message)

func _is_digit(ch):
    return ch != null and string.contains(_DIGITS, ch)

# Valeur hexadécimale d'un caractère (0..15), ou -1.
func _hex_value(ch):
    if ch == null:
        return -1
    return string.find(_HEX, string.lower(ch))

# Caractère (str) de code point `code` ; lève JSONError si le code n'est pas un point de code valide.
func _chr(code):
    if code < 0 or code > 1114111 or (code >= 55296 and code <= 57343):
        _fail("séquence \\u" + _hex4(code) + " : point de code invalide")
    return str(string.chr(code))

func _hex4(code):
    out := ""
    n := 4
    while n > 0:
        n = n - 1
        d := (code // (16 ** n)) % 16
        out = out + str(_HEX[d])
    return out

# Tri fusion de chaînes (clés d'objet) : O(n log n), renvoie une nouvelle liste.
func _sorted(items):
    n := len(items)
    if n < 2:
        return items
    mid := n // 2
    left := []
    right := []
    i := 0
    while i < n:
        if i < mid:
            append(left, items[i])
        else:
            append(right, items[i])
        i = i + 1
    left = _sorted(left)
    right = _sorted(right)
    out := []
    a := 0
    b := 0
    while a < len(left) and b < len(right):
        if right[b] < left[a]:
            append(out, right[b])
            b = b + 1
        else:
            append(out, left[a])
            a = a + 1
    while a < len(left):
        append(out, left[a])
        a = a + 1
    while b < len(right):
        append(out, right[b])
        b = b + 1
    return out

# --- analyse -----------------------------------------------------------------------------------------------

class _Parser:
    func init(text):
        self.chars = []
        for c in text:
            append(self.chars, str(c))
        self.n = len(self.chars)
        self.pos = 0

    # Caractère courant, ou null en fin de texte.
    func peek():
        if self.pos < self.n:
            return self.chars[self.pos]
        return null

    func error(message):
        line := 1
        col := 1
        i := 0
        while i < self.pos and i < self.n:
            if self.chars[i] == "\n":
                line = line + 1
                col = 1
            else:
                col = col + 1
            i = i + 1
        _fail(message + " (ligne " + str(line) + ", colonne " + str(col) + ")")

    func skip_ws():
        while self.pos < self.n:
            ch := self.chars[self.pos]
            if ch == " " or ch == "\n" or ch == "\t" or ch == "\r":
                self.pos = self.pos + 1
            else:
                return null
        return null

    func expect_word(word, value):
        i := 0
        n := len(word)
        while i < n:
            if self.peek() != str(word[i]):
                self.error("valeur inattendue, '" + word + "' attendu")
            self.pos = self.pos + 1
            i = i + 1
        return value

    func parse_value(depth):
        if depth >= MAX_DEPTH:
            self.error("profondeur maximale (" + str(MAX_DEPTH) + ") dépassée")
        self.skip_ws()
        ch := self.peek()
        if ch == null:
            self.error("fin de texte inattendue")
        if ch == "{":
            return self.parse_object(depth)
        if ch == "[":
            return self.parse_array(depth)
        if ch == "\"":
            return self.parse_string()
        if ch == "t":
            return self.expect_word("true", true)
        if ch == "f":
            return self.expect_word("false", false)
        if ch == "n":
            return self.expect_word("null", null)
        if ch == "-" or _is_digit(ch):
            return self.parse_number()
        self.error("caractère inattendu '" + ch + "'")

    func parse_object(depth):
        result := {}
        self.pos = self.pos + 1
        self.skip_ws()
        if self.peek() == "}":
            self.pos = self.pos + 1
            return result
        while true:
            self.skip_ws()
            if self.peek() != "\"":
                self.error("clé de chaîne attendue")
            key := self.parse_string()
            self.skip_ws()
            if self.peek() != ":":
                self.error("':' attendu après la clé")
            self.pos = self.pos + 1
            result[key] = self.parse_value(depth + 1)
            self.skip_ws()
            ch := self.peek()
            self.pos = self.pos + 1
            if ch == "}":
                return result
            if ch != ",":
                self.pos = self.pos - 1
                self.error("',' ou '}' attendu")

    func parse_array(depth):
        result := []
        self.pos = self.pos + 1
        self.skip_ws()
        if self.peek() == "]":
            self.pos = self.pos + 1
            return result
        while true:
            append(result, self.parse_value(depth + 1))
            self.skip_ws()
            ch := self.peek()
            self.pos = self.pos + 1
            if ch == "]":
                return result
            if ch != ",":
                self.pos = self.pos - 1
                self.error("',' ou ']' attendu")

    func parse_string():
        self.pos = self.pos + 1
        parts := []
        while true:
            ch := self.peek()
            if ch == null:
                self.error("chaîne non terminée")
            self.pos = self.pos + 1
            if ch == "\"":
                return string.join("", parts)
            if ch == "\\":
                append(parts, self.parse_escape())
            else:
                if ch < " ":
                    self.pos = self.pos - 1
                    self.error("caractère de contrôle interdit dans une chaîne")
                append(parts, ch)

    func parse_escape():
        e := self.peek()
        if e == null:
            self.error("échappement incomplet")
        self.pos = self.pos + 1
        if e == "\"" or e == "\\" or e == "/":
            return e
        if e == "n":
            return "\n"
        if e == "t":
            return "\t"
        if e == "r":
            return "\r"
        if e == "b":
            return _chr(8)
        if e == "f":
            return _chr(12)
        if e == "u":
            code := self.read_hex4()
            if code >= 56320 and code <= 57343:
                self.error("moitié basse de paire de substitution sans moitié haute")
            if code >= 55296 and code <= 56319:
                if self.peek() != "\\" or self.peek_at(1) != "u":
                    self.error("moitié haute de paire de substitution sans moitié basse")
                self.pos = self.pos + 2
                low := self.read_hex4()
                if low < 56320 or low > 57343:
                    self.error("paire de substitution invalide")
                code = 65536 + (code - 55296) * 1024 + (low - 56320)
            return _chr(code)
        self.pos = self.pos - 1
        self.error("échappement invalide '\\" + e + "'")

    func peek_at(k):
        i := self.pos + k
        if i >= len(self.chars):
            return null
        return self.chars[i]

    # Lit 4 chiffres hexadécimaux à la position courante.
    func read_hex4():
        code := 0
        k := 0
        while k < 4:
            h := _hex_value(self.peek())
            if h < 0:
                self.error("4 chiffres hexadécimaux attendus après \\u")
            code = code * 16 + h
            self.pos = self.pos + 1
            k = k + 1
        return code

    func parse_number():
        start := self.pos
        is_float := false
        if self.peek() == "-":
            self.pos = self.pos + 1
        ch := self.peek()
        if not _is_digit(ch):
            self.error("chiffre attendu")
        if ch == "0":
            self.pos = self.pos + 1
            if _is_digit(self.peek()):
                self.error("zéro initial interdit")
        else:
            while _is_digit(self.peek()):
                self.pos = self.pos + 1
        if self.peek() == ".":
            is_float = true
            self.pos = self.pos + 1
            if not _is_digit(self.peek()):
                self.error("chiffre attendu après '.'")
            while _is_digit(self.peek()):
                self.pos = self.pos + 1
        mant_end := self.pos
        exp := 0
        ch = self.peek()
        if ch == "e" or ch == "E":
            is_float = true
            self.pos = self.pos + 1
            sign := 1
            ch = self.peek()
            if ch == "+" or ch == "-":
                if ch == "-":
                    sign = -1
                self.pos = self.pos + 1
            if not _is_digit(self.peek()):
                self.error("chiffre attendu dans l'exposant")
            while _is_digit(self.peek()):
                exp = exp * 10 + to_int(self.peek())
                self.pos = self.pos + 1
            exp = exp * sign
        mant := self.slice(start, mant_end)
        if not is_float:
            return to_int(mant)
        value := to_float(mant)
        if exp > 0:
            value = value * (10.0 ** exp)
        elif exp < 0:
            value = value / (10.0 ** (0 - exp))
        if value - value != 0.0:
            self.error("nombre hors limites")
        return value

    func slice(a, b):
        out := []
        i := a
        while i < b:
            append(out, self.chars[i])
            i = i + 1
        return string.join("", out)

# Convertit un texte JSON en valeur ALEX. Lève JSONError si le texte est invalide.
func parse(text):
    if type(text) != "str":
        _fail("parse : chaîne attendue")
    # analyse native rapide ; en cas d'erreur, l'analyseur ALEX ci-dessous produit le message détaillé
    try:
        return _ns.json_parse(text)
    catch e:
        if e.type != "ArgumentError":
            raise(e)
    p := _Parser(text)
    v := p.parse_value(0)
    p.skip_ws()
    if p.peek() != null:
        p.error("texte superflu après la valeur")
    return v

# Vrai si `text` est un JSON valide.
func is_valid(text):
    try:
        parse(text)
    catch e:
        return false
    return true

# --- sérialisation -----------------------------------------------------------------------------------------

func _quote(s):
    return _ns.json_quote(s)

func _quote_alex(s):
    parts := ["\""]
    for c in s:
        ch := str(c)
        if ch == "\"":
            append(parts, "\\\"")
        elif ch == "\\":
            append(parts, "\\\\")
        elif ch == "\n":
            append(parts, "\\n")
        elif ch == "\t":
            append(parts, "\\t")
        elif ch == "\r":
            append(parts, "\\r")
        elif string.ord(c) == 8:
            append(parts, "\\b")
        elif string.ord(c) == 12:
            append(parts, "\\f")
        elif string.ord(c) < 32:
            append(parts, "\\u" + _hex4(string.ord(c)))
        else:
            append(parts, ch)
    append(parts, "\"")
    return string.join("", parts)

func _newline(indent, level):
    return "\n" + string.repeat(" ", indent * level)

func _write(v, indent, level, sort_keys):
    if level >= MAX_DEPTH:
        _fail("stringify : profondeur maximale (" + str(MAX_DEPTH) + ") dépassée (structure cyclique ?)")
    t := type(v)
    if t == "null":
        return "null"
    if t == "bool":
        if v:
            return "true"
        return "false"
    if t == "int":
        return str(v)
    if t == "float":
        if v - v != 0.0:
            _fail("stringify : nan et inf ne sont pas représentables en JSON")
        return str(v)
    if t == "str":
        return _quote(v)
    if t == "list" or t == "tuple":
        if len(v) == 0:
            return "[]"
        items := []
        for x in v:
            append(items, _write(x, indent, level + 1, sort_keys))
        if indent == null:
            return "[" + string.join(",", items) + "]"
        pad := _newline(indent, level + 1)
        return "[" + pad + string.join("," + pad, items) + _newline(indent, level) + "]"
    if t == "dict":
        ks := keys(v)
        if len(ks) == 0:
            return "{}"
        for k in ks:
            if type(k) != "str":
                _fail("stringify : les clés d'objet doivent être des str (reçu " + type(k) + ")")
        if sort_keys:
            ks = _sorted(ks)
        items := []
        sep := ":"
        if indent != null:
            sep = ": "
        for k in ks:
            append(items, _quote(k) + sep + _write(v[k], indent, level + 1, sort_keys))
        if indent == null:
            return "{" + string.join(",", items) + "}"
        pad := _newline(indent, level + 1)
        return "{" + pad + string.join("," + pad, items) + _newline(indent, level) + "}"
    _fail("stringify : type non sérialisable : " + t)

# Texte JSON de `value`. indent=null : compact ; indent=n : n espaces par niveau. sort_keys : clés triées.
func stringify(value, indent=null, sort_keys=true) -> str:
    if indent != null and (type(indent) != "int" or indent < 0):
        _fail("stringify : indent doit être un entier >= 0 ou null")
    return _write(value, indent, 0, sort_keys)

# Raccourci : stringify avec indentation (2 espaces par défaut).
func pretty(value, indent=2) -> str:
    return stringify(value, indent)

# Lit et analyse un fichier JSON.
func load(path):
    return parse(io.read_file(path))

# Écrit `value` dans un fichier JSON (indenté, terminé par une fin de ligne).
func save(path, value, indent=2):
    io.write_file(path, stringify(value, indent) + "\n")

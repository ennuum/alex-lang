# ALEX STANDARD LIBRARY — web.js.js_value
#
# Valeurs ALEX <-> littéraux JavaScript. to_js produit du JavaScript valide (clés sans guillemets quand c'est
# possible, undefined, NaN, Infinity, code brut Raw, objets dotés de to_js()) ; from_js lit un littéral
# JavaScript TOLÉRANT (commentaires, clés sans guillemets, chaînes '…' et `…`, virgules finales, nombres
# hexadécimaux / octaux / binaires / avec « _ », Infinity, NaN, undefined), au-delà de JSON.
#
#   use web.js.js_value as jv
#   jv.to_js({"nom": "Ada", "data-x": [1, 2.5, true, null]})    # {nom: "Ada", "data-x": [1, 2.5, true, null]}
#   jv.to_js({"a": {"b": 1}}, "  ")                             # indenté
#   jv.to_js(jv.Raw("() => 42"))                               # () => 42
#   jv.from_js("{ nom: 'Ada', // commentaire\n  âge: 0x24, tags: [`a`, 'b',], }")   # {"nom": "Ada", "âge": 36, ...}
#   jv.from_js("[1_000, .5, -Infinity, undefined]")             # [1000, 0.5, -inf, null]
#   jv.to_json_compatible(valeur)                               # undefined retiré, NaN -> null (comme JSON.stringify)
#
# Erreurs : JsValueError (valeur non convertible), JsSyntaxError (littéral mal formé, avec ligne et colonne).

from core use len, type, to_int, to_float
from collections use append, keys
use string as _s
use web.js.js_errors as _err
use web.js.js_types as _t

# Code JavaScript inséré tel quel par to_js.
class Raw:
    func init(code):
        self.code = str(code)

    func to_js(indent=null, level=0):
        return self.code

    func __str__():
        return self.code

func raw(code):
    return Raw(code)

func _has_to_js(v):
    try:
        f := v.to_js
        return true
    catch e:
        return false

func _is_container(v):
    t := type(v)
    return t == "list" or t == "tuple" or t == "dict"

# Littéral JavaScript d'une valeur ALEX ; indent : null (une ligne) ou texte d'indentation ; ascii : non-ASCII
# échappé ; sort_keys : clés triées ; script_safe : « </ » échappé dans les chaînes (code inclus dans <script>).
func to_js(v, indent=null, ascii=false, sort_keys=false, script_safe=false):
    return _js(v, indent, 0, ascii, sort_keys, script_safe, [])

func _js(v, indent, level, ascii, sort_keys, script_safe, stack):
    if v == null:
        return "null"
    t := type(v)
    if t == "bool":
        return "true" if v else "false"
    if t == "int" or t == "float":
        return _t.number(v)
    if t == "str":
        return _t.quote(v, "\"", ascii, script_safe)
    if _t.is_undefined(v):
        return "undefined"
    if t == "list" or t == "tuple":
        if len(v) == 0:
            return "[]"
        items := []
        for x in v:
            append(items, _js(x, indent, level + 1, ascii, sort_keys, script_safe, stack))
        return _wrap("[", "]", items, indent, level)
    if t == "dict":
        ks := keys(v)
        if sort_keys:
            ks = _sorted(ks)
        if len(ks) == 0:
            return "{}"
        items := []
        for k in ks:
            if type(k) != "str" and type(k) != "int":
                _err.value_error("js_value.to_js", "clé d'objet non convertible : " + type(k))
            append(items, _t.property_key(k, ascii) + ": " + _js(v[k], indent, level + 1, ascii, sort_keys, script_safe, stack))
        return _wrap("{", "}", items, indent, level)
    if t == "function":
        _err.value_error("js_value.to_js", "une fonction ALEX n'est pas convertible (utiliser Raw)")
    if _has_to_js(v):
        return v.to_js(indent, level)
    _err.value_error("js_value.to_js", "valeur non convertible de type " + t)

func _wrap(open, close, items, indent, level):
    if indent == null:
        return open + _s.join(", ", items) + close
    pad := _s.repeat(indent, level + 1)
    end := _s.repeat(indent, level)
    return open + "\n" + pad + _s.join(",\n" + pad, items) + "\n" + end + close

func _sorted(ks):
    out := []
    for k in ks:
        append(out, k)
    i := 1
    while i < len(out):
        cur := out[i]
        j := i - 1
        while j >= 0 and str(out[j]) > str(cur):
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = cur
        i += 1
    return out

# Copie compatible JSON.stringify : undefined retiré des objets (null dans les tableaux), NaN/Infinity -> null.
func to_json_compatible(v):
    if _t.is_undefined(v):
        return null
    t := type(v)
    if t == "float" and (_t.is_nan(v) or _t.is_infinite(v)):
        return null
    if t == "list" or t == "tuple":
        out := []
        for x in v:
            append(out, to_json_compatible(x))
        return out
    if t == "dict":
        out := {}
        for k in keys(v):
            if not _t.is_undefined(v[k]):
                out[str(k)] = to_json_compatible(v[k])
        return out
    return v

# ---------------------------------------------------------------- lecture tolérante

class _Reader:
    func init(text, undefined_as_null):
        self.t = str(text)
        self.n = len(self.t)
        self.i = 0
        self.undef_null = undefined_as_null

    func fail(msg):
        line := 1
        col := 1
        k := 0
        while k < self.i and k < self.n:
            if self.t[k] == '\n':
                line += 1
                col = 1
            else:
                col += 1
            k += 1
        _err.syntax_error("js_value.from_js", msg, line, col)

    func skip():
        while self.i < self.n:
            c := self.t[self.i]
            o := _s.ord(c)
            if c == ' ' or c == '\t' or c == '\n' or c == '\r' or o == 0xFEFF or o == 0xA0 or o == 0x2028 or o == 0x2029 or o == 11 or o == 12:
                self.i += 1
            elif c == '/' and self.i + 1 < self.n and self.t[self.i + 1] == '/':
                while self.i < self.n and self.t[self.i] != '\n':
                    self.i += 1
            elif c == '/' and self.i + 1 < self.n and self.t[self.i + 1] == '*':
                j := _s.find(self.t[self.i + 2:self.n], "*/")
                if j < 0:
                    self.fail("commentaire non fermé")
                self.i = self.i + 2 + j + 2
            else:
                return

    func peek():
        if self.i < self.n:
            return self.t[self.i]
        return null

    func value():
        self.skip()
        c := self.peek()
        if c == null:
            self.fail("valeur attendue, fin du texte")
        if c == '{':
            return self.object()
        if c == '[':
            return self.array()
        if c == '"' or c == '\'' or c == '`':
            return self.string()
        if c == '-' or c == '+' or c == '.' or (c >= '0' and c <= '9'):
            return self.number()
        if _t._start_char(c):
            w := self.word()
            if w == "true":
                return true
            if w == "false":
                return false
            if w == "null":
                return null
            if w == "undefined":
                return null if self.undef_null else _t.UNDEFINED
            if w == "Infinity":
                return 1e308 * 10.0
            if w == "NaN":
                return (1e308 * 10.0) - (1e308 * 10.0)
            self.fail("mot inattendu « " + w + " »")
        self.fail("caractère inattendu « " + str(c) + " »")

    func word():
        j := self.i
        while j < self.n and _t._part_char(self.t[j]):
            j += 1
        w := self.t[self.i:j]
        self.i = j
        return w

    func object():
        self.i += 1
        out := {}
        while true:
            self.skip()
            c := self.peek()
            if c == null:
                self.fail("objet non fermé")
            if c == '}':
                self.i += 1
                return out
            key := null
            if c == '"' or c == '\'' or c == '`':
                key = self.string()
            elif c >= '0' and c <= '9':
                key = _t.number(self.number())
            elif c == '[':
                self.fail("clé calculée non prise en charge")
            elif _t._start_char(c) or c == '\\':
                key = self.word()
                if key == "":
                    self.fail("clé invalide")
            else:
                self.fail("clé attendue, trouvé « " + str(c) + " »")
            self.skip()
            if self.peek() != ':':
                self.fail("« : » attendu après la clé « " + key + " »")
            self.i += 1
            out[key] = self.value()
            self.skip()
            c = self.peek()
            if c == ',':
                self.i += 1
            elif c != '}':
                self.fail("« , » ou « } » attendu")

    func array():
        self.i += 1
        out := []
        while true:
            self.skip()
            c := self.peek()
            if c == null:
                self.fail("tableau non fermé")
            if c == ']':
                self.i += 1
                return out
            if c == ',':
                # trou : [1,,2]
                append(out, null)
                self.i += 1
                continue
            append(out, self.value())
            self.skip()
            c = self.peek()
            if c == ',':
                self.i += 1
            elif c != ']':
                self.fail("« , » ou « ] » attendu")

    func string():
        q := self.t[self.i]
        self.i += 1
        out := []
        while true:
            if self.i >= self.n:
                self.fail("chaîne non terminée")
            c := self.t[self.i]
            if c == q:
                self.i += 1
                return _s.join("", out)
            if q == '`' and c == '$' and self.i + 1 < self.n and self.t[self.i + 1] == '{':
                self.fail("gabarit avec ${…} non pris en charge dans une valeur littérale")
            if (c == '\n' or c == '\r') and q != '`':
                self.fail("saut de ligne dans une chaîne")
            if c == '\\':
                self.i += 1
                if self.i >= self.n:
                    self.fail("échappement incomplet")
                e := self.t[self.i]
                self.i += 1
                if e == 'n':
                    append(out, "\n")
                elif e == 't':
                    append(out, "\t")
                elif e == 'r':
                    append(out, "\r")
                elif e == 'b':
                    append(out, str(_s.chr(8)))
                elif e == 'f':
                    append(out, str(_s.chr(12)))
                elif e == 'v':
                    append(out, str(_s.chr(11)))
                elif e == '0' and not (self.i < self.n and self.t[self.i] >= '0' and self.t[self.i] <= '9'):
                    append(out, str(_s.chr(0)))
                elif e == 'x':
                    append(out, str(_s.chr(self.hex(2))))
                elif e == 'u':
                    code := 0
                    if self.peek() == '{':
                        self.i += 1
                        j := _s.find(self.t[self.i:self.n], "}")
                        if j < 0:
                            self.fail("\\u{…} non fermé")
                        code = _hexnum(self.t[self.i:self.i + j], self)
                        self.i = self.i + j + 1
                    else:
                        code = self.hex(4)
                        if code >= 0xD800 and code <= 0xDBFF and self.i + 1 < self.n and self.t[self.i] == '\\' and self.t[self.i + 1] == 'u':
                            save := self.i
                            self.i += 2
                            lo := self.hex(4)
                            if lo >= 0xDC00 and lo <= 0xDFFF:
                                code = 0x10000 + (code - 0xD800) * 0x400 + (lo - 0xDC00)
                            else:
                                self.i = save
                    append(out, str(_s.chr(code)))
                elif e == '\r':
                    if self.peek() == '\n':
                        self.i += 1
                elif e == '\n':
                    pass
                else:
                    append(out, str(e))
                continue
            append(out, str(c))
            self.i += 1

    func hex(count):
        if self.i + count > self.n:
            self.fail("échappement hexadécimal incomplet")
        v := _hexnum(self.t[self.i:self.i + count], self)
        self.i += count
        return v

    func number():
        start := self.i
        sign := 1
        c := self.peek()
        if c == '-' or c == '+':
            if c == '-':
                sign = -1
            self.i += 1
            self.skip()
            if self.t[self.i:self.i + 8] == "Infinity":
                self.i += 8
                return sign * (1e308 * 10.0)
        if self.peek() == '0' and self.i + 1 < self.n and (self.t[self.i + 1] in ['x', 'X', 'o', 'O', 'b', 'B']):
            base := 16
            k := _s.lower(str(self.t[self.i + 1]))
            if k == "o":
                base = 8
            elif k == "b":
                base = 2
            self.i += 2
            j := self.i
            while j < self.n and (_hexval(self.t[j]) >= 0 or self.t[j] == '_'):
                j += 1
            digits := _s.replace(self.t[self.i:j], "_", "")
            self.i = j
            if self.peek() == 'n':
                self.i += 1
            v := 0
            for d in digits:
                dv := _hexval(d)
                if dv < 0 or dv >= base:
                    self.fail("chiffre invalide en base " + str(base))
                v = v * base + dv
            return sign * v
        j := self.i
        while j < self.n and ((self.t[j] >= '0' and self.t[j] <= '9') or self.t[j] == '.' or self.t[j] == '_' or self.t[j] == 'e' or self.t[j] == 'E' or ((self.t[j] == '+' or self.t[j] == '-') and j > self.i and (self.t[j - 1] == 'e' or self.t[j - 1] == 'E'))):
            j += 1
        text := _s.replace(self.t[self.i:j], "_", "")
        self.i = j
        if self.peek() == 'n':
            self.i += 1
        if text == "" or text == ".":
            self.i = start
            self.fail("nombre invalide")
        try:
            if _s.contains(text, ".") or _s.contains(text, "e") or _s.contains(text, "E"):
                t2 := text
                if _s.starts_with(t2, "."):
                    t2 = "0" + t2
                if _s.ends_with(t2, "."):
                    t2 = t2 + "0"
                return sign * to_float(t2)
            return sign * to_int(text)
        catch e:
            self.i = start
            self.fail("nombre invalide « " + text + " »")

func _hexval(c):
    if c >= '0' and c <= '9':
        return _s.ord(c) - 48
    if c >= 'a' and c <= 'f':
        return _s.ord(c) - 87
    if c >= 'A' and c <= 'F':
        return _s.ord(c) - 55
    return -1

func _hexnum(text, reader):
    v := 0
    if len(text) == 0:
        reader.fail("échappement hexadécimal vide")
    for c in text:
        d := _hexval(c)
        if d < 0:
            reader.fail("chiffre hexadécimal invalide « " + str(c) + " »")
        v = v * 16 + d
    return v

# Valeur ALEX depuis un littéral JavaScript ; undefined_as_null : undefined -> null (sinon UNDEFINED).
func from_js(text, undefined_as_null=true):
    r := _Reader(text, undefined_as_null)
    v := r.value()
    r.skip()
    if r.peek() == ';':
        r.i += 1
        r.skip()
    if r.i < r.n:
        r.fail("texte en trop après la valeur")
    return v

func is_literal(text):
    try:
        from_js(text)
        return true
    catch e:
        return false

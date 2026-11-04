# ALEX STANDARD LIBRARY — web.css.value
#
# Valeurs CSS au niveau syntaxique (CSS Syntax Level 3) : découpage en jetons (identifiants, nombres, dimensions,
# pourcentages, chaînes, url(), #hash, fonctions, délimiteurs, blocs) et arbre de « valeurs composantes »
# (fonctions avec leurs arguments, blocs). C'est le socle de l'analyseur (css_parser), du minifieur et de l'analyse
# des valeurs de propriétés.
#
#   use web.css.value as v
#   toks := v.tokenize("margin: 0 auto !important")
#   val := v.parse("calc(100% - 2rem) url(\"a b.png\") #fff")
#   len(val.components)                 # 3 (espaces non comptés)
#   val.components[0].name              # calc
#   val.to_css()                        # calc(100% - 2rem) url("a b.png") #fff
#   v.parse("a, b , c").split_commas()  # 3 groupes
#   v.parse("red !important").important # true
#
# Erreurs : aucune : les erreurs de syntaxe deviennent des jetons bad-string / bad-url (comme un navigateur).

from core use len, type, to_int, to_float
from collections use append
use string as _s
use web.css.units as _units

const WHITESPACE := "whitespace"
const IDENT := "ident"
const FUNCTION := "function"
const AT := "at-keyword"
const HASH := "hash"
const STRING := "string"
const BAD_STRING := "bad-string"
const URL := "url"
const BAD_URL := "bad-url"
const DELIM := "delim"
const NUMBER := "number"
const PERCENTAGE := "percentage"
const DIMENSION := "dimension"
const CDO := "cdo"
const CDC := "cdc"
const COLON := "colon"
const SEMICOLON := "semicolon"
const COMMA := "comma"
const OPEN := "open"          # [ ( {
const CLOSE := "close"        # ] ) }
const COMMENT := "comment"

class Token:
    func init(kind, value="", unit="", line=1, is_id=false):
        self.kind = kind
        self.value = value
        self.unit = unit
        self.line = line
        self.is_id = is_id          # hash : identifiant valide (sélecteur #id)

    func to_css(compact=false):
        k := self.kind
        if k == WHITESPACE:
            return " "
        if k == IDENT:
            return escape_ident(self.value)
        if k == FUNCTION:
            return escape_ident(self.value) + "("
        if k == AT:
            return "@" + escape_ident(self.value)
        if k == HASH:
            return "#" + self.value
        if k == STRING or k == BAD_STRING:
            return quote(self.value)
        if k == URL or k == BAD_URL:
            return "url(" + _url_text(self.value) + ")"
        if k == NUMBER:
            return _units.format_number(self.value)
        if k == PERCENTAGE:
            return _units.format_number(self.value) + "%"
        if k == DIMENSION:
            return _units.format_number(self.value) + self.unit
        if k == CDO:
            return "<!--"
        if k == CDC:
            return "-->"
        if k == COLON:
            return ":"
        if k == SEMICOLON:
            return ";"
        if k == COMMA:
            return ","
        if k == COMMENT:
            return "/*" + self.value + "*/"
        return str(self.value)

    func is_ident(name=null):
        return self.kind == IDENT and (name == null or _s.lower(self.value) == _s.lower(name))

    func is_delim(c):
        return self.kind == DELIM and self.value == c

    func __str__():
        return self.to_css()

func _url_text(v):
    for c in v:
        if c == ' ' or c == '(' or c == ')' or c == '"' or c == '\'' or c == '\\':
            return quote(v)
    return v

# Chaîne CSS entre guillemets doubles.
func quote(text):
    out := []
    for c in str(text):
        if c == '"' or c == '\\':
            append(out, "\\" + str(c))
        elif c == '\n':
            append(out, "\\a ")
        else:
            append(out, str(c))
    return "\"" + _s.join("", out) + "\""

func _is_name_start(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or _s.ord(c) >= 128

func _is_name(c):
    return _is_name_start(c) or (c >= '0' and c <= '9') or c == '-'

# Identifiant échappé si nécessaire (« 2col » -> « \32 col »).
func escape_ident(name):
    out := []
    i := 0
    n := len(name)
    for c in name:
        if _is_name(c) and not (i == 0 and c >= '0' and c <= '9') and not (i == 1 and c >= '0' and c <= '9' and name[0] == '-'):
            append(out, str(c))
        elif i == 0 and c == '-' and n > 1:
            append(out, "-")
        else:
            o := _s.ord(c)
            if (c >= '0' and c <= '9'):
                append(out, "\\" + _hex(o) + " ")
            else:
                append(out, "\\" + str(c))
        i += 1
    return _s.join("", out)

func _hex(v):
    digits := "0123456789abcdef"
    out := ""
    x := v
    if x == 0:
        return "0"
    while x > 0:
        out = str(digits[x & 15]) + out
        x = x >> 4
    return out

func _is_ws(c):
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or _s.ord(c) == 12

func _is_digit(c):
    return c >= '0' and c <= '9'

func _hexval(c):
    o := _s.ord(c)
    if o >= 48 and o <= 57:
        return o - 48
    if o >= 97 and o <= 102:
        return o - 87
    if o >= 65 and o <= 70:
        return o - 55
    return -1

class _Lexer:
    func init(text, keep_comments=false):
        self.t = text
        self.n = len(text)
        self.i = 0
        self.line = 1
        self.keep_comments = keep_comments

    func peek(k=0):
        j := self.i + k
        if j < self.n:
            return self.t[j]
        return null

    # Séquence d'échappement à la position courante (après « \ ») -> caractère.
    func escape():
        c := self.peek()
        if c == null:
            return "�"
        h := _hexval(c)
        if h >= 0:
            v := 0
            k := 0
            while k < 6 and self.peek() != null and _hexval(self.peek()) >= 0:
                v = v * 16 + _hexval(self.peek())
                self.i += 1
                k += 1
            if self.peek() != null and _is_ws(self.peek()):
                self.i += 1
            if v == 0 or v > 1114111 or (v >= 55296 and v <= 57343):
                return "�"
            return str(_s.chr(v))
        self.i += 1
        return str(c)

    func valid_escape(k=0):
        return self.peek(k) == '\\' and self.peek(k + 1) != null and self.peek(k + 1) != '\n'

    func starts_ident(k=0):
        c := self.peek(k)
        if c == null:
            return false
        if c == '-':
            d := self.peek(k + 1)
            return d != null and (_is_name_start(d) or d == '-' or self.valid_escape(k + 1))
        if _is_name_start(c):
            return true
        return self.valid_escape(k)

    func starts_number(k=0):
        c := self.peek(k)
        if c == null:
            return false
        if c == '+' or c == '-':
            d := self.peek(k + 1)
            if d != null and _is_digit(d):
                return true
            return d == '.' and self.peek(k + 2) != null and _is_digit(self.peek(k + 2))
        if c == '.':
            return self.peek(k + 1) != null and _is_digit(self.peek(k + 1))
        return _is_digit(c)

    func name():
        out := []
        while self.i < self.n:
            c := self.t[self.i]
            if _is_name(c):
                append(out, str(c))
                self.i += 1
            elif self.valid_escape():
                self.i += 1
                append(out, self.escape())
            else:
                break
        return _s.join("", out)

    func number():
        start := self.i
        if self.peek() == '+' or self.peek() == '-':
            self.i += 1
        while self.peek() != null and _is_digit(self.peek()):
            self.i += 1
        is_int := true
        if self.peek() == '.' and self.peek(1) != null and _is_digit(self.peek(1)):
            is_int = false
            self.i += 1
            while self.peek() != null and _is_digit(self.peek()):
                self.i += 1
        if (self.peek() == 'e' or self.peek() == 'E') and (self.peek(1) != null and (_is_digit(self.peek(1)) or ((self.peek(1) == '+' or self.peek(1) == '-') and self.peek(2) != null and _is_digit(self.peek(2))))):
            is_int = false
            self.i += 2
            while self.peek() != null and _is_digit(self.peek()):
                self.i += 1
        text := self.t[start:self.i]
        if is_int:
            return to_int(text)
        return to_float(text)

    func string(q):
        out := []
        while self.i < self.n:
            c := self.t[self.i]
            if c == q:
                self.i += 1
                return Token(STRING, _s.join("", out), "", self.line)
            if c == '\n':
                return Token(BAD_STRING, _s.join("", out), "", self.line)
            if c == '\\':
                if self.peek(1) == null:
                    self.i += 1
                elif self.peek(1) == '\n':
                    self.i += 2
                    self.line += 1
                else:
                    self.i += 1
                    append(out, self.escape())
                continue
            append(out, str(c))
            self.i += 1
        return Token(STRING, _s.join("", out), "", self.line)

    func url():
        while self.peek() != null and _is_ws(self.peek()):
            self.i += 1
        out := []
        while self.i < self.n:
            c := self.t[self.i]
            if c == ')':
                self.i += 1
                return Token(URL, _s.join("", out), "", self.line)
            if _is_ws(c):
                while self.peek() != null and _is_ws(self.peek()):
                    self.i += 1
                if self.peek() == ')' or self.peek() == null:
                    if self.peek() == ')':
                        self.i += 1
                    return Token(URL, _s.join("", out), "", self.line)
                return self.bad_url(out)
            if c == '"' or c == '\'' or c == '(':
                return self.bad_url(out)
            if c == '\\':
                if self.valid_escape():
                    self.i += 1
                    append(out, self.escape())
                    continue
                return self.bad_url(out)
            append(out, str(c))
            self.i += 1
        return Token(URL, _s.join("", out), "", self.line)

    func bad_url(out):
        while self.i < self.n and self.t[self.i] != ')':
            if self.valid_escape():
                self.i += 1
                self.escape()
            else:
                self.i += 1
        if self.i < self.n:
            self.i += 1
        return Token(BAD_URL, _s.join("", out), "", self.line)

    func numeric():
        v := self.number()
        if self.starts_ident():
            return Token(DIMENSION, v, self.name(), self.line)
        if self.peek() == '%':
            self.i += 1
            return Token(PERCENTAGE, v, "%", self.line)
        return Token(NUMBER, v, "", self.line)

    func ident_like():
        nm := self.name()
        if self.peek() == '(':
            self.i += 1
            if _s.lower(nm) == "url":
                j := self.i
                while j < self.n and _is_ws(self.t[j]):
                    j += 1
                if j < self.n and (self.t[j] == '"' or self.t[j] == '\''):
                    return Token(FUNCTION, nm, "", self.line)
                return self.url()
            return Token(FUNCTION, nm, "", self.line)
        return Token(IDENT, nm, "", self.line)

    func next():
        if self.i >= self.n:
            return null
        c := self.t[self.i]
        if c == '/' and self.peek(1) == '*':
            end := _find(self.t, "*/", self.i + 2)
            stop := self.n if end < 0 else end + 2
            body := self.t[self.i + 2:(self.n if end < 0 else end)]
            for ch in body:
                if ch == '\n':
                    self.line += 1
            self.i = stop
            if self.keep_comments:
                return Token(COMMENT, body, "", self.line)
            return self.next()
        if _is_ws(c):
            while self.i < self.n and _is_ws(self.t[self.i]):
                if self.t[self.i] == '\n':
                    self.line += 1
                self.i += 1
            return Token(WHITESPACE, " ", "", self.line)
        if c == '"' or c == '\'':
            self.i += 1
            return self.string(c)
        if c == '#':
            if self.peek(1) != null and (_is_name(self.peek(1)) or self.valid_escape(1)):
                is_id := self.starts_ident(1)
                self.i += 1
                return Token(HASH, self.name(), "", self.line, is_id)
        if c == '(' or c == '[' or c == '{':
            self.i += 1
            return Token(OPEN, str(c), "", self.line)
        if c == ')' or c == ']' or c == '}':
            self.i += 1
            return Token(CLOSE, str(c), "", self.line)
        if c == ',':
            self.i += 1
            return Token(COMMA, ",", "", self.line)
        if c == ':':
            self.i += 1
            return Token(COLON, ":", "", self.line)
        if c == ';':
            self.i += 1
            return Token(SEMICOLON, ";", "", self.line)
        if self.starts_number():
            return self.numeric()
        if c == '<' and self.t[self.i:self.i + 4] == "<!--":
            self.i += 4
            return Token(CDO, "<!--", "", self.line)
        if c == '-' and self.t[self.i:self.i + 3] == "-->":
            self.i += 3
            return Token(CDC, "-->", "", self.line)
        if c == '@' and self.starts_ident(1):
            self.i += 1
            return Token(AT, self.name(), "", self.line)
        if self.starts_ident():
            return self.ident_like()
        if c == '\\':
            self.i += 1
            return Token(DELIM, "\\", "", self.line)
        self.i += 1
        return Token(DELIM, str(c), "", self.line)

func _find(text, sub, start):
    n := len(text)
    m := len(sub)
    i := start
    while i <= n - m:
        if text[i] == sub[0] and text[i:i + m] == sub:
            return i
        i += 1
    return -1

# Liste de Token d'un texte CSS (commentaires omis, sauf keep_comments).
func tokenize(text, keep_comments=false):
    lx := _Lexer(text, keep_comments)
    out := []
    while true:
        t := lx.next()
        if t == null:
            break
        if t.kind == WHITESPACE and len(out) > 0 and out[len(out) - 1].kind == WHITESPACE:
            continue
        append(out, t)
    return out

# ---------------------------------------------------------------- valeurs composantes

class Function:
    func init(name, args):
        self.kind = "function-value"
        self.name = name
        self.args = args          # liste de composantes (Token, Function, Block)

    func to_css(compact=false):
        return escape_ident(self.name) + "(" + serialize(self.args, compact) + ")"

    func lower_name():
        return _s.lower(self.name)

    # Arguments séparés par des virgules (liste de listes de composantes, espaces aux bords retirés).
    func arg_groups():
        return split_on_commas(self.args)

    func __str__():
        return self.to_css()

class Block:
    func init(open, items):
        self.kind = "block"
        self.open = open          # [ ( {
        self.items = items

    func close_char():
        if self.open == "[":
            return "]"
        if self.open == "(":
            return ")"
        return "}"

    func to_css(compact=false):
        return self.open + serialize(self.items, compact) + self.close_char()

    func __str__():
        return self.to_css()

# Composantes depuis une liste de jetons (fonctions et blocs imbriqués).
func components(tokens):
    st := [0]
    return _consume_list(tokens, st, null)

func _consume_list(tokens, st, closer):
    out := []
    while st[0] < len(tokens):
        t := tokens[st[0]]
        st[0] = st[0] + 1
        if t.kind == CLOSE:
            if closer != null and t.value == closer:
                return out
            append(out, t)
            continue
        if t.kind == FUNCTION:
            append(out, Function(t.value, _consume_list(tokens, st, ")")))
        elif t.kind == OPEN:
            close := "]" if t.value == "[" else (")" if t.value == "(" else "}")
            append(out, Block(t.value, _consume_list(tokens, st, close)))
        else:
            append(out, t)
    return out

# Texte CSS de composantes ; compact : espaces superflus retirés (autour des virgules, des fonctions).
func serialize(items, compact=false):
    out := []
    n := len(items)
    i := 0
    while i < n:
        it := items[i]
        if isinstance(it, Token) and it.kind == WHITESPACE:
            if compact:
                prev := items[i - 1] if i > 0 else null
                nxt := items[i + 1] if i + 1 < n else null
                if prev == null or nxt == null:
                    i += 1
                    continue
                if (isinstance(prev, Token) and (prev.kind == COMMA or prev.kind == COLON or prev.is_delim("/"))) or (isinstance(nxt, Token) and (nxt.kind == COMMA or nxt.is_delim("/") or nxt.kind == CLOSE)):
                    i += 1
                    continue
            append(out, " ")
        else:
            append(out, it.to_css(compact))
        i += 1
    return _s.join("", out)

func _strip_ws(items):
    a := 0
    b := len(items)
    while a < b and isinstance(items[a], Token) and items[a].kind == WHITESPACE:
        a += 1
    while b > a and isinstance(items[b - 1], Token) and items[b - 1].kind == WHITESPACE:
        b -= 1
    return items[a:b]

func split_on_commas(items):
    groups := []
    cur := []
    for it in items:
        if isinstance(it, Token) and it.kind == COMMA:
            append(groups, _strip_ws(cur))
            cur = []
        else:
            append(cur, it)
    append(groups, _strip_ws(cur))
    return groups

# Valeur de propriété analysée : composantes (sans espaces de bord), drapeau !important.
class Value:
    func init(items, important=false):
        self.items = items
        self.important = important
        self.components = []
        for it in items:
            if not (isinstance(it, Token) and it.kind == WHITESPACE):
                append(self.components, it)

    func to_css(compact=false):
        out := serialize(self.items, compact)
        if self.important:
            out = out + (" !important" if not compact else "!important")
        return out

    func __str__():
        return self.to_css()

    func split_commas():
        return split_on_commas(self.items)

    # Mots-clés (identifiants) de premier niveau, en minuscules.
    func keywords():
        out := []
        for c in self.components:
            if isinstance(c, Token) and c.kind == IDENT:
                append(out, _s.lower(c.value))
        return out

    func functions():
        out := []
        for c in self.components:
            if isinstance(c, Function):
                append(out, c)
        return out

    func is_single_keyword(name=null):
        return len(self.components) == 1 and isinstance(self.components[0], Token) and self.components[0].is_ident(name)

    func is_empty():
        return len(self.components) == 0

# Valeur depuis du texte : « !important » final reconnu et retiré.
func parse(text):
    items := _strip_ws(components(tokenize(str(text))))
    important := false
    n := len(items)
    if n >= 2:
        last := items[n - 1]
        j := n - 2
        while j >= 0 and isinstance(items[j], Token) and items[j].kind == WHITESPACE:
            j -= 1
        if isinstance(last, Token) and last.is_ident("important") and j >= 0 and isinstance(items[j], Token) and items[j].is_delim("!"):
            important = true
            items = _strip_ws(items[0:j])
    return Value(items, important)

# Texte normalisé d'une valeur (espaces fusionnés, nombres compacts).
func normalize(text, compact=false):
    return parse(text).to_css(compact)

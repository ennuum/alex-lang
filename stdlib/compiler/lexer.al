# ALEX STANDARD LIBRARY — compiler.lexer
#
# Analyseur lexical d'ALEX écrit en ALEX : le texte source devient une liste de jetons, avec exactement les
# règles du compilateur natif (src/Lexer.cpp) — indentation structurante (INDENT / DEDENT, espaces seulement),
# NEWLINE en fin de ligne logique, continuation implicite entre ( [ {, commentaires # et /* */, entiers
# décimaux / 0x / 0b / 0o avec « _ », flottants avec exposant, chaînes "..." et """...""", f-strings (texte brut
# des interpolations conservé), caractères '.', échappements \n \t \r \\ \" \' \0 \e \xHH \uXXXX \u{...}.
#
#   use compiler.lexer as lx
#   toks := lx.tokenize("x := 0x1F + 2\n", "demo.al")
#   for t in toks:
#       print(t.type, t.lexeme, t.line, t.column)    # IDENTIFIER x 1 1, COLON_EQ := 1 3, INTEGER 0x1F 1 6 ...
#   print(lx.token_types(toks))                       # ["IDENTIFIER", "COLON_EQ", "INTEGER", "PLUS", ...]
#   lx.tokenize(src, "f.al", true)                    # garde aussi les commentaires (jetons COMMENT)
#
# Les noms de types de jetons sont ceux de TokenType.hpp (IDENTIFIER, KW_IF, COLON_EQ, ARROW, DOT_DOT...).
# Colonnes en caractères (base 1). Erreurs : LexError (« fichier:ligne:col: message »).

from core use len, type, to_int, to_float
from collections use append, pop
use string as _s

const KEYWORDS := {"and": "KW_AND", "as": "KW_AS", "async": "KW_ASYNC", "await": "KW_AWAIT", "break": "KW_BREAK",
    "finally": "KW_FINALLY", "catch": "KW_CATCH", "class": "KW_CLASS", "const": "KW_CONST", "continue": "KW_CONTINUE",
    "else": "KW_ELSE", "elif": "KW_ELIF", "enum": "KW_ENUM", "extends": "KW_EXTENDS", "false": "KW_FALSE",
    "for": "KW_FOR", "from": "KW_FROM", "func": "KW_FUNC", "if": "KW_IF", "import": "KW_IMPORT", "in": "KW_IN",
    "interface": "KW_INTERFACE", "let": "KW_LET", "match": "KW_MATCH", "not": "KW_NOT", "null": "KW_NULL",
    "or": "KW_OR", "return": "KW_RETURN", "self": "KW_SELF", "struct": "KW_STRUCT", "super": "KW_SUPER",
    "true": "KW_TRUE", "try": "KW_TRY", "use": "KW_USE", "while": "KW_WHILE", "yield": "KW_YIELD"}

# Opérateurs, du plus long au plus court.
const OPERATORS := [["**=", "STAR_STAR_EQ"], ["//=", "SLASH_SLASH_EQ"], ["<<=", "LT_LT_EQ"], [">>=", "GT_GT_EQ"],
    [":=", "COLON_EQ"], ["..", "DOT_DOT"], ["+=", "PLUS_EQ"], ["-=", "MINUS_EQ"], ["->", "THIN_ARROW"],
    ["**", "STAR_STAR"], ["*=", "STAR_EQ"], ["//", "SLASH_SLASH"], ["/=", "SLASH_EQ"], ["%=", "PERCENT_EQ"],
    ["==", "EQ_EQ"], ["=>", "ARROW"], ["!=", "BANG_EQ"], ["<<", "LT_LT"], ["<=", "LT_EQ"], [">>", "GT_GT"],
    [">=", "GT_EQ"], ["&=", "AMP_EQ"], ["|=", "PIPE_EQ"], ["^=", "CARET_EQ"],
    ["+", "PLUS"], ["-", "MINUS"], ["*", "STAR"], ["/", "SLASH"], ["%", "PERCENT"], ["=", "EQ"], ["<", "LT"],
    [">", "GT"], ["&", "AMP"], ["|", "PIPE"], ["^", "CARET"], ["~", "TILDE"], ["@", "AT"], [":", "COLON"],
    [".", "DOT"], [",", "COMMA"], ["?", "QUESTION"], ["(", "LPAREN"], [")", "RPAREN"], ["[", "LBRACKET"],
    ["]", "RBRACKET"], ["{", "LBRACE"], ["}", "RBRACE"]]

class Token:
    func init(type_name, lexeme, value, line, column):
        self.type = type_name
        self.lexeme = lexeme
        self.value = value
        self.line = line
        self.column = column

    func is_keyword():
        return _s.starts_with(self.type, "KW_")

    func __str__():
        if self.lexeme == "":
            return self.type + "@" + str(self.line) + ":" + str(self.column)
        return self.type + "(" + self.lexeme + ")@" + str(self.line) + ":" + str(self.column)

func _is_digit(c):
    return c >= '0' and c <= '9'

func _is_alpha(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_'

func _is_alnum(c):
    return _is_alpha(c) or _is_digit(c)

func _hex_digit(c):
    if c >= '0' and c <= '9':
        return _s.ord(c) - 48
    if c >= 'a' and c <= 'f':
        return _s.ord(c) - 87
    if c >= 'A' and c <= 'F':
        return _s.ord(c) - 55
    return -1

class Lexer:
    func init(source, file="<source>", keep_comments=false):
        self.src = source
        self.file = file
        self.keep_comments = keep_comments
        self.n = len(source)
        self.pos = 0
        self.line = 1
        self.col = 1
        self.tokens = []
        self.indents = [0]
        self.depth = 0
        self.at_line_start = true
        self.line_has_tokens = false

    func error(msg, line=null, col=null):
        l := line
        c := col
        if l == null:
            l = self.line
        if c == null:
            c = self.col
        raise("LexError", self.file + ":" + str(l) + ":" + str(c) + ": " + msg)

    func peek(k=0):
        i := self.pos + k
        if i >= self.n:
            return '\0'
        return self.src[i]

    func advance():
        c := self.src[self.pos]
        self.pos += 1
        if c == '\n':
            self.line += 1
            self.col = 1
        else:
            self.col += 1
        return c

    func add(t, lexeme, value, line, col):
        append(self.tokens, Token(t, lexeme, value, line, col))

    func skip_inline():
        while self.pos < self.n:
            c := self.peek()
            if c == ' ' or c == '\t' or c == '\r':
                self.advance()
            elif c == '#':
                sl := self.line
                sc := self.col
                a := self.pos
                while self.pos < self.n and self.peek() != '\n':
                    self.advance()
                if self.keep_comments:
                    self.add("COMMENT", _s.substring(self.src, a, self.pos), null, sl, sc)
            elif c == '/' and self.peek(1) == '*':
                sl := self.line
                sc := self.col
                a := self.pos
                self.advance()
                self.advance()
                closed := false
                while self.pos < self.n:
                    if self.peek() == '*' and self.peek(1) == '/':
                        self.advance()
                        self.advance()
                        closed = true
                        break
                    self.advance()
                if not closed:
                    self.error("commentaire multiligne '/*' non refermé avant la fin du fichier", sl, sc)
                if self.keep_comments:
                    self.add("COMMENT", _s.substring(self.src, a, self.pos), null, sl, sc)
            else:
                break

    func line_start():
        while true:
            spaces := 0
            while self.peek() == ' ':
                spaces += 1
                self.advance()
            if self.peek() == '\t':
                self.error("tabulation interdite dans l'indentation structurante ; utilisez uniquement des espaces (§3)")
            content_line := self.line
            self.skip_inline()
            if self.pos >= self.n:
                return
            if self.peek() == '\n':
                self.advance()
                continue
            top := self.indents[len(self.indents) - 1]
            if spaces > top:
                append(self.indents, spaces)
                self.add("INDENT", "", null, content_line, spaces + 1)
            elif spaces < top:
                while len(self.indents) > 1 and self.indents[len(self.indents) - 1] > spaces:
                    pop(self.indents)
                    self.add("DEDENT", "", null, content_line, spaces + 1)
                if self.indents[len(self.indents) - 1] != spaces:
                    self.error("niveau d'indentation incohérent : ne correspond à aucun niveau ouvert", content_line, spaces + 1)
            return

    func run():
        while true:
            if self.depth == 0 and self.at_line_start:
                self.line_start()
                self.at_line_start = false
            self.skip_inline()
            if self.pos >= self.n:
                break
            c := self.peek()
            if c == '\n':
                self.advance()
                if self.depth == 0:
                    if self.line_has_tokens:
                        self.add("NEWLINE", "", null, self.line - 1, self.col)
                    self.line_has_tokens = false
                    self.at_line_start = true
                continue
            self.scan_token()
            self.line_has_tokens = true
        if self.line_has_tokens:
            self.add("NEWLINE", "", null, self.line, self.col)
        if self.depth != 0:
            self.error("délimiteur non refermé à la fin du fichier (parenthèse, crochet ou accolade en attente)")
        while len(self.indents) > 1:
            pop(self.indents)
            self.add("DEDENT", "", null, self.line, self.col)
        self.add("END_OF_FILE", "", null, self.line, self.col)
        return self.tokens

    func scan_token():
        sl := self.line
        sc := self.col
        c := self.peek()
        if c == '"':
            self.advance()
            if self.peek() == '"' and self.peek(1) == '"':
                self.advance()
                self.advance()
                self.scan_string(false, sl, sc, true)
            else:
                self.scan_string(false, sl, sc, false)
            return
        if c == '\'':
            self.advance()
            self.scan_char(sl, sc)
            return
        if c == 'f' and self.peek(1) == '"':
            self.advance()
            self.advance()
            if self.peek() == '"' and self.peek(1) == '"':
                self.advance()
                self.advance()
                self.scan_string(true, sl, sc, true)
            else:
                self.scan_string(true, sl, sc, false)
            return
        if _is_alpha(c):
            a := self.pos
            while self.pos < self.n and _is_alnum(self.peek()):
                self.advance()
            text := _s.substring(self.src, a, self.pos)
            if text in KEYWORDS:
                self.add(KEYWORDS[text], text, null, sl, sc)
            else:
                self.add("IDENTIFIER", text, text, sl, sc)
            return
        if _is_digit(c):
            self.scan_number(sl, sc)
            return
        if c == '!' and self.peek(1) != '=':
            self.error("caractère '!' inattendu (seul '!=' est défini par la grammaire)", sl, sc)
        for op in OPERATORS:
            text := op[0]
            k := len(text)
            ok := true
            i := 0
            while i < k:
                if self.peek(i) != text[i]:
                    ok = false
                    break
                i += 1
            if ok:
                i = 0
                while i < k:
                    self.advance()
                    i += 1
                if text == "(" or text == "[" or text == "{":
                    self.depth += 1
                elif (text == ")" or text == "]" or text == "}") and self.depth > 0:
                    self.depth -= 1
                self.add(op[1], text, null, sl, sc)
                return
        self.error("caractère inattendu '" + str(c) + "'", sl, sc)

    func scan_number(sl, sc):
        a := self.pos
        nx := self.peek(1)
        if self.peek() == '0' and (nx == 'x' or nx == 'X' or nx == 'b' or nx == 'B' or nx == 'o' or nx == 'O'):
            base := 8
            if nx == 'x' or nx == 'X':
                base = 16
            elif nx == 'b' or nx == 'B':
                base = 2
            self.advance()
            self.advance()
            v := 0
            digits := 0
            last_us := false
            while self.pos < self.n:
                c := self.peek()
                d := _hex_digit(c)
                if c == '_' and digits > 0:
                    self.advance()
                    last_us = true
                    continue
                if d < 0 or d >= base:
                    if _is_alnum(c):
                        self.error("chiffre invalide '" + str(c) + "' dans un littéral en base " + str(base), sl, sc)
                    break
                v = v * base + d
                digits += 1
                last_us = false
                self.advance()
            text := _s.substring(self.src, a, self.pos)
            if digits == 0 or last_us:
                self.error("littéral en base " + str(base) + " incomplet : '" + text + "'", sl, sc)
            self.add("INTEGER", text, v, sl, sc)
            return
        while self.pos < self.n and (_is_digit(self.peek()) or (self.peek() == '_' and _is_digit(self.peek(1)))):
            self.advance()
        is_float := false
        if self.peek() == '.' and self.peek(1) != '.' and _is_digit(self.peek(1)):
            is_float = true
            self.advance()
            while self.pos < self.n and (_is_digit(self.peek()) or (self.peek() == '_' and _is_digit(self.peek(1)))):
                self.advance()
        e := self.peek()
        if (e == 'e' or e == 'E') and (_is_digit(self.peek(1)) or ((self.peek(1) == '+' or self.peek(1) == '-') and _is_digit(self.peek(2)))):
            is_float = true
            self.advance()
            if self.peek() == '+' or self.peek() == '-':
                self.advance()
            while self.pos < self.n and _is_digit(self.peek()):
                self.advance()
        text := _s.replace(_s.substring(self.src, a, self.pos), "_", "")
        if is_float:
            self.add("FLOAT", text, to_float(text), sl, sc)
        else:
            if len(text) > 19 or (len(text) == 19 and text > "9223372036854775807"):
                self.error("littéral numérique hors de la plage représentable : '" + text + "'", sl, sc)
            self.add("INTEGER", text, to_int(text), sl, sc)

    func escape(sl, sc):
        if self.pos >= self.n:
            self.error("séquence d'échappement incomplète en fin de fichier", sl, sc)
        e := self.advance()
        if e == 'n':
            return "\n"
        if e == 't':
            return "\t"
        if e == 'r':
            return "\r"
        if e == '\\':
            return "\\"
        if e == '"':
            return "\""
        if e == '\'':
            return "'"
        if e == '0':
            return "\0"
        if e == 'e':
            return "\e"
        if e == 'x':
            return str(_s.chr(self.read_hex(2, "\\x", sl, sc)))
        if e == 'u':
            v := 0
            if self.peek() == '{':
                self.advance()
                k := 0
                while self.pos < self.n and self.peek() != '}':
                    d := _hex_digit(self.peek())
                    if d < 0 or k >= 6:
                        self.error("échappement \\u{...} : 1 à 6 chiffres hexadécimaux attendus", sl, sc)
                    v = v * 16 + d
                    self.advance()
                    k += 1
                if self.pos >= self.n or k == 0:
                    self.error("échappement \\u{...} incomplet", sl, sc)
                self.advance()
            else:
                v = self.read_hex(4, "\\u", sl, sc)
            if v > 0x10FFFF or (v >= 0xD800 and v <= 0xDFFF):
                self.error("échappement \\u : point de code Unicode invalide", sl, sc)
            return str(_s.chr(v))
        self.error("séquence d'échappement inconnue '\\" + str(e) + "'", sl, sc)

    func read_hex(count, what, sl, sc):
        v := 0
        i := 0
        while i < count:
            if self.pos >= self.n or _hex_digit(self.peek()) < 0:
                self.error("échappement " + what + " : chiffres hexadécimaux attendus", sl, sc)
            v = v * 16 + _hex_digit(self.advance())
            i += 1
        return v

    func scan_string(is_f, sl, sc, triple):
        parts := []
        chunk := self.pos
        in_interp := false
        depth := 0
        while true:
            if self.pos >= self.n:
                self.error("chaîne non terminée avant la fin du fichier", sl, sc)
            ch := self.peek()
            if ch == '\n' and not triple:
                self.error("retour à la ligne littéral interdit dans une chaîne (utilisez l'échappement \\n)", sl, sc)
            if not in_interp and ch == '"' and (not triple or (self.peek(1) == '"' and self.peek(2) == '"')):
                append(parts, _s.substring(self.src, chunk, self.pos))
                self.advance()
                if triple:
                    self.advance()
                    self.advance()
                break
            if is_f:
                if not in_interp and ((ch == '{' and self.peek(1) == '{') or (ch == '}' and self.peek(1) == '}')):
                    append(parts, _s.substring(self.src, chunk, self.pos + 1))
                    self.advance()
                    self.advance()
                    chunk = self.pos
                    continue
                if not in_interp and ch == '}':
                    self.error("'}' isolé dans une f-string ; utilisez '}}' pour une accolade littérale", sl, sc)
                if not in_interp and ch == '{':
                    in_interp = true
                    depth = 1
                    self.advance()
                    continue
                if in_interp:
                    if ch == '{':
                        depth += 1
                    elif ch == '}':
                        depth -= 1
                        if depth == 0:
                            in_interp = false
                    self.advance()
                    continue
            if ch == '\\':
                append(parts, _s.substring(self.src, chunk, self.pos))
                self.advance()
                append(parts, self.escape(sl, sc))
                chunk = self.pos
                continue
            self.advance()
        content := _s.join("", parts)
        if is_f:
            self.add("FSTRING", content, content, sl, sc)
        else:
            self.add("STRING", content, content, sl, sc)

    func scan_char(sl, sc):
        if self.pos >= self.n:
            self.error("littéral caractère non terminé en fin de fichier", sl, sc)
        c := self.peek()
        v := null
        if c == '\'':
            self.error("littéral caractère vide (''), un caractère est requis", sl, sc)
        elif c == '\n':
            self.error("retour à la ligne interdit dans un littéral caractère", sl, sc)
        elif c == '\\':
            self.advance()
            v = self.escape(sl, sc)[0]
        else:
            v = self.advance()
        if self.pos >= self.n or self.peek() != '\'':
            self.error("littéral caractère doit contenir exactement un caractère (guillemet simple fermant manquant)", sl, sc)
        self.advance()
        self.add("CHAR", "'" + str(v) + "'", v, sl, sc)

# Liste de jetons de source (le dernier est END_OF_FILE).
func tokenize(source, file="<source>", keep_comments=false):
    return Lexer(source, file, keep_comments).run()

func token_types(tokens):
    return [t.type for t in tokens]

func is_keyword(word):
    return word in KEYWORDS

# Jetons d'une seule ligne d'expression (sans NEWLINE ni END_OF_FILE).
func tokenize_expression(text):
    return [t for t in tokenize(text) if t.type != "NEWLINE" and t.type != "END_OF_FILE"]

# ALEX — lexer
#
# Analyseur lexical de la chaîne de compilation vers bytecode : portage fidèle de src/Lexer.cpp. Il travaille
# sur les OCTETS du source (colonnes comptées en octets, comme le lexer de référence) : mêmes jetons, mêmes
# positions, mêmes valeurs (entiers 0x/0b/0o en complément à deux, échappements \n \t \r \\ \" \' \0 \e \xHH
# \uXXXX \u{H...}, chaînes """...""", f-strings dont le contenu brut est gardé pour le parser), mêmes
# INDENT / DEDENT / NEWLINE, mêmes erreurs.
#
#   use lexer as lx
#   toks := lx.tokenize_text("x := 1\n", "essai.al")
#   for t in toks: print(t.type, t.lexeme, t.line, t.column)     # IDENTIFIER x 1 1 ...
#   toks2 := lx.tokenize(io.read_bytes("prog.al"), "prog.al")
#
# Types de jetons : noms de l'énumération TokenType (« IDENTIFIER », « KW_FUNC », « COLON_EQ »...), « EOF » en fin.
# Erreurs : SyntaxError, IndentationError (« fichier:ligne:colonne: message »).

from core use len, type, to_int, to_float
from collections use append
use string as _s
use token as _tk

func _is_alpha(c):
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

func _is_digit(c):
    return c >= 48 and c <= 57

func _is_alnum(c):
    return _is_alpha(c) or _is_digit(c)

func _hexval(c):
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55
    return -1

func append_utf8(out, cp):
    if cp < 0x80:
        append(out, cp)
    elif cp < 0x800:
        append(out, 0xC0 | (cp >> 6))
        append(out, 0x80 | (cp & 0x3F))
    elif cp < 0x10000:
        append(out, 0xE0 | (cp >> 12))
        append(out, 0x80 | ((cp >> 6) & 0x3F))
        append(out, 0x80 | (cp & 0x3F))
    else:
        append(out, 0xF0 | (cp >> 18))
        append(out, 0x80 | ((cp >> 12) & 0x3F))
        append(out, 0x80 | ((cp >> 6) & 0x3F))
        append(out, 0x80 | (cp & 0x3F))

class Lexer:
    func init(src, filename):
        self.src = src             # liste d'octets
        self.n = len(src)
        self.text_src = _s.byte_pack(src)   # même source, en chaîne (extraits de lexèmes)
        self.filename = filename
        self.pos = 0
        self.line = 1
        self.column = 1
        self.tokens = []
        self.indents = [0]
        self.bracket = 0
        self.at_line_start = true
        self.line_has_tokens = false

    func error(kind, message, line=-1, column=-1):
        l := self.line if line < 0 else line
        c := self.column if column < 0 else column
        raise(kind, self.filename + ":" + str(l) + ":" + str(c) + ": " + message)

    func at_end():
        return self.pos >= self.n

    func peek(k=0):
        i := self.pos + k
        if k < 0 or i >= self.n:
            return 0
        return self.src[i]

    func advance():
        c := self.src[self.pos]
        self.pos += 1
        if c == 10:
            self.line += 1
            self.column = 1
        else:
            self.column += 1
        return c

    func accept(c):
        if self.pos >= self.n or self.src[self.pos] != c:
            return false
        self.advance()
        return true

    func add(type, lexeme, value, line, column):
        append(self.tokens, _tk.Token(type, lexeme, value, line, column))

    func text(a, b):
        if a >= b:
            return ""
        return _s.byte_slice(self.text_src, a, b)

    func skip_inline():
        src := self.src
        n := self.n
        while self.pos < n:
            c := src[self.pos]
            if c == 32 or c == 9 or c == 13:
                # blancs (jamais de fin de ligne) : position et colonne avancent ensemble
                p := self.pos + 1
                while p < n and (src[p] == 32 or src[p] == 9 or src[p] == 13):
                    p += 1
                self.column += p - self.pos
                self.pos = p
            elif c == 35:
                p := self.pos
                while p < n and src[p] != 10:
                    p += 1
                self.column += p - self.pos
                self.pos = p
            elif c == 47 and self.peek(1) == 42:
                sl := self.line
                sc := self.column
                self.advance()
                self.advance()
                closed := false
                while self.pos < self.n:
                    if self.src[self.pos] == 42 and self.peek(1) == 47:
                        self.advance()
                        self.advance()
                        closed = true
                        break
                    self.advance()
                if not closed:
                    self.error("SyntaxError", "commentaire multiligne '/*' non refermé avant la fin du fichier", sl, sc)
            else:
                break

    func line_start():
        while true:
            spaces := 0
            while self.peek() == 32:
                spaces += 1
                self.advance()
            if self.peek() == 9:
                self.error("IndentationError", "tabulation interdite dans l'indentation structurante ; utilisez uniquement des espaces (§3)")
            content_line := self.line
            self.skip_inline()
            if self.at_end():
                return
            if self.peek() == 10:
                self.advance()
                continue
            top := self.indents[len(self.indents) - 1]
            if spaces > top:
                append(self.indents, spaces)
                self.add("INDENT", "", null, content_line, spaces + 1)
            elif spaces < top:
                while len(self.indents) > 1 and self.indents[len(self.indents) - 1] > spaces:
                    self.indents = self.indents[0:len(self.indents) - 1]
                    self.add("DEDENT", "", null, content_line, spaces + 1)
                if self.indents[len(self.indents) - 1] != spaces:
                    self.error("IndentationError", "niveau d'indentation incohérent : ne correspond à aucun niveau ouvert", content_line, spaces + 1)
            return

    func tokenize():
        self.tokens = []
        while true:
            if self.bracket == 0 and self.at_line_start:
                self.line_start()
                self.at_line_start = false
            self.skip_inline()
            if self.at_end():
                break
            c := self.peek()
            if c == 10:
                self.advance()
                if self.bracket == 0:
                    if self.line_has_tokens:
                        self.add("NEWLINE", "", null, self.line - 1, self.column)
                    self.line_has_tokens = false
                    self.at_line_start = true
                continue
            self.scan_token()
            self.line_has_tokens = true
        if self.line_has_tokens:
            self.add("NEWLINE", "", null, self.line, self.column)
        if self.bracket != 0:
            self.error("SyntaxError", "délimiteur non refermé à la fin du fichier (parenthèse, crochet ou accolade en attente)")
        while len(self.indents) > 1:
            self.indents = self.indents[0:len(self.indents) - 1]
            self.add("DEDENT", "", null, self.line, self.column)
        self.add("EOF", "", null, self.line, self.column)
        return self.tokens

    func scan_token():
        sl := self.line
        sc := self.column
        c := self.advance()
        if c == 40:
            self.bracket += 1
            self.add("LPAREN", "(", null, sl, sc)
        elif c == 41:
            if self.bracket > 0:
                self.bracket -= 1
            self.add("RPAREN", ")", null, sl, sc)
        elif c == 91:
            self.bracket += 1
            self.add("LBRACKET", "[", null, sl, sc)
        elif c == 93:
            if self.bracket > 0:
                self.bracket -= 1
            self.add("RBRACKET", "]", null, sl, sc)
        elif c == 123:
            self.bracket += 1
            self.add("LBRACE", "{", null, sl, sc)
        elif c == 125:
            if self.bracket > 0:
                self.bracket -= 1
            self.add("RBRACE", "}", null, sl, sc)
        elif c == 44:
            self.add("COMMA", ",", null, sl, sc)
        elif c == 63:
            self.add("QUESTION", "?", null, sl, sc)
        elif c == 126:
            self.add("TILDE", "~", null, sl, sc)
        elif c == 64:
            self.add("AT", "@", null, sl, sc)
        elif c == 58:
            if self.accept(61):
                self.add("COLON_EQ", ":=", null, sl, sc)
            else:
                self.add("COLON", ":", null, sl, sc)
        elif c == 46:
            if self.peek() == 46:
                self.advance()
                self.add("DOT_DOT", "..", null, sl, sc)
            else:
                self.add("DOT", ".", null, sl, sc)
        elif c == 43:
            if self.accept(61):
                self.add("PLUS_EQ", "+=", null, sl, sc)
            else:
                self.add("PLUS", "+", null, sl, sc)
        elif c == 45:
            if self.accept(61):
                self.add("MINUS_EQ", "-=", null, sl, sc)
            elif self.accept(62):
                self.add("THIN_ARROW", "->", null, sl, sc)
            else:
                self.add("MINUS", "-", null, sl, sc)
        elif c == 42:
            if self.peek() == 42:
                self.advance()
                if self.accept(61):
                    self.add("STAR_STAR_EQ", "**=", null, sl, sc)
                else:
                    self.add("STAR_STAR", "**", null, sl, sc)
            elif self.accept(61):
                self.add("STAR_EQ", "*=", null, sl, sc)
            else:
                self.add("STAR", "*", null, sl, sc)
        elif c == 47:
            if self.peek() == 47:
                self.advance()
                if self.accept(61):
                    self.add("SLASH_SLASH_EQ", "//=", null, sl, sc)
                else:
                    self.add("SLASH_SLASH", "//", null, sl, sc)
            elif self.accept(61):
                self.add("SLASH_EQ", "/=", null, sl, sc)
            else:
                self.add("SLASH", "/", null, sl, sc)
        elif c == 37:
            if self.accept(61):
                self.add("PERCENT_EQ", "%=", null, sl, sc)
            else:
                self.add("PERCENT", "%", null, sl, sc)
        elif c == 61:
            if self.accept(61):
                self.add("EQ_EQ", "==", null, sl, sc)
            elif self.accept(62):
                self.add("ARROW", "=>", null, sl, sc)
            else:
                self.add("EQ", "=", null, sl, sc)
        elif c == 33:
            if self.accept(61):
                self.add("BANG_EQ", "!=", null, sl, sc)
            else:
                self.error("SyntaxError", "caractère '!' inattendu (seul '!=' est défini par la grammaire)", sl, sc)
        elif c == 60:
            if self.peek() == 60:
                self.advance()
                if self.accept(61):
                    self.add("LT_LT_EQ", "<<=", null, sl, sc)
                else:
                    self.add("LT_LT", "<<", null, sl, sc)
            elif self.accept(61):
                self.add("LT_EQ", "<=", null, sl, sc)
            else:
                self.add("LT", "<", null, sl, sc)
        elif c == 62:
            if self.peek() == 62:
                self.advance()
                if self.accept(61):
                    self.add("GT_GT_EQ", ">>=", null, sl, sc)
                else:
                    self.add("GT_GT", ">>", null, sl, sc)
            elif self.accept(61):
                self.add("GT_EQ", ">=", null, sl, sc)
            else:
                self.add("GT", ">", null, sl, sc)
        elif c == 38:
            if self.accept(61):
                self.add("AMP_EQ", "&=", null, sl, sc)
            else:
                self.add("AMP", "&", null, sl, sc)
        elif c == 124:
            if self.accept(61):
                self.add("PIPE_EQ", "|=", null, sl, sc)
            else:
                self.add("PIPE", "|", null, sl, sc)
        elif c == 94:
            if self.accept(61):
                self.add("CARET_EQ", "^=", null, sl, sc)
            else:
                self.add("CARET", "^", null, sl, sc)
        elif c == 34:
            if self.peek() == 34 and self.peek(1) == 34:
                self.advance()
                self.advance()
                self.scan_string(false, sl, sc, true)
            else:
                self.scan_string(false, sl, sc, false)
        elif c == 39:
            self.scan_char(sl, sc)
        elif c == 102 and self.peek() == 34:
            self.advance()
            if self.peek() == 34 and self.peek(1) == 34:
                self.advance()
                self.advance()
                self.scan_string(true, sl, sc, true)
            else:
                self.scan_string(true, sl, sc, false)
        elif _is_alpha(c) or c == 95:
            self.pos -= 1
            self.column -= 1
            self.scan_identifier()
        elif _is_digit(c):
            self.pos -= 1
            self.column -= 1
            self.scan_number()
        else:
            self.error("SyntaxError", "caractère inattendu '" + _s.byte_pack([c]) + "'", sl, sc)

    func scan_identifier():
        sl := self.line
        sc := self.column
        start := self.pos
        src := self.src
        n := self.n
        p := start
        while p < n:
            c := src[p]
            if (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 95:
                p += 1
            else:
                break
        # un identifiant ne contient pas de fin de ligne : la colonne avance d'autant
        self.column += p - start
        self.pos = p
        t := self.text(start, self.pos)
        if t in _tk.KEYWORDS:
            self.add(_tk.KEYWORDS[t], t, null, sl, sc)
        else:
            self.add("IDENTIFIER", t, t, sl, sc)

    func scan_number():
        sl := self.line
        sc := self.column
        start := self.pos
        p1 := self.peek(1)
        if self.peek() == 48 and (p1 == 120 or p1 == 88 or p1 == 98 or p1 == 66 or p1 == 111 or p1 == 79):
            kind := p1 | 32
            base := 16 if kind == 120 else (2 if kind == 98 else 8)
            step := 4 if base == 16 else (1 if base == 2 else 3)
            self.advance()
            self.advance()
            v := 0
            digits := 0
            bits := 0
            last_us := false
            while self.pos < self.n:
                c := self.src[self.pos]
                d := _hexval(c)
                if c == 95 and digits > 0:
                    self.advance()
                    last_us = true
                    continue
                if d < 0 or d >= base:
                    if _is_alnum(c):
                        self.error("SyntaxError", "chiffre invalide '" + _s.byte_pack([c]) + "' dans un littéral en base " + str(base), sl, sc)
                    break
                if bits > 0:
                    bits += step
                elif d > 0:
                    bits = 1
                    x := d
                    while x > 1:
                        bits += 1
                        x = x >> 1
                v = v * base + d
                digits += 1
                last_us = false
                self.advance()
            t := self.text(start, self.pos)
            if digits == 0 or last_us:
                self.error("SyntaxError", "littéral en base " + str(base) + " incomplet : '" + t + "'", sl, sc)
            if bits > 64:
                self.error("SyntaxError", "littéral numérique au-delà de 64 bits : '" + t + "'", sl, sc)
            self.add("INTEGER", t, v, sl, sc)
            return
        while self.pos < self.n and (_is_digit(self.src[self.pos]) or (self.src[self.pos] == 95 and _is_digit(self.peek(1)))):
            self.advance()
        is_float := false
        if self.peek() == 46 and self.peek(1) != 46 and _is_digit(self.peek(1)):
            is_float = true
            self.advance()
            while self.pos < self.n and (_is_digit(self.src[self.pos]) or (self.src[self.pos] == 95 and _is_digit(self.peek(1)))):
                self.advance()
        if (self.peek() == 101 or self.peek() == 69) and (_is_digit(self.peek(1)) or ((self.peek(1) == 43 or self.peek(1) == 45) and _is_digit(self.peek(2)))):
            is_float = true
            self.advance()
            if self.peek() == 43 or self.peek() == 45:
                self.advance()
            while self.pos < self.n and _is_digit(self.src[self.pos]):
                self.advance()
        raw := [self.src[k] for k in start..self.pos if self.src[k] != 95]
        t := _s.byte_pack(raw)
        if is_float:
            self.add("FLOAT", t, to_float(t), sl, sc)
        else:
            # stoll : au-delà de 2^63 - 1 -> hors plage
            digits_only := t
            k := 0
            while k < len(digits_only) - 1 and digits_only[k] == '0':
                k += 1
            sig := len(digits_only) - k
            if sig > 19 or (sig == 19 and digits_only[k:len(digits_only)] > "9223372036854775807"):
                self.error("SyntaxError", "littéral numérique hors de la plage représentable : '" + t + "'", sl, sc)
            self.add("INTEGER", t, to_int(t), sl, sc)

    func escape(sl, sc):
        if self.at_end():
            self.error("SyntaxError", "séquence d'échappement incomplète en fin de fichier", sl, sc)
        e := self.advance()
        if e == 110:
            return 10
        if e == 116:
            return 9
        if e == 114:
            return 13
        if e == 92:
            return 92
        if e == 34:
            return 34
        if e == 39:
            return 39
        if e == 48:
            return 0
        if e == 101:
            return 27
        if e == 120:
            return self.read_hex(2, "\\x", sl, sc)
        if e == 117:
            v := 0
            if not self.at_end() and self.peek() == 123:
                self.advance()
                k := 0
                while not self.at_end() and self.peek() != 125:
                    d := _hexval(self.peek())
                    if d < 0 or k >= 6:
                        self.error("SyntaxError", "échappement \\u{...} : 1 à 6 chiffres hexadécimaux attendus", sl, sc)
                    v = v * 16 + d
                    self.advance()
                    k += 1
                if self.at_end() or k == 0:
                    self.error("SyntaxError", "échappement \\u{...} incomplet", sl, sc)
                self.advance()
            else:
                v = self.read_hex(4, "\\u", sl, sc)
            if v > 0x10FFFF or (v >= 0xD800 and v <= 0xDFFF):
                self.error("SyntaxError", "échappement \\u : point de code Unicode invalide", sl, sc)
            return v
        self.error("SyntaxError", "séquence d'échappement inconnue '\\" + _s.byte_pack([e]) + "'", sl, sc)

    func read_hex(count, what, sl, sc):
        v := 0
        i := 0
        while i < count:
            if self.at_end() or _hexval(self.peek()) < 0:
                self.error("SyntaxError", "échappement " + what + " : chiffres hexadécimaux attendus", sl, sc)
            v = v * 16 + _hexval(self.advance())
            i += 1
        return v

    func utf8_codepoint(sl, sc):
        b0 := self.advance()
        if b0 < 0x80:
            return b0
        extra := 0
        cp := 0
        if (b0 & 0xE0) == 0xC0:
            extra = 1
            cp = b0 & 0x1F
        elif (b0 & 0xF0) == 0xE0:
            extra = 2
            cp = b0 & 0x0F
        elif (b0 & 0xF8) == 0xF0:
            extra = 3
            cp = b0 & 0x07
        else:
            self.error("SyntaxError", "séquence UTF-8 invalide", sl, sc)
        i := 0
        while i < extra:
            if self.at_end():
                self.error("SyntaxError", "séquence UTF-8 tronquée en fin de fichier", sl, sc)
            b := self.advance()
            if (b & 0xC0) != 0x80:
                self.error("SyntaxError", "octet de continuation UTF-8 invalide", sl, sc)
            cp = (cp << 6) | (b & 0x3F)
            i += 1
        return cp

    func scan_string(is_f, sl, sc, triple):
        content := []
        in_interp := false
        depth := 0
        while true:
            if self.at_end():
                self.error("SyntaxError", "chaîne non terminée avant la fin du fichier", sl, sc)
            ch := self.src[self.pos]
            if ch == 10 and not triple:
                self.error("SyntaxError", "retour à la ligne littéral interdit dans une chaîne (utilisez l'échappement \\n)", sl, sc)
            if triple and not in_interp and ch == 34 and self.peek(1) == 34 and self.peek(2) == 34:
                self.advance()
                self.advance()
                self.advance()
                break
            if not triple and not in_interp and ch == 34:
                self.advance()
                break
            if is_f:
                if not in_interp and ch == 123 and self.peek(1) == 123:
                    self.advance()
                    self.advance()
                    append(content, 123)
                    continue
                if not in_interp and ch == 125 and self.peek(1) == 125:
                    self.advance()
                    self.advance()
                    append(content, 125)
                    continue
                if not in_interp and ch == 125:
                    self.error("SyntaxError", "'}' isolé dans une f-string ; utilisez '}}' pour une accolade littérale", sl, sc)
                if not in_interp and ch == 123:
                    self.advance()
                    append(content, 123)
                    in_interp = true
                    depth = 1
                    continue
                if in_interp:
                    if ch == 123:
                        depth += 1
                    elif ch == 125:
                        depth -= 1
                        if depth == 0:
                            in_interp = false
                    append(content, ch)
                    self.advance()
                    continue
            if ch == 92:
                self.advance()
                append_utf8(content, self.escape(sl, sc))
                continue
            append(content, ch)
            self.advance()
        if is_f and in_interp:
            self.error("SyntaxError", "interpolation '{' non refermée dans une f-string", sl, sc)
        t := _s.byte_pack(content)
        self.add("FSTRING" if is_f else "STRING", t, t, sl, sc)

    func scan_char(sl, sc):
        if self.at_end():
            self.error("SyntaxError", "littéral caractère non terminé en fin de fichier", sl, sc)
        c := self.peek()
        v := 0
        if c == 39:
            self.error("SyntaxError", "littéral caractère vide (''), un caractère est requis", sl, sc)
        elif c == 10:
            self.error("SyntaxError", "retour à la ligne interdit dans un littéral caractère", sl, sc)
        elif c == 92:
            self.advance()
            v = self.escape(sl, sc)
        else:
            v = self.utf8_codepoint(sl, sc)
        if self.at_end() or self.peek() != 39:
            self.error("SyntaxError", "littéral caractère doit contenir exactement un caractère (guillemet simple fermant manquant)", sl, sc)
        self.advance()
        self.add("CHAR", "", v, sl, sc)

func tokenize(src_bytes, filename="<source>"):
    return Lexer(src_bytes, filename).tokenize()

func tokenize_text(text, filename="<source>"):
    return Lexer(_s.byte_unpack(text), filename).tokenize()

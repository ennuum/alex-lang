# ALEX STANDARD LIBRARY — web.js.js_formatter
#
# Mise en forme de JavaScript par jetons : indentation par blocs, une instruction par ligne, espaces autour des
# opérateurs binaires et après les virgules, mots-clés suivis d'un espace, objets et tableaux courts gardés sur
# une ligne, lignes vides conservées (une au plus), commentaires préservés. Ne réordonne ni ne réécrit rien :
# seuls les blancs changent (le code minifié redevient lisible).
#
#   use web.js.js_formatter as fmt
#   fmt.format("function f(a,b){if(a>b){return a}else{return b}}")
#   # function f(a, b) {\n  if (a > b) {\n    return a\n  } else {\n    return b\n  }\n}\n
#   fmt.format(source, fmt.Options("    "))     # indentation de 4 espaces
#   fmt.is_formatted(source)                     # vrai si format() ne change rien
#
# Erreurs : JsSyntaxError (source lexicalement invalide).

from core use len, type
from collections use append
use string as _s
use web.js.js_errors as _err
use web.js.js_validator as _lex

class Options:
    func init(indent="  ", max_inline=60, keep_blank_lines=true):
        self.indent = indent
        self.max_inline = max_inline        # longueur max d'un objet / tableau gardé sur une ligne
        self.keep_blank_lines = keep_blank_lines

const _SPACE_AFTER_KEYWORDS := ["if", "for", "while", "switch", "catch", "return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case", "const", "let", "var", "else", "do", "try", "finally", "function", "class", "extends", "import", "export", "from", "as", "async", "await", "yield", "default", "static", "get", "set"]
const _BINARY := ["=", "+=", "-=", "*=", "/=", "%=", "**=", "<<=", ">>=", ">>>=", "&=", "|=", "^=", "&&=", "||=", "??=", "==", "!=", "===", "!==", "<", ">", "<=", ">=", "&&", "||", "??", "+", "-", "*", "/", "%", "**", "&", "|", "^", "<<", ">>", ">>>", "=>", "?", ":"]

func _is_value_end(t):
    if t == null:
        return false
    if t.kind == _lex.IDENTIFIER or t.kind == _lex.NUMBER or t.kind == _lex.STRING or t.kind == _lex.TEMPLATE or t.kind == _lex.REGEX or t.kind == _lex.PRIVATE:
        return true
    if t.kind == _lex.KEYWORD and t.value in ["this", "true", "false", "null", "super"]:
        return true
    return t.kind == _lex.PUNCT and (t.value == ")" or t.value == "]" or t.value == "}" or t.value == "++" or t.value == "--")

class _F:
    func init(src, opts):
        self.src = src
        self.o = opts
        self.toks = _lex.tokenize(src, true)
        for t in self.toks:
            if t.kind == _lex.ERROR:
                _err.syntax_error("js_formatter", t.error, t.line, t.column)
        self.out = []
        self.level = 0
        self.line_open = false
        self.unary = false
        self.pending_switch = false
        self.stack = []          # pile : "{" bloc, "{o" objet en ligne, "(" , "[", "[i" tableau en ligne, "for("

    func pad():
        return _s.repeat(self.o.indent, self.level)

    func newline():
        if self.line_open:
            append(self.out, "\n")
        self.line_open = false

    func write(text):
        if not self.line_open:
            append(self.out, self.pad())
            self.line_open = true
        append(self.out, text)

    func space():
        if self.line_open and len(self.out) > 0 and not _s.ends_with(self.out[len(self.out) - 1], " "):
            append(self.out, " ")

    func top():
        return self.stack[len(self.stack) - 1] if len(self.stack) > 0 else null

    # Longueur du contenu jusqu'au fermant correspondant, ou -1 s'il contient un bloc / commentaire / est trop long.
    func inline_length(i, open, close):
        depth := 0
        total := 0
        j := i
        while j < len(self.toks):
            t := self.toks[j]
            if t.is_comment():
                return -1
            if t.kind == _lex.PUNCT and t.value == open:
                depth += 1
            elif t.kind == _lex.PUNCT and t.value == close:
                depth -= 1
                if depth == 0:
                    return total
            elif t.kind == _lex.KEYWORD and t.value in ["function", "class", "return", "if", "for", "while"]:
                return -1
            elif t.is_punct(";") or t.is_punct("=>"):
                return -1
            total += len(t.value) + 1
            if total > self.o.max_inline:
                return -1
            j += 1
        return -1

    func blank_lines_before(t, prev):
        if prev == null or not self.o.keep_blank_lines:
            return 0
        between := self.src[prev.end:t.start]
        return _s.count(between, "\n")

    func run():
        prev := null
        i := 0
        n := len(self.toks)
        while i < n:
            t := self.toks[i]
            nxt := self.toks[i + 1] if i + 1 < n else null
            if self.blank_lines_before(t, prev) >= 2 and self.top() != "(" and self.top() != "[i" and self.top() != "{o":
                self.newline()
                append(self.out, "\n")
            if t.kind == _lex.LINE_COMMENT:
                if prev != null and not t.nl_before:
                    if not self.line_open and len(self.out) > 0 and self.out[len(self.out) - 1] == "\n":
                        self.out = self.out[0:len(self.out) - 1]
                        self.line_open = true
                    self.space()
                else:
                    self.newline()
                self.write(t.value)
                self.newline()
                prev = t
                i += 1
                continue
            if t.kind == _lex.BLOCK_COMMENT:
                if t.nl_before or prev == null:
                    self.newline()
                else:
                    self.space()
                self.write(t.value)
                if nxt != null and nxt.nl_before:
                    self.newline()
                prev = t
                i += 1
                continue
            if t.kind == _lex.HASHBANG:
                self.write(t.value)
                self.newline()
                prev = t
                i += 1
                continue
            v := t.value
            was_unary := self.unary
            self.unary = false
            if t.kind == _lex.KEYWORD and t.value == "switch":
                self.pending_switch = true
            if t.kind == _lex.KEYWORD and (t.value == "case" or (t.value == "default" and nxt != null and nxt.is_punct(":"))) and self.top() == "{s+":
                self.level -= 1
                self.stack[len(self.stack) - 1] = "{s"
                self.newline()
            if t.kind == _lex.PUNCT:
                if v == "{":
                    inline := -1
                    is_block := prev == null or prev.is_punct(")") or (prev.kind == _lex.KEYWORD and prev.value in ["else", "try", "finally", "do"]) or prev.is_punct(";") or prev.is_punct("{") or prev.is_punct("}") or prev.is_punct("=>") or (prev.kind == _lex.IDENTIFIER and i >= 2 and self._class_head(i))
                    if not is_block:
                        inline = self.inline_length(i, "{", "}")
                    if prev != null and not prev.is_punct("(") and not prev.is_punct("[") and not prev.is_punct("{"):
                        self.space()
                    if nxt != null and nxt.is_punct("}"):
                        self.write("{}")
                        i += 2
                        prev = nxt
                        if is_block:
                            self.after_close(i)
                        continue
                    if inline >= 0:
                        self.write("{ ")
                        append(self.stack, "{o")
                    else:
                        self.write("{")
                        kind := "{"
                        if self.pending_switch:
                            kind = "{s"
                            self.pending_switch = false
                        elif not is_block:
                            kind = "{m"
                        append(self.stack, kind)
                        self.level += 1
                        self.newline()
                elif v == "}":
                    kind := self.top()
                    if len(self.stack) > 0:
                        self.stack = self.stack[0:len(self.stack) - 1]
                    if kind == "{o":
                        self.space()
                        self.write("}")
                    else:
                        if kind == "{s+" and self.level > 0:
                            self.level -= 1
                        if self.level > 0:
                            self.level -= 1
                        self.newline()
                        self.write("}")
                        prev = t
                        i += 1
                        self.after_close(i)
                        continue
                elif v == "(":
                    if prev != null and prev.kind == _lex.KEYWORD and prev.value in _SPACE_AFTER_KEYWORDS and prev.value != "function" and prev.value != "import":
                        self.space()
                    elif prev != null and (prev.is_punct("=>") or (prev.kind == _lex.PUNCT and prev.value in _BINARY) or prev.is_punct(",") or (prev.kind == _lex.IDENTIFIER and prev.value == "async")):
                        self.space()
                    self.write("(")
                    append(self.stack, "for(" if prev != null and prev.is_keyword("for") else "(")
                elif v == ")":
                    if len(self.stack) > 0:
                        self.stack = self.stack[0:len(self.stack) - 1]
                    self.write(")")
                elif v == "[":
                    if prev != null and (prev.kind == _lex.PUNCT and (prev.value in _BINARY or prev.value == ",") or prev.kind == _lex.KEYWORD and prev.value in _SPACE_AFTER_KEYWORDS):
                        self.space()
                    self.write("[")
                    append(self.stack, "[i")
                elif v == "]":
                    if len(self.stack) > 0:
                        self.stack = self.stack[0:len(self.stack) - 1]
                    self.write("]")
                elif v == ";":
                    self.write(";")
                    if self.top() == "for(":
                        if nxt != null and not nxt.is_punct(";") and not nxt.is_punct(")"):
                            self.space()
                    else:
                        self.newline()
                elif v == ",":
                    self.write(",")
                    if self.top() == "{m":
                        self.newline()
                    else:
                        self.space()
                elif v == ":" and self._is_case_colon(i) and (self.top() == "{s" or self.top() == "{s+"):
                    self.write(":")
                    if self.top() == "{s":
                        self.stack[len(self.stack) - 1] = "{s+"
                        self.level += 1
                    self.newline()
                elif v == ":" and self._is_label_or_key(i):
                    self.write(":")
                    self.space()
                elif v == "." or v == "?." or v == "...":
                    self.write(v)
                elif (v == "++" or v == "--"):
                    if prev != null and _is_value_end(prev) and not t.nl_before:
                        self.write(v)
                    else:
                        if prev != null and not (prev.is_punct("(") or prev.is_punct("[")):
                            self.space()
                        self.write(v)
                elif (v == "!" or v == "~") or ((v == "+" or v == "-") and not _is_value_end(prev)):
                    if prev != null and not (prev.is_punct("(") or prev.is_punct("[") or prev.is_punct("!") or prev.is_punct("{")):
                        self.space()
                    self.write(v)
                    self.unary = true
                    prev = t
                    i += 1
                    continue
                elif v in _BINARY:
                    self.space()
                    self.write(v)
                    self.space()
                else:
                    self.write(v)
            else:
                if prev != null and t.nl_before and self.top() != "(" and self.top() != "for(" and self.top() != "[i" and self.top() != "{o" and _is_value_end(prev):
                    self.newline()
                elif prev != null and not was_unary and self._needs_space(prev, t):
                    self.space()
                self.write(v)
                if t.kind == _lex.KEYWORD and t.value in _SPACE_AFTER_KEYWORDS and nxt != null and not nxt.is_punct(";") and not nxt.is_punct(")") and not nxt.is_punct(".") and not nxt.is_punct(",") and not nxt.is_punct(":") and not (t.value == "function" and nxt.is_punct("(")):
                    self.space()
            prev = t
            i += 1
        self.newline()
        text := _s.join("", self.out)
        lines := []
        for l in _s.split(text, "\n"):
            append(lines, _rstrip(l))
        out := _s.join("\n", lines)
        while _s.ends_with(out, "\n\n"):
            out = out[0:len(out) - 1]
        if out != "" and not _s.ends_with(out, "\n"):
            out = out + "\n"
        return out

    # Après « } » de bloc : « else », « catch », « finally », « while » (do…while), « ) », « , », « ; », « . »
    # restent sur la même ligne.
    func after_close(i):
        if i >= len(self.toks):
            self.newline()
            return
        nx := self.toks[i]
        if nx.kind == _lex.KEYWORD and nx.value in ["else", "catch", "finally", "while"]:
            self.space()
            return
        if nx.is_punct(")") or nx.is_punct(",") or nx.is_punct(";") or nx.is_punct(".") or nx.is_punct("?.") or nx.is_punct("]") or nx.is_punct("("):
            return
        self.newline()

    func _class_head(i):
        j := i - 1
        while j >= 0 and j > i - 6:
            t := self.toks[j]
            if t.is_keyword("class"):
                return true
            if t.is_punct(";") or t.is_punct("}") or t.is_punct("{") or t.is_punct("="):
                return false
            j -= 1
        return false

    # « : » qui termine « case … » ou « default » (au même niveau de parenthèses).
    func _is_case_colon(i):
        depth := 0
        j := i - 1
        while j >= 0:
            t := self.toks[j]
            if t.is_punct(")") or t.is_punct("]") or t.is_punct("}"):
                depth += 1
            elif t.is_punct("(") or t.is_punct("[") or t.is_punct("{"):
                if depth == 0:
                    return false
                depth -= 1
            elif depth == 0 and t.is_punct("?"):
                return false
            elif depth == 0 and (t.is_keyword("case") or t.is_keyword("default")):
                return true
            elif depth == 0 and (t.is_punct(";") or t.is_punct(":")):
                return false
            j -= 1
        return false

    # « : » d'une clé d'objet, d'un case / default, ou d'une étiquette (pas du ternaire).
    func _is_label_or_key(i):
        depth := 0
        j := i - 1
        while j >= 0:
            t := self.toks[j]
            if t.is_punct(")") or t.is_punct("]") or t.is_punct("}"):
                depth += 1
            elif t.is_punct("(") or t.is_punct("["):
                if depth == 0:
                    return false
                depth -= 1
            elif t.is_punct("{"):
                if depth == 0:
                    return true
                depth -= 1
            elif depth == 0 and t.is_punct("?"):
                return false
            elif depth == 0 and (t.is_keyword("case") or t.is_keyword("default")):
                return true
            elif depth == 0 and (t.is_punct(",") or t.is_punct(";")):
                return true
            j -= 1
        return true

    func _needs_space(prev, t):
        if prev.kind == _lex.PUNCT:
            return prev.value in _BINARY or prev.value == "," or prev.value == ")" or prev.value == "]" or prev.value == "}"
        return true

func _rstrip(l):
    t := l
    while len(t) > 0 and (t[len(t) - 1] == ' ' or t[len(t) - 1] == '\t'):
        t = t[0:len(t) - 1]
    return t

func format(source, opts=null):
    return _F(str(source), opts if opts != null else Options()).run()

func is_formatted(source, opts=null):
    return format(source, opts) == str(source)

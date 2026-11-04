# ALEX STANDARD LIBRARY — web.js.js_validator
#
# Analyse lexicale complète de JavaScript (ES2024 : gabarits imbriqués, expressions régulières distinguées de
# la division, nombres avec « _ », BigInt, champs privés #x, hashbang) et VALIDATION d'un source : erreurs de
# syntaxe lexicale, parenthèses / crochets / accolades équilibrés, déclarations en double, mots réservés,
# risques ASI, et avertissements de SÉCURITÉ (eval, new Function, innerHTML, document.write, setTimeout avec
# une chaîne, URL javascript:). Le tokenizer sert aussi à web.js.js_formatter, js_minifier et js_import.
#
#   use web.js.js_validator as jv
#   toks := jv.tokenize("const x = a / b; const r = /ab+c/gi;")
#   [t.kind for t in toks]          # keyword identifier punct identifier punct identifier punct ...regex...
#   r := jv.validate("let a = 1;\nlet a = 2;\nel.innerHTML = saisie;\nif (a == 2 {")
#   r.is_valid()                    # false
#   for i in r.issues: print(i)     # error [redeclaration] …, warning [security-innerhtml] …, error [unbalanced] …
#   jv.is_valid("x => x * 2")      # true
#
# Erreurs : JsSyntaxError (tokenize avec strict=true sur un source mal formé).

from core use len, type
from collections use append, keys
use string as _s
use web.js.js_errors as _err
use web.js.js_types as _t

const IDENTIFIER := "identifier"
const KEYWORD := "keyword"
const PUNCT := "punct"
const NUMBER := "number"
const STRING := "string"
const TEMPLATE := "template"
const REGEX := "regex"
const LINE_COMMENT := "line-comment"
const BLOCK_COMMENT := "block-comment"
const PRIVATE := "private"
const HASHBANG := "hashbang"
const ERROR := "error"

const _PUNCTS := [">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=", "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "**", "<<", ">>"]
const _SINGLE := "{}()[];,<>+-*/%&|^!~?:=.@"
const _REGEX_AFTER_KEYWORDS := ["return", "typeof", "instanceof", "in", "of", "new", "delete", "void", "throw", "case", "do", "else", "yield", "await", "extends"]

class Token:
    func init(kind, value, line, column, start, end, nl_before=false):
        self.kind = kind
        self.value = value
        self.line = line
        self.column = column
        self.start = start
        self.end = end
        self.nl_before = nl_before      # saut de ligne entre le jeton précédent et celui-ci
        self.parts = null               # gabarit : liste de textes et de sources d'expressions (str)
        self.error = null

    func is_punct(v):
        return self.kind == PUNCT and self.value == v

    func is_keyword(v):
        return self.kind == KEYWORD and self.value == v

    func is_comment():
        return self.kind == LINE_COMMENT or self.kind == BLOCK_COMMENT

    func __str__():
        return self.kind + "(" + self.value + ")"

func _is_id_start(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '$' or c == '_' or c == '\\' or _s.ord(c) >= 128

func _is_id_part(c):
    return _is_id_start(c) or (c >= '0' and c <= '9')

func _is_digit(c):
    return c >= '0' and c <= '9'

func _is_line_term(c):
    o := _s.ord(c)
    return c == '\n' or c == '\r' or o == 0x2028 or o == 0x2029

func _is_space(c):
    o := _s.ord(c)
    return c == ' ' or c == '\t' or o == 11 or o == 12 or o == 0xA0 or o == 0xFEFF or (o >= 0x2000 and o <= 0x200A) or o == 0x202F or o == 0x205F or o == 0x3000 or o == 0x1680

class _Lexer:
    func init(src, keep_comments):
        self.src = str(src)
        self.n = len(self.src)
        self.i = 0
        self.line = 1
        self.line_start = 0
        self.keep = keep_comments
        self.out = []
        self.last = null          # dernier jeton significatif
        self.nl = false
        self.depth_stack = []     # pour « } » refermant un ${ d'un gabarit (non utilisé : gabarits lus d'un bloc)

    func col(pos):
        return pos - self.line_start + 1

    func newline_at(pos):
        self.line += 1
        self.line_start = pos + 1

    func emit(kind, value, start, line, column):
        t := Token(kind, value, line, column, start, self.i, self.nl)
        if kind != LINE_COMMENT and kind != BLOCK_COMMENT:
            self.nl = false
            self.last = t
            append(self.out, t)
        elif self.keep:
            append(self.out, t)
        return t

    func regex_allowed():
        t := self.last
        if t == null:
            return true
        if t.kind == NUMBER or t.kind == STRING or t.kind == TEMPLATE or t.kind == REGEX or t.kind == PRIVATE:
            return false
        if t.kind == IDENTIFIER:
            return false
        if t.kind == KEYWORD:
            return t.value in _REGEX_AFTER_KEYWORDS
        if t.kind == PUNCT:
            return not (t.value == ")" or t.value == "]" or t.value == "}" or t.value == "++" or t.value == "--")
        return true

    func run():
        s := self.src
        if self.n >= 2 and s[0] == '#' and s[1] == '!':
            j := 0
            while j < self.n and not _is_line_term(s[j]):
                j += 1
            self.i = j
            self.emit(HASHBANG, s[0:j], 0, 1, 1)
        while self.i < self.n:
            c := s[self.i]
            if _is_line_term(c):
                if c == '\r' and self.i + 1 < self.n and s[self.i + 1] == '\n':
                    self.i += 1
                self.newline_at(self.i)
                self.i += 1
                self.nl = true
                continue
            if _is_space(c):
                self.i += 1
                continue
            start := self.i
            line := self.line
            column := self.col(start)
            if c == '/' and self.i + 1 < self.n and s[self.i + 1] == '/':
                j := self.i
                while j < self.n and not _is_line_term(s[j]):
                    j += 1
                self.i = j
                self.emit(LINE_COMMENT, s[start:j], start, line, column)
                continue
            if c == '/' and self.i + 1 < self.n and s[self.i + 1] == '*':
                j := _s.find(s[self.i + 2:self.n], "*/")
                end := self.n if j < 0 else self.i + 2 + j + 2
                k := self.i
                while k < end:
                    if s[k] == '\n':
                        self.newline_at(k)
                        self.nl = true
                    k += 1
                self.i = end
                t := self.emit(BLOCK_COMMENT, s[start:end], start, line, column)
                if j < 0:
                    self.error_token("commentaire /* non fermé", start, line, column)
                continue
            if _is_id_start(c):
                self.word(start, line, column)
                continue
            if c == '#' and self.i + 1 < self.n and _is_id_start(s[self.i + 1]):
                self.i += 1
                j := self.i
                while j < self.n and _is_id_part(s[j]):
                    j += 1
                self.i = j
                self.emit(PRIVATE, s[start:j], start, line, column)
                continue
            if _is_digit(c) or (c == '.' and self.i + 1 < self.n and _is_digit(s[self.i + 1])):
                self.number(start, line, column)
                continue
            if c == '"' or c == '\'':
                self.string(c, start, line, column)
                continue
            if c == '`':
                self.template(start, line, column)
                continue
            if c == '/' and self.regex_allowed():
                self.regex(start, line, column)
                continue
            matched := null
            for p in _PUNCTS:
                if s[self.i:self.i + len(p)] == p:
                    matched = p
                    break
            if matched == "?." and self.i + 2 < self.n and _is_digit(s[self.i + 2]):
                matched = null
            if matched != null:
                self.i += len(matched)
                self.emit(PUNCT, matched, start, line, column)
                continue
            if _s.contains(_SINGLE, str(c)):
                self.i += 1
                self.emit(PUNCT, str(c), start, line, column)
                continue
            self.i += 1
            self.error_token("caractère inattendu « " + str(c) + " »", start, line, column)
        return self.out

    func error_token(msg, start, line, column):
        t := Token(ERROR, self.src[start:self.i], line, column, start, self.i, self.nl)
        t.error = msg
        append(self.out, t)

    func word(start, line, column):
        s := self.src
        j := self.i
        while j < self.n and _is_id_part(s[j]):
            if s[j] == '\\':
                j += 2
                while j < self.n and (s[j] == '{' or _is_id_part(s[j]) or s[j] == '}') and s[j] != '\\':
                    if s[j] == '}':
                        j += 1
                        break
                    j += 1
                continue
            j += 1
        self.i = j
        w := s[start:j]
        kind := KEYWORD if (w in _t.KEYWORDS or w in ["let", "static", "yield", "await", "enum"]) else IDENTIFIER
        # après « . » ou « ?. », un mot réservé est un nom de propriété
        if kind == KEYWORD and self.last != null and self.last.kind == PUNCT and (self.last.value == "." or self.last.value == "?."):
            kind = IDENTIFIER
        self.emit(kind, w, start, line, column)

    func number(start, line, column):
        s := self.src
        j := self.i
        if s[j] == '0' and j + 1 < self.n and (s[j + 1] in ['x', 'X', 'o', 'O', 'b', 'B']):
            j += 2
            while j < self.n and (_is_id_part(s[j])):
                j += 1
        else:
            while j < self.n and (_is_digit(s[j]) or s[j] == '_'):
                j += 1
            if j < self.n and s[j] == '.':
                j += 1
                while j < self.n and (_is_digit(s[j]) or s[j] == '_'):
                    j += 1
            if j < self.n and (s[j] == 'e' or s[j] == 'E'):
                k := j + 1
                if k < self.n and (s[k] == '+' or s[k] == '-'):
                    k += 1
                if k < self.n and _is_digit(s[k]):
                    j = k
                    while j < self.n and (_is_digit(s[j]) or s[j] == '_'):
                        j += 1
            if j < self.n and s[j] == 'n':
                j += 1
        self.i = j
        if j < self.n and _is_id_start(s[j]):
            while self.i < self.n and _is_id_part(s[self.i]):
                self.i += 1
            self.error_token("identifiant collé à un nombre « " + s[start:self.i] + " »", start, line, column)
            return
        self.emit(NUMBER, s[start:j], start, line, column)

    func string(q, start, line, column):
        s := self.src
        j := self.i + 1
        while j < self.n:
            c := s[j]
            if c == '\\':
                if j + 1 < self.n and s[j + 1] == '\r' and j + 2 < self.n and s[j + 2] == '\n':
                    self.newline_at(j + 2)
                    j += 3
                    continue
                if j + 1 < self.n and _is_line_term(s[j + 1]):
                    self.newline_at(j + 1)
                j += 2
                continue
            if c == q:
                self.i = j + 1
                self.emit(STRING, s[start:j + 1], start, line, column)
                return
            if c == '\n' or c == '\r':
                break
            j += 1
        self.i = j
        self.error_token("chaîne non terminée", start, line, column)

    # Lit un gabarit complet (expressions ${…} comprises, gabarits imbriqués) ; parts : textes / sources.
    func template(start, line, column):
        s := self.src
        parts := []
        j := self.i + 1
        chunk_start := j
        while j < self.n:
            c := s[j]
            if c == '\\':
                j += 2
                continue
            if c == '\n':
                self.newline_at(j)
            if c == '`':
                append(parts, s[chunk_start:j])
                self.i = j + 1
                t := self.emit(TEMPLATE, s[start:j + 1], start, line, column)
                t.parts = parts
                return
            if c == '$' and j + 1 < self.n and s[j + 1] == '{':
                append(parts, s[chunk_start:j])
                k := self.skip_expression(j + 2)
                if k < 0:
                    break
                append(parts, ("${", s[j + 2:k]))
                j = k + 1
                chunk_start = j
                continue
            j += 1
        self.i = self.n
        self.error_token("gabarit ` non terminé", start, line, column)

    # Fin (indice du « } ») d'une expression de gabarit, en tenant compte des chaînes, gabarits et commentaires.
    func skip_expression(pos):
        s := self.src
        depth := 0
        j := pos
        while j < self.n:
            c := s[j]
            if c == '\n':
                self.newline_at(j)
            if c == '"' or c == '\'':
                k := j + 1
                while k < self.n and s[k] != c:
                    if s[k] == '\\':
                        k += 1
                    k += 1
                j = k + 1
                continue
            if c == '`':
                k := j + 1
                while k < self.n and s[k] != '`':
                    if s[k] == '\\':
                        k += 1
                    elif s[k] == '$' and k + 1 < self.n and s[k + 1] == '{':
                        e := self.skip_expression(k + 2)
                        if e < 0:
                            return -1
                        k = e
                    k += 1
                j = k + 1
                continue
            if c == '/' and j + 1 < self.n and s[j + 1] == '/':
                while j < self.n and s[j] != '\n':
                    j += 1
                continue
            if c == '/' and j + 1 < self.n and s[j + 1] == '*':
                e := _s.find(s[j + 2:self.n], "*/")
                if e < 0:
                    return -1
                j = j + 2 + e + 2
                continue
            if c == '{':
                depth += 1
            elif c == '}':
                if depth == 0:
                    return j
                depth -= 1
            j += 1
        return -1

    func regex(start, line, column):
        s := self.src
        j := self.i + 1
        in_class := false
        while j < self.n:
            c := s[j]
            if c == '\\':
                j += 2
                continue
            if _is_line_term(c):
                break
            if c == '[':
                in_class = true
            elif c == ']':
                in_class = false
            elif c == '/' and not in_class:
                j += 1
                while j < self.n and _is_id_part(s[j]):
                    j += 1
                self.i = j
                self.emit(REGEX, s[start:j], start, line, column)
                return
            j += 1
        self.i = j
        self.error_token("expression régulière non terminée", start, line, column)

# Jetons d'un source ; keep_comments : garder les commentaires ; strict : JsSyntaxError au premier jeton invalide.
func tokenize(source, keep_comments=false, strict=false):
    toks := _Lexer(source, keep_comments).run()
    if strict:
        for t in toks:
            if t.kind == ERROR:
                _err.syntax_error("js_validator.tokenize", t.error, t.line, t.column)
    return toks

# Jetons significatifs (sans commentaires ni erreurs).
func significant(tokens):
    out := []
    for t in tokens:
        if not t.is_comment() and t.kind != ERROR and t.kind != HASHBANG:
            append(out, t)
    return out

# ---------------------------------------------------------------- validation

class Options:
    func init(security=true, style=false, module=true):
        self.security = security
        self.style = style            # infos de style (==, var, console.log)
        self.module = module          # code de module (import / export permis au niveau supérieur)

class Report:
    func init(issues):
        self.issues = issues

    func errors():
        out := []
        for i in self.issues:
            if i.level == _err.ERROR:
                append(out, i)
        return out

    func warnings():
        out := []
        for i in self.issues:
            if i.level == _err.WARNING:
                append(out, i)
        return out

    func is_valid():
        return len(self.errors()) == 0

    func codes():
        out := []
        for i in self.issues:
            append(out, i.code)
        return out

    func summary():
        return str(len(self.errors())) + " erreur(s), " + str(len(self.warnings())) + " avertissement(s)"

    func __str__():
        lines := [self.summary()]
        for i in self.issues:
            append(lines, str(i))
        return _s.join("\n", lines)

func _add(out, level, code, msg, t):
    append(out, _err.Issue(level, code, msg, t.line if t != null else null, t.column if t != null else null))

const _CLOSE := {")": "(", "]": "[", "}": "{"}
const _STATEMENT_END := [")", "]", "}"]

func _check_tokens(toks, out, opts, depth_offset):
    stack := []
    declared := {}
    i := 0
    n := len(toks)
    while i < n:
        t := toks[i]
        prev := toks[i - 1] if i > 0 else null
        nxt := toks[i + 1] if i + 1 < n else null
        if t.kind == ERROR:
            _add(out, _err.ERROR, "lexical", t.error, t)
            i += 1
            continue
        if t.kind == TEMPLATE and t.parts != null:
            for p in t.parts:
                if type(p) == "tuple":
                    sub := tokenize(p[1])
                    for st in sub:
                        st.line = st.line + t.line - 1
                    _check_tokens(significant(sub) + _errors_of(sub), out, opts, len(stack))
        if t.kind == PUNCT:
            v := t.value
            if v == "(" or v == "[" or v == "{":
                append(stack, t)
            elif v == ")" or v == "]" or v == "}":
                if len(stack) == 0:
                    _add(out, _err.ERROR, "unbalanced", "« " + v + " » sans ouverture", t)
                else:
                    top := stack[len(stack) - 1]
                    if top.value != _CLOSE[v]:
                        _add(out, _err.ERROR, "unbalanced", "« " + v + " » ferme « " + top.value + " » ouvert ligne " + str(top.line), t)
                    stack = stack[0:len(stack) - 1]
            if opts.style and (v == "==" or v == "!="):
                _add(out, _err.INFO, "eqeqeq", "« " + v + " » : préférer « " + v + "= »", t)
            if opts.security and v == "=" and prev != null and prev.kind == IDENTIFIER and prev.value in ["innerHTML", "outerHTML"] and i >= 2 and toks[i - 2].is_punct("."):
                _add(out, _err.WARNING, "security-innerhtml", "affectation de " + prev.value + " : risque d'injection (XSS), préférer textContent", t)
            # ASI : ligne qui commence par ( ou [ après une expression sans « ; »
            if (v == "(" or v == "[" or v == "`") and t.nl_before and prev != null and (prev.kind == IDENTIFIER or prev.kind == NUMBER or prev.kind == STRING or (prev.kind == PUNCT and (prev.value == ")" or prev.value == "]"))):
                _add(out, _err.WARNING, "asi-hazard", "ligne commençant par « " + v + " » rattachée à la précédente (point-virgule manquant ?)", t)
        if t.kind == KEYWORD:
            w := t.value
            if (w == "let" or w == "const" or w == "var" or w == "class" or w == "function") and nxt != null and nxt.kind == KEYWORD and not (w == "function" and nxt.is_punct("*")) and not (w == "let" and nxt.value in ["in", "of", "instanceof"]):
                _add(out, _err.ERROR, "reserved-word", "« " + nxt.value + " » est un mot réservé et ne peut pas nommer une déclaration", nxt)
            if (w == "const" or w == "var" or (w == "let" and opts.module)) and nxt != null and not (nxt.kind == IDENTIFIER or nxt.kind == KEYWORD or nxt.is_punct("{") or nxt.is_punct("[")) and not (prev != null and (prev.is_punct(".") or prev.is_punct("?."))):
                _add(out, _err.ERROR, "declaration", "nom de variable attendu après « " + w + " »", nxt)
            if (w == "let" or w == "const" or w == "class") and nxt != null and nxt.kind == IDENTIFIER and len(stack) + depth_offset == 0:
                if nxt.value in declared:
                    _add(out, _err.ERROR, "redeclaration", "« " + nxt.value + " » déjà déclaré ligne " + str(declared[nxt.value]), nxt)
                else:
                    declared[nxt.value] = nxt.line
            if w == "return" and nxt != null and nxt.nl_before and not nxt.is_punct("}") and not nxt.is_punct(";"):
                _add(out, _err.WARNING, "return-newline", "saut de ligne après « return » : la valeur de la ligne suivante est ignorée", t)
            if w == "with":
                _add(out, _err.WARNING if opts.module else _err.INFO, "with", "« with » est interdit en mode strict (modules)", t)
            if w == "debugger" and opts.style:
                _add(out, _err.INFO, "debugger", "instruction « debugger » laissée dans le code", t)
            if opts.style and w == "var":
                _add(out, _err.INFO, "no-var", "« var » : préférer let ou const", t)
            if opts.security and w == "new" and nxt != null and nxt.value == "Function":
                _add(out, _err.WARNING, "security-eval", "new Function(…) évalue du texte comme du code", t)
            if (w == "import" or w == "export") and not opts.module and len(stack) == 0 and not (nxt != null and (nxt.is_punct("(") or nxt.is_punct("."))):
                _add(out, _err.ERROR, "module-syntax", "« " + w + " » hors d'un module", t)
        if t.kind == IDENTIFIER and opts.security:
            w := t.value
            calls := nxt != null and nxt.is_punct("(")
            after_dot := prev != null and (prev.is_punct(".") or prev.is_punct("?."))
            if w == "eval" and calls and not after_dot:
                _add(out, _err.WARNING, "security-eval", "eval(…) évalue du texte comme du code", t)
            if (w == "setTimeout" or w == "setInterval") and calls and i + 2 < n and toks[i + 2].kind == STRING:
                _add(out, _err.WARNING, "security-eval", w + " avec une chaîne évalue du code", t)
            if w == "write" and after_dot and i >= 2 and toks[i - 2].value == "document" and calls:
                _add(out, _err.WARNING, "security-document-write", "document.write(…) : risque d'injection et blocage du rendu", t)
            if w == "insertAdjacentHTML" and calls:
                _add(out, _err.WARNING, "security-innerhtml", "insertAdjacentHTML : risque d'injection (XSS)", t)
            if w == "__proto__":
                _add(out, _err.WARNING, "proto", "__proto__ : préférer Object.getPrototypeOf / setPrototypeOf", t)
            if opts.style and w == "console" and nxt != null and nxt.is_punct(".") :
                _add(out, _err.INFO, "console", "appel à console laissé dans le code", t)
        if t.kind == STRING and opts.security and _s.starts_with(_s.lower(_s.trim(t.value[1:len(t.value)])), "javascript:"):
            _add(out, _err.WARNING, "security-javascript-url", "URL « javascript: » dans une chaîne", t)
        i += 1
    for o in stack:
        _add(out, _err.ERROR, "unbalanced", "« " + o.value + " » non fermé", o)

func _errors_of(toks):
    out := []
    for t in toks:
        if t.kind == ERROR:
            append(out, t)
    return out

# Valide un source -> Report (niveau error : le code ne s'exécuterait pas ; warning : risque ; info : style).
func validate(source, opts=null):
    o := opts if opts != null else Options()
    out := []
    toks := tokenize(source)
    _check_tokens(toks, out, o, 0)
    return Report(out)

func is_valid(source, opts=null):
    return validate(source, opts).is_valid()

func assert_valid(source, opts=null):
    r := validate(source, opts)
    if not r.is_valid():
        e := r.errors()[0]
        _err.syntax_error("js_validator", e.message, e.line, e.column)
    return r

# Identifiants globaux probablement non déclarés (lus mais jamais déclarés, ni globaux connus).
func free_identifiers(source):
    toks := significant(tokenize(source))
    declared := []
    used := []
    i := 0
    while i < len(toks):
        t := toks[i]
        prev := toks[i - 1] if i > 0 else null
        nxt := toks[i + 1] if i + 1 < len(toks) else null
        if t.kind == KEYWORD and t.value in ["let", "const", "var", "function", "class"] and nxt != null and nxt.kind == IDENTIFIER:
            append(declared, nxt.value)
        elif t.kind == IDENTIFIER:
            is_prop := prev != null and (prev.is_punct(".") or prev.is_punct("?."))
            is_key := nxt != null and nxt.is_punct(":") and prev != null and (prev.is_punct("{") or prev.is_punct(","))
            is_param := nxt != null and (nxt.is_punct("=>") or ((nxt.is_punct(",") or nxt.is_punct(")")) and _in_params(toks, i)))
            if is_param:
                append(declared, t.value)
            elif not is_prop and not is_key and not (t.value in used):
                append(used, t.value)
        i += 1
    out := []
    for u in used:
        if not (u in declared) and not (u in _t.GLOBALS) and not (u in _t.CONTEXTUAL):
            append(out, u)
    return out

func _in_params(toks, i):
    # l'identifiant est-il dans une liste « ( a, b ) => » ou « function f(a, b) » ?
    j := i
    while j >= 0 and not toks[j].is_punct("("):
        if toks[j].is_punct(")") or toks[j].is_punct(";") or toks[j].is_punct("{"):
            return false
        j -= 1
    if j < 0:
        return false
    k := i
    while k < len(toks) and not toks[k].is_punct(")"):
        k += 1
    if k + 1 < len(toks) and toks[k + 1].is_punct("=>"):
        return true
    if j >= 1 and (toks[j - 1].kind == IDENTIFIER or toks[j - 1].is_keyword("function")) and j >= 2 and (toks[j - 2].is_keyword("function") or toks[j - 1].is_keyword("function")):
        return true
    return false

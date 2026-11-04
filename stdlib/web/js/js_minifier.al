# ALEX STANDARD LIBRARY — web.js.js_minifier
#
# Minification de JavaScript par jetons (web.js.js_validator.tokenize) : commentaires retirés (sauf « /*! »
# de licence), espaces réduits au strict nécessaire (jamais « a+ +b » fusionné en « a++b »), sauts de ligne
# gardés seulement là où l'insertion automatique de points-virgules (ASI) en dépend, nombres raccourcis
# (1.0 -> 1, 0.50 -> .5), et rapport de taille. Le code n'est jamais restructuré : pas de renommage.
#
#   use web.js.js_minifier as mini
#   mini.minify("function f ( a , b ) {\n  // somme\n  return a + b ;\n}")    # function f(a,b){return a+b;}
#   mini.minify("let a = 1\nlet b = a\n(b)")        # let a=1\nlet b=a\n(b)   (sauts de ligne significatifs gardés)
#   r := mini.minify_report(source)
#   r.ratio                                          # taille finale / taille d'origine
#   mini.Options(false)                              # options : keep_licenses, shorten_numbers
#
# Erreurs : JsSyntaxError (source lexicalement invalide : chaîne, gabarit ou commentaire non fermé).

from core use len, type
from collections use append
use string as _s
use web.js.js_errors as _err
use web.js.js_validator as _lex

class Options:
    func init(keep_licenses=true, shorten_numbers=true):
        self.keep_licenses = keep_licenses
        self.shorten_numbers = shorten_numbers

class Report:
    func init(code, original_size):
        self.code = code
        self.original_size = original_size
        self.size = len(code)
        self.saved = original_size - self.size
        self.ratio = (self.size / original_size) if original_size > 0 else 1.0

    func __str__():
        return str(self.original_size) + " -> " + str(self.size) + " caractères"

func _id_char(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '$' or c == '_' or c == '\\' or c == '#' or _s.ord(c) >= 128

# Deux jetons accolés se confondraient-ils ?
func needs_space(a, b):
    if a == "" or b == "":
        return false
    x := a[len(a) - 1]
    y := b[0]
    if _id_char(x) and _id_char(y):
        return true
    if (x == '+' and (y == '+')) or (x == '-' and (y == '-')):
        return true
    if x == '/' and (y == '/' or y == '*'):
        return true
    if _is_digit_text(a) and y == '.':
        return true
    if y == '.' and len(b) > 1 and b[1] >= '0' and b[1] <= '9' and _id_char(x):
        return true
    if x == '<' and y == '!':
        return true
    if x == '-' and b[0:1] == ">" and _s.ends_with(a, "--"):
        return true
    return false

func _is_digit_text(t):
    if len(t) == 0:
        return false
    for c in t:
        if not ((c >= '0' and c <= '9') or c == '_'):
            return false
    return true

const _END_KINDS := ["identifier", "number", "string", "template", "regex", "private"]
const _END_KEYWORDS := ["this", "true", "false", "null", "super", "return", "break", "continue", "yield", "debugger"]
const _END_PUNCTS := [")", "]", "}", "++", "--"]
const _START_PUNCTS := ["(", "[", "{", "++", "--", "!", "~", "+", "-", "/", "`", "@", "#", "..."]

func _can_end(t):
    if t.kind in _END_KINDS:
        return true
    if t.kind == _lex.KEYWORD:
        return t.value in _END_KEYWORDS
    if t.kind == _lex.PUNCT:
        return t.value in _END_PUNCTS
    return false

func _can_start(t):
    if t.kind == _lex.PUNCT:
        return t.value in _START_PUNCTS
    return true

# Nombre raccourci sans changer sa valeur (« 1.50 » -> « 1.5 », « 0.5 » -> « .5 », « 1.0 » -> « 1 »).
func shorten_number(text):
    t := text
    if _s.contains(t, "_"):
        return t
    low := _s.lower(t)
    if _s.starts_with(low, "0x") or _s.starts_with(low, "0o") or _s.starts_with(low, "0b") or _s.ends_with(low, "n") or _s.contains(low, "e"):
        return t
    if not _s.contains(t, "."):
        return t
    parts := _s.split(t, ".")
    ip := parts[0]
    fp := parts[1]
    while len(fp) > 0 and fp[len(fp) - 1] == '0':
        fp = fp[0:len(fp) - 1]
    while len(ip) > 1 and ip[0] == '0':
        ip = ip[1:len(ip)]
    if fp == "":
        return ip if ip != "" else "0"
    if ip == "0" or ip == "":
        return "." + fp
    return ip + "." + fp

func minify_report(source, opts=null):
    o := opts if opts != null else Options()
    src := str(source)
    toks := _lex.tokenize(src, true)
    for t in toks:
        if t.kind == _lex.ERROR:
            _err.syntax_error("js_minifier", t.error, t.line, t.column)
    out := []
    prev_text := ""
    prev := null
    pending_nl := false
    for t in toks:
        if t.kind == _lex.LINE_COMMENT or t.kind == _lex.BLOCK_COMMENT:
            if o.keep_licenses and t.kind == _lex.BLOCK_COMMENT and _s.starts_with(t.value, "/*!"):
                if len(out) > 0:
                    append(out, "\n")
                append(out, t.value)
                append(out, "\n")
                prev_text = ""
                prev = null
            if t.kind == _lex.LINE_COMMENT or _s.contains(t.value, "\n"):
                pending_nl = true
            continue
        if t.kind == _lex.HASHBANG:
            append(out, t.value + "\n")
            continue
        text := t.value
        if t.kind == _lex.NUMBER and o.shorten_numbers:
            text = shorten_number(text)
        nl := (t.nl_before or pending_nl) and prev != null and _can_end(prev) and _can_start(t)
        if prev != null and prev.kind == _lex.KEYWORD and prev.value in ["return", "break", "continue", "throw", "yield"] and (t.nl_before or pending_nl):
            nl = true
        if nl:
            append(out, "\n")
        elif needs_space(prev_text, text):
            append(out, " ")
        append(out, text)
        prev_text = text
        prev = t
        pending_nl = false
    code := _s.join("", out)
    return Report(_s.trim(code), len(src))

func minify(source, opts=null):
    return minify_report(source, opts).code

# ALEX — commands.lang_service
#
# Service de langage (IntelliSense) écrit en ALEX, port de alex::tooling::LanguageService (LanguageService.cpp) :
# index des symboles d'un fichier à partir du vrai lexer / parser du compilateur ALEX (src/lexer, src/parser),
# avec réparation des lignes fautives pendant la frappe ; résolution des noms (portées, classes, modules
# importés) ; diagnostics du compilateur (analyse, types, modules) et avertissements ; complétion, survol,
# signature, définition, références, renommage, symboles, mise en forme, actions rapides. Utilisé par `alexc lsp`.
#
#   use commands.lang_service as ls
#   svc := ls.LanguageService("stdlib", "/chemin/projet")
#   svc.open("/chemin/projet/main.al", texte)
#   diags := svc.diagnostics("/chemin/projet/main.al")
#   items := svc.complete("/chemin/projet/main.al", 3, 10)
#
# Positions : ligne à partir de 0, colonne en OCTETS UTF-8 à partir de 0 (le serveur LSP convertit).
# Erreurs : aucune levée par les requêtes (résultats vides).

from core use len, type, to_int
from collections use append
use string as _s
use os as _os
use io as _io
use commands.common as cc
use lexer as _lx
use parser as _bp
use resolver as _bm

# ------------------------------------------------------------------------------------------------ octets

func blen(s):
    return _s.byte_len(s)

func bat(s, i):
    return _s.byte_at(s, i)

func bsub(s, a, b):
    n := blen(s)
    if a < 0:
        a = 0
    if b > n:
        b = n
    if a >= b:
        return ""
    return _s.byte_slice(s, a, b)

func bfind(s, sub, frm=0):
    n := blen(s)
    if frm > n:
        return -1
    if frm <= 0:
        return _s.byte_find(s, sub)
    p := _s.byte_find(_s.byte_slice(s, frm, n), sub)
    return -1 if p < 0 else p + frm

func brfind(s, sub):
    n := blen(s)
    m := blen(sub)
    i := n - m
    while i >= 0:
        if _s.byte_slice(s, i, i + m) == sub:
            return i
        i -= 1
    return -1

func is_ident_byte(b):
    return (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or (b >= 48 and b <= 57) or b == 95 or b >= 128

func trim(s):
    n := blen(s)
    a := 0
    while a < n and _is_space(bat(s, a)):
        a += 1
    b := n
    while b > a and _is_space(bat(s, b - 1)):
        b -= 1
    return bsub(s, a, b)

func _is_space(c):
    return c == 32 or (c >= 9 and c <= 13)

func starts_with(s, p):
    return blen(s) >= blen(p) and bsub(s, 0, blen(p)) == p

func ends_with(s, p):
    return blen(s) >= blen(p) and bsub(s, blen(s) - blen(p), blen(s)) == p

func lower(s):
    out := []
    for b in _s.byte_unpack(s):
        append(out, b + 32 if b >= 65 and b <= 90 else b)
    return _s.byte_pack(out)

# Correspondance floue : préfixe (insensible à la casse) ou sous-suite.
func fuzzy(candidate, query):
    if query == "":
        return true
    c := lower(candidate)
    q := lower(query)
    if starts_with(c, q):
        return true
    j := 0
    nq := blen(q)
    for ch in _s.byte_unpack(c):
        if j < nq and ch == bat(q, j):
            j += 1
    return j == nq and nq >= 2

const KEYWORDS := ["and", "as", "async", "await", "break", "catch", "class", "const", "continue", "elif", "else", "enum",
    "extends", "false", "finally", "for", "from", "func", "if", "implements", "in", "interface", "match", "not",
    "null", "or", "return", "self", "struct", "super", "true", "try", "use", "while"]

const RESERVED := {"and": true, "as": true, "async": true, "await": true, "break": true, "catch": true, "class": true, "const": true,
    "continue": true, "elif": true, "else": true, "enum": true, "extends": true, "false": true, "finally": true,
    "for": true, "from": true, "func": true, "if": true, "import": true, "in": true, "interface": true, "let": true,
    "match": true, "not": true, "null": true, "or": true, "return": true, "self": true, "struct": true, "super": true,
    "true": true, "try": true, "use": true, "while": true, "yield": true}

func is_identifier(s):
    if s == "":
        return false
    c0 := bat(s, 0)
    if c0 >= 48 and c0 <= 57:
        return false
    for b in _s.byte_unpack(s):
        if not is_ident_byte(b):
            return false
    return true

func kind_name(k):
    if k in _KIND_FR:
        return _KIND_FR[k]
    return "symbole"

const _KIND_FR := {"module": "module", "class": "classe", "struct": "struct", "interface": "interface", "enum": "enum",
    "variant": "variante", "function": "fonction", "method": "méthode", "field": "champ", "variable": "variable",
    "constant": "constante", "parameter": "paramètre", "builtin": "intégrée", "keyword": "mot-clé", "snippet": "modèle"}

const _WIN := _os.platform() == "windows"

func canonical(path):
    if path == "":
        return path
    if _WIN:
        # lecteur (D:\...), UNC (\\serveur\partage), « / » ou « \ » : os.absolute rend un chemin absolu normalisé
        w := _os.absolute(path)
        try:
            if _os.exists(w):
                return _os.realpath(w)
        catch e:
            return w
        return w
    a := path
    if not starts_with(a, "/"):
        a = _bm.lexically_normal(_os.cwd() + "/" + a)
    else:
        a = _bm.lexically_normal(a)
    # weakly_canonical : partie existante résolue (liens), reste conservé
    try:
        if _os.exists(a):
            return _os.realpath(a)
    catch e:
        return a
    head := _bm._parent(a)
    tail := bsub(a, blen(head), blen(a))
    if head != "" and head != a and _os.exists(head):
        try:
            return _bm.lexically_normal(_os.realpath(head) + tail)
        catch e:
            return a
    return a

# Clé d'un chemin : « / » comme séparateur (aussi sous Windows), sans « / » final.
func path_key(p):
    if _WIN:
        p = _s.replace(p, "\\", "/")
    n := blen(p)
    while n > 1 and bat(p, n - 1) == 47:
        n -= 1
    return bsub(p, 0, n)

func path_is_under(path, d):
    if d == "":
        return false
    pk := path_key(path)
    dk := path_key(d)
    if blen(pk) < blen(dk) or bsub(pk, 0, blen(dk)) != dk:
        return false
    return blen(pk) == blen(dk) or bat(pk, blen(dk)) == 47 or dk == "/"

func path_relative_to(path, d):
    if not path_is_under(path, d):
        return path
    pk := path_key(path)
    dk := path_key(d)
    k := blen(dk) + (0 if dk == "/" else 1)
    if k >= blen(pk):
        return ""
    return bsub(pk, k, blen(pk))

# ------------------------------------------------------------------------------------------------ index

class Symbol:
    func init(id, name, kind, line, col, end_line, scope):
        self.id = id
        self.name = name
        self.kind = kind
        self.line = line
        self.col = col
        self.end_line = end_line
        self.scope = scope
        self.detail = ""
        self.doc = ""
        self.type_name = ""
        self.container = ""
        self.params = []
        self.import_file = ""
        self.import_name = ""
        self.module_path = ""
        self.base_class = ""
        self.is_import = false

class Scope:
    func init(parent, start, end, kind, class_name, owner):
        self.parent = parent
        self.start = start
        self.end = end
        self.kind = kind
        self.class_name = class_name
        self.owner = owner

class Occ:
    func init(line, col, ln, name, scope):
        self.line = line
        self.col = col
        self.len = ln
        self.name = name
        self.scope = scope
        self.is_member = false
        self.object_name = ""
        self.object_occ = -1
        self.is_decl = false
        self.decl_sym = -1

class FileIndex:
    func init(path, text):
        self.path = path
        self.text = text
        self.lines = []
        self.parsed = false
        self.repaired = false
        self.symbols = []
        self.scopes = []
        self.occ = []
        self.version = 0
        self.stamp = 0

# Position (0-based) du premier délimiteur ouvrant jamais refermé (chaînes et commentaires ignorés), [-1, -1] sinon.
func unclosed_delimiter(text):
    stack := []
    line := 0
    col := 0
    b := _s.byte_unpack(text)
    n := len(b)
    i := 0
    while i < n:
        c := b[i]
        if c == 10:
            line += 1
            col = 0
            i += 1
            continue
        if c == 35:
            while i + 1 < n and b[i + 1] != 10:
                i += 1
            i += 1
            continue
        if c == 34 or c == 39:
            triple := i + 2 < n and b[i + 1] == c and b[i + 2] == c
            j := i + (3 if triple else 1)
            l := line
            cl := col + (3 if triple else 1)
            while j < n:
                if b[j] == 92:
                    j += 2
                    cl += 2
                    continue
                if b[j] == 10:
                    if not triple:
                        break
                    l += 1
                    cl = 0
                    j += 1
                    continue
                if b[j] == c and (not triple or (j + 2 < n and b[j + 1] == c and b[j + 2] == c)):
                    j += 3 if triple else 1
                    cl += 3 if triple else 1
                    break
                j += 1
                cl += 1
            i = j
            line = l
            col = cl
            continue
        if c == 40 or c == 91 or c == 123:
            append(stack, [line, col])
        elif (c == 41 or c == 93 or c == 125) and len(stack) > 0:
            stack = stack[0:len(stack) - 1]
        col += 1
        i += 1
    if len(stack) == 0:
        return [-1, -1]
    return stack[0]

func _err_pos(msg):
    # « fichier:ligne:colonne: message » -> ligne (1-based), 0 si absente
    n := blen(msg)
    i := 0
    while i < n:
        if bat(msg, i) == 58:
            j := i + 1
            while j < n and bat(msg, j) >= 48 and bat(msg, j) <= 57:
                j += 1
            if j > i + 1 and j < n and bat(msg, j) == 58:
                k := j + 1
                while k < n and bat(msg, k) >= 48 and bat(msg, k) <= 57:
                    k += 1
                if k > j + 1 and k < n and bat(msg, k) == 58:
                    return to_int(bsub(msg, i + 1, j))
        i += 1
    return 0

# Analyse avec réparation : la ligne fautive est remplacée par « 0 » (même indentation) et l'on réessaie.
# Renvoie [programme ou null, réparé].
func parse_repaired(path, text0):
    text := text0
    repaired := false
    attempt := 0
    while attempt < 16:
        attempt += 1
        err_line := -1
        prog := null
        try:
            prog = _bp.parse_text(text, path)
        catch e:
            if e.type != "SyntaxError" and e.type != "IndentationError":
                return [null, repaired]
            err_line = _err_pos(e.message)
            if _s.contains(e.message, "délimiteur non refermé"):
                u := unclosed_delimiter(text)
                if u[0] >= 0:
                    err_line = u[0] + 1
        if prog != null:
            return [prog, repaired]
        lines := cc.split_lines(text)
        if err_line < 1 or err_line > len(lines):
            return [null, repaired]
        idx := err_line - 1
        while idx > 0 and (trim(lines[idx]) == "" or trim(lines[idx]) == "0"):
            idx -= 1
        L := lines[idx]
        ind := 0
        while ind < blen(L) and (bat(L, ind) == 32 or bat(L, ind) == 9):
            ind += 1
        t := trim(L)
        if t == "0" or t == "if 0:":
            return [null, repaired]
        next_ind := -1
        k := idx + 1
        while k < len(lines):
            if trim(lines[k]) != "":
                m := 0
                while m < blen(lines[k]) and (bat(lines[k], m) == 32 or bat(lines[k], m) == 9):
                    m += 1
                next_ind = m
                break
            k += 1
        repl := "0"
        if next_ind > ind:
            repl = "if 0:"
            if starts_with(t, "func ") and _word(t, 5) != "":
                repl = "func " + _word(t, 5) + "():"
            elif starts_with(t, "async func ") and _word(t, 11) != "":
                repl = "async func " + _word(t, 11) + "():"
            elif starts_with(t, "class ") and _word(t, 6) != "":
                repl = "class " + _word(t, 6) + ":"
            if trim(L) == repl:
                repl = "if 0:"
        lines[idx] = bsub(L, 0, ind) + repl
        text = _s.join("\n", lines)
        repaired = true
    return [null, repaired]

func _word(t, frm):
    a := frm
    while a < blen(t) and bat(t, a) == 32:
        a += 1
    b := a
    while b < blen(t):
        c := bat(t, b)
        if not ((c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 95):
            break
        b += 1
    return bsub(t, a, b)

func type_text(t):
    if t == null:
        return ""
    s := ""
    if t.name == "func":
        s = "func("
        i := 0
        while i + 1 < len(t.args):
            s += (", " if i > 0 else "") + type_text(t.args[i])
            i += 1
        s += ")"
        if len(t.args) > 0 and t.args[len(t.args) - 1].name != "any":
            s += " -> " + type_text(t.args[len(t.args) - 1])
    else:
        s = t.name
        if len(t.args) > 0:
            s += "[" + _s.join(", ", [type_text(a) for a in t.args]) + "]"
    return s + "?" if t.nullable else s

func _upper0(n):
    return blen(n) > 0 and bat(n, 0) >= 65 and bat(n, 0) <= 90

func infer_type(e):
    if e == null:
        return ""
    k := e.kind
    if k == "CallExpr":
        c := e.callee
        if c.kind == "Identifier":
            n := c.name
            if _upper0(n):
                return n
            if n != "":
                return "=" + n
        if c.kind == "MemberExpr":
            if c.object.kind == "Identifier" and c.member != "":
                q := c.object.name + "." + c.member
                if _upper0(c.member):
                    return q
                return "=" + q
    if k == "ListLiteral" or k == "ComprehensionExpr":
        return "list"
    if k == "DictLiteral":
        return "dict"
    if k == "Literal":
        lk := e.literal_kind
        if lk == "Integer":
            return "int"
        if lk == "Float":
            return "float"
        if lk == "Boolean":
            return "bool"
        if lk == "String":
            return "str"
        if lk == "Char":
            return "char"
        return ""
    if k == "FStringLiteral":
        return "str"
    return ""

func return_type_of(b):
    if b == null:
        return ""
    for n in b.statements:
        t := ""
        k := n.kind
        if k == "ReturnStmt":
            t = infer_type(n.value)
        elif k == "IfStmt":
            t = return_type_of(n.then_block)
            for e in n.elif_clauses:
                if t == "":
                    t = return_type_of(e.body)
            if t == "":
                t = return_type_of(n.else_block)
        elif k == "WhileStmt" or k == "ForStmt":
            t = return_type_of(n.body)
        elif k == "TryStmt":
            t = return_type_of(n.try_block)
        if t != "":
            return t
    return ""

func split_params(s):
    out := []
    cur := []
    depth := 0
    in_str := false
    q := 0
    for c in _s.byte_unpack(s):
        if in_str:
            append(cur, c)
            if c == q:
                in_str = false
            continue
        if c == 34 or c == 39:
            in_str = true
            q = c
        if c == 40 or c == 91 or c == 123:
            depth += 1
        if c == 41 or c == 93 or c == 125:
            depth -= 1
        if c == 44 and depth == 0:
            append(out, trim(_s.byte_pack(cur)))
            cur = []
            continue
        append(cur, c)
    last := trim(_s.byte_pack(cur))
    if last != "":
        append(out, last)
    return out

func last_line(n):
    if n == null:
        return 0
    m := n.line
    k := n.kind
    if k == "Block":
        for s in n.statements:
            m = _max(m, last_line(s))
    elif k == "FunctionDecl" or k == "ClassDecl" or k == "StructDecl" or k == "InterfaceDecl":
        if n.body != null:
            for s in n.body.statements:
                m = _max(m, last_line(s))
    elif k == "EnumDecl":
        for mb in n.members:
            m = _max(m, mb.line)
    elif k == "IfStmt":
        m = _max(m, last_line(n.then_block))
        for e in n.elif_clauses:
            m = _max(m, last_line(e.body))
        m = _max(m, last_line(n.else_block))
    elif k == "WhileStmt" or k == "ForStmt":
        m = _max(m, last_line(n.body))
    elif k == "TryStmt":
        m = _max(m, last_line(n.try_block))
        for c in n.catch_clauses:
            m = _max(m, last_line(c.body))
        m = _max(m, last_line(n.finally_block))
    elif k == "MatchStmt":
        for c in n.cases:
            m = _max(m, last_line(c.body))
    elif k == "VariableDecl" or k == "ConstDecl" or k == "Assignment" or k == "ReturnStmt":
        m = _max(m, last_line(n.value))
    elif k == "ExpressionStmt":
        m = _max(m, last_line(n.expr))
    elif k == "CallExpr":
        m = _max(m, last_line(n.callee))
        for a in n.arguments:
            m = _max(m, last_line(a.value))
    elif k == "ListLiteral":
        for e in n.elements:
            m = _max(m, last_line(e))
    elif k == "DictLiteral":
        for kv in n.entries:
            m = _max(m, last_line(kv.key))
            m = _max(m, last_line(kv.value))
    elif k == "LambdaExpr":
        m = _max(m, last_line(n.function))
    elif k == "BinaryExpr":
        m = _max(m, last_line(n.left))
        m = _max(m, last_line(n.right))
    return m

func _max(a, b):
    return a if a > b else b

func _min(a, b):
    return a if a < b else b

class Builder:
    func init(fi, resolve_import):
        self.fi = fi
        self.resolve_import = resolve_import
        self.cur = 0
        self.class_name = ""
        self.class_sym = -1
        self.class_scope = -1
        self.in_class_body = false

    func find_name(line0, col0, name, max_lines=3):
        lines := self.fi.lines
        nb := blen(name)
        l := line0
        while l < len(lines) and l < line0 + max_lines:
            t := lines[l]
            frm := col0 if (l == line0 and col0 > 0) else 0
            while true:
                p := bfind(t, name, frm)
                if p < 0:
                    break
                ok_l := p == 0 or not is_ident_byte(bat(t, p - 1))
                ok_r := p + nb >= blen(t) or not is_ident_byte(bat(t, p + nb))
                if ok_l and ok_r:
                    return [l, p]
                frm = p + 1
            l += 1
        return [line0, 0 if col0 < 0 else col0]

    func doc_above(line0):
        out := []
        l := line0 - 1
        while l >= 0:
            t := trim(self.fi.lines[l])
            if t == "" or bat(t, 0) != 35:
                break
            body := trim(bsub(t, 1, blen(t)))
            if body != "alex: native":
                append(out, body)
            l -= 1
        res := ""
        k := len(out) - 1
        while k >= 0:
            if res != "":
                res += "\n"
            res += out[k]
            k -= 1
        return res

    func header_params(line0, name_col, name):
        text := []
        depth := 0
        started := false
        lines := self.fi.lines
        l := line0
        while l < len(lines) and l < line0 + 30:
            t := lines[l]
            n := blen(t)
            k := name_col + blen(name) if l == line0 else 0
            while k < n:
                c := bat(t, k)
                if not started:
                    if c == 40:
                        started = true
                        depth = 1
                    k += 1
                    continue
                if c == 40 or c == 91 or c == 123:
                    depth += 1
                if c == 41 or c == 93 or c == 125:
                    depth -= 1
                    if depth == 0:
                        after := bsub(t, k + 1, n)
                        arrow := bfind(after, "->")
                        ret := ""
                        if arrow >= 0:
                            ret = bsub(after, arrow + 2, blen(after))
                            colon := brfind(ret, ":")
                            if colon >= 0:
                                ret = bsub(ret, 0, colon)
                            ret = trim(ret)
                        return [trim(_s.byte_pack(text)), ret]
                append(text, c)
                k += 1
            if started:
                append(text, 32)
            l += 1
        return [trim(_s.byte_pack(text)), ""]

    func new_scope(kind, start, end, owner):
        append(self.fi.scopes, Scope(self.cur, start, end, kind, self.class_name, owner))
        return len(self.fi.scopes) - 1

    func declare(name, kind, line0, col0, end0, scope):
        s := Symbol(len(self.fi.symbols), name, kind, line0, col0, end0, scope)
        append(self.fi.symbols, s)
        o := Occ(line0, col0, blen(name), name, scope)
        o.is_decl = true
        o.decl_sym = s.id
        append(self.fi.occ, o)
        return s.id

    func fix_position(line0, col0, name):
        lines := self.fi.lines
        if line0 < 0 or line0 >= len(lines):
            return null
        t := lines[line0]
        nb := blen(name)
        if col0 >= 0 and col0 + nb <= blen(t) and bsub(t, col0, col0 + nb) == name:
            return [line0, col0]
        p := self.find_name(line0, _max(0, col0 - 2), name, 1)
        if p[0] == line0 and p[1] + nb <= blen(t) and bsub(t, p[1], p[1] + nb) == name:
            return p
        return null

    func reference(name, line1, col1, member=false, object_occ=-1, object_name=""):
        p := self.fix_position(line1 - 1, col1 - 1, name)
        if p == null:
            return -1
        o := Occ(p[0], p[1], blen(name), name, self.cur)
        o.is_member = member
        o.object_name = object_name
        o.object_occ = object_occ
        append(self.fi.occ, o)
        return len(self.fi.occ) - 1

    func block(b, kind="block"):
        if b == null:
            return
        start := 0 if len(b.statements) == 0 else b.statements[0].line - 1
        end := last_line(b) - 1
        saved := self.cur
        self.cur = self.new_scope(kind, start, start if end < start else end, -1)
        self.stmts(b.statements)
        self.cur = saved

    func stmts(lst):
        for s in lst:
            self.stmt(s)

    func function(f, method, lam):
        line0 := f.line - 1
        sym := -1
        if not lam:
            pos := self.find_name(line0, f.column - 1 + 4, f.name)
            sym = self.declare(f.name, "method" if method else "function", pos[0], pos[1], last_line(f) - 1, self.cur)
            s := self.fi.symbols[sym]
            hp := self.header_params(pos[0], pos[1], f.name)
            s.params = split_params(hp[0])
            ret := type_text(f.return_type) if f.return_type != null else hp[1]
            s.detail = ("async " if f.is_async else "") + "func " + f.name + "(" + hp[0] + ")" + ("" if ret == "" else " -> " + ret)
            s.type_name = ret
            s.doc = self.doc_above(f.line - 1)
            if method:
                s.container = self.class_name
        saved := self.cur
        saved_body := self.in_class_body
        self.in_class_body = false
        self.cur = self.new_scope("lambda" if lam else "function", f.line - 1, last_line(f) - 1, sym)
        for p in f.params:
            pl := p.line - 1 if p.line > 0 else f.line - 1
            pc := p.column - 1 if p.column > 0 else 0
            fp := self.fix_position(pl, pc, p.name)
            if fp == null:
                fp = self.find_name(f.line - 1, 0, p.name)
            ps := self.declare(p.name, "parameter", fp[0], fp[1], fp[0], self.cur)
            self.fi.symbols[ps].type_name = type_text(p.type)
            self.fi.symbols[ps].detail = p.name + (": " + type_text(p.type) if p.type != null else "")
            if p.default_value != null:
                self.expr(p.default_value)
        if f.body != null:
            self.stmts(f.body.statements)
        if sym >= 0 and self.fi.symbols[sym].type_name == "" and f.body != null:
            self.fi.symbols[sym].type_name = return_type_of(f.body)
        self.cur = saved
        self.in_class_body = saved_body

    func type_body(name, kind, n, body, base, interfaces):
        line0 := n.line - 1
        pos := self.find_name(line0, n.column - 1 + 1, name)
        sym := self.declare(name, kind, pos[0], pos[1], last_line(n) - 1, self.cur)
        self.fi.symbols[sym].doc = self.doc_above(line0)
        detail := ("class " if kind == "class" else "struct " if kind == "struct" else "interface ") + name
        if base != null:
            self.fi.symbols[sym].base_class = base
            detail += " extends " + base
            bp := self.find_name(pos[0], pos[1] + blen(name), base, 1)
            self.reference(base, bp[0] + 1, bp[1] + 1)
        if interfaces != null and len(interfaces) > 0:
            detail += " implements "
            i := 0
            for itf in interfaces:
                if i > 0:
                    detail += ", "
                detail += itf
                ip := self.find_name(pos[0], pos[1] + blen(name), itf, 1)
                self.reference(itf, ip[0] + 1, ip[1] + 1)
                i += 1
        self.fi.symbols[sym].detail = detail
        saved_class := self.class_name
        saved_sym := self.class_sym
        saved_scope := self.class_scope
        saved_body := self.in_class_body
        saved := self.cur
        self.class_name = name
        self.class_sym = sym
        self.cur = self.new_scope("class", line0, last_line(n) - 1, sym)
        self.class_scope = self.cur
        self.in_class_body = true
        if body != null:
            for s in body.statements:
                if s.kind == "FunctionDecl":
                    self.function(s, true, false)
                    self.in_class_body = true
                else:
                    self.stmt(s)
        self.cur = saved
        self.class_name = saved_class
        self.class_sym = saved_sym
        self.class_scope = saved_scope
        self.in_class_body = saved_body

    func stmt(s):
        k := s.kind
        fi := self.fi
        if k == "FunctionDecl":
            self.function(s, self.in_class_body, false)
        elif k == "ClassDecl":
            self.type_body(s.name, "class", s, s.body, s.base_class, s.interfaces)
        elif k == "StructDecl":
            self.type_body(s.name, "struct", s, s.body, null, null)
        elif k == "InterfaceDecl":
            self.type_body(s.name, "interface", s, s.body, null, null)
        elif k == "EnumDecl":
            pos := self.find_name(s.line - 1, s.column, s.name)
            sym := self.declare(s.name, "enum", pos[0], pos[1], last_line(s) - 1, self.cur)
            fi.symbols[sym].doc = self.doc_above(s.line - 1)
            fi.symbols[sym].detail = "enum " + s.name
            saved := self.cur
            saved_class := self.class_name
            self.class_name = s.name
            self.cur = self.new_scope("enum", s.line - 1, last_line(s) - 1, sym)
            for m in s.members:
                ml := m.line - 1 if m.line > 0 else s.line - 1
                mc := m.column - 1 if m.column > 0 else 0
                fp := self.fix_position(ml, mc, m.name)
                if fp == null:
                    fp = self.find_name(ml, 0, m.name)
                ms := self.declare(m.name, "variant", fp[0], fp[1], fp[0], self.cur)
                fi.symbols[ms].container = s.name
                d := s.name + "." + m.name
                if m.fields != null and len(m.fields) > 0:
                    d += "(" + _s.join(", ", m.fields) + ")"
                    fi.symbols[ms].params = m.fields
                fi.symbols[ms].detail = d
            self.cur = saved
            self.class_name = saved_class
        elif k == "VariableDecl":
            if s.value != null and not s.declared_only:
                self.expr(s.value)
            fp := self.fix_position(s.line - 1, s.column - 1, s.name)
            if fp == null:
                fp = self.find_name(s.line - 1, 0, s.name)
            sym := self.declare(s.name, "field" if self.in_class_body else "variable", fp[0], fp[1], last_line(s) - 1, self.cur)
            S := fi.symbols[sym]
            S.type_name = type_text(s.type) if s.type != null else infer_type(s.value)
            S.detail = s.name + ("" if S.type_name == "" or bat(S.type_name, 0) == 61 else ": " + S.type_name)
            S.doc = self.doc_above(s.line - 1)
            if self.in_class_body:
                S.container = self.class_name
        elif k == "ConstDecl":
            if s.value != null:
                self.expr(s.value)
            p := self.find_name(s.line - 1, s.column - 1 + 5, s.name)
            sym := self.declare(s.name, "constant", p[0], p[1], last_line(s) - 1, self.cur)
            S := fi.symbols[sym]
            S.type_name = type_text(s.type) if s.type != null else infer_type(s.value)
            line := fi.lines[p[0]]
            eq := bfind(line, ":=")
            val := "" if eq < 0 else trim(bsub(line, eq + 2, blen(line)))
            if blen(val) > 60:
                val = bsub(val, 0, 57) + "..."
            S.detail = "const " + s.name + ("" if val == "" else " := " + val)
            S.doc = self.doc_above(s.line - 1)
            if self.in_class_body:
                S.container = self.class_name
        elif k == "Assignment":
            self.expr(s.value)
            t := s.target
            if t.kind == "MemberExpr" and self.class_sym >= 0 and self.class_name != "":
                if t.object.kind == "Identifier" and t.object.name == "self":
                    exists := false
                    for sy in fi.symbols:
                        if sy.kind == "field" and sy.container == self.class_name and sy.name == t.member:
                            exists = true
                    if not exists:
                        fp := self.fix_position(t.line - 1, t.column, t.member)
                        if fp != null:
                            sym := self.declare(t.member, "field", fp[0], fp[1], fp[0], self.class_scope)
                            S := fi.symbols[sym]
                            S.container = self.class_name
                            S.type_name = infer_type(s.value)
                            S.detail = "self." + t.member + ("" if S.type_name == "" or bat(S.type_name, 0) == 61 else ": " + S.type_name)
                            S.doc = self.doc_above(s.line - 1)
                            last := fi.occ[len(fi.occ) - 1]
                            last.is_member = true
                            last.object_name = "self"
                            last.scope = self.cur
            self.expr(t)
        elif k == "CompoundAssignment":
            self.expr(s.target)
            self.expr(s.value)
        elif k == "ExpressionStmt":
            self.expr(s.expr)
        elif k == "ReturnStmt":
            self.expr(s.value)
        elif k == "IfStmt":
            self.expr(s.condition)
            self.block(s.then_block)
            for e in s.elif_clauses:
                self.expr(e.condition)
                self.block(e.body)
            self.block(s.else_block)
        elif k == "WhileStmt":
            self.expr(s.condition)
            self.block(s.body)
        elif k == "ForStmt":
            self.expr(s.iterable)
            saved := self.cur
            self.cur = self.new_scope("block", s.line - 1, last_line(s) - 1, -1)
            p := self.find_name(s.line - 1, s.column - 1 + 3, s.variable, 1)
            self.declare(s.variable, "variable", p[0], p[1], p[0], self.cur)
            if s.body != null:
                self.stmts(s.body.statements)
            self.cur = saved
        elif k == "TryStmt":
            self.block(s.try_block)
            for c in s.catch_clauses:
                saved := self.cur
                start := c.line - 1 if c.line > 0 else s.line - 1
                self.cur = self.new_scope("block", start, last_line(c.body) - 1 if c.body != null else start, -1)
                if c.name != null:
                    p := self.find_name(start, 0, c.name, 1)
                    sy := self.declare(c.name, "variable", p[0], p[1], p[0], self.cur)
                    fi.symbols[sy].type_name = "Exception"
                    fi.symbols[sy].detail = c.name + " (exception : .type, .message, .trace)"
                if c.body != null:
                    self.stmts(c.body.statements)
                self.cur = saved
            self.block(s.finally_block)
        elif k == "MatchStmt":
            self.expr(s.subject)
            for c in s.cases:
                saved := self.cur
                start := c.pattern.line - 1 if c.pattern != null else s.line - 1
                self.cur = self.new_scope("block", start, last_line(c.body) - 1 if c.body != null else start, -1)
                if c.pattern != null:
                    self.pattern(c.pattern)
                if c.guard != null:
                    self.expr(c.guard)
                if c.body != null:
                    self.stmts(c.body.statements)
                self.cur = saved
        elif k == "ImportStmt":
            dotted := _s.join(".", s.module_path)
            file := self.resolve_import(s.module_path)
            line0 := s.line - 1
            if line0 < 0 or line0 >= len(fi.lines):
                return
            lt := fi.lines[line0]
            if s.is_from:
                up := bfind(lt, " use ")
                frm := 0 if up < 0 else up + 5
                for n in s.names:
                    p := self.find_name(line0, frm, n, 1)
                    sy := self.declare(n, "function", p[0], p[1], p[0], self.cur)
                    S := fi.symbols[sy]
                    S.is_import = true
                    S.import_file = file
                    S.import_name = n
                    S.module_path = dotted
                    S.detail = "from " + dotted + " use " + n
                    frm = p[1] + blen(n)
            else:
                bound := s.alias if s.alias != null else (s.module_path[len(s.module_path) - 1] if len(s.module_path) > 0 else "")
                p := null
                if s.alias != null:
                    ap := bfind(lt, " as ")
                    p = self.find_name(line0, 0 if ap < 0 else ap + 4, bound, 1)
                else:
                    dp := bfind(lt, dotted)
                    p = self.find_name(line0, 0 if dp < 0 else dp + blen(dotted) - blen(bound), bound, 1)
                sy := self.declare(bound, "module", p[0], p[1], p[0], self.cur)
                S := fi.symbols[sy]
                S.is_import = true
                S.import_file = file
                S.module_path = dotted
                S.detail = "use " + dotted + (" as " + s.alias if s.alias != null else "")

    func pattern(p):
        if p.pk == "Bind" and p.name != "" and p.name != "_":
            fp := self.fix_position(p.line - 1, p.column - 1, p.name)
            if fp == null:
                return
            self.declare(p.name, "variable", fp[0], fp[1], fp[0], self.cur)
        for sp in p.subpatterns:
            if sp != null:
                self.pattern(sp)

    func expr(e):
        if e == null:
            return -1
        k := e.kind
        if k == "Identifier":
            if e.name == "self" or e.name == "super":
                return -1
            return self.reference(e.name, e.line, e.column)
        if k == "MemberExpr":
            obj := self.expr(e.object)
            on := e.object.name if e.object.kind == "Identifier" else ""
            return self.reference(e.member, e.line, e.column + 1, true, obj, on)
        if k == "CallExpr":
            self.expr(e.callee)
            for a in e.arguments:
                self.expr(a.value)
        elif k == "IndexExpr":
            self.expr(e.object)
            self.expr(e.index)
        elif k == "BinaryExpr":
            self.expr(e.left)
            self.expr(e.right)
        elif k == "UnaryExpr" or k == "ErrorPropagationExpr":
            self.expr(e.operand)
        elif k == "ConditionalExpr":
            self.expr(e.condition)
            self.expr(e.then_expr)
            self.expr(e.else_expr)
        elif k == "RangeExpr":
            self.expr(e.start)
            self.expr(e.end)
        elif k == "ListLiteral" or k == "TupleLiteral":
            for x in e.elements:
                self.expr(x)
        elif k == "DictLiteral":
            for kv in e.entries:
                self.expr(kv.key)
                self.expr(kv.value)
        elif k == "FStringLiteral":
            for p in e.parts:
                if p.is_expr:
                    self.expr(p.expr)
        elif k == "LambdaExpr":
            if e.function != null:
                self.function(e.function, false, true)
        elif k == "ComprehensionExpr":
            saved := self.cur
            self.cur = self.new_scope("block", e.line - 1, e.line - 1, -1)
            for cl in e.clauses:
                self.expr(cl.expr)
                if cl.clause_kind == "For":
                    l := cl.line - 1 if cl.line > 0 else e.line - 1
                    p := self.find_name(l, cl.column - 1 if cl.column > 0 else 0, cl.variable, 1)
                    self.declare(cl.variable, "variable", p[0], p[1], p[0], self.cur)
            self.expr(e.element)
            self.expr(e.key)
            self.expr(e.value)
            self.cur = saved
        return -1

# « fichier.al:12:5: message » : [fichier, ligne, colonne, message] (regex ([^\s:][^:\n]*\.al):(\d+):(\d+):\s*(.*)).
func _parse_pos(text):
    n := blen(text)
    i := 0
    while true:
        p := bfind(text, ".al:", i)
        if p < 0:
            return null
        # début du chemin : après le dernier blanc, ':' ou fin de ligne avant p
        a := p
        while a > 0:
            c := bat(text, a - 1)
            if c == 58 or c == 10:
                break
            a -= 1
        while a < p and _is_space(bat(text, a)):
            a += 1
        q := p + 4
        l0 := q
        while q < n and bat(text, q) >= 48 and bat(text, q) <= 57:
            q += 1
        if q > l0 and q < n and bat(text, q) == 58:
            c0 := q + 1
            r := c0
            while r < n and bat(text, r) >= 48 and bat(text, r) <= 57:
                r += 1
            if r > c0 and r < n and bat(text, r) == 58 and a < p:
                m := r + 1
                while m < n and (bat(text, m) == 32 or bat(text, m) == 9):
                    m += 1
                e := m
                while e < n and bat(text, e) != 10:
                    e += 1
                return [bsub(text, a, p + 3), to_int(bsub(text, l0, q)), to_int(bsub(text, c0, r)), bsub(text, m, e), m]
        i = p + 1

const SEMANTIC_CODES := {"NameError": true, "DuplicateBindingError": true, "ConstAssignmentError": true, "ArgumentError": true,
    "FeatureNotImplementedError": true, "InheritanceError": true, "InterfaceError": true, "AsyncError": true, "TypeCheckError": true}
const MODULE_CODES := {"ModuleNotFoundError": true, "CyclicImportError": true, "ExportNotFoundError": true}

class Diagnostic:
    func init(line, col, end_line, end_col, code, message, severity=1):
        self.range = [line, col, end_line, end_col]
        self.code = code
        self.message = message
        self.severity = severity
        self.source = "alex"
        self.tags = []

# Graphe de modules réutilisable : modules de la bibliothèque standard compilés une fois par session.
class _CachingGraph:
    func init(roots, cache):
        self.g = _bm.ModuleGraph(roots)
        self.cache = cache

    func build(path):
        g := self.g
        stdc := g.stdlib_canonical
        cache := self.cache
        # pré-remplissage : modules de la stdlib déjà compilés (sans dépendance au projet)
        for p in cache:
            g.compiled[p] = cache[p]
        g.resolve_and_compile(canonical_noresolve(path), true)
        for p in g.compiled:
            if not (p in cache) and path_is_under(p, stdc) and not (p in g.overrides):
                cache[p] = g.compiled[p]

func canonical_noresolve(p):
    return _bm.canonicalize(p)

class LanguageService:
    func init(stdlib_root, workspace_root):
        self.stdlib = canonical(stdlib_root)
        self.workspace = canonical(workspace_root) if workspace_root != "" else ""
        self.files = {}
        self.open_files = {}
        self.ws_files = []
        self.ws_scan = -1000.0
        self.module_cache = {}

    func set_workspace_root(root):
        self.workspace = root

    # -------- fichiers
    func open(path, text, version=0):
        p := canonical(path)
        self.open_files[p] = true
        fi := FileIndex(p, text)
        fi.version = version
        self.build(fi)
        self.files[p] = fi

    func change(path, text, version=0):
        self.open(path, text, version)

    func close(path):
        p := canonical(path)
        if p in self.open_files:
            self.open_files = _without(self.open_files, p)
        if p in self.files:
            self.files = _without(self.files, p)

    func is_open(path):
        return canonical(path) in self.open_files

    func text_of(path):
        return self.load(canonical(path)).text

    func index(path):
        return self.load(canonical(path))

    func _stamp(p):
        try:
            return _os.mtime(p)
        catch e:
            return 0

    func load(cp):
        if cp in self.files:
            fi := self.files[cp]
            if (cp in self.open_files) or fi.stamp == self._stamp(cp):
                return fi
        text := ""
        try:
            text = _io.read_file(cp)
        catch e:
            text = ""
        fi := FileIndex(cp, text)
        fi.stamp = self._stamp(cp)
        self.build(fi)
        self.files[cp] = fi
        return fi

    func resolve_import(from_file, module_path):
        roots := _bm.SearchRoots()
        roots.stdlib_root = self.stdlib
        roots.project_root = self.workspace if self.workspace != "" else _bm._parent(from_file)
        roots.entry_root = _bm._parent(from_file)
        roots.packages_root = _bm._join(roots.project_root, "alex_packages")
        r := null
        try:
            r = _bm.resolve_module_file(module_path, roots)
        catch e:
            r = null
        if r == null:
            return ""
        return canonical(r)

    func build(fi):
        fi.lines = cc.split_lines(fi.text)
        fi.symbols = []
        fi.scopes = [Scope(-1, 0, len(fi.lines), "module", "", -1)]
        fi.occ = []
        pr := parse_repaired(fi.path, fi.text)
        prog := pr[0]
        fi.parsed = prog != null
        fi.repaired = pr[1]
        if prog == null:
            return
        frm := fi.path
        b := Builder(fi, (mp) => self.resolve_import(frm, mp))
        b.cur = 0
        b.stmts(prog.top_level)

    # -------- résolution
    func scope_at(fi, line):
        best := 0
        span := 1 << 30
        i := 0
        for s in fi.scopes:
            if line >= s.start and line <= s.end:
                sp := s.end - s.start
                if sp <= span:
                    best = i
                    span = sp
            i += 1
        return best

    func lookup(fi, name, scope, line):
        s := scope
        first := true
        while s >= 0:
            sc := fi.scopes[s]
            skip := not first and (sc.kind == "class" or sc.kind == "enum")
            if not skip:
                best := -1
                for sym in fi.symbols:
                    if sym.scope != s or sym.name != name:
                        continue
                    if sym.kind == "field" or sym.kind == "method" or sym.kind == "variant":
                        if not (first and (sc.kind == "class" or sc.kind == "enum")):
                            continue
                    if best < 0:
                        best = sym.id
                    elif sym.line <= line and (fi.symbols[best].line > line or sym.line > fi.symbols[best].line):
                        best = sym.id
                if best >= 0:
                    return best
            first = false
            s = sc.parent
        return -1

    func sym(r):
        if r == null or r[1] < 0:
            return null
        fi := self.load(r[0])
        if r[1] >= len(fi.symbols):
            return null
        return fi.symbols[r[1]]

    func follow(r, depth=0):
        if depth > 8:
            return r
        s := self.sym(r)
        if s == null or not s.is_import or s.import_name == "" or s.import_file == "":
            return r
        t := self.load(s.import_file)
        for c in t.symbols:
            if c.scope == 0 and c.name == s.import_name:
                return self.follow([t.path, c.id], depth + 1)
        return r

    func _top(file, name):
        mf := self.load(file)
        for c in mf.symbols:
            if c.scope == 0 and c.name == name:
                return [mf.path, c.id]
        return null

    func resolve_type_name(fi, type_name, scope, line, depth=0):
        if type_name == "" or depth > 6:
            return null
        t := type_name
        if ends_with(t, "?"):
            t = bsub(t, 0, blen(t) - 1)
        dot := bfind(t, ".")
        if dot >= 0:
            m := self.lookup(fi, bsub(t, 0, dot), scope, line)
            if m < 0:
                return null
            ms := self.sym(self.follow([fi.path, m]))
            if ms == null or ms.kind != "module" or ms.import_file == "":
                return null
            c := self._top(ms.import_file, bsub(t, dot + 1, blen(t)))
            return self.follow(c) if c != null else null
        s := self.lookup(fi, t, scope, line)
        if s < 0:
            return null
        r := self.follow([fi.path, s])
        rs := self.sym(r)
        if rs == null:
            return null
        if rs.kind == "class" or rs.kind == "struct" or rs.kind == "interface" or rs.kind == "enum":
            return r
        return null

    func type_of_symbol(r, depth=0):
        s := self.sym(r)
        if s == null or depth > 6:
            return null
        if s.kind == "class" or s.kind == "struct" or s.kind == "interface" or s.kind == "enum":
            return r
        if s.type_name == "":
            return null
        tn := s.type_name
        scope := s.scope
        line := s.line
        fi := self.load(r[0])
        if bat(tn, 0) == 61:
            callee := bsub(tn, 1, blen(tn))
            target := null
            dot := bfind(callee, ".")
            if dot < 0:
                f := self.lookup(fi, callee, scope, line)
                if f >= 0:
                    target = self.follow([fi.path, f])
            else:
                o := self.lookup(fi, bsub(callee, 0, dot), scope, line)
                if o < 0:
                    return null
                obj := self.follow([fi.path, o])
                os := self.sym(obj)
                if os == null:
                    return null
                member := bsub(callee, dot + 1, blen(callee))
                if os.kind == "module":
                    if os.import_file == "":
                        return null
                    c := self._top(os.import_file, member)
                    if c != null:
                        target = self.follow(c)
                else:
                    t := self.type_of_symbol(obj, depth + 1)
                    if t != null:
                        target = self.find_member(t, member)
            ts := self.sym(target)
            if ts == null:
                return null
            if ts.kind == "class" or ts.kind == "struct":
                return target
            if ts.kind != "function" and ts.kind != "method":
                return null
            return self.type_of_symbol(target, depth + 1)
        return self.resolve_type_name(fi, tn, scope, line, depth + 1)

    func find_member(cls, name, depth=0):
        c := self.sym(cls)
        if c == null or depth > 8:
            return null
        fi := self.load(cls[0])
        for s in fi.symbols:
            if s.container == c.name and s.name == name and (s.kind == "field" or s.kind == "method" or s.kind == "variant" or s.kind == "constant"):
                return [fi.path, s.id]
        if c.base_class != "":
            base := self.resolve_type_name(fi, c.base_class, c.scope, c.line)
            if base != null:
                return self.find_member(base, name, depth + 1)
        return null

    func members_of(cls, depth=0):
        out := []
        c := self.sym(cls)
        if c == null or depth > 8:
            return out
        fi := self.load(cls[0])
        seen := {}
        for s in fi.symbols:
            if s.container == c.name and (s.kind == "field" or s.kind == "method" or s.kind == "variant" or s.kind == "constant") and not (s.name in seen):
                seen[s.name] = true
                append(out, [fi.path, s.id])
        if c.base_class != "":
            b := self.resolve_type_name(fi, c.base_class, c.scope, c.line)
            if b != null:
                for m in self.members_of(b, depth + 1):
                    ms := self.sym(m)
                    if ms != null and not (ms.name in seen):
                        seen[ms.name] = true
                        append(out, m)
        return out

    func module_exports(file):
        out := []
        if file == "":
            return out
        fi := self.load(file)
        for s in fi.symbols:
            if s.scope == 0 and not (s.is_import and s.kind == "module"):
                append(out, [fi.path, s.id])
        return out

    func _class_of_scope(fi, sc):
        while sc >= 0:
            if fi.scopes[sc].class_name != "":
                return fi.scopes[sc].class_name
            sc = fi.scopes[sc].parent
        return ""

    func resolve_occurrence(fi, o, depth=0):
        if depth > 10:
            return null
        if o.is_decl and not o.is_member:
            return [fi.path, o.decl_sym]
        if o.is_decl and o.decl_sym >= 0:
            return [fi.path, o.decl_sym]
        if not o.is_member:
            s := self.lookup(fi, o.name, o.scope, o.line)
            if s < 0:
                return null
            return [fi.path, s]
        if o.object_name == "self":
            cls := self._class_of_scope(fi, o.scope)
            if cls == "":
                return null
            cs := self.lookup(fi, cls, 0, o.line)
            if cs < 0:
                for s in fi.symbols:
                    if s.name == cls and (s.kind == "class" or s.kind == "struct"):
                        cs = s.id
            if cs < 0:
                return null
            return self.find_member([fi.path, cs], o.name)
        if o.object_occ < 0 or o.object_occ >= len(fi.occ):
            return null
        obj := self.follow(self.resolve_occurrence(fi, fi.occ[o.object_occ], depth + 1))
        os := self.sym(obj)
        if os == null:
            return null
        if os.kind == "module":
            if os.import_file == "":
                return null
            return self._top(os.import_file, o.name)
        t := self.type_of_symbol(obj)
        if t == null:
            return null
        return self.find_member(t, o.name)

    func occurrence_at(fi, line, col):
        best := null
        for o in fi.occ:
            if o.line == line and col >= o.col and col <= o.col + o.len:
                if best == null or o.len < best.len:
                    best = o
        return best

    func symbol_at(path, line, col, where=null):
        fi := self.load(canonical(path))
        o := self.occurrence_at(fi, line, col)
        if o == null:
            return null
        if where != null:
            where[0] = [o.line, o.col, o.line, o.col + o.len]
        return self.resolve_occurrence(fi, o)

    func signature_of(s):
        return s.detail if s.detail != "" else s.name

    func markdown_for(r):
        s := self.sym(r)
        if s == null:
            return ""
        md := "```alex\n"
        if s.kind == "method" and s.container != "":
            md += "(méthode de " + s.container + ") "
        elif s.kind == "field" and s.container != "":
            md += "(champ de " + s.container + ") "
        else:
            md += "(" + kind_name(s.kind) + ") "
        sg := self.signature_of(s)
        if (s.kind == "variable" or s.kind == "parameter" or s.kind == "field") and bfind(sg, ":") < 0:
            t := self.type_of_symbol(r)
            s = self.sym(r)
            ts := self.sym(t)
            if ts != null:
                sg += ": " + ts.name
        md += sg + "\n```"
        if s.kind == "module" and s.import_file != "":
            mf := self.load(s.import_file)
            head := ""
            n := 0
            for l in mf.lines:
                t := trim(l)
                if t == "" or bat(t, 0) != 35:
                    if head != "":
                        break
                    continue
                body := ""
                if blen(t) > 1:
                    body = bsub(t, 2 if bat(t, 1) == 32 else 1, blen(t))
                if body == "alex: native" or bfind(body, "ALEX STANDARD LIBRARY") >= 0:
                    continue
                head += body + "\n"
                n += 1
                if n > 14:
                    break
            if head != "":
                md += "\n\n" + head
        elif s.doc != "":
            md += "\n\n" + s.doc
        rel := r[0]
        if self.workspace != "" and path_is_under(rel, self.workspace) and path_key(rel) != path_key(self.workspace):
            rel = path_relative_to(rel, self.workspace)
        elif path_is_under(rel, self.stdlib) and path_key(rel) != path_key(self.stdlib):
            rel = "stdlib/" + path_relative_to(rel, self.stdlib)
        md += "\n\n*" + rel + ":" + str(s.line + 1) + "*"
        return md

    # -------- diagnostics
    func compiler_diagnostics(fi):
        out := []
        roots := _bm.SearchRoots()
        roots.stdlib_root = self.stdlib
        roots.project_root = self.workspace if self.workspace != "" else _bm._parent(fi.path)
        roots.entry_root = _bm._parent(fi.path)
        roots.packages_root = _bm._join(roots.project_root, "alex_packages")
        cg := _CachingGraph(roots, self.module_cache)
        cg.g.set_source_override(fi.path, fi.text)
        err := null
        try:
            cg.build(fi.path)
        catch e:
            err = e
        if err == null:
            return out
        t := err.type
        msg := err.message
        if t == "SyntaxError" or t == "IndentationError":
            p := _parse_pos(msg)
            raw := p[3] if p != null else msg
            u := [-1, -1]
            if _s.contains(raw, "délimiteur non refermé") and p != null and canonical(p[0]) == fi.path:
                u = unclosed_delimiter(fi.text)
            if u[0] >= 0:
                append(out, Diagnostic(u[0], u[1], u[0], u[1] + 1, t, "délimiteur ouvert ici jamais refermé (parenthèse, crochet ou accolade)"))
            elif p != null:
                self._add(out, fi, p[0], p[1], p[2], t, raw)
            else:
                self._add(out, fi, fi.path, 1, 1, t, msg)
        elif t in SEMANTIC_CODES:
            p := _parse_pos(msg)
            if p == null:
                self._add(out, fi, fi.path, 1, 1, t, msg)
            else:
                # premier diagnostic, puis « fichier:l:c: message » des suivants
                raw := bsub(msg, p[4], blen(msg))
                first := true
                for line in _s.split(raw, "\n"):
                    tl := trim(line)
                    if first:
                        self._add(out, fi, p[0], p[1], p[2], t, tl)
                        first = false
                        continue
                    q := _parse_pos(tl)
                    if q != null:
                        self._add(out, fi, q[0], q[1], q[2], t, q[3])
        elif t in MODULE_CODES:
            full := t + ": " + msg
            at := -1
            name := _quoted_name(full)
            if name != "":
                i := 0
                while i < len(fi.lines):
                    tl := trim(fi.lines[i])
                    if (starts_with(tl, "use ") or starts_with(tl, "from ")) and bfind(tl, name) >= 0:
                        at = i
                        break
                    i += 1
            l := at if at >= 0 else 0
            append(out, Diagnostic(l, 0, l, self._line_len(fi, l), "ModuleError", full))
        else:
            code := "CompileError" if t == "CompileError" else "Error"
            full := msg if t == "CompileError" else str(err)
            p := _parse_pos(full)
            if p != null:
                self._add(out, fi, p[0], p[1], p[2], code, p[3])
            else:
                self._add(out, fi, fi.path, 1, 1, code, full)
        return out

    func _line_len(fi, l):
        return blen(fi.lines[l]) if l >= 0 and l < len(fi.lines) else 0

    func _add(out, fi, file, line1, col1, code, msg):
        cf := canonical(file)
        if file != "" and cf != fi.path:
            at := -1
            for s in fi.symbols:
                if s.is_import and canonical(s.import_file) == cf:
                    at = s.line
                    break
            m := "dans le module importé " + _os.basename(file) + ":" + str(line1) + " : " + msg
            l1 := at + 1 if at >= 0 else 1
            append(out, Diagnostic(l1 - 1, 0, l1 - 1, self._line_len(fi, l1 - 1), code, m))
            return
        l := _max(0, line1 - 1)
        c := _max(0, col1 - 1)
        end := c
        if l < len(fi.lines):
            t := fi.lines[l]
            n := blen(t)
            while end < n and is_ident_byte(bat(t, end)):
                end += 1
            if end == c:
                end = _max(c + 1, n)
            if c >= n:
                c = 0
                while c < n and bat(t, c) == 32:
                    c += 1
                end = n
        append(out, Diagnostic(l, c, l, end, code, msg))

    func lint_diagnostics(fi):
        out := []
        if not fi.parsed or fi.repaired:
            return out
        uses := [0 for i in 0..len(fi.symbols)]
        for o in fi.occ:
            if o.is_decl:
                continue
            r := self.resolve_occurrence(fi, o)
            if r != null and r[1] >= 0 and r[0] == fi.path and r[1] < len(uses):
                uses[r[1]] += 1
        for s in fi.symbols:
            if s.name != "" and bat(s.name, 0) == 95:
                continue
            unused_import := s.is_import and uses[s.id] == 0 and s.scope == 0
            unused_local := not s.is_import and s.kind == "variable" and uses[s.id] == 0 and fi.scopes[s.scope].kind != "module"
            if not unused_import and not unused_local:
                continue
            d := Diagnostic(s.line, s.col, s.line, s.col + blen(s.name), "unused-import" if unused_import else "unused-variable",
                            "import inutilisé : « " + s.name + " »" if unused_import else "variable « " + s.name + " » jamais lue",
                            2 if unused_import else 4)
            append(d.tags, "unnecessary")
            append(out, d)
        i := 0
        for t in fi.lines:
            n := blen(t)
            if n > 0 and (bat(t, n - 1) == 32 or bat(t, n - 1) == 9):
                k := n
                while k > 0 and (bat(t, k - 1) == 32 or bat(t, k - 1) == 9):
                    k -= 1
                append(out, Diagnostic(i, k, i, n, "trailing-whitespace", "espaces en fin de ligne", 4))
            tab := bfind(t, "\t")
            fnb := 0
            while fnb < n and (bat(t, fnb) == 32 or bat(t, fnb) == 9):
                fnb += 1
            if tab >= 0 and fnb < n and tab < fnb:
                append(out, Diagnostic(i, 0, i, fnb, "tab-indent", "indentation par tabulation (4 espaces attendus)", 2))
            i += 1
        return out

    func diagnostics(path):
        fi := self.load(canonical(path))
        out := self.compiler_diagnostics(fi)
        for d in self.lint_diagnostics(fi):
            clash := false
            for e in out:
                if e.range[0] == d.range[0]:
                    clash = true
            if not clash:
                append(out, d)
        return out

    # -------- complétion
    func item_for(s):
        it := {"label": s.name, "kind": s.kind, "detail": s.detail if (s.is_import and s.kind != "module") else self.signature_of(s),
               "doc": s.doc, "insert": "", "snippet": false, "sort": ""}
        if s.kind == "function" or s.kind == "method":
            if len(s.params) == 0:
                it["insert"] = s.name + "()"
            else:
                ins := s.name + "("
                n := 0
                for p in s.params:
                    pn := p
                    cut := _first_of(pn, ":=")
                    if cut >= 0:
                        pn = trim(bsub(pn, 0, cut))
                    if pn == "self":
                        continue
                    if bfind(p, "=") >= 0:
                        break
                    ins += (", " if n > 0 else "") + "${" + str(n + 1) + ":" + pn + "}"
                    n += 1
                ins += ")"
                it["insert"] = ins
                it["snippet"] = true
        return it

    func complete(path, line, col):
        out := []
        fi := self.load(canonical(path))
        if line < 0 or line >= len(fi.lines):
            return out
        text := fi.lines[line]
        c := _min(col, blen(text))
        before := bsub(text, 0, c)
        p := c
        while p > 0 and is_ident_byte(bat(before, p - 1)):
            p -= 1
        prefix := bsub(before, p, blen(before))
        head := trim(bsub(before, 0, p))
        seen := {}
        push := (it) => _push(out, seen, it, prefix)
        um := _match_use(before)
        if um != null:
            typed := um
            dot := brfind(typed, ".")
            parent := "" if dot < 0 else bsub(typed, 0, dot)
            dir := _s.replace(parent, ".", "/")
            names := list_modules(self.stdlib, dir)
            if self.workspace != "":
                for n in list_modules(self.workspace, dir):
                    append(names, n)
            for n in names:
                push({"label": n, "kind": "module", "detail": ("" if parent == "" else parent + ".") + n, "doc": "", "insert": "", "snippet": false, "sort": ""})
            return out
        fm := _match_from_use(before)
        if fm != null:
            file := self.resolve_import(fi.path, _s.split(fm, "."))
            for r in self.module_exports(file):
                s2 := self.sym(r)
                if s2 != null and s2.name != "" and bat(s2.name, 0) != 95:
                    it := self.item_for(s2)
                    it["insert"] = ""
                    it["snippet"] = false
                    push(it)
            return out
        scope := self.scope_at(fi, line)
        if p > 0 and bat(before, p - 1) == 46:
            q := p - 1
            chain := []
            while q > 0:
                e := q
                s := e
                while s > 0 and is_ident_byte(bat(before, s - 1)):
                    s -= 1
                if s == e:
                    break
                chain = [bsub(before, s, e)] + chain
                q = s
                if q > 0 and bat(before, q - 1) == 46:
                    q -= 1
                else:
                    break
            if len(chain) == 0:
                return out
            cur := null
            is_self := chain[0] == "self"
            if is_self:
                cls := self._class_of_scope(fi, scope)
                for s in fi.symbols:
                    if s.name == cls and (s.kind == "class" or s.kind == "struct"):
                        cur = [fi.path, s.id]
            else:
                s := self.lookup(fi, chain[0], scope, line)
                if s >= 0:
                    cur = self.follow([fi.path, s])
            k := 1
            while k < len(chain) and cur != null:
                cs := self.sym(cur)
                if cs == null:
                    break
                if cs.kind == "module":
                    nxt := null
                    for r in self.module_exports(cs.import_file):
                        x := self.sym(r)
                        if x != null and x.name == chain[k]:
                            nxt = self.follow(r)
                    cur = nxt
                else:
                    t := self.type_of_symbol(cur)
                    cur = self.follow(self.find_member(t, chain[k])) if t != null else null
                    if cur != null and cur[1] < 0:
                        cur = null
                k += 1
            cs := self.sym(cur)
            if cs == null:
                return out
            if cs.kind == "module":
                for r in self.module_exports(cs.import_file):
                    x := self.sym(r)
                    if x == null or x.name == "" or bat(x.name, 0) == 95:
                        continue
                    fx := self.sym(self.follow(r))
                    it := self.item_for(fx if fx != null else x)
                    it["label"] = x.name
                    push(it)
            else:
                t := cur if is_self else self.type_of_symbol(cur)
                if t != null:
                    for r in self.members_of(t):
                        x := self.sym(r)
                        if x == null:
                            continue
                        if x.name == "init" and not is_self:
                            continue
                        if not is_self and x.name != "" and bat(x.name, 0) == 95:
                            continue
                        if not is_self and cs.kind == "enum" and x.kind != "variant":
                            continue
                        push(self.item_for(x))
            return out
        if blen(head) >= 1 and bat(head, blen(head) - 1) == 46:
            return out
        s := scope
        first := true
        while s >= 0:
            sc := fi.scopes[s]
            skip := not first and (sc.kind == "class" or sc.kind == "enum")
            if not skip:
                for sy in fi.symbols:
                    if sy.scope != s:
                        continue
                    if (sy.kind == "field" or sy.kind == "method" or sy.kind == "variant") and not (first and sc.kind == "class"):
                        continue
                    if sy.kind == "variable" and sc.kind != "module" and sy.line > line:
                        continue
                    it := self.item_for(sy)
                    if sy.is_import and sy.kind != "module":
                        fr := self.follow([fi.path, sy.id])
                        fx := self.sym(fr)
                        if fx != null:
                            it = self.item_for(fx)
                            it["label"] = sy.name
                    it["sort"] = ("0" if s == scope else "1") + sy.name
                    push(it)
            first = false
            s = sc.parent
        for b in _BUILTINS:
            push({"label": b[0], "kind": "builtin", "detail": b[1], "doc": "", "insert": b[0] + "(${1})", "snippet": true, "sort": "2" + b[0]})
        line_start := head == ""
        for k in KEYWORDS:
            push({"label": k, "kind": "keyword", "detail": "", "doc": "", "insert": "", "snippet": false, "sort": "3" + k})
        if line_start:
            for sn in _SNIPPETS:
                it := {"label": sn[0], "kind": "snippet", "detail": sn[2], "doc": "", "insert": sn[1], "snippet": true, "sort": "4" + sn[0]}
                if fuzzy(sn[0], prefix):
                    append(out, it)
        return out

    # -------- survol, signature, navigation
    func hover(path, line, col):
        where := [null]
        r := self.symbol_at(path, line, col, where)
        if r == null or r[1] < 0:
            return null
        f := self.follow(r)
        if self.sym(f) == null:
            return null
        return {"range": where[0], "markdown": self.markdown_for(f)}

    func signature_help(path, line, col):
        fi := self.load(canonical(path))
        depth := 0
        commas := 0
        l := line
        if l >= len(fi.lines):
            return null
        c := _min(col, blen(fi.lines[l]))
        open_line := -1
        open_col := -1
        steps := 0
        while steps < 2000 and l >= 0 and l > line - 6:
            steps += 1
            if c <= 0:
                l -= 1
                if l < 0:
                    break
                c = blen(fi.lines[l])
                continue
            ch := bat(fi.lines[l], c - 1)
            c -= 1
            if ch == 41 or ch == 93 or ch == 125:
                depth += 1
            elif ch == 40 or ch == 91 or ch == 123:
                if depth == 0:
                    if ch == 40:
                        open_line = l
                        open_col = c
                    break
                depth -= 1
            elif ch == 44 and depth == 0:
                commas += 1
        if open_line < 0:
            return null
        t := fi.lines[open_line]
        e := open_col
        while e > 0 and bat(t, e - 1) == 32:
            e -= 1
        s := e
        while s > 0 and (is_ident_byte(bat(t, s - 1)) or bat(t, s - 1) == 46):
            s -= 1
        chain_text := bsub(t, s, e)
        if chain_text == "":
            return null
        chain := _s.split(chain_text, ".")
        scope := self.scope_at(fi, open_line)
        cur := null
        if chain[0] == "self":
            cls := self._class_of_scope(fi, scope)
            for sy in fi.symbols:
                if sy.name == cls and (sy.kind == "class" or sy.kind == "struct"):
                    cur = [fi.path, sy.id]
        else:
            sy := self.lookup(fi, chain[0], scope, open_line)
            if sy >= 0:
                cur = self.follow([fi.path, sy])
        k := 1
        while k < len(chain) and cur != null:
            cs := self.sym(cur)
            if cs.kind == "module":
                nxt := null
                for r in self.module_exports(cs.import_file):
                    x := self.sym(r)
                    if x != null and x.name == chain[k]:
                        nxt = self.follow(r)
                cur = nxt
            else:
                ty := cur if (k == 1 and chain[0] == "self") else self.type_of_symbol(cur)
                cur = self.follow(self.find_member(ty, chain[k])) if ty != null else null
                if cur != null and cur[1] < 0:
                    cur = null
            k += 1
        fs := self.sym(cur)
        if fs == null:
            return null
        info := {"label": "", "doc": "", "params": [], "active": commas}
        if fs.kind == "class" or fs.kind == "struct":
            ini := self.sym(self.find_member(cur, "init"))
            if ini == null:
                return null
            ps := [p for p in ini.params if p != "self"]
            info["label"] = fs.name + "(" + _s.join(", ", ps) + ")"
            info["params"] = ps
            info["doc"] = fs.doc
        elif fs.kind == "function" or fs.kind == "method" or fs.kind == "variant":
            info["label"] = fs.name if fs.detail == "" else fs.detail
            info["params"] = [p for p in fs.params if p != "self"]
            info["doc"] = fs.doc
        else:
            return null
        return info

    func definition(path, line, col):
        out := []
        r := self.symbol_at(path, line, col)
        if r == null or r[1] < 0:
            return out
        f := self.follow(r)
        s := self.sym(f)
        if s == null:
            return out
        if s.kind == "module" and s.import_file != "":
            append(out, [s.import_file, [0, 0, 0, 0]])
            return out
        append(out, [f[0], [s.line, s.col, s.line, s.col + blen(s.name)]])
        return out

    func project_files():
        now := _os.monotonic_time()
        if len(self.ws_files) > 0 and now - self.ws_scan < 2.0:
            return self.ws_files
        self.ws_files = []
        self.ws_scan = now
        if self.workspace == "":
            return self.ws_files
        count := [0]
        self._scan(self.workspace, count)
        return self.ws_files

    func _scan(dir, count):
        names := []
        try:
            names = _os.list_dir(dir)
        catch e:
            return
        for n in names:
            if count[0] >= 5000:
                return
            p := dir + "/" + n
            if _os.isdir(p):
                if n != "" and (bat(n, 0) == 46 or n == "build" or n == "node_modules" or n == "dist" or n == "alex_packages"):
                    continue
                self._scan(p, count)
            elif ends_with(n, ".al"):
                append(self.ws_files, canonical(p))
                count[0] += 1

    func references(path, line, col, include_decl):
        out := []
        r := self.symbol_at(path, line, col)
        if r == null or r[1] < 0:
            return out
        target := self.follow(r)
        ts := self.sym(target)
        if ts == null:
            return out
        name := ts.name
        files := {}
        files[canonical(path)] = true
        for f in self.open_files:
            files[f] = true
        local := ts.scope != 0 and ts.kind != "method" and ts.kind != "field" and ts.kind != "variant"
        if not local:
            for f in self.project_files():
                files[f] = true
        files[target[0]] = true
        flist := cc.sort_strings([f for f in files])
        member_unique := false
        if ts.kind == "method" or ts.kind == "field":
            owners := {}
            for f in flist:
                fi := self.load(f)
                for s in fi.symbols:
                    if s.name == name and s.container != "" and (s.kind == "method" or s.kind == "field"):
                        owners[f + "#" + s.container] = true
            member_unique = len(owners) == 1
        seen := {}
        for f in flist:
            fi := self.load(f)
            if bfind(fi.text, name) < 0:
                continue
            for o in fi.occ:
                if o.name != name and not (o.is_decl and o.decl_sym >= 0 and fi.symbols[o.decl_sym].is_import):
                    continue
                rr := self.follow(self.resolve_occurrence(fi, o))
                valid := rr != null and rr[1] >= 0
                probable := member_unique and not valid and o.is_member and o.name == name and o.object_name != "self"
                if not probable and (not valid or rr[0] != target[0] or rr[1] != target[1]):
                    continue
                is_target_decl := f == target[0] and o.is_decl and o.decl_sym == target[1]
                if is_target_decl and not include_decl:
                    continue
                if o.name != name:
                    continue
                key := f + "\x00" + str(o.line) + ":" + str(o.col)
                if key in seen:
                    continue
                seen[key] = true
                append(out, [f, [o.line, o.col, o.line, o.col + o.len]])
        return cc.sort_by(out, (a, b) => a[0] < b[0] or (a[0] == b[0] and (a[1][0] < b[1][0] or (a[1][0] == b[1][0] and a[1][1] < b[1][1]))))

    func highlights(path, line, col):
        cp := canonical(path)
        return [l[1] for l in self.references(path, line, col, true) if l[0] == cp]

    func prepare_rename(path, line, col):
        where := [null]
        r := self.symbol_at(path, line, col, where)
        if r == null or r[1] < 0:
            return null
        t := self.follow(r)
        s := self.sym(t)
        if s == null:
            return null
        if path_is_under(t[0], self.stdlib) and (self.workspace == "" or not path_is_under(t[0], self.workspace)):
            return null
        return [where[0], s.name]

    # [modifications {fichier: [[range, texte]...]}, erreur]
    func rename(path, line, col, new_name):
        if not is_identifier(new_name) or (new_name in RESERVED):
            return [null, "« " + new_name + " » n'est pas un identifiant valide"]
        r := self.symbol_at(path, line, col)
        if r == null or r[1] < 0:
            return [null, "aucun symbole à cet endroit"]
        t := self.follow(r)
        if path_is_under(t[0], self.stdlib) and (self.workspace == "" or not path_is_under(t[0], self.workspace)):
            return [null, "symbole de la bibliothèque standard : renommage refusé"]
        changes := {}
        order := []
        for loc in self.references(path, line, col, true):
            if not (loc[0] in changes):
                changes[loc[0]] = []
                append(order, loc[0])
            append(changes[loc[0]], [loc[1], new_name])
        if len(order) == 0:
            return [null, "aucune occurrence trouvée"]
        return [[[f, changes[f]] for f in cc.sort_strings(order)], ""]

    # -------- symboles
    func _doc_symbol(fi, s):
        end_line := _max(s.end_line, s.line)
        end_col := blen(fi.lines[end_line]) if end_line < len(fi.lines) else 0
        return {"name": s.name, "detail": s.detail, "kind": s.kind, "range": [s.line, 0, end_line, end_col],
                "selection": [s.line, s.col, s.line, s.col + blen(s.name)], "children": []}

    func document_symbols(path):
        fi := self.load(canonical(path))
        out := []
        for s in fi.symbols:
            if s.scope != 0 or s.is_import:
                continue
            d := self._doc_symbol(fi, s)
            if s.kind == "class" or s.kind == "struct" or s.kind == "interface" or s.kind == "enum":
                for m in fi.symbols:
                    if m.container == s.name and m.id != s.id and (m.kind == "method" or m.kind == "field" or m.kind == "variant" or m.kind == "constant"):
                        append(d["children"], self._doc_symbol(fi, m))
            append(out, d)
        return out

    func workspace_symbols(query):
        out := []
        files := {}
        for f in self.open_files:
            files[f] = true
        for f in self.project_files():
            files[f] = true
        for f in cc.sort_strings([x for x in files]):
            fi := self.load(f)
            for s in fi.symbols:
                if s.is_import:
                    continue
                top := s.scope == 0
                member := s.kind == "method" or s.kind == "field" or s.kind == "variant"
                if not top and not member:
                    continue
                if not fuzzy(s.name, query):
                    continue
                append(out, {"name": s.name, "kind": s.kind, "container": s.container, "file": f,
                             "range": [s.line, s.col, s.line, s.col + blen(s.name)]})
                if len(out) >= 500:
                    return out
        lq := lower(query)
        return cc.sort_by(out, (a, b) => _ws_less(a, b, lq))

    # -------- mise en forme
    func format(path, tab_size=4):
        fi := self.load(canonical(path))
        out := []
        blank := 0
        for line0 in fi.lines:
            lead := ""
            k := 0
            n := blen(line0)
            while k < n and (bat(line0, k) == 32 or bat(line0, k) == 9):
                if bat(line0, k) == 9:
                    lead += _s.repeat(" ", tab_size - blen(lead) % tab_size)
                else:
                    lead += " "
                k += 1
            line := lead + bsub(line0, k, n)
            e := blen(line)
            while e > 0 and (bat(line, e - 1) == 32 or bat(line, e - 1) == 9):
                e -= 1
            line = bsub(line, 0, e)
            if line == "":
                blank += 1
                if blank > 2:
                    continue
            else:
                blank = 0
            append(out, line)
        while len(out) > 1 and out[len(out) - 1] == "":
            out = out[0:len(out) - 1]
        text := _s.join("", [l + "\n" for l in out])
        if text == fi.text:
            return []
        last := len(fi.lines) - 1
        return [[[0, 0, last, blen(fi.lines[last])], text]]

    # -------- actions rapides : [{title, kind, preferred, changes: [[fichier, [[range, texte]...]]]}]
    func code_actions(path, rng, context):
        out := []
        cp := canonical(path)
        fi := self.load(cp)
        last_import := -1
        i := 0
        for l in fi.lines:
            t := trim(l)
            if starts_with(t, "use ") or starts_with(t, "from "):
                last_import = i
            i += 1
        insert_at := last_import + 1
        if last_import < 0:
            insert_at = 0
            while insert_at < len(fi.lines) and starts_with(trim(fi.lines[insert_at]), "#"):
                insert_at += 1
        for d in context:
            nm := _undefined_name(d["message"])
            if (d["code"] == "NameError" or bfind(d["message"], "n'est pas défini") >= 0) and nm != "":
                if _os.exists(self.stdlib + "/" + nm + "/" + nm + ".al"):
                    append(out, {"title": "Ajouter « use " + nm + " »", "kind": "quickfix", "preferred": true,
                                 "changes": [[cp, [[[insert_at, 0, insert_at, 0], "use " + nm + "\n"]]]]})
                for mod in ["core", "collections", "string", "math", "io", "os", "functional", "time", "json"]:
                    file := self.resolve_import(cp, [mod])
                    if file == "":
                        continue
                    found := false
                    for r in self.module_exports(file):
                        s := self.sym(r)
                        if s == null or s.name != nm:
                            continue
                        existing := -1
                        j := 0
                        for l in fi.lines:
                            if starts_with(trim(l), "from " + mod + " use "):
                                existing = j
                            j += 1
                        a := {"title": "Importer « " + nm + " » de " + mod, "kind": "quickfix", "preferred": len(out) == 0}
                        if existing >= 0:
                            endc := blen(fi.lines[existing])
                            a["changes"] = [[cp, [[[existing, endc, existing, endc], ", " + nm]]]]
                        else:
                            a["changes"] = [[cp, [[[insert_at, 0, insert_at, 0], "from " + mod + " use " + nm + "\n"]]]]
                        append(out, a)
                        found = true
                        break
            if d["code"] == "unused-import":
                l := d["range"][0]
                if l < 0 or l >= len(fi.lines):
                    continue
                t := trim(fi.lines[l])
                nmu := bsub(fi.lines[l], d["range"][1], d["range"][3])
                if starts_with(t, "from ") and bfind(t, ",") >= 0:
                    line := fi.lines[l]
                    append(out, {"title": "Retirer « " + nmu + " » de l'import", "kind": "quickfix", "preferred": false,
                                 "changes": [[cp, [[[l, 0, l, blen(line)], _remove_import_name(line, nmu)]]]]})
                else:
                    append(out, {"title": "Supprimer l'import inutilisé « " + nmu + " »", "kind": "quickfix", "preferred": false,
                                 "changes": [[cp, [[[l, 0, l + 1, 0], ""]]]]})
            if d["code"] == "trailing-whitespace" or d["code"] == "tab-indent":
                edits := self.format(path)
                if len(edits) > 0:
                    append(out, {"title": "Mettre en forme le document", "kind": "quickfix", "preferred": false, "changes": [[cp, edits]]})
        first := -1
        last := -1
        i = 0
        for l in fi.lines:
            t := trim(l)
            imp := starts_with(t, "use ") or starts_with(t, "from ")
            if imp and blen(l) > 0 and bat(l, 0) != 32:
                if first < 0:
                    first = i
                last = i
            elif first >= 0 and t != "":
                break
            i += 1
        if first >= 0 and rng[0] <= last + 1:
            froms := []
            uses := []
            k := first
            while k <= last:
                t := trim(fi.lines[k])
                if t != "":
                    if starts_with(t, "from "):
                        append(froms, t)
                    else:
                        append(uses, t)
                k += 1
            text := _s.join("", [f + "\n" for f in cc.sort_strings(froms)]) + _s.join("", [u + "\n" for u in cc.sort_strings(uses)])
            old := _s.join("", [fi.lines[k2] + "\n" for k2 in first..(last + 1)])
            if text != old:
                append(out, {"title": "Organiser les imports", "kind": "source.organizeImports", "preferred": false,
                             "changes": [[cp, [[[first, 0, last + 1, 0], text]]]]})
        return out

func _ws_less(a, b, lq):
    pa := starts_with(lower(a["name"]), lq)
    pb := starts_with(lower(b["name"]), lq)
    if pa != pb:
        return pa
    if blen(a["name"]) != blen(b["name"]):
        return blen(a["name"]) < blen(b["name"])
    return a["name"] < b["name"]

func _without(d, key):
    out := {}
    for k in d:
        if k != key:
            out[k] = d[k]
    return out

func _first_of(s, chars):
    i := 0
    n := blen(s)
    while i < n:
        c := bat(s, i)
        for ch in _s.byte_unpack(chars):
            if c == ch:
                return i
        i += 1
    return -1

func _push(out, seen, it, prefix):
    if not fuzzy(it["label"], prefix):
        return
    if it["label"] in seen:
        return
    seen[it["label"]] = true
    append(out, it)

# ^\s*(use|from)\s+([\w.]*)$ : nom tapé, null sinon.
func _match_use(before):
    t := before
    i := 0
    n := blen(t)
    while i < n and _is_space(bat(t, i)):
        i += 1
    kw := ""
    if starts_with(bsub(t, i, n), "use"):
        kw = "use"
    elif starts_with(bsub(t, i, n), "from"):
        kw = "from"
    else:
        return null
    i += blen(kw)
    j := i
    while j < n and _is_space(bat(t, j)):
        j += 1
    if j == i:
        return null
    k := j
    while k < n and (is_word_byte(bat(t, k)) or bat(t, k) == 46):
        k += 1
    if k != n:
        return null
    return bsub(t, j, n)

func is_word_byte(c):
    return (c >= 97 and c <= 122) or (c >= 65 and c <= 90) or (c >= 48 and c <= 57) or c == 95

# ^\s*from\s+([\w.]+)\s+use\s+[\w\s,]*$ : module, null sinon.
func _match_from_use(before):
    t := before
    n := blen(t)
    i := 0
    while i < n and _is_space(bat(t, i)):
        i += 1
    if not starts_with(bsub(t, i, n), "from"):
        return null
    i += 4
    j := i
    while j < n and _is_space(bat(t, j)):
        j += 1
    if j == i:
        return null
    k := j
    while k < n and (is_word_byte(bat(t, k)) or bat(t, k) == 46):
        k += 1
    if k == j:
        return null
    mod := bsub(t, j, k)
    m := k
    while m < n and _is_space(bat(t, m)):
        m += 1
    if m == k or not starts_with(bsub(t, m, n), "use"):
        return null
    m += 3
    q := m
    while q < n and _is_space(bat(t, q)):
        q += 1
    if q == m:
        return null
    while q < n:
        c := bat(t, q)
        if not (is_word_byte(c) or _is_space(c) or c == 44):
            return null
        q += 1
    return mod

# « 'nom' n'est pas d » : nom, "" sinon.
func _undefined_name(msg):
    i := 0
    while true:
        q := bfind(msg, "'", i)
        if q < 0:
            return ""
        e := q + 1
        n := blen(msg)
        if e < n and (is_word_byte(bat(msg, e)) and not (bat(msg, e) >= 48 and bat(msg, e) <= 57)):
            f := e
            while f < n and is_word_byte(bat(msg, f)):
                f += 1
            if f < n and bat(msg, f) == 39 and starts_with(bsub(msg, f + 1, n), " n'est pas d"):
                return bsub(msg, e, f)
        i = q + 1

# Premier nom entre apostrophes ('a.b') d'un message.
func _quoted_name(msg):
    i := 0
    n := blen(msg)
    while true:
        q := bfind(msg, "'", i)
        if q < 0:
            return ""
        e := q + 1
        if e < n and ((bat(msg, e) >= 65 and bat(msg, e) <= 90) or (bat(msg, e) >= 97 and bat(msg, e) <= 122) or bat(msg, e) == 95):
            f := e
            while f < n and (is_word_byte(bat(msg, f)) or bat(msg, f) == 46):
                f += 1
            if f < n and bat(msg, f) == 39:
                return bsub(msg, e, f)
        i = q + 1

# (,\s*nom\b)|(\bnom\s*,\s*) retiré une fois.
func _remove_import_name(line, nm):
    n := blen(line)
    m := blen(nm)
    i := 0
    while i < n:
        if bat(line, i) == 44:
            j := i + 1
            while j < n and _is_space(bat(line, j)):
                j += 1
            if bsub(line, j, j + m) == nm and (j + m >= n or not is_word_byte(bat(line, j + m))):
                return bsub(line, 0, i) + bsub(line, j + m, n)
        if bsub(line, i, i + m) == nm and (i == 0 or not is_word_byte(bat(line, i - 1))):
            j := i + m
            k := j
            while k < n and _is_space(bat(line, k)):
                k += 1
            if k < n and bat(line, k) == 44:
                k += 1
                while k < n and _is_space(bat(line, k)):
                    k += 1
                return bsub(line, 0, i) + bsub(line, k, n)
        i += 1
    return line

func list_modules(root, prefix_dir):
    out := []
    dir := root + "/" + prefix_dir if prefix_dir != "" else root
    if not _os.isdir(dir):
        return out
    names := []
    try:
        names = _os.list_dir(dir)
    catch e:
        return out
    last := _os.basename(prefix_dir) if prefix_dir != "" else ""
    for n in names:
        if n == "" or bat(n, 0) == 46 or bat(n, 0) == 95:
            continue
        p := dir + "/" + n
        if _os.isdir(p):
            if n == "build" or n == "node_modules" or n == "alex_packages" or n == "tests":
                continue
            append(out, n)
        elif ends_with(n, ".al"):
            stem := bsub(n, 0, blen(n) - 3)
            if stem != last:
                append(out, stem)
    out = cc.sort_strings(out)
    uniq := []
    for x in out:
        if len(uniq) == 0 or uniq[len(uniq) - 1] != x:
            append(uniq, x)
    return uniq

const _BUILTINS := [["print", "print(valeur, ...) — affiche, une valeur par ligne"],
    ["input", "input(invite) -> str — lit une ligne"],
    ["str", "str(valeur) -> str — conversion en texte"],
    ["raise", "raise(type, message) — lève une exception"],
    ["isinstance", "isinstance(valeur, Type) -> bool"]]

const _SNIPPETS := [["func", "func ${1:nom}(${2}):\n    ${0}", "fonction"],
    ["class", "class ${1:Nom}:\n    func init(${2}):\n        ${0}", "classe avec constructeur"],
    ["if", "if ${1:condition}:\n    ${0}", "si"],
    ["ifelse", "if ${1:condition}:\n    ${2}\nelse:\n    ${0}", "si / sinon"],
    ["for", "for ${1:x} in ${2:elements}:\n    ${0}", "boucle pour"],
    ["forrange", "for ${1:i} in 0..${2:n}:\n    ${0}", "boucle sur un intervalle"],
    ["while", "while ${1:condition}:\n    ${0}", "tant que"],
    ["try", "try:\n    ${1}\ncatch e:\n    ${0}", "essayer / attraper"],
    ["match", "match ${1:valeur}:\n    ${2:motif}:\n        ${0}", "filtrage"],
    ["main", "func main():\n    ${0}\n\nmain()", "point d'entrée"],
    ["test", "func test_${1:nom}():\n    ${0}", "fonction de test"]]

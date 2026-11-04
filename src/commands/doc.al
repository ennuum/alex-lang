# ALEX — commands.doc
#
# `alexc doc <module|fichier.al>... | --json <module> | --html <dossier> [modules] | --list` : documentation tirée
# des sources, comme alex::tooling (DocGen.cpp) sur l'index de symboles du service de langage (LanguageService.cpp,
# Builder) : en-tête de commentaires du module, déclarations publiques (fonctions, classes, structs, interfaces,
# enums, constantes, variables) avec leur signature et le commentaire qui les précède, membres des types.
#
#   use commands.doc as cd
#   d := cd.document_file("stdlib/json/json.al", "json")
#   print(cd.to_markdown(d))
#   code := cd.run(["--list"], "stdlib")
#
# Erreurs : aucune levée par run (messages sur stderr).

from core use len, type
from collections use append
use string as _s
use os as _os
use io as _io
use commands.common as cc
use parser as _bp

# ------------------------------------------------------------------------------------------- index de symboles

func _is_ident_char(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or _s.byte_len(str(c)) > 1

func _trim(s):
    return _s.trim(s)

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
    return len(n) > 0 and n[0] >= 'A' and n[0] <= 'Z'

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

class Symbol:
    func init(name, kind, line, col, root):
        self.name = name
        self.kind = kind
        self.line = line
        self.col = col
        self.root = root
        self.detail = ""
        self.doc = ""
        self.container = ""
        self.is_import = false
        self.type_name = ""

class Builder:
    func init(lines):
        self.lines = lines
        self.symbols = []
        self.root = true
        self.class_name = ""
        self.class_sym = -1
        self.in_class_body = false

    func find_name(line0, col0, name, max_lines=3):
        l := line0
        nl := len(self.lines)
        while l < nl and l < line0 + max_lines:
            t := self.lines[l]
            frm := col0 if (l == line0 and col0 > 0) else 0
            while true:
                p := _bfind(t, name, frm)
                if p < 0:
                    break
                ok_l := p == 0 or not _is_ident_byte(_s.byte_at(t, p - 1))
                ok_r := p + _s.byte_len(name) >= _s.byte_len(t) or not _is_ident_byte(_s.byte_at(t, p + _s.byte_len(name)))
                if ok_l and ok_r:
                    return [l, p]
                frm = p + 1
            l += 1
        return [line0, 0 if col0 < 0 else col0]

    func fix_position(line0, col0, name):
        if line0 < 0 or line0 >= len(self.lines):
            return null
        t := self.lines[line0]
        bl := _s.byte_len(name)
        if col0 >= 0 and col0 + bl <= _s.byte_len(t) and _s.byte_slice(t, col0, col0 + bl) == name:
            return [line0, col0]
        p := self.find_name(line0, col0 - 2 if col0 - 2 > 0 else 0, name, 1)
        if p[0] == line0 and p[1] + bl <= _s.byte_len(t) and _s.byte_slice(t, p[1], p[1] + bl) == name:
            return p
        return null

    func doc_above(line0):
        out := []
        l := line0 - 1
        while l >= 0:
            t := _trim(self.lines[l])
            if t == "" or t[0] != '#':
                break
            body := _trim(_s.substring(t, 1, len(t)))
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
        l := line0
        while l < len(self.lines) and l < line0 + 30:
            t := self.lines[l]
            n := _s.byte_len(t)
            k := name_col + _s.byte_len(name) if l == line0 else 0
            while k < n:
                c := _s.byte_at(t, k)
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
                        after := _s.byte_slice(t, k + 1, n)
                        ret := ""
                        arrow := _s.find(after, "->")
                        if arrow >= 0:
                            ret = _s.substring(after, arrow + 2, len(after))
                            colon := _rfind(ret, ":")
                            if colon >= 0:
                                ret = _s.substring(ret, 0, colon)
                            ret = _trim(ret)
                        return [_trim(_s.byte_join(text)), ret]
                append(text, _s.byte_slice(t, k, k + 1))
                k += 1
            if started:
                append(text, " ")
            l += 1
        return [_trim(_s.byte_join(text)), ""]

    func declare(name, kind, line0, col0):
        s := Symbol(name, kind, line0, col0, self.root)
        append(self.symbols, s)
        return s

    func with_scope(f):
        saved := self.root
        self.root = false
        f()
        self.root = saved

    func block(b):
        if b == null:
            return
        self.with_scope(() => self.stmts(b.statements))

    func stmts(lst):
        for s in lst:
            self.stmt(s)

    func function(f, method, lam):
        line0 := f.line - 1
        if not lam:
            pos := self.find_name(line0, f.column - 1 + 4, f.name)
            s := self.declare(f.name, "method" if method else "function", pos[0], pos[1])
            hp := self.header_params(pos[0], pos[1], f.name)
            ret := type_text(f.return_type) if f.return_type != null else hp[1]
            s.detail = ("async " if f.is_async else "") + "func " + f.name + "(" + hp[0] + ")" + ("" if ret == "" else " -> " + ret)
            s.doc = self.doc_above(f.line - 1)
            if method:
                s.container = self.class_name
        saved_body := self.in_class_body
        self.in_class_body = false
        saved := self.root
        self.root = false
        for p in f.params:
            if p.default_value != null:
                self.expr(p.default_value)
        if f.body != null:
            self.stmts(f.body.statements)
        self.root = saved
        self.in_class_body = saved_body

    func type_body(name, kind, n, body, base, interfaces):
        line0 := n.line - 1
        pos := self.find_name(line0, n.column - 1 + 1, name)
        s := self.declare(name, kind, pos[0], pos[1])
        s.doc = self.doc_above(line0)
        detail := ("class " if kind == "class" else "struct " if kind == "struct" else "interface ") + name
        if base != null:
            detail += " extends " + base
        if interfaces != null and len(interfaces) > 0:
            detail += " implements " + _s.join(", ", interfaces)
        s.detail = detail
        saved_class := self.class_name
        saved_sym := self.class_sym
        saved_body := self.in_class_body
        saved := self.root
        self.class_name = name
        self.class_sym = len(self.symbols) - 1
        self.root = false
        self.in_class_body = true
        if body != null:
            for st in body.statements:
                if st.kind == "FunctionDecl":
                    self.function(st, true, false)
                    self.in_class_body = true
                else:
                    self.stmt(st)
        self.root = saved
        self.class_name = saved_class
        self.class_sym = saved_sym
        self.in_class_body = saved_body

    func stmt(s):
        k := s.kind
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
            sy := self.declare(s.name, "enum", pos[0], pos[1])
            sy.doc = self.doc_above(s.line - 1)
            sy.detail = "enum " + s.name
            saved := self.root
            saved_class := self.class_name
            self.class_name = s.name
            self.root = false
            for m in s.members:
                ml := m.line - 1 if m.line > 0 else s.line - 1
                mc := m.column - 1 if m.column > 0 else 0
                fp := self.fix_position(ml, mc, m.name)
                if fp == null:
                    fp = self.find_name(ml, 0, m.name)
                ms := self.declare(m.name, "variant", fp[0], fp[1])
                ms.container = s.name
                d := s.name + "." + m.name
                if m.fields != null and len(m.fields) > 0:
                    d += "(" + _s.join(", ", m.fields) + ")"
                ms.detail = d
            self.root = saved
            self.class_name = saved_class
        elif k == "VariableDecl":
            if s.value != null and not s.declared_only:
                self.expr(s.value)
            fp := self.fix_position(s.line - 1, s.column - 1, s.name)
            if fp == null:
                fp = self.find_name(s.line - 1, 0, s.name)
            sy := self.declare(s.name, "field" if self.in_class_body else "variable", fp[0], fp[1])
            sy.type_name = type_text(s.type) if s.type != null else infer_type(s.value)
            sy.detail = s.name + ("" if sy.type_name == "" or sy.type_name[0] == '=' else ": " + sy.type_name)
            sy.doc = self.doc_above(s.line - 1)
            if self.in_class_body:
                sy.container = self.class_name
        elif k == "ConstDecl":
            if s.value != null:
                self.expr(s.value)
            p := self.find_name(s.line - 1, s.column - 1 + 5, s.name)
            sy := self.declare(s.name, "constant", p[0], p[1])
            line := self.lines[p[0]]
            eq := _s.find(line, ":=")
            val := "" if eq < 0 else _trim(_s.substring(line, eq + 2, len(line)))
            if _s.byte_len(val) > 60:
                val = _s.byte_slice(val, 0, 57) + "..."
            sy.detail = "const " + s.name + ("" if val == "" else " := " + val)
            sy.doc = self.doc_above(s.line - 1)
            if self.in_class_body:
                sy.container = self.class_name
        elif k == "Assignment":
            self.expr(s.value)
            t := s.target
            if t.kind == "MemberExpr" and self.class_sym >= 0 and self.class_name != "":
                if t.object.kind == "Identifier" and t.object.name == "self":
                    exists := false
                    for sy in self.symbols:
                        if sy.kind == "field" and sy.container == self.class_name and sy.name == t.member:
                            exists = true
                    if not exists:
                        fp := self.fix_position(t.line - 1, t.column, t.member)
                        if fp != null:
                            sy := Symbol(t.member, "field", fp[0], fp[1], false)
                            append(self.symbols, sy)
                            sy.container = self.class_name
                            sy.type_name = infer_type(s.value)
                            sy.detail = "self." + t.member + ("" if sy.type_name == "" or sy.type_name[0] == '=' else ": " + sy.type_name)
                            sy.doc = self.doc_above(s.line - 1)
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
            self.block(s.body)
        elif k == "TryStmt":
            self.block(s.try_block)
            for c in s.catch_clauses:
                self.block(c.body)
            self.block(s.finally_block)
        elif k == "MatchStmt":
            self.expr(s.subject)
            for c in s.cases:
                saved := self.root
                self.root = false
                if c.guard != null:
                    self.expr(c.guard)
                if c.body != null:
                    self.stmts(c.body.statements)
                self.root = saved
        elif k == "ImportStmt":
            for n in (s.names if s.is_from else [s.alias if s.alias != null else (s.module_path[len(s.module_path) - 1] if len(s.module_path) > 0 else "")]):
                sy := self.declare(n, "function" if s.is_from else "module", s.line - 1, 0)
                sy.is_import = true

    func expr(e):
        if e == null:
            return
        k := e.kind
        if k == "MemberExpr":
            self.expr(e.object)
        elif k == "CallExpr":
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
            saved := self.root
            self.root = false
            for cl in e.clauses:
                self.expr(cl.expr)
            self.expr(e.element)
            self.expr(e.key)
            self.expr(e.value)
            self.root = saved

func _is_ident_byte(b):
    return (b >= 97 and b <= 122) or (b >= 65 and b <= 90) or (b >= 48 and b <= 57) or b == 95 or b >= 128

# Position d'octet de `sub` dans `s` à partir de l'octet `frm`, -1 sinon.
func _bfind(s, sub, frm):
    if frm >= _s.byte_len(s):
        return -1 if _s.byte_len(sub) > 0 or frm > _s.byte_len(s) else frm
    p := _s.byte_find(_s.byte_slice(s, frm, _s.byte_len(s)), sub)
    return -1 if p < 0 else p + frm

func _rfind(s, sub):
    i := len(s) - len(sub)
    while i >= 0:
        if _s.substring(s, i, i + len(sub)) == sub:
            return i
        i -= 1
    return -1

# Symboles d'un texte source (liste de Symbol, dans l'ordre de déclaration) ; [] si l'analyse échoue.
func index_text(text, path):
    lines := cc.split_lines(text)
    b := Builder(lines)
    prog := null
    try:
        prog = _bp.parse_text(text, path)
    catch e:
        return [lines, []]
    b.stmts(prog.top_level)
    return [lines, b.symbols]

# ------------------------------------------------------------------------------------------- documentation

const _KIND_LABEL := {"class": "classe", "struct": "struct", "interface": "interface", "enum": "enum", "variant": "variante",
                      "function": "fonction", "method": "méthode", "field": "champ", "constant": "constante", "variable": "variable"}

func module_header(lines):
    head := ""
    started := false
    for l in lines:
        t := _trim(l)
        if t == "":
            if started:
                break
            continue
        if t[0] != '#':
            break
        started = true
        body := ""
        if len(t) > 1:
            body = _s.substring(l, _s.find(l, "#") + 1, len(l))
        if len(body) > 0 and body[0] == ' ':
            body = _s.substring(body, 1, len(body))
        tb := _trim(body)
        if tb == "alex: native" or _s.contains(tb, "ALEX STANDARD LIBRARY"):
            continue
        head += body + "\n"
    while len(head) > 0 and head[len(head) - 1] == '\n':
        head = _s.substring(head, 0, len(head) - 1)
    while len(head) > 0 and head[0] == '\n':
        head = _s.substring(head, 1, len(head))
    return head

func _getlines(text):
    ls := _s.split(text, "\n")
    if len(ls) > 0 and ls[len(ls) - 1] == "":
        ls = ls[0:len(ls) - 1]
    return ls

func _indented(line):
    return len(line) >= 2 and line[0] == ' ' and line[1] == ' '

func first_sentence(text):
    t := ""
    for line in _getlines(text):
        tl := _trim(line)
        if tl == "" or _indented(line) or tl[0] == '|':
            if t != "":
                break
            continue
        t += ("" if t == "" else " ") + tl
    # coupe à la première phrase (« . » suivi d'une espace, au-delà de l'octet 15)
    n := _s.byte_len(t)
    i := 16
    while i + 1 < n:
        if _s.byte_at(t, i) == 46 and _s.byte_at(t, i + 1) == 32:
            t = _s.byte_slice(t, 0, i + 1)
            break
        i += 1
    if len(t) > 0 and t[len(t) - 1] == ':':
        t = _s.substring(t, 0, len(t) - 1)
    t = _trim(t)
    if _s.byte_len(t) > 180:
        sp := -1
        j := 177
        while j >= 0:
            if _s.byte_at(t, j) == 32:
                sp = j
                break
            j -= 1
        t = _s.byte_slice(t, 0, 177 if sp < 0 else sp) + "…"
    return t

func html_escape(s):
    return _s.replace(_s.replace(_s.replace(_s.replace(s, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "\"", "&quot;")

func inline_code(esc):
    out := []
    inside := false
    for c in esc:
        if c == '`':
            append(out, "</code>" if inside else "<code>")
            inside = not inside
        else:
            append(out, str(c))
    if inside:
        append(out, "</code>")
    return _s.join("", out)

func _only_table_rule(row):
    for c in row:
        if c != '|' and c != '-' and c != ':' and c != ' ':
            return false
    return true

func comment_to_html(text):
    lines := _getlines(text)
    out := []
    i := 0
    n := len(lines)
    while i < n:
        t := _trim(lines[i])
        if t == "":
            i += 1
            continue
        if t[0] == '|':
            append(out, "<table>")
            head := true
            while i < n and _trim(lines[i]) != "" and _trim(lines[i])[0] == '|':
                row := _trim(lines[i])
                i += 1
                if _s.contains(row, "---") and _only_table_rule(row):
                    continue
                append(out, "<tr>")
                cells := []
                cell := ""
                k := 1
                while k < len(row):
                    if row[k] == '|':
                        append(cells, _trim(cell))
                        cell = ""
                    else:
                        cell += str(row[k])
                    k += 1
                for c in cells:
                    append(out, ("<th>" if head else "<td>") + inline_code(html_escape(c)) + ("</th>" if head else "</td>"))
                append(out, "</tr>")
                head = false
            append(out, "</table>")
            continue
        if _indented(lines[i]):
            append(out, "<pre class=\"code\">")
            while i < n and (_trim(lines[i]) == "" or _indented(lines[i])):
                if _trim(lines[i]) == "" and (i + 1 >= n or not (len(lines[i + 1]) >= 2 and lines[i + 1][0] == ' ')):
                    break
                append(out, html_escape(_s.substring(lines[i], 2, len(lines[i])) if len(lines[i]) >= 2 else "") + "\n")
                i += 1
            append(out, "</pre>")
            continue
        append(out, "<p>")
        first := true
        while i < n and _trim(lines[i]) != "" and _trim(lines[i])[0] != '|' and not _indented(lines[i]):
            if not first:
                append(out, "<br>")
            append(out, inline_code(html_escape(_trim(lines[i]))))
            first = false
            i += 1
        append(out, "</p>")
    return _s.join("", out)

const _CSS := "\n:root{--bg:#05080f;--panel:#0b1220;--line:#16233a;--text:#d8e2f2;--dim:#8193b2;--accent:#2bd4ff;--accent2:#1e6bff;--code:#0e1a2e}\n@media (prefers-color-scheme: light){:root{--bg:#f6f8fc;--panel:#ffffff;--line:#dde4f0;--text:#14203a;--dim:#5a6a88;--accent:#0a78d1;--accent2:#1e6bff;--code:#eef3fb}}\n*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.55 system-ui,-apple-system,\"Segoe UI\",sans-serif}\na{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}\nheader{display:flex;align-items:center;gap:12px;padding:14px 22px;border-bottom:1px solid var(--line);background:linear-gradient(90deg,rgba(30,107,255,.18),transparent)}\nheader .logo{width:30px;height:30px;border-radius:7px;background:linear-gradient(135deg,var(--accent2),var(--accent));display:grid;place-items:center;font-weight:800;color:#fff}\nheader h1{font-size:17px;margin:0;font-weight:650}header .sub{color:var(--dim);font-size:13px}\n.wrap{display:flex;min-height:calc(100vh - 60px)}nav{width:270px;flex:none;border-right:1px solid var(--line);padding:14px;overflow:auto;max-height:calc(100vh - 60px);position:sticky;top:0}\nnav input{width:100%;padding:8px 10px;border-radius:8px;border:1px solid var(--line);background:var(--panel);color:var(--text);margin-bottom:10px}\nnav a{display:block;padding:3px 8px;border-radius:6px;font-size:13.5px;color:var(--text)}nav a:hover{background:var(--panel);text-decoration:none}nav a.cur{background:var(--panel);color:var(--accent)}\nmain{flex:1;padding:22px 34px;max-width:980px;min-width:0}h2{font-size:24px;margin:.2em 0 .4em}h3{font-size:15px;margin:0}\n.entry{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:12px 16px;margin:12px 0}\n.entry .sig{font-family:\"JetBrains Mono\",ui-monospace,Consolas,monospace;font-size:13.5px;color:var(--accent);overflow-x:auto;white-space:pre}\n.kind{font-size:11px;text-transform:uppercase;letter-spacing:.06em;color:var(--dim);margin-right:8px}\n.members{margin:8px 0 0 12px;border-left:2px solid var(--line);padding-left:12px}\npre.code{background:var(--code);border:1px solid var(--line);border-radius:8px;padding:10px 12px;overflow-x:auto;font:13px/1.45 ui-monospace,Consolas,monospace}\ncode{background:var(--code);padding:1px 5px;border-radius:4px;font:13px ui-monospace,Consolas,monospace}\ntable{border-collapse:collapse;margin:8px 0;font-size:13.5px;display:block;overflow-x:auto}td,th{border:1px solid var(--line);padding:5px 9px;text-align:left;vertical-align:top}th{background:var(--panel)}\n.modlist td:first-child{white-space:nowrap}.dim{color:var(--dim)}\n@media (max-width:760px){.wrap{display:block}nav{width:auto;max-height:38vh;position:static;border-right:0;border-bottom:1px solid var(--line)}main{padding:16px}}\n"

func page_html(title, nav_html, body):
    return "<!doctype html><html lang=\"fr\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>" + html_escape(title) + "</title><style>" + _CSS + "</style></head><body><header><div class=\"logo\">A</div><div><h1>ALEX — Référence</h1><div class=\"sub\">" + html_escape(title) + "</div></div></header><div class=\"wrap\"><nav><input id=\"q\" placeholder=\"Filtrer les modules…\" oninput=\"for(const a of document.querySelectorAll('nav a'))a.style.display=a.textContent.toLowerCase().includes(this.value.toLowerCase())?'':'none'\">" + nav_html + "</nav><main>" + body + "</main></div></body></html>\n"

func _entry_html(e, out):
    append(out, "<div class=\"entry\" id=\"" + html_escape(e["name"]) + "\"><div><span class=\"kind\">" + html_escape(e["kind"]) + "</span><span class=\"sig\">" + html_escape(e["signature"]) + "</span></div>")
    if e["doc"] != "":
        append(out, comment_to_html(e["doc"]))
    if len(e["members"]) > 0:
        append(out, "<div class=\"members\">")
        for m in e["members"]:
            _entry_html(m, out)
        append(out, "</div>")
    append(out, "</div>")

func _entry(kind, s, signature):
    return {"kind": _KIND_LABEL[kind] if kind in _KIND_LABEL else kind, "name": s.name, "signature": signature, "doc": s.doc, "line": s.line + 1, "members": []}

func document_file(file, module_name):
    text := ""
    try:
        text = _io.read_file(file)
    catch e:
        text = ""
    ix := index_text(text, file)
    lines := ix[0]
    syms := ix[1]
    d := {"name": module_name, "file": file, "header": module_header(lines), "summary": "", "entries": []}
    d["summary"] = first_sentence(d["header"])
    class_idx := {}
    for s in syms:
        if not s.root or s.is_import or s.name == "" or s.name[0] == '_':
            continue
        if s.kind == "module":
            continue
        sig := s.name if s.detail == "" else s.detail
        if (s.kind == "variable" or s.kind == "constant") and s.line < len(lines):
            sig = _trim(lines[s.line])
        if s.kind == "class" or s.kind == "struct" or s.kind == "interface" or s.kind == "enum":
            class_idx[s.name] = len(d["entries"])
        append(d["entries"], _entry(s.kind, s, sig))
    for s in syms:
        if s.container == "" or s.name == "" or (s.name[0] == '_' and s.name != "init"):
            continue
        if s.kind != "method" and s.kind != "field" and s.kind != "variant" and s.kind != "constant":
            continue
        if not (s.container in class_idx):
            continue
        owner := d["entries"][class_idx[s.container]]
        dup := false
        for m in owner["members"]:
            if m["name"] == s.name:
                dup = true
        if dup:
            continue
        append(owner["members"], _entry(s.kind, s, s.name if s.detail == "" else s.detail))
    return d

# Modules de la bibliothèque standard : [[nom, fichier]...] triés par nom (outils et noms en _ exclus).
func stdlib_modules(root):
    out := []
    _collect(root, root, [], out)
    out = cc.sort_by(out, (a, b) => a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
    uniq := []
    for m in out:
        if len(uniq) == 0 or uniq[len(uniq) - 1][0] != m[0]:
            append(uniq, m)
    return uniq

func _collect(root, dir, rel, out):
    names := []
    try:
        names = _os.list_dir(dir)
    catch e:
        return
    for n in names:
        p := dir + "/" + n
        if _os.isdir(p):
            _collect(root, p, rel + [n], out)
            continue
        if not cc.ends_with(n, ".al") or not _os.isfile(p):
            continue
        stem := _s.substring(n, 0, len(n) - 3)
        if stem == "" or stem[0] == '_':
            continue
        parts := rel + [stem]
        hidden := false
        for q in parts:
            if len(q) > 0 and q[0] == '_':
                hidden = true
        if hidden or parts[0] == "outils":
            continue
        if len(parts) >= 2 and parts[len(parts) - 1] == parts[len(parts) - 2]:
            parts = parts[0:len(parts) - 1]
        append(out, [_s.join(".", parts), p])

func module_file(stdlib_root, workspace, module):
    rel := _s.replace(module, ".", "/")
    last := _os.basename(rel)
    for root in [stdlib_root, workspace]:
        if root == "":
            continue
        a := root + "/" + rel + ".al"
        b := root + "/" + rel + "/" + last + ".al"
        if _os.isfile(a):
            return a
        if _os.isfile(b):
            return b
    return ""

func to_markdown(d):
    o := ["# " + d["name"] + "\n\n"]
    if d["header"] != "":
        in_code := false
        for l in _getlines(d["header"]):
            code := _indented(l)
            if code and not in_code:
                append(o, "```alex\n")
                in_code = true
            elif not code and in_code and _trim(l) != "":
                append(o, "```\n")
                in_code = false
            append(o, (_s.substring(l, 2, len(l)) if code else l) + "\n")
        if in_code:
            append(o, "```\n")
        append(o, "\n")
    for e in d["entries"]:
        _emit_md(e, "##", o)
        for m in e["members"]:
            _emit_md(m, "###", o)
    return _s.join("", o)

func _emit_md(e, level, o):
    append(o, level + " " + e["name"] + " *(" + e["kind"] + ")*\n\n```alex\n" + e["signature"] + "\n```\n\n")
    if e["doc"] != "":
        append(o, e["doc"] + "\n\n")

func _entry_json(e):
    x := {"kind": e["kind"], "name": e["name"], "signature": e["signature"], "doc": e["doc"], "line": e["line"]}
    if len(e["members"]) > 0:
        x["members"] = [_entry_json(m) for m in e["members"]]
    return x

func to_json(d):
    return {"module": d["name"], "file": d["file"], "summary": d["summary"], "header": d["header"], "entries": [_entry_json(e) for e in d["entries"]]}

func _nav(mods, cur):
    n := ["<a href=\"index.html\"" + (" class=\"cur\"" if cur == "" else "") + ">Tous les modules</a>"]
    for m in mods:
        append(n, "<a href=\"" + m["name"] + ".html\"" + (" class=\"cur\"" if m["name"] == cur else "") + ">" + html_escape(m["name"]) + "</a>")
    return _s.join("", n)

func write_html_site(mods, out_dir, title):
    _os.mkdir_all(out_dir)
    idx := ["<h2>" + html_escape(title) + "</h2><p class=\"dim\">" + str(len(mods)) + " modules. Utilisez le filtre à gauche ou <code>alexc doc &lt;module&gt;</code> dans un terminal.</p><table class=\"modlist\"><tr><th>Module</th><th>Résumé</th></tr>"]
    for m in mods:
        append(idx, "<tr><td><a href=\"" + m["name"] + ".html\">" + html_escape(m["name"]) + "</a></td><td>" + inline_code(html_escape(m["summary"])) + "</td></tr>")
    append(idx, "</table>")
    _io.write_file(out_dir + "/index.html", page_html(title, _nav(mods, ""), _s.join("", idx)))
    for m in mods:
        body := ["<h2>" + html_escape(m["name"]) + "</h2>"]
        if m["header"] != "":
            append(body, comment_to_html(m["header"]))
        if len(m["entries"]) > 0:
            append(body, "<p class=\"dim\">")
            i := 0
            for e in m["entries"]:
                append(body, (" · " if i > 0 else "") + "<a href=\"#" + html_escape(e["name"]) + "\">" + html_escape(e["name"]) + "</a>")
                i += 1
            append(body, "</p>")
        for e in m["entries"]:
            _entry_html(e, body)
        _io.write_file(out_dir + "/" + m["name"] + ".html", page_html(m["name"] + " — " + title, _nav(mods, m["name"]), _s.join("", body)))

const _USAGE := "usage: alexc doc <module|fichier.al>... | --json <module> | --html <dossier> [modules] | --list"

func _resolve(t, stdlib_root, ws):
    if _os.isfile(t):
        return [_os.stem(t), _os.absolute(t)]
    return [t, module_file(stdlib_root, ws, t)]

func run(args, stdlib_root):
    mode := "md"
    html_dir := ""
    targets := []
    i := 0
    while i < len(args):
        a := args[i]
        if a == "--json":
            mode = "json"
        elif a == "--list":
            mode = "list"
        elif a == "--html" and i + 1 < len(args):
            mode = "html"
            i += 1
            html_dir = args[i]
        elif a == "-h" or a == "--help":
            print(_USAGE)
            return 0
        else:
            append(targets, a)
        i += 1
    ws := _os.cwd()
    if mode == "list":
        for m in stdlib_modules(stdlib_root):
            # seul le résumé de l'en-tête sert ici : pas d'analyse syntaxique
            text := ""
            try:
                text = _io.read_file(m[1])
            catch e:
                text = ""
            summary := first_sentence(module_header(cc.split_lines(text)))
            line := m[0]
            if summary != "":
                line += _s.repeat(" ", 26 - _s.byte_len(m[0]) if _s.byte_len(m[0]) < 26 else 1) + summary
            print(line)
        return 0
    if mode == "html":
        mods := []
        if len(targets) == 0:
            for m in stdlib_modules(stdlib_root):
                append(mods, document_file(m[1], m[0]))
        else:
            for t in targets:
                r := _resolve(t, stdlib_root, ws)
                if r[1] == "":
                    cc.err("module introuvable : " + t + "\n")
                    return 1
                append(mods, document_file(r[1], r[0]))
        write_html_site(mods, html_dir, "Bibliothèque standard ALEX" if len(targets) == 0 else "Documentation du projet")
        cc.err(str(len(mods)) + " page(s) écrite(s) dans " + html_dir + "\n")
        return 0
    if len(targets) == 0:
        cc.err(_USAGE + "\n")
        return 1
    for t in targets:
        r := _resolve(t, stdlib_root, ws)
        if r[1] == "":
            cc.err("module introuvable : " + t + "\n")
            return 1
        d := document_file(r[1], r[0])
        if mode == "json":
            print(cc.json_dump(to_json(d)))
        else:
            cc.out(to_markdown(d))
    return 0

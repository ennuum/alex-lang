# ALEX STANDARD LIBRARY — compiler.codegen
#
# Génération de code et chaîne de compilation complète.
#   emit_alex(arbre)        source ALEX formatée (indentation 4 espaces, parenthèses minimales selon les
#                           priorités) : sert de formateur et garantit l'aller-retour parse(emit(arbre)) == arbre
#   emit_alex_mapped(arbre, fichier_source)   [texte, SourceMap] (ligne générée -> ligne d'origine)
#   emit_python(arbre)      transpilation vers Python 3 du sous-ensemble procédural (fonctions, contrôle,
#                           expressions, compréhensions, try/catch) ; CodegenError pour le reste
#   emit_ir(module)         listing de l'IR (compiler.ir.format)
#   compile(source, ...)    lexer -> parser -> vérification -> optimisation -> IR -> optimisation IR ;
#                           CompileResult (ast, ir, diagnostics, stats, run())
#
#   use compiler.codegen as cg
#   print(cg.format_source("x:=1+2\nif x>2 :\n  print( x )\n"))    # x := 1 + 2 / if x > 2: / print(x)
#   r := cg.compile("func f(n) => n * 2\nprint(f(21))\n", "demo.al")
#   if r.ok:
#       r.run()                              # 42 (interpréteur IR)
#   print(r.diagnostics.render())
#   print(cg.emit_python(r.ast))             # def f(n): return n * 2 ...
#
# Erreurs : CodegenError (construction non traduisible), ParseError / LexError (compile avec raise_errors).

from core use len, type
from collections use append
use string as _s
use compiler.ast as _ast
use compiler.parser as _ps
use compiler.lexer as _lx
use compiler.ir as _ir
use compiler.optimizer as _opt
use compiler.type_checker as _tc
use compiler.diagnostics as _dg
use compiler.source_map as _sm
use _native_net as _net

# Priorités (plus grand = plus serré).
const PREC := {"or": 3, "and": 4, "==": 6, "!=": 6, "<": 6, "<=": 6, ">": 6, ">=": 6, "in": 6, "not in": 6,
    "|": 7, "^": 8, "&": 9, "<<": 10, ">>": 10, "+": 11, "-": 11, "*": 12, "/": 12, "//": 12, "%": 12, "**": 13}

func _esc(text, fstring=false):
    out := []
    for c in text:
        o := _s.ord(c)
        if c == '\\':
            append(out, "\\\\")
        elif c == '"':
            append(out, "\\\"")
        elif c == '\n':
            append(out, "\\n")
        elif c == '\t':
            append(out, "\\t")
        elif c == '\r':
            append(out, "\\r")
        elif o == 0:
            append(out, "\\0")
        elif o == 27:
            append(out, "\\e")
        elif o < 32 or o == 127:
            append(out, "\\x" + _hex2(o))
        elif fstring and c == '{':
            append(out, "{{")
        elif fstring and c == '}':
            append(out, "}}")
        else:
            append(out, str(c))
    return _s.join("", out)

func _hex2(n):
    d := "0123456789abcdef"
    return str(d[n // 16]) + str(d[n % 16])

func lit_text(v):
    t := type(v)
    if v == null:
        return "null"
    if t == "bool":
        if v:
            return "true"
        return "false"
    if t == "str":
        return "\"" + _esc(v) + "\""
    if t == "char":
        if v == '\'':
            return "'\\''"
        e := _esc(str(v))
        if e == "\\\"":
            e = "\""
        return "'" + e + "'"
    if t == "float":
        s := _net.repr_float(v)
        if not _s.contains(s, ".") and not _s.contains(s, "e") and not _s.contains(s, "n"):
            s = s + ".0"
        return s
    return str(v)

class AlexEmitter:
    func init(source_file=null):
        self.lines = []
        self.map = null
        self.source_file = source_file
        if source_file != null:
            self.map = _sm.SourceMap("<formaté>")

    func line(depth, text, n=null):
        append(self.lines, _s.repeat("    ", depth) + text)
        if self.map != null and n != null and n.line > 0:
            self.map.add(len(self.lines), depth * 4 + 1, self.source_file, n.line, n.column)

    func program(p):
        prev := null
        for s in p.body:
            if prev != null and (_is_def(s) or _is_def(prev)) and not (_is_import(s) and _is_import(prev)):
                append(self.lines, "")
            self.stmt(s, 0)
            prev = s
        return _s.join("\n", self.lines) + "\n"

    func body(stmts, depth):
        if len(stmts) == 0:
            self.line(depth, "pass")
            return
        for s in stmts:
            self.stmt(s, depth)

    func type_ref(t):
        if t == null:
            return ""
        out := t.name
        if t.name == "func":
            n := len(t.args)
            ps := [self.type_ref(a) for a in t.args[:n - 1]]
            out = "func(" + _s.join(", ", ps) + ")"
            if n > 0 and t.args[n - 1].name != "any":
                out += " -> " + self.type_ref(t.args[n - 1])
        elif len(t.args) > 0:
            out += "[" + _s.join(", ", [self.type_ref(a) for a in t.args]) + "]"
        if t.nullable:
            out += "?"
        return out

    func params(ps):
        out := []
        for p in ps:
            s := p.name
            if p.rest:
                s = "*" + s
            if p.type != null:
                s += ": " + self.type_ref(p.type)
            if p.default != null:
                s += "=" + self.expr(p.default, 0)
            append(out, s)
        return _s.join(", ", out)

    func stmt(s, d):
        k := s.kind
        if k == "ExprStmt":
            self.line(d, self.expr(s.expr, 0), s)
        elif k == "VarDecl":
            head := s.name
            if s.type != null:
                head += ": " + self.type_ref(s.type)
                if s.declared_only:
                    self.line(d, head, s)
                    return
            self.line(d, head + " := " + self.rhs(s.value), s)
        elif k == "Const":
            head := "const " + s.name
            if s.type != null:
                head += ": " + self.type_ref(s.type)
            self.line(d, head + " := " + self.expr(s.value, 0), s)
        elif k == "Assign":
            self.line(d, self.expr(s.target, 0) + " = " + self.rhs(s.value), s)
        elif k == "CompoundAssign":
            self.line(d, self.expr(s.target, 0) + " " + s.op + "= " + self.expr(s.value, 0), s)
        elif k == "Destructure":
            ts := []
            for t in s.targets:
                if t.star:
                    append(ts, "*" + self.expr(t.expr, 0))
                else:
                    append(ts, self.expr(t.expr, 0))
            op := " = "
            if s.declare:
                op = " := "
            self.line(d, _s.join(", ", ts) + op + self.rhs(s.value), s)
        elif k == "Use":
            t := "use " + _s.join(".", s.path)
            if s.alias != null:
                t += " as " + s.alias
            self.line(d, t, s)
        elif k == "FromUse":
            self.line(d, "from " + _s.join(".", s.path) + " use " + _s.join(", ", s.names), s)
        elif k == "Func":
            self.function(s, d)
        elif k == "Class":
            head := "class " + s.name
            if s.base != null:
                head += " extends " + s.base
            if len(s.interfaces) > 0:
                head += " implements " + _s.join(", ", s.interfaces)
            self.line(d, head + ":", s)
            self.members(s.body, d + 1)
        elif k == "Struct" or k == "Interface":
            self.line(d, _s.lower(k) + " " + s.name + ":", s)
            self.members(s.body, d + 1)
        elif k == "Enum":
            self.line(d, "enum " + s.name + ":", s)
            for m in s.members:
                if len(m.fields) == 0:
                    self.line(d + 1, m.name, m)
                else:
                    fs := []
                    for f in m.fields:
                        if f.type != null:
                            append(fs, f.name + ": " + self.type_ref(f.type))
                        else:
                            append(fs, f.name)
                    self.line(d + 1, m.name + "(" + _s.join(", ", fs) + ")", m)
        elif k == "If":
            self.line(d, "if " + self.expr(s.cond, 0) + ":", s)
            self.body(s.then_body, d + 1)
            for e in s.elifs:
                self.line(d, "elif " + self.expr(e.cond, 0) + ":", e)
                self.body(e.body, d + 1)
            if s.else_body != null:
                self.line(d, "else:")
                self.body(s.else_body, d + 1)
        elif k == "While":
            self.line(d, "while " + self.expr(s.cond, 0) + ":", s)
            self.body(s.body, d + 1)
            if s.else_body != null:
                self.line(d, "else:")
                self.body(s.else_body, d + 1)
        elif k == "For":
            vs := []
            for v in s.vars:
                if v.star:
                    append(vs, "*" + v.expr.name)
                else:
                    append(vs, v.expr.name)
            self.line(d, "for " + _s.join(", ", vs) + " in " + self.expr(s.iter, 0) + ":", s)
            self.body(s.body, d + 1)
            if s.else_body != null:
                self.line(d, "else:")
                self.body(s.else_body, d + 1)
        elif k == "Try":
            self.line(d, "try:", s)
            self.body(s.body, d + 1)
            for c in s.catches:
                head := "catch"
                if len(c.types) == 0:
                    if c.name != null:
                        head += " " + c.name
                elif c.name != null and len(c.types) >= 1:
                    head += " (" + _s.join(", ", c.types) + ") as " + c.name
                else:
                    head += " (" + _s.join(", ", c.types) + ")"
                self.line(d, head + ":", c)
                self.body(c.body, d + 1)
            if s.finally_body != null:
                self.line(d, "finally:")
                self.body(s.finally_body, d + 1)
        elif k == "Match":
            self.line(d, "match " + self.expr(s.subject, 0) + ":", s)
            for c in s.cases:
                head := self.pattern(c.pattern)
                if c.guard != null:
                    head += " if " + self.expr(c.guard, 0)
                self.line(d + 1, head + ":", c)
                self.body(c.body, d + 2)
        elif k == "Break":
            self.line(d, "break", s)
        elif k == "Continue":
            self.line(d, "continue", s)
        elif k == "Return":
            if s.value == null:
                self.line(d, "return", s)
            else:
                self.line(d, "return " + self.rhs(s.value), s)
        elif k == "Pass":
            self.line(d, "pass", s)
        elif k == "With":
            t := "with " + self.expr(s.resource, 0)
            if s.name != null:
                t += " as " + s.name
            self.line(d, t + ":", s)
            self.body(s.body, d + 1)
        elif k == "Assert":
            t := "assert " + self.expr(s.cond, 0)
            if s.message != null:
                t += ", " + self.expr(s.message, 0)
            self.line(d, t, s)
        elif k == "Del":
            self.line(d, "del " + _s.join(", ", [self.expr(t, 0) for t in s.targets]), s)
        elif k == "Extend":
            self.line(d, "extend " + s.type_name + ":", s)
            self.members(s.methods, d + 1)
        else:
            raise("CodegenError", "emit_alex : instruction inconnue " + k)

    func members(stmts, d):
        if len(stmts) == 0:
            self.line(d, "pass")
            return
        first := true
        for s in stmts:
            if not first and s.kind == "Func" and not (s.short or len(s.body) == 0):
                append(self.lines, "")
            self.stmt(s, d)
            first = false

    func function(f, d):
        for dec in f.decorators:
            self.line(d, "@" + self.expr(dec, 0), dec)
        head := "func " + f.name + "(" + self.params(f.params) + ")"
        if f.is_async:
            head = "async " + head
        if f.ret_type != null:
            head += " -> " + self.type_ref(f.ret_type)
        if f.short:
            self.line(d, head + " => " + self.expr(f.body[0].value, 0), f)
        elif len(f.body) == 0:
            self.line(d, head, f)
        else:
            self.line(d, head + ":", f)
            self.body(f.body, d + 1)

    func pattern(p):
        k := p.pk
        if k == "wildcard":
            return "_"
        if k == "bind":
            return p.name
        if k == "literal":
            return lit_text(p.value)
        if k == "range":
            return lit_text(p.low) + ".." + lit_text(p.high)
        if k == "list":
            return "[" + _s.join(", ", [self.pattern(x) for x in p.items]) + "]"
        if k == "tuple":
            return "(" + _s.join(", ", [self.pattern(x) for x in p.items]) + ")"
        if k == "variant":
            t := p.enum_name + "." + p.variant
            if len(p.items) > 0:
                t += "(" + _s.join(", ", [self.pattern(x) for x in p.items]) + ")"
            return t
        raise("CodegenError", "motif inconnu " + str(k))

    # valeur à droite d'une affectation / d'un return : un tuple s'écrit sans parenthèses
    func rhs(e):
        if e.kind == "TupleLit" and len(e.elements) >= 2 and e.elements[0].kind != "Spread":
            return _s.join(", ", [self.expr(x, 1) for x in e.elements])
        return self.expr(e, 0)

    func wrap(text, prec, ctx):
        if prec < ctx:
            return "(" + text + ")"
        return text

    func args(lst):
        out := []
        for a in lst:
            if a.name != null:
                append(out, a.name + "=" + self.expr(a.value, 0))
            else:
                append(out, self.expr(a.value, 0))
        return _s.join(", ", out)

    func elems(lst):
        return _s.join(", ", [self.expr(x, 0) for x in lst])

    func expr(e, ctx):
        k := e.kind
        if k == "Literal":
            t := lit_text(e.value)
            if e.has("raw"):
                t = e.raw
            if (type(e.value) == "int" or type(e.value) == "float") and e.value < 0:
                return self.wrap(t, 14, ctx)
            return t
        if k == "Name":
            return e.name
        if k == "FString":
            out := []
            for p in e.parts:
                if _ast.is_node(p):
                    append(out, "{" + self.expr(p, 0) + "}")
                else:
                    append(out, _esc(p, true))
            return "f\"" + _s.join("", out) + "\""
        if k == "Binary":
            p := PREC[e.op]
            lc := p
            rc := p + 1
            if e.op == "**":
                lc = p + 1
                rc = p
            if p == 6:
                lc = p + 1
            return self.wrap(self.expr(e.left, lc) + " " + e.op + " " + self.expr(e.right, rc), p, ctx)
        if k == "Unary":
            if e.op == "not":
                return self.wrap("not " + self.expr(e.operand, 5), 5, ctx)
            if e.op == "await":
                return self.wrap("await " + self.expr(e.operand, 14), 14, ctx)
            return self.wrap(e.op + self.expr(e.operand, 14), 14, ctx)
        if k == "Ternary":
            return self.wrap(self.expr(e.then_expr, 2) + " if " + self.expr(e.cond, 1) + " else " + self.expr(e.else_expr, 1), 1, ctx)
        if k == "Range":
            return self.wrap(self.expr(e.start, 3) + ".." + self.expr(e.end, 3), 2, ctx)
        if k == "Call":
            return self.expr(e.callee, 15) + "(" + self.args(e.args) + ")"
        if k == "Member":
            return self.expr(e.object, 15) + "." + e.member
        if k == "Index":
            return self.expr(e.object, 15) + "[" + self.expr(e.index, 0) + "]"
        if k == "Slice":
            t := self.expr(e.object, 15) + "["
            if e.start != null:
                t += self.expr(e.start, 0)
            t += ":"
            if e.stop != null:
                t += self.expr(e.stop, 0)
            if e.step != null:
                t += ":" + self.expr(e.step, 0)
            return t + "]"
        if k == "Propagate":
            return self.expr(e.operand, 15) + "?"
        if k == "Spread":
            return "*" + self.expr(e.value, 0)
        if k == "Lambda":
            ps := e.params
            head := ""
            if len(ps) == 1 and ps[0].type == null and ps[0].default == null and not ps[0].rest:
                head = ps[0].name
            else:
                head = "(" + self.params(ps) + ")"
            return self.wrap(head + " => " + self.expr(e.body, 0), 0, ctx)
        if k == "ListLit":
            return "[" + self.elems(e.elements) + "]"
        if k == "TupleLit":
            if len(e.elements) == 1:
                return "(" + self.elems(e.elements) + ",)"
            return "(" + self.elems(e.elements) + ")"
        if k == "SetLit":
            return "{" + self.elems(e.elements) + "}"
        if k == "DictLit":
            out := []
            for en in e.entries:
                if en.kind == "DictSpread":
                    append(out, "**" + self.expr(en.value, 0))
                else:
                    append(out, self.expr(en.key, 0) + ": " + self.expr(en.value, 0))
            return "{" + _s.join(", ", out) + "}"
        if k == "Comprehension":
            cl := []
            for c in e.clauses:
                if c.kind == "CompFor":
                    append(cl, "for " + c.var + " in " + self.expr(c.iter, 2))
                else:
                    append(cl, "if " + self.expr(c.cond, 3))
            tail := " " + _s.join(" ", cl)
            if e.comp == "list":
                return "[" + self.expr(e.element, 2) + tail + "]"
            if e.comp == "set":
                return "{" + self.expr(e.element, 2) + tail + "}"
            return "{" + self.expr(e.key, 2) + ": " + self.expr(e.value, 2) + tail + "}"
        raise("CodegenError", "emit_alex : expression inconnue " + k)

func _is_def(s):
    return s.kind == "Func" or s.kind == "Class" or s.kind == "Struct" or s.kind == "Interface" or s.kind == "Enum" or s.kind == "Extend"

func _is_import(s):
    return s.kind == "Use" or s.kind == "FromUse"

func emit_alex(program):
    return AlexEmitter().program(program)

func emit_alex_mapped(program, source_file="<source>"):
    em := AlexEmitter(source_file)
    text := em.program(program)
    return [text, em.map]

# Reformate un texte source ALEX (les commentaires ne sont pas conservés).
func format_source(source, file="<source>"):
    return emit_alex(_ps.parse(source, file))

# ---------------------------------------------------------------------------------------------------------
# Python 3
# ---------------------------------------------------------------------------------------------------------

const PY_PRELUDE := "class AlexError(Exception):\n    def __init__(self, type_, message):\n        super().__init__(f\"{type_}: {message}\")\n        self.type = type_\n        self.message = message\n\n\ndef alex_raise(type_, message=\"\"):\n    raise AlexError(type_, message)\n\n\ndef alex_str(v):\n    if v is None:\n        return \"null\"\n    if v is True:\n        return \"true\"\n    if v is False:\n        return \"false\"\n    return str(v)\n"

const PY_NAMES := {"str": "alex_str", "raise": "alex_raise", "null": "None", "self": "self"}

class PythonEmitter:
    func init():
        self.lines = []
        self.uses_prelude = false

    func line(d, t):
        append(self.lines, _s.repeat("    ", d) + t)

    func fail(n, what):
        raise("CodegenError", "emit_python : " + what + " non traduisible en Python (ligne " + str(n.line) + ")")

    func program(p):
        body := []
        for s in p.body:
            self.stmt(s, 0)
        return PY_PRELUDE + "\n\n" + _s.join("\n", self.lines) + "\n"

    func body(stmts, d):
        if len(stmts) == 0:
            self.line(d, "pass")
        for s in stmts:
            self.stmt(s, d)

    func params(ps):
        out := []
        for p in ps:
            t := p.name
            if p.rest:
                t = "*" + t
            if p.default != null:
                t += "=" + self.expr(p.default)
            append(out, t)
        return _s.join(", ", out)

    func stmt(s, d):
        k := s.kind
        if k == "ExprStmt":
            self.line(d, self.expr(s.expr))
        elif k == "VarDecl" or k == "Const":
            v := "None"
            if s.value != null:
                v = self.expr(s.value)
            self.line(d, s.name + " = " + v)
        elif k == "Assign":
            self.line(d, self.expr(s.target) + " = " + self.expr(s.value))
        elif k == "CompoundAssign":
            self.line(d, self.expr(s.target) + " " + s.op + "= " + self.expr(s.value))
        elif k == "Destructure":
            ts := []
            for t in s.targets:
                if t.star:
                    append(ts, "*" + self.expr(t.expr))
                else:
                    append(ts, self.expr(t.expr))
            self.line(d, _s.join(", ", ts) + " = " + self.expr(s.value))
        elif k == "Func":
            for dec in s.decorators:
                self.line(d, "@" + self.expr(dec))
            head := "def "
            if s.is_async:
                head = "async def "
            self.line(d, head + s.name + "(" + self.params(s.params) + "):")
            self.body(s.body, d + 1)
            self.line(0, "")
        elif k == "If":
            self.line(d, "if " + self.expr(s.cond) + ":")
            self.body(s.then_body, d + 1)
            for e in s.elifs:
                self.line(d, "elif " + self.expr(e.cond) + ":")
                self.body(e.body, d + 1)
            if s.else_body != null:
                self.line(d, "else:")
                self.body(s.else_body, d + 1)
        elif k == "While":
            self.line(d, "while " + self.expr(s.cond) + ":")
            self.body(s.body, d + 1)
            if s.else_body != null:
                self.line(d, "else:")
                self.body(s.else_body, d + 1)
        elif k == "For":
            vs := []
            for v in s.vars:
                if v.star:
                    append(vs, "*" + v.expr.name)
                else:
                    append(vs, v.expr.name)
            self.line(d, "for " + _s.join(", ", vs) + " in " + self.expr(s.iter) + ":")
            self.body(s.body, d + 1)
            if s.else_body != null:
                self.line(d, "else:")
                self.body(s.else_body, d + 1)
        elif k == "Try":
            self.line(d, "try:")
            self.body(s.body, d + 1)
            for c in s.catches:
                nm := c.name
                if nm == null:
                    nm = "_e"
                if len(c.types) == 0:
                    self.line(d, "except AlexError as " + nm + ":")
                    self.body(c.body, d + 1)
                else:
                    self.line(d, "except AlexError as " + nm + ":")
                    self.line(d + 1, "if " + nm + ".type not in (" + _s.join(", ", ["\"" + t + "\"" for t in c.types]) + ",):")
                    self.line(d + 2, "raise")
                    self.body(c.body, d + 1)
            if s.finally_body != null:
                self.line(d, "finally:")
                self.body(s.finally_body, d + 1)
        elif k == "Break" or k == "Continue" or k == "Pass":
            self.line(d, _s.lower(k))
        elif k == "Return":
            if s.value == null:
                self.line(d, "return None")
            else:
                self.line(d, "return " + self.expr(s.value))
        elif k == "Assert":
            t := "assert " + self.expr(s.cond)
            if s.message != null:
                t += ", " + self.expr(s.message)
            self.line(d, t)
        elif k == "Del":
            self.line(d, "del " + _s.join(", ", [self.expr(t) for t in s.targets]))
        elif k == "Use" or k == "FromUse":
            self.line(d, "# " + _s.lower(k) + " " + _s.join(".", s.path) + " : module ALEX sans équivalent Python")
        elif k == "Class":
            base := ""
            if s.base != null:
                base = "(" + s.base + ")"
            self.line(d, "class " + s.name + base + ":")
            if len(s.body) == 0:
                self.line(d + 1, "pass")
            for m in s.body:
                if m.kind == "Func":
                    ps := m.params
                    nm := m.name
                    if nm == "init":
                        nm = "__init__"
                    self.line(d + 1, "def " + nm + "(self" + _s.join("", [", " + x for x in [self.params(ps)] if x != ""]) + "):")
                    self.body(m.body, d + 2)
                elif m.kind == "VarDecl":
                    v := "None"
                    if m.value != null:
                        v = self.expr(m.value)
                    self.line(d + 1, m.name + " = " + v)
                else:
                    self.stmt(m, d + 1)
            self.line(0, "")
        else:
            self.fail(s, k)

    func expr(e):
        k := e.kind
        if k == "Literal":
            v := e.value
            if v == null:
                return "None"
            if type(v) == "bool":
                if v:
                    return "True"
                return "False"
            if type(v) == "char":
                return "\"" + _esc(str(v)) + "\""
            return lit_text(v)
        if k == "Name":
            if e.name in PY_NAMES:
                return PY_NAMES[e.name]
            return e.name
        if k == "FString":
            out := []
            for p in e.parts:
                if _ast.is_node(p):
                    append(out, "{alex_str(" + self.expr(p) + ")}")
                else:
                    append(out, _esc(p, true))
            return "f\"" + _s.join("", out) + "\""
        if k == "Binary":
            return "(" + self.expr(e.left) + " " + e.op + " " + self.expr(e.right) + ")"
        if k == "Unary":
            if e.op == "not":
                return "(not " + self.expr(e.operand) + ")"
            return "(" + e.op + " " + self.expr(e.operand) + ")"
        if k == "Ternary":
            return "(" + self.expr(e.then_expr) + " if " + self.expr(e.cond) + " else " + self.expr(e.else_expr) + ")"
        if k == "Range":
            return "range(" + self.expr(e.start) + ", " + self.expr(e.end) + ")"
        if k == "Call":
            out := []
            for a in e.args:
                if a.name != null:
                    append(out, a.name + "=" + self.expr(a.value))
                else:
                    append(out, self.expr(a.value))
            return self.expr(e.callee) + "(" + _s.join(", ", out) + ")"
        if k == "Member":
            return self.expr(e.object) + "." + e.member
        if k == "Index":
            return self.expr(e.object) + "[" + self.expr(e.index) + "]"
        if k == "Slice":
            parts := []
            for p in [e.start, e.stop, e.step]:
                if p == null:
                    append(parts, "")
                else:
                    append(parts, self.expr(p))
            t := parts[0] + ":" + parts[1]
            if e.step != null:
                t += ":" + parts[2]
            return self.expr(e.object) + "[" + t + "]"
        if k == "Spread":
            return "*" + self.expr(e.value)
        if k == "Lambda":
            return "(lambda " + self.params(e.params) + ": " + self.expr(e.body) + ")"
        if k == "ListLit":
            return "[" + _s.join(", ", [self.expr(x) for x in e.elements]) + "]"
        if k == "TupleLit":
            return "(" + _s.join(", ", [self.expr(x) for x in e.elements]) + ",)"
        if k == "SetLit":
            return "{" + _s.join(", ", [self.expr(x) for x in e.elements]) + "}"
        if k == "DictLit":
            out := []
            for en in e.entries:
                if en.kind == "DictSpread":
                    append(out, "**" + self.expr(en.value))
                else:
                    append(out, self.expr(en.key) + ": " + self.expr(en.value))
            return "{" + _s.join(", ", out) + "}"
        if k == "Comprehension":
            cl := []
            for c in e.clauses:
                if c.kind == "CompFor":
                    append(cl, "for " + c.var + " in " + self.expr(c.iter))
                else:
                    append(cl, "if " + self.expr(c.cond))
            tail := " " + _s.join(" ", cl)
            if e.comp == "list":
                return "[" + self.expr(e.element) + tail + "]"
            if e.comp == "set":
                return "{" + self.expr(e.element) + tail + "}"
            return "{" + self.expr(e.key) + ": " + self.expr(e.value) + tail + "}"
        if k == "Unary" and e.op == "await":
            return "(await " + self.expr(e.operand) + ")"
        self.fail(e, k)

func emit_python(program):
    return PythonEmitter().program(program)

func emit_ir(module):
    return _ir.format(module)

# ---------------------------------------------------------------------------------------------------------
# Chaîne complète
# ---------------------------------------------------------------------------------------------------------

class CompileResult:
    func init(file, source):
        self.file = file
        self.source = source
        self.tokens = null
        self.ast = null
        self.ir = null
        self.diagnostics = _dg.DiagnosticBag(file, source)
        self.stats = {}
        self.ok = false
        self.phases = []

    # Exécute l'IR (interpréteur de référence) ; renvoie l'interpréteur (sortie capturée si capture).
    func run(capture=false, others=null):
        if self.ir == null:
            raise("CodegenError", "CompileResult.run : pas d'IR (compilation échouée ou construction non prise en charge)")
        vm := _ir.Interpreter()
        if capture:
            vm.capture()
        if others != null:
            for o in others:
                vm.register(o)
        vm.run(self.ir)
        return vm

    func summary():
        return self.file + " : " + _s.join(" -> ", self.phases) + " ; " + _dg.summary(self.diagnostics.items)

# opt_level : 0 / 1 / 2 ; check : vérification sémantique ; to_ir : abaisser vers l'IR.
func compile(source, file="<source>", opt_level=2, check=true, to_ir=true, module_name=null):
    r := CompileResult(file, source)
    try:
        r.tokens = _lx.tokenize(source, file)
        append(r.phases, "lexer")
        r.ast = _ps.parse_tokens(r.tokens, file)
        append(r.phases, "parser")
    catch e:
        d := _dg.from_error(e, file)
        d.phase = e.type
        if e.type == "LexError":
            d.code = "E0101"
        else:
            d.code = "E0201"
        r.diagnostics.add(d)
        return r
    if check:
        r.diagnostics.extend(_tc.check(r.ast, file, source, true))
        append(r.phases, "vérification")
        if r.diagnostics.has_errors():
            return r
    o := _opt.Optimizer(opt_level)
    o.run_ast(r.ast)
    if opt_level > 0:
        append(r.phases, "optimisation")
    if to_ir:
        nm := module_name
        if nm == null:
            nm = _module_name(file)
        try:
            r.ir = _ir.lower(r.ast, nm)
            append(r.phases, "ir")
            o.run_ir(r.ir)
            if opt_level > 1:
                append(r.phases, "optimisation-ir")
        catch e:
            r.diagnostics.error("E0501", e.message, 0, 0, 1, "IrError")
            r.ir = null
    r.stats = o.stats
    r.ok = not r.diagnostics.has_errors()
    return r

func _module_name(file):
    b := file
    i := len(b) - 1
    while i >= 0:
        if b[i] == '/':
            b = _s.substring(b, i + 1, len(b))
            break
        i -= 1
    if _s.ends_with(b, ".al"):
        b = _s.substring(b, 0, len(b) - 3)
    if b == "" or _s.starts_with(b, "<"):
        return "main"
    return b

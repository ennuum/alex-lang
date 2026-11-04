# ALEX STANDARD LIBRARY — web.js.js_statement
#
# Instructions JavaScript (AST) : déclarations let / const / var, if / else, boucles (for, for…of, for…in,
# while, do…while), switch, try / catch / finally, return, throw, break, continue, étiquettes, commentaires,
# blocs et programmes. Génération indentée ou compacte, avec ou sans points-virgules (protection ASI : une
# ligne commençant par ( [ ` + - / reçoit un « ; » de tête).
#
#   use web.js.js_statement as js
#   use web.js.js_expression as je
#   p := js.Program([
#       js.const_decl("items", je.array([1, 2, 3])),
#       js.for_of("const", "x", je.ident("items"), [je.log([je.ident("x")])]),
#       js.if_stmt(je.ident("items").dot("length").op(">", 2), [js.ret(je.lit(true))], [js.ret(je.lit(false))]),
#   ])
#   p.to_js()            # const items = [1, 2, 3];\nfor (const x of items) {\n  console.log(x);\n}\n...
#   p.to_js(je.compact_style())    # const items=[1,2,3];for(const x of items){console.log(x);}...
#
# Erreurs : JsError (genre de déclaration inconnu, constante sans valeur, structure invalide).

from core use len, type
from collections use append
use string as _s
use web.js.js_errors as _err
use web.js.js_types as _t
use web.js.js_expression as _e

const DECLARATION_KINDS := ["let", "const", "var", "using", "await using"]

class Stmt:
    func to_js(style=null, level=0):
        return self.emit(_e.style_of(style), level)

    func __str__():
        return self.to_js()

func _semi(s):
    return ";" if s.semicolons else ""

# Instruction depuis une valeur : Stmt inchangée, Expr -> ExprStmt, texte -> code brut.
func stmt(x):
    if isinstance(x, Stmt):
        return x
    if _is_declaration(x):
        return x
    if isinstance(x, _e.Expr):
        return ExprStmt(x)
    if type(x) == "str":
        return RawStmt(x)
    try:
        f := x.emit
        return x
    catch e:
        _err.js_error("js_statement.stmt", "instruction attendue, reçu " + type(x))

# Vrai pour une déclaration de fonction ou de classe nommée (web.js.js_function), émise sans parenthèses.
func _is_declaration(x):
    try:
        return x.is_declaration == true
    catch e:
        return false

func stmts(items):
    out := []
    if items == null:
        return out
    if type(items) != "list":
        return [stmt(items)]
    for x in items:
        append(out, stmt(x))
    return out

func _body(items, s, level):
    return _e.emit_block(_guard_asi(stmts(items), s), s, level)

# Sans points-virgules, protège les instructions qui commenceraient par ( [ ` + - /.
func _guard_asi(items, s):
    if s.semicolons:
        return items
    out := []
    for x in items:
        append(out, _AsiGuard(x))
    return out

class _AsiGuard:
    func init(inner):
        self.inner = inner

    func emit(s, level):
        t := self.inner.emit(s, level)
        if len(t) > 0 and (t[0] == '(' or t[0] == '[' or t[0] == '`' or t[0] == '+' or t[0] == '-' or t[0] == '/'):
            return ";" + t
        return t

class ExprStmt extends Stmt:
    func init(expression):
        self.kind = "expression"
        self.expression = expression

    func emit(s, level):
        t := self.expression.emit(s, level)
        if _s.starts_with(t, "{") or _s.starts_with(t, "function") or _s.starts_with(t, "class ") or _s.starts_with(t, "let [") or _s.starts_with(t, "async function"):
            t = "(" + t + ")"
        return t + _semi(s)

class RawStmt extends Stmt:
    func init(code):
        self.kind = "raw"
        self.code = str(code)

    func emit(s, level):
        return self.code

class Comment extends Stmt:
    func init(text, block=false):
        self.kind = "comment"
        self.text = str(text)
        self.block = block

    func emit(s, level):
        if self.block or s.compact:
            if s.compact and not _s.starts_with(self.text, "!"):
                return ""
            return "/* " + _s.replace(self.text, "*/", "* /") + " */"
        lines := _s.split(self.text, "\n")
        out := []
        for l in lines:
            append(out, "// " + l)
        return _s.join("\n" + s.pad(level), out)

class Empty extends Stmt:
    func init():
        self.kind = "empty"

    func emit(s, level):
        return ";"

# Déclaration : declarators : liste de (cible, valeur ou null) ; cible : nom ou motif (ObjectExpr / ArrayExpr / Raw).
class VarDecl extends Stmt:
    func init(kind, declarators):
        if not (kind in DECLARATION_KINDS):
            _err.js_error("js_statement.VarDecl", "genre de déclaration inconnu « " + str(kind) + " »")
        for d in declarators:
            if (kind == "const" or kind == "using" or kind == "await using") and d[1] == null:
                _err.js_error("js_statement.VarDecl", "« " + kind + " » sans valeur initiale")
            if type(d[0]) == "str" and not _t.is_identifier(d[0]):
                _err.js_error("js_statement.VarDecl", "nom de variable invalide « " + d[0] + " »")
        self.kind = kind
        self.declarators = declarators

    func emit_head(s, level):
        parts := []
        for d in self.declarators:
            target := d[0] if type(d[0]) == "str" else d[0].emit(s, level)
            if d[1] == null:
                append(parts, target)
            else:
                append(parts, target + s.sp() + "=" + s.sp() + _e._paren(_e.expr(d[1]), s, level, _e.P_ASSIGN))
        return self.kind + " " + _s.join("," + s.sp(), parts)

    func emit(s, level):
        return self.emit_head(s, level) + _semi(s)

class Return extends Stmt:
    func init(argument=null):
        self.kind = "return"
        self.argument = argument

    func emit(s, level):
        if self.argument == null:
            return "return" + _semi(s)
        return "return " + _e.expr(self.argument).emit(s, level) + _semi(s)

class Throw extends Stmt:
    func init(argument):
        self.kind = "throw"
        self.argument = argument

    func emit(s, level):
        return "throw " + _e.expr(self.argument).emit(s, level) + _semi(s)

class Break extends Stmt:
    func init(label=null):
        self.kind = "break"
        self.label = label

    func emit(s, level):
        return "break" + (" " + self.label if self.label != null else "") + _semi(s)

class Continue extends Stmt:
    func init(label=null):
        self.kind = "continue"
        self.label = label

    func emit(s, level):
        return "continue" + (" " + self.label if self.label != null else "") + _semi(s)

class Block extends Stmt:
    func init(body):
        self.kind = "block"
        self.body = body

    func emit(s, level):
        return _body(self.body, s, level)

# alternate : liste d'instructions, If (else if), ou null.
class If extends Stmt:
    func init(test, consequent, alternate=null):
        self.kind = "if"
        self.test = test
        self.consequent = consequent
        self.alternate = alternate

    func emit(s, level):
        sp := s.sp()
        out := "if" + sp + "(" + _e.expr(self.test).emit(s, level) + ")" + sp + _body(self.consequent, s, level)
        if self.alternate == null:
            return out
        if isinstance(self.alternate, If):
            return out + sp + "else " + self.alternate.emit(s, level)
        return out + sp + "else" + sp + _body(self.alternate, s, level)

class For extends Stmt:
    func init(init_part, test, update, body):
        self.kind = "for"
        self.init_part = init_part
        self.test = test
        self.update = update
        self.body = body

    func emit(s, level):
        sp := s.sp()
        a := ""
        if self.init_part != null:
            if isinstance(self.init_part, VarDecl):
                a = self.init_part.emit_head(s, level)
            else:
                a = _e.expr(self.init_part).emit(s, level)
        b := _e.expr(self.test).emit(s, level) if self.test != null else ""
        c := _e.expr(self.update).emit(s, level) if self.update != null else ""
        return "for" + sp + "(" + a + ";" + (sp if b != "" else "") + b + ";" + (sp if c != "" else "") + c + ")" + sp + _body(self.body, s, level)

class ForOf extends Stmt:
    func init(kind, target, iterable, body, is_await=false, keyword="of"):
        self.kind = "for-" + keyword
        self.decl_kind = kind
        self.target = target
        self.iterable = iterable
        self.body = body
        self.is_await = is_await
        self.keyword = keyword

    func emit(s, level):
        sp := s.sp()
        t := self.target if type(self.target) == "str" else self.target.emit(s, level)
        head := (self.decl_kind + " " if self.decl_kind != null else "") + t
        return "for" + (" await" if self.is_await else "") + sp + "(" + head + " " + self.keyword + " " + _e.expr(self.iterable).emit(s, level) + ")" + sp + _body(self.body, s, level)

class While extends Stmt:
    func init(test, body):
        self.kind = "while"
        self.test = test
        self.body = body

    func emit(s, level):
        sp := s.sp()
        return "while" + sp + "(" + _e.expr(self.test).emit(s, level) + ")" + sp + _body(self.body, s, level)

class DoWhile extends Stmt:
    func init(body, test):
        self.kind = "do-while"
        self.body = body
        self.test = test

    func emit(s, level):
        sp := s.sp()
        return "do" + sp + _body(self.body, s, level) + sp + "while" + sp + "(" + _e.expr(self.test).emit(s, level) + ")" + _semi(s)

# cases : liste de (test ou null pour default, instructions).
class Switch extends Stmt:
    func init(discriminant, cases):
        self.kind = "switch"
        self.discriminant = discriminant
        self.cases = cases

    func emit(s, level):
        sp := s.sp()
        head := "switch" + sp + "(" + _e.expr(self.discriminant).emit(s, level) + ")" + sp + "{"
        parts := []
        for c in self.cases:
            label := "default:" if c[0] == null else "case " + _e.expr(c[0]).emit(s, level) + ":"
            if s.compact:
                inner := ""
                for st in stmts(c[1]):
                    inner = inner + st.emit(s, level + 2)
                append(parts, label + inner)
            else:
                lines := [s.pad(level + 1) + label]
                for st in stmts(c[1]):
                    append(lines, s.pad(level + 2) + st.emit(s, level + 2))
                append(parts, _s.join("\n", lines))
        if s.compact:
            return head + _s.join("", parts) + "}"
        return head + "\n" + _s.join("\n", parts) + "\n" + s.pad(level) + "}"

class Try extends Stmt:
    func init(block, param=null, handler=null, finalizer=null):
        if handler == null and finalizer == null:
            _err.js_error("js_statement.Try", "catch ou finally requis")
        self.kind = "try"
        self.block = block
        self.param = param
        self.handler = handler
        self.finalizer = finalizer

    func emit(s, level):
        sp := s.sp()
        out := "try" + sp + _body(self.block, s, level)
        if self.handler != null:
            out = out + sp + "catch" + ((sp + "(" + self.param + ")") if self.param != null else "") + sp + _body(self.handler, s, level)
        if self.finalizer != null:
            out = out + sp + "finally" + sp + _body(self.finalizer, s, level)
        return out

class Labeled extends Stmt:
    func init(label, body):
        self.kind = "labeled"
        self.label = label
        self.body = body

    func emit(s, level):
        return self.label + ":" + s.sp() + stmt(self.body).emit(s, level)

# Programme (ou corps de module) : suite d'instructions séparées par des sauts de ligne.
class Program extends Stmt:
    func init(body=null, directives=null):
        self.kind = "program"
        self.body = stmts(body) if body != null else []
        self.directives = directives if directives != null else []

    func add(x):
        append(self.body, stmt(x))
        return self

    func extend(items):
        for x in items:
            self.add(x)
        return self

    func emit(s, level):
        parts := []
        for d in self.directives:
            append(parts, _t.quote(d, s.quote) + _semi(s))
        for x in _guard_asi(self.body, s):
            t := x.emit(s, level)
            if t != "":
                append(parts, t)
        if s.compact:
            return _s.join("" if s.semicolons else "\n", parts)
        return _s.join("\n", parts) + ("\n" if len(parts) > 0 else "")

# ---------------------------------------------------------------- constructeurs

func declare(kind, name, value=null):
    return VarDecl(kind, [(name, value)])

func let_decl(name, value=null):
    return VarDecl("let", [(name, value)])

func const_decl(name, value):
    return VarDecl("const", [(name, value)])

func var_decl(name, value=null):
    return VarDecl("var", [(name, value)])

# const {a, b: c} = source ; names : liste de noms ou de (clé, alias).
func destructure(kind, names, source, array_pattern=false):
    parts := []
    for n in names:
        if type(n) == "tuple" or type(n) == "list":
            append(parts, str(n[0]) + ": " + str(n[1]))
        else:
            append(parts, str(n))
    pattern := ("[" + _s.join(", ", parts) + "]") if array_pattern else ("{" + _s.join(", ", parts) + "}")
    return VarDecl(kind, [(_e.RawExpr(pattern), source)])

func ret(value=null):
    return Return(value)

func throw_error(message, error_class="Error"):
    return Throw(_e.New(_e.path(error_class), [_e.expr(message)]))

func if_stmt(test, then_body, else_body=null):
    return If(test, then_body, else_body)

func for_loop(init_part, test, update, body):
    return For(init_part, test, update, body)

# for (let i = start; i < end; i++)
func for_range(name, start, end, body, step=1):
    upd := _e.Update("++", _e.ident(name)) if step == 1 else _e.Assign("+=", _e.ident(name), _e.expr(step))
    return For(VarDecl("let", [(name, start)]), _e.binary("<", _e.ident(name), end), upd, body)

func for_of(kind, target, iterable, body, is_await=false):
    return ForOf(kind, target, iterable, body, is_await, "of")

func for_in(kind, target, obj, body):
    return ForOf(kind, target, obj, body, false, "in")

func while_loop(test, body):
    return While(test, body)

func try_catch(block, param, handler, finalizer=null):
    return Try(block, param, handler, finalizer)

func comment(text, block=false):
    return Comment(text, block)

func program(body=null, strict=false):
    return Program(body, ["use strict"] if strict else null)

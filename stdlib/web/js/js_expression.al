# ALEX STANDARD LIBRARY — web.js.js_expression
#
# Expressions JavaScript sous forme d'arbre (AST) et leur génération en texte avec les parenthèses EXACTEMENT
# nécessaires (table de priorité ECMAScript, associativité, cas « ?? » mêlé à « || », « -a ** b »).
# Construction concise par méthodes chaînées.
#
#   use web.js.js_expression as je
#   e := je.ident("document").dot("querySelector").call([je.lit("#app")])
#   e.to_js()                                          # document.querySelector("#app")
#   je.binary("*", je.binary("+", je.ident("a"), je.ident("b")), je.lit(2)).to_js()     # (a + b) * 2
#   je.arrow(["x"], je.ident("x").op("*", 2)).to_js()  # (x) => x * 2
#   je.ident("user").dot("name", true).op("??", "anonyme").to_js()   # user?.name ?? "anonyme"
#   je.template(["Bonjour ", "!"], [je.ident("nom")]).to_js()       # `Bonjour ${nom}!`
#   je.new_expr(je.ident("Map"), []).to_js()           # new Map()
#   je.expr({"a": [1, je.ident("b")]}).to_js()          # {a: [1, b]}
#
# Erreurs : JsError (opérateur inconnu, cible d'affectation invalide), JsValueError (valeur non convertible).

from core use len, type
from collections use append, keys
use string as _s
use web.js.js_errors as _err
use web.js.js_types as _t

# Options de génération partagées par les expressions et les instructions.
class Style:
    func init(indent="  ", semicolons=true, quote="\"", compact=false, ascii=false, arrow_parens=true, trailing_commas=false):
        self.indent = indent
        self.semicolons = semicolons
        self.quote = quote
        self.compact = compact
        self.ascii = ascii
        self.arrow_parens = arrow_parens
        self.trailing_commas = trailing_commas

    func sp():
        return "" if self.compact else " "

    func nl():
        return "" if self.compact else "\n"

    func pad(level):
        if self.compact:
            return ""
        return _s.repeat(self.indent, level)

func style_of(s):
    if s == null:
        return Style()
    if type(s) == "str":
        return Style(s)
    return s

func compact_style():
    return Style("", true, "\"", true)

# ---------------------------------------------------------------- priorités

const P_SEQUENCE := 1
const P_ASSIGN := 2
const P_CONDITIONAL := 3
const P_COALESCE := 4
const P_OR := 5
const P_AND := 6
const P_BITOR := 7
const P_BITXOR := 8
const P_BITAND := 9
const P_EQUALITY := 10
const P_RELATIONAL := 11
const P_SHIFT := 12
const P_ADDITIVE := 13
const P_MULTIPLICATIVE := 14
const P_EXPONENT := 15
const P_UNARY := 16
const P_UPDATE := 17
const P_NEW := 18
const P_CALL := 19
const P_PRIMARY := 20

const BINARY_PRECEDENCE := {"??": 4, "||": 5, "&&": 6, "|": 7, "^": 8, "&": 9, "==": 10, "!=": 10, "===": 10, "!==": 10, "<": 11, ">": 11, "<=": 11, ">=": 11, "in": 11, "instanceof": 11, "<<": 12, ">>": 12, ">>>": 12, "+": 13, "-": 13, "*": 14, "/": 14, "%": 14, "**": 15}
const ASSIGN_OPS := ["=", "+=", "-=", "*=", "/=", "%=", "**=", "<<=", ">>=", ">>>=", "&=", "|=", "^=", "&&=", "||=", "??="]
const UNARY_OPS := ["!", "~", "+", "-", "typeof", "void", "delete", "await"]

# ---------------------------------------------------------------- nœuds

class Expr:
    func prec():
        return P_PRIMARY

    func to_js(style=null, level=0):
        return self.emit(style_of(style), level)

    func __str__():
        return self.to_js()

    # Raccourcis chaînés.
    func dot(name, optional=false):
        return Member(self, name, false, optional)

    func index(e, optional=false):
        return Member(self, expr(e), true, optional)

    func call(args=null, optional=false):
        return Call(self, _exprs(args), optional)

    func method(name, args=null):
        return Call(Member(self, name, false, false), _exprs(args), false)

    func op(operator, other):
        return binary(operator, self, expr(other))

    func assign(value, operator="="):
        return Assign(operator, self, expr(value))

    func not_():
        return Unary("!", self)

    func await_():
        return Unary("await", self)

    func spread():
        return Spread(self)

func _exprs(args):
    out := []
    if args == null:
        return out
    for a in args:
        append(out, expr(a))
    return out

func _paren(e, s, level, min_prec):
    t := e.emit(s, level)
    if e.prec() < min_prec:
        return "(" + t + ")"
    return t

class Literal extends Expr:
    func init(value):
        self.kind = "literal"
        self.value = value

    func prec():
        if type(self.value) == "int" or type(self.value) == "float":
            if self.value < 0:
                return P_UNARY
        return P_PRIMARY

    func emit(s, level):
        v := self.value
        if type(v) == "str":
            return _t.quote(v, s.quote, s.ascii)
        if v == null:
            return "null"
        if type(v) == "bool":
            return "true" if v else "false"
        if _t.is_undefined(v):
            return "void 0" if s.compact else "undefined"
        return _t.number(v)

class Identifier extends Expr:
    func init(name):
        self.kind = "identifier"
        if not _t.is_identifier_name(str(name)):
            _err.js_error("js_expression.ident", "identifiant invalide « " + str(name) + " »")
        self.name = str(name)

    func emit(s, level):
        return self.name

# Code brut (non analysé) ; prec : priorité supposée (primaire par défaut ; P_SEQUENCE pour forcer des parenthèses).
class RawExpr extends Expr:
    func init(code, precedence=20):
        self.kind = "raw"
        self.code = str(code)
        self.precedence = precedence

    func prec():
        return self.precedence

    func emit(s, level):
        return self.code

# Expression explicitement parenthésée.
class Paren extends Expr:
    func init(inner):
        self.kind = "paren"
        self.inner = inner

    func emit(s, level):
        return "(" + self.inner.emit(s, level) + ")"

class This extends Expr:
    func init():
        self.kind = "this"

    func emit(s, level):
        return "this"

class Member extends Expr:
    func init(target, prop, computed=false, optional=false):
        self.kind = "member"
        self.target = target
        self.prop = prop
        self.computed = computed
        self.optional = optional

    func prec():
        return P_CALL

    func emit(s, level):
        obj := _paren(self.target, s, level, P_CALL)
        if isinstance(self.target, Literal) and (type(self.target.value) == "int") and not self.computed and not _s.starts_with(obj, "("):
            obj = "(" + obj + ")"
        if self.computed:
            return obj + ("?.[" if self.optional else "[") + self.prop.emit(s, level) + "]"
        name := str(self.prop)
        if not _t.is_identifier_name(name) and not _s.starts_with(name, "#"):
            return obj + ("?.[" if self.optional else "[") + _t.quote(name, s.quote, s.ascii) + "]"
        return obj + ("?." if self.optional else ".") + name

class Call extends Expr:
    func init(callee, args=null, optional=false):
        self.kind = "call"
        self.callee = callee
        self.args = args if args != null else []
        self.optional = optional

    func prec():
        return P_CALL

    func emit(s, level):
        c := _paren(self.callee, s, level, P_CALL)
        if isinstance(self.callee, New):
            c = "(" + self.callee.emit(s, level) + ")"
        return c + ("?.(" if self.optional else "(") + _args(self.args, s, level) + ")"

func _args(args, s, level):
    parts := []
    for a in args:
        append(parts, _paren(a, s, level, P_ASSIGN))
    return _s.join("," + s.sp(), parts)

class New extends Expr:
    func init(callee, args=null):
        self.kind = "new"
        self.callee = callee
        self.args = args if args != null else []

    func prec():
        return P_CALL

    func emit(s, level):
        c := self.callee.emit(s, level)
        if self.callee.prec() < P_CALL or isinstance(self.callee, Call) or _contains_call(self.callee):
            c = "(" + c + ")"
        return "new " + c + "(" + _args(self.args, s, level) + ")"

func _contains_call(e):
    if isinstance(e, Call):
        return true
    if isinstance(e, Member):
        return _contains_call(e.target)
    return false

class Binary extends Expr:
    func init(operator, left, right):
        if not (operator in BINARY_PRECEDENCE):
            _err.js_error("js_expression.binary", "opérateur binaire inconnu « " + str(operator) + " »")
        self.kind = "binary"
        self.operator = operator
        self.left = left
        self.right = right

    func prec():
        return BINARY_PRECEDENCE[self.operator]

    func emit(s, level):
        p := self.prec()
        o := self.operator
        lmin := p
        rmin := p + 1
        if o == "**":
            lmin = p + 1
            rmin = p
        lt := _paren(self.left, s, level, lmin)
        rt := _paren(self.right, s, level, rmin)
        # « ?? » ne se mélange pas sans parenthèses avec « || » / « && »
        if o == "??" or o == "||" or o == "&&":
            if _mixes_coalesce(self.left, o) and not _s.starts_with(lt, "("):
                lt = "(" + lt + ")"
            if _mixes_coalesce(self.right, o) and not _s.starts_with(rt, "("):
                rt = "(" + rt + ")"
        # « -a ** b » est une erreur de syntaxe
        if o == "**" and (isinstance(self.left, Unary) or (isinstance(self.left, Literal) and self.left.prec() == P_UNARY)) and not _s.starts_with(lt, "("):
            lt = "(" + lt + ")"
        sp := s.sp()
        if o == "in" or o == "instanceof":
            sp = " "
        out := lt + sp + o + sp + rt
        if s.compact and (o == "+" or o == "-") and len(rt) > 0 and (rt[0] == o[0]):
            out = lt + o + " " + rt
        return out

func _mixes_coalesce(child, parent_op):
    if not isinstance(child, Binary):
        return false
    c := child.operator
    if parent_op == "??":
        return c == "||" or c == "&&"
    return c == "??"

class Unary extends Expr:
    func init(operator, argument):
        if not (operator in UNARY_OPS):
            _err.js_error("js_expression.unary", "opérateur unaire inconnu « " + str(operator) + " »")
        self.kind = "unary"
        self.operator = operator
        self.argument = argument

    func prec():
        return P_UNARY

    func emit(s, level):
        a := _paren(self.argument, s, level, P_UNARY)
        o := self.operator
        if _t.is_identifier_name(o):
            return o + " " + a
        if (o == "-" or o == "+") and len(a) > 0 and a[0] == o[0]:
            return o + " " + a
        return o + a

class Update extends Expr:
    func init(operator, argument, prefix=false):
        if operator != "++" and operator != "--":
            _err.js_error("js_expression.update", "opérateur « ++ » ou « -- » attendu")
        _check_target(argument)
        self.kind = "update"
        self.operator = operator
        self.argument = argument
        self.prefix = prefix

    func prec():
        return P_UPDATE

    func emit(s, level):
        a := _paren(self.argument, s, level, P_CALL)
        return self.operator + a if self.prefix else a + self.operator

func _check_target(t):
    if not (isinstance(t, Identifier) or isinstance(t, Member) or isinstance(t, ArrayExpr) or isinstance(t, ObjectExpr) or isinstance(t, RawExpr)):
        _err.js_error("js_expression", "cible d'affectation invalide")

class Assign extends Expr:
    func init(operator, target, value):
        if not (operator in ASSIGN_OPS):
            _err.js_error("js_expression.assign", "opérateur d'affectation inconnu « " + str(operator) + " »")
        _check_target(target)
        self.kind = "assign"
        self.operator = operator
        self.target = target
        self.value = value

    func prec():
        return P_ASSIGN

    func emit(s, level):
        lt := self.target.emit(s, level)
        if isinstance(self.target, ObjectExpr):
            lt = "(" + lt
            return lt + s.sp() + self.operator + s.sp() + _paren(self.value, s, level, P_ASSIGN) + ")"
        return lt + s.sp() + self.operator + s.sp() + _paren(self.value, s, level, P_ASSIGN)

class Conditional extends Expr:
    func init(test, consequent, alternate):
        self.kind = "conditional"
        self.test = test
        self.consequent = consequent
        self.alternate = alternate

    func prec():
        return P_CONDITIONAL

    func emit(s, level):
        sp := s.sp()
        return _paren(self.test, s, level, P_COALESCE) + sp + "?" + sp + _paren(self.consequent, s, level, P_ASSIGN) + sp + ":" + sp + _paren(self.alternate, s, level, P_ASSIGN)

class Sequence extends Expr:
    func init(items):
        self.kind = "sequence"
        self.items = items

    func prec():
        return P_SEQUENCE

    func emit(s, level):
        parts := []
        for e in self.items:
            append(parts, _paren(e, s, level, P_ASSIGN))
        return _s.join("," + s.sp(), parts)

class Spread extends Expr:
    func init(argument):
        self.kind = "spread"
        self.argument = argument

    func prec():
        return P_ASSIGN

    func emit(s, level):
        return "..." + _paren(self.argument, s, level, P_ASSIGN)

class ArrayExpr extends Expr:
    func init(items=null):
        self.kind = "array"
        self.items = items if items != null else []

    func push(e):
        append(self.items, expr(e))
        return self

    func emit(s, level):
        if len(self.items) == 0:
            return "[]"
        parts := []
        for e in self.items:
            if e == null:
                append(parts, "")
            else:
                append(parts, _paren(e, s, level + 1, P_ASSIGN))
        return "[" + _s.join("," + s.sp(), parts) + "]"

# Propriété d'objet : clé (texte, ou Expr si calculée), valeur ; kind : "init", "get", "set", "method",
# "spread", "shorthand".
class Property:
    func init(key, value, kind="init", computed=false):
        self.key = key
        self.value = value
        self.kind = kind
        self.computed = computed

    func key_text(s, level):
        if self.computed:
            return "[" + self.key.emit(s, level) + "]"
        if type(self.key) == "int":
            return str(self.key)
        k := str(self.key)
        if _t.is_identifier_name(k) or _t.is_canonical_index(k):
            return k
        return _t.quote(k, s.quote, s.ascii)

    func emit(s, level):
        if self.kind == "spread":
            return "..." + _paren(self.value, s, level, P_ASSIGN)
        if self.kind == "shorthand":
            return str(self.key)
        if self.kind == "get" or self.kind == "set" or self.kind == "method":
            # self.value : Function (web.js.js_function) dont on émet la forme méthode
            prefix := "" if self.kind == "method" else self.kind + " "
            return prefix + self.value.emit_method(self.key_text(s, level), s, level)
        return self.key_text(s, level) + ":" + s.sp() + _paren(self.value, s, level, P_ASSIGN)

class ObjectExpr extends Expr:
    func init(props=null):
        self.kind = "object"
        self.props = props if props != null else []

    func set(key, value):
        append(self.props, Property(key, expr(value)))
        return self

    func computed(key_expr, value):
        append(self.props, Property(key_expr, expr(value), "init", true))
        return self

    func shorthand(name):
        append(self.props, Property(name, null, "shorthand"))
        return self

    func spread(e):
        append(self.props, Property(null, expr(e), "spread"))
        return self

    func method(name, fn):
        append(self.props, Property(name, fn, "method"))
        return self

    func getter(name, fn):
        append(self.props, Property(name, fn, "get"))
        return self

    func setter(name, fn):
        append(self.props, Property(name, fn, "set"))
        return self

    func emit(s, level):
        if len(self.props) == 0:
            return "{}"
        parts := []
        multiline := not s.compact and _needs_lines(self.props)
        for p in self.props:
            append(parts, p.emit(s, level + 1 if multiline else level))
        if multiline:
            pad := s.pad(level + 1)
            tail := "," if s.trailing_commas else ""
            return "{\n" + pad + _s.join(",\n" + pad, parts) + tail + "\n" + s.pad(level) + "}"
        if s.compact:
            return "{" + _s.join(",", parts) + "}"
        return "{" + _s.join(", ", parts) + "}"

func _needs_lines(props):
    if len(props) > 4:
        return true
    for p in props:
        if p.kind == "get" or p.kind == "set" or p.kind == "method":
            return true
    return false

# Gabarit `a${x}b` ; quasis : textes (un de plus que les expressions) ; tag : expression d'étiquette.
class Template extends Expr:
    func init(quasis, exprs, tag=null):
        if len(quasis) != len(exprs) + 1:
            _err.js_error("js_expression.template", "il faut un texte de plus que d'expressions")
        self.kind = "template"
        self.quasis = quasis
        self.exprs = exprs
        self.tag = tag

    func prec():
        return P_CALL if self.tag != null else P_PRIMARY

    func emit(s, level):
        out := []
        if self.tag != null:
            append(out, _paren(self.tag, s, level, P_CALL))
        append(out, "`")
        i := 0
        while i < len(self.quasis):
            q := _t.quote(self.quasis[i], "`")
            append(out, q[1:len(q) - 1])
            if i < len(self.exprs):
                append(out, "${" + self.exprs[i].emit(s, level) + "}")
            i += 1
        append(out, "`")
        return _s.join("", out)

# Fonction fléchée ; params : noms (texte) ou Param (web.js.js_function) ; body : Expr ou liste d'instructions.
class Arrow extends Expr:
    func init(params, body, is_async=false):
        self.kind = "arrow"
        self.params = params
        self.body = body
        self.is_async = is_async

    func prec():
        return P_ASSIGN

    func emit(s, level):
        ps := []
        for p in self.params:
            append(ps, p if type(p) == "str" else p.emit(s, level))
        head := ""
        if self.is_async:
            head = "async "
        if len(ps) == 1 and not s.arrow_parens and type(self.params[0]) == "str":
            head = head + ps[0]
        else:
            head = head + "(" + _s.join("," + s.sp(), ps) + ")"
        sp := s.sp()
        if type(self.body) == "list":
            return head + sp + "=>" + sp + emit_block(self.body, s, level)
        b := self.body.emit(s, level)
        if isinstance(self.body, ObjectExpr) or (self.body.prec() < P_ASSIGN):
            b = "(" + b + ")"
        return head + sp + "=>" + sp + b

# Bloc d'instructions « { … } » (instructions dotées de emit(style, niveau)).
func emit_block(stmts, s, level):
    if len(stmts) == 0:
        return "{}"
    if s.compact:
        parts := []
        for st in stmts:
            append(parts, st.emit(s, level + 1))
        return "{" + _s.join("", parts) + "}"
    lines := []
    for st in stmts:
        append(lines, s.pad(level + 1) + st.emit(s, level + 1))
    return "{\n" + _s.join("\n", lines) + "\n" + s.pad(level) + "}"

# ---------------------------------------------------------------- constructeurs

# Expression depuis une valeur ALEX : Expr inchangée, dict -> objet, list -> tableau, sinon littéral.
func expr(v):
    if isinstance(v, Expr):
        return v
    t := type(v)
    if t == "list" or t == "tuple":
        items := []
        for x in v:
            append(items, expr(x))
        return ArrayExpr(items)
    if t == "dict":
        o := ObjectExpr()
        for k in keys(v):
            o.set(k, v[k])
        return o
    if v == null or t == "bool" or t == "int" or t == "float" or t == "str" or _t.is_undefined(v):
        return Literal(v)
    try:
        return RawExpr(v.to_js())
    catch e:
        _err.value_error("js_expression.expr", "valeur non convertible de type " + t)

func lit(v):
    return Literal(v)

func ident(name):
    return Identifier(name)

func raw(code, precedence=20):
    return RawExpr(code, precedence)

func this():
    return This()

# Chemin pointé : path("window.location.href").
func path(dotted):
    parts := _s.split(str(dotted), ".")
    e := Identifier(parts[0]) if parts[0] != "this" else This()
    i := 1
    while i < len(parts):
        e = Member(e, parts[i])
        i += 1
    return e

func member(target, prop, computed=false, optional=false):
    return Member(expr(target) if not (type(target) == "str") else Identifier(target), expr(prop) if computed else prop, computed, optional)

func call(callee, args=null):
    c := path(callee) if type(callee) == "str" else callee
    return Call(c, _exprs(args))

func new_expr(callee, args=null):
    c := path(callee) if type(callee) == "str" else callee
    return New(c, _exprs(args))

func binary(operator, left, right):
    return Binary(operator, expr(left), expr(right))

func unary(operator, argument):
    return Unary(operator, expr(argument))

func assign(target, value, operator="="):
    t := path(target) if type(target) == "str" else target
    return Assign(operator, t, expr(value))

func conditional(test, consequent, alternate):
    return Conditional(expr(test), expr(consequent), expr(alternate))

func sequence(items):
    return Sequence(_exprs(items))

func array(items=null):
    return ArrayExpr(_exprs(items))

func object(props=null):
    o := ObjectExpr()
    if props != null:
        for k in keys(props):
            o.set(k, props[k])
    return o

func template(quasis, exprs, tag=null):
    return Template(quasis, _exprs(exprs), tag)

func arrow(params, body, is_async=false):
    b := body if type(body) == "list" else expr(body)
    return Arrow(params, b, is_async)

func spread(e):
    return Spread(expr(e))

func await_expr(e):
    return Unary("await", expr(e))

func typeof_expr(e):
    return Unary("typeof", expr(e))

# Chaîne d'opérateurs logiques : all_of([a, b]) -> a && b ; any_of -> a || b.
func all_of(items):
    e := expr(items[0])
    i := 1
    while i < len(items):
        e = Binary("&&", e, expr(items[i]))
        i += 1
    return e

func any_of(items):
    e := expr(items[0])
    i := 1
    while i < len(items):
        e = Binary("||", e, expr(items[i]))
        i += 1
    return e

# console.log(...)
func log(args):
    return Call(path("console.log"), _exprs(args))

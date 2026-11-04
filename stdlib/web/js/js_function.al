# ALEX STANDARD LIBRARY — web.js.js_function
#
# Fonctions et classes JavaScript (AST) : paramètres (valeur par défaut, reste, motifs), fonctions nommées ou
# anonymes, async, générateurs, méthodes, accesseurs, classes (héritage, constructeur, champs publics et
# privés « # », membres statiques, blocs static). Une fonction ou une classe NOMMÉE est une déclaration quand
# elle est placée dans un programme ; ailleurs, c'est une expression.
#
#   use web.js.js_function as jf
#   use web.js.js_statement as js
#   use web.js.js_expression as je
#   f := jf.function("somme", [jf.param("a"), jf.param("b", 0)], [js.ret(je.ident("a").op("+", je.ident("b")))])
#   f.to_js()                # function somme(a, b = 0) {\n  return a + b;\n}
#   jf.function(null, [jf.rest("args")], [], true).to_js()   # async function(...args) {}
#   c := jf.class_decl("Chien", "Animal")
#   c.constructor([jf.param("nom")], [je.raw("super(nom)")])
#   c.method("aboyer", [], [js.ret(je.lit("Wouf"))])
#   c.field("#puces", 0)
#   c.to_js()
#
# Erreurs : JsError (paramètre de reste qui n'est pas le dernier, nom invalide, membre en double).

from core use len, type
from collections use append
use string as _s
use web.js.js_errors as _err
use web.js.js_types as _t
use web.js.js_expression as _e
use web.js.js_statement as _st
from web.js.js_expression use Expr

class Param:
    # name : nom (texte) ou motif (texte brut « {a, b} ») ; default : valeur ALEX ou Expr ; rest : « ...name ».
    func init(name, default=null, is_rest=false, has_default=false):
        self.name = str(name)
        self.default = default
        self.is_rest = is_rest
        self.has_default = has_default or default != null

    func emit(s, level):
        out := ("..." if self.is_rest else "") + self.name
        if self.has_default:
            out = out + s.sp() + "=" + s.sp() + _e._paren(_e.expr(self.default), s, level, _e.P_ASSIGN)
        return out

func param(name, default=null):
    return Param(name, default)

func rest(name):
    return Param(name, null, true)

# Paramètre avec valeur par défaut null explicite (default=null signifie « sans défaut » ailleurs).
func param_null_default(name):
    return Param(name, null, false, true)

func _params(ps):
    out := []
    i := 0
    for p in ps:
        q := p if isinstance(p, Param) else Param(p)
        if q.is_rest and i != len(ps) - 1:
            _err.js_error("js_function", "le paramètre de reste « ..." + q.name + " » doit être le dernier")
        append(out, q)
        i += 1
    return out

func _emit_params(ps, s, level):
    parts := []
    for p in ps:
        append(parts, p.emit(s, level))
    return "(" + _s.join("," + s.sp(), parts) + ")"

class Function extends Expr:
    func init(name=null, params=null, body=null, is_async=false, is_generator=false):
        if name != null and not _t.is_identifier(str(name)):
            _err.js_error("js_function.Function", "nom de fonction invalide « " + str(name) + " »")
        self.kind = "function"
        self.name = name
        self.params = _params(params if params != null else [])
        self.body = _st.stmts(body)
        self.is_async = is_async
        self.is_generator = is_generator
        self.is_declaration = name != null

    func prec():
        return _e.P_PRIMARY

    func add(x):
        append(self.body, _st.stmt(x))
        return self

    func emit(s, level):
        head := ("async " if self.is_async else "") + "function" + ("*" if self.is_generator else "")
        if self.name != null:
            head = head + " " + self.name
        return head + (s.sp() if self.name == null and not s.compact else "") + _emit_params(self.params, s, level) + s.sp() + _st._body(self.body, s, level)

    # Forme méthode : « [async] [*]clé(params) { … } ».
    func emit_method(key, s, level):
        head := ("async " if self.is_async else "") + ("*" if self.is_generator else "") + key
        return head + _emit_params(self.params, s, level) + s.sp() + _st._body(self.body, s, level)

    # Version fléchée (sans this ni arguments propres) ; corps simple « return x » raccourci.
    func to_arrow():
        names := []
        for p in self.params:
            append(names, p)
        if len(self.body) == 1 and isinstance(self.body[0], _st.Return) and self.body[0].argument != null:
            return _e.Arrow(names, _e.expr(self.body[0].argument), self.is_async)
        return _e.Arrow(names, self.body, self.is_async)

func function(name=null, params=null, body=null, is_async=false, is_generator=false):
    return Function(name, params, body, is_async, is_generator)

func async_function(name, params=null, body=null):
    return Function(name, params, body, true)

func generator(name, params=null, body=null):
    return Function(name, params, body, false, true)

# Fonction fléchée avec Param (défauts, reste).
func arrow(params, body, is_async=false):
    ps := _params(params)
    b := _st.stmts(body) if type(body) == "list" else _e.expr(body)
    return _e.Arrow(ps, b, is_async)

# Fonction immédiatement invoquée : (() => { … })() ou (async () => { … })().
func iife(body, is_async=false):
    a := _e.Arrow([], _st.stmts(body), is_async)
    return _e.Call(_e.Paren(a), [])

# ---------------------------------------------------------------- classes

class Member:
    # kind : "method", "get", "set", "constructor", "field", "static-block"
    func init(kind, name, value=null, is_static=false):
        self.kind = kind
        self.name = name
        self.value = value
        self.is_static = is_static

    func emit(s, level):
        pre := "static " if self.is_static else ""
        if self.kind == "field":
            if self.value == null:
                return pre + self.name + (";" if s.semicolons or s.compact else "")
            return pre + self.name + s.sp() + "=" + s.sp() + _e.expr(self.value).emit(s, level) + (";" if s.semicolons or s.compact else "")
        if self.kind == "static-block":
            return "static" + s.sp() + _st._body(self.value, s, level)
        key := self.name
        if not _t.is_identifier_name(key) and not _s.starts_with(key, "#") and not _s.starts_with(key, "["):
            key = _t.quote(key, s.quote)
        if self.kind == "get" or self.kind == "set":
            return pre + self.kind + " " + self.value.emit_method(key, s, level)
        return pre + self.value.emit_method(key, s, level)

class Class extends Expr:
    func init(name=null, superclass=null):
        if name != null and not _t.is_identifier(str(name)):
            _err.js_error("js_function.Class", "nom de classe invalide « " + str(name) + " »")
        self.kind = "class"
        self.name = name
        self.superclass = superclass
        self.members = []
        self.is_declaration = name != null

    func prec():
        return _e.P_PRIMARY

    func _check(name, kind, is_static):
        for m in self.members:
            if m.name == name and m.is_static == is_static and m.kind == kind and kind != "get" and kind != "set":
                _err.js_error("js_function.Class", "membre « " + name + " » déjà défini")

    func constructor(params, body):
        for m in self.members:
            if m.kind == "constructor":
                _err.js_error("js_function.Class", "constructeur déjà défini")
        append(self.members, Member("constructor", "constructor", Function(null, params, body)))
        return self

    func method(name, params=null, body=null, is_static=false, is_async=false, is_generator=false):
        self._check(name, "method", is_static)
        append(self.members, Member("method", name, Function(null, params, body, is_async, is_generator), is_static))
        return self

    func getter(name, body, is_static=false):
        append(self.members, Member("get", name, Function(null, [], body), is_static))
        return self

    func setter(name, param_name, body, is_static=false):
        append(self.members, Member("set", name, Function(null, [param_name], body), is_static))
        return self

    func field(name, value=null, is_static=false):
        self._check(name, "field", is_static)
        append(self.members, Member("field", name, value, is_static))
        return self

    func static_block(body):
        append(self.members, Member("static-block", "static", _st.stmts(body), true))
        return self

    func emit(s, level):
        head := "class"
        if self.name != null:
            head = head + " " + self.name
        if self.superclass != null:
            sup := self.superclass if type(self.superclass) == "str" else self.superclass.emit(s, level)
            head = head + " extends " + sup
        if len(self.members) == 0:
            return head + s.sp() + "{}"
        if s.compact:
            parts := []
            for m in self.members:
                append(parts, m.emit(s, level + 1))
            return head + "{" + _s.join("", parts) + "}"
        lines := []
        for m in self.members:
            append(lines, s.pad(level + 1) + m.emit(s, level + 1))
        return head + " {\n" + _s.join("\n\n", lines) + "\n" + s.pad(level) + "}"

func class_decl(name, superclass=null):
    return Class(name, superclass)

func class_expr(superclass=null):
    return Class(null, superclass)

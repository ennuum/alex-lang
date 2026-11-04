# ALEX STANDARD LIBRARY — compiler.ast
#
# Arbre syntaxique abstrait d'ALEX. Chaque nœud est un Node : un genre (kind), une position (line, column) et des
# champs nommés accessibles directement (n.left, n.body...). L'arbre est FIDÈLE au texte : with, assert, del,
# pass, décorateurs, déstructuration, tranches et ensembles gardent leur propre nœud (le compilateur natif, lui,
# les désucre) — idéal pour les outils (formatage, analyse, réécriture).
#
#   use compiler.ast as ast
#   n := ast.binary("+", ast.literal(1), ast.name("x"))
#   print(n.kind, n.op, n.left.value)              # Binary + 1
#   print(ast.dump(n))                             # (Binary + (Literal 1) (Name x))
#   ast.walk(arbre, (nd) => print(nd.kind))        # parcours préfixe de tous les nœuds
#   noms := ast.find_all(arbre, "Name")
#   arbre2 := ast.transform(arbre, (nd) => remplacer(nd))   # réécriture ascendante (rendre nd ou un autre nœud)
#   class Compteur extends ast.Visitor: ...        # (via from compiler.ast use Visitor) visit_Call(n), etc.
#
# Genres (champs) — expressions : Literal(value, lit), FString(parts), Name(name), Unary(op, operand),
# Binary(op, left, right), Ternary(cond, then_expr, else_expr), Range(start, end), Call(callee, args),
# Arg(name, value), Member(object, member), Index(object, index), Slice(object, start, stop, step),
# Propagate(operand), Lambda(params, body), ListLit(elements), TupleLit(elements), SetLit(elements),
# DictLit(entries), DictEntry(key, value), DictSpread(value), Comprehension(comp, element, key, value, clauses),
# CompFor(var, iter), CompIf(cond), Spread(value).
# Instructions : Program(body), Use(path, alias), FromUse(path, names), Func(name, params, ret_type, body,
# is_async, decorators, short, extends_type), Param(name, type, default, rest), TypeRef(name, args, nullable),
# Class(name, base, interfaces, body), Struct(name, body), Interface(name, body), Enum(name, members),
# EnumMember(name, fields), Const(name, type, value), VarDecl(name, type, value, declared_only),
# Assign(target, value), CompoundAssign(op, target, value), Destructure(targets, value, declare),
# Target(expr, star), ExprStmt(expr), If(cond, then_body, elifs, else_body), Elif(cond, body),
# While(cond, body, else_body), For(vars, iter, body, else_body), Try(body, catches, finally_body),
# Catch(types, name, body), Match(subject, cases), Case(pattern, guard, body), Pattern(pk, name, value, low,
# high, items, enum_name, variant), Break, Continue, Return(value), With(resource, name, body), Pass,
# Assert(cond, message), Del(targets), Extend(type_name, methods).
#
# Erreurs : AttributeError (champ inconnu), TypeError.

from core use len, type
from collections use append
use string as _s
use _native_reflect as _r

class Node:
    func init(kind, line=0, column=0, fields=null):
        self.kind = kind
        self.line = line
        self.column = column
        self._fields = []
        if fields != null:
            for k in fields:
                append(self._fields, k)
                _r.set_field(self, k, fields[k])

    func get(name, default=null):
        if _r.has_field(self, name):
            return _r.get_field(self, name)
        return default

    func set(name, value):
        if not (name in self._fields):
            append(self._fields, name)
        _r.set_field(self, name, value)
        return self

    func field_names():
        return self._fields[:]

    func has(name):
        return name in self._fields

    func is_a(kind):
        return self.kind == kind

    # Nœuds enfants directs (dans l'ordre des champs).
    func children():
        out := []
        for f in self._fields:
            v := _r.get_field(self, f)
            if is_node(v):
                append(out, v)
            elif type(v) == "list":
                for x in v:
                    if is_node(x):
                        append(out, x)
        return out

    func copy():
        d := {}
        for f in self._fields:
            d[f] = _copy_value(_r.get_field(self, f))
        return Node(self.kind, self.line, self.column, d)

    func __str__():
        return dump(self)

func _copy_value(v):
    if is_node(v):
        return v.copy()
    if type(v) == "list":
        return [_copy_value(x) for x in v]
    return v

func is_node(v):
    return _r.is_instance(v) and _r.type_name(v) == _r.type_name(_PROBE)

_PROBE := Node("Pass")

func node(kind, line=0, column=0, fields=null):
    return Node(kind, line, column, fields)

# ---- fabriques ----
func literal(value, line=0, column=0):
    t := type(value)
    lit := t
    if t == "null":
        lit = "null"
    return Node("Literal", line, column, {"value": value, "lit": lit})

func name(n, line=0, column=0):
    return Node("Name", line, column, {"name": n})

func binary(op, left, right, line=0, column=0):
    return Node("Binary", line, column, {"op": op, "left": left, "right": right})

func unary(op, operand, line=0, column=0):
    return Node("Unary", line, column, {"op": op, "operand": operand})

func call(callee, args, line=0, column=0):
    out := []
    for a in args:
        if is_node(a) and a.kind == "Arg":
            append(out, a)
        else:
            append(out, Node("Arg", line, column, {"name": null, "value": a}))
    return Node("Call", line, column, {"callee": callee, "args": out})

func member(obj, m, line=0, column=0):
    return Node("Member", line, column, {"object": obj, "member": m})

func expr_stmt(e):
    return Node("ExprStmt", e.line, e.column, {"expr": e})

func ret(value, line=0, column=0):
    return Node("Return", line, column, {"value": value})

func program(body):
    return Node("Program", 1, 1, {"body": body})

# ---- parcours ----
func walk(n, fn):
    if not is_node(n):
        return
    fn(n)
    for c in n.children():
        walk(c, fn)

func find_all(n, kind):
    out := []
    walk(n, (x) => append(out, x) if x.kind == kind else null)
    return out

func count(n, kind=null):
    k := [0]
    walk(n, (x) => _incr(k) if kind == null or x.kind == kind else null)
    return k[0]

func _incr(k):
    k[0] += 1

# Réécriture ascendante : fn(nœud) renvoie le nœud (éventuellement nouveau) ; une valeur null dans une liste
# d'instructions supprime l'instruction, une liste la remplace par plusieurs.
func transform(n, fn):
    if not is_node(n):
        return n
    for f in n._fields:
        v := _r.get_field(n, f)
        if is_node(v):
            _r.set_field(n, f, transform(v, fn))
        elif type(v) == "list":
            out := []
            for x in v:
                if is_node(x):
                    r := transform(x, fn)
                    if r == null:
                        continue
                    if type(r) == "list":
                        for y in r:
                            append(out, y)
                    else:
                        append(out, r)
                else:
                    append(out, x)
            _r.set_field(n, f, out)
    return fn(n)

# Égalité structurelle (positions ignorées).
func equals(a, b):
    if is_node(a) != is_node(b):
        return false
    if not is_node(a):
        if type(a) == "list" and type(b) == "list":
            if len(a) != len(b):
                return false
            i := 0
            while i < len(a):
                if not equals(a[i], b[i]):
                    return false
                i += 1
            return true
        if type(a) != type(b):
            return false
        return a == b
    if a.kind != b.kind or len(a._fields) != len(b._fields):
        return false
    for f in a._fields:
        if not b.has(f):
            return false
        if not equals(_r.get_field(a, f), _r.get_field(b, f)):
            return false
    return true

func _atom(v):
    if v == null:
        return "null"
    t := type(v)
    if t == "str":
        return "\"" + _s.replace(_s.replace(v, "\\", "\\\\"), "\"", "\\\"") + "\""
    if t == "char":
        return "'" + str(v) + "'"
    if t == "bool":
        if v:
            return "true"
        return "false"
    return str(v)

# Forme S-expression compacte (champs scalaires puis enfants).
func dump(n):
    if not is_node(n):
        if type(n) == "list":
            return "[" + _s.join(" ", [dump(x) for x in n]) + "]"
        return _atom(n)
    if n.kind == "Literal":
        return "(Literal " + _atom(n.value) + ")"
    if n.kind == "Name":
        return "(Name " + n.name + ")"
    parts := [n.kind]
    for f in n._fields:
        v := _r.get_field(n, f)
        if v == null or (type(v) == "bool" and not v) or (type(v) == "list" and len(v) == 0):
            continue
        if is_node(v) or type(v) == "list":
            append(parts, dump(v))
        elif type(v) == "bool":
            append(parts, ":" + f)
        elif type(v) == "str" and (f == "op" or f == "name" or f == "member" or f == "comp" or f == "pk"):
            append(parts, v)
        else:
            append(parts, ":" + f + " " + _atom(v))
    return "(" + _s.join(" ", parts) + ")"

# Dictionnaire (JSON-compatible) de l'arbre.
func to_dict(n):
    if is_node(n):
        d := {"kind": n.kind, "line": n.line, "column": n.column}
        for f in n._fields:
            d[f] = to_dict(_r.get_field(n, f))
        return d
    if type(n) == "list":
        return [to_dict(x) for x in n]
    if type(n) == "char":
        return str(n)
    return n

func from_dict(d):
    if type(d) == "list":
        return [from_dict(x) for x in d]
    if type(d) != "dict" or not ("kind" in d):
        return d
    fields := {}
    for k in d:
        if k != "kind" and k != "line" and k != "column":
            fields[k] = from_dict(d[k])
    return Node(d["kind"], d["line"], d["column"], fields)

# Visiteur : visit(n) appelle self.visit_<Genre>(n) s'il existe, sinon generic_visit (visite les enfants).
class Visitor:
    func visit(n):
        if not is_node(n):
            return null
        m := _r.method(self, "visit_" + n.kind)
        if m != null:
            return m(n)
        return self.generic_visit(n)

    func generic_visit(n):
        for c in n.children():
            self.visit(c)
        return null

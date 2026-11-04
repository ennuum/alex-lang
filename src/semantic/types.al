# ALEX — semantic.types
#
# Vérification statique graduelle des annotations de type, écrite en ALEX : portage fidèle de
# src/TypeChecker.cpp (docs/TYPES.md). Ce qui n'est pas annoté est `any`, compatible avec tout. Le
# vérificateur parcourt l'arbre de parser, signale les incompatibilités (arguments, retours,
# affectations, opérations, types inconnus, raffinement `T?` -> `T` après `x != null`...) et relève les
# expressions dont le résultat est un entier dimensionné (i8..u64), que le compilateur borne à l'exécution.
#
#   use semantic.types as bt
#   tc := bt.TypeChecker("prog.al", options)      # options : bytecode.compiler.CompileOptions, ou null
#   diags := tc.check(program)                    # [[ligne, colonne, message], ...]
#   tc.check_or_throw(program)                    # lève TypeCheckError s'il y a des diagnostics
#   options.sized_results = tc.sized_results      # uid de nœud -> "u8", "i32"...
#
# Erreurs : TypeCheckError (premier diagnostic, suivis des autres « fichier:ligne:colonne: message »).

from core use len, type
from collections use append
from builtins use ord
use string as _s

const BUILTIN_TYPES := {"any": true, "int": true, "float": true, "bool": true, "str": true, "char": true,
    "byte": true, "null": true, "list": true, "dict": true, "tuple": true, "func": true, "future": true, "i8": true,
    "i16": true, "i32": true, "u8": true, "u16": true, "u32": true, "u64": true, "f32": true}

const INT64_MAX := 9223372036854775807

# ---------------------------------------------------------------------------------------------- types
class TType:
    func init(name="any", args=null, nullable=false):
        self.name = name
        self.args = args if args != null else []
        self.nullable = nullable

    func is_any():
        return self.name == "any"

    func copy():
        return TType(self.name, [a for a in self.args], self.nullable)

    func str():
        s := ""
        n := len(self.args)
        if self.name == "func":
            s = "func("
            i := 0
            while i + 1 < n:
                s += (", " if i > 0 else "") + self.args[i].str()
                i += 1
            s += ")"
            if n > 0 and not self.args[n - 1].is_any():
                s += " -> " + self.args[n - 1].str()
        else:
            s = self.name
            if n > 0:
                s += "[" + _s.join(", ", [a.str() for a in self.args]) + "]"
        return s + "?" if self.nullable else s

func of(name):
    return TType(name)

func normalize(n):
    if n == "i64":
        return "int"
    if n == "f64":
        return "float"
    return n

func is_sized_int(n):
    return n == "i8" or n == "i16" or n == "i32" or n == "u8" or n == "u16" or n == "u32" or n == "u64"

func is_numeric(n):
    return n == "int" or n == "float" or n == "f32" or is_sized_int(n)

func is_float(n):
    return n == "float" or n == "f32"

func is_integral(n):
    return n == "int" or is_sized_int(n)

# [min, max]
func sized_int_range(n):
    if n == "i8":
        return [-128, 127]
    if n == "i16":
        return [-32768, 32767]
    if n == "i32":
        return [-2147483648, 2147483647]
    if n == "u8":
        return [0, 255]
    if n == "u16":
        return [0, 65535]
    if n == "u32":
        return [0, 4294967295]
    if n == "u64":
        return [0, INT64_MAX]
    return [-INT64_MAX - 1, INT64_MAX]

# Valeur d'un littéral entier éventuellement précédé de '-', ou null.
func int_literal(e):
    if e == null:
        return null
    neg := false
    if e.kind == "UnaryExpr":
        if e.op != "Minus":
            return null
        neg = true
        e = e.operand
    if e.kind != "Literal" or e.literal_kind != "Integer":
        return null
    return -e.value if neg else e.value

func list_of(elem):
    return TType("list", [elem])

func unify(ts):
    if len(ts) == 0:
        return TType()
    first := ts[0].str()
    for t in ts:
        if t.str() != first:
            return TType()
    return ts[0]

func type_from_ref(ref):
    return TType(normalize(ref.name), [type_from_ref(a) for a in ref.args], ref.nullable)

# Texte d'une annotation (ast::typeRefToString) : forme des signatures de module.
func type_ref_string(t):
    s := ""
    n := len(t.args)
    if t.name == "func":
        s = "func("
        i := 0
        while i + 1 < n:
            s += (", " if i > 0 else "") + type_ref_string(t.args[i])
            i += 1
        s += ")"
        if n > 0 and t.args[n - 1].name != "any":
            s += " -> " + type_ref_string(t.args[n - 1])
    else:
        s = t.name
        if n > 0:
            s += "[" + _s.join(", ", [type_ref_string(a) for a in t.args]) + "]"
    return s + "?" if t.nullable else s

# ---------------------------------------------------------------------------------------------- texte -> type
func _ident_char(c):
    o := ord(c)
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '$' or c == ':' or o >= 0x80

class _TextParser:
    func init(s):
        self.s = s
        self.i = 0
        self.n = len(s)

    func ws():
        while self.i < self.n and self.s[self.i] == ' ':
            self.i += 1

    func ident():
        self.ws()
        st := self.i
        while self.i < self.n and _ident_char(self.s[self.i]):
            self.i += 1
        return _s.substring(self.s, st, self.i)

    func eat(c):
        self.ws()
        if self.i < self.n and self.s[self.i] == c:
            self.i += 1
            return true
        return false

    func parse():
        t := TType(normalize(self.ident()))
        if t.name == "":
            t.name = "any"
        if t.name == "func":
            ret := TType()
            if self.eat('(') and not self.eat(')'):
                append(t.args, self.parse())
                while self.eat(','):
                    append(t.args, self.parse())
                self.eat(')')
            self.ws()
            if self.i + 1 < self.n and self.s[self.i] == '-' and self.s[self.i + 1] == '>':
                self.i += 2
                ret = self.parse()
            append(t.args, ret)
        elif self.eat('['):
            append(t.args, self.parse())
            while self.eat(','):
                append(t.args, self.parse())
            self.eat(']')
        if self.eat('?'):
            t.nullable = true
        return t

func parse_type_string(text):
    return _TextParser(text).parse()

# ---------------------------------------------------------------------------------------------- vérificateur
class FuncSig:
    func init():
        self.names = []
        self.params = []
        self.has_default = []
        self.ret = TType()
        self.known = false

class ClassInfo:
    func init():
        self.base = ""
        self.interfaces = []
        self.fields = {}
        self.methods = {}
        self.is_enum = false

func _sig_from_module(fs):
    sig := FuncSig()
    sig.known = true
    for p in fs.params:
        append(sig.names, p.name)
        append(sig.params, TType() if p.type == "" else parse_type_string(p.type))
        append(sig.has_default, p.has_default)
    if fs.ret != "":
        sig.ret = parse_type_string(fs.ret)
    return sig

func _func_type(params, ret):
    return TType("func", [p for p in params] + [ret])

const OP_TEXT := {"Add": "+", "Sub": "-", "Mul": "*", "Div": "/", "FloorDiv": "//", "Mod": "%", "Pow": "**",
    "Eq": "==", "Ne": "!=", "Lt": "<", "Le": "<=", "Gt": ">", "Ge": ">=", "And": "and", "Or": "or", "BitAnd": "&",
    "BitOr": "|", "BitXor": "^", "Shl": "<<", "Shr": ">>", "In": "in", "NotIn": "not in"}

const CALL_BUILTINS := {"print": "null", "str": "str", "input": "str", "len": "int", "type": "str",
    "isinstance": "bool", "__slice": "any", "__len": "int", "__del_item": "null"}

class TypeChecker:
    func init(file, options=null):
        self.file = file
        self.options = options
        self.diags = []
        self.functions = {}
        self.classes = {}
        self.scopes = []
        self.fn_stack = []
        self.current_class = ""
        self.sized_results = {}
        self.ns_functions = {}

    func error(at, msg):
        append(self.diags, [at.line, at.column, msg])

    func validate_type(t, ref):
        known := (t.name in BUILTIN_TYPES) or (t.name in self.classes)
        if not known and self.options != null:
            o := self.options
            known = (t.name in o.imported_structs) or (t.name in o.imported_names) or (t.name in o.imported_enums) or (t.name in o.imported_interfaces)
        if not known:
            self.error(ref, "type inconnu '" + t.name + "'")
            return false
        n := len(t.args)
        arity_ok := true
        if t.name == "list":
            arity_ok = n <= 1
        elif t.name == "dict":
            arity_ok = n == 0 or n == 2
        elif t.name == "future":
            arity_ok = n <= 1
        elif t.name != "tuple" and t.name != "func":
            arity_ok = n == 0
        if not arity_ok:
            self.error(ref, "nombre de paramètres de type invalide pour '" + t.name + "'")
        ok := arity_ok
        k := 0
        while k < len(ref.args) and k < n:
            ok = self.validate_type(t.args[k], ref.args[k]) and ok
            k += 1
        return ok

    func signature_of(fn):
        sig := FuncSig()
        sig.known = true
        for p in fn.params:
            append(sig.names, p.name)
            append(sig.params, type_from_ref(p.type) if p.type != null and not p.is_rest else TType())
            append(sig.has_default, p.default_value != null or p.is_rest)
        if fn.return_type != null:
            sig.ret = type_from_ref(fn.return_type)
        return sig

    func collect(stmts):
        for s in stmts:
            k := s.kind
            if k == "FunctionDecl":
                if s.extends_type == "":
                    self.functions[s.name] = self.signature_of(s)
            elif k == "StructDecl" or k == "ClassDecl" or k == "InterfaceDecl":
                info := ClassInfo()
                if k == "ClassDecl":
                    if s.base_class != null:
                        info.base = s.base_class
                    info.interfaces = s.interfaces
                if s.body != null:
                    for m in s.body.statements:
                        if m.kind == "FunctionDecl":
                            info.methods[m.name] = self.signature_of(m)
                        elif m.kind == "VariableDecl":
                            info.fields[m.name] = type_from_ref(m.type) if m.type != null else TType()
                self.classes[s.name] = info
            elif k == "EnumDecl":
                info := ClassInfo()
                info.is_enum = true
                self.classes[s.name] = info
        if self.options != null:
            for local in self.options.imported_functions:
                self.functions[local] = _sig_from_module(self.options.imported_functions[local])

    func namespace_function(m):
        if self.options == null or m.object.kind != "Identifier":
            return null
        ns := m.object.name
        for sc in self.scopes:
            if ns in sc:
                return null
        if not (ns in self.options.namespace_imports):
            return null
        fns := self.options.namespace_imports[ns].sigs.functions
        if not (m.member in fns):
            return null
        key := ns + "." + m.member
        if key in self.ns_functions:
            return self.ns_functions[key]
        sig := _sig_from_module(fns[m.member])
        self.ns_functions[key] = sig
        return sig

    func is_subclass(sub, base):
        cur := sub
        guard := 0
        while guard < 64 and cur != "":
            if cur == base:
                return true
            if not (cur in self.classes):
                if self.options != null and (cur in self.options.imported_structs):
                    if self.options.imported_structs[cur].is_class:
                        return true
                return false
            c := self.classes[cur]
            for i in c.interfaces:
                if i == base:
                    return true
            cur = c.base
            guard += 1
        return false

    func assignable(frm, to, expr=null):
        if to.is_any() or frm.is_any():
            return true
        if frm.name == "null":
            return to.nullable or to.name == "null"
        if frm.nullable and not to.nullable:
            return false
        if frm.name == to.name:
            if frm.name == "func":
                return true
            if len(frm.args) == len(to.args):
                i := 0
                while i < len(frm.args):
                    if not self.assignable(frm.args[i], to.args[i]):
                        return false
                    i += 1
            return true
        if is_float(to.name) and is_numeric(frm.name):
            return to.name == "float" or frm.name != "float"
        if is_sized_int(to.name) and is_integral(frm.name):
            r := sized_int_range(to.name)
            v := int_literal(expr)
            if v != null:
                return v >= r[0] and v <= r[1]
            if is_sized_int(frm.name):
                fr := sized_int_range(frm.name)
                return fr[0] >= r[0] and fr[1] <= r[1]
            return true
        if to.name == "int" and is_sized_int(frm.name):
            return true
        return self.is_subclass(frm.name, to.name)

    func expect_assignable(frm, to, expr, what):
        if self.assignable(frm, to, expr):
            return
        v := int_literal(expr)
        if is_sized_int(to.name) and v != null:
            self.error(expr, what + " : la valeur " + str(v) + " ne tient pas dans " + to.name)
            return
        self.error(expr, what + " : attendu " + to.str() + ", obtenu " + frm.str())

    func declare(name, t):
        self.scopes[len(self.scopes) - 1][name] = t

    func lookup(name):
        i := len(self.scopes) - 1
        while i >= 0:
            if name in self.scopes[i]:
                return self.scopes[i][name]
            i -= 1
        if name in self.functions:
            fs := self.functions[name]
            return _func_type(fs.params, fs.ret)
        return TType()

    # ------------------------------------------------------------------ expressions
    func infer(e):
        k := e.kind
        if k == "Literal":
            lk := e.literal_kind
            if lk == "Integer":
                return of("int")
            if lk == "Float":
                return of("float")
            if lk == "Boolean":
                return of("bool")
            if lk == "Null":
                return of("null")
            if lk == "Char":
                return of("char")
            return of("str")
        if k == "FStringLiteral":
            # (les sous-expressions ne sont pas inférées, comme en C++)
            return of("str")
        if k == "Identifier":
            return self.lookup(e.name)
        if k == "ListLiteral":
            ts := [self.infer(x) for x in e.elements]
            return of("list") if len(ts) == 0 else list_of(unify(ts))
        if k == "DictLiteral":
            ks := []
            vs := []
            for kv in e.entries:
                append(ks, self.infer(kv.key))
                append(vs, self.infer(kv.value))
            t := of("dict")
            if len(ks) > 0:
                t.args = [unify(ks), unify(vs)]
            return t
        if k == "TupleLiteral":
            for x in e.elements:
                self.infer(x)
            return of("tuple")
        if k == "BinaryExpr":
            l := self.infer(e.left)
            r := self.infer(e.right)
            res := self.binary_result(e.op, l, r, e)
            if is_sized_int(res.name):
                self.sized_results[e.uid] = res.name
            return res
        if k == "UnaryExpr":
            t := self.infer(e.operand)
            op := e.op
            if op == "Not":
                return of("bool")
            if op == "Await" or op == "Spread" or op == "DictSpread":
                return TType()
            if op == "Plus" or op == "Minus":
                if is_sized_int(t.name) and not t.nullable:
                    self.sized_results[e.uid] = t.name
                if t.is_any() or (is_numeric(t.name) and not t.nullable):
                    return t
                self.error(e, "opérateur unaire impossible sur " + t.str())
                return TType()
            if op == "BitNot":
                if is_sized_int(t.name) and not t.nullable:
                    self.sized_results[e.uid] = t.name
                if t.is_any() or (is_integral(t.name) and not t.nullable):
                    return t
                self.error(e, "'~' attend un entier, obtenu " + t.str())
                return TType()
            return TType()
        if k == "ConditionalExpr":
            self.infer(e.condition)
            a := self.infer(e.then_expr)
            b := self.infer(e.else_expr)
            if a.str() == b.str():
                return a
            if a.name == "null" and not b.is_any():
                b = b.copy()
                b.nullable = true
                a = b
            elif b.name == "null" and not a.is_any():
                a = a.copy()
                a.nullable = true
            else:
                return TType()
            return a
        if k == "RangeExpr":
            for bound in [e.start, e.end]:
                if bound == null:
                    continue
                t := self.infer(bound)
                if not t.is_any() and not is_integral(t.name):
                    self.error(bound, "borne d'intervalle : attendu int, obtenu " + t.str())
            return TType()
        if k == "CallExpr":
            return self.infer_call(e)
        if k == "IndexExpr":
            obj := self.infer(e.object)
            idx := self.infer(e.index)
            if obj.nullable and not obj.is_any():
                self.error(e, "indexation d'une valeur peut-être null (" + obj.str() + ")")
            if obj.name == "list" or obj.name == "str" or obj.name == "tuple":
                if not idx.is_any() and not is_integral(idx.name):
                    self.error(e.index, "index : attendu int, obtenu " + idx.str())
                if obj.name == "str":
                    return of("char")
                if obj.name == "list" and len(obj.args) == 1:
                    return obj.args[0]
                return TType()
            if obj.name == "dict" and len(obj.args) == 2:
                self.expect_assignable(idx, obj.args[0], e.index, "clé de dict")
                return obj.args[1]
            return TType()
        if k == "MemberExpr":
            sig := self.namespace_function(e)
            if sig != null:
                return _func_type(sig.params, sig.ret)
            obj := self.infer(e.object)
            if not (obj.name in self.classes):
                return TType()
            if obj.nullable:
                self.error(e, "accès membre '" + e.member + "' sur une valeur peut-être null (" + obj.str() + ")")
            cls := obj.name
            while cls != "":
                if not (cls in self.classes):
                    break
                c := self.classes[cls]
                if e.member in c.fields:
                    return c.fields[e.member]
                if e.member in c.methods:
                    mt := c.methods[e.member]
                    return _func_type(mt.params, mt.ret)
                cls = c.base
            return TType()
        if k == "ErrorPropagationExpr":
            t := self.infer(e.operand).copy()
            t.nullable = false
            return t
        if k == "LambdaExpr":
            fn := e.function
            self.function(fn, "")
            ps := [type_from_ref(p.type) if p.type != null else TType() for p in fn.params]
            return _func_type(ps, type_from_ref(fn.return_type) if fn.return_type != null else TType())
        if k == "ComprehensionExpr":
            append(self.scopes, {})
            for cl in e.clauses:
                t := self.infer(cl.expr) if cl.expr != null else TType()
                if cl.clause_kind == "For":
                    elem := TType()
                    if cl.expr != null and cl.expr.kind == "RangeExpr":
                        elem = of("int")
                    elif t.name == "list" and len(t.args) == 1:
                        elem = t.args[0]
                    self.declare(cl.variable, elem)
            out := null
            if e.comp_kind == "List":
                out = list_of(self.infer(e.element) if e.element != null else TType())
            else:
                kt := self.infer(e.key) if e.key != null else TType()
                vt := self.infer(e.value) if e.value != null else TType()
                out = TType("dict", [kt, vt])
            self.scopes = self.scopes[0:len(self.scopes) - 1]
            return out
        return TType()

    func _mismatch(op, l, r, b):
        self.error(b, "opération '" + op + "' impossible entre " + l.str() + " et " + r.str())
        return TType()

    # [vrai si concerné, type résultat]
    func _sized_mix(op, l, r, b):
        if not is_sized_int(l.name) and not is_sized_int(r.name):
            return [false, null]
        if is_sized_int(l.name) and is_sized_int(r.name) and l.name != r.name:
            self.error(b, "opération '" + op + "' entre " + l.name + " et " + r.name + " : convertir explicitement (to_" + l.name + "(…) ou to_" + r.name + "(…))")
            return [true, TType()]
        if not is_integral(l.name) or not is_integral(r.name):
            return [false, null]
        return [true, of(l.name if is_sized_int(l.name) else r.name)]

    func binary_result(op_kind, l, r, b):
        op := OP_TEXT[op_kind]
        if op_kind == "Eq" or op_kind == "Ne" or op_kind == "In" or op_kind == "NotIn":
            return of("bool")
        if op_kind == "Lt" or op_kind == "Le" or op_kind == "Gt" or op_kind == "Ge":
            if not l.is_any() and not r.is_any() and not (is_numeric(l.name) and is_numeric(r.name)) and l.name != r.name:
                self._mismatch(op, l, r, b)
            return of("bool")
        if op_kind == "And" or op_kind == "Or":
            return l if l.str() == r.str() else TType()
        if l.is_any() or r.is_any():
            return TType()
        if l.nullable or r.nullable:
            return self._mismatch(op, l, r, b)
        bitwise := op_kind == "BitAnd" or op_kind == "BitOr" or op_kind == "BitXor" or op_kind == "Shl" or op_kind == "Shr"
        if bitwise:
            if l.name == "bool" and r.name == "bool" and op_kind != "Shl" and op_kind != "Shr":
                return l
            if not is_integral(l.name) or not is_integral(r.name):
                return self._mismatch(op, l, r, b)
            if (op_kind == "Shl" or op_kind == "Shr") and is_sized_int(l.name):
                return l
            mix := self._sized_mix(op, l, r, b)
            if mix[0]:
                return mix[1]
            return of("int")
        if op_kind == "Add" and l.name == "str" and r.name == "str":
            return l
        if op_kind == "Add" and l.name == "list" and r.name == "list":
            return l if l.str() == r.str() else list_of(TType())
        if op_kind == "Add" and l.name == "tuple" and r.name == "tuple":
            return l
        if op_kind == "Mul":
            if (l.name == "list" or l.name == "tuple" or l.name == "str") and is_integral(r.name):
                return l
            if is_integral(l.name) and (r.name == "list" or r.name == "tuple" or r.name == "str"):
                return r
        if not is_numeric(l.name) or not is_numeric(r.name):
            return self._mismatch(op, l, r, b)
        if op_kind == "Div":
            return of("float")
        if is_float(l.name) or is_float(r.name):
            return of("float")
        mix := self._sized_mix(op, l, r, b)
        if mix[0]:
            return mix[1]
        return of("int")

    func check_args(sig, call, callee_name):
        pos := 0
        spread_seen := false
        for a in call.arguments:
            t := self.infer(a.value)
            idx := -1
            if a.name == null and a.value.kind == "UnaryExpr" and a.value.op == "Spread":
                spread_seen = true
            if spread_seen and a.name == null:
                continue
            if a.name != null:
                i := 0
                while i < len(sig.names):
                    if sig.names[i] == a.name:
                        idx = i
                    i += 1
            else:
                idx = pos
                pos += 1
            if idx >= 0 and idx < len(sig.params):
                self.expect_assignable(t, sig.params[idx], a.value, "argument '" + sig.names[idx] + "' de " + callee_name)

    func infer_call(call):
        if call.callee.kind == "Identifier":
            name := call.callee.name
            shadowed := false
            for sc in self.scopes:
                if name in sc:
                    shadowed = true
            if not shadowed:
                if name in self.functions:
                    fs := self.functions[name]
                    self.check_args(fs, call, name)
                    return fs.ret
                if name in self.classes and not self.classes[name].is_enum:
                    c := name
                    while c != "":
                        if not (c in self.classes):
                            break
                        ci := self.classes[c]
                        if "init" in ci.methods:
                            self.check_args(ci.methods["init"], call, name)
                            return of(name)
                        c = ci.base
                    for a in call.arguments:
                        self.infer(a.value)
                    return of(name)
                if self.options != null and (name in self.options.imported_structs):
                    for a in call.arguments:
                        self.infer(a.value)
                    return of(name)
                if name in CALL_BUILTINS:
                    for a in call.arguments:
                        self.infer(a.value)
                    return of(CALL_BUILTINS[name])
            t := self.lookup(name)
            for a in call.arguments:
                self.infer(a.value)
            if t.name == "func" and len(t.args) > 0:
                return t.args[len(t.args) - 1]
            if not t.is_any() and t.name != "func":
                self.error(call, "'" + name + "' (" + t.str() + ") n'est pas appelable")
            return TType()
        if call.callee.kind == "MemberExpr":
            m := call.callee
            sig := self.namespace_function(m)
            if sig != null:
                self.check_args(sig, call, m.object.name + "." + m.member)
                return sig.ret
            obj := self.infer(m.object)
            if (obj.name in self.classes) and not self.classes[obj.name].is_enum:
                if obj.nullable:
                    self.error(call, "appel de '" + m.member + "' sur une valeur peut-être null (" + obj.str() + ")")
                c := obj.name
                while c != "":
                    if not (c in self.classes):
                        break
                    ci := self.classes[c]
                    if m.member in ci.methods:
                        mt := ci.methods[m.member]
                        self.check_args(mt, call, obj.name + "." + m.member)
                        return mt.ret
                    c = ci.base
            for a in call.arguments:
                self.infer(a.value)
            return TType()
        self.infer(call.callee)
        for a in call.arguments:
            self.infer(a.value)
        return TType()

    # ------------------------------------------------------------------ instructions
    func block(b, narrowed=""):
        if b == null:
            return
        append(self.scopes, {})
        if narrowed != "":
            self.narrow(narrowed)
        self.statements(b.statements)
        self.scopes = self.scopes[0:len(self.scopes) - 1]

    # [nom, non_null] ou null
    func null_test(cond):
        if cond.kind != "BinaryExpr" or (cond.op != "Eq" and cond.op != "Ne"):
            return null
        other := null
        if cond.right.kind == "Literal" and cond.right.literal_kind == "Null":
            other = cond.left
        elif cond.left.kind == "Literal" and cond.left.literal_kind == "Null":
            other = cond.right
        if other == null or other.kind != "Identifier":
            return null
        return [other.name, cond.op == "Ne"]

    func narrow(name):
        t := self.lookup(name)
        if not t.nullable or t.is_any():
            return
        t = t.copy()
        t.nullable = false
        self.declare(name, t)

    func statements(lst):
        for s in lst:
            self.stmt(s)
            if s.kind != "IfStmt":
                continue
            nt := self.null_test(s.condition)
            if nt == null or nt[1] or len(s.elif_clauses) > 0 or s.else_block != null or len(s.then_block.statements) == 0:
                continue
            last_stmt := s.then_block.statements[len(s.then_block.statements) - 1]
            last := last_stmt.kind
            raises := last == "ExpressionStmt" and last_stmt.expr.kind == "CallExpr" and last_stmt.expr.callee.kind == "Identifier" and last_stmt.expr.callee.name == "raise"
            if last == "ReturnStmt" or last == "BreakStmt" or last == "ContinueStmt" or raises:
                self.narrow(nt[0])

    func function(fn, self_class=""):
        sig := self.signature_of(fn)
        for p in fn.params:
            if p.type != null:
                self.validate_type(type_from_ref(p.type), p.type)
        if fn.return_type != null:
            self.validate_type(sig.ret, fn.return_type)
        append(self.scopes, {})
        if self_class != "":
            self.declare("self", of(self_class))
        elif fn.extends_type != "":
            self.declare("self", TType())
        i := 0
        while i < len(fn.params):
            p := fn.params[i]
            if p.default_value != null:
                d := self.infer(p.default_value)
                self.expect_assignable(d, sig.params[i], p.default_value, "valeur par défaut de '" + p.name + "'")
            self.declare(p.name, of("list") if p.is_rest else sig.params[i])
            i += 1
        append(self.fn_stack, sig)
        if fn.body != null:
            self.statements(fn.body.statements)
        self.fn_stack = self.fn_stack[0:len(self.fn_stack) - 1]
        self.scopes = self.scopes[0:len(self.scopes) - 1]

    func stmt(s):
        k := s.kind
        if k == "VariableDecl" or k == "ConstDecl":
            is_const := k == "ConstDecl"
            ref := s.type
            if not is_const and s.declared_only:
                t := type_from_ref(ref) if ref != null else TType()
                if ref != null and not self.validate_type(t, ref):
                    t = TType()
                self.declare(s.name, t)
                return
            v := self.infer(s.value)
            if ref != null:
                t := type_from_ref(ref)
                if not self.validate_type(t, ref):
                    t = TType()
                self.expect_assignable(v, t, s.value, "variable '" + s.name + "'")
                self.declare(s.name, t)
            else:
                self.declare(s.name, v if is_const else TType())
            return
        if k == "Assignment":
            v := self.infer(s.value)
            if s.target.kind == "Identifier":
                name := s.target.name
                cur := self.lookup(name)
                wide := cur.copy()
                wide.nullable = true
                if not cur.nullable and not cur.is_any() and not self.assignable(v, cur, s.value) and self.assignable(v, wide, s.value):
                    i := len(self.scopes) - 1
                    while i >= 0:
                        if not (name in self.scopes[i]):
                            i -= 1
                            continue
                        narrowed_binding := false
                        o := i - 1
                        while o >= 0:
                            if name in self.scopes[o]:
                                g := self.scopes[o][name]
                                narrowed_binding = g.nullable and g.name == cur.name
                                break
                            o -= 1
                        if narrowed_binding:
                            self.scopes[i][name] = wide
                            return
                        break
                self.expect_assignable(v, cur, s.value, "variable '" + name + "'")
            else:
                t := self.infer(s.target)
                what := "champ '" + s.target.member + "'" if s.target.kind == "MemberExpr" else "élément"
                self.expect_assignable(v, t, s.value, what)
            return
        if k == "CompoundAssignment":
            t := self.infer(s.target)
            v := self.infer(s.value)
            res := self.binary_result(s.op, t, v, s)
            if not res.is_any():
                self.expect_assignable(res, t, s.value, "affectation composée")
            return
        if k == "ExpressionStmt":
            self.infer(s.expr)
            return
        if k == "IfStmt":
            self.infer(s.condition)
            nt := self.null_test(s.condition)
            tested := nt[0] if nt != null else ""
            not_null := nt != null and nt[1]
            self.block(s.then_block, tested if not_null else "")
            for e in s.elif_clauses:
                self.infer(e.condition)
                self.block(e.body)
            self.block(s.else_block, tested if not not_null and len(s.elif_clauses) == 0 else "")
            return
        if k == "WhileStmt":
            self.infer(s.condition)
            nt := self.null_test(s.condition)
            self.block(s.body, nt[0] if nt != null and nt[1] else "")
            if s.else_body != null:
                self.block(s.else_body)
            return
        if k == "ForStmt":
            it := self.infer(s.iterable)
            elem := TType()
            if s.iterable.kind == "RangeExpr":
                elem = of("int")
            elif it.name == "list" and len(it.args) == 1:
                elem = it.args[0]
            elif it.name == "str":
                elem = of("char")
            elif it.name == "dict" and len(it.args) == 2:
                elem = it.args[0]
            append(self.scopes, {})
            self.declare(s.variable, elem)
            self.block(s.body)
            self.scopes = self.scopes[0:len(self.scopes) - 1]
            if s.else_body != null:
                self.block(s.else_body)
            return
        if k == "ReturnStmt":
            v := self.infer(s.value) if s.value != null else of("null")
            if len(self.fn_stack) == 0:
                return
            want := self.fn_stack[len(self.fn_stack) - 1].ret
            if s.value != null:
                self.expect_assignable(v, want, s.value, "valeur de retour")
            elif not self.assignable(v, want):
                self.error(s, "valeur de retour : attendu " + want.str() + ", 'return' sans valeur")
            return
        if k == "TryStmt":
            self.block(s.try_block)
            for c in s.catch_clauses:
                append(self.scopes, {})
                if c.name != null:
                    self.declare(c.name, TType())
                self.block(c.body)
                self.scopes = self.scopes[0:len(self.scopes) - 1]
            self.block(s.finally_block)
            return
        if k == "MatchStmt":
            self.infer(s.subject)
            for c in s.cases:
                append(self.scopes, {})
                todo := [c.pattern]
                while len(todo) > 0:
                    p := todo[len(todo) - 1]
                    todo = todo[0:len(todo) - 1]
                    if p == null:
                        continue
                    if p.pk == "Bind":
                        self.declare(p.name, TType())
                    for sub in p.subpatterns:
                        append(todo, sub)
                if c.guard != null:
                    self.infer(c.guard)
                self.block(c.body)
                self.scopes = self.scopes[0:len(self.scopes) - 1]
            return
        if k == "FunctionDecl":
            if len(self.scopes) > 1:
                sig := self.signature_of(s)
                self.declare(s.name, _func_type(sig.params, sig.ret))
            self.function(s, self.current_class)
            return
        if k == "StructDecl" or k == "ClassDecl" or k == "InterfaceDecl":
            if s.body == null:
                return
            saved := self.current_class
            self.current_class = s.name
            append(self.scopes, {})
            for m in s.body.statements:
                if m.kind == "FunctionDecl":
                    self.function(m, s.name)
                else:
                    self.stmt(m)
            self.scopes = self.scopes[0:len(self.scopes) - 1]
            self.current_class = saved
            return

    func check(program):
        self.diags = []
        self.scopes = [{}]
        self.collect(program.top_level)
        for s in program.top_level:
            if s.kind == "FunctionDecl":
                self.function(s, "")
                continue
            self.stmt(s)
        return self.diags

    func check_or_throw(program):
        diags := self.check(program)
        if len(diags) == 0:
            return
        msg := self.file + ":" + str(diags[0][0]) + ":" + str(diags[0][1]) + ": " + diags[0][2]
        i := 1
        while i < len(diags):
            msg += "\n  " + self.file + ":" + str(diags[i][0]) + ":" + str(diags[i][1]) + ": " + diags[i][2]
            i += 1
        raise("TypeCheckError", msg)

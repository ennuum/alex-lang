# ALEX STANDARD LIBRARY — compiler.type_checker
#
# Analyse sémantique et vérification de types statique (légère) d'un arbre compiler.ast. Elle reprend les
# règles du compilateur natif (src/Analyzer.cpp) — portée par blocs, hissage des func / class / struct / enum /
# interface, noms intrinsèques (print, input, str, raise, isinstance...), arité des appels de fonctions et de
# constructeurs connus, await hors d'une async func, break / continue hors d'une boucle — et ajoute des
# avertissements utiles : variables et imports inutilisés, code inatteignable, changement de type d'une
# variable, opérations sur des types incompatibles connus statiquement.
#
#   use compiler.type_checker as tc
#   bag := tc.check_source("x := 1\ny := x + \"a\"\nprint(z)\n", "demo.al")
#   print(bag.render())     # demo.al:2:8: erreur[E0403]: opérateur '+' entre int et str
#                           # demo.al:3:7: erreur[E0301]: nom 'z' non défini
#   r := tc.TypeChecker("demo.al").run(programme)    # DiagnosticBag ; r.symbols : déclarations de haut niveau
#   print(tc.infer_source("[1, 2]"))                  # list[int]
#
# Codes : E0301 nom non défini, E0302 double déclaration, E0303 affectation d'un nom non déclaré,
# E0304 affectation d'une constante, E0305 break/continue hors boucle, E0306 return hors fonction,
# E0307 await hors async, E0308 self hors méthode, E0309 classe de base inconnue, E0401 arité,
# E0402 type annoté incompatible, E0403 opérandes incompatibles, E0404 appel d'une valeur non appelable ;
# W0101 variable inutilisée, W0102 import inutilisé, W0103 code inatteignable, W0104 changement de type,
# W0105 condition constante.
# Les types inférés : int, float, str, char, bool, null, list, dict, tuple, func, ou null (inconnu).
# Erreurs : aucune levée par check (diagnostics) ; check_or_raise lève SemanticError / TypeError.

from core use len, type
from collections use append
use string as _s
use compiler.ast as _ast
use compiler.parser as _ps
use compiler.diagnostics as _dg

const INTRINSICS := ["print", "input", "str", "raise", "isinstance", "__list_append", "__len", "__del_item",
    "__slice", "__list_insert", "__list_remove_at", "__list_clear", "__dict_remove_key", "__make_set"]
const BUILTINS := ["abs", "all", "any", "append", "bool", "capitalize", "center", "chr", "clear", "copy", "count",
    "dict", "divmod", "endswith", "enumerate", "extend", "filter", "find", "float", "get", "hash", "index", "insert",
    "int", "isalpha", "isdigit", "isspace", "items", "join", "keys", "len", "list", "ljust", "lower", "lstrip", "map",
    "max", "min", "ord", "pop", "pow", "range", "remove", "replace", "reverse", "reversed", "rjust", "round",
    "rstrip", "set", "setdefault", "sort", "sorted", "split", "startswith", "strip", "sum", "title", "tuple", "type",
    "update", "upper", "values", "zfill", "zip"]
const TYPE_NAMES := ["int", "float", "str", "char", "bool", "null", "list", "dict", "tuple", "func", "any", "byte"]
const NUMERIC := ["int", "float"]

class Binding:
    func init(name, kind, node, is_const=false, type_name=null):
        self.name = name
        self.kind = kind          # var | const | param | func | class | struct | enum | interface | import | builtin
        self.node = node
        self.is_const = is_const
        self.type = type_name
        self.declared_type = null
        self.reads = 0
        self.line = 0
        self.column = 0
        if node != null:
            self.line = node.line
            self.column = node.column

class Scope:
    func init(parent, kind):
        self.parent = parent
        self.kind = kind          # module | function | block | class | lambda
        self.names = {}
        self.order = []

    func local(name):
        if name in self.names:
            return self.names[name]
        return null

    func lookup(name):
        s := self
        while s != null:
            if name in s.names:
                return s.names[name]
            s = s.parent
        return null

class TypeChecker:
    func init(file="<source>", source=null, warnings=true):
        self.bag = _dg.DiagnosticBag(file, source)
        self.warnings = warnings
        self.scope = null
        self.loops = 0
        self.funcs = []           # pile : [is_async, est_méthode]
        self.symbols = []
        self.classes = {}

    # ---- outils ----
    func err(code, msg, n, phase="SemanticError"):
        self.bag.error(code, msg, n.line, n.column, 1, phase)

    func warn(code, msg, n):
        if self.warnings:
            self.bag.warning(code, msg, n.line, n.column)

    func push(kind):
        self.scope = Scope(self.scope, kind)

    func pop():
        s := self.scope
        if self.warnings and (s.kind == "function" or s.kind == "block" or s.kind == "lambda"):
            for nm in s.order:
                b := s.names[nm]
                if b.kind == "var" and b.reads == 0 and not _s.starts_with(nm, "_"):
                    self.warn("W0101", "variable '" + nm + "' déclarée mais jamais lue", b.node)
        if self.warnings and s.kind == "module":
            for nm in s.order:
                b := s.names[nm]
                if b.kind == "import" and b.reads == 0 and not _s.starts_with(nm, "_"):
                    self.warn("W0102", "import '" + nm + "' inutilisé", b.node)
        self.scope = s.parent

    func declare(name, kind, n, is_const=false, type_name=null):
        if self.scope.local(name) != null:
            self.err("E0302", "'" + name + "' est déjà déclaré dans ce scope (§5.1)", n)
            return self.scope.local(name)
        if type_name == "null":
            type_name = null      # « x := null » : type connu seulement à l'affectation suivante
        b := Binding(name, kind, n, is_const, type_name)
        self.scope.names[name] = b
        append(self.scope.order, name)
        return b

    func resolve(name, n):
        b := self.scope.lookup(name)
        if b == null:
            if name in INTRINSICS or name in BUILTINS or _s.starts_with(name, "__"):
                return null
            if (name == "self" or name == "super") and len(self.funcs) > 0 and self.funcs[len(self.funcs) - 1][1]:
                return null
            if name == "self" or name == "super":
                self.err("E0308", "'" + name + "' n'est utilisable que dans une méthode de classe", n)
                return null
            self.err("E0301", "nom '" + name + "' non défini", n, "NameError")
            return null
        b.reads += 1
        return b

    # ---- point d'entrée ----
    func run(program):
        self.push("module")
        self.statements(program.body, true)
        for nm in self.scope.order:
            b := self.scope.names[nm]
            if b.kind != "import":
                append(self.symbols, {"name": nm, "kind": b.kind, "line": b.line, "type": b.type})
        self.pop()
        return self.bag

    func hoist(stmts):
        for s in stmts:
            k := s.kind
            if k == "Func" and s.extends_type == null:
                self.declare(s.name, "func", s, false, "func")
            elif k == "Class" or k == "Struct" or k == "Enum" or k == "Interface":
                b := self.declare(s.name, _s.lower(k), s, false, "type")
                self.classes[s.name] = s

    func statements(stmts, top=false):
        self.hoist(stmts)
        dead := false
        deferred := []
        for s in stmts:
            if dead:
                self.warn("W0103", "code inatteignable", s)
                dead = false
            # Les corps de fonctions (et méthodes) sont analysés à la fin de la liste : ils peuvent lire des
            # noms déclarés plus loin dans la même portée (ils s'exécutent après).
            if s.kind == "Func" or s.kind == "Class" or s.kind == "Extend" or s.kind == "Struct" or s.kind == "Interface":
                append(deferred, [s, self.loops])
            else:
                self.stmt(s)
            if s.kind == "Return" or s.kind == "Break" or s.kind == "Continue" or _is_raise(s):
                dead = true
        for d in deferred:
            saved := self.loops
            self.loops = d[1]
            self.stmt(d[0])
            self.loops = saved

    func block(stmts, kind="block"):
        self.push(kind)
        self.statements(stmts)
        self.pop()

    # ---- instructions ----
    func stmt(s):
        k := s.kind
        if k == "Use":
            nm := s.alias
            if nm == null:
                nm = s.path[len(s.path) - 1]
            self.declare(nm, "import", s)
        elif k == "FromUse":
            for nm in s.names:
                self.declare(nm, "import", s)
        elif k == "Func":
            self.function(s, false)
        elif k == "Extend":
            for f in s.methods:
                self.function(f, true)
        elif k == "Class" or k == "Struct" or k == "Interface":
            self.class_decl(s)
        elif k == "Enum":
            return null
        elif k == "Const":
            t := self.expr(s.value)
            if s.type != null:
                self.check_annot(s.type, t, s)
                t = s.type.name
            self.declare(s.name, "const", s, true, t)
        elif k == "VarDecl":
            t := null
            if s.value != null:
                t = self.expr(s.value)
            b := self.declare(s.name, "var", s, false, t)
            if s.type != null:
                self.check_annot(s.type, t, s)
                b.declared_type = s.type.name
                b.type = s.type.name
            if s.declared_only:
                b.reads += 1
        elif k == "Assign":
            t := self.expr(s.value)
            self.assign_target(s.target, t, s)
        elif k == "CompoundAssign":
            vt := self.expr(s.value)
            tt := self.expr(s.target)
            self.binary_types(s.op, tt, vt, s)
            if s.target.kind == "Name":
                b := self.scope.lookup(s.target.name)
                if b != null and b.is_const:
                    self.err("E0304", "affectation de la constante '" + s.target.name + "'", s)
        elif k == "Destructure":
            self.expr(s.value)
            for tg in s.targets:
                if s.declare:
                    self.declare(tg.expr.name, "var", tg.expr)
                else:
                    self.assign_target(tg.expr, null, s)
        elif k == "ExprStmt":
            self.expr(s.expr)
        elif k == "If":
            self.cond(s.cond)
            self.block(s.then_body)
            for e in s.elifs:
                self.cond(e.cond)
                self.block(e.body)
            if s.else_body != null:
                self.block(s.else_body)
        elif k == "While":
            self.expr(s.cond)
            self.loops += 1
            self.block(s.body)
            self.loops -= 1
            if s.else_body != null:
                self.block(s.else_body)
        elif k == "For":
            self.expr(s.iter)
            self.loops += 1
            self.push("block")
            for v in s.vars:
                b := self.declare(v.expr.name, "var", v.expr)
                b.reads += 1
            self.statements(s.body)
            self.pop()
            self.loops -= 1
            if s.else_body != null:
                self.block(s.else_body)
        elif k == "Try":
            self.block(s.body)
            for c in s.catches:
                self.push("block")
                if c.name != null:
                    b := self.declare(c.name, "var", c)
                    b.reads += 1
                self.statements(c.body)
                self.pop()
            if s.finally_body != null:
                self.block(s.finally_body)
        elif k == "Match":
            self.expr(s.subject)
            for c in s.cases:
                self.push("block")
                self.pattern(c.pattern)
                if c.guard != null:
                    self.expr(c.guard)
                self.statements(c.body)
                self.pop()
        elif k == "Break" or k == "Continue":
            if self.loops == 0:
                self.err("E0305", "'" + _s.lower(k) + "' hors d'une boucle", s)
        elif k == "Return":
            if len(self.funcs) == 0:
                self.err("E0306", "'return' hors d'une fonction", s)
            if s.value != null:
                self.expr(s.value)
        elif k == "With":
            self.expr(s.resource)
            if s.name != null:
                b := self.declare(s.name, "var", s)
                b.reads += 1
            self.block(s.body)
        elif k == "Assert":
            self.expr(s.cond)
            if s.message != null:
                self.expr(s.message)
        elif k == "Del":
            for t in s.targets:
                self.expr(t)
        return null

    func pattern(p):
        if p.pk == "bind":
            b := self.declare(p.name, "var", p)
            b.reads += 1
        elif p.pk == "list" or p.pk == "tuple" or p.pk == "variant":
            for it in p.items:
                self.pattern(it)

    func cond(e):
        t := self.expr(e)
        if e.kind == "Literal" and e.lit == "bool":
            self.warn("W0105", "condition toujours " + str(e.value), e)

    func check_annot(tref, t, n):
        want := tref.name
        if t == null or want == "any" or not (want in TYPE_NAMES):
            return
        base := _base(t)
        if base == want:
            return
        if t == "null" and tref.nullable:
            return
        if want == "float" and base == "int":
            return
        self.err("E0402", "type annoté '" + want + "' incompatible avec la valeur de type '" + t + "'", n, "TypeError")

    func assign_target(target, t, s):
        if target.kind == "Name":
            b := self.scope.lookup(target.name)
            if b == null:
                if not (target.name in INTRINSICS) and not (target.name in BUILTINS) and not _s.starts_with(target.name, "__"):
                    self.err("E0303", "affectation de '" + target.name + "' qui n'est pas déclaré (utiliser ':=')", s, "NameError")
                return
            if b.is_const:
                self.err("E0304", "affectation de la constante '" + target.name + "'", s)
            elif b.declared_type != null and t != null:
                ann := _ast.Node("TypeRef", s.line, s.column, {"name": b.declared_type, "args": [], "nullable": false})
                self.check_annot(ann, t, s)
            elif b.kind == "var" and b.type != null and t != null and _base(b.type) != _base(t) and t != "null" and b.type != "null":
                if not ((b.type in NUMERIC) and (t in NUMERIC)):
                    self.warn("W0104", "la variable '" + target.name + "' change de type (" + b.type + " -> " + t + ")", s)
        else:
            self.expr(target)

    func function(f, is_method):
        for d in f.decorators:
            self.expr(d)
        for p in f.params:
            if p.default != null:
                self.expr(p.default)
        self.push("function")
        append(self.funcs, [f.is_async, is_method])
        for p in f.params:
            b := self.declare(p.name, "param", p, false, null)
            if p.type != null:
                b.type = p.type.name
                b.declared_type = p.type.name
        saved := self.loops
        self.loops = 0
        self.statements(f.body)
        self.loops = saved
        self.funcs = self.funcs[:len(self.funcs) - 1]
        self.pop()

    func class_decl(c):
        if c.kind == "Class" and c.base != null:
            if self.scope.lookup(c.base) == null:
                self.err("E0309", "classe de base '" + c.base + "' inconnue", c, "InheritanceError")
            else:
                self.scope.lookup(c.base).reads += 1
        if c.kind == "Class":
            for i in c.interfaces:
                b := self.scope.lookup(i)
                if b == null:
                    self.err("E0309", "interface '" + i + "' inconnue", c, "InterfaceError")
                else:
                    b.reads += 1
        self.push("class")
        for s in c.body:
            if s.kind == "Func":
                saved := self.scope
                self.scope = _module_scope(self.scope)
                self.function(s, true)
                self.scope = saved
            elif s.kind == "VarDecl":
                if s.value != null:
                    self.expr(s.value)
            else:
                self.stmt(s)
        self.scope = self.scope.parent

    # ---- expressions : renvoie le type inféré (ou null) ----
    func expr(e):
        if e == null:
            return null
        k := e.kind
        if k == "Literal":
            return e.lit
        if k == "FString":
            for p in e.parts:
                if _ast.is_node(p):
                    self.expr(p)
            return "str"
        if k == "Name":
            b := self.resolve(e.name, e)
            if b == null:
                if e.name in INTRINSICS or e.name in BUILTINS:
                    return "func"
                return null
            if b.kind == "func":
                return "func"
            return b.type
        if k == "Unary":
            t := self.expr(e.operand)
            if e.op == "not":
                return "bool"
            if e.op == "await":
                if len(self.funcs) > 0 and not self.funcs[len(self.funcs) - 1][0]:
                    self.err("E0307", "'await' n'est permis que dans une 'async func' ou au niveau supérieur d'un module", e, "AsyncError")
                return null
            if e.op == "-" or e.op == "+":
                if t != null and not (t in NUMERIC):
                    self.err("E0403", "opérateur unaire '" + e.op + "' sur une valeur de type " + t, e, "TypeError")
                return t
            if e.op == "~":
                return "int"
            return t
        if k == "Binary":
            lt := self.expr(e.left)
            rt := self.expr(e.right)
            return self.binary_types(e.op, lt, rt, e)
        if k == "Ternary":
            self.expr(e.cond)
            a := self.expr(e.then_expr)
            b := self.expr(e.else_expr)
            if a == b:
                return a
            return null
        if k == "Range":
            self.expr(e.start)
            self.expr(e.end)
            return "range"
        if k == "Call":
            return self.call(e)
        if k == "Member":
            self.expr(e.object)
            return null
        if k == "Index":
            ot := self.expr(e.object)
            self.expr(e.index)
            if ot == "str":
                return "char"
            if ot != null and _s.starts_with(ot, "list[") :
                return _s.substring(ot, 5, len(ot) - 1)
            return null
        if k == "Slice":
            ot := self.expr(e.object)
            self.expr(e.start)
            self.expr(e.stop)
            self.expr(e.step)
            return ot
        if k == "Propagate":
            self.expr(e.operand)
            return null
        if k == "Spread":
            self.expr(e.value)
            return null
        if k == "Lambda":
            for p in e.params:
                if p.default != null:
                    self.expr(p.default)
            self.push("lambda")
            for p in e.params:
                self.declare(p.name, "param", p)
            append(self.funcs, [false, len(self.funcs) > 0 and self.funcs[len(self.funcs) - 1][1]])
            saved := self.loops
            self.loops = 0
            self.expr(e.body)
            self.loops = saved
            self.funcs = self.funcs[:len(self.funcs) - 1]
            self.pop()
            return "func"
        if k == "ListLit" or k == "TupleLit" or k == "SetLit":
            ts := [self.expr(x) for x in e.elements]
            base := "list"
            if k == "TupleLit":
                base = "tuple"
            elif k == "SetLit":
                return "set"
            if len(ts) > 0 and base == "list":
                first := ts[0]
                same := first != null
                for t in ts:
                    if t != first:
                        same = false
                if same:
                    return "list[" + first + "]"
            return base
        if k == "DictLit":
            for en in e.entries:
                if en.kind == "DictEntry":
                    self.expr(en.key)
                    self.expr(en.value)
                else:
                    self.expr(en.value)
            return "dict"
        if k == "Comprehension":
            self.push("lambda")
            for c in e.clauses:
                if c.kind == "CompFor":
                    self.expr(c.iter)
                    b := self.declare(c.var, "var", c)
                    b.reads += 1
                else:
                    self.expr(c.cond)
            if e.comp == "dict":
                self.expr(e.key)
                self.expr(e.value)
            else:
                self.expr(e.element)
            self.pop()
            if e.comp == "dict":
                return "dict"
            if e.comp == "set":
                return "set"
            return "list"
        return null

    func binary_types(op, lt, rt, n):
        if op == "and" or op == "or":
            if lt == rt:
                return lt
            return null
        if op == "==" or op == "!=" or op == "<" or op == "<=" or op == ">" or op == ">=" or op == "in" or op == "not in":
            if (op == "<" or op == "<=" or op == ">" or op == ">=") and lt != null and rt != null:
                if not _comparable(lt, rt):
                    self.err("E0403", "comparaison '" + op + "' entre " + lt + " et " + rt, n, "TypeError")
            return "bool"
        if lt == null or rt == null:
            if op == "/" and (lt == "int" or lt == "float" or rt == "int" or rt == "float"):
                return "float"
            return null
        lb := _base(lt)
        rb := _base(rt)
        if (lb in NUMERIC) and (rb in NUMERIC):
            if op == "/":
                return "float"
            if lb == "float" or rb == "float":
                return "float"
            return "int"
        if op == "+" and (lb == "str" or lb == "char") and (rb == "str" or rb == "char"):
            return "str"
        if op == "+" and lb == "list" and rb == "list":
            return "list"
        if op == "*" and ((lb == "str" and rb == "int") or (lb == "list" and rb == "int")):
            return lb
        if op == "%" and lb == "str":
            return "str"
        if lb == "char" and rb == "int" and (op == "+" or op == "-"):
            return "char"
        if lb == "char" and rb == "char" and op == "-":
            return "int"
        if (lb == "bool" and rb == "bool") and (op == "&" or op == "|" or op == "^"):
            return "bool"
        if lb in ["int", "float", "str", "char", "bool", "null", "list", "dict", "tuple"] and rb in ["int", "float", "str", "char", "bool", "null", "list", "dict", "tuple"]:
            self.err("E0403", "opérateur '" + op + "' entre " + lt + " et " + rt, n, "TypeError")
        return null

    func call(e):
        args_t := []
        for a in e.args:
            append(args_t, self.expr(a.value))
        c := e.callee
        if c.kind == "Literal" and c.lit != "null":
            self.err("E0404", "une valeur de type " + c.lit + " n'est pas appelable", e, "TypeError")
            return null
        if c.kind == "Name" and c.name == "isinstance" and len(e.args) == 2 and e.args[1].value.kind == "Name":
            # 2e argument : nom de type résolu statiquement
            self.resolve(c.name, c)
            self.expr(e.args[0].value)
            return "bool"
        ct := self.expr(c)
        if c.kind == "Name":
            nm := c.name
            if nm == "str":
                return "str"
            if nm == "len" or nm == "hash":
                return "int"
            if nm == "print":
                return "null"
            b := self.scope.lookup(nm)
            if b != null and b.kind == "func":
                self.check_arity(e, b.node, nm)
                return _ret_type(b.node)
            if b != null and b.kind == "class":
                init := _find_init(b.node, self.classes)
                if init != null:
                    p2 := init.params
                    if len(p2) > 0 and p2[0].name == "self":
                        p2 = p2[1:]
                    self.check_params(e, p2, nm)
                return nm
            if b != null and b.kind == "struct":
                return nm
            if b != null and b.kind == "interface":
                self.err("E0404", "l'interface '" + nm + "' ne peut pas être instanciée : elle ne décrit qu'un contrat", e, "InterfaceError")
            if b != null and b.type != null and (b.type in ["int", "float", "str", "char", "bool", "list", "dict"]):
                self.err("E0404", "'" + nm + "' (de type " + b.type + ") n'est pas appelable", e, "TypeError")
        return null

    func check_arity(call, fn, label):
        self.check_params(call, fn.params, label)

    func check_params(call, params, label):
        n := len(params)
        rest := n > 0 and params[n - 1].rest
        for a in call.args:
            if a.name == null and a.value.kind == "Spread":
                return
            if a.name != null and rest:
                self.err("E0401", "les arguments nommés ne sont pas supportés pour '" + label + "' (paramètre variadique)", call, "ArgumentError")
                return
        if rest:
            n -= 1
        filled := [false for i in 0..n]
        pos := 0
        for a in call.args:
            if a.name == null:
                if pos >= n and rest:
                    continue
                if pos >= n:
                    self.err("E0401", "trop d'arguments dans l'appel de '" + label + "' (attendu au plus " + str(n) + ")", call, "ArgumentError")
                    return
                filled[pos] = true
                pos += 1
        for a in call.args:
            if a.name != null:
                idx := -1
                i := 0
                while i < n:
                    if params[i].name == a.name:
                        idx = i
                    i += 1
                if idx < 0:
                    self.err("E0401", "l'argument nommé '" + a.name + "' ne correspond à aucun paramètre de '" + label + "'", call, "ArgumentError")
                    return
                if filled[idx]:
                    self.err("E0401", "l'argument '" + a.name + "' est fourni à la fois positionnellement et par nom dans l'appel de '" + label + "'", call, "ArgumentError")
                    return
                filled[idx] = true
        i := 0
        while i < n:
            if not filled[i] and params[i].default == null:
                self.err("E0401", "argument manquant pour le paramètre '" + params[i].name + "' de '" + label + "'", call, "ArgumentError")
                return
            i += 1

func _module_scope(s):
    cur := s
    while cur.parent != null and cur.kind != "module":
        cur = cur.parent
    return cur

func _find_init(cls, classes):
    c := cls
    guard := 0
    while c != null and guard < 50:
        for s in c.body:
            if s.kind == "Func" and s.name == "init":
                return s
        if c.kind != "Class" or c.base == null or not (c.base in classes):
            return null
        c = classes[c.base]
        guard += 1
    return null

func _ret_type(fn):
    if fn.ret_type != null:
        return fn.ret_type.name
    if fn.short and len(fn.body) == 1 and fn.body[0].value != null and fn.body[0].value.kind == "Literal":
        return fn.body[0].value.lit
    return null

func _base(t):
    i := _s.find(t, "[")
    if i < 0:
        return t
    return _s.substring(t, 0, i)

func _comparable(a, b):
    x := _base(a)
    y := _base(b)
    if (x in NUMERIC) and (y in NUMERIC):
        return true
    if x == y:
        return true
    return false

func _is_raise(s):
    return s.kind == "ExprStmt" and s.expr.kind == "Call" and s.expr.callee.kind == "Name" and s.expr.callee.name == "raise"

# Vérifie un programme ; DiagnosticBag.
func check(program, file="<source>", source=null, warnings=true):
    return TypeChecker(file, source, warnings).run(program)

# Analyse + vérification d'un texte ; les erreurs de syntaxe deviennent des diagnostics.
func check_source(source, file="<source>", warnings=true):
    r := _ps.try_parse(source, file)
    if r[0] == null:
        return r[1]
    return check(r[0], file, source, warnings)

# Lève l'erreur du premier diagnostic d'erreur (s'il y en a) ; renvoie le sac sinon.
func check_or_raise(source, file="<source>"):
    bag := check_source(source, file, false)
    bag.raise_first()
    return bag

# Type inféré d'une expression isolée (texte), noms inconnus tolérés.
func infer_source(text):
    t := TypeChecker("<expression>", text, false)
    t.push("module")
    return t.expr(_ps.parse_expression(text))

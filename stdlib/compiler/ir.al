# ALEX STANDARD LIBRARY — compiler.ir
#
# Représentation intermédiaire (IR) à pile, abaissement (lowering) depuis compiler.ast, et interpréteur de
# référence. L'IR est simple et lisible — une liste d'instructions par fonction, des étiquettes symboliques
# pour les sauts — de façon à servir de terrain d'expérimentation (optimiseur, génération de code, édition des
# liens) indépendamment du bytecode natif.
#
#   use compiler.parser as ps
#   use compiler.ir as ir
#   m := ir.lower(ps.parse("func carre(x) => x * x\nprint(carre(7))\n"), "demo")
#   print(ir.format(m))              # listing : func carre(x): LOAD x / LOAD x / BINARY * / RETURN ...
#   ir.run(m)                        # exécute : affiche 49
#   vm := ir.Interpreter()
#   vm.run(m)
#   print(vm.globals_of("demo")["carre"])      # fonction IR
#   print(vm.call_function("demo", "carre", [5]))   # 25
#
# Instructions (op arg) : CONST v · LOAD nom · STORE nom · DECLARE nom · LOAD_ATTR m · STORE_ATTR m · INDEX ·
# STORE_INDEX · SLICE · BINARY op · UNARY op · JUMP L · JUMP_IF_FALSE L · JUMP_IF_TRUE L · AND_JUMP L ·
# OR_JUMP L · LABEL L · CALL n · CALL_KW [n, noms] · RETURN · POP · DUP · BUILD_LIST n · BUILD_TUPLE n ·
# BUILD_DICT n · BUILD_STR n · RANGE · MAKE_FUNC nom · ITER · FOR_ITER L · ENTER · EXIT · IMPORT [chemin, nom] ·
# IMPORT_FROM [chemin, noms] · NOP.
# Couverture : variables et constantes, affectations (noms, membres, index, composées, déstructuration),
# if / elif / else, while, for, break / continue, fonctions (défauts, *reste, imbriquées, fermetures),
# lambdas, appels (nommés, positionnels), listes / tuples / dicts / intervalles / tranches / f-strings,
# compréhensions de liste, assert, pass, imports entre modules IR. Les classes, try, match et with ne sont pas
# abaissés : IrError (« construction non prise en charge par l'IR »).
# Erreurs : IrError (abaissement), NameError, ArgumentError, TypeError (exécution) et les erreurs levées par
# le programme interprété.

from core use len, type
from collections use append, pop
use string as _s
use _native_reflect as _r
use compiler.ast as _ast

class Instr:
    func init(op, arg=null, line=0):
        self.op = op
        self.arg = arg
        self.line = line

    func __str__():
        if self.arg == null and not _takes_null(self.op):
            return self.op
        return self.op + " " + _show(self.arg)

func _takes_null(op):
    return op == "CONST"

func _show(v):
    if type(v) == "str":
        return v
    if type(v) == "list":
        return "[" + _s.join(", ", [_show_const(x) for x in v]) + "]"
    return _show_const(v)

func _show_const(v):
    if v == null:
        return "null"
    if type(v) == "str":
        return "\"" + _s.replace(_s.replace(v, "\\", "\\\\"), "\"", "\\\"") + "\""
    if type(v) == "char":
        return "'" + str(v) + "'"
    if type(v) == "bool":
        if v:
            return "true"
        return "false"
    return str(v)

class IrFunction:
    func init(name, params, code=null, module="main"):
        self.name = name
        self.params = params          # liste de noms ; le dernier peut être « *reste »
        self.defaults = {}            # nom -> code (liste d'Instr) évalué à l'appel si l'argument manque
        self.code = code
        if self.code == null:
            self.code = []
        self.module = module
        self.is_lambda = false
        self.line = 0

    func emit(op, arg=null, line=0):
        append(self.code, Instr(op, arg, line))

    func size():
        return len(self.code)

    func rest_param():
        if len(self.params) > 0 and _s.starts_with(self.params[len(self.params) - 1], "*"):
            return _s.substring(self.params[len(self.params) - 1], 1, len(self.params[len(self.params) - 1]))
        return null

class IrModule:
    func init(name="main"):
        self.name = name
        self.functions = {}       # nom qualifié -> IrFunction (fonctions et lambdas)
        self.order = []
        self.main = IrFunction("<module>", [], null, name)
        self.imports = []         # chemins de modules utilisés
        self.exports = []         # noms de haut niveau

    func add_function(f):
        if not (f.name in self.functions):
            append(self.order, f.name)
        self.functions[f.name] = f
        return f

    func function_names():
        return self.order[:]

    func instruction_count():
        n := len(self.main.code)
        for k in self.order:
            n += len(self.functions[k].code)
        for k in self.order:
            for d in self.functions[k].defaults:
                n += len(self.functions[k].defaults[d])
        return n

# ---------------------------------------------------------------------------------------------------------
# Abaissement AST -> IR
# ---------------------------------------------------------------------------------------------------------

class Lowerer:
    func init(module_name="main"):
        self.mod = IrModule(module_name)
        self.fn = self.mod.main
        self.labels = 0
        self.loops = []          # [étiquette continue, étiquette break, profondeur de portée]
        self.depth = 0
        self.lambdas = 0
        self.temps = 0

    func unsupported(n, what):
        raise("IrError", str(n.line) + ":" + str(n.column) + ": construction non prise en charge par l'IR : " + what)

    func label():
        self.labels += 1
        return "L" + str(self.labels)

    func temp():
        self.temps += 1
        return "$t" + str(self.temps)

    func emit(op, arg=null, n=null):
        line := 0
        if n != null:
            line = n.line
        self.fn.emit(op, arg, line)

    func lower_program(p):
        for s in p.body:
            if s.kind == "Func" or s.kind == "Const" or s.kind == "VarDecl":
                if not (s.name in self.mod.exports):
                    append(self.mod.exports, s.name)
        # hissage : les fonctions de haut niveau sont créées avant le reste
        for s in p.body:
            if s.kind == "Func":
                self.stmt(s)
        for s in p.body:
            if s.kind != "Func":
                self.stmt(s)
        self.emit("CONST", null)
        self.emit("RETURN")
        return self.mod

    func block(stmts):
        self.emit("ENTER")
        self.depth += 1
        for s in stmts:
            if s.kind == "Func":
                self.stmt(s)
        for s in stmts:
            if s.kind != "Func":
                self.stmt(s)
        self.depth -= 1
        self.emit("EXIT")

    func stmt(s):
        k := s.kind
        if k == "ExprStmt":
            self.expr(s.expr)
            self.emit("POP", null, s)
        elif k == "VarDecl" or k == "Const":
            if s.value == null:
                self.emit("CONST", null, s)
            else:
                self.expr(s.value)
            self.emit("DECLARE", s.name, s)
        elif k == "Assign":
            self.assign(s.target, () => self.expr(s.value), s)
        elif k == "CompoundAssign":
            self.assign(s.target, () => self.compound(s), s)
        elif k == "Destructure":
            t := self.temp()
            self.expr(s.value)
            self.emit("DECLARE", t, s)
            i := 0
            star := -1
            while i < len(s.targets):
                if s.targets[i].star:
                    star = i
                i += 1
            i = 0
            n := len(s.targets)
            while i < n:
                tg := s.targets[i]
                idx := i
                load := null
                if star >= 0 and i == star:
                    load = () => self.slice_of(t, idx, idx - n + 1, s)
                elif star >= 0 and i > star:
                    load = () => self.index_of(t, idx - n, s)
                else:
                    load = () => self.index_of(t, idx, s)
                if s.declare:
                    load()
                    self.emit("DECLARE", tg.expr.name, s)
                else:
                    self.assign(tg.expr, load, s)
                i += 1
        elif k == "If":
            done := self.label()
            nxt := self.label()
            self.expr(s.cond)
            self.emit("JUMP_IF_FALSE", nxt, s)
            self.block(s.then_body)
            self.emit("JUMP", done)
            self.emit("LABEL", nxt)
            for e in s.elifs:
                nxt = self.label()
                self.expr(e.cond)
                self.emit("JUMP_IF_FALSE", nxt, e)
                self.block(e.body)
                self.emit("JUMP", done)
                self.emit("LABEL", nxt)
            if s.else_body != null:
                self.block(s.else_body)
            self.emit("LABEL", done)
        elif k == "While":
            top := self.label()
            done := self.label()
            brk := self.label()
            self.emit("LABEL", top)
            self.expr(s.cond)
            self.emit("JUMP_IF_FALSE", done, s)
            append(self.loops, [top, brk, self.depth])
            self.block(s.body)
            pop(self.loops)
            self.emit("JUMP", top)
            self.emit("LABEL", done)
            if s.else_body != null:
                self.block(s.else_body)
            self.emit("LABEL", brk)
        elif k == "For":
            if len(s.vars) != 1 or s.vars[0].star:
                self.unsupported(s, "for à plusieurs variables")
            top := self.label()
            done := self.label()
            brk := self.label()
            self.expr(s.iter)
            self.emit("ITER", null, s)
            self.emit("LABEL", top)
            self.emit("FOR_ITER", done, s)
            self.emit("ENTER")
            self.depth += 1
            self.emit("DECLARE", s.vars[0].expr.name, s)
            append(self.loops, [top, brk, self.depth - 1])
            for b in s.body:
                if b.kind == "Func":
                    self.stmt(b)
            for b in s.body:
                if b.kind != "Func":
                    self.stmt(b)
            pop(self.loops)
            self.depth -= 1
            self.emit("EXIT")
            self.emit("JUMP", top)
            self.emit("LABEL", done)
            if s.else_body != null:
                self.block(s.else_body)
            self.emit("JUMP", brk + "x")
            self.emit("LABEL", brk)
            self.emit("POP")
            self.emit("LABEL", brk + "x")
        elif k == "Break" or k == "Continue":
            if len(self.loops) == 0:
                self.unsupported(s, _s.lower(k) + " hors d'une boucle")
            lp := self.loops[len(self.loops) - 1]
            d := self.depth
            while d > lp[2]:
                self.emit("EXIT")
                d -= 1
            if k == "Break":
                self.emit("JUMP", lp[1], s)
            else:
                self.emit("JUMP", lp[0], s)
        elif k == "Return":
            if s.value == null:
                self.emit("CONST", null, s)
            else:
                self.expr(s.value)
            self.emit("RETURN", null, s)
        elif k == "Func":
            f := self.function(s.name, s.params, s.body, s, false)
            # décorateurs : f = d1(d2(f))
            for d in s.decorators:
                self.expr(d)
            self.emit("MAKE_FUNC", f.name, s)
            for d in s.decorators:
                self.emit("CALL", 1, s)
            self.emit("DECLARE", s.name, s)
        elif k == "Pass":
            self.emit("NOP", null, s)
        elif k == "Assert":
            ok := self.label()
            self.expr(s.cond)
            self.emit("JUMP_IF_TRUE", ok, s)
            self.emit("LOAD", "raise", s)
            self.emit("CONST", "AssertionError")
            if s.message == null:
                self.emit("CONST", "assertion échouée")
            else:
                self.expr(s.message)
            self.emit("CALL", 2, s)
            self.emit("POP")
            self.emit("LABEL", ok)
        elif k == "Use":
            alias := s.alias
            if alias == null:
                alias = s.path[len(s.path) - 1]
            p := _s.join(".", s.path)
            append(self.mod.imports, p)
            self.emit("IMPORT", [p, alias], s)
        elif k == "FromUse":
            p := _s.join(".", s.path)
            append(self.mod.imports, p)
            self.emit("IMPORT_FROM", [p, s.names], s)
        elif k == "Class" or k == "Struct" or k == "Interface" or k == "Enum":
            self.unsupported(s, "déclaration " + _s.lower(k))
        elif k == "Try":
            self.unsupported(s, "try / catch")
        elif k == "Match":
            self.unsupported(s, "match")
        elif k == "With":
            self.unsupported(s, "with")
        else:
            self.unsupported(s, k)

    func index_of(t, i, n):
        self.emit("LOAD", t, n)
        self.emit("CONST", i)
        self.emit("INDEX", null, n)

    func slice_of(t, a, b, n):
        self.emit("LOAD", t, n)
        self.emit("CONST", a)
        if b >= 0:
            self.emit("CONST", null)
        else:
            self.emit("CONST", b)
        self.emit("CONST", null)
        self.emit("SLICE", null, n)

    func compound(s):
        self.expr(s.target)
        self.expr(s.value)
        self.emit("BINARY", s.op, s)

    func assign(target, value_fn, n):
        k := target.kind
        if k == "Name":
            value_fn()
            self.emit("STORE", target.name, n)
        elif k == "Member":
            self.expr(target.object)
            value_fn()
            self.emit("STORE_ATTR", target.member, n)
        elif k == "Index":
            self.expr(target.object)
            self.expr(target.index)
            value_fn()
            self.emit("STORE_INDEX", null, n)
        else:
            self.unsupported(n, "cible d'affectation " + k)

    func function(name, params, body, n, is_lambda):
        qual := name
        if is_lambda:
            self.lambdas += 1
            qual = "<lambda" + str(self.lambdas) + ">"
        elif self.fn != self.mod.main:
            qual = self.fn.name + "." + name
        pnames := []
        for p in params:
            if p.rest:
                append(pnames, "*" + p.name)
            else:
                append(pnames, p.name)
        f := IrFunction(qual, pnames, null, self.mod.name)
        f.is_lambda = is_lambda
        f.line = n.line
        saved_fn := self.fn
        saved_loops := self.loops
        saved_depth := self.depth
        self.loops = []
        self.depth = 0
        for p in params:
            if p.default != null:
                self.fn = IrFunction("<défaut>", [], null, self.mod.name)
                self.expr(p.default)
                self.emit("RETURN")
                f.defaults[p.name] = self.fn.code
        self.fn = f
        self.mod.add_function(f)
        if is_lambda:
            self.expr(body)
            self.emit("RETURN", null, n)
        else:
            for s in body:
                if s.kind == "Func":
                    self.stmt(s)
            for s in body:
                if s.kind != "Func":
                    self.stmt(s)
            self.emit("CONST", null)
            self.emit("RETURN")
        self.fn = saved_fn
        self.loops = saved_loops
        self.depth = saved_depth
        return f

    func expr(e):
        k := e.kind
        if k == "Literal":
            self.emit("CONST", e.value, e)
        elif k == "Name":
            self.emit("LOAD", e.name, e)
        elif k == "Binary":
            if e.op == "and" or e.op == "or":
                end := self.label()
                self.expr(e.left)
                if e.op == "and":
                    self.emit("AND_JUMP", end, e)
                else:
                    self.emit("OR_JUMP", end, e)
                self.expr(e.right)
                self.emit("LABEL", end)
            else:
                self.expr(e.left)
                self.expr(e.right)
                self.emit("BINARY", e.op, e)
        elif k == "Unary":
            if e.op == "await":
                self.unsupported(e, "await")
            self.expr(e.operand)
            self.emit("UNARY", e.op, e)
        elif k == "Ternary":
            other := self.label()
            end := self.label()
            self.expr(e.cond)
            self.emit("JUMP_IF_FALSE", other, e)
            self.expr(e.then_expr)
            self.emit("JUMP", end)
            self.emit("LABEL", other)
            self.expr(e.else_expr)
            self.emit("LABEL", end)
        elif k == "Call":
            self.expr(e.callee)
            names := []
            for a in e.args:
                if a.value.kind == "Spread":
                    self.unsupported(e, "appel avec *étalement")
                self.expr(a.value)
                if a.name != null:
                    append(names, a.name)
                elif len(names) > 0:
                    self.unsupported(e, "argument positionnel après un argument nommé")
            if len(names) > 0:
                self.emit("CALL_KW", [len(e.args), names], e)
            else:
                self.emit("CALL", len(e.args), e)
        elif k == "Member":
            self.expr(e.object)
            self.emit("LOAD_ATTR", e.member, e)
        elif k == "Index":
            self.expr(e.object)
            self.expr(e.index)
            self.emit("INDEX", null, e)
        elif k == "Slice":
            self.expr(e.object)
            for part in [e.start, e.stop, e.step]:
                if part == null:
                    self.emit("CONST", null)
                else:
                    self.expr(part)
            self.emit("SLICE", null, e)
        elif k == "ListLit" or k == "TupleLit":
            for x in e.elements:
                if x.kind == "Spread":
                    self.unsupported(e, "*étalement dans un littéral")
                self.expr(x)
            if k == "ListLit":
                self.emit("BUILD_LIST", len(e.elements), e)
            else:
                self.emit("BUILD_TUPLE", len(e.elements), e)
        elif k == "DictLit":
            for en in e.entries:
                if en.kind != "DictEntry":
                    self.unsupported(e, "**étalement dans un dict")
                self.expr(en.key)
                self.expr(en.value)
            self.emit("BUILD_DICT", len(e.entries), e)
        elif k == "Range":
            self.expr(e.start)
            self.expr(e.end)
            self.emit("RANGE", null, e)
        elif k == "FString":
            n := 0
            for p in e.parts:
                if _ast.is_node(p):
                    self.expr(p)
                else:
                    self.emit("CONST", p)
                n += 1
            self.emit("BUILD_STR", n, e)
        elif k == "Lambda":
            f := self.function("<lambda>", e.params, e.body, e, true)
            self.emit("MAKE_FUNC", f.name, e)
        elif k == "Comprehension":
            if e.comp != "list":
                self.unsupported(e, "compréhension " + e.comp)
            acc := self.temp()
            self.emit("ENTER")
            self.emit("BUILD_LIST", 0, e)
            self.emit("DECLARE", acc, e)
            self.comp(e, 0, acc)
            self.emit("LOAD", acc)
            self.emit("EXIT")
        elif k == "Propagate":
            self.unsupported(e, "propagation '?'")
        else:
            self.unsupported(e, "expression " + k)

    func comp(e, i, acc):
        if i >= len(e.clauses):
            self.emit("LOAD", "__list_append")
            self.emit("LOAD", acc)
            self.expr(e.element)
            self.emit("CALL", 2, e)
            self.emit("POP")
            return
        c := e.clauses[i]
        if c.kind == "CompIf":
            skip := self.label()
            self.expr(c.cond)
            self.emit("JUMP_IF_FALSE", skip, c)
            self.comp(e, i + 1, acc)
            self.emit("LABEL", skip)
        else:
            top := self.label()
            done := self.label()
            self.expr(c.iter)
            self.emit("ITER", null, c)
            self.emit("LABEL", top)
            self.emit("FOR_ITER", done, c)
            self.emit("ENTER")
            self.emit("DECLARE", c.var, c)
            self.comp(e, i + 1, acc)
            self.emit("EXIT")
            self.emit("JUMP", top)
            self.emit("LABEL", done)

# Abaisse un programme (nœud Program) ; IrModule.
func lower(program, module_name="main"):
    return Lowerer(module_name).lower_program(program)

# ---------------------------------------------------------------------------------------------------------
# Listing, sérialisation
# ---------------------------------------------------------------------------------------------------------

func format_code(code, indent="    "):
    lines := []
    i := 0
    for ins in code:
        if ins.op == "LABEL":
            append(lines, ins.arg + ":")
        else:
            append(lines, indent + _pad(str(i), 4) + str(ins))
        i += 1
    return lines

func _pad(s, n):
    out := s
    while len(out) < n:
        out += " "
    return out

func format(m):
    out := ["; module " + m.name]
    for k in m.order:
        f := m.functions[k]
        append(out, "func " + f.name + "(" + _s.join(", ", f.params) + "):")
        for d in f.defaults:
            append(out, "  défaut " + d + ":")
            for l in format_code(f.defaults[d], "      "):
                append(out, l)
        for l in format_code(f.code):
            append(out, l)
    append(out, "<module>:")
    for l in format_code(m.main.code):
        append(out, l)
    return _s.join("\n", out)

func _code_dict(code):
    return [[i.op, i.arg, i.line] for i in code]

func _code_from(lst):
    return [Instr(x[0], x[1], x[2]) for x in lst]

func _fn_dict(f):
    d := {}
    for k in f.defaults:
        d[k] = _code_dict(f.defaults[k])
    return {"name": f.name, "params": f.params, "defaults": d, "code": _code_dict(f.code), "lambda": f.is_lambda, "line": f.line}

func _fn_from(d, module):
    f := IrFunction(d["name"], d["params"], _code_from(d["code"]), module)
    for k in d["defaults"]:
        f.defaults[k] = _code_from(d["defaults"][k])
    f.is_lambda = d["lambda"]
    f.line = d["line"]
    return f

func to_dict(m):
    return {"format": "alex-ir", "version": 1, "name": m.name, "imports": m.imports, "exports": m.exports,
            "main": _code_dict(m.main.code), "functions": [_fn_dict(m.functions[k]) for k in m.order]}

func from_dict(d):
    if not ("format" in d) or d["format"] != "alex-ir":
        raise("ValueError", "ir.from_dict : ce n'est pas un module IR ALEX")
    m := IrModule(d["name"])
    m.imports = d["imports"]
    m.exports = d["exports"]
    m.main = IrFunction("<module>", [], _code_from(d["main"]), m.name)
    for fd in d["functions"]:
        m.add_function(_fn_from(fd, m.name))
    return m

# ---------------------------------------------------------------------------------------------------------
# Interpréteur
# ---------------------------------------------------------------------------------------------------------

class Env:
    func init(parent=null):
        self.parent = parent
        self.vars = {}

    func find(name):
        e := self
        while e != null:
            if name in e.vars:
                return e
            e = e.parent
        return null

class Closure:
    func init(fn, env, interp):
        self.fn = fn
        self.env = env
        self.interp = interp

    func __call__(*args):
        return self.interp.invoke(self, args, null)

    func __str__():
        return "<fonction IR " + self.fn.name + ">"

class ModuleObject:
    func init(name, env):
        self.name = name
        self.env = env

class _Iter:
    func init(items):
        self.items = items
        self.i = 0

func _items(v):
    if type(v) == "dict":
        return [k for k in v]
    return [x for x in v]

func _labels(code):
    out := {}
    i := 0
    for ins in code:
        if ins.op == "LABEL":
            out[ins.arg] = i
        i += 1
    return out

func _truthy(v):
    if v == null or v == false:
        return false
    t := type(v)
    if t == "int" or t == "float":
        return v != 0
    if t == "str" or t == "list" or t == "dict" or t == "tuple":
        return len(v) > 0
    return true

func binary_op(op, a, b):
    if op == "+":
        return a + b
    if op == "-":
        return a - b
    if op == "*":
        return a * b
    if op == "/":
        return a / b
    if op == "//":
        return a // b
    if op == "%":
        return a % b
    if op == "**":
        return a ** b
    if op == "==":
        return a == b
    if op == "!=":
        return a != b
    if op == "<":
        return a < b
    if op == "<=":
        return a <= b
    if op == ">":
        return a > b
    if op == ">=":
        return a >= b
    if op == "in":
        return a in b
    if op == "not in":
        return not (a in b)
    if op == "&":
        return a & b
    if op == "|":
        return a | b
    if op == "^":
        return a ^ b
    if op == "<<":
        return a << b
    if op == ">>":
        return a >> b
    raise("IrError", "opérateur binaire inconnu '" + str(op) + "'")

func unary_op(op, v):
    if op == "-":
        return -v
    if op == "+":
        return +v
    if op == "not":
        return not _truthy(v)
    if op == "~":
        return ~v
    raise("IrError", "opérateur unaire inconnu '" + str(op) + "'")

func _std_builtins():
    use_print := (*a) => print(_s.join(" ", [str(x) for x in a]))
    return {"print": use_print, "str": (x) => str(x), "len": (x) => len(x), "type": (x) => type(x),
            "raise": (t, m) => raise(t, m), "__list_append": (l, v) => append(l, v),
            "append": (l, v) => append(l, v), "pop": (l) => pop(l), "abs": (x) => x if x >= 0 else -x,
            "min": (a, b) => a if a <= b else b, "max": (a, b) => a if a >= b else b,
            "range": (a, b) => [i for i in a..b], "isinstance": (v, t) => type(v) == t}

class Interpreter:
    func init(builtins=null, max_steps=10000000):
        self.builtins = _std_builtins()
        if builtins != null:
            for k in builtins:
                self.builtins[k] = builtins[k]
        self.modules = {}         # nom -> IrModule disponible pour IMPORT
        self.loaded = {}          # nom -> ModuleObject (après exécution)
        self.max_steps = max_steps
        self.steps = 0
        self.output = null        # liste : capture de print si non null
        self.label_cache = {}

    func capture():
        self.output = []
        self.builtins["print"] = (*a) => append(self.output, _s.join(" ", [str(x) for x in a]))
        return self

    func register(m):
        self.modules[m.name] = m
        return self

    func run(m):
        self.register(m)
        return self.load(m.name)

    func load(name):
        if name in self.loaded:
            return self.loaded[name]
        if not (name in self.modules):
            raise("ImportError", "module IR '" + name + "' introuvable")
        m := self.modules[name]
        genv := Env(null)
        mo := ModuleObject(name, genv)
        self.loaded[name] = mo
        self.exec_code(m.main, genv)
        return mo

    func globals_of(name):
        return self.load(name).env.vars

    func call_function(module, fname, args):
        g := self.globals_of(module)
        if not (fname in g):
            raise("NameError", "fonction '" + fname + "' absente du module " + module)
        return self.call_value(g[fname], args, null)

    func call_value(f, args, kwnames):
        if _r.is_instance(f) and _r.type_name(f) == _r.type_name(_CLOSURE_PROBE):
            return self.invoke(f, args, kwnames)
        if kwnames != null and len(kwnames) > 0:
            raise("ArgumentError", "arguments nommés non pris en charge pour une fonction hôte")
        if type(f) != "function":
            raise("TypeError", "valeur de type '" + type(f) + "' non appelable")
        return _apply(f, args)

    func invoke(clo, args, kwnames):
        fn := clo.fn
        env := Env(clo.env)
        nkw := 0
        if kwnames != null:
            nkw = len(kwnames)
        npos := len(args) - nkw
        rest := fn.rest_param()
        fixed := fn.params
        if rest != null:
            fixed = fn.params[:len(fn.params) - 1]
        if npos > len(fixed) and rest == null:
            raise("ArgumentError", fn.name + " : trop d'arguments (" + str(npos) + " pour " + str(len(fixed)) + ")")
        i := 0
        while i < len(fixed) and i < npos:
            env.vars[fixed[i]] = args[i]
            i += 1
        if rest != null:
            extra := []
            while i < npos:
                append(extra, args[i])
                i += 1
            env.vars[rest] = extra
        k := 0
        while k < nkw:
            nm := kwnames[k]
            if not (nm in fixed):
                raise("ArgumentError", fn.name + " : argument nommé inconnu '" + nm + "'")
            if nm in env.vars:
                raise("ArgumentError", fn.name + " : argument '" + nm + "' fourni deux fois")
            env.vars[nm] = args[npos + k]
            k += 1
        for p in fixed:
            if not (p in env.vars):
                if p in fn.defaults:
                    dfn := IrFunction("<défaut>", [], fn.defaults[p], fn.module)
                    env.vars[p] = self.exec_code(dfn, env)
                else:
                    raise("ArgumentError", fn.name + " : argument manquant '" + p + "'")
        return self.exec_code(fn, env)

    func find_function(module, name):
        m := self.modules[module]
        return m.functions[name]

    func lookup(env, name):
        e := env.find(name)
        if e != null:
            return e.vars[name]
        if name in self.builtins:
            return self.builtins[name]
        raise("NameError", "nom '" + name + "' non défini")

    func exec_code(fn, env0):
        code := fn.code
        key := fn.module + "::" + fn.name
        labels := null
        if fn.name == "<défaut>":
            labels = _labels(code)
        else:
            if not (key in self.label_cache):
                self.label_cache[key] = _labels(code)
            labels = self.label_cache[key]
        stack := []
        env := env0
        pc := 0
        n := len(code)
        while pc < n:
            ins := code[pc]
            pc += 1
            self.steps += 1
            if self.steps > self.max_steps:
                raise("IrError", "nombre maximal d'instructions dépassé (" + str(self.max_steps) + ")")
            op := ins.op
            if op == "CONST":
                append(stack, ins.arg)
            elif op == "LOAD":
                append(stack, self.lookup(env, ins.arg))
            elif op == "DECLARE":
                env.vars[ins.arg] = pop(stack)
            elif op == "STORE":
                e := env.find(ins.arg)
                if e == null:
                    raise("NameError", "affectation de '" + ins.arg + "' non déclaré")
                e.vars[ins.arg] = pop(stack)
            elif op == "POP":
                pop(stack)
            elif op == "DUP":
                append(stack, stack[len(stack) - 1])
            elif op == "BINARY":
                b := pop(stack)
                a := pop(stack)
                append(stack, binary_op(ins.arg, a, b))
            elif op == "UNARY":
                append(stack, unary_op(ins.arg, pop(stack)))
            elif op == "JUMP":
                pc = labels[ins.arg]
            elif op == "JUMP_IF_FALSE":
                if not _truthy(pop(stack)):
                    pc = labels[ins.arg]
            elif op == "JUMP_IF_TRUE":
                if _truthy(pop(stack)):
                    pc = labels[ins.arg]
            elif op == "AND_JUMP":
                if not _truthy(stack[len(stack) - 1]):
                    pc = labels[ins.arg]
                else:
                    pop(stack)
            elif op == "OR_JUMP":
                if _truthy(stack[len(stack) - 1]):
                    pc = labels[ins.arg]
                else:
                    pop(stack)
            elif op == "LABEL" or op == "NOP":
                continue
            elif op == "CALL" or op == "CALL_KW":
                argc := ins.arg
                names := null
                if op == "CALL_KW":
                    argc = ins.arg[0]
                    names = ins.arg[1]
                args := stack[len(stack) - argc:]
                stack = stack[:len(stack) - argc]
                f := pop(stack)
                append(stack, self.call_value(f, args, names))
            elif op == "RETURN":
                return pop(stack)
            elif op == "BUILD_LIST" or op == "BUILD_TUPLE":
                k := ins.arg
                items := stack[len(stack) - k:]
                stack = stack[:len(stack) - k]
                if op == "BUILD_TUPLE":
                    append(stack, _tuple(items))
                else:
                    append(stack, items)
            elif op == "BUILD_DICT":
                k := ins.arg * 2
                items := stack[len(stack) - k:]
                stack = stack[:len(stack) - k]
                d := {}
                i := 0
                while i < k:
                    d[items[i]] = items[i + 1]
                    i += 2
                append(stack, d)
            elif op == "BUILD_STR":
                k := ins.arg
                items := stack[len(stack) - k:]
                stack = stack[:len(stack) - k]
                append(stack, _s.join("", [str(x) for x in items]))
            elif op == "RANGE":
                b := pop(stack)
                a := pop(stack)
                append(stack, [i for i in a..b])
            elif op == "INDEX":
                i := pop(stack)
                o := pop(stack)
                append(stack, o[i])
            elif op == "STORE_INDEX":
                v := pop(stack)
                i := pop(stack)
                o := pop(stack)
                o[i] = v
            elif op == "SLICE":
                st := pop(stack)
                b := pop(stack)
                a := pop(stack)
                o := pop(stack)
                append(stack, _slice(o, a, b, st))
            elif op == "LOAD_ATTR":
                o := pop(stack)
                append(stack, self.get_attr(o, ins.arg))
            elif op == "STORE_ATTR":
                v := pop(stack)
                o := pop(stack)
                if _r.is_instance(o) and _r.type_name(o) == _r.type_name(_MODULE_PROBE):
                    o.env.vars[ins.arg] = v
                else:
                    _r.set_field(o, ins.arg, v)
            elif op == "MAKE_FUNC":
                f := self.modules[fn.module].functions[ins.arg]
                append(stack, Closure(f, env, self))
            elif op == "ITER":
                append(stack, _Iter(_items(pop(stack))))
            elif op == "FOR_ITER":
                it := stack[len(stack) - 1]
                if it.i < len(it.items):
                    append(stack, it.items[it.i])
                    it.i += 1
                else:
                    pop(stack)
                    pc = labels[ins.arg]
            elif op == "ENTER":
                env = Env(env)
            elif op == "EXIT":
                env = env.parent
            elif op == "IMPORT":
                mo := self.load(ins.arg[0])
                env.vars[ins.arg[1]] = mo
            elif op == "IMPORT_FROM":
                mo := self.load(ins.arg[0])
                for nm in ins.arg[1]:
                    if not (nm in mo.env.vars):
                        raise("ImportError", "'" + nm + "' n'est pas défini dans le module " + ins.arg[0])
                    env.vars[nm] = mo.env.vars[nm]
            else:
                raise("IrError", "instruction inconnue '" + op + "'")
        return null

    func get_attr(o, name):
        if _r.is_instance(o) and _r.type_name(o) == _r.type_name(_MODULE_PROBE):
            if not (name in o.env.vars):
                raise("AttributeError", "le module " + o.name + " n'a pas de membre '" + name + "'")
            return o.env.vars[name]
        if _r.is_instance(o):
            if _r.has_field(o, name):
                return _r.get_field(o, name)
            m := _r.method(o, name)
            if m != null:
                return m
        raise("AttributeError", "valeur de type '" + type(o) + "' : membre '" + name + "' inconnu")

func _tuple(items):
    n := len(items)
    if n == 2:
        return (items[0], items[1])
    if n == 3:
        return (items[0], items[1], items[2])
    if n == 4:
        return (items[0], items[1], items[2], items[3])
    return items

func _slice(o, a, b, st):
    if st != null:
        return o[a:b:st]
    if a == null and b == null:
        return o[:]
    if a == null:
        return o[:b]
    if b == null:
        return o[a:]
    return o[a:b]

func _apply(f, args):
    return f(*args)

_CLOSURE_PROBE := Closure(null, null, null)
_MODULE_PROBE := ModuleObject("", null)

# Exécute un module IR (et les modules IR qu'il importe, s'ils sont fournis) ; renvoie l'interpréteur.
func run(m, others=null, builtins=null):
    vm := Interpreter(builtins)
    if others != null:
        for o in others:
            vm.register(o)
    vm.run(m)
    return vm

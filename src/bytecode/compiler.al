# ALEX — bytecode.compiler
#
# Compilateur AST -> bytecode .albc écrit en ALEX : portage fidèle de src/Compiler.cpp (et de
# src/TypeIndex.cpp). À partir de l'arbre de parser et des options de module (qualification des
# noms d'un module dépendant, imports réels résolus, signatures des exports importés), il produit un
# bytecode.format.BcModule identique, octet pour octet, à celui du compilateur de référence : mêmes
# fonctions, mêmes constantes dans le même ordre, mêmes instructions, mêmes tables de lignes et de noms locaux.
#
# Couvre : expressions (littéraux, f-strings, opérateurs, court-circuits, in / not in, conditionnelles,
# compréhensions, spread *x / **d), appels (intrinsèques print/input/str/raise/isinstance/__len/__slice/
# __list_*/__dict_remove_key/__del_item, arguments nommés résolus statiquement, valeurs par défaut en prologue),
# variables locales / globales / qualifiées, fermetures (cellules, upvalues, fonctions hissées, lambdas),
# boucles (intervalle a..b, itération par index + IndexError, dict -> clés, else), break / continue / return
# à travers try / finally, exceptions typées, match (littéraux, plages, variantes d'enum, listes, tuples,
# gardes), struct / class (héritage, interfaces, champs par défaut, super), enum, async / await, annotations
# de type vérifiées (CHECK_TYPE), entiers dimensionnés (débordement vérifié).
#
#   use parser as bp
#   use bytecode.compiler as bc
#   prog := bp.parse_file("prog.al")
#   m := bc.compile(prog)                          # BcModule (fichier d'entrée)
#   opts := bc.CompileOptions()
#   opts.self_qualifier = "$mod0123456789abcdef"   # module dépendant
#   m2 := bc.compile(prog, opts)
#
# Erreurs : CompileError (construction non compilable, argument nommé inconnu, classe de base inconnue...).

from core use len, type
from collections use append
use string as _s
use os as _os
use bytecode.format as bf
use ast as _a
from ast use Node

# Producteur et canal : ceux de la chaîne ALEX qui exécute ce compilateur (comme version::producer() en C++).
func _toolchain():
    b := _os.alex_build()
    return ["alex " + b["full"], b["channel"] == "beta"]

# ---------------------------------------------------------------------------------------------- signatures
class ParamSig:
    func init(name, has_default=false, type=""):
        self.name = name
        self.has_default = has_default
        self.type = type

class FunctionSig:
    func init(params=null, ret=""):
        self.params = params if params != null else []
        self.ret = ret

class StructSig:
    func init():
        self.has_ctor = false
        self.ctor_params = []
        self.is_class = false
        self.has_field_init = false

class EnumSig:
    func init():
        self.variants = {}       # variante -> noms des champs

class InterfaceSig:
    func init(methods=null):
        self.methods = methods if methods != null else []

class ModuleSignatures:
    func init():
        self.functions = {}
        self.structs = {}
        self.enums = {}
        self.interfaces = {}

class NamespaceImport:
    func init(qualifier, exports, sigs):
        self.qualifier = qualifier
        self.exports = exports   # dict nom -> true
        self.sigs = sigs

class CompileOptions:
    func init():
        self.self_qualifier = ""
        self.source_path = ""
        self.imported_names = {}
        self.imported_functions = {}
        self.imported_structs = {}
        self.imported_enums = {}
        self.imported_interfaces = {}
        self.namespace_imports = {}
        self.sized_results = null    # uid -> type dimensionné (semantic.types), ou null

# ---------------------------------------------------------------------------------------------- TypeIndex
class TypeDecl:
    func init(kind, name, node, body):
        self.kind = kind          # Struct, Class, Interface
        self.name = name
        self.node = node
        self.body = body
        self.base = null
        self.interfaces = []

    func own_methods():
        if self.body == null:
            return []
        return [s for s in self.body.statements if s.kind == "FunctionDecl"]

    func own_method(name):
        for m in self.own_methods():
            if m.name == name:
                return m
        return null

    func own_fields():
        if self.body == null:
            return []
        return [s for s in self.body.statements if s.kind == "VariableDecl"]

class TypeIndex:
    func init(statements):
        self.by_name = {}
        self.ordered = []
        for s in statements:
            d := null
            if s.kind == "StructDecl":
                d = TypeDecl("Struct", s.name, s, s.body)
            elif s.kind == "ClassDecl":
                d = TypeDecl("Class", s.name, s, s.body)
                d.base = s.base_class
                d.interfaces = s.interfaces
            elif s.kind == "InterfaceDecl":
                d = TypeDecl("Interface", s.name, s, s.body)
            else:
                continue
            if not (d.name in self.by_name):
                self.by_name[d.name] = d
                append(self.ordered, d)

    func find(name):
        if name in self.by_name:
            return self.by_name[name]
        return null

    # [types de la chaîne, cyclique, base externe]
    func chain(t):
        types := []
        seen := {}
        cur := t
        while cur != null:
            if cur.name in seen:
                return [types, true, null]
            seen[cur.name] = true
            append(types, cur)
            if cur.base == null:
                return [types, false, null]
            nxt := self.find(cur.base)
            if nxt == null or nxt.kind != "Class":
                return [types, false, cur.base if nxt == null else null]
            cur = nxt
        return [types, false, null]

    # [méthode ou null, base externe]
    func find_method(t, name):
        c := self.chain(t)
        for x in c[0]:
            m := x.own_method(name)
            if m != null:
                return [m, null]
        return [null, c[2]]

    func has_local_field_init(t):
        for x in self.chain(t)[0]:
            if len(x.own_fields()) > 0:
                return true
        return false

# ---------------------------------------------------------------------------------------------- analyse des captures
class CaptureScanner:
    func init(out):
        self.out = out

    func expr(e, inner):
        if e == null:
            return
        k := e.kind
        if k == "Identifier":
            if inner:
                self.out[e.name] = true
                if e.name == "super":
                    self.out["self"] = true
        elif k == "ListLiteral" or k == "TupleLiteral":
            for x in e.elements:
                self.expr(x, inner)
        elif k == "DictLiteral":
            for kv in e.entries:
                self.expr(kv.key, inner)
                self.expr(kv.value, inner)
        elif k == "FStringLiteral":
            for p in e.parts:
                if p.is_expr:
                    self.expr(p.expr, inner)
        elif k == "BinaryExpr":
            self.expr(e.left, inner)
            self.expr(e.right, inner)
        elif k == "UnaryExpr" or k == "ErrorPropagationExpr":
            self.expr(e.operand, inner)
        elif k == "ConditionalExpr":
            self.expr(e.condition, inner)
            self.expr(e.then_expr, inner)
            self.expr(e.else_expr, inner)
        elif k == "RangeExpr":
            self.expr(e.start, inner)
            self.expr(e.end, inner)
        elif k == "CallExpr":
            self.expr(e.callee, inner)
            for a in e.arguments:
                self.expr(a.value, inner)
        elif k == "IndexExpr":
            self.expr(e.object, inner)
            self.expr(e.index, inner)
        elif k == "MemberExpr":
            self.expr(e.object, inner)
        elif k == "LambdaExpr":
            self.function(e.function)
        elif k == "ComprehensionExpr":
            self.expr(e.element, inner)
            self.expr(e.key, inner)
            self.expr(e.value, inner)
            for c in e.clauses:
                self.expr(c.expr, inner)

    func stmt(s, inner):
        if s == null:
            return
        k := s.kind
        if k == "VariableDecl" or k == "ConstDecl":
            self.expr(s.value, inner)
        elif k == "Assignment" or k == "CompoundAssignment":
            self.expr(s.target, inner)
            self.expr(s.value, inner)
        elif k == "ExpressionStmt":
            self.expr(s.expr, inner)
        elif k == "IfStmt":
            self.expr(s.condition, inner)
            self.block(s.then_block, inner)
            for c in s.elif_clauses:
                self.expr(c.condition, inner)
                self.block(c.body, inner)
            self.block(s.else_block, inner)
        elif k == "WhileStmt":
            self.expr(s.condition, inner)
            self.block(s.body, inner)
            self.block(s.else_body, inner)
        elif k == "ForStmt":
            self.expr(s.iterable, inner)
            self.block(s.body, inner)
            self.block(s.else_body, inner)
        elif k == "ReturnStmt":
            self.expr(s.value, inner)
        elif k == "TryStmt":
            self.block(s.try_block, inner)
            for c in s.catch_clauses:
                self.block(c.body, inner)
            self.block(s.finally_block, inner)
        elif k == "MatchStmt":
            self.expr(s.subject, inner)
            for c in s.cases:
                self.expr(c.guard, inner)
                self.block(c.body, inner)
        elif k == "FunctionDecl":
            self.function(s)

    func block(b, inner):
        if b == null:
            return
        for s in b.statements:
            self.stmt(s, inner)

    func function(fn):
        for p in fn.params:
            self.expr(p.default_value, true)
        self.block(fn.body, true)

# ---------------------------------------------------------------------------------------------- contextes
class Var:
    func init(slot=0, boxed=false, declared=true, type_desc=""):
        self.slot = slot
        self.boxed = boxed
        self.declared = declared
        self.type_desc = type_desc

class Ref:
    func init(is_global, index, boxed=false, upvalue=false):
        self.is_global = is_global
        self.index = index
        self.boxed = boxed
        self.upvalue = upvalue

class LoopCtx:
    func init(try_depth):
        self.try_depth_at_entry = try_depth
        self.break_fixups = []
        self.continue_fixups = []

class FuncCtx:
    func init():
        self.instrs = []
        self.byte_len = 0
        self.scopes = []
        self.next_local = 0
        self.local_names = []
        self.outermost_global = false
        self.loops = []
        self.try_depth = 0
        self.parent = null
        self.hoisted = false
        self.upvalues = []          # [nom, depuis_local_parent, index]
        self.upvalue_index = {}
        self.captured = {}
        self.cur_line = 0
        self.lines = []
        self.finally_stack = []     # [bloc, try_depth_dehors, profondeur_boucles]
        self.ret_desc = ""
        self.ret_what = ""

class StructInfo:
    func init():
        self.has_ctor = false
        self.ctor_decl = null
        self.sig_params = []
        self.runtime_name = ""
        self.is_class = false
        self.needs_field_init = false

const BUILTIN_TYPES := {"any": true, "int": true, "float": true, "bool": true, "str": true, "char": true,
    "byte": true, "null": true, "list": true, "dict": true, "tuple": true, "func": true, "future": true, "i8": true,
    "i16": true, "i32": true, "u8": true, "u16": true, "u32": true, "u64": true, "f32": true}

const BINOP := {"Add": bf.ADD, "Sub": bf.SUB, "Mul": bf.MUL, "Div": bf.DIV, "FloorDiv": bf.FLOORDIV,
    "Mod": bf.MOD, "Pow": bf.POW, "Eq": bf.EQ, "Ne": bf.NE, "Lt": bf.LT, "Le": bf.LE, "Gt": bf.GT, "Ge": bf.GE,
    "BitAnd": bf.BAND, "BitOr": bf.BOR, "BitXor": bf.BXOR, "Shl": bf.SHL, "Shr": bf.SHR}

func _cerr(message):
    raise("CompileError", message)

func _is_spread_arg(a):
    return a.name == null and a.value.kind == "UnaryExpr" and a.value.op == "Spread"

func _has_spread_element(els):
    for e in els:
        if e.kind == "UnaryExpr" and e.op == "Spread":
            return true
    return false

func _is_dict_spread(kv):
    return kv.key.kind == "UnaryExpr" and kv.key.op == "DictSpread"

func _has_named(args):
    for a in args:
        if a.name != null:
            return true
    return false

func literal_constant(kind, value):
    if kind == "Integer":
        return bf.const_int(value)
    if kind == "Float":
        return bf.const_float(value)
    if kind == "Boolean":
        return bf.const_bool(value)
    if kind == "Null":
        return bf.const_null()
    if kind == "Char":
        return bf.const_char(value)
    if kind == "String":
        return bf.const_str(value)
    _cerr("littéral non pris en charge")

# ---------------------------------------------------------------------------------------------- compilateur
class Compiler:
    func init(options):
        self.options = options
        self.m = bf.BcModule()
        self.closure_serial = 0
        self.functions = []
        self.code = []
        self.next_function_id = 0
        self.own_names = {}
        self.structs = {}
        self.enums = {}           # nom -> [nom runtime, {variante: champs}]
        self.types = null
        self.interfaces = {}
        self.global_types = {}
        self.sized_pending = -1
        self.current_class = null
        self.named_functions = {}

    # ------------------------------------------------------------------ noms
    func global_name(name):
        if name in self.options.imported_names:
            return self.options.imported_names[name]
        q := self.options.self_qualifier
        if q != "" and (name == "$entry" or name in self.own_names):
            return q + "::" + name
        return name

    func intern(c):
        return self.m.intern(c)

    func istr(s):
        return self.m.intern(bf.const_str(s))

    func inull():
        return self.m.intern(bf.const_null())

    # ------------------------------------------------------------------ programme
    func compile_program(program):
        main_stmts := []
        top_fns := []
        top_structs := []
        top_classes := []
        self.types = TypeIndex(program.top_level)
        for s in program.top_level:
            k := s.kind
            if k == "FunctionDecl":
                append(top_fns, s)
                if s.extends_type == "":
                    self.own_names[s.name] = true
            elif k == "StructDecl":
                append(top_structs, s)
                self.own_names[s.name] = true
                append(main_stmts, s)
            elif k == "ClassDecl":
                append(top_classes, s)
                self.own_names[s.name] = true
                append(main_stmts, s)
            elif k == "InterfaceDecl":
                self.own_names[s.name] = true
                self.interfaces[s.name] = self.global_name(s.name)
                append(main_stmts, s)
            elif k == "EnumDecl":
                self.own_names[s.name] = true
                self.register_enum(s)
                append(main_stmts, s)
            else:
                if k == "ImportStmt":
                    if not s.is_from and len(s.module_path) > 0:
                        bound := s.alias if s.alias != null else s.module_path[len(s.module_path) - 1]
                        if not (bound in self.options.namespace_imports):
                            self.own_names[bound] = true
                if k == "ConstDecl" or k == "VariableDecl":
                    self.own_names[s.name] = true
                append(main_stmts, s)
        for local in self.options.imported_structs:
            sig := self.options.imported_structs[local]
            info := StructInfo()
            info.has_ctor = sig.has_ctor
            info.sig_params = sig.ctor_params
            info.is_class = sig.is_class
            info.needs_field_init = sig.has_field_init
            info.runtime_name = self.global_name(local)
            self.structs[local] = info
        for local in self.options.imported_interfaces:
            self.interfaces[local] = self.global_name(local)
        for local in self.options.imported_enums:
            sig := self.options.imported_enums[local]
            self.enums[local] = [self.global_name(local), sig.variants]
        for sd in top_structs:
            info := StructInfo()
            info.runtime_name = self.global_name(sd.name)
            for st in sd.body.statements:
                if st.kind == "FunctionDecl" and st.name == "init":
                    info.has_ctor = true
                    info.ctor_decl = st
            self.structs[sd.name] = info
        self.register_classes(top_classes)
        self.collect_function_decls(program.top_level)
        for st in program.top_level:
            ann := null
            if st.kind == "VariableDecl" or st.kind == "ConstDecl":
                ann = st.type
            if ann != null:
                d := self.type_desc(ann)
                if d != "any":
                    self.global_types[st.name] = d
        for sd in top_structs:
            for st in sd.body.statements:
                if st.kind == "FunctionDecl":
                    self.compile_function(st, self.structs[sd.name].runtime_name + "#" + st.name, true)
        for cd in top_classes:
            self.compile_class_methods(cd)
        for fn in top_fns:
            if fn.extends_type != "":
                self.compile_function(fn, fn.extends_type + "#" + fn.name, true)
            else:
                self.compile_function(fn, "", false)
        main_id := self.next_function_id
        self.next_function_id += 1
        main_name := self.istr(self.global_name("$entry"))
        ctx := FuncCtx()
        ctx.outermost_global = true
        append(ctx.scopes, {})
        scan := CaptureScanner(ctx.captured)
        for st in main_stmts:
            scan.stmt(st, false)
        self.emit_class_registration(ctx, top_classes)
        for st in program.top_level:
            body := null
            name := ""
            if st.kind == "StructDecl" or st.kind == "ClassDecl":
                name = st.name
                body = st.body
            if body == null or not (name in self.structs):
                continue
            for mm in body.statements:
                if mm.kind != "VariableDecl" or mm.type == null:
                    continue
                desc := self.type_desc(mm.type)
                if desc == "any":
                    continue
                self.emit(ctx, bf.CONST, self.istr(self.structs[name].runtime_name))
                self.emit(ctx, bf.CONST, self.istr(mm.name))
                self.emit(ctx, bf.CONST, self.istr(desc))
                self.emit(ctx, bf.DECLARE_FIELD_TYPE)
        for st in main_stmts:
            self.gen_stmt(ctx, st)
        self.emit(ctx, bf.CONST, self.inull())
        self.emit(ctx, bf.RETURN)
        self.finalize(main_id, main_name, 0, 0, ctx)
        m := self.m
        m.entry_function = main_id
        m.functions = self.functions
        m.code = self.code
        m.version_major = 0
        m.version_minor = bf.CURRENT_VERSION_MINOR
        tc := _toolchain()
        m.producer = tc[0]
        if tc[1]:
            m.flags = m.flags | bf.FLAG_BETA
        return m

    func collect_function_decls(stmts):
        for s in stmts:
            self.collect_in(s)

    func collect_in(s):
        k := s.kind
        if k == "FunctionDecl":
            if s.extends_type == "":
                self.named_functions[s.name] = s
            self.collect_function_decls(s.body.statements)
        elif k == "IfStmt":
            self.collect_function_decls(s.then_block.statements)
            for c in s.elif_clauses:
                self.collect_function_decls(c.body.statements)
            if s.else_block != null:
                self.collect_function_decls(s.else_block.statements)
        elif k == "WhileStmt" or k == "ForStmt":
            self.collect_function_decls(s.body.statements)
            if s.else_body != null:
                self.collect_function_decls(s.else_body.statements)
        elif k == "TryStmt":
            self.collect_function_decls(s.try_block.statements)
            for c in s.catch_clauses:
                self.collect_function_decls(c.body.statements)
            if s.finally_block != null:
                self.collect_function_decls(s.finally_block.statements)
        elif k == "MatchStmt":
            for c in s.cases:
                self.collect_function_decls(c.body.statements)

    # ------------------------------------------------------------------ arguments
    func order_arguments(fn_name, params, arguments):
        n := len(params)
        slots := [null for i in 0..n]
        filled := [false for i in 0..n]
        pos := 0
        for a in arguments:
            if a.name != null:
                continue
            if pos >= n:
                _cerr("trop d'arguments dans l'appel de '" + fn_name + "' (attendu au plus " + str(n) + ")")
            slots[pos] = a.value
            filled[pos] = true
            pos += 1
        for a in arguments:
            if a.name == null:
                continue
            idx := -1
            i := 0
            while i < n:
                if params[i].name == a.name:
                    idx = i
                    break
                i += 1
            if idx < 0:
                _cerr("l'argument nommé '" + a.name + "' ne correspond à aucun paramètre de '" + fn_name + "'")
            if filled[idx]:
                _cerr("l'argument '" + a.name + "' est fourni à la fois positionnellement et par nom dans l'appel de '" + fn_name + "'")
            slots[idx] = a.value
            filled[idx] = true
        i := 0
        while i < n:
            if not filled[i]:
                if params[i].default_value == null:
                    _cerr("argument manquant pour le paramètre '" + params[i].name + "' de '" + fn_name + "'")
                slots[i] = params[i].default_value
            i += 1
        return slots

    func order_arguments_sig(fn_name, params, arguments):
        n := len(params)
        slots := [null for i in 0..n]
        filled := [false for i in 0..n]
        pos := 0
        for a in arguments:
            if a.name != null:
                continue
            if pos >= n:
                _cerr("trop d'arguments dans l'appel de '" + fn_name + "' (attendu au plus " + str(n) + ")")
            slots[pos] = a.value
            filled[pos] = true
            pos += 1
        for a in arguments:
            if a.name == null:
                continue
            idx := -1
            i := 0
            while i < n:
                if params[i].name == a.name:
                    idx = i
                    break
                i += 1
            if idx < 0:
                _cerr("l'argument nommé '" + a.name + "' ne correspond à aucun paramètre de '" + fn_name + "'")
            if filled[idx]:
                _cerr("l'argument '" + a.name + "' est fourni à la fois positionnellement et par nom dans l'appel de '" + fn_name + "'")
            slots[idx] = a.value
            filled[idx] = true
        i := 0
        while i < n:
            if not filled[i] and not params[i].has_default:
                _cerr("argument manquant pour le paramètre '" + params[i].name + "' de '" + fn_name + "'")
            i += 1
        return slots

    func gen_positional_call(ctx, arguments):
        spread := false
        for a in arguments:
            spread = spread or _is_spread_arg(a)
        if not spread:
            for a in arguments:
                self.gen_expr(ctx, a.value)
            self.emit(ctx, bf.CALL, len(arguments))
            return
        self.gen_spread_sequence(ctx, [a.value for a in arguments])
        self.emit(ctx, bf.CALL_SPREAD)

    func gen_spread_sequence(ctx, exprs):
        state := [false, 0]
        for e in exprs:
            if e.kind == "UnaryExpr" and e.op == "Spread":
                if state[1] > 0 or not state[0]:
                    self._flush_list(ctx, state)
                self.gen_expr(ctx, e.operand)
                self.emit(ctx, bf.LIST_EXTEND)
            else:
                self.gen_expr(ctx, e)
                state[1] += 1
        if state[1] > 0 or not state[0]:
            self._flush_list(ctx, state)

    func _flush_list(ctx, state):
        self.emit(ctx, bf.BUILD_LIST, state[1])
        if state[0]:
            self.emit(ctx, bf.LIST_EXTEND)
        state[0] = true
        state[1] = 0

    func gen_ordered_args(ctx, slots):
        for e in slots:
            if e == null:
                self.emit(ctx, bf.CONST, self.inull())
            else:
                self.gen_expr(ctx, e)

    # ------------------------------------------------------------------ émission
    func emit(ctx, op, a=0, b=0):
        cl := ctx.cur_line
        if cl != 0:
            nl := len(ctx.lines)
            if nl == 0 or ctx.lines[nl - 1][1] != cl:
                if nl > 0 and ctx.lines[nl - 1][0] == ctx.byte_len:
                    ctx.lines[nl - 1][1] = cl
                else:
                    append(ctx.lines, [ctx.byte_len, cl])
        append(ctx.instrs, [op, a, b])
        ctx.byte_len += bf.instr_size(op)

    func jump_placeholder(ctx, op):
        idx := len(ctx.instrs)
        self.emit(ctx, op, 0)
        return idx

    func patch(ctx, idx, target):
        ctx.instrs[idx][1] = target

    func type_desc(t):
        n := t.name
        if n == "i64":
            n = "int"
        elif n == "f64":
            n = "float"
        if not (n in BUILTIN_TYPES):
            if n in self.structs:
                n = self.structs[n].runtime_name
            elif n in self.interfaces:
                n = self.interfaces[n]
            else:
                n = "any"
        if n == "any":
            return "any"
        if (n == "list" or n == "dict") and len(t.args) > 0:
            n += "[" + _s.join(",", [self.type_desc(x) for x in t.args]) + "]"
        return n + "?" if t.nullable else n

    func emit_type_check(ctx, desc, what):
        if desc == "" or desc == "any":
            return
        self.emit(ctx, bf.CONST, self.istr(desc))
        self.emit(ctx, bf.CONST, self.istr(what))
        self.emit(ctx, bf.CHECK_TYPE)

    func declared_type_of(ctx, name):
        if not (len(ctx.scopes) == 1 and ctx.outermost_global):
            i := len(ctx.scopes) - 1
            while i >= 0:
                sc := ctx.scopes[i]
                if name in sc:
                    return sc[name].type_desc
                if ctx.outermost_global and i == 0:
                    break
                i -= 1
        if name in self.global_types:
            return self.global_types[name]
        return null

    # ------------------------------------------------------------------ fonctions
    func finalize(fid, name_const, amin, amax, ctx):
        fe := bf.FunctionEntry(fid, name_const)
        fe.code_offset = len(self.code)
        before := len(self.code)
        bf.encode_instructions(ctx.instrs, self.code)
        fe.code_length = len(self.code) - before
        fe.arity_min = amin
        fe.arity_max = amax
        fe.locals_count = ctx.next_local
        fe.debug_lines = ctx.lines
        names := ctx.local_names
        if len(names) > ctx.next_local:
            names = names[0:ctx.next_local]
        fe.local_names = names
        if self.options.source_path != "":
            fe.source_const = self.istr(self.options.source_path)
        append(self.functions, fe)

    func register_enum(e):
        variants := {}
        for mm in e.members:
            variants[mm.name] = mm.fields
        self.enums[e.name] = [self.global_name(e.name), variants]

    func compile_function(fn, name_override, implicit_self, parent=null, out_upvals=null, hoisted=false):
        fid := self.next_function_id
        self.next_function_id += 1
        name_const := self.istr(self.global_name(fn.name) if name_override == "" else name_override)
        ctx := FuncCtx()
        ctx.parent = parent
        ctx.hoisted = hoisted
        append(ctx.scopes, {})
        if fn.is_async:
            self.emit(ctx, bf.ASYNC_ENTRY)
        scan := CaptureScanner(ctx.captured)
        for p in fn.params:
            scan.expr(p.default_value, false)
        for st in fn.body.statements:
            scan.stmt(st, false)
        if implicit_self:
            self.declare_param(ctx, "self")
        for p in fn.params:
            self.declare_param(ctx, p.name)
        for p in fn.params:
            if p.default_value == null:
                continue
            ref := self.resolve(ctx, p.name)
            self.emit_load(ctx, ref)
            self.emit(ctx, bf.CONST, self.inull())
            self.emit(ctx, bf.EQ)
            skip := self.jump_placeholder(ctx, bf.JUMP_FALSE)
            self.gen_expr(ctx, p.default_value)
            self.emit_store(ctx, ref)
            self.patch(ctx, skip, ctx.byte_len)
        label := "<lambda>" if fn.name == _a.LAMBDA_NAME else fn.name
        for p in fn.params:
            if p.type == null or p.is_rest:
                continue
            desc := self.type_desc(p.type)
            if desc == "any":
                continue
            self.emit_load(ctx, self.resolve(ctx, p.name))
            self.emit_type_check(ctx, desc, "paramètre '" + p.name + "' de " + label)
            self.emit(ctx, bf.POP)
        if fn.return_type != null:
            ctx.ret_desc = self.type_desc(fn.return_type)
            ctx.ret_what = "valeur de retour de " + label
        self.predeclare_block(ctx, fn.body.statements)
        for st in fn.body.statements:
            self.gen_stmt(ctx, st)
        self.emit(ctx, bf.CONST, self.inull())
        self.emit_type_check(ctx, ctx.ret_desc, ctx.ret_what)
        self.emit(ctx, bf.RETURN)
        amin := 0
        amax := len(fn.params)
        for p in fn.params:
            if p.default_value == null and not p.is_rest:
                amin += 1
        if len(fn.params) > 0 and fn.params[len(fn.params) - 1].is_rest:
            amax = 0x8000 | (len(fn.params) - 1)
        self.finalize(fid, name_const, amin, amax, ctx)
        if out_upvals != null:
            for u in ctx.upvalues:
                append(out_upvals, u)
        return fid

    func closure_name(fn):
        n := fn.name + "@" + str(fn.line) + ":" + str(fn.column) + "#" + str(self.closure_serial)
        self.closure_serial += 1
        q := self.options.self_qualifier
        return n if q == "" else q + "::" + n

    func gen_closure(ctx, fn, hoisted):
        unique := self.closure_name(fn)
        ups := []
        self.compile_function(fn, unique, false, ctx, ups, hoisted)
        for u in ups:
            self.emit(ctx, bf.LOAD_LOCAL if u[1] else bf.UPVALUE_CELL, u[2])
        self.emit(ctx, bf.MAKE_CLOSURE, self.istr(unique), len(ups))

    func predeclare_block(ctx, stmts):
        if len(ctx.scopes) == 1 and ctx.outermost_global:
            return
        fns := []
        for st in stmts:
            if st.kind == "VariableDecl" or st.kind == "ConstDecl":
                if not (st.name in ctx.captured):
                    continue
                slot := ctx.next_local
                ctx.next_local += 1
                self.bind_var(ctx, st.name, Var(slot, true, false))
                self.emit(ctx, bf.NEW_CELL_EMPTY, slot)
            elif st.kind == "FunctionDecl":
                slot := ctx.next_local
                ctx.next_local += 1
                boxed := st.name in ctx.captured
                self.bind_var(ctx, st.name, Var(slot, boxed, true))
                if boxed:
                    self.emit(ctx, bf.NEW_CELL_EMPTY, slot)
                append(fns, st)
        for fn in fns:
            self.gen_closure(ctx, fn, true)
            v := ctx.scopes[len(ctx.scopes) - 1][fn.name]
            if v.boxed:
                self.emit(ctx, bf.LOAD_LOCAL, v.slot)
                self.emit(ctx, bf.CELL_SET)
            else:
                self.emit(ctx, bf.STORE_LOCAL, v.slot)

    # ------------------------------------------------------------------ résolution
    func resolve(ctx, name):
        i := len(ctx.scopes) - 1
        while i >= 0:
            sc := ctx.scopes[i]
            if name in sc:
                v := sc[name]
                if v.declared:
                    if i == 0 and ctx.outermost_global:
                        return Ref(true, self.istr(self.global_name(name)))
                    return Ref(false, v.slot, v.boxed)
            i -= 1
        if ctx.parent != null:
            up := self.resolve_upvalue(ctx, name)
            if up >= 0:
                return Ref(false, up, true, true)
        return Ref(true, self.istr(self.global_name(name)))

    func resolve_upvalue(ctx, name):
        if name in ctx.upvalue_index:
            return ctx.upvalue_index[name]
        p := ctx.parent
        if p == null:
            return -1
        i := len(p.scopes) - 1
        while i >= 0:
            sc := p.scopes[i]
            if name in sc:
                v := sc[name]
                if not (not v.declared and not ctx.hoisted):
                    if i == 0 and p.outermost_global:
                        return -1
                    if not v.boxed:
                        _cerr("erreur interne : la variable '" + name + "' est capturée par une fonction imbriquée mais n'a pas été boxée")
                    return self.add_upvalue(ctx, name, true, v.slot)
            i -= 1
        via := self.resolve_upvalue(p, name)
        if via < 0:
            return -1
        return self.add_upvalue(ctx, name, false, via)

    func add_upvalue(ctx, name, from_local, index):
        rank := len(ctx.upvalues)
        append(ctx.upvalues, [name, from_local, index])
        ctx.upvalue_index[name] = rank
        return rank

    func bind_var(ctx, name, v):
        while len(ctx.local_names) <= v.slot:
            append(ctx.local_names, "")
        ctx.local_names[v.slot] = name
        ctx.scopes[len(ctx.scopes) - 1][name] = v

    func declare_local(ctx, name):
        if len(ctx.scopes) == 1 and ctx.outermost_global:
            ctx.scopes[0][name] = Var()
            return Ref(true, self.istr(self.global_name(name)))
        slot := ctx.next_local
        ctx.next_local += 1
        boxed := name in ctx.captured
        self.bind_var(ctx, name, Var(slot, boxed, true))
        return Ref(false, slot, boxed)

    func declare_param(ctx, name):
        ref := self.declare_local(ctx, name)
        if ref.boxed:
            self.emit(ctx, bf.LOAD_LOCAL, ref.index)
            self.emit(ctx, bf.NEW_CELL, ref.index)

    func emit_load(ctx, ref):
        if ref.is_global:
            self.emit(ctx, bf.LOAD_GLOBAL, ref.index)
        elif ref.upvalue:
            self.emit(ctx, bf.UPVALUE_CELL, ref.index)
            self.emit(ctx, bf.CELL_GET)
        elif ref.boxed:
            self.emit(ctx, bf.LOAD_LOCAL, ref.index)
            self.emit(ctx, bf.CELL_GET)
        else:
            self.emit(ctx, bf.LOAD_LOCAL, ref.index)

    func emit_store(ctx, ref):
        if ref.is_global:
            self.emit(ctx, bf.STORE_GLOBAL, ref.index)
        elif ref.upvalue:
            self.emit(ctx, bf.UPVALUE_CELL, ref.index)
            self.emit(ctx, bf.CELL_SET)
        elif ref.boxed:
            self.emit(ctx, bf.LOAD_LOCAL, ref.index)
            self.emit(ctx, bf.CELL_SET)
        else:
            self.emit(ctx, bf.STORE_LOCAL, ref.index)

    func gen_decl_store(ctx, name):
        if not (len(ctx.scopes) == 1 and ctx.outermost_global):
            sc := ctx.scopes[len(ctx.scopes) - 1]
            if name in sc:
                v := sc[name]
                if not v.declared:
                    v.declared = true
                    self.emit(ctx, bf.LOAD_LOCAL, v.slot)
                    self.emit(ctx, bf.CELL_SET)
                    return
        ref := self.declare_local(ctx, name)
        if ref.is_global:
            self.emit(ctx, bf.STORE_GLOBAL, ref.index)
        elif ref.boxed:
            self.emit(ctx, bf.NEW_CELL, ref.index)
        else:
            self.emit(ctx, bf.STORE_LOCAL, ref.index)

    # Variable de boucle : [slot brut, boxée, slot boxé]
    func alloc_loop_var(ctx, name):
        raw := self.alloc_temp(ctx)
        if name in ctx.captured:
            bs := ctx.next_local
            ctx.next_local += 1
            return [raw, true, bs]
        return [raw, false, 0]

    func bind_loop_name(ctx, name, lv):
        if lv[1]:
            self.bind_var(ctx, name, Var(lv[2], true, true))
        else:
            self.bind_var(ctx, name, Var(lv[0], false, true))

    func declare_loop_var(ctx, name):
        lv := self.alloc_loop_var(ctx, name)
        self.bind_loop_name(ctx, name, lv)
        return lv

    func bind_loop_var(ctx, lv):
        if not lv[1]:
            return
        self.emit(ctx, bf.LOAD_LOCAL, lv[0])
        self.emit(ctx, bf.NEW_CELL, lv[2])

    func push_scope(ctx):
        append(ctx.scopes, {})

    func pop_scope(ctx):
        ctx.scopes = ctx.scopes[0:len(ctx.scopes) - 1]

    func alloc_temp(ctx):
        s := ctx.next_local
        ctx.next_local += 1
        return s

    # ------------------------------------------------------------------ expressions
    func gen_expr(ctx, e):
        sr := self.options.sized_results
        if sr != null and self.sized_pending != e.uid and e.uid in sr:
            saved := self.sized_pending
            self.sized_pending = e.uid
            self.gen_expr(ctx, e)
            self.sized_pending = saved
            t := sr[e.uid]
            self.emit_type_check(ctx, t, "débordement de " + t)
            return
        saved_line := ctx.cur_line
        if e.line > 0:
            ctx.cur_line = e.line
        self.gen_expr_inner(ctx, e)
        ctx.cur_line = saved_line

    func gen_expr_inner(ctx, e):
        k := e.kind
        if k == "Literal":
            self.emit(ctx, bf.CONST, self.intern(literal_constant(e.literal_kind, e.value)))
        elif k == "Identifier":
            self.emit_load(ctx, self.resolve(ctx, e.name))
        elif k == "LambdaExpr":
            self.gen_closure(ctx, e.function, false)
        elif k == "ComprehensionExpr":
            self.gen_comprehension(ctx, e)
        elif k == "ListLiteral":
            if _has_spread_element(e.elements):
                self.gen_spread_sequence(ctx, e.elements)
                return
            for x in e.elements:
                self.gen_expr(ctx, x)
            self.emit(ctx, bf.BUILD_LIST, len(e.elements))
        elif k == "TupleLiteral":
            if _has_spread_element(e.elements):
                self.gen_spread_sequence(ctx, e.elements)
                self.emit(ctx, bf.LIST_TO_TUPLE)
                return
            for x in e.elements:
                self.gen_expr(ctx, x)
            self.emit(ctx, bf.BUILD_TUPLE, len(e.elements))
        elif k == "DictLiteral":
            self.gen_dict(ctx, e)
        elif k == "FStringLiteral":
            if len(e.parts) == 0:
                self.emit(ctx, bf.CONST, self.istr(""))
                return
            first := true
            for p in e.parts:
                if p.is_expr:
                    self.gen_expr(ctx, p.expr)
                    self.emit(ctx, bf.TO_STRING)
                else:
                    self.emit(ctx, bf.CONST, self.istr(p.text))
                if not first:
                    self.emit(ctx, bf.ADD)
                first = false
        elif k == "BinaryExpr":
            self.gen_binary(ctx, e)
        elif k == "UnaryExpr":
            if e.op == "Spread" or e.op == "DictSpread":
                _cerr("'*' / '**' n'est permis que dans un appel, une liste, un tuple ou un dict littéral")
            self.gen_unary(ctx, e)
        elif k == "ConditionalExpr":
            self.gen_expr(ctx, e.condition)
            else_jump := self.jump_placeholder(ctx, bf.JUMP_FALSE)
            self.gen_expr(ctx, e.then_expr)
            end_jump := self.jump_placeholder(ctx, bf.JUMP)
            self.patch(ctx, else_jump, ctx.byte_len)
            self.gen_expr(ctx, e.else_expr)
            self.patch(ctx, end_jump, ctx.byte_len)
        elif k == "RangeExpr":
            _cerr("une expression range (a..b) ne peut être compilée que comme itérable direct d'un 'for' (aucun type Range n'existe dans le modèle runtime, voir README section P9)")
        elif k == "CallExpr":
            self.gen_call(ctx, e)
        elif k == "IndexExpr":
            self.gen_expr(ctx, e.object)
            self.gen_expr(ctx, e.index)
            self.emit(ctx, bf.GET_INDEX)
        elif k == "MemberExpr":
            self.gen_member(ctx, e)
        elif k == "ErrorPropagationExpr":
            self.gen_expr(ctx, e.operand)
        else:
            _cerr("expression non prise en charge par le compilateur P9")

    func gen_dict(ctx, e):
        any_spread := false
        for kv in e.entries:
            any_spread = any_spread or _is_dict_spread(kv)
        if any_spread:
            state := [false, 0]
            for kv in e.entries:
                if _is_dict_spread(kv):
                    if state[1] > 0 or not state[0]:
                        self._flush_dict(ctx, state)
                    self.gen_expr(ctx, kv.key.operand)
                    self.emit(ctx, bf.DICT_UPDATE)
                else:
                    self.gen_expr(ctx, kv.key)
                    self.gen_expr(ctx, kv.value)
                    state[1] += 1
            if state[1] > 0 or not state[0]:
                self._flush_dict(ctx, state)
            return
        for kv in e.entries:
            self.gen_expr(ctx, kv.key)
            self.gen_expr(ctx, kv.value)
        self.emit(ctx, bf.BUILD_DICT, len(e.entries))

    func _flush_dict(ctx, state):
        self.emit(ctx, bf.BUILD_DICT, state[1])
        if state[0]:
            self.emit(ctx, bf.DICT_UPDATE)
        state[0] = true
        state[1] = 0

    func _intrinsic_args(ctx, n, name, expected):
        if len(n.arguments) != expected:
            _cerr("'" + name + "' attend exactement " + str(expected) + " argument(s)")
        for a in n.arguments:
            if a.name != null:
                _cerr("'" + name + "' ne prend pas d'argument nommé")
            self.gen_expr(ctx, a.value)

    func gen_call(ctx, n):
        if n.callee.kind == "Identifier":
            cn := n.callee.name
            if cn == "print":
                if len(n.arguments) == 0:
                    self.emit(ctx, bf.CONST, self.istr(""))
                    self.emit(ctx, bf.PRINT)
                else:
                    for a in n.arguments:
                        if a.name != null:
                            _cerr("print(...) ne prend pas d'arguments nommés")
                        self.gen_expr(ctx, a.value)
                        self.emit(ctx, bf.TO_STRING)
                        self.emit(ctx, bf.PRINT)
                self.emit(ctx, bf.CONST, self.inull())
                return
            if cn == "input":
                if len(n.arguments) > 1:
                    _cerr("input(...) accepte au plus un argument (l'invite)")
                if len(n.arguments) == 1:
                    if n.arguments[0].name != null:
                        _cerr("input(...) ne prend pas d'argument nommé")
                    self.gen_expr(ctx, n.arguments[0].value)
                    self.emit(ctx, bf.PRINT)
                self.emit(ctx, bf.INPUT)
                return
            if cn == "isinstance":
                self.gen_isinstance(ctx, n)
                return
            if cn == "str":
                if len(n.arguments) != 1:
                    _cerr("str(...) attend exactement un argument")
                if n.arguments[0].name != null:
                    _cerr("str(...) ne prend pas d'argument nommé")
                self.gen_expr(ctx, n.arguments[0].value)
                self.emit(ctx, bf.TO_STRING)
                return
            if cn == "__del_item":
                if len(n.arguments) != 2:
                    _cerr("'__del_item' attend exactement 2 arguments")
                for a in n.arguments:
                    self.gen_expr(ctx, a.value)
                self.emit(ctx, bf.DEL_ITEM)
                return
            if cn == "__len":
                if len(n.arguments) != 1:
                    _cerr("'__len' attend exactement 1 argument")
                self.gen_expr(ctx, n.arguments[0].value)
                self.emit(ctx, bf.LEN)
                return
            if cn == "__slice":
                if len(n.arguments) != 4:
                    _cerr("'__slice' attend exactement 4 arguments")
                for a in n.arguments:
                    self.gen_expr(ctx, a.value)
                self.emit(ctx, bf.GET_SLICE)
                return
            if cn == "__list_append" or cn == "__list_clear":
                self._intrinsic_args(ctx, n, cn, 2 if cn == "__list_append" else 1)
                self.emit(ctx, bf.LIST_APPEND if cn == "__list_append" else bf.LIST_CLEAR)
                return
            if cn == "__list_insert" or cn == "__list_remove_at":
                self._intrinsic_args(ctx, n, cn, 3 if cn == "__list_insert" else 2)
                self.emit(ctx, bf.LIST_INSERT if cn == "__list_insert" else bf.LIST_REMOVE_AT)
                return
            if cn == "raise":
                if len(n.arguments) != 1 and len(n.arguments) != 2:
                    _cerr("'raise' attend 1 argument (message) ou 2 (type, message)")
                for a in n.arguments:
                    if a.name != null:
                        _cerr("'raise' ne prend pas d'argument nommé")
                if len(n.arguments) == 1:
                    self.emit(ctx, bf.CONST, self.istr("Exception"))
                    self.gen_expr(ctx, n.arguments[0].value)
                else:
                    self.gen_expr(ctx, n.arguments[0].value)
                    self.gen_expr(ctx, n.arguments[1].value)
                self.emit(ctx, bf.RAISE)
                return
            if cn == "__dict_remove_key":
                if len(n.arguments) != 2:
                    _cerr("'__dict_remove_key' attend exactement 2 arguments")
                for a in n.arguments:
                    if a.name != null:
                        _cerr("'__dict_remove_key' ne prend pas d'argument nommé")
                    self.gen_expr(ctx, a.value)
                self.emit(ctx, bf.DICT_REMOVE_KEY)
                return
            if cn in self.structs:
                self.gen_struct_construct(ctx, cn, self.structs[cn], n.arguments)
                return
            if _has_named(n.arguments):
                if cn in self.options.imported_functions:
                    slots := self.order_arguments_sig(cn, self.options.imported_functions[cn].params, n.arguments)
                    self.gen_expr(ctx, n.callee)
                    self.gen_ordered_args(ctx, slots)
                    self.emit(ctx, bf.CALL, len(slots))
                    return
                if cn in self.named_functions:
                    slots := self.order_arguments(cn, self.named_functions[cn].params, n.arguments)
                    self.gen_expr(ctx, n.callee)
                    self.gen_ordered_args(ctx, slots)
                    self.emit(ctx, bf.CALL, len(slots))
                    return
        if n.callee.kind == "MemberExpr":
            mem := n.callee
            ns_enum := self.resolve_namespace_enum(mem.object)
            if ns_enum != null:
                variants := ns_enum[0].variants
                if not (mem.member in variants):
                    _cerr("l'enum '" + ns_enum[2] + "' n'a pas de variante '" + mem.member + "'")
                if len(variants[mem.member]) != len(n.arguments):
                    _cerr("'" + ns_enum[2] + "." + mem.member + "' attend " + str(len(variants[mem.member])) + " argument(s), obtenu " + str(len(n.arguments)))
                self.gen_enum_construct_tag(ctx, ns_enum[1] + "." + mem.member, n.arguments)
                return
            if mem.object.kind == "Identifier":
                q := mem.object.name
                if q in self.enums:
                    en := self.enums[q]
                    if mem.member in en[1]:
                        fields := en[1][mem.member]
                        if len(fields) != len(n.arguments):
                            _cerr("'" + q + "." + mem.member + "' attend " + str(len(fields)) + " argument(s), obtenu " + str(len(n.arguments)))
                        self.gen_enum_construct_tag(ctx, en[0] + "." + mem.member, n.arguments)
                        return
                if q in self.options.namespace_imports:
                    ns := self.options.namespace_imports[q]
                    if not (mem.member in ns.exports):
                        _cerr("'" + q + "' n'exporte aucun membre '" + mem.member + "' (voir la déclaration de module correspondante)")
                    qualified := ns.qualifier + "::" + mem.member
                    if mem.member in ns.sigs.structs:
                        sig := ns.sigs.structs[mem.member]
                        info := StructInfo()
                        info.has_ctor = sig.has_ctor
                        info.sig_params = sig.ctor_params
                        info.is_class = sig.is_class
                        info.needs_field_init = sig.has_field_init
                        info.runtime_name = qualified
                        self.gen_struct_construct(ctx, q + "." + mem.member, info, n.arguments)
                        return
                    self.emit(ctx, bf.LOAD_GLOBAL, self.istr(qualified))
                    if _has_named(n.arguments):
                        if not (mem.member in ns.sigs.functions):
                            _cerr("les arguments nommés ne sont compilables que vers une fonction : '" + q + "." + mem.member + "' n'est pas une fonction exportée")
                        slots := self.order_arguments_sig(q + "." + mem.member, ns.sigs.functions[mem.member].params, n.arguments)
                        self.gen_ordered_args(ctx, slots)
                        self.emit(ctx, bf.CALL, len(slots))
                        return
                    self.gen_positional_call(ctx, n.arguments)
                    return
        self.gen_expr(ctx, n.callee)
        for a in n.arguments:
            if a.name != null:
                _cerr("les arguments nommés ('" + a.name + "=...') ne sont compilables que pour un appel dont la cible est résolue STATIQUEMENT (identifiant référant à une déclaration `func` connue, ou constructeur de struct) : ici la cible n'est pas un identifiant de fonction connu au moment de la compilation (valeur passée par variable, appel de méthode dynamique via obj.method(...), etc.) — l'opcode CALL ne transmet que des arguments positionnels (§14.1), voir README section P9")
        self.gen_positional_call(ctx, n.arguments)

    func gen_member(ctx, n):
        if n.object.kind == "Identifier" and n.object.name == "super":
            self.gen_super_member(ctx, n.member)
            return
        ns_enum := self.resolve_namespace_enum(n.object)
        if ns_enum != null:
            variants := ns_enum[0].variants
            if not (n.member in variants):
                _cerr("l'enum '" + ns_enum[2] + "' n'a pas de variante '" + n.member + "'")
            if len(variants[n.member]) > 0:
                _cerr("'" + ns_enum[2] + "." + n.member + "' attend " + str(len(variants[n.member])) + " argument(s) : utiliser '" + ns_enum[2] + "." + n.member + "(...)'")
            self.gen_enum_construct_tag(ctx, ns_enum[1] + "." + n.member, [])
            return
        if n.object.kind == "Identifier":
            q := n.object.name
            if q in self.enums:
                en := self.enums[q]
                if n.member in en[1]:
                    if len(en[1][n.member]) > 0:
                        _cerr("'" + q + "." + n.member + "' attend " + str(len(en[1][n.member])) + " argument(s) : utiliser '" + q + "." + n.member + "(...)'")
                    self.gen_enum_construct_tag(ctx, en[0] + "." + n.member, [])
                    return
            if q in self.options.namespace_imports:
                ns := self.options.namespace_imports[q]
                if not (n.member in ns.exports):
                    _cerr("'" + q + "' n'exporte aucun membre '" + n.member + "' (voir la déclaration de module correspondante)")
                self.emit(ctx, bf.LOAD_GLOBAL, self.istr(ns.qualifier + "::" + n.member))
                return
        self.gen_expr(ctx, n.object)
        self.emit(ctx, bf.GET_MEMBER, self.istr(n.member))

    # ------------------------------------------------------------------ orienté objet
    func register_classes(classes):
        for cd in classes:
            info := StructInfo()
            info.is_class = true
            info.runtime_name = self.global_name(cd.name)
            self.structs[cd.name] = info
        for cd in classes:
            td := self.types.find(cd.name)
            info := self.structs[cd.name]
            if cd.base_class != null:
                self.require_base_class(cd.base_class, cd.name)
            fm := self.types.find_method(td, "init")
            ctor := fm[0]
            external := fm[1]
            if ctor != null:
                info.has_ctor = true
                info.ctor_decl = ctor
            inherited := false
            if external != null:
                ext := self.require_base_class(external, cd.name)
                if ctor == null:
                    info.has_ctor = ext.has_ctor
                    info.sig_params = ext.sig_params
                inherited = ext.needs_field_init
            info.needs_field_init = self.types.has_local_field_init(td) or inherited

    func require_base_class(base, derived):
        if not (base in self.structs) or not self.structs[base].is_class:
            _cerr("la classe de base '" + base + "' de '" + derived + "' est inconnue ou n'est pas une classe (une struct ou une interface ne peut pas servir de base)")
        return self.structs[base]

    func gen_self(ctx):
        self.gen_expr(ctx, _a.ident("self", 0, 0))

    func gen_super_member(ctx, member):
        if self.current_class == null or self.current_class.base == null:
            _cerr("'super' n'est utilisable que dans une méthode d'une classe qui a une classe de base")
        self.gen_self(ctx)
        self.emit(ctx, bf.CONST, self.istr(self.structs[self.current_class.base].runtime_name))
        self.emit(ctx, bf.GET_SUPER, self.istr(member))

    func compile_class_methods(cd):
        td := self.types.find(cd.name)
        info := self.structs[cd.name]
        saved := self.current_class
        self.current_class = td
        for mm in td.own_methods():
            self.compile_function(mm, info.runtime_name + "#" + mm.name, true)
        if len(td.own_fields()) > 0:
            self.compile_field_initializer(td, info)
        self.current_class = saved

    func compile_field_initializer(td, info):
        fid := self.next_function_id
        self.next_function_id += 1
        name_const := self.istr(info.runtime_name + "#__fields")
        ctx := FuncCtx()
        append(ctx.scopes, {})
        scan := CaptureScanner(ctx.captured)
        for f in td.own_fields():
            scan.expr(f.value, false)
        self.declare_param(ctx, "self")
        if td.base != null and self.structs[td.base].needs_field_init:
            self.gen_super_member(ctx, "__fields")
            self.emit(ctx, bf.CALL, 0)
            self.emit(ctx, bf.POP)
        for f in td.own_fields():
            if f.declared_only:
                continue
            self.gen_self(ctx)
            self.gen_expr(ctx, f.value)
            self.emit(ctx, bf.SET_MEMBER, self.istr(f.name))
        self.emit(ctx, bf.CONST, self.inull())
        self.emit(ctx, bf.RETURN)
        self.finalize(fid, name_const, 0, 0, ctx)

    func emit_class_registration(ctx, classes):
        for cd in classes:
            info := self.structs[cd.name]
            self.emit(ctx, bf.CONST, self.istr(info.runtime_name))
            if cd.base_class != null:
                self.emit(ctx, bf.CONST, self.istr(self.require_base_class(cd.base_class, cd.name).runtime_name))
            else:
                self.emit(ctx, bf.CONST, self.inull())
            self.emit(ctx, bf.DEF_CLASS)
            for iface in cd.interfaces:
                if not (iface in self.interfaces):
                    _cerr("'" + iface + "' (implements de '" + cd.name + "') n'est pas une interface connue")
                self.emit(ctx, bf.CONST, self.istr(info.runtime_name))
                self.emit(ctx, bf.CONST, self.istr(self.interfaces[iface]))
                self.emit(ctx, bf.ADD_INTERFACE)

    func gen_isinstance(ctx, call):
        ok := len(call.arguments) == 2 and call.arguments[0].name == null and call.arguments[1].name == null
        te := call.arguments[1].value if ok else null
        if te == null or (te.kind != "Identifier" and te.kind != "MemberExpr"):
            _cerr("isinstance attend (valeur, NomDeType) : deux arguments positionnels, le second étant un nom de type")
        runtime := ""
        if te.kind == "Identifier":
            tn := te.name
            if tn in self.structs:
                runtime = self.structs[tn].runtime_name
            elif tn in self.interfaces:
                runtime = self.interfaces[tn]
            else:
                _cerr("isinstance : '" + tn + "' n'est pas une struct, une classe ou une interface connue")
        else:
            obj := te.object
            if obj.kind != "Identifier" or not (obj.name in self.options.namespace_imports):
                _cerr("isinstance : le type qualifié doit être de la forme alias.Type, où alias est un module importé par 'use module [as alias]'")
            ns := self.options.namespace_imports[obj.name]
            if not (te.member in ns.sigs.structs) and not (te.member in ns.sigs.interfaces):
                _cerr("isinstance : '" + obj.name + "." + te.member + "' n'est pas une struct, une classe ou une interface exportée")
            runtime = ns.qualifier + "::" + te.member
        self.gen_expr(ctx, call.arguments[0].value)
        self.emit(ctx, bf.CONST, self.istr(runtime))
        self.emit(ctx, bf.INSTANCE_OF)

    func gen_struct_construct(ctx, display, info, arguments):
        tmp := self.alloc_temp(ctx)
        self.emit(ctx, bf.NEW_INSTANCE, self.istr(info.runtime_name))
        self.emit(ctx, bf.STORE_LOCAL, tmp)
        if info.needs_field_init:
            self.emit(ctx, bf.LOAD_LOCAL, tmp)
            self.emit(ctx, bf.GET_MEMBER, self.istr("__fields"))
            self.emit(ctx, bf.CALL, 0)
            self.emit(ctx, bf.POP)
        if info.has_ctor:
            self.emit(ctx, bf.LOAD_LOCAL, tmp)
            self.emit(ctx, bf.GET_MEMBER, self.istr("init"))
            if _has_named(arguments):
                slots := []
                if info.ctor_decl != null:
                    slots = self.order_arguments(display, info.ctor_decl.params, arguments)
                else:
                    slots = self.order_arguments_sig(display, info.sig_params, arguments)
                self.gen_ordered_args(ctx, slots)
                self.emit(ctx, bf.CALL, len(slots))
            else:
                self.gen_positional_call(ctx, arguments)
            self.emit(ctx, bf.POP)
        elif len(arguments) > 0:
            _cerr("'" + display + "' n'a pas de constructeur 'init' : aucun argument attendu, " + str(len(arguments)) + " fourni(s)")
        self.emit(ctx, bf.LOAD_LOCAL, tmp)

    func gen_enum_construct_tag(ctx, tag, arguments):
        tmp := self.alloc_temp(ctx)
        self.emit(ctx, bf.NEW_INSTANCE, self.istr(tag))
        self.emit(ctx, bf.STORE_LOCAL, tmp)
        self.emit(ctx, bf.LOAD_LOCAL, tmp)
        self.emit(ctx, bf.CONST, self.istr(tag))
        self.emit(ctx, bf.SET_MEMBER, self.istr("__tag"))
        i := 0
        while i < len(arguments):
            if arguments[i].name != null:
                _cerr("les arguments nommés ne sont pas compilables pour une variante d'enum ('" + tag + "')")
            self.emit(ctx, bf.LOAD_LOCAL, tmp)
            self.gen_expr(ctx, arguments[i].value)
            self.emit(ctx, bf.SET_MEMBER, self.istr("_" + str(i)))
            i += 1
        self.emit(ctx, bf.LOAD_LOCAL, tmp)

    # [signature, nom runtime, affichage] ou null
    func resolve_namespace_enum(e):
        if e.kind != "MemberExpr" or e.object.kind != "Identifier":
            return null
        alias := e.object.name
        if not (alias in self.options.namespace_imports):
            return null
        ns := self.options.namespace_imports[alias]
        if not (e.member in ns.sigs.enums):
            return null
        return [ns.sigs.enums[e.member], ns.qualifier + "::" + e.member, alias + "." + e.member]

    # ------------------------------------------------------------------ opérateurs
    func gen_binary(ctx, n):
        if n.op == "And":
            self.gen_expr(ctx, n.left)
            self.emit(ctx, bf.DUP)
            sc := self.jump_placeholder(ctx, bf.JUMP_FALSE)
            self.emit(ctx, bf.POP)
            self.gen_expr(ctx, n.right)
            self.patch(ctx, sc, ctx.byte_len)
            return
        if n.op == "Or":
            self.gen_expr(ctx, n.left)
            self.emit(ctx, bf.DUP)
            self.emit(ctx, bf.NOT)
            sc := self.jump_placeholder(ctx, bf.JUMP_FALSE)
            self.emit(ctx, bf.POP)
            self.gen_expr(ctx, n.right)
            self.patch(ctx, sc, ctx.byte_len)
            return
        self.gen_expr(ctx, n.left)
        self.gen_expr(ctx, n.right)
        if n.op == "In" or n.op == "NotIn":
            self.emit(ctx, bf.CONTAINS)
            if n.op == "NotIn":
                self.emit(ctx, bf.NOT)
            return
        self.emit(ctx, BINOP[n.op])

    func gen_unary(ctx, n):
        op := n.op
        if op == "Plus":
            self.emit(ctx, bf.CONST, self.intern(bf.const_int(0)))
            self.gen_expr(ctx, n.operand)
            self.emit(ctx, bf.ADD)
        elif op == "Minus":
            self.emit(ctx, bf.CONST, self.intern(bf.const_int(0)))
            self.gen_expr(ctx, n.operand)
            self.emit(ctx, bf.SUB)
        elif op == "Not":
            self.gen_expr(ctx, n.operand)
            self.emit(ctx, bf.NOT)
        elif op == "BitNot":
            self.gen_expr(ctx, n.operand)
            self.emit(ctx, bf.BITNOT)
        elif op == "Await":
            self.gen_expr(ctx, n.operand)
            self.emit(ctx, bf.AWAIT)
        else:
            _cerr("spread ('...') hors d'un contexte autorisé")

    # ------------------------------------------------------------------ instructions
    func gen_block(ctx, b):
        self.push_scope(ctx)
        self.predeclare_block(ctx, b.statements)
        for s in b.statements:
            self.gen_stmt(ctx, s)
        self.pop_scope(ctx)

    func gen_stmt(ctx, s):
        saved_line := ctx.cur_line
        if s.line > 0:
            ctx.cur_line = s.line
        self.gen_stmt_inner(ctx, s)
        ctx.cur_line = saved_line

    func gen_stmt_inner(ctx, s):
        k := s.kind
        if k == "VariableDecl" or k == "ConstDecl":
            self.gen_expr(ctx, s.value)
            desc := self.type_desc(s.type) if s.type != null else ""
            self.emit_type_check(ctx, desc, "variable '" + s.name + "'")
            self.gen_decl_store(ctx, s.name)
            if desc != "" and desc != "any":
                if len(ctx.scopes) == 1 and ctx.outermost_global:
                    self.global_types[s.name] = desc
                else:
                    sc := ctx.scopes[len(ctx.scopes) - 1]
                    if s.name in sc:
                        sc[s.name].type_desc = desc
        elif k == "Assignment":
            self.gen_assign(ctx, s.target, s.value, -1)
        elif k == "CompoundAssignment":
            self.gen_assign(ctx, s.target, s.value, BINOP[s.op])
        elif k == "ExpressionStmt":
            self.gen_expr(ctx, s.expr)
            self.emit(ctx, bf.POP)
        elif k == "IfStmt":
            self.gen_if(ctx, s)
        elif k == "WhileStmt":
            self.gen_while(ctx, s)
        elif k == "ForStmt":
            self.gen_for_loop(ctx, s.variable, s.iterable, ["block", s.body], s.else_body)
        elif k == "BreakStmt" or k == "ContinueStmt":
            if len(ctx.loops) == 0:
                _cerr("'break' en dehors de toute boucle" if k == "BreakStmt" else "'continue' en dehors de toute boucle")
            self.unwind_finallies(ctx, len(ctx.loops), ["break" if k == "BreakStmt" else "continue"])
        elif k == "ReturnStmt":
            if s.value != null:
                self.gen_expr(ctx, s.value)
            else:
                self.emit(ctx, bf.CONST, self.inull())
            self.emit_type_check(ctx, ctx.ret_desc, ctx.ret_what)
            if len(ctx.finally_stack) > 0:
                slot := self.alloc_temp(ctx)
                self.emit(ctx, bf.STORE_LOCAL, slot)
                self.unwind_finallies(ctx, 0, ["return", slot])
                return
            self.emit(ctx, bf.RETURN)
        elif k == "TryStmt":
            self.gen_try(ctx, s)
        elif k == "FunctionDecl":
            if not (s.name in ctx.scopes[len(ctx.scopes) - 1]):
                _cerr("erreur interne : la fonction imbriquée '" + s.name + "' n'a pas été hissée")
        elif k == "ImportStmt":
            if len(s.module_path) == 0:
                _cerr("chemin de module vide")
            if s.is_from:
                if len(s.names) > 0 and (s.names[0] in self.options.imported_names):
                    return
                self.emit(ctx, bf.IMPORT, self.istr(s.module_path[0]))
            else:
                bound := s.alias if s.alias != null else s.module_path[len(s.module_path) - 1]
                if bound in self.options.namespace_imports:
                    return
                self.emit(ctx, bf.IMPORT_MODULE, self.istr(s.module_path[0]))
                self.emit(ctx, bf.STORE_GLOBAL, self.istr(self.global_name(bound)))
        elif k == "StructDecl" or k == "EnumDecl" or k == "ClassDecl" or k == "InterfaceDecl":
            return
        elif k == "MatchStmt":
            self.gen_match(ctx, s)
        else:
            _cerr("instruction non prise en charge par le compilateur P9")

    # compound : opcode, ou -1 pour une affectation simple
    func gen_assign(ctx, target, value, compound):
        if target.kind == "Identifier":
            name := target.name
            ref := self.resolve(ctx, name)
            if compound >= 0:
                self.emit_load(ctx, ref)
                self.gen_expr(ctx, value)
                self.emit(ctx, compound)
            else:
                self.gen_expr(ctx, value)
            desc := self.declared_type_of(ctx, name)
            if desc != null:
                self.emit_type_check(ctx, desc, "variable '" + name + "'")
            self.emit_store(ctx, ref)
            return
        if target.kind == "IndexExpr":
            obj_slot := self.alloc_temp(ctx)
            idx_slot := self.alloc_temp(ctx)
            self.gen_expr(ctx, target.object)
            self.emit(ctx, bf.STORE_LOCAL, obj_slot)
            self.gen_expr(ctx, target.index)
            self.emit(ctx, bf.STORE_LOCAL, idx_slot)
            if compound >= 0:
                self.emit(ctx, bf.LOAD_LOCAL, obj_slot)
                self.emit(ctx, bf.LOAD_LOCAL, idx_slot)
                self.emit(ctx, bf.GET_INDEX)
                self.gen_expr(ctx, value)
                self.emit(ctx, compound)
            else:
                self.gen_expr(ctx, value)
            nv := self.alloc_temp(ctx)
            self.emit(ctx, bf.STORE_LOCAL, nv)
            self.emit(ctx, bf.LOAD_LOCAL, obj_slot)
            self.emit(ctx, bf.LOAD_LOCAL, idx_slot)
            self.emit(ctx, bf.LOAD_LOCAL, nv)
            self.emit(ctx, bf.SET_INDEX)
            return
        if target.kind == "MemberExpr":
            obj_slot := self.alloc_temp(ctx)
            self.gen_expr(ctx, target.object)
            self.emit(ctx, bf.STORE_LOCAL, obj_slot)
            mc := self.istr(target.member)
            if compound >= 0:
                self.emit(ctx, bf.LOAD_LOCAL, obj_slot)
                self.emit(ctx, bf.GET_MEMBER, mc)
                self.gen_expr(ctx, value)
                self.emit(ctx, compound)
            else:
                self.gen_expr(ctx, value)
            nv := self.alloc_temp(ctx)
            self.emit(ctx, bf.STORE_LOCAL, nv)
            self.emit(ctx, bf.LOAD_LOCAL, obj_slot)
            self.emit(ctx, bf.LOAD_LOCAL, nv)
            self.emit(ctx, bf.SET_MEMBER, mc)
            return
        _cerr("cible d'affectation non compilable (seuls identifiant, indexation et accès membre le sont — voir README section P9)")

    func gen_if(ctx, n):
        ends := []
        self.gen_expr(ctx, n.condition)
        nxt := self.jump_placeholder(ctx, bf.JUMP_FALSE)
        self.gen_block(ctx, n.then_block)
        append(ends, self.jump_placeholder(ctx, bf.JUMP))
        self.patch(ctx, nxt, ctx.byte_len)
        for c in n.elif_clauses:
            self.gen_expr(ctx, c.condition)
            j := self.jump_placeholder(ctx, bf.JUMP_FALSE)
            self.gen_block(ctx, c.body)
            append(ends, self.jump_placeholder(ctx, bf.JUMP))
            self.patch(ctx, j, ctx.byte_len)
        if n.else_block != null:
            self.gen_block(ctx, n.else_block)
        for f in ends:
            self.patch(ctx, f, ctx.byte_len)

    func gen_while(ctx, n):
        start := ctx.byte_len
        self.gen_expr(ctx, n.condition)
        exit_jump := self.jump_placeholder(ctx, bf.JUMP_FALSE)
        append(ctx.loops, LoopCtx(ctx.try_depth))
        self.gen_block(ctx, n.body)
        loop := ctx.loops[len(ctx.loops) - 1]
        ctx.loops = ctx.loops[0:len(ctx.loops) - 1]
        for f in loop.continue_fixups:
            self.patch(ctx, f, start)
        self.emit(ctx, bf.JUMP, start)
        self.patch(ctx, exit_jump, ctx.byte_len)
        if n.else_body != null:
            self.gen_block(ctx, n.else_body)
        for f in loop.break_fixups:
            self.patch(ctx, f, ctx.byte_len)

    # body : ["block", bloc] (instruction for) ou ["comp", compréhension, clause suivante, slot résultat]
    func emit_body(ctx, body):
        if body[0] == "block":
            self.gen_block(ctx, body[1])
        else:
            self.gen_comp_clauses(ctx, body[1], body[2], body[3])

    func gen_for_loop(ctx, variable, iterable, body, else_body=null):
        if iterable.kind == "RangeExpr":
            self.gen_for_range(ctx, variable, iterable, body, else_body)
        else:
            self.gen_for_iterable(ctx, variable, iterable, body, else_body)

    func gen_for_range(ctx, variable, rng, body, else_body):
        self.push_scope(ctx)
        lv := self.alloc_loop_var(ctx, variable)
        var_slot := lv[0]
        self.gen_expr(ctx, rng.start)
        self.emit(ctx, bf.STORE_LOCAL, var_slot)
        end_slot := self.alloc_temp(ctx)
        self.gen_expr(ctx, rng.end)
        self.emit(ctx, bf.STORE_LOCAL, end_slot)
        self.bind_loop_name(ctx, variable, lv)
        start := ctx.byte_len
        self.emit(ctx, bf.LOAD_LOCAL, var_slot)
        self.emit(ctx, bf.LOAD_LOCAL, end_slot)
        self.emit(ctx, bf.LT)
        exit_jump := self.jump_placeholder(ctx, bf.JUMP_FALSE)
        self.bind_loop_var(ctx, lv)
        append(ctx.loops, LoopCtx(ctx.try_depth))
        self.emit_body(ctx, body)
        loop := ctx.loops[len(ctx.loops) - 1]
        ctx.loops = ctx.loops[0:len(ctx.loops) - 1]
        inc := ctx.byte_len
        for f in loop.continue_fixups:
            self.patch(ctx, f, inc)
        self.emit(ctx, bf.LOAD_LOCAL, var_slot)
        self.emit(ctx, bf.CONST, self.intern(bf.const_int(1)))
        self.emit(ctx, bf.ADD)
        self.emit(ctx, bf.STORE_LOCAL, var_slot)
        self.emit(ctx, bf.JUMP, start)
        self.patch(ctx, exit_jump, ctx.byte_len)
        if else_body != null:
            self.gen_block(ctx, else_body)
        for f in loop.break_fixups:
            self.patch(ctx, f, ctx.byte_len)
        self.pop_scope(ctx)

    func gen_for_iterable(ctx, variable, iterable, body, else_body):
        self.push_scope(ctx)
        coll := self.alloc_temp(ctx)
        self.gen_expr(ctx, iterable)
        self.emit(ctx, bf.STORE_LOCAL, coll)
        self.emit(ctx, bf.LOAD_LOCAL, coll)
        self.emit(ctx, bf.TYPE_NAME)
        self.emit(ctx, bf.CONST, self.istr("dict"))
        self.emit(ctx, bf.EQ)
        not_dict := self.jump_placeholder(ctx, bf.JUMP_FALSE)
        self.emit(ctx, bf.LOAD_LOCAL, coll)
        self.emit(ctx, bf.DICT_KEYS)
        self.emit(ctx, bf.STORE_LOCAL, coll)
        self.patch(ctx, not_dict, ctx.byte_len)
        idx := self.alloc_temp(ctx)
        self.emit(ctx, bf.CONST, self.intern(bf.const_int(0)))
        self.emit(ctx, bf.STORE_LOCAL, idx)
        lv := self.declare_loop_var(ctx, variable)
        var_slot := lv[0]
        exc := self.alloc_temp(ctx)
        start := ctx.byte_len
        try_begin := len(ctx.instrs)
        self.emit(ctx, bf.TRY_BEGIN, 0, exc)
        self.emit(ctx, bf.LOAD_LOCAL, coll)
        self.emit(ctx, bf.LOAD_LOCAL, idx)
        self.emit(ctx, bf.GET_INDEX)
        self.emit(ctx, bf.STORE_LOCAL, var_slot)
        self.emit(ctx, bf.TRY_END)
        self.bind_loop_var(ctx, lv)
        append(ctx.loops, LoopCtx(ctx.try_depth))
        self.emit_body(ctx, body)
        loop := ctx.loops[len(ctx.loops) - 1]
        ctx.loops = ctx.loops[0:len(ctx.loops) - 1]
        inc := ctx.byte_len
        for f in loop.continue_fixups:
            self.patch(ctx, f, inc)
        self.emit(ctx, bf.LOAD_LOCAL, idx)
        self.emit(ctx, bf.CONST, self.intern(bf.const_int(1)))
        self.emit(ctx, bf.ADD)
        self.emit(ctx, bf.STORE_LOCAL, idx)
        self.emit(ctx, bf.JUMP, start)
        after := ctx.byte_len
        self.patch(ctx, try_begin, after)
        self.emit(ctx, bf.LOAD_LOCAL, exc)
        self.emit(ctx, bf.CONST, self.istr("IndexError"))
        self.emit(ctx, bf.EXC_MATCHES)
        end_it := self.jump_placeholder(ctx, bf.JUMP_FALSE)
        to_end := self.jump_placeholder(ctx, bf.JUMP)
        self.patch(ctx, end_it, ctx.byte_len)
        self.emit(ctx, bf.LOAD_LOCAL, exc)
        self.emit(ctx, bf.THROW)
        self.patch(ctx, to_end, ctx.byte_len)
        if else_body != null:
            self.gen_block(ctx, else_body)
        for f in loop.break_fixups:
            self.patch(ctx, f, ctx.byte_len)
        self.pop_scope(ctx)

    func gen_comprehension(ctx, n):
        is_dict := n.comp_kind == "Dict"
        slot := self.alloc_temp(ctx)
        self.emit(ctx, bf.BUILD_DICT if is_dict else bf.BUILD_LIST, 0)
        self.emit(ctx, bf.STORE_LOCAL, slot)
        self.gen_comp_clauses(ctx, n, 0, slot)
        self.emit(ctx, bf.LOAD_LOCAL, slot)

    func gen_comp_clauses(ctx, n, i, slot):
        if i == len(n.clauses):
            self.emit(ctx, bf.LOAD_LOCAL, slot)
            if n.comp_kind == "Dict":
                self.gen_expr(ctx, n.key)
                self.gen_expr(ctx, n.value)
                self.emit(ctx, bf.SET_INDEX)
            else:
                self.gen_expr(ctx, n.element)
                self.emit(ctx, bf.LIST_APPEND)
                self.emit(ctx, bf.POP)
            return
        c := n.clauses[i]
        if c.clause_kind == "For":
            self.gen_for_loop(ctx, c.variable, c.expr, ["comp", n, i + 1, slot], null)
        else:
            self.gen_expr(ctx, c.expr)
            skip := self.jump_placeholder(ctx, bf.JUMP_FALSE)
            self.gen_comp_clauses(ctx, n, i + 1, slot)
            self.patch(ctx, skip, ctx.byte_len)

    # ------------------------------------------------------------------ match
    func safe_bool_begin(ctx):
        result := self.alloc_temp(ctx)
        tb := len(ctx.instrs)
        self.emit(ctx, bf.TRY_BEGIN, 0, bf.NO_CONST)
        return [result, tb]

    func safe_bool_end(ctx, st):
        self.emit(ctx, bf.STORE_LOCAL, st[0])
        self.emit(ctx, bf.TRY_END)
        after := self.jump_placeholder(ctx, bf.JUMP)
        self.patch(ctx, st[1], ctx.byte_len)
        self.emit(ctx, bf.CONST, self.intern(bf.const_bool(false)))
        self.emit(ctx, bf.STORE_LOCAL, st[0])
        self.patch(ctx, after, ctx.byte_len)
        self.emit(ctx, bf.LOAD_LOCAL, st[0])

    func gen_pattern_test(ctx, value_slot, pat, fails):
        pk := pat.pk
        if pk == "Wildcard" or pk == "Bind":
            return
        if pk == "Literal":
            self.emit(ctx, bf.LOAD_LOCAL, value_slot)
            self.emit(ctx, bf.CONST, self.intern(literal_constant(pat.literal_kind, pat.literal_value)))
            self.emit(ctx, bf.EQ)
            append(fails, self.jump_placeholder(ctx, bf.JUMP_FALSE))
            return
        if pk == "Range":
            st := self.safe_bool_begin(ctx)
            self.emit(ctx, bf.LOAD_LOCAL, value_slot)
            self.emit(ctx, bf.CONST, self.intern(literal_constant(pat.range_low.literal_kind, pat.range_low.literal_value)))
            self.emit(ctx, bf.GE)
            self.safe_bool_end(ctx, st)
            append(fails, self.jump_placeholder(ctx, bf.JUMP_FALSE))
            st2 := self.safe_bool_begin(ctx)
            self.emit(ctx, bf.LOAD_LOCAL, value_slot)
            self.emit(ctx, bf.CONST, self.intern(literal_constant(pat.range_high.literal_kind, pat.range_high.literal_value)))
            self.emit(ctx, bf.LT)
            self.safe_bool_end(ctx, st2)
            append(fails, self.jump_placeholder(ctx, bf.JUMP_FALSE))
            return
        if pk == "EnumVariant":
            en := null
            if pat.enum_type_name in self.enums:
                en = self.enums[pat.enum_type_name]
                if pat.variant_name in en[1]:
                    fields := en[1][pat.variant_name]
                    if len(fields) != len(pat.subpatterns):
                        _cerr("le motif '" + pat.enum_type_name + "." + pat.variant_name + "(...)' a " + str(len(pat.subpatterns)) + " sous-motif(s), la variante en déclare " + str(len(fields)))
            tag := (en[0] if en != null else pat.enum_type_name) + "." + pat.variant_name
            st := self.safe_bool_begin(ctx)
            self.emit(ctx, bf.LOAD_LOCAL, value_slot)
            self.emit(ctx, bf.GET_MEMBER, self.istr("__tag"))
            self.emit(ctx, bf.CONST, self.istr(tag))
            self.emit(ctx, bf.EQ)
            self.safe_bool_end(ctx, st)
            append(fails, self.jump_placeholder(ctx, bf.JUMP_FALSE))
            i := 0
            while i < len(pat.subpatterns):
                sub := self.alloc_temp(ctx)
                self.emit(ctx, bf.LOAD_LOCAL, value_slot)
                self.emit(ctx, bf.GET_MEMBER, self.istr("_" + str(i)))
                self.emit(ctx, bf.STORE_LOCAL, sub)
                self.gen_pattern_test(ctx, sub, pat.subpatterns[i], fails)
                i += 1
            return
        if pk == "List" or pk == "Tuple":
            self.emit(ctx, bf.LOAD_LOCAL, value_slot)
            self.emit(ctx, bf.TYPE_NAME)
            self.emit(ctx, bf.CONST, self.istr("list" if pk == "List" else "tuple"))
            self.emit(ctx, bf.EQ)
            append(fails, self.jump_placeholder(ctx, bf.JUMP_FALSE))
            self.emit(ctx, bf.LOAD_LOCAL, value_slot)
            self.emit(ctx, bf.LEN)
            self.emit(ctx, bf.CONST, self.intern(bf.const_int(len(pat.subpatterns))))
            self.emit(ctx, bf.EQ)
            append(fails, self.jump_placeholder(ctx, bf.JUMP_FALSE))
            i := 0
            while i < len(pat.subpatterns):
                sub := self.alloc_temp(ctx)
                self.emit(ctx, bf.LOAD_LOCAL, value_slot)
                self.emit(ctx, bf.CONST, self.intern(bf.const_int(i)))
                self.emit(ctx, bf.GET_INDEX)
                self.emit(ctx, bf.STORE_LOCAL, sub)
                self.gen_pattern_test(ctx, sub, pat.subpatterns[i], fails)
                i += 1

    func gen_pattern_bind(ctx, value_slot, pat):
        pk := pat.pk
        if pk == "Bind":
            self.emit(ctx, bf.LOAD_LOCAL, value_slot)
            self.gen_decl_store(ctx, pat.name)
        elif pk == "EnumVariant":
            i := 0
            while i < len(pat.subpatterns):
                sub := self.alloc_temp(ctx)
                self.emit(ctx, bf.LOAD_LOCAL, value_slot)
                self.emit(ctx, bf.GET_MEMBER, self.istr("_" + str(i)))
                self.emit(ctx, bf.STORE_LOCAL, sub)
                self.gen_pattern_bind(ctx, sub, pat.subpatterns[i])
                i += 1
        elif pk == "List" or pk == "Tuple":
            i := 0
            while i < len(pat.subpatterns):
                sub := self.alloc_temp(ctx)
                self.emit(ctx, bf.LOAD_LOCAL, value_slot)
                self.emit(ctx, bf.CONST, self.intern(bf.const_int(i)))
                self.emit(ctx, bf.GET_INDEX)
                self.emit(ctx, bf.STORE_LOCAL, sub)
                self.gen_pattern_bind(ctx, sub, pat.subpatterns[i])
                i += 1

    func gen_match(ctx, n):
        self.gen_expr(ctx, n.subject)
        subj := self.alloc_temp(ctx)
        self.emit(ctx, bf.STORE_LOCAL, subj)
        ends := []
        for c in n.cases:
            self.push_scope(ctx)
            fails := []
            self.gen_pattern_test(ctx, subj, c.pattern, fails)
            self.gen_pattern_bind(ctx, subj, c.pattern)
            if c.guard != null:
                self.gen_expr(ctx, c.guard)
                append(fails, self.jump_placeholder(ctx, bf.JUMP_FALSE))
            self.gen_block(ctx, c.body)
            append(ends, self.jump_placeholder(ctx, bf.JUMP))
            self.pop_scope(ctx)
            for f in fails:
                self.patch(ctx, f, ctx.byte_len)
        for e in ends:
            self.patch(ctx, e, ctx.byte_len)

    # ------------------------------------------------------------------ try / finally
    # tail : ["break"], ["continue"] ou ["return", slot]
    func unwind_finallies(ctx, min_loop_depth, tail):
        saved_stack := [f for f in ctx.finally_stack]
        saved_depth := ctx.try_depth
        while len(ctx.finally_stack) > 0 and ctx.finally_stack[len(ctx.finally_stack) - 1][2] >= min_loop_depth:
            f := ctx.finally_stack[len(ctx.finally_stack) - 1]
            ctx.finally_stack = ctx.finally_stack[0:len(ctx.finally_stack) - 1]
            k := f[1]
            while k < ctx.try_depth:
                self.emit(ctx, bf.TRY_END)
                k += 1
            ctx.try_depth = f[1]
            self.gen_block(ctx, f[0])
        if tail[0] == "return":
            self.emit(ctx, bf.LOAD_LOCAL, tail[1])
            self.emit(ctx, bf.RETURN)
        else:
            loop := ctx.loops[len(ctx.loops) - 1]
            k := loop.try_depth_at_entry
            while k < ctx.try_depth:
                self.emit(ctx, bf.TRY_END)
                k += 1
            fix := self.jump_placeholder(ctx, bf.JUMP)
            if tail[0] == "break":
                append(loop.break_fixups, fix)
            else:
                append(loop.continue_fixups, fix)
        ctx.finally_stack = saved_stack
        ctx.try_depth = saved_depth

    func gen_try(ctx, n):
        has_finally := n.finally_block != null
        fbegin := 0
        fexc := bf.NO_CONST
        if has_finally:
            fexc = self.alloc_temp(ctx)
            fbegin = len(ctx.instrs)
            self.emit(ctx, bf.TRY_BEGIN, 0, fexc)
            append(ctx.finally_stack, [n.finally_block, ctx.try_depth, len(ctx.loops)])
            ctx.try_depth += 1
        if len(n.catch_clauses) == 0:
            self.gen_block(ctx, n.try_block)
        else:
            self.gen_try_catch(ctx, n)
        if has_finally:
            ctx.try_depth -= 1
            ctx.finally_stack = ctx.finally_stack[0:len(ctx.finally_stack) - 1]
            self.emit(ctx, bf.TRY_END)
            self.gen_block(ctx, n.finally_block)
            to_end := self.jump_placeholder(ctx, bf.JUMP)
            self.patch(ctx, fbegin, ctx.byte_len)
            self.gen_block(ctx, n.finally_block)
            self.emit(ctx, bf.LOAD_LOCAL, fexc)
            self.emit(ctx, bf.THROW)
            self.patch(ctx, to_end, ctx.byte_len)

    func gen_try_catch(ctx, n):
        tb := len(ctx.instrs)
        exc := self.alloc_temp(ctx)
        self.emit(ctx, bf.TRY_BEGIN, 0, exc)
        ctx.try_depth += 1
        self.gen_block(ctx, n.try_block)
        ctx.try_depth -= 1
        self.emit(ctx, bf.TRY_END)
        to_end := [self.jump_placeholder(ctx, bf.JUMP)]
        self.patch(ctx, tb, ctx.byte_len)
        has_generic := false
        for c in n.catch_clauses:
            saved_line := ctx.cur_line
            if c.line > 0:
                ctx.cur_line = c.line
            to_next := -1
            if len(c.types) > 0:
                to_body := []
                for t in c.types:
                    self.emit(ctx, bf.LOAD_LOCAL, exc)
                    self.emit(ctx, bf.CONST, self.istr(t))
                    self.emit(ctx, bf.EXC_MATCHES)
                    skip := self.jump_placeholder(ctx, bf.JUMP_FALSE)
                    append(to_body, self.jump_placeholder(ctx, bf.JUMP))
                    self.patch(ctx, skip, ctx.byte_len)
                to_next = self.jump_placeholder(ctx, bf.JUMP)
                for b in to_body:
                    self.patch(ctx, b, ctx.byte_len)
            else:
                has_generic = true
            self.push_scope(ctx)
            if c.name != null:
                if c.name in ctx.captured:
                    bs := ctx.next_local
                    ctx.next_local += 1
                    self.bind_var(ctx, c.name, Var(bs, true, true))
                    self.emit(ctx, bf.LOAD_LOCAL, exc)
                    self.emit(ctx, bf.NEW_CELL, bs)
                else:
                    self.bind_var(ctx, c.name, Var(exc, false, true))
            self.gen_block(ctx, c.body)
            self.pop_scope(ctx)
            append(to_end, self.jump_placeholder(ctx, bf.JUMP))
            if to_next >= 0:
                self.patch(ctx, to_next, ctx.byte_len)
            ctx.cur_line = saved_line
            if has_generic:
                break
        if not has_generic:
            self.emit(ctx, bf.LOAD_LOCAL, exc)
            self.emit(ctx, bf.THROW)
        for e in to_end:
            self.patch(ctx, e, ctx.byte_len)

func compile(program, options=null):
    opts := options if options != null else CompileOptions()
    return Compiler(opts).compile_program(program)

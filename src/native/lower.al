# ALEX — native.lower
#
# Abaissement AST -> IR du compilateur natif écrit en ALEX (étape C) : portage fidèle de src/NativeLower.cpp.
# Sous-ensemble statique typé du backend natif : int, float, bool, str, char, list[T], dict[K, V], tuples, T?,
# struct / class (héritage, interfaces, répartition dynamique), enums et match, fonctions typées ou génériques
# (spécialisées par signature d'appel), fonctions comme valeurs et fermetures (cellules), async / await,
# try / catch / finally, compréhensions, f-strings, intrinsèques du runtime (__load64, __syscall...).
# Le runtime natif (écrit en Alex, runtime/alex/native/source.al) est abaissé dans le même programme ;
# seules les fonctions atteignables sont gardées.
#
#   use native.lower as nl
#   prog := nl.lower(modules, runtime_program)    # modules : [SourceModule], dépendances d'abord
#
# Erreurs : NativeError (constructions hors du sous-ensemble natif, toutes listées « fichier:ligne:col: … »).

from core use len, type
from collections use append
use string as _s
use _native_net as _n
use native.ir as ir
use ast as _a
use semantic.types as _bt

# Genres de types (enum Kind du C++, même ordre).
const K_VOID := 0
const K_INT := 1
const K_BOOL := 2
const K_FLOAT := 3
const K_STR := 4
const K_LIST := 5
const K_STRUCT := 6
const K_NULL := 7
const K_NULLABLE := 8
const K_DICT := 9
const K_EXC := 10
const K_FUNC := 11
const K_TUPLE := 12
const K_ENUM := 13
const K_CHAR := 14
const K_FUTURE := 15

const TVOID := 0
const TINT := 1
const TBOOL := 2
const TFLOAT := 3
const TSTR := 4
const TNULL := 5
const TEXC := 6
const TCHAR := 7

const RUNTIME_FILE := "<runtime natif>"

const INT_OPS := {"Add": ir.ADD, "Sub": ir.SUB, "Mul": ir.MUL, "FloorDiv": ir.FLOORDIV, "Mod": ir.MOD,
    "Pow": ir.POW, "Eq": ir.EQ, "Ne": ir.NE, "Lt": ir.LT, "Le": ir.LE, "Gt": ir.GT, "Ge": ir.GE,
    "BitAnd": ir.AND, "BitOr": ir.OR, "BitXor": ir.XOR, "Shl": ir.SHL, "Shr": ir.SHR}
const CMP_OPS := {"Eq": ir.EQ, "Ne": ir.NE, "Lt": ir.LT, "Le": ir.LE, "Gt": ir.GT, "Ge": ir.GE}

const IMPORT_ALLOWED := {"core": {"len": true, "to_int": true, "to_float": true},
    "collections": {"append": true, "keys": true, "values": true, "get": true, "contains_key": true, "remove": true,
    "set": true, "clear": true}}

func float_bits(d):
    return _n.f64_bits(d)


# Cible Alex OS (alexc build --native --alexos) : exécutable AEX, aucune bibliothèque partagée ; __alexos() vrai.
_alexos := [false]

func set_alexos(on):
    _alexos[0] = on

class SourceModule:
    func init(program, file, imports=null):
        self.program = program
        self.file = file
        self.imports = imports if imports != null else {}    # uid de l'ImportStmt -> indice du module
        self.inline = false     # « # alex: inline » : petites fonctions feuilles intégrées comme celles du runtime

class Val:
    func init(reg=-1, ty=0, bad=false):
        self.reg = reg
        self.ty = ty
        self.bad = bad

class Var:
    func init(ty, glob, index):
        self.ty = ty
        self.glob = glob
        self.index = index
        self.view = false
        self.o_ty = -1
        self.o_glob = false
        self.o_index = -1
        self.boxed = false
        self.o_boxed = false

    func copy():
        v := Var(self.ty, self.glob, self.index)
        v.view = self.view
        v.o_ty = self.o_ty
        v.o_glob = self.o_glob
        v.o_index = self.o_index
        v.boxed = self.boxed
        v.o_boxed = self.o_boxed
        return v

    func original():
        o := Var(self.o_ty, self.o_glob, self.o_index)
        o.boxed = self.o_boxed
        return o

class StructInfo:
    func init():
        self.name = ""
        self.ty = -1
        self.decl = null
        self.body = null
        self.is_interface = false
        self.base = -1
        self.ifaces = []
        self.resolved = false
        self.fields = []
        self.field_ty = []
        self.defaults = []
        self.field_index = {}
        self.methods = {}
        self.method_order = []    # ordre d'insertion des méthodes (diagnostics)

class Fn:
    func init():
        self.id = 0
        self.decl = null
        self.name = ""
        self.names = []
        self.params = []
        self.ret = TVOID
        self.owner = -1
        self.runtime = false
        self.abstract = false
        self.module = 0
        self.generic = false
        self.is_async = false
        self.index = 0

class ModInfo:
    func init():
        self.inline = false
        self.prefix = ""
        self.name = ""
        self.file = 0
        self.stdlib = false
        self.ns = {}
        self.frm = {}
        self.resolved = {}

class EnumVariant:
    func init():
        self.name = ""
        self.fields = []
        self.field_ty = []
        self.ann = []

class EnumInfo:
    func init():
        self.name = ""
        self.ty = -1
        self.decl = null
        self.variants = []

class Loop:
    func init(brk, cont, tries):
        self.brk = brk
        self.cont = cont
        self.tries = tries

func _is_raise(s):
    if s.kind != "ExpressionStmt":
        return false
    e := s.expr
    return e.kind == "CallExpr" and e.callee.kind == "Identifier" and e.callee.name == "raise"

func _exports(p, name):
    for s in p.top_level:
        k := s.kind
        if k == "FunctionDecl" or k == "ConstDecl" or k == "VariableDecl" or k == "StructDecl" or k == "ClassDecl" or k == "InterfaceDecl" or k == "EnumDecl":
            if s.name == name:
                return true
    return false

func join_diags(file, d):
    s := "NativeError: " + _diag_at(file, d[0])
    i := 1
    while i < len(d):
        s += "\n  " + _diag_at(file, d[i])
        i += 1
    return s

func _diag_at(file, x):
    return (file if x[3] == "" else x[3]) + ":" + str(x[0]) + ":" + str(x[1]) + ": " + x[2]

func _diag_less(a, b):
    if a[3] != b[3]:
        return _str_less(a[3], b[3])
    if a[0] != b[0]:
        return a[0] < b[0]
    return a[1] < b[1]

# Ordre lexicographique des octets (std::string::operator<).
func _str_less(x, y):
    bx := _s.byte_unpack(x)
    by := _s.byte_unpack(y)
    i := 0
    while i < len(bx) and i < len(by):
        if bx[i] != by[i]:
            return bx[i] < by[i]
        i += 1
    return len(bx) < len(by)

# Tri stable par insertion (std::stable_sort).
func _stable_sort(xs, less):
    out := []
    for x in xs:
        j := len(out)
        append(out, x)
        while j > 0 and less(x, out[j - 1]):
            out[j] = out[j - 1]
            j -= 1
        out[j] = x
    return out

func _sorted_strings(names):
    return _stable_sort(names, _str_less)

func _starts(s, p):
    return _s.starts_with(s, p)

func _hexval(ch):
    if ch >= 0x30 and ch <= 0x39:
        return ch - 0x30
    if ch >= 0x61 and ch <= 0x66:
        return ch - 0x61 + 10
    if ch >= 0x41 and ch <= 0x46:
        return ch - 0x41 + 10
    return -1

# Intrinsèques « simples » : nom -> [arité, types, opération, type du résultat, imm] (ordre des tests du C++
# respecté par groupes : les noms sont disjoints, l'ordre n'influe que sur la priorité, sans recouvrement).
const SIMPLE_INTRINSICS := {"__mmap": [1, [1], 62, 1, 0], "__munmap": [2, [1, 1], 63, 0, 0], "__sp": [0, [], 64, 1, 0],
    "__stack_top": [0, [], 65, 1, 0], "__save_regs": [0, [], 66, 1, 0], "__globals_start": [0, [], 67, 1, 0],
    "__globals_end": [0, [], 68, 1, 0], "__zero": [2, [1, 1], 69, 0, 0], "__unwind": [1, [1], 73, 0, 0],
    "__handler_top": [0, [], 74, 1, 0], "__frame": [0, [], 75, 1, 0], "__flush": [0, [], 76, 0, 0],
    "__exit": [1, [1], 77, 0, 0], "__load64": [1, [1], 43, 1, 0], "__load8": [1, [1], 45, 1, 0],
    "__store64": [2, [1, 1], 44, 0, 0], "__store8": [2, [1, 1], 46, 0, 0], "__int_to_str": [1, [1], 51, 4, 0],
    "__fail": [1, [4], 56, 0, 0], "__write_err": [1, [4], 57, 0, 0], "__code_base": [0, [], 58, 1, 0],
    "__trace_info": [0, [], 59, 1, 0], "__argv_base": [0, [], 60, 1, 0]}
const PORTS_OUT := {"__outb": 1, "__outw": 2, "__outl": 4}
const PORTS_IN := {"__inb": 1, "__inw": 2, "__inl": 4}
const SIMPLE_INTRINSICS_2 := {"__irq_save": [0, [], 83, 1, 4], "__cr2": [0, [], 83, 1, 6], "__cr3": [0, [], 83, 1, 7],
    "__invlpg": [1, [1], 83, 0, 8], "__fiber_entry": [0, [], 84, 1, 0], "__f2i": [1, [3], 33, 1, 0],
    "__i2f": [1, [1], 32, 3, 0], "__fsqrt": [1, [3], 95, 3, 0]}
const SIMPLE_INTRINSICS_3 := {"__enter_user_frame": [2, [1, 1], 86, 1, 1], "__leave_user": [2, [1, 1], 87, 0, 0],
    "__set_cr3": [1, [1], 83, 0, 9], "__cpu_local": [0, [], 83, 1, 10], "__rdmsr": [1, [1], 83, 1, 11],
    "__wrmsr": [2, [1, 1], 83, 0, 12], "__ap_entry": [0, [], 83, 1, 13], "__ap_trampoline": [0, [], 83, 1, 14],
    "__smp": [0, [], 83, 1, 15], "__xadd": [2, [1, 1], 83, 1, 17], "__park": [2, [1, 1], 83, 0, 18],
    "__gc_park": [0, [], 83, 0, 20], "__gc_ipi": [0, [], 83, 0, 21], "__apic_eoi": [0, [], 83, 0, 22],
    "__bkl_take": [0, [], 83, 0, 23], "__bkl_drop": [0, [], 83, 0, 24], "__bkl_held": [0, [], 83, 2, 25],
    "__fxsave": [1, [1], 83, 0, 26], "__fxrstor": [1, [1], 83, 0, 27], "__cpu_kstack": [1, [1], 83, 0, 19],
    "__switch": [2, [1, 1], 85, 0, 0]}
const CPU_SIMPLE := {"__hlt": 0, "__cli": 1, "__sti": 2, "__pause": 3}
const SIMPLE_INTRINSICS_4 := {"__load16": [1, [1], 88, 1, 0], "__load32": [1, [1], 89, 1, 0],
    "__store16": [2, [1, 1], 90, 0, 0], "__store32": [2, [1, 1], 91, 0, 0]}
const CASTS := {"__str_addr": [4, 1], "__as_str": [1, 4], "__f2bits": [3, 1], "__bits2f": [1, 3],
    "__char_code": [7, 1], "__code_char": [1, 7]}


class Lowerer:
    func init(file):
        self.file = file
        self.prog = ir.IrProgram()
        self.prog.messages = ["ZeroDivisionError: division entière par zéro (int // 0)",
            "ZeroDivisionError: modulo par zéro (int % 0)",
            "TypeError: décalage hors limites (0..63) pour '<<'",
            "TypeError: décalage hors limites (0..63) pour '>>'",
            "RecursionError: profondeur d'appel maximale dépassée (100000)",
            "ValueError: exposant négatif dans '**' : le résultat serait un float (non supporté en natif)",
            "ZeroDivisionError: division par zéro (int / 0)",
            "ZeroDivisionError: division par zéro (float)",
            "ZeroDivisionError: division entière par zéro (float)",
            "ZeroDivisionError: modulo par zéro (float)",
            "MemoryError: mémoire épuisée",
            "KeyError: clé absente du dictionnaire (§10)"]
        self.types = [[K_VOID, -1, -1, -1], [K_INT, -1, -1, -1], [K_BOOL, -1, -1, -1], [K_FLOAT, -1, -1, -1],
            [K_STR, -1, -1, -1], [K_NULL, -1, -1, -1], [K_EXC, -1, -1, -1], [K_CHAR, -1, -1, -1]]
        self.type_index = {}
        i := 0
        while i < len(self.types):
            t := self.types[i]
            self.type_index[self._tkey(t[0], t[1], t[2], t[3])] = i
            i += 1
        self.freestanding = false
        self.uefi = false
        self.windows = false
        self.a64 = false
        self.dyn = false
        self.extend = null
        self.box_names = {}
        self.thunks = {}
        self.failed_locals = {}
        self.specs = {}
        self.async_thunks = {}
        self.uses_async = false
        self.want_ = -1
        self.cur_owner = -1
        self.tries = []
        self.diags = []
        self.structs = []
        self.struct_by_name = {}
        self.fns = []
        self.fn_by_name = {}
        self.imported = {}
        self.mods = []
        self.mod_ = 0
        self.entry_mod = 0
        self.scopes = []
        self.fn_scope_base = 0
        self.fn_ = null
        self.ret_ty = TVOID
        self.fn_name = ""
        self.in_main = false
        self.in_runtime = false
        self.cur_line = 0
        self.loops = []
        self.str_index = {}
        self.sigs = []
        self.sig_index = {}
        self.enums = []
        self.enum_by_name = {}

    # ------------------------------------------------------------------ outils
    func _tkey(k, e, s, v):
        return str(k) + "," + str(e) + "," + str(s) + "," + str(v)

    func find_method(sid, name):
        c := sid
        while c >= 0:
            st := self.structs[c]
            if name in st.methods:
                return st.methods[name]
            c = st.base
        return -1

    func is_sub(a, b):
        c := a
        while c >= 0:
            if c == b:
                return true
            for i in self.structs[c].ifaces:
                if i == b:
                    return true
            c = self.structs[c].base
        return false

    func concrete_subs(sid):
        out := []
        c := 0
        while c < len(self.structs):
            if not self.structs[c].is_interface and self.is_sub(c, sid):
                append(out, c)
            c += 1
        return out

    func sid_of(ty):
        return self.types[ty][2]

    func qual(n):
        return self.mods[self.mod_].prefix + n

    # Clé d'un nom vu depuis le module courant (dict table), ou null.
    func resolve_key(table, name):
        m := self.mods[self.mod_]
        dot := _s.find(name, ".")
        if dot >= 0:
            pre := _s.substring(name, 0, dot)
            if not (pre in m.ns):
                return null
            buf := self.mods[m.ns[pre]].prefix + _s.substring(name, dot + 1, len(name))
            return buf if buf in table else null
        buf := m.prefix + name
        if buf in table:
            return buf
        if name in m.frm and (m.frm[name] in table):
            return m.frm[name]
        return null

    func find_fn(name):
        k := self.resolve_key(self.fn_by_name, name)
        return self.fn_by_name[k] if k != null else -1

    func find_struct(name):
        k := self.resolve_key(self.struct_by_name, name)
        return self.struct_by_name[k] if k != null else -1

    func find_enum(name):
        k := self.resolve_key(self.enum_by_name, name)
        return self.enum_by_name[k] if k != null else -1

    func module_of(e):
        if e.kind != "Identifier":
            return -1
        if self.lookup(e.name) != null:
            return -1
        m := self.mods[self.mod_]
        return m.ns[e.name] if e.name in m.ns else -1

    func enum_of(e):
        if e.kind != "Identifier":
            return -1
        return -1 if self.lookup(e.name) != null else self.find_enum(e.name)

    # ------------------------------------------------------------------ diagnostics
    func error(at, msg):
        if not self.in_runtime:
            self.error_at(at.line, at.column, msg)
        else:
            append(self.diags, [at.line, at.column, "runtime natif : " + msg, ""])

    func error_at(line, col, msg):
        f := ""
        if len(self.mods) > 0 and self.mod_ != self.entry_mod:
            f = self.prog.files[self.mods[self.mod_].file]
        append(self.diags, [line, col, msg, f])

    func bad():
        return Val(-1, TVOID, true)

    func unsupported(at, what):
        self.error(at, "non supporté en natif : " + what)
        return self.bad()

    # ------------------------------------------------------------------ types
    func kind(t):
        return self.types[t][0]

    func elem_of(t):
        return self.types[t][1]

    func val_of(t):
        return self.types[t][3]

    func intern(k, e=-1, s=-1, v=-1):
        key := self._tkey(k, e, s, v)
        if key in self.type_index:
            return self.type_index[key]
        append(self.types, [k, e, s, v])
        idx := len(self.types) - 1
        self.type_index[key] = idx
        return idx

    func push_type(k, e, s):
        # types_.push_back sans internement (structs, enums) : la clé n'est enregistrée que si elle est nouvelle
        append(self.types, [k, e, s, -1])
        idx := len(self.types) - 1
        key := self._tkey(k, e, s, -1)
        if not (key in self.type_index):
            self.type_index[key] = idx
        return idx

    func list_of(elem):
        return self.intern(K_LIST, elem)

    func future_of(elem):
        return self.intern(K_FUTURE, elem)

    func _sig(params):
        key := _s.join(",", [str(p) for p in params])
        if key in self.sig_index:
            return self.sig_index[key]
        append(self.sigs, [p for p in params])
        k := len(self.sigs) - 1
        self.sig_index[key] = k
        return k

    func func_of(params, ret):
        return self.intern(K_FUNC, -1, self._sig(params), ret)

    func tuple_of(elems):
        return self.intern(K_TUPLE, -1, self._sig(elems), -1)

    func elems_of(t):
        return self.sigs[self.types[t][2]]

    func tuple_elem(t):
        es := self.elems_of(t)
        for e in es:
            if e != es[0]:
                return -1
        return -1 if len(es) == 0 else es[0]

    func params_of(t):
        return self.sigs[self.types[t][2]]

    func dict_of(k, v):
        return self.intern(K_DICT, k, -1, v)

    func nullable_of(t):
        k := self.kind(t)
        if k == K_NULLABLE or k == K_NULL or k == K_VOID:
            return t
        return self.intern(K_NULLABLE, t)

    func unnull(t):
        return self.elem_of(t) if t >= 0 and self.kind(t) == K_NULLABLE else t

    func is_scalar(t):
        return t == TINT or t == TFLOAT or t == TBOOL or t == TCHAR

    func is_num(t):
        return t == TINT or t == TFLOAT

    func wrap(v):
        if not self.is_scalar(v.ty):
            return v.reg
        box := self.rt("__rt_alloc", [self.constant(8), self.constant(1)])
        self.emit_op(ir.STORE64, -1, box, v.reg, 0)
        return box

    func unwrap(r, nullable_ty):
        if not self.is_scalar(self.elem_of(nullable_ty)):
            return r
        x := self.reg()
        self.emit_op(ir.LOAD64, x, r, -1, 0)
        return x

    func key_kind(t):
        return 1 if t == TSTR else 2 if t == TFLOAT else 0

    func ty_name(t):
        k := self.kind(t)
        if k == K_VOID:
            return "null"
        if k == K_INT:
            return "int"
        if k == K_BOOL:
            return "bool"
        if k == K_FLOAT:
            return "float"
        if k == K_STR:
            return "str"
        if k == K_LIST:
            return "list[" + self.ty_name(self.elem_of(t)) + "]"
        if k == K_STRUCT:
            return self.structs[self.types[t][2]].name
        if k == K_NULL:
            return "null"
        if k == K_NULLABLE:
            return self.ty_name(self.elem_of(t)) + "?"
        if k == K_DICT:
            return "dict[" + self.ty_name(self.elem_of(t)) + ", " + self.ty_name(self.val_of(t)) + "]"
        if k == K_EXC:
            return "Exception"
        if k == K_CHAR:
            return "char"
        if k == K_FUTURE:
            return "future[" + ("null" if self.elem_of(t) == TVOID else self.ty_name(self.elem_of(t))) + "]"
        if k == K_ENUM:
            return self.enums[self.types[t][2]].name
        if k == K_TUPLE:
            return "tuple[" + _s.join(", ", [self.ty_name(e) for e in self.elems_of(t)]) + "]"
        if k == K_FUNC:
            s := "func(" + _s.join(", ", [self.ty_name(p) for p in self.sigs[self.types[t][2]]]) + ")"
            if self.val_of(t) != TVOID:
                s += " -> " + self.ty_name(self.val_of(t))
            return s
        return "?"

    func type_of(t, allow_void=false):
        base := self.type_of_base(t, allow_void)
        if base < 0 or not t.nullable:
            return base
        return -1 if base == TVOID else self.nullable_of(base)

    func type_of_base(t, allow_void):
        n := len(t.args)
        if t.name == "func" and n > 0:
            ps := []
            i := 0
            while i + 1 < n:
                p := self.type_of(t.args[i])
                if p < 0:
                    return -1
                append(ps, p)
                i += 1
            r := t.args[n - 1]
            ret := TVOID if r.name == "any" else self.type_of(r, true)
            if ret < 0:
                return -1
            return self.func_of(ps, ret)
        if t.name == "dict" and n == 2:
            k := self.type_of(t.args[0])
            v := self.type_of(t.args[1])
            if k < 0 or v < 0 or not (self.is_scalar(k) or k == TSTR):
                return -1
            return self.dict_of(k, v)
        if t.name == "future" and n == 1:
            e := self.type_of(t.args[0], true)
            return -1 if e < 0 else self.future_of(e)
        if t.name == "tuple" and n > 0:
            es := []
            for a in t.args:
                e := self.type_of(a)
                if e < 0:
                    return -1
                append(es, e)
            return self.tuple_of(es)
        if t.name == "list" and n == 1:
            e := self.type_of(t.args[0])
            return -1 if e < 0 else self.list_of(e)
        if n > 0:
            return -1
        nm := t.name
        if nm == "int" or nm == "i64":
            return TINT
        if nm == "float" or nm == "f64":
            return TFLOAT
        if nm == "bool":
            return TBOOL
        if nm == "str":
            return TSTR
        if nm == "char":
            return TCHAR
        if nm == "null" and allow_void:
            return TVOID
        sid := self.find_struct(nm)
        if sid >= 0:
            return self.structs[sid].ty
        eid := self.find_enum(nm)
        return self.enums[eid].ty if eid >= 0 else -1

    func expect_type(e, v, want, what):
        if v.bad:
            return false
        if v.ty == want:
            return true
        if self.kind(v.ty) == K_STRUCT and self.kind(want) == K_STRUCT and self.is_sub(self.sid_of(v.ty), self.sid_of(want)):
            v.ty = want
            return true
        if self.kind(want) == K_NULLABLE and self.kind(v.ty) == K_STRUCT and self.kind(self.elem_of(want)) == K_STRUCT and self.is_sub(self.sid_of(v.ty), self.sid_of(self.elem_of(want))):
            v.ty = want
            return true
        if self.kind(want) == K_NULLABLE:
            if v.ty == TNULL:
                v.reg = self.constant(0)
                v.ty = want
                v.bad = false
                return true
            if v.ty == self.elem_of(want):
                v.reg = self.wrap(v)
                v.ty = want
                v.bad = false
                return true
        hint := ""
        if want == TFLOAT and v.ty == TINT:
            hint = " (en natif, un int n'est pas converti implicitement : écrire 3.0 ou to_float(…))"
        self.error(e, what + " : attendu " + self.ty_name(want) + ", obtenu " + self.ty_name(v.ty) + hint)
        return false

    # ------------------------------------------------------------------ émission
    func reg():
        r := self.fn_.vregs
        self.fn_.vregs = r + 1
        return r

    func label():
        l := self.fn_.labels
        self.fn_.labels = l + 1
        return l

    func emit(i):
        i.line = self.cur_line
        append(self.fn_.code, i)

    func emit_op(op, dst, a=-1, b=-1, imm=0):
        i := ir.Ins(op)
        i.dst = dst
        i.a = a
        i.b = b
        i.imm = imm
        self.emit(i)

    func place(l):
        i := ir.Ins(ir.LABEL)
        i.label = l
        self.emit(i)

    func jump(op, l, a=-1):
        i := ir.Ins(op)
        i.label = l
        i.a = a
        self.emit(i)

    func constant(v):
        r := self.reg()
        self.emit_op(ir.CONST, r, -1, -1, v)
        return r

    func message(m):
        append(self.prog.messages, m)
        return len(self.prog.messages) - 1

    func str_index_of(s):
        if s in self.str_index:
            return self.str_index[s]
        idx := len(self.prog.strings)
        append(self.prog.strings, _s.byte_unpack(s))
        self.str_index[s] = idx
        return idx

    func str_const(s):
        idx := self.str_index_of(s)
        r := self.reg()
        self.emit_op(ir.STR_CONST, r, -1, -1, idx)
        return r

    func rt(name, args, has_result=true):
        f := self.fns[self.fn_by_name[name]]
        i := ir.Ins(ir.CALL)
        i.callee = f.id
        i.args = args
        i.dst = self.reg() if has_result else -1
        d := i.dst
        self.emit(i)
        return d

    func fail_if(cond, msg):
        ok := self.label()
        self.jump(ir.JMP_IF_ZERO, ok, cond)
        self.emit_op(ir.FAIL, -1, -1, -1, msg)
        self.place(ok)

    func list_len(lst):
        n := self.reg()
        self.emit_op(ir.LOAD64, n, lst, -1, 0)
        return n

    func list_data(lst):
        d := self.reg()
        self.emit_op(ir.LOAD64, d, lst, -1, 16)
        return d

    func bounds_check(index, ln):
        i := ir.Ins(ir.BOUNDS_CHECK)
        i.a = index
        i.b = ln
        i.callee = self.fns[self.fn_by_name["__rt_index_error"]].id
        self.emit(i)

    func norm_index(idx, ln):
        r := self.reg()
        neg := self.reg()
        skip := self.label()
        self.emit_op(ir.COPY, r, idx)
        self.emit_op(ir.LT, neg, idx, self.constant(0))
        self.jump(ir.JMP_IF_ZERO, skip, neg)
        self.emit_op(ir.ADD, r, idx, ln)
        self.place(skip)
        return r

    func dict_index(d, key):
        return self.rt("__rt_dict_index", [d, key.reg, self.constant(self.key_kind(key.ty))])

    func leave_tries(keep):
        saved := [t for t in self.tries]
        while len(self.tries) > keep:
            t := self.tries[len(self.tries) - 1]
            self.tries = self.tries[0:len(self.tries) - 1]
            e := ir.Ins(ir.TRY_END)
            e.a = t[0]
            self.emit(e)
            if t[1] != null:
                append(self.scopes, {})
                self.statements(t[1].statements)
                self.scopes = self.scopes[0:len(self.scopes) - 1]
        self.tries = saved

    func handler_record():
        top := -1
        i := 0
        while i < 9:
            top = self.reg()
            i += 1
        return top

    func push_scope():
        append(self.scopes, {})

    func pop_scope():
        self.scopes = self.scopes[0:len(self.scopes) - 1]

    # ------------------------------------------------------------------ variables
    # [portée, clé] de la variable visible, ou null.
    func lookup_slot(name):
        i := len(self.scopes)
        lim := self.fn_scope_base if self.fn_scope_base > 1 else 1
        while i > lim:
            if name in self.scopes[i - 1]:
                return [self.scopes[i - 1], name]
            i -= 1
        if self.in_runtime:
            return null
        k := self.resolve_key(self.scopes[0], name)
        return [self.scopes[0], k] if k != null else null

    func lookup(name):
        sl := self.lookup_slot(name)
        return sl[0][sl[1]] if sl != null else null

    func read(v):
        if v.boxed:
            r := self.reg()
            self.emit_op(ir.LOAD64, r, v.index, -1, 0)
            return Val(r, v.ty)
        if not v.glob:
            return Val(v.index, v.ty)
        r := self.reg()
        self.emit_op(ir.LOAD_GLOBAL, r, -1, -1, v.index)
        return Val(r, v.ty)

    func write(v, r):
        if v.view:
            self.emit_op(ir.COPY, v.index, r)
            self.write(v.original(), self.wrap(Val(r, v.ty)))
            return
        if v.boxed:
            self.emit_op(ir.STORE64, -1, v.index, r, 0)
            return
        if v.glob:
            self.emit_op(ir.STORE_GLOBAL, -1, r, -1, v.index)
        else:
            self.emit_op(ir.COPY, v.index, r)

    func narrow(name):
        v := self.lookup(name)
        if v == null or self.kind(v.ty) != K_NULLABLE:
            return
        orig := v.copy()
        cur := self.read(orig)
        view := Var(self.elem_of(orig.ty), false, self.reg())
        view.view = true
        view.o_ty = orig.ty
        view.o_glob = orig.glob
        view.o_index = orig.index
        view.o_boxed = orig.boxed
        self.emit_op(ir.COPY, view.index, self.unwrap(cur.reg, orig.ty))
        self.scopes[len(self.scopes) - 1][name] = view

    # [identifiant, non_null] ou null
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
        return [other, cond.op == "Ne"]

    func statements(lst):
        for s in lst:
            self.stmt(s)
            if s.kind != "IfStmt":
                continue
            nt := self.null_test(s.condition)
            if nt == null or nt[1] or len(s.elif_clauses) > 0 or s.else_block != null or len(s.then_block.statements) == 0:
                continue
            last := s.then_block.statements[len(s.then_block.statements) - 1]
            lk := last.kind
            if lk == "ReturnStmt" or lk == "BreakStmt" or lk == "ContinueStmt" or _is_raise(last):
                self.narrow(nt[0].name)

    func declare(name, ty, value_reg):
        v := Var(ty, self.in_main and len(self.scopes) == 1, 0)
        if not v.glob and (name in self.box_names):
            v.boxed = true
            v.index = self.rt("__rt_alloc", [self.constant(8), self.constant(0)])
        else:
            if v.glob:
                v.index = self.prog.globals
                self.prog.globals += 1
            else:
                v.index = self.reg()
        self.write(v, value_reg)
        self.scopes[len(self.scopes) - 1][self.qual(name) if v.glob else name] = v

    # ------------------------------------------------------------------ conversions
    func to_float(v):
        if v.ty == TFLOAT:
            return v.reg
        r := self.reg()
        self.emit_op(ir.INT_TO_FLOAT, r, v.reg)
        return r

    func truthy(at, v):
        if v.bad:
            return self.constant(0)
        k := self.kind(v.ty)
        if k == K_INT or k == K_BOOL:
            return v.reg
        if k == K_FLOAT:
            r := self.reg()
            self.emit_op(ir.FNE, r, v.reg, self.constant(float_bits(0.0)))
            return r
        if k == K_STR:
            p := self.reg()
            self.emit_op(ir.LOAD64, p, v.reg, -1, 0)
            return p
        if k == K_LIST or k == K_DICT or k == K_STRUCT or k == K_EXC or k == K_TUPLE or k == K_CHAR or k == K_FUTURE or k == K_ENUM or k == K_FUNC:
            return self.constant(1)
        if k == K_NULL:
            return self.constant(0)
        if k == K_NULLABLE:
            r := self.reg()
            l_end := self.label()
            self.emit_op(ir.COPY, r, v.reg)
            self.jump(ir.JMP_IF_ZERO, l_end, v.reg)
            self.emit_op(ir.COPY, r, self.truthy(at, Val(self.unwrap(v.reg, v.ty), self.elem_of(v.ty))))
            self.place(l_end)
            return r
        self.error(at, "condition sans valeur")
        return self.constant(0)

    func sb_add(sb, r):
        self.rt("__rt_sb_add", [sb, r], false)

    func to_str(v):
        k := self.kind(v.ty)
        if k == K_STR:
            return v
        if k == K_INT:
            r := self.reg()
            self.emit_op(ir.INT_TO_STR, r, v.reg)
            return Val(r, TSTR)
        if k == K_FLOAT:
            return Val(self.rt("__rt_float_to_str", [v.reg]), TSTR)
        if k == K_BOOL:
            r := self.reg()
            l_false := self.label()
            l_end := self.label()
            self.jump(ir.JMP_IF_ZERO, l_false, v.reg)
            self.emit_op(ir.COPY, r, self.str_const("true"))
            self.jump(ir.JMP, l_end)
            self.place(l_false)
            self.emit_op(ir.COPY, r, self.str_const("false"))
            self.place(l_end)
            return Val(r, TSTR)
        if k == K_STRUCT or k == K_ENUM:
            h := self.reg()
            self.emit_op(ir.LOAD64, h, v.reg, -1, 0)
            return Val(h, TSTR)
        if k == K_NULL:
            return Val(self.str_const("null"), TSTR)
        if k == K_CHAR:
            return Val(self.rt("__rt_char_str", [v.reg]), TSTR)
        if k == K_FUTURE:
            return Val(self.rt("__rt_future_str", [v.reg]), TSTR)
        if k == K_EXC:
            return Val(self.rt("__rt_exc_str", [v.reg]), TSTR)
        if k == K_FUNC:
            r := self.reg()
            self.emit_op(ir.LOAD64, r, v.reg, -1, 8)
            return Val(r, TSTR)
        if k == K_TUPLE:
            sb := self.rt("__rt_sb_new", [])
            self.sb_add(sb, self.str_const("("))
            es := self.elems_of(v.ty)
            i := 0
            while i < len(es):
                if i > 0:
                    self.sb_add(sb, self.str_const(", "))
                e := self.reg()
                self.emit_op(ir.LOAD64, e, v.reg, -1, 8 * (i + 1))
                self.sb_add(sb, self.to_str(Val(e, es[i])).reg)
                i += 1
            self.sb_add(sb, self.str_const(")"))
            return Val(self.rt("__rt_sb_str", [sb]), TSTR)
        if k == K_NULLABLE:
            r := self.reg()
            l_null := self.label()
            l_end := self.label()
            self.jump(ir.JMP_IF_ZERO, l_null, v.reg)
            self.emit_op(ir.COPY, r, self.to_str(Val(self.unwrap(v.reg, v.ty), self.elem_of(v.ty))).reg)
            self.jump(ir.JMP, l_end)
            self.place(l_null)
            self.emit_op(ir.COPY, r, self.str_const("null"))
            self.place(l_end)
            return Val(r, TSTR)
        if k == K_DICT:
            sb := self.rt("__rt_sb_new", [])
            self.sb_add(sb, self.str_const("{"))
            e := self.constant(0)
            one := self.constant(1)
            first := self.reg()
            l_top := self.label()
            l_end := self.label()
            l_next := self.label()
            l_no_sep := self.label()
            self.emit_op(ir.COPY, first, self.constant(1))
            self.place(l_top)
            used := self.reg()
            t := self.reg()
            self.emit_op(ir.LOAD64, used, v.reg, -1, 8)
            self.emit_op(ir.LT, t, e, used)
            self.jump(ir.JMP_IF_ZERO, l_end, t)
            hashes := self.reg()
            h := self.reg()
            neg := self.reg()
            self.emit_op(ir.LOAD64, hashes, v.reg, -1, 40)
            self.emit_op(ir.LOAD_ELEM, h, hashes, e)
            self.emit_op(ir.LT, neg, h, self.constant(0))
            self.jump(ir.JMP_IF_NON_ZERO, l_next, neg)
            self.jump(ir.JMP_IF_NON_ZERO, l_no_sep, first)
            self.sb_add(sb, self.str_const(", "))
            self.place(l_no_sep)
            self.emit_op(ir.COPY, first, self.constant(0))
            keys := self.reg()
            vals := self.reg()
            kr := self.reg()
            x := self.reg()
            self.emit_op(ir.LOAD64, keys, v.reg, -1, 24)
            self.emit_op(ir.LOAD64, vals, v.reg, -1, 32)
            self.emit_op(ir.LOAD_ELEM, kr, keys, e)
            self.emit_op(ir.LOAD_ELEM, x, vals, e)
            self.sb_add(sb, self.to_str(Val(kr, self.elem_of(v.ty))).reg)
            self.sb_add(sb, self.str_const(": "))
            self.sb_add(sb, self.to_str(Val(x, self.val_of(v.ty))).reg)
            self.place(l_next)
            self.emit_op(ir.ADD, e, e, one)
            self.jump(ir.JMP, l_top)
            self.place(l_end)
            self.sb_add(sb, self.str_const("}"))
            return Val(self.rt("__rt_sb_str", [sb]), TSTR)
        if k == K_LIST:
            sb := self.rt("__rt_sb_new", [])
            self.sb_add(sb, self.str_const("["))
            i := self.constant(0)
            one := self.constant(1)
            l_top := self.label()
            l_end := self.label()
            l_first := self.label()
            self.place(l_top)
            n := self.list_len(v.reg)
            t := self.reg()
            self.emit_op(ir.LT, t, i, n)
            self.jump(ir.JMP_IF_ZERO, l_end, t)
            self.jump(ir.JMP_IF_ZERO, l_first, i)
            self.sb_add(sb, self.str_const(", "))
            self.place(l_first)
            e := self.reg()
            self.emit_op(ir.LOAD_ELEM, e, self.list_data(v.reg), i)
            sv := self.to_str(Val(e, self.elem_of(v.ty)))
            self.sb_add(sb, sv.reg)
            self.emit_op(ir.ADD, i, i, one)
            self.jump(ir.JMP, l_top)
            self.place(l_end)
            self.sb_add(sb, self.str_const("]"))
            return Val(self.rt("__rt_sb_str", [sb]), TSTR)
        return self.bad()

    # ------------------------------------------------------------------ expressions
    func expr_value(e, want=-1):
        v := self.expr(e, want)
        if not v.bad and v.ty == TVOID:
            self.error(e, "cette expression ne produit pas de valeur")
            return self.bad()
        return v

    func expr(e, want=-1):
        saved_line := self.cur_line
        if e.line > 0:
            self.cur_line = e.line
        v := self.expr_inner(e, want)
        self.cur_line = saved_line
        return v

    func expr_inner(e, want):
        k := e.kind
        if k == "Literal":
            lk := e.literal_kind
            if lk == "Integer":
                return Val(self.constant(e.value), TINT)
            if lk == "Float":
                return Val(self.constant(float_bits(e.value)), TFLOAT)
            if lk == "Boolean":
                return Val(self.constant(1 if e.value else 0), TBOOL)
            if lk == "String":
                return Val(self.str_const(e.value), TSTR)
            if lk == "Char":
                return Val(self.constant(e.value), TCHAR)
            if lk == "Null":
                return Val(self.constant(0), TNULL)
            return self.bad()
        if k == "Identifier":
            v := self.lookup(e.name)
            if v != null:
                return self.read(v)
            f := self.find_fn(e.name)
            if f >= 0 and not self.fns[f].runtime:
                return self.function_value(e, f)
            return self.unsupported(e, "'" + e.name + "' (nom inconnu du programme natif)")
        if k == "BinaryExpr":
            return self.binary(e)
        if k == "UnaryExpr":
            return self.unary(e)
        if k == "ConditionalExpr":
            cond := self.expr_value(e.condition)
            l_else := self.label()
            l_end := self.label()
            r := self.reg()
            self.jump(ir.JMP_IF_ZERO, l_else, self.truthy(e.condition, cond))
            a := self.expr_value(e.then_expr, want)
            if not a.bad:
                self.emit_op(ir.COPY, r, a.reg)
            self.jump(ir.JMP, l_end)
            self.place(l_else)
            b := self.expr_value(e.else_expr, want if a.bad else a.ty)
            if not b.bad:
                self.emit_op(ir.COPY, r, b.reg)
            self.place(l_end)
            if a.bad or b.bad:
                return self.bad()
            if a.ty != b.ty:
                self.error(e, "branches de types différents (" + self.ty_name(a.ty) + ", " + self.ty_name(b.ty) + ")")
                return self.bad()
            return Val(r, a.ty)
        if k == "CallExpr":
            saved := self.want_
            self.want_ = want
            v := self.call(e)
            self.want_ = saved
            return v
        if k == "FStringLiteral":
            return self.fstring(e)
        if k == "ListLiteral":
            return self.list_literal(e, self.unnull(want))
        if k == "DictLiteral":
            return self.dict_literal(e, self.unnull(want))
        if k == "IndexExpr":
            return self.index_expr(e)
        if k == "MemberExpr":
            eid := self.enum_of(e.object)
            if eid >= 0:
                return self.enum_variant(e, eid, e.member, null)
            target := self.module_of(e.object)
            if target >= 0:
                return self.module_member(e, target)
            fr := self.field_ref(e)
            if fr[0].bad:
                return fr[0]
            r := self.reg()
            self.emit_op(ir.LOAD64, r, fr[1], -1, 8 * fr[2])
            return Val(r, fr[0].ty)
        if k == "TupleLiteral":
            return self.tuple_literal(e, self.unnull(want))
        if k == "ComprehensionExpr":
            return self.comprehension(e, want)
        if k == "LambdaExpr":
            return self.lambda_(e.function, want, "<lambda>")
        if k == "RangeExpr":
            return self.unsupported(e, "intervalle hors d'une boucle for")
        if k == "ErrorPropagationExpr":
            return self.unsupported(e, "opérateur '?'")
        return self.unsupported(e, "expression")

    func unary(e):
        if e.op == "Spread" or e.op == "DictSpread":
            return self.unsupported(e, "l'expansion '*' / '**' (backend natif)")
        if e.op == "Await":
            f := self.expr_value(e.operand)
            if f.bad:
                return f
            if self.kind(f.ty) != K_FUTURE:
                self.error(e, "await attend une tâche ou un futur (obtenu " + self.ty_name(f.ty) + ")")
                return self.bad()
            self.uses_async = true
            w := self.rt("__rt_await", [f.reg])
            if self.elem_of(f.ty) == TVOID:
                return Val(-1, TVOID)
            return Val(w, self.elem_of(f.ty))
        v := self.expr_value(e.operand)
        if v.bad:
            return v
        r := self.reg()
        op := e.op
        if op == "Not":
            self.emit_op(ir.NOT, r, self.truthy(e, v))
            return Val(r, TBOOL)
        if op == "Plus":
            if self.is_num(v.ty):
                return v
        elif op == "Minus":
            if v.ty == TINT:
                self.emit_op(ir.NEG, r, v.reg)
                return Val(r, TINT)
            if v.ty == TFLOAT:
                self.emit_op(ir.FSUB, r, self.constant(float_bits(0.0)), v.reg)
                return Val(r, TFLOAT)
        elif op == "BitNot":
            if v.ty == TINT:
                self.emit_op(ir.BITNOT, r, v.reg)
                return Val(r, TINT)
        self.error(e, "opérateur unaire impossible sur " + self.ty_name(v.ty))
        return self.bad()

    func index_expr(e):
        obj := self.expr_value(e.object)
        if not obj.bad and self.kind(obj.ty) == K_DICT:
            key := self.expr_value(e.index, self.elem_of(obj.ty))
            if not self.expect_type(e.index, key, self.elem_of(obj.ty), "clé de dict"):
                return self.bad()
            ent := self.dict_index(obj.reg, key)
            neg := self.reg()
            self.emit_op(ir.LT, neg, ent, self.constant(0))
            self.fail_if(neg, ir.MSG_KEY_ERROR)
            vals := self.reg()
            r := self.reg()
            self.emit_op(ir.LOAD64, vals, obj.reg, -1, 32)
            self.emit_op(ir.LOAD_ELEM, r, vals, ent)
            return Val(r, self.val_of(obj.ty))
        if not obj.bad and self.kind(obj.ty) == K_TUPLE:
            return self.tuple_index(e, obj)
        idx := self.expr_value(e.index)
        if obj.bad or idx.bad:
            return self.bad()
        if idx.ty != TINT:
            self.error(e.index, "index : attendu int, obtenu " + self.ty_name(idx.ty))
            return self.bad()
        if self.kind(obj.ty) == K_LIST:
            ln := self.list_len(obj.reg)
            pos := self.norm_index(idx.reg, ln)
            self.bounds_check(pos, ln)
            r := self.reg()
            self.emit_op(ir.LOAD_ELEM, r, self.list_data(obj.reg), pos)
            return Val(r, self.elem_of(obj.ty))
        if obj.ty == TSTR:
            ln := self.rt("__rt_str_len", [obj.reg])
            return Val(self.rt("__rt_str_char_at", [obj.reg, self.norm_index(idx.reg, ln)]), TCHAR)
        self.error(e, "indexation de " + self.ty_name(obj.ty))
        return self.bad()

    func tuple_literal(t, want):
        hint := want >= 0 and self.kind(want) == K_TUPLE and len(self.elems_of(want)) == len(t.elements)
        es := []
        regs := []
        i := 0
        while i < len(t.elements):
            w := self.elems_of(want)[i] if hint else -1
            v := self.expr_value(t.elements[i], w)
            if v.bad:
                return v
            if w >= 0 and not self.expect_type(t.elements[i], v, w, "élément " + str(i) + " du tuple"):
                return self.bad()
            append(es, v.ty)
            append(regs, v.reg)
            i += 1
        obj := self.rt("__rt_alloc", [self.constant(8 * (len(es) + 1)), self.constant(0)])
        self.emit_op(ir.STORE64, -1, obj, self.constant(len(es)), 0)
        i = 0
        while i < len(regs):
            self.emit_op(ir.STORE64, -1, obj, regs[i], 8 * (i + 1))
            i += 1
        return Val(obj, self.tuple_of(es))

    func tuple_index(ix, obj):
        es := self.elems_of(obj.ty)
        n := len(es)
        ie := ix.index
        is_const := false
        k := 0
        if ie.kind == "Literal" and ie.literal_kind == "Integer":
            is_const = true
            k = ie.value
        elif ie.kind == "UnaryExpr":
            if ie.op == "Minus" and ie.operand.kind == "Literal" and ie.operand.literal_kind == "Integer":
                is_const = true
                k = -ie.operand.value
        if is_const:
            if k < 0 and k + n >= 0:
                k += n
            if k >= 0 and k < n:
                r := self.reg()
                self.emit_op(ir.LOAD64, r, obj.reg, -1, 8 * (k + 1))
                return Val(r, es[k])
            # (GCC évalue les arguments de droite à gauche : la constante n est émise d'abord)
            nr := self.constant(n)
            self.bounds_check(self.constant(k), nr)
            return Val(self.constant(0), es[0] if n > 0 else TINT)
        et := self.tuple_elem(obj.ty)
        if et < 0:
            self.error(ie, "index non constant sur un tuple hétérogène (" + self.ty_name(obj.ty) + ")")
            return self.bad()
        idx := self.expr_value(ie)
        if idx.bad:
            return idx
        if idx.ty != TINT:
            self.error(ie, "index : attendu int, obtenu " + self.ty_name(idx.ty))
            return self.bad()
        pos := self.norm_index(idx.reg, self.constant(n))
        self.bounds_check(pos, self.constant(n))
        base := self.reg()
        r := self.reg()
        self.emit_op(ir.ADD, base, obj.reg, self.constant(8))
        self.emit_op(ir.LOAD_ELEM, r, base, pos)
        return Val(r, et)

    func value_eq(at, l, r):
        if self.kind(l.ty) == K_LIST and self.kind(r.ty) == K_LIST:
            res := self.reg()
            l_end := self.label()
            l_top := self.label()
            i := self.reg()
            n := self.list_len(l.reg)
            t := self.reg()
            self.emit_op(ir.COPY, res, self.constant(0))
            self.emit_op(ir.NE, t, n, self.list_len(r.reg))
            self.jump(ir.JMP_IF_NON_ZERO, l_end, t)
            self.emit_op(ir.COPY, i, self.constant(0))
            self.place(l_top)
            more := self.reg()
            self.emit_op(ir.LT, more, i, n)
            l_same := self.label()
            self.jump(ir.JMP_IF_ZERO, l_same, more)
            x := self.reg()
            y := self.reg()
            self.emit_op(ir.LOAD_ELEM, x, self.list_data(l.reg), i)
            self.emit_op(ir.LOAD_ELEM, y, self.list_data(r.reg), i)
            e := self.value_eq(at, Val(x, self.elem_of(l.ty)), Val(y, self.elem_of(r.ty)))
            if e < 0:
                return -1
            self.jump(ir.JMP_IF_ZERO, l_end, e)
            self.emit_op(ir.ADD, i, i, self.constant(1))
            self.jump(ir.JMP, l_top)
            self.place(l_same)
            self.emit_op(ir.COPY, res, self.constant(1))
            self.place(l_end)
            return res
        if self.kind(l.ty) != K_TUPLE or self.kind(r.ty) != K_TUPLE:
            num := self.is_num(l.ty) and self.is_num(r.ty)
            comparable := num or l.ty == r.ty or self.kind(l.ty) == K_NULL or self.kind(r.ty) == K_NULL or (self.kind(l.ty) == K_NULLABLE and self.elem_of(l.ty) == r.ty) or (self.kind(r.ty) == K_NULLABLE and self.elem_of(r.ty) == l.ty)
            if not comparable and (self.kind(l.ty) == K_TUPLE or self.kind(r.ty) == K_TUPLE or self.is_scalar(l.ty) or self.is_scalar(r.ty) or l.ty == TSTR or r.ty == TSTR):
                return self.constant(0)
            v := self.arith(at, "Eq", l, r)
            return -1 if v.bad else v.reg
        a := self.elems_of(l.ty)
        b := self.elems_of(r.ty)
        if len(a) != len(b):
            return self.constant(0)
        res := self.reg()
        l_end := self.label()
        self.emit_op(ir.COPY, res, self.constant(0))
        i := 0
        while i < len(a):
            x := self.reg()
            y := self.reg()
            self.emit_op(ir.LOAD64, x, l.reg, -1, 8 * (i + 1))
            self.emit_op(ir.LOAD64, y, r.reg, -1, 8 * (i + 1))
            e := self.value_eq(at, Val(x, a[i]), Val(y, b[i]))
            if e < 0:
                return -1
            self.jump(ir.JMP_IF_ZERO, l_end, e)
            i += 1
        self.emit_op(ir.COPY, res, self.constant(1))
        self.place(l_end)
        return res

    # [Val (ty), registre de l'objet, rang du champ]
    func field_ref(m):
        if m.object.kind == "Identifier" and self.lookup(m.object.name) == null:
            return [self.unsupported(m, "accès '" + m.object.name + "." + m.member + "' (module non importé)"), -1, -1]
        obj := self.expr_value(m.object)
        if obj.bad:
            return [obj, -1, -1]
        if obj.ty == TEXC and (m.member == "type" or m.member == "message"):
            return [Val(-1, TSTR), obj.reg, 0 if m.member == "type" else 1]
        if self.kind(obj.ty) != K_STRUCT:
            self.error(m, "accès membre '" + m.member + "' sur " + self.ty_name(obj.ty) + (" (membres disponibles en natif : type, message)" if obj.ty == TEXC else ""))
            return [self.bad(), -1, -1]
        s := self.structs[self.types[obj.ty][2]]
        if not (m.member in s.field_index):
            self.error(m, "'" + s.name + "' n'a pas de champ déclaré '" + m.member + "'")
            return [self.bad(), -1, -1]
        fi := s.field_index[m.member]
        return [Val(-1, s.field_ty[fi]), obj.reg, fi + 1]

    func list_literal(l, want):
        elem_want := self.elem_of(want) if want >= 0 and self.kind(want) == K_LIST else -1
        if len(l.elements) == 0:
            if elem_want < 0:
                self.error(l, "liste vide : son type doit être connu (xs: list[int] := [])")
                return self.bad()
            return Val(self.rt("__rt_list_new", [self.constant(0)]), want)
        regs := []
        elem_ty := elem_want
        ok := true
        for el in l.elements:
            v := self.expr_value(el, elem_ty)
            if v.bad:
                ok = false
                continue
            if elem_ty < 0:
                elem_ty = v.ty
            elif not self.expect_type(el, v, elem_ty, "élément de liste (en natif, une liste est homogène)"):
                ok = false
                continue
            append(regs, v.reg)
        if not ok:
            return self.bad()
        lst := self.rt("__rt_list_new", [self.constant(len(regs))])
        data := self.list_data(lst)
        i := 0
        while i < len(regs):
            st := ir.Ins(ir.STORE_ELEM)
            st.a = data
            st.b = self.constant(i)
            st.args = [regs[i]]
            self.emit(st)
            i += 1
        return Val(lst, self.list_of(elem_ty))

    func dict_literal(d, want):
        key_want := self.elem_of(want) if want >= 0 and self.kind(want) == K_DICT else -1
        val_want := self.val_of(want) if key_want >= 0 else -1
        if len(d.entries) == 0:
            if key_want < 0:
                self.error(d, "dict vide : son type doit être connu (d: dict[str, int] := {})")
                return self.bad()
            return Val(self.rt("__rt_dict_new", [self.constant(8)]), want)
        kv := []
        kt := key_want
        vt := val_want
        ok := true
        for entry in d.entries:
            kk := self.expr_value(entry.key, kt)
            vv := self.expr_value(entry.value, vt)
            if kk.bad or vv.bad:
                ok = false
                continue
            if kt < 0:
                kt = kk.ty
            if vt < 0:
                vt = vv.ty
            if not self.expect_type(entry.key, kk, kt, "clé de dict") or not self.expect_type(entry.value, vv, vt, "valeur de dict"):
                ok = false
                continue
            append(kv, [kk, vv])
        if not ok:
            return self.bad()
        if not (self.is_scalar(kt) or kt == TSTR):
            self.error(d, "clé de dict de type " + self.ty_name(kt) + " : int, bool, float ou str attendu")
            return self.bad()
        dct := self.rt("__rt_dict_new", [self.constant(len(kv))])
        for p in kv:
            self.rt("__rt_dict_set", [dct, p[0].reg, p[1].reg, self.constant(self.key_kind(kt))], false)
        return Val(dct, self.dict_of(kt, vt))

    func fstring(f):
        sb := self.rt("__rt_sb_new", [])
        for part in f.parts:
            if not part.is_expr:
                if part.text != "":
                    self.sb_add(sb, self.str_const(part.text))
                continue
            v := self.expr_value(part.expr)
            if v.bad:
                return v
            self.sb_add(sb, self.to_str(v).reg)
        return Val(self.rt("__rt_sb_str", [sb]), TSTR)

    func binary(b):
        if b.op == "And" or b.op == "Or":
            l := self.expr_value(b.left)
            r := self.reg()
            l_end := self.label()
            if not l.bad:
                self.emit_op(ir.COPY, r, l.reg)
            self.jump(ir.JMP_IF_ZERO if b.op == "And" else ir.JMP_IF_NON_ZERO, l_end, self.truthy(b, l))
            rv := self.expr_value(b.right)
            if not rv.bad:
                self.emit_op(ir.COPY, r, rv.reg)
            self.place(l_end)
            if l.bad or rv.bad:
                return self.bad()
            if l.ty != rv.ty:
                self.error(b, "'and'/'or' entre " + self.ty_name(l.ty) + " et " + self.ty_name(rv.ty) + " : types identiques requis en natif")
                return self.bad()
            return Val(r, l.ty)
        l := self.expr_value(b.left)
        r := self.expr_value(b.right)
        if l.bad or r.bad:
            return self.bad()
        return self.arith(b, b.op, l, r)

    func _mismatch(at, op_name, l, r):
        self.error(at, "opération '" + op_name + "' entre " + self.ty_name(l.ty) + " et " + self.ty_name(r.ty))
        return self.bad()

    func arith(at, op, l, r):
        op_name := _a.BINARY_TEXT[op]
        cmp := op == "Eq" or op == "Ne" or op == "Lt" or op == "Le" or op == "Gt" or op == "Ge"
        d := self.reg()
        l_nul := self.kind(l.ty) == K_NULL or self.kind(l.ty) == K_NULLABLE
        r_nul := self.kind(r.ty) == K_NULL or self.kind(r.ty) == K_NULLABLE
        if l_nul or r_nul:
            if (op == "Eq" or op == "Ne") and (l.ty == TNULL or r.ty == TNULL):
                other := r if l.ty == TNULL else l
                if other.ty == TNULL:
                    return Val(self.constant(1 if op == "Eq" else 0), TBOOL)
                if self.kind(other.ty) != K_NULLABLE:
                    return Val(self.constant(1 if op == "Ne" else 0), TBOOL)
                self.emit_op(ir.EQ if op == "Eq" else ir.NE, d, other.reg, self.constant(0))
                return Val(d, TBOOL)
            self.error(at, "opération '" + op_name + "' entre " + self.ty_name(l.ty) + " et " + self.ty_name(r.ty) + " : tester d'abord `x != null` (la valeur est alors de type non nullable)")
            return self.bad()
        if self.kind(l.ty) == K_TUPLE or self.kind(r.ty) == K_TUPLE or (self.kind(l.ty) == K_LIST and self.kind(r.ty) == K_LIST):
            if op != "Eq" and op != "Ne":
                return self._mismatch(at, op_name, l, r)
            eq := self.value_eq(at, l, r)
            if eq < 0:
                return self.bad()
            if op == "Eq":
                return Val(eq, TBOOL)
            self.emit_op(ir.NOT, d, eq)
            return Val(d, TBOOL)
        if l.ty == TCHAR or r.ty == TCHAR:
            if l.ty != r.ty:
                if op == "Eq" or op == "Ne":
                    return Val(self.constant(1 if op == "Ne" else 0), TBOOL)
                return self._mismatch(at, op_name, l, r)
            if not (op in CMP_OPS):
                return self._mismatch(at, op_name, l, r)
            self.emit_op(CMP_OPS[op], d, l.reg, r.reg)
            return Val(d, TBOOL)
        if self.kind(l.ty) == K_ENUM or self.kind(r.ty) == K_ENUM or self.kind(l.ty) == K_FUTURE or self.kind(r.ty) == K_FUTURE:
            if (op != "Eq" and op != "Ne") or l.ty != r.ty:
                return self._mismatch(at, op_name, l, r)
            self.emit_op(ir.EQ if op == "Eq" else ir.NE, d, l.reg, r.reg)
            return Val(d, TBOOL)
        if l.ty == TSTR and r.ty == TSTR:
            if op == "Add":
                return Val(self.rt("__rt_concat", [l.reg, r.reg]), TSTR)
            if op == "Eq" or op == "Ne":
                eq := self.rt("__rt_str_eq", [l.reg, r.reg])
                if op == "Eq":
                    return Val(eq, TBOOL)
                self.emit_op(ir.NOT, d, eq)
                return Val(d, TBOOL)
            if not cmp:
                return self._mismatch(at, op_name, l, r)
            c := self.rt("__rt_str_cmp", [l.reg, r.reg])
            o := ir.LT if op == "Lt" else ir.LE if op == "Le" else ir.GT if op == "Gt" else ir.GE
            self.emit_op(o, d, c, self.constant(0))
            return Val(d, TBOOL)
        if l.ty == TBOOL and r.ty == TBOOL:
            if op != "Eq" and op != "Ne":
                return self._mismatch(at, op_name, l, r)
            self.emit_op(ir.EQ if op == "Eq" else ir.NE, d, l.reg, r.reg)
            return Val(d, TBOOL)
        if not self.is_num(l.ty) or not self.is_num(r.ty):
            return self._mismatch(at, op_name, l, r)
        if l.ty == TFLOAT or r.ty == TFLOAT or op == "Div":
            a := self.to_float(l)
            b := self.to_float(r)
            if op == "Add":
                self.emit_op(ir.FADD, d, a, b)
                return Val(d, TFLOAT)
            if op == "Sub":
                self.emit_op(ir.FSUB, d, a, b)
                return Val(d, TFLOAT)
            if op == "Mul":
                self.emit_op(ir.FMUL, d, a, b)
                return Val(d, TFLOAT)
            if op == "Div":
                self._zero_check(b, ir.MSG_DIV_ZERO_INT if l.ty == TINT and r.ty == TINT else ir.MSG_DIV_ZERO_FLOAT)
                self.emit_op(ir.FDIV, d, a, b)
                return Val(d, TFLOAT)
            if op == "FloorDiv":
                self._zero_check(b, ir.MSG_FLOOR_DIV_ZERO_FLOAT)
                self.emit_op(ir.FDIV, d, a, b)
                return Val(self.rt("__rt_floor", [d]), TFLOAT)
            if op == "Mod":
                self._zero_check(b, ir.MSG_MOD_ZERO_FLOAT)
                return Val(self.rt("__rt_floor_mod", [a, b]), TFLOAT)
            fo := {"Eq": ir.FEQ, "Ne": ir.FNE, "Lt": ir.FLT, "Le": ir.FLE, "Gt": ir.FGT, "Ge": ir.FGE}
            if op in fo:
                self.emit_op(fo[op], d, a, b)
                return Val(d, TBOOL)
            if op == "Pow":
                self.error(at, "'**' sur des flottants : non supporté en natif (utiliser math.pow)")
                return self.bad()
            return self._mismatch(at, op_name, l, r)
        if not (op in INT_OPS):
            return self._mismatch(at, op_name, l, r)
        self.emit_op(INT_OPS[op], d, l.reg, r.reg)
        return Val(d, TBOOL if cmp else TINT)

    func _zero_check(b, msg):
        z := self.reg()
        self.emit_op(ir.FEQ, z, b, self.constant(float_bits(0.0)))
        self.fail_if(z, msg)

    # ------------------------------------------------------------------ appels
    func print_(c):
        if len(c.arguments) == 0:
            self.emit_op(ir.PRINT_EMPTY, -1)
            return
        for a in c.arguments:
            if a.name != null:
                self.error(c, "print(...) ne prend pas d'arguments nommés")
                continue
            v := self.expr_value(a.value)
            if v.bad:
                continue
            if v.ty == TINT:
                self.emit_op(ir.PRINT_INT, -1, v.reg)
            else:
                self.emit_op(ir.PRINT_STR, -1, self.to_str(v).reg)

    # Arguments d'une intrinsèque : null si erreur (signalée), sinon liste de Val.
    func _take(c, name, args, n):
        if len(c.arguments) != n:
            self.error(c, name + "(...) attend " + str(n) + " argument(s)")
            return false
        for a in c.arguments:
            if a.name != null:
                self.error(c, name + "(...) ne prend pas d'arguments nommés")
                return false
            v := self.expr_value(a.value)
            append(args, v)
            if v.bad:
                return false
        return true

    func _want(c, name, args, i, ty):
        if args[i].ty == ty:
            return true
        self.error(c, name + "(...) : argument " + str(i + 1) + " de type " + self.ty_name(args[i].ty) + ", attendu " + self.ty_name(ty))
        return false

    func _simple(c, name, args, n, tys, op, res_ty, imm=0):
        if not self._take(c, name, args, n):
            return self.bad()
        i := 0
        for t in tys:
            if not self._want(c, name, args, i, t):
                return self.bad()
            i += 1
        d := -1 if res_ty == TVOID else self.reg()
        self.emit_op(op, d, args[0].reg if n > 0 else -1, args[1].reg if n > 1 else -1, imm)
        return Val(d, res_ty)

    # [géré, Val]
    func intrinsic(c, name):
        args := []
        if name == "raise" and self.lookup(name) == null:
            if len(c.arguments) == 0 or len(c.arguments) > 2:
                self.error(c, "raise(...) attend 1 ou 2 arguments")
                return [true, self.bad()]
            for a in c.arguments:
                if a.name != null:
                    self.error(c, "raise(...) ne prend pas d'arguments nommés")
                    return [true, self.bad()]
                v := self.expr_value(a.value)
                append(args, v)
                if v.bad:
                    return [true, self.bad()]
            exc := -1
            if len(args) == 1 and args[0].ty == TEXC:
                exc = args[0].reg
            elif len(args) == 1 and args[0].ty == TSTR:
                exc = self.rt("__rt_exc_new", [self.str_const("Exception"), args[0].reg])
            elif len(args) == 2 and args[0].ty == TSTR and args[1].ty == TSTR:
                exc = self.rt("__rt_exc_new", [args[0].reg, args[1].reg])
            else:
                self.error(c, "raise(...) : raise(message), raise(type, message) (chaînes) ou raise(exception)")
                return [true, self.bad()]
            self.rt("__rt_throw", [exc], false)
            return [true, Val(-1, TVOID)]
        if name == "isinstance" and self.lookup(name) == null:
            if len(c.arguments) != 2 or c.arguments[1].value.kind != "Identifier":
                self.error(c, "isinstance(valeur, Classe) attendu")
                return [true, self.bad()]
            v := self.expr_value(c.arguments[0].value)
            if v.bad:
                return [true, v]
            cls := c.arguments[1].value.name
            sid_cls := self.find_struct(cls)
            if sid_cls < 0 or self.kind(v.ty) != K_STRUCT:
                self.error(c, "isinstance : en natif, une instance de classe et un nom de classe ou d'interface")
                return [true, self.bad()]
            r := self.reg()
            header := self.reg()
            l_end := self.label()
            self.emit_op(ir.COPY, r, self.constant(1))
            self.emit_op(ir.LOAD64, header, v.reg, -1, 0)
            for sub in self.concrete_subs(sid_cls):
                eq := self.reg()
                self.emit_op(ir.EQ, eq, header, self.str_const("<" + self.structs[sub].name + " instance>"))
                self.jump(ir.JMP_IF_NON_ZERO, l_end, eq)
            self.emit_op(ir.COPY, r, self.constant(0))
            self.place(l_end)
            return [true, Val(r, TBOOL)]
        if name == "str" and self.lookup(name) == null:
            if not self._take(c, name, args, 1):
                return [true, self.bad()]
            return [true, self.to_str(args[0])]
        if (name in self.imported) and self.lookup(name) == null:
            res := self.imported_call(c, name, args)
            if res != null:
                return [true, res]
        if (self.in_runtime or self.mods[self.mod_].stdlib) and _starts(name, "__") and not _starts(name, "__rt_"):
            res := self.privileged(c, name, args)
            if res != null:
                return [true, res]
        return [false, self.bad()]

    func imported_call(c, name, args):
        if name == "len":
            if not self._take(c, name, args, 1):
                return self.bad()
            k := self.kind(args[0].ty)
            if k == K_LIST:
                return Val(self.list_len(args[0].reg), TINT)
            if k == K_TUPLE:
                return Val(self.constant(len(self.elems_of(args[0].ty))), TINT)
            if k == K_DICT:
                d := self.reg()
                self.emit_op(ir.LOAD64, d, args[0].reg, -1, 0)
                return Val(d, TINT)
            if args[0].ty == TSTR:
                return Val(self.rt("__rt_str_len", [args[0].reg]), TINT)
            self.error(c, "len(...) sur " + self.ty_name(args[0].ty))
            return self.bad()
        if name == "to_int":
            if not self._take(c, name, args, 1):
                return self.bad()
            if args[0].ty == TINT:
                return args[0]
            if args[0].ty == TBOOL:
                return Val(args[0].reg, TINT)
            if args[0].ty == TFLOAT:
                d := self.reg()
                self.emit_op(ir.FLOAT_TO_INT, d, args[0].reg)
                return Val(d, TINT)
            if args[0].ty == TSTR:
                return Val(self.rt("__rt_str_to_int", [args[0].reg]), TINT)
            self.error(c, "to_int(...) sur " + self.ty_name(args[0].ty))
            return self.bad()
        if name == "to_float":
            if not self._take(c, name, args, 1):
                return self.bad()
            if self.is_num(args[0].ty):
                return Val(self.to_float(args[0]), TFLOAT)
            if args[0].ty == TSTR:
                return Val(self.rt("__rt_str_to_float", [args[0].reg]), TFLOAT)
            self.error(c, "to_float(...) sur " + self.ty_name(args[0].ty))
            return self.bad()
        if name == "keys" or name == "values" or name == "get" or name == "contains_key" or name == "remove" or name == "set":
            want := 1 if name == "keys" or name == "values" else 3 if name == "set" else 2
            if len(c.arguments) != want:
                self.error(c, name + "(...) attend " + str(want) + " argument(s)")
                return self.bad()
            for a in c.arguments:
                if a.name != null:
                    self.error(c, name + "(...) ne prend pas d'arguments nommés")
                    return self.bad()
            dv := self.expr_value(c.arguments[0].value)
            if dv.bad:
                return dv
            if self.kind(dv.ty) != K_DICT:
                self.error(c, name + "(...) sur " + self.ty_name(dv.ty) + " (en natif : dict seulement)")
                return self.bad()
            if name == "keys" or name == "values":
                return Val(self.rt("__rt_dict_list", [dv.reg, self.constant(24 if name == "keys" else 32)]), self.list_of(self.elem_of(dv.ty) if name == "keys" else self.val_of(dv.ty)))
            key := self.expr_value(c.arguments[1].value, self.elem_of(dv.ty))
            if not self.expect_type(c.arguments[1].value, key, self.elem_of(dv.ty), name + " (clé)"):
                return self.bad()
            if name == "set":
                v := self.expr_value(c.arguments[2].value, self.val_of(dv.ty))
                if not self.expect_type(c.arguments[2].value, v, self.val_of(dv.ty), "set (valeur)"):
                    return self.bad()
                self.rt("__rt_dict_set", [dv.reg, key.reg, v.reg, self.constant(self.key_kind(key.ty))], false)
                return Val(-1, TVOID)
            if name == "remove":
                self.rt("__rt_dict_remove", [dv.reg, key.reg, self.constant(self.key_kind(key.ty))], false)
                return Val(-1, TVOID)
            ent := self.dict_index(dv.reg, key)
            if name == "contains_key":
                d := self.reg()
                self.emit_op(ir.GE, d, ent, self.constant(0))
                return Val(d, TBOOL)
            res_ty := self.nullable_of(self.val_of(dv.ty))
            r := self.reg()
            l_miss := self.label()
            l_end := self.label()
            neg := self.reg()
            self.emit_op(ir.LT, neg, ent, self.constant(0))
            self.jump(ir.JMP_IF_NON_ZERO, l_miss, neg)
            vals := self.reg()
            x := self.reg()
            self.emit_op(ir.LOAD64, vals, dv.reg, -1, 32)
            self.emit_op(ir.LOAD_ELEM, x, vals, ent)
            self.emit_op(ir.COPY, r, x if self.kind(self.val_of(dv.ty)) == K_NULLABLE else self.wrap(Val(x, self.val_of(dv.ty))))
            self.jump(ir.JMP, l_end)
            self.place(l_miss)
            self.emit_op(ir.COPY, r, self.constant(0))
            self.place(l_end)
            return Val(r, res_ty)
        if name == "clear":
            if not self._take(c, name, args, 1):
                return self.bad()
            if self.kind(args[0].ty) != K_LIST:
                self.error(c, "clear(...) sur " + self.ty_name(args[0].ty) + " (en natif : listes)")
                return self.bad()
            self.emit_op(ir.STORE64, -1, args[0].reg, self.constant(0), 0)
            return Val(-1, TVOID)
        if name == "append":
            if len(c.arguments) != 2 or c.arguments[0].name != null or c.arguments[1].name != null:
                self.error(c, "append(liste, valeur) attend 2 arguments positionnels")
                return self.bad()
            l := self.expr_value(c.arguments[0].value)
            if l.bad:
                return l
            if self.kind(l.ty) != K_LIST:
                self.error(c, "append(...) sur " + self.ty_name(l.ty))
                return self.bad()
            v := self.expr_value(c.arguments[1].value, self.elem_of(l.ty))
            if not self.expect_type(c.arguments[1].value, v, self.elem_of(l.ty), "append"):
                return self.bad()
            self.rt("__rt_list_push", [l.reg, v.reg], false)
            return Val(-1, TVOID)
        return null

    # Intrinsèques du runtime et de la stdlib native (null : nom non reconnu).
    func privileged(c, name, args):
        if name == "__alloc" or name == "__alloc_raw":
            if not self._take(c, name, args, 1) or not self._want(c, name, args, 0, TINT):
                return self.bad()
            return Val(self.rt("__rt_alloc", [args[0].reg, self.constant(1 if name == "__alloc_raw" else 0)]), TINT)
        if name == "__state":
            return self._simple(c, name, args, 0, [], ir.RT_STATE, TINT)
        flags := {"__freestanding": self.freestanding, "__uefi": self.uefi, "__windows": self.windows, "__a64": self.a64, "__dyn": self.dyn, "__alexos": _alexos[0]}
        if name in flags:
            if not self._take(c, name, args, 0):
                return self.bad()
            return Val(self.constant(1 if flags[name] else 0), TBOOL)
        if name == "__dyn_invoke":
            if not self._take(c, name, args, 11):
                return self.bad()
            i := ir.Ins(ir.CALL_IND)
            i.a = args[0].reg
            k := 1
            while k < 11:
                if not self._want(c, name, args, k, TINT):
                    return self.bad()
                append(i.args, args[k].reg)
                k += 1
            i.imm = 8
            i.dst = self.reg()
            dst := i.dst
            self.emit(i)
            return Val(dst, TINT)
        if name == "__svc":
            if not self.a64 or self.windows or self.freestanding or len(c.arguments) == 0 or len(c.arguments) > 7:
                self.error(c, "__svc(numéro, arguments...) : de 1 à 7 arguments, cible Linux AArch64 seulement")
                return self.bad()
            if not self._take(c, name, args, len(c.arguments)):
                return self.bad()
            i := ir.Ins(ir.SYSCALL)
            k := 0
            while k < len(args):
                if not self._want(c, name, args, k, TINT):
                    return self.bad()
                append(i.args, args[k].reg)
                k += 1
            i.dst = self.reg()
            dst := i.dst
            self.emit(i)
            return Val(dst, TINT)
        if name == "__wincall":
            return self.wincall(c)
        if name == "__wincallback":
            return self.wincallback(c)
        if name == "__sysv_call":
            # appel C System V (VM écrite en ALEX : ffi) ; cadre : voir nt_codegen (SYSV_CALL)
            if self.windows or self.freestanding or self.a64:
                self.error(c, "__sysv_call(fonction, cadre) : cible Linux x86-64 seulement")
                return self.bad()
            if not self._take(c, name, args, 2) or not self._want(c, name, args, 0, TINT) or not self._want(c, name, args, 1, TINT):
                return self.bad()
            i := ir.Ins(ir.SYSV_CALL)
            i.a = args[0].reg
            i.b = args[1].reg
            i.dst = self.reg()
            dst := i.dst
            self.emit(i)
            return Val(dst, TINT)
        if name == "__elf_import" and _alexos[0]:
            # cible Alex OS : aucune bibliothèque partagée ; l'adresse vaut 0 (fonctions concernées désactivées)
            return Val(self.constant(0), TINT)
        if name == "__elf_import":
            # adresse d'une fonction d'une bibliothèque partagée (« libc.so.6!dlopen »), liée au chargement par
            # l'éditeur de liens dynamique : l'exécutable devient un ELF dynamique (VM écrite en ALEX seulement)
            ok_lit := len(c.arguments) == 1 and c.arguments[0].value.kind == "Literal" and c.arguments[0].value.literal_kind == "String" and _s.find(c.arguments[0].value.value, "!") > 0
            if not ok_lit or self.windows or self.freestanding or self.a64:
                self.error(c, "__elf_import(\"lib.so!symbole\") : nom littéral, cible Linux x86-64 seulement")
                return self.bad()
            full := c.arguments[0].value.value
            index := -1
            k := 0
            while k < len(self.prog.imports):
                if self.prog.imports[k] == full:
                    index = k
                k += 1
            if index < 0:
                index = len(self.prog.imports)
                append(self.prog.imports, full)
            ia := ir.Ins(ir.IMPORT_ADDR)
            ia.dst = self.reg()
            ia.imm = index
            dst := ia.dst
            self.emit(ia)
            return Val(dst, TINT)
        if name == "__mscall" or name == "__mscall_f":
            # __mscall_f : même appel, rend les bits du flottant de retour (xmm0) au lieu de rax (x86-64 seulement)
            n := len(c.arguments)
            if name == "__mscall_f" and self.a64:
                self.error(c, "__mscall_f(...) : cible x86-64 seulement")
                return self.bad()
            if n < 1 or n > 17:
                self.error(c, name + "(fonction, arguments...) : 1 à 17 arguments")
                return self.bad()
            if not self._take(c, name, args, n):
                return self.bad()
            k := 0
            while k < n:
                if not self._want(c, name, args, k, TINT):
                    return self.bad()
                k += 1
            i := ir.Ins(ir.MS_CALL)
            i.a = args[0].reg
            if name == "__mscall_f":
                i.imm = 1
            k = 1
            while k < n:
                append(i.args, args[k].reg)
                k += 1
            i.dst = self.reg()
            dst := i.dst
            self.emit(i)
            return Val(dst, TINT)
        if self.freestanding and name == "__mmap":
            if not self._take(c, name, args, 1) or not self._want(c, name, args, 0, TINT):
                return self.bad()
            return Val(self.rt("__rt_kmap", [args[0].reg]), TINT)
        if self.freestanding and name == "__munmap":
            if not self._take(c, name, args, 2) or not self._want(c, name, args, 0, TINT) or not self._want(c, name, args, 1, TINT):
                return self.bad()
            self.rt("__rt_kunmap", [args[0].reg, args[1].reg], false)
            return Val(-1, TVOID)
        if name in SIMPLE_INTRINSICS:
            s := SIMPLE_INTRINSICS[name]
            return self._simple(c, name, args, s[0], s[1], s[2], s[3], s[4])
        if name == "__copy":
            if not self._take(c, name, args, 3) or not self._want(c, name, args, 0, TINT) or not self._want(c, name, args, 1, TINT) or not self._want(c, name, args, 2, TINT):
                return self.bad()
            i := ir.Ins(ir.MEM_COPY)
            i.a = args[0].reg
            i.b = args[1].reg
            i.args = [args[2].reg]
            self.emit(i)
            return Val(-1, TVOID)
        if name in PORTS_OUT:
            if not self._take(c, name, args, 2) or not self._want(c, name, args, 0, TINT) or not self._want(c, name, args, 1, TINT):
                return self.bad()
            i := ir.Ins(ir.PORT_OUT)
            i.a = args[0].reg
            i.b = args[1].reg
            i.imm = PORTS_OUT[name]
            self.emit(i)
            return Val(-1, TVOID)
        if name in PORTS_IN:
            if not self._take(c, name, args, 1) or not self._want(c, name, args, 0, TINT):
                return self.bad()
            return self._simple(c, name, args, 1, [TINT], ir.PORT_IN, TINT, PORTS_IN[name])
        if name in SIMPLE_INTRINSICS_2:
            s := SIMPLE_INTRINSICS_2[name]
            return self._simple(c, name, args, s[0], s[1], s[2], s[3], s[4])
        if name == "__fnaddr":
            ok_arg := len(c.arguments) == 1 and c.arguments[0].value.kind == "Literal" and c.arguments[0].value.literal_kind == "String" and (c.arguments[0].value.value in self.fn_by_name)
            if not ok_arg:
                self.error(c, "__fnaddr(\"__rt_...\") attendu")
                return self.bad()
            fa := ir.Ins(ir.FUNC_ADDR)
            fa.dst = self.reg()
            fa.callee = self.fns[self.fn_by_name[c.arguments[0].value.value]].id
            dst := fa.dst
            self.emit(fa)
            return Val(dst, TINT)
        if name == "__enter_user" or name == "__cas":
            if not self._take(c, name, args, 3) or not self._want(c, name, args, 0, TINT) or not self._want(c, name, args, 1, TINT) or not self._want(c, name, args, 2, TINT):
                return self.bad()
            i := ir.Ins(ir.CPU_OP if name == "__cas" else ir.ENTER_USER)
            if name == "__cas":
                i.imm = 16
            i.dst = self.reg()
            i.a = args[0].reg
            i.b = args[1].reg
            i.args = [args[2].reg]
            dst := i.dst
            self.emit(i)
            return Val(dst, TINT)
        if name in SIMPLE_INTRINSICS_3:
            s := SIMPLE_INTRINSICS_3[name]
            return self._simple(c, name, args, s[0], s[1], s[2], s[3], s[4])
        if name == "__as_task":
            if not self._take(c, name, args, 1) or not self._want(c, name, args, 0, TINT):
                return self.bad()
            return Val(args[0].reg, self.func_of([], TVOID))
        if name == "__addr":
            if not self._take(c, name, args, 1):
                return self.bad()
            if self.is_scalar(args[0].ty):
                self.error(c, "__addr(...) : objet du tas attendu")
                return self.bad()
            return Val(args[0].reg, TINT)
        if name == "__irq_restore":
            return self._simple(c, name, args, 1, [TINT], ir.CPU_OP, TVOID, 5)
        if name in CPU_SIMPLE:
            return self._simple(c, name, args, 0, [], ir.CPU_OP, TVOID, CPU_SIMPLE[name])
        if name in SIMPLE_INTRINSICS_4:
            s := SIMPLE_INTRINSICS_4[name]
            return self._simple(c, name, args, s[0], s[1], s[2], s[3], s[4])
        if name == "__syscall":
            return self.syscall_(c, name, args)
        if name in CASTS:
            cs := CASTS[name]
            if not self._take(c, name, args, 1) or not self._want(c, name, args, 0, cs[0]):
                return self.bad()
            return Val(args[0].reg, cs[1])
        return null

    func syscall_(c, name, args):
        if len(c.arguments) == 0 or len(c.arguments) > 7:
            self.error(c, "__syscall(numéro, arguments...) : de 1 à 7 arguments")
            return self.bad()
        if not self._take(c, name, args, len(c.arguments)):
            return self.bad()
        if (self.a64 and not self.windows and not self.freestanding) or self.windows:
            regs := []
            k := 0
            while k < len(args):
                if not self._want(c, name, args, k, TINT):
                    return self.bad()
                append(regs, args[k].reg)
                k += 1
            while len(regs) < 7:
                append(regs, self.constant(0))
            return Val(self.rt("__rt_a64_syscall" if self.a64 and not self.windows and not self.freestanding else "__rt_win_syscall", regs), TINT)
        i := ir.Ins(ir.SYSCALL)
        k := 0
        while k < len(args):
            if not self._want(c, name, args, k, TINT):
                return self.bad()
            append(i.args, args[k].reg)
            k += 1
        i.dst = self.reg()
        dst := i.dst
        self.emit(i)
        return Val(dst, TINT)

    func wincall(c):
        n := len(c.arguments)
        a0 := c.arguments[0].value if n >= 1 else null
        ok_name := n >= 1 and a0.kind == "Literal" and a0.literal_kind == "String"
        if not ok_name or n > 17:
            self.error(c, "__wincall(\"dll!Nom\", arguments...) : nom littéral et 0 à 16 arguments")
            return self.bad()
        if not self.windows:
            self.error(c, "__wincall(...) : seulement pour un exécutable Windows (--windows)")
            return self.bad()
        fname := a0.value
        if _s.find(fname, "!") < 0:
            fname = "kernel32.dll!" + fname
        index := -1
        k := 0
        while k < len(self.prog.imports):
            if self.prog.imports[k] == fname:
                index = k
            k += 1
        if index < 0:
            index = len(self.prog.imports)
            append(self.prog.imports, fname)
        regs := []
        k = 1
        while k < n:
            if c.arguments[k].name != null:
                self.error(c, "__wincall(...) ne prend pas d'arguments nommés")
                return self.bad()
            v := self.expr_value(c.arguments[k].value)
            if v.bad:
                return v
            if v.ty != TINT:
                self.error(c, "__wincall(...) : argument " + str(k + 1) + " de type " + self.ty_name(v.ty) + ", attendu int")
                return self.bad()
            append(regs, v.reg)
            k += 1
        ia := ir.Ins(ir.IMPORT_ADDR)
        ia.dst = self.reg()
        ia.imm = index
        fn_reg := ia.dst
        self.emit(ia)
        i := ir.Ins(ir.MS_CALL)
        i.a = fn_reg
        i.args = regs
        i.dst = self.reg()
        dst := i.dst
        self.emit(i)
        return Val(dst, TINT)

    func wincallback(c):
        ok_arg := self.windows and len(c.arguments) == 1 and c.arguments[0].value.kind == "Literal" and c.arguments[0].value.literal_kind == "String"
        fname := c.arguments[0].value.value if ok_arg else ""
        key := null
        if ok_arg:
            if self.qual(fname) in self.fn_by_name:
                key = self.qual(fname)
            elif fname in self.fn_by_name:
                key = fname
        if not ok_arg or key == null:
            self.error(c, "__wincallback(\"fonction\") : fonction du module attendue (exécutable Windows seulement)")
            return self.bad()
        fn := self.fns[self.fn_by_name[key]]
        if len(fn.params) != 4:
            self.error(c, "__wincallback : la fonction '" + fname + "' doit prendre 4 paramètres entiers")
            return self.bad()
        t := ir.Ins(ir.WIN_THUNK)
        t.dst = self.reg()
        t.callee = fn.id
        dst := t.dst
        self.emit(t)
        return Val(dst, TINT)

    # [registres, ok]
    func prepare_args(at, f, args, self_reg):
        first := 1 if self_reg >= 0 else 0
        n := len(f.params)
        exprs := [null for i in 0..n]
        pos := first
        ok := true
        for a in args:
            idx := pos
            if a.name != null:
                idx = n
                i := first
                while i < n:
                    if f.names[i] == a.name:
                        idx = i
                    i += 1
            else:
                pos += 1
            if idx >= n:
                self.error(at, "argument en trop ou inconnu dans l'appel de " + f.name)
                ok = false
                continue
            exprs[idx] = a.value
        regs := [-1 for i in 0..n]
        if self_reg >= 0:
            regs[0] = self_reg
        i := first
        while i < n:
            e := exprs[i] if exprs[i] != null else f.decl.params[i - first].default_value
            if e == null:
                self.error(at, "argument '" + f.names[i] + "' manquant dans l'appel de " + f.name)
                ok = false
                i += 1
                continue
            v := self.expr_value(e, f.params[i])
            if v.ty == TINT and f.params[i] == TFLOAT and self.mods[f.module].stdlib:
                v = Val(self.to_float(v), TFLOAT)
            if not self.expect_type(e, v, f.params[i], "argument '" + f.names[i] + "' de " + f.name):
                ok = false
                i += 1
                continue
            regs[i] = v.reg
            i += 1
        return [regs, ok]

    func emit_call(f, regs):
        i := ir.Ins(ir.CALL)
        i.callee = f.id
        i.args = [r for r in regs]
        i.dst = -1 if f.ret == TVOID else self.reg()
        dst := i.dst
        self.emit(i)
        return Val(dst, f.ret)

    func invoke(fn_index, regs):
        f := self.fns[fn_index]
        return self.spawn_async(fn_index, regs) if f.is_async else self.emit_call(f, regs)

    func call_async(at, fn_index, args, self_reg):
        f := self.fns[fn_index]
        if f.generic:
            self.error(at, "async func " + f.name + " : paramètres annotés requis en natif")
            return self.bad()
        pa := self.prepare_args(at, f, args, self_reg)
        if not pa[1]:
            return self.bad()
        return self.spawn_async(fn_index, pa[0])

    func _raw(op, dst=-1, a=-1, imm=0):
        i := ir.Ins(op)
        i.dst = dst
        i.a = a
        i.imm = imm
        return i

    func spawn_async(fn_index, regs):
        f := self.fns[fn_index]
        self.uses_async = true
        thunk := -1
        if fn_index in self.async_thunks:
            thunk = self.async_thunks[fn_index]
        else:
            fir := ir.IrFunction(f.name)
            fir.params = 1
            fir.runtime = true
            v := 1
            append(fir.code, self._raw(ir.LOAD64, v, 0, 16))
            v += 1
            cl := ir.Ins(ir.CALL)
            cl.callee = f.id
            i := 0
            while i < len(f.params):
                append(fir.code, self._raw(ir.LOAD64, v, 0, 24 + 8 * i))
                append(cl.args, v)
                v += 1
                i += 1
            if f.ret == TVOID:
                cl.dst = -1
            else:
                cl.dst = v
                v += 1
            cl.line = f.decl.line
            append(fir.code, cl)
            result := cl.dst
            if result < 0:
                append(fir.code, self._raw(ir.CONST, v, -1, 0))
                result = v
                v += 1
            done := ir.Ins(ir.CALL)
            done.callee = self.fns[self.fn_by_name["__rt_task_done"]].id
            done.args = [1, result]
            append(fir.code, done)
            append(fir.code, ir.Ins(ir.RET))
            fir.vregs = v
            thunk = len(self.prog.functions)
            append(self.prog.functions, fir)
            self.async_thunks[fn_index] = thunk
        c := self.rt("__rt_alloc", [self.constant(24 + 8 * len(regs)), self.constant(0)])
        code := self.reg()
        fa := ir.Ins(ir.FUNC_ADDR)
        fa.dst = code
        fa.callee = thunk
        self.emit(fa)
        self.emit_op(ir.STORE64, -1, c, code, 0)
        self.emit_op(ir.STORE64, -1, c, self.str_const(f.decl.name), 8)
        i := 0
        while i < len(regs):
            self.emit_op(ir.STORE64, -1, c, regs[i], 24 + 8 * i)
            i += 1
        return Val(self.rt("__rt_task_new", [c]), self.future_of(f.ret))

    func asyncio_call(at, name, args, want):
        self.uses_async = true
        vs := []
        for a in args:
            if a.name != null:
                self.error(at, "asyncio." + name + "(...) : arguments positionnels seulement")
                return self.bad()
            v := self.expr_value(a.value)
            append(vs, v)
            if v.bad:
                return self.bad()
        if name == "future":
            if not self._arity(at, name, vs, 0):
                return self.bad()
            w := self.unnull(want)
            if w < 0 or self.kind(w) != K_FUTURE:
                self.error(at, "asyncio.future() : annoter le type du futur (p: future[int] := asyncio.future())")
                return self.bad()
            return Val(self.rt("__rt_future_new", [self.str_const("")]), w)
        if name == "sleep":
            if not self._arity(at, name, vs, 1):
                return self.bad()
            sec := self._seconds(at, name, vs, 0)
            return self.bad() if sec < 0 else Val(self.rt("__rt_sleep", [sec]), self.future_of(TVOID))
        if name == "now":
            if not self._arity(at, name, vs, 0):
                return self.bad()
            return Val(self.rt("__rt_now", []), TFLOAT)
        if name == "resolve":
            if not self._arity(at, name, vs, 2) or not self._fut(at, name, vs, 0):
                return self.bad()
            w := self.constant(0)
            if self.elem_of(vs[0].ty) != TVOID:
                if not self.expect_type(args[1].value, vs[1], self.elem_of(vs[0].ty), "valeur du futur"):
                    return self.bad()
                w = vs[1].reg
            return Val(self.rt("__rt_resolve", [vs[0].reg, w]), TBOOL)
        if name == "reject":
            if not self._arity(at, name, vs, 3) or not self._fut(at, name, vs, 0):
                return self.bad()
            if vs[1].ty != TSTR or vs[2].ty != TSTR:
                self.error(at, "asyncio.reject(f, type, message) : chaînes attendues")
                return self.bad()
            e := self.rt("__rt_exc_new", [vs[1].reg, vs[2].reg])
            return Val(self.rt("__rt_reject", [vs[0].reg, e]), TBOOL)
        if name == "cancel":
            if not self._arity(at, name, vs, 1) or not self._fut(at, name, vs, 0):
                return self.bad()
            return Val(self.rt("__rt_cancel", [vs[0].reg]), TBOOL)
        if name == "done" or name == "cancelled" or name == "failed":
            if not self._arity(at, name, vs, 1) or not self._fut(at, name, vs, 0):
                return self.bad()
            st := self.reg()
            r := self.reg()
            self.emit_op(ir.LOAD64, st, vs[0].reg, -1, 0)
            if name == "done":
                self.emit_op(ir.NE, r, st, self.constant(0))
            else:
                self.emit_op(ir.EQ, r, st, self.constant(2 if name == "failed" else 3))
            return Val(r, TBOOL)
        if name == "abandoned":
            if not self._arity(at, name, vs, 1) or not self._fut(at, name, vs, 0):
                return self.bad()
            return Val(self.rt("__rt_abandoned", [vs[0].reg]), TBOOL)
        if name == "result":
            if not self._arity(at, name, vs, 1) or not self._fut(at, name, vs, 0):
                return self.bad()
            w := self.rt("__rt_future_result", [vs[0].reg])
            return Val(-1, TVOID) if self.elem_of(vs[0].ty) == TVOID else Val(w, self.elem_of(vs[0].ty))
        if name == "is_future" or name == "is_task":
            if not self._arity(at, name, vs, 1):
                return self.bad()
            if self.kind(vs[0].ty) != K_FUTURE:
                return Val(self.constant(0), TBOOL)
            if name == "is_future":
                return Val(self.constant(1), TBOOL)
            r := self.reg()
            self.emit_op(ir.LOAD64, r, vs[0].reg, -1, 40)
            return Val(r, TBOOL)
        if name == "timeout":
            if not self._arity(at, name, vs, 2) or not self._fut(at, name, vs, 0):
                return self.bad()
            sec := self._seconds(at, name, vs, 1)
            return self.bad() if sec < 0 else Val(self.rt("__rt_timeout", [vs[0].reg, sec]), vs[0].ty)
        if name == "race" or name == "gather":
            if not self._arity(at, name, vs, 1):
                return self.bad()
            if self.kind(vs[0].ty) != K_LIST or self.kind(self.elem_of(vs[0].ty)) != K_FUTURE:
                self.error(at, "asyncio." + name + "(...) : liste de futurs attendue")
                return self.bad()
            ft := self.elem_of(vs[0].ty)
            if name == "race":
                return Val(self.rt("__rt_race", [vs[0].reg]), ft)
            return Val(self.rt("__rt_gather", [vs[0].reg]), self.future_of(self.list_of(TNULL if self.elem_of(ft) == TVOID else self.elem_of(ft))))
        self.error(at, "asyncio." + name + " : non disponible en natif")
        return self.bad()

    func _arity(at, name, vs, n):
        if len(vs) == n:
            return true
        self.error(at, "asyncio." + name + "(...) attend " + str(n) + " argument(s)")
        return false

    func _fut(at, name, vs, i):
        if self.kind(vs[i].ty) == K_FUTURE:
            return true
        self.error(at, "asyncio." + name + "(...) : futur attendu, obtenu " + self.ty_name(vs[i].ty))
        return false

    func _seconds(at, name, vs, i):
        if vs[i].ty == TINT:
            return self.to_float(vs[i])
        if vs[i].ty == TFLOAT:
            return vs[i].reg
        self.error(at, "asyncio." + name + "(...) : délai en secondes attendu")
        return -1

    func inline_asm(at, args, value):
        if len(args) != 1 or args[0].name != null or args[0].value.kind != "Literal" or args[0].value.literal_kind != "String":
            self.error(at, "asm(...) : un littéral de chaîne d'octets hexadécimaux attendu, ex. asm(\"fa f4\")")
            return self.bad()
        text := _s.byte_unpack(args[0].value.value)
        out := []
        digit := []
        i := 0
        n := len(text)
        while i < n:
            ch := text[i]
            if ch == 0x30 and i + 1 < n and (text[i + 1] == 0x78 or text[i + 1] == 0x58) and len(digit) == 0:
                i += 2
                continue
            hv := _hexval(ch)
            if hv >= 0:
                append(digit, hv)
                if len(digit) == 2:
                    append(out, digit[0] * 16 + digit[1])
                    digit = []
            elif ch == 0x20 or ch == 0x2c or ch == 0x09 or ch == 0x0a:
                if len(digit) > 0:
                    self.error(at, "asm(...) : octet incomplet '" + _s.byte_pack([text[i - 1]]) + "'")
                    return self.bad()
            else:
                self.error(at, "asm(...) : caractère inattendu '" + _s.byte_pack([ch]) + "'")
                return self.bad()
            i += 1
        if len(digit) > 0:
            self.error(at, "asm(...) : octet incomplet '" + _s.byte_pack([text[n - 1]]) + "'")
            return self.bad()
        bs := _s.byte_pack(out)
        self.str_const(bs)
        ri := ir.Ins(ir.RAW_CODE)
        ri.imm = self.str_index[bs]
        ri.dst = self.reg() if value else -1
        dst := ri.dst
        self.emit(ri)
        return Val(dst, TINT) if value else Val(-1, TVOID)

    func _save_ctx():
        return [self.scopes, self.fn_scope_base, self.ret_ty, self.cur_line, self.mod_, self.cur_owner, self.fn_name, self.in_main, self.loops, self.tries, self.box_names, self.fn_]

    func _restore_ctx(s):
        self.scopes = s[0]
        self.fn_scope_base = s[1]
        self.ret_ty = s[2]
        self.cur_line = s[3]
        self.mod_ = s[4]
        self.cur_owner = s[5]
        self.fn_name = s[6]
        self.in_main = s[7]
        self.loops = s[8]
        self.tries = s[9]
        self.box_names = s[10]
        self.fn_ = s[11]

    func _copy_scope(sc):
        out := {}
        for k in sc:
            out[k] = sc[k].copy()
        return out

    func call_generic(at, fn_index, args):
        f := self.fns[fn_index]
        n := len(f.params)
        exprs := [null for i in 0..n]
        pos := 0
        for a in args:
            idx := pos
            pos += 1
            if a.name != null:
                idx = n
                i := 0
                while i < n:
                    if f.names[i] == a.name:
                        idx = i
                    i += 1
            if idx >= n:
                self.error(at, "argument en trop ou inconnu dans l'appel de " + f.name)
                return self.bad()
            exprs[idx] = a.value
        regs := []
        tys := []
        i := 0
        while i < n:
            e := exprs[i] if exprs[i] != null else f.decl.params[i].default_value
            if e == null:
                self.error(at, "argument '" + f.names[i] + "' manquant dans l'appel de " + f.name)
                return self.bad()
            v := self.expr_value(e, f.params[i])
            if v.bad:
                return v
            if f.params[i] >= 0:
                if v.ty == TINT and f.params[i] == TFLOAT and self.mods[f.module].stdlib:
                    v = Val(self.to_float(v), TFLOAT)
                if not self.expect_type(e, v, f.params[i], "argument '" + f.names[i] + "' de " + f.name):
                    return self.bad()
            append(regs, v.reg)
            append(tys, v.ty)
            i += 1
        key := str(fn_index) + ":" + _s.join(",", [str(t) for t in tys])
        if not (key in self.specs):
            fir := ir.IrFunction(f.name)
            fir.file = self.mods[f.module].file
            fir.params = len(tys)
            fir.vregs = fir.params
            fid := len(self.prog.functions)
            append(self.prog.functions, fir)
            self.specs[key] = [fid, f.ret]
            saved := self._save_ctx()
            self.fn_ = fir
            self.scopes = [self._copy_scope(saved[0][0]), {}]
            self.fn_scope_base = 1
            self.in_main = false
            self.loops = []
            self.tries = []
            self.mod_ = f.module
            self.cur_owner = -1
            self.ret_ty = f.ret
            self.fn_name = f.name
            self.cur_line = f.decl.line
            self.box_names = self.captured_names(f.decl.body.statements, false)
            i = 0
            while i < len(tys):
                pv := Var(tys[i], false, i)
                if f.names[i] in self.box_names:
                    pv.boxed = true
                    pv.index = self.rt("__rt_alloc", [self.constant(8), self.constant(0)])
                    self.emit_op(ir.STORE64, -1, pv.index, i, 0)
                self.scopes[1][f.names[i]] = pv
                i += 1
            self.statements(f.decl.body.statements)
            body := f.decl.body.statements
            if len(body) > 0:
                self.cur_line = body[len(body) - 1].line
            if self.ret_ty == -2:
                self.ret_ty = TVOID
            if self.ret_ty == TVOID:
                self.emit(ir.Ins(ir.RET))
            else:
                self.emit_op(ir.FAIL, -1, -1, -1, self.message("TypeError: valeur de retour de " + f.name + " : attendu " + self.ty_name(self.ret_ty) + ", obtenu null"))
            self.fn_.returns_value = self.ret_ty != TVOID
            self.specs[key][1] = self.ret_ty
            new_global := self.scopes[0]
            self._restore_ctx(saved)
            self.scopes[0] = new_global
        sp := self.specs[key]
        if sp[1] == -2:
            self.error(at, f.name + " : appel récursif d'une fonction non typée ; annoter son type de retour")
            return self.bad()
        cl := ir.Ins(ir.CALL)
        cl.callee = sp[0]
        cl.args = regs
        cl.dst = -1 if sp[1] == TVOID else self.reg()
        dst := cl.dst
        self.emit(cl)
        return Val(dst, sp[1])

    func call_function(at, f, args, self_reg):
        if f.owner < 0 and self.prog.files[self.mods[f.module].file] == "<stdlib natif>/asyncio.al":
            return self.asyncio_call(at, f.name, args, self.want_)
        if f.is_async:
            return self.call_async(at, f.index, args, self_reg)
        if (f.name == "asm" or f.name == "asm_value") and f.owner < 0 and self.prog.files[self.mods[f.module].file] == "<stdlib natif>/hw.al":
            return self.inline_asm(at, args, f.name == "asm_value")
        if f.generic:
            return self.call_generic(at, f.index, args)
        pa := self.prepare_args(at, f, args, self_reg)
        if not pa[1]:
            return self.bad()
        return self.emit_call(f, pa[0])

    func construct(c, sid):
        s := self.structs[sid]
        if s.is_interface:
            self.error(c, "'" + s.name + "' est une interface : elle ne s'instancie pas")
            return self.bad()
        obj := self.reg()
        self.emit_op(ir.COPY, obj, self.rt("__rt_alloc", [self.constant(8 * (len(s.fields) + 1)), self.constant(0)]))
        self.emit_op(ir.STORE64, -1, obj, self.str_const("<" + s.name + " instance>"), 0)
        i := 0
        while i < len(s.fields):
            if s.defaults[i] != null:
                v := self.expr_value(s.defaults[i], s.field_ty[i])
                if self.expect_type(s.defaults[i], v, s.field_ty[i], "champ '" + s.fields[i] + "'"):
                    self.emit_op(ir.STORE64, -1, obj, v.reg, 8 * (i + 1))
            i += 1
        init := self.find_method(sid, "init")
        if init >= 0:
            r := self.call_function(c, self.fns[init], c.arguments, obj)
            if r.bad:
                return r
        elif len(c.arguments) > 0:
            self.error(c, "'" + s.name + "' n'a pas de méthode init : aucun argument attendu")
            return self.bad()
        return Val(obj, s.ty)

    func call_method(c, obj, name):
        sid := self.sid_of(obj.ty)
        s := self.structs[sid]
        decl_idx := self.find_method(sid, name)
        if decl_idx < 0:
            self.error(c, "'" + s.name + "' n'a pas de méthode '" + name + "'")
            return self.bad()
        decl := self.fns[decl_idx]
        impls := []
        for sub in self.concrete_subs(sid):
            m := self.find_method(sub, name)
            if m < 0 or self.fns[m].abstract:
                self.error(c, "la classe '" + self.structs[sub].name + "' n'implémente pas '" + name + "'")
                return self.bad()
            append(impls, [sub, m])
        pa := self.prepare_args(c, decl, c.arguments, obj.reg)
        if not pa[1]:
            return self.bad()
        regs := pa[0]
        same := true
        for p in impls:
            same = same and p[1] == impls[0][1]
        if len(impls) == 0:
            if decl.abstract:
                self.error(c, "aucune classe n'implémente '" + name + "'")
                return self.bad()
            return self.invoke(decl_idx, regs)
        if same:
            return self.invoke(impls[0][1], regs)
        res_ty := self.future_of(decl.ret) if decl.is_async else decl.ret
        header := self.reg()
        result := -1 if res_ty == TVOID else self.reg()
        l_end := self.label()
        self.emit_op(ir.LOAD64, header, obj.reg, -1, 0)
        k := 0
        while k < len(impls):
            l_next := self.label()
            if k + 1 < len(impls):
                eq := self.reg()
                self.emit_op(ir.EQ, eq, header, self.str_const("<" + self.structs[impls[k][0]].name + " instance>"))
                self.jump(ir.JMP_IF_ZERO, l_next, eq)
            r := self.invoke(impls[k][1], regs)
            if result >= 0:
                self.emit_op(ir.COPY, result, r.reg)
            self.jump(ir.JMP, l_end)
            self.place(l_next)
            k += 1
        self.place(l_end)
        return Val(result, res_ty)

    func call(c):
        if c.callee.kind == "MemberExpr":
            m := c.callee
            if m.object.kind == "Identifier" and m.object.name == "super":
                base := self.structs[self.cur_owner].base if self.cur_owner >= 0 else -1
                target := self.find_method(base, m.member) if base >= 0 else -1
                me := self.lookup("self")
                if target < 0 or me == null:
                    self.error(c, "super." + m.member + "(...) : aucune méthode de classe de base correspondante")
                    return self.bad()
                return self.call_function(c, self.fns[target], c.arguments, self.read(me).reg)
            eid := self.enum_of(m.object)
            if eid >= 0:
                return self.enum_variant(c, eid, m.member, c.arguments)
            target := self.module_of(m.object)
            if target >= 0:
                key := self.mods[target].prefix + m.member
                if key in self.struct_by_name:
                    return self.construct(c, self.struct_by_name[key])
                if key in self.fn_by_name:
                    return self.call_function(c, self.fns[self.fn_by_name[key]], c.arguments, -1)
                fv := self.module_member(m, target)
                return fv if fv.bad else self.call_value(c, fv)
            if m.object.kind == "Identifier" and self.lookup(m.object.name) == null:
                return self.unsupported(c, "appel '" + m.object.name + "." + m.member + "(...)' (module non importé)")
            obj := self.expr_value(m.object)
            if obj.bad:
                return obj
            if self.kind(obj.ty) != K_STRUCT:
                self.error(c, "appel de méthode '" + m.member + "' sur " + self.ty_name(obj.ty))
                return self.bad()
            return self.call_method(c, obj, m.member)
        if c.callee.kind != "Identifier":
            f := self.expr_value(c.callee)
            return f if f.bad else self.call_value(c, f)
        name := c.callee.name
        if name == "print" and self.lookup(name) == null:
            self.print_(c)
            return Val(-1, TVOID)
        if name == "input" and self.lookup(name) == null:
            if len(c.arguments) > 1 or (len(c.arguments) == 1 and c.arguments[0].name != null):
                self.error(c, "input(...) accepte au plus un argument (l'invite)")
                return self.bad()
            if len(c.arguments) == 1:
                self.print_(c)
            return Val(self.rt("__rt_input", []), TSTR)
        hv := self.intrinsic(c, name)
        if hv[0]:
            return hv[1]
        var := self.lookup(name)
        if var != null:
            return self.call_value(c, self.read(var.copy()))
        sid := self.find_struct(name)
        if sid >= 0:
            return self.construct(c, sid)
        if name in self.failed_locals:
            return self.bad()
        privileged := self.in_runtime or self.mods[self.mod_].stdlib
        fi := -1
        if privileged and _starts(name, "__rt_"):
            fi = self.fn_by_name[name] if name in self.fn_by_name else -1
        else:
            fi = self.find_fn(name)
        if fi < 0 or (self.fns[fi].runtime and not privileged):
            if name == "type":
                return self.unsupported(c, "'" + name + "(...)'")
            return self.unsupported(c, "appel de '" + name + "' (fonction inconnue du programme natif)")
        return self.call_function(c, self.fns[fi], c.arguments, -1)

    # ------------------------------------------------------------------ affectations et boucles
    func assign(s, target, value, op):
        if target.kind == "Identifier":
            name := target.name
            sl := self.lookup_slot(name)
            if sl == null:
                self.unsupported(target, "'" + name + "' (nom inconnu du programme natif)")
                return
            vcopy := sl[0][sl[1]].copy()
            v := self.expr_value(value, vcopy.ty)
            if v.bad:
                return
            if vcopy.view and op == null and (v.ty == vcopy.o_ty or v.ty == TNULL):
                orig := vcopy.original()
                if not self.expect_type(value, v, orig.ty, "variable '" + name + "'"):
                    return
                self.write(orig, v.reg)
                sl[0][sl[1]] = orig
                return
            if op != null:
                v = self.arith(s, op, self.read(vcopy), v)
            if not self.expect_type(value, v, vcopy.ty, "variable '" + name + "'"):
                return
            self.write(vcopy, v.reg)
            return
        if target.kind == "IndexExpr":
            obj := self.expr_value(target.object)
            if not obj.bad and self.kind(obj.ty) == K_TUPLE:
                self.error(target, "un tuple est immuable : affectation indexée impossible")
                return
            if not obj.bad and self.kind(obj.ty) == K_DICT:
                key := self.expr_value(target.index, self.elem_of(obj.ty))
                if not self.expect_type(target.index, key, self.elem_of(obj.ty), "clé de dict"):
                    return
                v := self.expr_value(value, self.val_of(obj.ty))
                if v.bad:
                    return
                if op != null:
                    ent := self.dict_index(obj.reg, key)
                    neg := self.reg()
                    self.emit_op(ir.LT, neg, ent, self.constant(0))
                    self.fail_if(neg, ir.MSG_KEY_ERROR)
                    vals := self.reg()
                    cur := self.reg()
                    self.emit_op(ir.LOAD64, vals, obj.reg, -1, 32)
                    self.emit_op(ir.LOAD_ELEM, cur, vals, ent)
                    v = self.arith(s, op, Val(cur, self.val_of(obj.ty)), v)
                if not self.expect_type(value, v, self.val_of(obj.ty), "valeur de dict"):
                    return
                self.rt("__rt_dict_set", [obj.reg, key.reg, v.reg, self.constant(self.key_kind(key.ty))], false)
                return
            idx := self.expr_value(target.index)
            if obj.bad or idx.bad:
                return
            if self.kind(obj.ty) != K_LIST:
                self.error(target, "affectation indexée sur " + self.ty_name(obj.ty) + (" (chaînes immuables)" if obj.ty == TSTR else ""))
                return
            if idx.ty != TINT:
                self.error(target.index, "index : attendu int, obtenu " + self.ty_name(idx.ty))
                return
            ln := self.list_len(obj.reg)
            idx.reg = self.norm_index(idx.reg, ln)
            self.bounds_check(idx.reg, ln)
            data := self.list_data(obj.reg)
            v := self.expr_value(value, self.elem_of(obj.ty))
            if v.bad:
                return
            if op != null:
                cur := self.reg()
                self.emit_op(ir.LOAD_ELEM, cur, data, idx.reg)
                v = self.arith(s, op, Val(cur, self.elem_of(obj.ty)), v)
            if not self.expect_type(value, v, self.elem_of(obj.ty), "élément de liste"):
                return
            st := ir.Ins(ir.STORE_ELEM)
            st.a = data
            st.b = idx.reg
            st.args = [v.reg]
            self.emit(st)
            return
        if target.kind == "MemberExpr":
            fr := self.field_ref(target)
            if fr[0].bad:
                return
            fty := fr[0].ty
            v := self.expr_value(value, fty)
            if v.bad:
                return
            if op != null:
                cur := self.reg()
                self.emit_op(ir.LOAD64, cur, fr[1], -1, 8 * fr[2])
                v = self.arith(s, op, Val(cur, fty), v)
            if not self.expect_type(value, v, fty, "champ '" + target.member + "'"):
                return
            self.emit_op(ir.STORE64, -1, fr[1], v.reg, 8 * fr[2])
            return
        self.unsupported(target, "cible d'affectation")

    func loop_var(name, ty, value_reg):
        v := Var(ty, false, value_reg)
        if name in self.box_names:
            v.boxed = true
            v.index = self.rt("__rt_alloc", [self.constant(8), self.constant(0)])
            self.emit_op(ir.STORE64, -1, v.index, value_reg, 0)
        self.scopes[len(self.scopes) - 1][name] = v
        return v

    func comprehension(c, want):
        is_dict := c.comp_kind == "Dict"
        st := [-1, -1, true]    # type élément / clé, type valeur, ok
        if want >= 0 and not is_dict and self.kind(want) == K_LIST:
            st[0] = self.elem_of(want)
        if want >= 0 and is_dict and self.kind(want) == K_DICT:
            st[0] = self.elem_of(want)
            st[1] = self.val_of(want)
        out := self.reg()
        self.emit_op(ir.COPY, out, self.rt("__rt_dict_new", [self.constant(8)]) if is_dict else self.rt("__rt_list_new", [self.constant(0)]))
        self.push_scope()
        self.comp_clause(c, 0, out, st, is_dict)
        self.pop_scope()
        if not st[2]:
            return self.bad()
        if st[0] < 0 or (is_dict and st[1] < 0):
            self.error(c, "compréhension : type des éléments inconnu")
            return self.bad()
        return Val(out, self.dict_of(st[0], st[1]) if is_dict else self.list_of(st[0]))

    func comp_clause(c, i, out, st, is_dict):
        if not st[2]:
            return
        if i == len(c.clauses):
            ke := c.key if is_dict else c.element
            k := self.expr_value(ke, st[0])
            if k.bad:
                st[2] = false
                return
            if st[0] < 0:
                st[0] = k.ty
            if not self.expect_type(ke, k, st[0], "clé de dict" if is_dict else "élément de liste (en natif, une liste est homogène)"):
                st[2] = false
                return
            if not is_dict:
                self.rt("__rt_list_push", [out, k.reg], false)
                return
            if not (self.is_scalar(st[0]) or st[0] == TSTR):
                self.error(ke, "clé de dict de type " + self.ty_name(st[0]) + " : int, bool, float ou str attendu")
                st[2] = false
                return
            v := self.expr_value(c.value, st[1])
            if v.bad:
                st[2] = false
                return
            if st[1] < 0:
                st[1] = v.ty
            if not self.expect_type(c.value, v, st[1], "valeur de dict"):
                st[2] = false
                return
            self.rt("__rt_dict_set", [out, k.reg, v.reg, self.constant(self.key_kind(st[0]))], false)
            return
        cl := c.clauses[i]
        if cl.clause_kind == "If":
            skip := self.label()
            self.jump(ir.JMP_IF_ZERO, skip, self.truthy(cl.expr, self.expr_value(cl.expr)))
            self.comp_clause(c, i + 1, out, st, is_dict)
            self.place(skip)
            return
        self.iterate(cl.variable, cl.expr, ["comp", c, i + 1, out, st, is_dict], false)

    func run_body(body):
        if body[0] == "stmts":
            self.statements(body[1])
        else:
            self.comp_clause(body[1], body[2], body[3], body[4], body[5])

    func iterate(variable, iterable, body, is_loop):
        l_top := self.label()
        l_cont := self.label()
        l_end := self.label()
        one := self.constant(1)
        if iterable.kind == "RangeExpr":
            lo := self.expr_value(iterable.start)
            hi := self.expr_value(iterable.end)
            if lo.bad or hi.bad:
                return
            if lo.ty != TINT or hi.ty != TINT:
                self.error(iterable, "bornes d'intervalle : int attendu")
                return
            i := self.reg()
            end := self.reg()
            self.emit_op(ir.COPY, i, lo.reg)
            self.emit_op(ir.COPY, end, hi.reg)
            self.place(l_top)
            t := self.reg()
            self.emit_op(ir.LT, t, i, end)
            self.jump(ir.JMP_IF_ZERO, l_end, t)
            self.push_scope()
            lv := self.loop_var(variable, TINT, i)
            if is_loop:
                append(self.loops, Loop(l_end, l_cont, len(self.tries)))
            self.run_body(body)
            if is_loop:
                self.loops = self.loops[0:len(self.loops) - 1]
            self.pop_scope()
            self.place(l_cont)
            if lv.boxed:
                self.emit_op(ir.LOAD64, i, lv.index, -1, 0)
            self.emit_op(ir.ADD, i, i, one)
            self.jump(ir.JMP, l_top)
            self.place(l_end)
            return
        coll := self.expr_value(iterable)
        if coll.bad:
            return
        if self.kind(coll.ty) == K_DICT:
            obj := self.reg()
            e := self.constant(0)
            self.emit_op(ir.COPY, obj, coll.reg)
            self.place(l_top)
            used := self.reg()
            t := self.reg()
            self.emit_op(ir.LOAD64, used, obj, -1, 8)
            self.emit_op(ir.LT, t, e, used)
            self.jump(ir.JMP_IF_ZERO, l_end, t)
            hashes := self.reg()
            h := self.reg()
            neg := self.reg()
            self.emit_op(ir.LOAD64, hashes, obj, -1, 40)
            self.emit_op(ir.LOAD_ELEM, h, hashes, e)
            self.emit_op(ir.LT, neg, h, self.constant(0))
            self.jump(ir.JMP_IF_NON_ZERO, l_cont, neg)
            self.push_scope()
            keys := self.reg()
            k := self.reg()
            self.emit_op(ir.LOAD64, keys, obj, -1, 24)
            self.emit_op(ir.LOAD_ELEM, k, keys, e)
            self.loop_var(variable, self.elem_of(coll.ty), k)
            if is_loop:
                append(self.loops, Loop(l_end, l_cont, len(self.tries)))
            self.run_body(body)
            if is_loop:
                self.loops = self.loops[0:len(self.loops) - 1]
            self.pop_scope()
            self.place(l_cont)
            self.emit_op(ir.ADD, e, e, one)
            self.jump(ir.JMP, l_top)
            self.place(l_end)
            return
        if self.kind(coll.ty) == K_TUPLE:
            et := self.tuple_elem(coll.ty)
            if et < 0:
                self.error(iterable, "for sur un tuple hétérogène (" + self.ty_name(coll.ty) + ")")
                return
            data := self.reg()
            i := self.constant(0)
            self.emit_op(ir.ADD, data, coll.reg, self.constant(8))
            self.place(l_top)
            t := self.reg()
            self.emit_op(ir.LT, t, i, self.constant(len(self.elems_of(coll.ty))))
            self.jump(ir.JMP_IF_ZERO, l_end, t)
            self.push_scope()
            x := self.reg()
            self.emit_op(ir.LOAD_ELEM, x, data, i)
            self.loop_var(variable, et, x)
            if is_loop:
                append(self.loops, Loop(l_end, l_cont, len(self.tries)))
            self.run_body(body)
            if is_loop:
                self.loops = self.loops[0:len(self.loops) - 1]
            self.pop_scope()
            self.place(l_cont)
            self.emit_op(ir.ADD, i, i, one)
            self.jump(ir.JMP, l_top)
            self.place(l_end)
            return
        if self.kind(coll.ty) != K_LIST and coll.ty != TSTR:
            self.error(iterable, "for sur " + self.ty_name(coll.ty))
            return
        obj := self.reg()
        i := self.constant(0)
        self.emit_op(ir.COPY, obj, coll.reg)
        self.place(l_top)
        ln := self.rt("__rt_str_len", [obj]) if coll.ty == TSTR else self.list_len(obj)
        t := self.reg()
        self.emit_op(ir.LT, t, i, ln)
        self.jump(ir.JMP_IF_ZERO, l_end, t)
        self.push_scope()
        x := self.reg()
        if coll.ty == TSTR:
            self.emit_op(ir.COPY, x, self.rt("__rt_str_char_at", [obj, i]))
        else:
            self.emit_op(ir.LOAD_ELEM, x, self.list_data(obj), i)
        self.loop_var(variable, TCHAR if coll.ty == TSTR else self.elem_of(coll.ty), x)
        if is_loop:
            append(self.loops, Loop(l_end, l_cont, len(self.tries)))
        self.run_body(body)
        if is_loop:
            self.loops = self.loops[0:len(self.loops) - 1]
        self.pop_scope()
        self.place(l_cont)
        self.emit_op(ir.ADD, i, i, one)
        self.jump(ir.JMP, l_top)
        self.place(l_end)

    # ------------------------------------------------------------------ instructions
    func stmt(s):
        saved_line := self.cur_line
        if s.line > 0:
            self.cur_line = s.line
        self.stmt_inner(s)
        self.cur_line = saved_line

    func _narrowed_block(body, name):
        self.push_scope()
        if name != "":
            self.narrow(name)
        if body != null:
            self.statements(body.statements)
        self.pop_scope()

    func stmt_inner(s):
        k := s.kind
        if k == "VariableDecl" or k == "ConstDecl":
            name := s.name
            ann := s.type
            value := s.value
            want := -1
            if ann != null:
                want = self.type_of(ann)
                if want < 0:
                    self.error_at(ann.line, ann.column, "type '" + _bt.type_ref_string(ann) + "' non supporté en natif")
            v := self.expr_value(value, want)
            if not v.bad and ann == null and v.ty == TNULL:
                self.error(value, "variable '" + name + "' initialisée à null : annoter son type (" + name + ": T? := null)")
                v.bad = true
            ty := want if want >= 0 else v.ty
            ok := false
            if not v.bad:
                ok = (ann == null) if want < 0 else self.expect_type(value, v, want, "variable '" + name + "'")
            if not ok:
                self.scopes[len(self.scopes) - 1][name] = Var(TINT if ty == TVOID else ty, false, self.reg())
                return
            self.declare(name, ty, v.reg)
            return
        if k == "Assignment":
            self.assign(s, s.target, s.value, null)
            return
        if k == "CompoundAssignment":
            self.assign(s, s.target, s.value, s.op)
            return
        if k == "ExpressionStmt":
            self.expr(s.expr)
            return
        if k == "IfStmt":
            self.if_stmt(s)
            return
        if k == "WhileStmt":
            if s.else_body != null:
                self.error(s, "'while ... else' n'est pas supporté par le compilateur natif")
            l_top := self.label()
            l_end := self.label()
            self.place(l_top)
            self.jump(ir.JMP_IF_ZERO, l_end, self.truthy(s.condition, self.expr_value(s.condition)))
            append(self.loops, Loop(l_end, l_top, len(self.tries)))
            nt := self.null_test(s.condition)
            self.push_scope()
            if nt != null and nt[1]:
                self.narrow(nt[0].name)
            self.statements(s.body.statements)
            self.pop_scope()
            self.loops = self.loops[0:len(self.loops) - 1]
            self.jump(ir.JMP, l_top)
            self.place(l_end)
            return
        if k == "ForStmt":
            if s.else_body != null:
                self.error(s, "'for ... else' n'est pas supporté par le compilateur natif")
            self.iterate(s.variable, s.iterable, ["stmts", s.body.statements], true)
            return
        if k == "BreakStmt" or k == "ContinueStmt":
            if len(self.loops) == 0:
                self.error(s, "'break'/'continue' hors d'une boucle")
                return
            lp := self.loops[len(self.loops) - 1]
            self.leave_tries(lp.tries)
            self.jump(ir.JMP, lp.brk if k == "BreakStmt" else lp.cont)
            return
        if k == "ReturnStmt":
            self.return_stmt(s)
            return
        if k == "FunctionDecl":
            if not self.in_main or len(self.scopes) > 1:
                self.local_function(s)
            return
        if k == "StructDecl" or k == "ClassDecl":
            if not self.in_main or len(self.scopes) > 1:
                self.unsupported(s, "struct / class imbriquée")
            return
        if k == "InterfaceDecl":
            if not self.in_main or len(self.scopes) > 1:
                self.unsupported(s, "interface imbriquée")
            return
        if k == "EnumDecl":
            if not self.in_main or len(self.scopes) > 1:
                self.unsupported(s, "enum imbriqué")
            return
        if k == "ImportStmt":
            if s.uid in self.mods[self.mod_].resolved:
                return
            allowed := null
            if s.is_from and len(s.module_path) == 1 and (s.module_path[0] in IMPORT_ALLOWED):
                allowed = IMPORT_ALLOWED[s.module_path[0]]
            if allowed == null:
                self.unsupported(s, "import de module (seuls `from core use len, to_int, to_float` et `from collections use append, keys, values, get, contains_key, remove, set` sont reconnus en natif pour l'instant)")
                return
            for name in s.names:
                if name in allowed:
                    self.imported[name] = true
                else:
                    self.unsupported(s, "'" + name + "' du module " + s.module_path[0] + "")
            return
        if k == "TryStmt":
            self.try_stmt(s)
            return
        if k == "MatchStmt":
            self.match_stmt(s)
            return
        self.unsupported(s, "instruction")

    func if_stmt(n):
        if (self.in_runtime or self.mods[self.mod_].stdlib) and n.condition.kind == "CallExpr" and len(n.elif_clauses) == 0:
            cc := n.condition
            cn := cc.callee.name if cc.callee.kind == "Identifier" and len(cc.arguments) == 0 else null
            if cn == "__freestanding" or cn == "__windows" or cn == "__uefi" or cn == "__a64" or cn == "__dyn" or cn == "__alexos":
                on := self.freestanding if cn == "__freestanding" else self.windows if cn == "__windows" else self.a64 if cn == "__a64" else self.dyn if cn == "__dyn" else _alexos[0] if cn == "__alexos" else self.uefi
                chosen := n.then_block if on else n.else_block
                if chosen != null:
                    self.push_scope()
                    self.statements(chosen.statements)
                    self.pop_scope()
                return
        l_end := self.label()
        nt := self.null_test(n.condition)
        first_not_null := nt != null and nt[1]
        tested := nt[0].name if nt != null else ""
        self._branch(n.condition, n.then_block, tested if nt != null and first_not_null else "", l_end)
        for e in n.elif_clauses:
            self._branch(e.condition, e.body, "", l_end)
        if n.else_block != null:
            self._narrowed_block(n.else_block, tested if nt != null and not first_not_null and len(n.elif_clauses) == 0 else "")
        self.place(l_end)

    func _branch(cond, body, name, l_end):
        l_next := self.label()
        self.jump(ir.JMP_IF_ZERO, l_next, self.truthy(cond, self.expr_value(cond)))
        self._narrowed_block(body, name)
        self.jump(ir.JMP, l_end)
        self.place(l_next)

    func return_stmt(s):
        if self.in_main:
            self.unsupported(s, "'return' au niveau du module")
            return
        i := ir.Ins(ir.RET)
        if s.value != null and (self.ret_ty == -2 or self.ret_ty == TVOID):
            v := self.expr(s.value)
            if v.bad:
                return
            if v.ty == TVOID:
                if self.ret_ty == -2:
                    self.ret_ty = TVOID
                self.leave_tries(0)
                self.emit(i)
                return
            if self.ret_ty == -2:
                self.ret_ty = v.ty
                keep := self.reg()
                self.emit_op(ir.COPY, keep, v.reg)
                i.a = keep
                self.leave_tries(0)
                self.emit(i)
                return
        if s.value != null:
            if self.ret_ty == TVOID:
                self.error(s, "'return' avec valeur : annoter le type de retour de " + self.fn_name)
                return
            v := self.expr_value(s.value, self.ret_ty)
            if not self.expect_type(s.value, v, self.ret_ty, "valeur de retour de " + self.fn_name):
                return
            keep := self.reg()
            self.emit_op(ir.COPY, keep, v.reg)
            i.a = keep
        elif self.ret_ty == -2:
            self.ret_ty = TVOID
        elif self.ret_ty != TVOID:
            self.error(s, "valeur de retour de " + self.fn_name + " : attendu " + self.ty_name(self.ret_ty) + ", 'return' sans valeur")
            return
        self.leave_tries(0)
        self.emit(i)

    # ------------------------------------------------------------------ fermetures
    func collect_idents(n, out):
        if n == null:
            return
        k := n.kind
        if k == "Identifier":
            out[n.name] = true
        elif k == "ListLiteral" or k == "TupleLiteral":
            for x in n.elements:
                self.collect_idents(x, out)
        elif k == "DictLiteral":
            for kv in n.entries:
                self.collect_idents(kv.key, out)
                self.collect_idents(kv.value, out)
        elif k == "FStringLiteral":
            for p in n.parts:
                if p.is_expr:
                    self.collect_idents(p.expr, out)
        elif k == "BinaryExpr":
            self.collect_idents(n.left, out)
            self.collect_idents(n.right, out)
        elif k == "UnaryExpr" or k == "ErrorPropagationExpr":
            self.collect_idents(n.operand, out)
        elif k == "ConditionalExpr":
            self.collect_idents(n.condition, out)
            self.collect_idents(n.then_expr, out)
            self.collect_idents(n.else_expr, out)
        elif k == "RangeExpr":
            self.collect_idents(n.start, out)
            self.collect_idents(n.end, out)
        elif k == "CallExpr":
            self.collect_idents(n.callee, out)
            for a in n.arguments:
                self.collect_idents(a.value, out)
        elif k == "IndexExpr":
            self.collect_idents(n.object, out)
            self.collect_idents(n.index, out)
        elif k == "MemberExpr":
            self.collect_idents(n.object, out)
        elif k == "LambdaExpr":
            self.collect_idents(n.function, out)
        elif k == "ComprehensionExpr":
            self.collect_idents(n.element, out)
            self.collect_idents(n.key, out)
            self.collect_idents(n.value, out)
            for cl in n.clauses:
                self.collect_idents(cl.expr, out)
        elif k == "Block":
            for st in n.statements:
                self.collect_idents(st, out)
        elif k == "VariableDecl" or k == "ConstDecl":
            self.collect_idents(n.value, out)
        elif k == "Assignment" or k == "CompoundAssignment":
            self.collect_idents(n.target, out)
            self.collect_idents(n.value, out)
        elif k == "ExpressionStmt":
            self.collect_idents(n.expr, out)
        elif k == "IfStmt":
            self.collect_idents(n.condition, out)
            self.collect_idents(n.then_block, out)
            for c in n.elif_clauses:
                self.collect_idents(c.condition, out)
                self.collect_idents(c.body, out)
            self.collect_idents(n.else_block, out)
        elif k == "WhileStmt":
            self.collect_idents(n.condition, out)
            self.collect_idents(n.body, out)
        elif k == "ForStmt":
            self.collect_idents(n.iterable, out)
            self.collect_idents(n.body, out)
        elif k == "ReturnStmt":
            self.collect_idents(n.value, out)
        elif k == "TryStmt":
            self.collect_idents(n.try_block, out)
            for c in n.catch_clauses:
                self.collect_idents(c.body, out)
            self.collect_idents(n.finally_block, out)
        elif k == "MatchStmt":
            self.collect_idents(n.subject, out)
            for c in n.cases:
                self.collect_idents(c.guard, out)
                self.collect_idents(c.body, out)
        elif k == "FunctionDecl":
            out[n.name] = true
            for p in n.params:
                self.collect_idents(p.default_value, out)
            self.collect_idents(n.body, out)

    func _find_captures(m, out):
        if m == null:
            return
        k := m.kind
        if k == "LambdaExpr" or k == "FunctionDecl":
            self.collect_idents(m, out)
            return
        if k == "ListLiteral" or k == "TupleLiteral":
            for x in m.elements:
                self._find_captures(x, out)
        elif k == "DictLiteral":
            for kv in m.entries:
                self._find_captures(kv.key, out)
                self._find_captures(kv.value, out)
        elif k == "FStringLiteral":
            for p in m.parts:
                if p.is_expr:
                    self._find_captures(p.expr, out)
        elif k == "BinaryExpr":
            self._find_captures(m.left, out)
            self._find_captures(m.right, out)
        elif k == "UnaryExpr":
            self._find_captures(m.operand, out)
        elif k == "ConditionalExpr":
            self._find_captures(m.condition, out)
            self._find_captures(m.then_expr, out)
            self._find_captures(m.else_expr, out)
        elif k == "CallExpr":
            self._find_captures(m.callee, out)
            for a in m.arguments:
                self._find_captures(a.value, out)
        elif k == "IndexExpr":
            self._find_captures(m.object, out)
            self._find_captures(m.index, out)
        elif k == "MemberExpr":
            self._find_captures(m.object, out)
        elif k == "Block":
            for st in m.statements:
                self._find_captures(st, out)
        elif k == "VariableDecl" or k == "ConstDecl":
            self._find_captures(m.value, out)
        elif k == "Assignment":
            self._find_captures(m.target, out)
            self._find_captures(m.value, out)
        elif k == "CompoundAssignment":
            self._find_captures(m.value, out)
        elif k == "ExpressionStmt":
            self._find_captures(m.expr, out)
        elif k == "IfStmt":
            self._find_captures(m.condition, out)
            self._find_captures(m.then_block, out)
            for c in m.elif_clauses:
                self._find_captures(c.condition, out)
                self._find_captures(c.body, out)
            self._find_captures(m.else_block, out)
        elif k == "WhileStmt":
            self._find_captures(m.condition, out)
            self._find_captures(m.body, out)
        elif k == "ForStmt":
            self._find_captures(m.iterable, out)
            self._find_captures(m.body, out)
        elif k == "ReturnStmt":
            self._find_captures(m.value, out)
        elif k == "TryStmt":
            self._find_captures(m.try_block, out)
            for c in m.catch_clauses:
                self._find_captures(c.body, out)
            self._find_captures(m.finally_block, out)
        elif k == "ComprehensionExpr":
            self._find_captures(m.element, out)
            self._find_captures(m.key, out)
            self._find_captures(m.value, out)
            for cl in m.clauses:
                self._find_captures(cl.expr, out)
        elif k == "MatchStmt":
            self._find_captures(m.subject, out)
            for c in m.cases:
                self._find_captures(c.guard, out)
                self._find_captures(c.body, out)

    func captured_names(body, top_level):
        out := {}
        for s in body:
            if top_level and (s.kind == "FunctionDecl" or s.kind == "StructDecl" or s.kind == "ClassDecl" or s.kind == "InterfaceDecl"):
                continue
            self._find_captures(s, out)
        return out

    func lambda_(fn, want, display):
        want_f := self.unnull(want) if want >= 0 and self.kind(self.unnull(want)) == K_FUNC else -1
        ps := []
        ok := true
        i := 0
        while i < len(fn.params):
            p := fn.params[i]
            t := -1
            if p.type != null:
                t = self.type_of(p.type)
            elif want_f >= 0 and i < len(self.params_of(want_f)):
                t = self.params_of(want_f)[i]
            if t < 0:
                self.error_at(p.line, p.column, "paramètre '" + p.name + "' : type requis (annotation, ou type fonction attendu connu)")
                ok = false
                t = TINT
            if p.default_value != null:
                self.error(p.default_value, "valeur par défaut dans une fonction locale ou une lambda : non supportée en natif")
                ok = false
            append(ps, t)
            i += 1
        if want_f >= 0 and len(self.params_of(want_f)) != len(ps):
            self.error(fn, "fonction à " + str(len(ps)) + " paramètre(s), " + self.ty_name(want_f) + " attendu")
            ok = false
        ret := -2
        if fn.return_type != null:
            ret = self.type_of(fn.return_type, true)
            if ret < 0:
                self.error_at(fn.return_type.line, fn.return_type.column, "type de retour '" + _bt.type_ref_string(fn.return_type) + "' non supporté en natif")
                ok = false
                ret = TVOID
        elif want_f >= 0:
            ret = self.val_of(want_f)
            if fn.is_async and self.kind(ret) == K_FUTURE:
                ret = self.elem_of(ret)
        ids := {}
        self.collect_idents(fn.body, ids)
        names := _sorted_strings([nm for nm in ids])
        caps := []
        for name in names:
            is_param := false
            for p in fn.params:
                is_param = is_param or p.name == name
            if is_param:
                continue
            v := self.lookup(name)
            if v == null or v.glob:
                continue
            c := v.copy()
            if c.view:
                c = c.original()
                if c.glob:
                    continue
            if not c.boxed:
                self.error(fn, "capture de '" + name + "' par une fonction locale : non prise en charge ici")
                ok = false
                continue
            append(caps, [name, c])
        if not ok:
            return self.bad()
        outer := self.fn_
        fir := ir.IrFunction(display)
        fir.file = self.mods[self.mod_].file
        fir.params = len(ps) + 1
        fir.vregs = fir.params
        fid := len(self.prog.functions)
        append(self.prog.functions, fir)
        saved := self._save_ctx()
        self.fn_ = fir
        self.scopes = [self._copy_scope(saved[0][0]), {}, {}]
        self.fn_scope_base = 1
        self.in_main = false
        self.loops = []
        self.tries = []
        self.ret_ty = ret
        self.fn_name = display
        self.cur_line = fn.line
        self.box_names = self.captured_names(fn.body.statements, false)
        k := 0
        while k < len(caps):
            cv := caps[k][1].copy()
            cv.index = self.reg()
            cv.boxed = true
            cv.glob = false
            cv.view = false
            self.emit_op(ir.LOAD64, cv.index, 0, -1, 16 + 8 * k)
            self.scopes[1][caps[k][0]] = cv
            k += 1
        i = 0
        while i < len(ps):
            pv := Var(ps[i], false, i + 1)
            if fn.params[i].name in self.box_names:
                pv.boxed = true
                pv.index = self.rt("__rt_alloc", [self.constant(8), self.constant(0)])
                self.emit_op(ir.STORE64, -1, pv.index, i + 1, 0)
            self.scopes[2][fn.params[i].name] = pv
            i += 1
        self.statements(fn.body.statements)
        body := fn.body.statements
        if len(body) > 0:
            self.cur_line = body[len(body) - 1].line
        if self.ret_ty == -2:
            self.ret_ty = TVOID
        if self.ret_ty == TVOID:
            self.emit(ir.Ins(ir.RET))
        else:
            self.emit_op(ir.FAIL, -1, -1, -1, self.message("TypeError: valeur de retour de " + display + " : attendu " + self.ty_name(self.ret_ty) + ", obtenu null"))
        final_ret := self.ret_ty
        self.fn_.returns_value = final_ret != TVOID
        mod_keep := self.mod_
        owner_keep := self.cur_owner
        self._restore_ctx(saved)
        self.mod_ = mod_keep
        self.cur_owner = owner_keep
        self.fn_ = outer
        entry := fid
        if fn.is_async:
            self.uses_async = true
            n := len(ps)
            th := ir.IrFunction(display)
            th.params = 1
            th.runtime = true
            v := 1
            append(th.code, self._raw(ir.LOAD64, v, 0, 16))
            v += 1
            cl := ir.Ins(ir.CALL)
            cl.callee = fid
            i = 0
            while i <= n:
                append(th.code, self._raw(ir.LOAD64, v, 0, 24 + 8 * i))
                append(cl.args, v)
                v += 1
                i += 1
            if final_ret == TVOID:
                cl.dst = -1
            else:
                cl.dst = v
                v += 1
            cl.line = fn.line
            append(th.code, cl)
            result := cl.dst
            if result < 0:
                append(th.code, self._raw(ir.CONST, v, -1, 0))
                result = v
                v += 1
            done := ir.Ins(ir.CALL)
            done.callee = self.fns[self.fn_by_name["__rt_task_done"]].id
            done.args = [1, result]
            append(th.code, done)
            append(th.code, ir.Ins(ir.RET))
            th.vregs = v
            thunk := len(self.prog.functions)
            append(self.prog.functions, th)
            sp := ir.IrFunction(display)
            sp.params = n + 1
            sp.vregs = n + 1
            sp.runtime = true
            sp.returns_value = true
            entry = len(self.prog.functions)
            append(self.prog.functions, sp)
            self.fn_ = sp
            c := self.rt("__rt_alloc", [self.constant(32 + 8 * n), self.constant(0)])
            tc := self.reg()
            tfa := ir.Ins(ir.FUNC_ADDR)
            tfa.dst = tc
            tfa.callee = thunk
            self.emit(tfa)
            self.emit_op(ir.STORE64, -1, c, tc, 0)
            self.emit_op(ir.STORE64, -1, c, self.str_const(display), 8)
            i = 0
            while i <= n:
                self.emit_op(ir.STORE64, -1, c, i, 24 + 8 * i)
                i += 1
            r := ir.Ins(ir.RET)
            r.a = self.rt("__rt_task_new", [c])
            self.emit(r)
            self.fn_ = outer
        obj := self.rt("__rt_alloc", [self.constant(16 + 8 * len(caps)), self.constant(0)])
        code := self.reg()
        fa := ir.Ins(ir.FUNC_ADDR)
        fa.dst = code
        fa.callee = entry
        self.emit(fa)
        self.emit_op(ir.STORE64, -1, obj, code, 0)
        self.emit_op(ir.STORE64, -1, obj, self.str_const("<function " + display + ">"), 8)
        k = 0
        while k < len(caps):
            self.emit_op(ir.STORE64, -1, obj, caps[k][1].index, 16 + 8 * k)
            k += 1
        return Val(obj, self.func_of(ps, self.future_of(final_ret) if fn.is_async else final_ret))

    func function_value(at, fn_index):
        f := self.fns[fn_index]
        if f.generic:
            self.error(at, "'" + f.name + "' (paramètres non typés) utilisée comme valeur : non supporté en natif")
            return self.bad()
        for p in f.decl.params:
            if p.default_value != null:
                self.error(at, "'" + f.name + "' utilisée comme valeur : paramètres par défaut non pris en charge en natif")
                return self.bad()
        thunk := -1
        if fn_index in self.thunks:
            thunk = self.thunks[fn_index]
        elif f.is_async:
            fir := ir.IrFunction(f.name)
            fir.params = len(f.params) + 1
            fir.vregs = fir.params
            fir.runtime = true
            fir.returns_value = true
            thunk = len(self.prog.functions)
            outer := self.fn_
            append(self.prog.functions, fir)
            self.fn_ = fir
            regs := [i + 1 for i in 0..len(f.params)]
            r := ir.Ins(ir.RET)
            r.a = self.spawn_async(fn_index, regs).reg
            self.emit(r)
            self.fn_ = outer
            self.thunks[fn_index] = thunk
        else:
            fir := ir.IrFunction(f.name)
            fir.params = len(f.params) + 1
            fir.vregs = fir.params + (0 if f.ret == TVOID else 1)
            fir.runtime = true
            cl := ir.Ins(ir.CALL)
            cl.callee = f.id
            cl.args = [i + 1 for i in 0..len(f.params)]
            cl.dst = -1 if f.ret == TVOID else fir.params
            cl.line = self.cur_line
            append(fir.code, cl)
            r := ir.Ins(ir.RET)
            r.a = cl.dst
            append(fir.code, r)
            thunk = len(self.prog.functions)
            append(self.prog.functions, fir)
            self.thunks[fn_index] = thunk
        obj := self.rt("__rt_alloc", [self.constant(16), self.constant(0)])
        code := self.reg()
        fa := ir.Ins(ir.FUNC_ADDR)
        fa.dst = code
        fa.callee = thunk
        self.emit(fa)
        self.emit_op(ir.STORE64, -1, obj, code, 0)
        self.emit_op(ir.STORE64, -1, obj, self.str_const("<function " + f.name + ">"), 8)
        return Val(obj, self.func_of(f.params, self.future_of(f.ret) if f.is_async else f.ret))

    func local_function(fn):
        ps := []
        for p in fn.params:
            t := self.type_of(p.type) if p.type != null else -1
            if t < 0:
                self.error_at(p.line, p.column, "paramètre '" + p.name + "' de la fonction locale " + fn.name + " : type requis en natif")
                self.failed_locals[fn.name] = true
                return
            append(ps, t)
        ret := self.type_of(fn.return_type, true) if fn.return_type != null else TVOID
        if ret < 0:
            self.error(fn, "type de retour de " + fn.name + " non supporté en natif")
            self.failed_locals[fn.name] = true
            return
        ft := self.func_of(ps, self.future_of(ret) if fn.is_async else ret)
        self.declare(fn.name, ft, self.constant(0))
        v := self.lambda_(fn, ft, fn.name)
        if v.bad:
            return
        var := self.lookup(fn.name).copy()
        self.write(var, v.reg)

    func call_value(c, f):
        if self.kind(f.ty) != K_FUNC:
            self.error(c, "appel d'une valeur de type " + self.ty_name(f.ty))
            return self.bad()
        ps := self.params_of(f.ty)
        if len(c.arguments) != len(ps):
            self.error(c, "appel d'une fonction-valeur : " + str(len(ps)) + " argument(s) attendu(s)")
            return self.bad()
        ins := ir.Ins(ir.CALL_IND)
        ins.a = f.reg
        i := 0
        while i < len(ps):
            if c.arguments[i].name != null:
                self.error(c, "appel d'une fonction-valeur : arguments positionnels seulement")
                return self.bad()
            v := self.expr_value(c.arguments[i].value, ps[i])
            if not self.expect_type(c.arguments[i].value, v, ps[i], "argument " + str(i + 1)):
                return self.bad()
            append(ins.args, v.reg)
            i += 1
        ins.dst = -1 if self.val_of(f.ty) == TVOID else self.reg()
        dst := ins.dst
        self.emit(ins)
        return Val(dst, self.val_of(f.ty))

    # ------------------------------------------------------------------ enums et match
    func register_enums(stmts):
        for s in stmts:
            if s.kind != "EnumDecl":
                continue
            info := EnumInfo()
            info.name = s.name
            info.decl = s
            eid := len(self.enums)
            info.ty = self.push_type(K_ENUM, -1, eid)
            self.enum_by_name[self.qual(s.name)] = eid
            append(self.enums, info)

    func resolve_enums(stmts):
        for s in stmts:
            if s.kind != "EnumDecl":
                continue
            info := self.enums[self.enum_by_name[self.qual(s.name)]]
            for m in s.members:
                v := EnumVariant()
                v.name = m.name
                v.fields = m.fields
                i := 0
                while i < len(m.fields):
                    t := m.field_types[i] if i < len(m.field_types) else null
                    ty := -1
                    if t != null:
                        ty = self.type_of(t)
                        if ty < 0:
                            self.error_at(t.line, t.column, "type '" + _bt.type_ref_string(t) + "' non supporté en natif")
                    append(v.field_ty, ty)
                    append(v.ann, t)
                    i += 1
                append(info.variants, v)

    func enum_variant(at, eid, variant, args):
        info := self.enums[eid]
        vi := 0
        while vi < len(info.variants) and info.variants[vi].name != variant:
            vi += 1
        if vi == len(info.variants):
            self.error(at, "'" + info.name + "' n'a pas de variante '" + variant + "'")
            return self.bad()
        n := len(info.variants[vi].fields)
        full := info.name + "." + variant
        if args == null and n > 0:
            self.error(at, "'" + full + "' attend " + str(n) + " argument(s) : utiliser '" + full + "(...)'")
            return self.bad()
        if args != null and len(args) != n:
            self.error(at, "'" + full + "' attend " + str(n) + " argument(s), obtenu " + str(len(args)))
            return self.bad()
        regs := []
        i := 0
        while i < n:
            a := args[i]
            if a.name != null:
                self.error(at, "'" + full + "' : arguments positionnels seulement")
                return self.bad()
            fts := self.enums[eid].variants[vi].field_ty
            v := self.expr_value(a.value, fts[i])
            if v.bad:
                return v
            if fts[i] < 0:
                if v.ty == TNULL:
                    self.error(a.value, "champ '" + info.variants[vi].fields[i] + "' de " + full + " : annoter son type (" + info.variants[vi].fields[i] + ": T?)")
                    return self.bad()
                fts[i] = v.ty
            if not self.expect_type(a.value, v, fts[i], "champ '" + info.variants[vi].fields[i] + "' de " + full):
                return self.bad()
            append(regs, v.reg)
            i += 1
        obj := self.rt("__rt_alloc", [self.constant(8 * (n + 2)), self.constant(0)])
        self.emit_op(ir.STORE64, -1, obj, self.str_const("<" + full + " instance>"), 0)
        self.emit_op(ir.STORE64, -1, obj, self.constant(vi), 8)
        i = 0
        while i < n:
            self.emit_op(ir.STORE64, -1, obj, regs[i], 8 * (i + 2))
            i += 1
        return Val(obj, self.enums[eid].ty)

    func match_stmt(m):
        subj := self.expr_value(m.subject)
        if subj.bad:
            return
        keep := self.reg()
        self.emit_op(ir.COPY, keep, subj.reg)
        subj.reg = keep
        l_end := self.label()
        for c in m.cases:
            l_next := self.label()
            self.push_scope()
            self.pattern(m, c.pattern, subj, l_next)
            if c.guard != null:
                self.jump(ir.JMP_IF_ZERO, l_next, self.truthy(c.guard, self.expr_value(c.guard)))
            self.statements(c.body.statements)
            self.pop_scope()
            self.jump(ir.JMP, l_end)
            self.place(l_next)
        self.place(l_end)

    func _pattern_literal(lp):
        lk := lp.literal_kind
        if lk == "Integer":
            return Val(self.constant(lp.literal_value), TINT)
        if lk == "Float":
            return Val(self.constant(float_bits(lp.literal_value)), TFLOAT)
        if lk == "Boolean":
            return Val(self.constant(1 if lp.literal_value else 0), TBOOL)
        if lk == "String":
            return Val(self.str_const(lp.literal_value), TSTR)
        if lk == "Null":
            return Val(self.constant(0), TNULL)
        if lk == "Char":
            return Val(self.constant(lp.literal_value), TCHAR)
        self.error_at(lp.line, lp.column, "motif littéral non supporté en natif")
        return self.bad()

    func pattern(at, p, v, l_fail):
        pk := p.pk
        if pk == "Wildcard":
            return
        if pk == "Bind":
            self.declare(p.name, v.ty, v.reg)
            return
        if pk == "Literal":
            lit := self._pattern_literal(p)
            if lit.bad:
                return
            eq := self.value_eq(at, v, lit)
            if eq >= 0:
                self.jump(ir.JMP_IF_ZERO, l_fail, eq)
            return
        if pk == "Range":
            lo := self._pattern_literal(p.range_low)
            hi := self._pattern_literal(p.range_high)
            if lo.bad or hi.bad:
                return
            if not self.is_num(v.ty) or not self.is_num(lo.ty) or not self.is_num(hi.ty):
                self.jump(ir.JMP, l_fail)
                return
            ge := self.arith(at, "Ge", v, lo)
            if not ge.bad:
                self.jump(ir.JMP_IF_ZERO, l_fail, ge.reg)
            lt := self.arith(at, "Lt", v, hi)
            if not lt.bad:
                self.jump(ir.JMP_IF_ZERO, l_fail, lt.reg)
            return
        if pk == "EnumVariant":
            eid := self.find_enum(p.enum_type_name)
            if eid < 0:
                self.error_at(p.line, p.column, "enum '" + p.enum_type_name + "' inconnu du programme natif")
                return
            if v.ty != self.enums[eid].ty:
                self.jump(ir.JMP, l_fail)
                return
            info := self.enums[eid]
            vi := 0
            while vi < len(info.variants) and info.variants[vi].name != p.variant_name:
                vi += 1
            if vi == len(info.variants):
                self.error_at(p.line, p.column, "'" + info.name + "' n'a pas de variante '" + p.variant_name + "'")
                return
            tag := self.reg()
            eq := self.reg()
            self.emit_op(ir.LOAD64, tag, v.reg, -1, 8)
            self.emit_op(ir.EQ, eq, tag, self.constant(vi))
            self.jump(ir.JMP_IF_ZERO, l_fail, eq)
            var := info.variants[vi]
            if len(p.subpatterns) == 0:
                return
            if len(p.subpatterns) != len(var.fields):
                self.error_at(p.line, p.column, "motif " + info.name + "." + var.name + " : " + str(len(var.fields)) + " champ(s) attendu(s)")
                return
            i := 0
            while i < len(var.fields):
                ft := var.field_ty[i]
                if ft < 0:
                    self.error_at(p.line, p.column, "champ '" + var.fields[i] + "' de " + info.name + "." + var.name + " : type inconnu à ce point (l'annoter : " + var.name + "(" + var.fields[i] + ": T, ...))")
                    return
                f := self.reg()
                self.emit_op(ir.LOAD64, f, v.reg, -1, 8 * (i + 2))
                self.pattern(at, p.subpatterns[i], Val(f, ft), l_fail)
                i += 1
            return
        if pk == "Tuple":
            if self.kind(v.ty) != K_TUPLE or len(self.elems_of(v.ty)) != len(p.subpatterns):
                self.jump(ir.JMP, l_fail)
                return
            es := self.elems_of(v.ty)
            i := 0
            while i < len(es):
                f := self.reg()
                self.emit_op(ir.LOAD64, f, v.reg, -1, 8 * (i + 1))
                self.pattern(at, p.subpatterns[i], Val(f, es[i]), l_fail)
                i += 1
            return
        if pk == "List":
            if self.kind(v.ty) != K_LIST:
                self.jump(ir.JMP, l_fail)
                return
            eq := self.reg()
            cn := self.constant(len(p.subpatterns))
            self.emit_op(ir.EQ, eq, self.list_len(v.reg), cn)
            self.jump(ir.JMP_IF_ZERO, l_fail, eq)
            i := 0
            while i < len(p.subpatterns):
                f := self.reg()
                ci := self.constant(i)
                self.emit_op(ir.LOAD_ELEM, f, self.list_data(v.reg), ci)
                self.pattern(at, p.subpatterns[i], Val(f, self.elem_of(v.ty)), l_fail)
                i += 1

    func try_stmt(t):
        self.fn_.has_try = true
        l_after_finally := self.label()
        l_finally_landing := self.label()
        rec_f := -1
        if t.finally_block != null:
            rec_f = self.handler_record()
            b := ir.Ins(ir.TRY_BEGIN)
            b.a = rec_f
            b.label = l_finally_landing
            self.emit(b)
            append(self.tries, [rec_f, t.finally_block])
        if len(t.catch_clauses) == 0:
            self.push_scope()
            self.statements(t.try_block.statements)
            self.pop_scope()
        else:
            rec := self.handler_record()
            l_landing := self.label()
            l_end := self.label()
            b := ir.Ins(ir.TRY_BEGIN)
            b.a = rec
            b.label = l_landing
            self.emit(b)
            append(self.tries, [rec, null])
            self.push_scope()
            self.statements(t.try_block.statements)
            self.pop_scope()
            self.tries = self.tries[0:len(self.tries) - 1]
            e := ir.Ins(ir.TRY_END)
            e.a = rec
            self.emit(e)
            self.jump(ir.JMP, l_end)
            self.place(l_landing)
            exc := self.reg()
            self.emit_op(ir.LANDING, exc)
            exc_type := self.reg()
            self.emit_op(ir.LOAD64, exc_type, exc, -1, 0)
            generic := false
            for c in t.catch_clauses:
                l_body := self.label()
                l_next := self.label()
                if len(c.types) == 0:
                    generic = true
                else:
                    all := false
                    for ty in c.types:
                        all = all or ty == "Exception"
                    if not all:
                        for ty in c.types:
                            self.jump(ir.JMP_IF_NON_ZERO, l_body, self.rt("__rt_str_eq", [exc_type, self.str_const(ty)]))
                        self.jump(ir.JMP, l_next)
                self.place(l_body)
                self.push_scope()
                if c.name != null:
                    v := Var(TEXC, false, self.reg())
                    self.emit_op(ir.COPY, v.index, exc)
                    self.scopes[len(self.scopes) - 1][c.name] = v
                self.statements(c.body.statements)
                self.pop_scope()
                self.jump(ir.JMP, l_end)
                self.place(l_next)
                if generic:
                    break
            if not generic:
                self.rt("__rt_throw", [exc], false)
            self.place(l_end)
        if t.finally_block != null:
            self.tries = self.tries[0:len(self.tries) - 1]
            e := ir.Ins(ir.TRY_END)
            e.a = rec_f
            self.emit(e)
            self.push_scope()
            self.statements(t.finally_block.statements)
            self.pop_scope()
            self.jump(ir.JMP, l_after_finally)
            self.place(l_finally_landing)
            exc_f := self.reg()
            self.emit_op(ir.LANDING, exc_f)
            self.push_scope()
            self.statements(t.finally_block.statements)
            self.pop_scope()
            self.rt("__rt_throw", [exc_f], false)
            self.place(l_after_finally)

    # ------------------------------------------------------------------ déclarations
    func resolve_fields(sid):
        info := self.structs[sid]
        if info.resolved:
            return
        info.resolved = true
        if info.base >= 0:
            self.resolve_fields(info.base)
            b := self.structs[info.base]
            info.fields = [x for x in b.fields]
            info.field_ty = [x for x in b.field_ty]
            info.defaults = [x for x in b.defaults]
            info.field_index = {}
            for k in b.field_index:
                info.field_index[k] = b.field_index[k]
        if info.body == null:
            return
        for m in info.body.statements:
            if m.kind != "VariableDecl":
                continue
            ty := -1
            if m.type != null:
                ty = self.type_of(m.type)
                if ty < 0:
                    self.error_at(m.type.line, m.type.column, "type '" + _bt.type_ref_string(m.type) + "' non supporté en natif")
            elif m.value != null and m.value.kind == "Literal":
                lk := m.value.literal_kind
                ty = TINT if lk == "Integer" else TFLOAT if lk == "Float" else TBOOL if lk == "Boolean" else TSTR if lk == "String" else -1
            if ty < 0:
                if m.type == null:
                    self.error(m, "champ '" + m.name + "' : annoter son type (" + m.name + ": T := valeur)")
                ty = TINT
            if m.name in info.field_index:
                self.error(m, "champ '" + m.name + "' déjà déclaré dans une classe de base")
                continue
            info.field_index[m.name] = len(info.fields)
            append(info.fields, m.name)
            append(info.field_ty, ty)
            append(info.defaults, null if m.declared_only else m.value)

    func declare_structs(stmts):
        found := []
        for s in stmts:
            k := s.kind
            if k != "StructDecl" and k != "ClassDecl" and k != "InterfaceDecl":
                continue
            info := StructInfo()
            info.decl = s
            info.name = s.name
            info.body = s.body
            info.is_interface = k == "InterfaceDecl"
            sid := len(self.structs)
            info.ty = self.push_type(K_STRUCT, -1, sid)
            self.struct_by_name[self.qual(info.name)] = sid
            append(self.structs, info)
            append(found, sid)
        for sid in found:
            info := self.structs[sid]
            if info.decl.kind != "ClassDecl":
                continue
            d := info.decl
            if d.base_class != null:
                b := self.find_struct(d.base_class)
                if b < 0 or self.structs[b].is_interface:
                    self.error(d, "classe de base '" + d.base_class + "' inconnue du programme natif")
                else:
                    info.base = b
            for iname in d.interfaces:
                it := self.find_struct(iname)
                if it < 0 or not self.structs[it].is_interface:
                    self.error(d, "interface '" + iname + "' inconnue du programme natif")
                else:
                    append(info.ifaces, it)
        for sid in found:
            self.resolve_fields(sid)
        for sid in found:
            if self.structs[sid].body == null:
                continue
            for m in self.structs[sid].body.statements:
                if m.kind == "FunctionDecl":
                    self.declare_function(m, sid, false)
                elif m.kind != "VariableDecl":
                    self.error(m, "membre de struct non supporté en natif")
        for sid in found:
            st := self.structs[sid]
            for name in st.method_order:
                idx := st.methods[name]
                parents := []
                if st.base >= 0:
                    append(parents, st.base)
                c := sid
                while c >= 0:
                    for i in self.structs[c].ifaces:
                        append(parents, i)
                    c = self.structs[c].base
                f := self.fns[idx]
                for p in parents:
                    other := self.find_method(p, name)
                    if other < 0 or name == "init":
                        continue
                    g := self.fns[other]
                    same := f.ret == g.ret and len(f.params) == len(g.params)
                    k := 1
                    while same and k < len(f.params):
                        same = f.params[k] == g.params[k]
                        k += 1
                    if not same:
                        self.error(f.decl, "'" + f.name + "' redéfinit '" + g.name + "' avec une signature différente")

    func declare_function(fn, owner, runtime):
        f := Fn()
        f.id = len(self.prog.functions)
        f.decl = fn
        f.owner = owner
        f.runtime = runtime
        f.module = self.mod_
        f.abstract = owner >= 0 and self.structs[owner].is_interface
        f.name = self.structs[owner].name + "." + fn.name if owner >= 0 else fn.name
        f.is_async = fn.is_async
        if owner >= 0:
            append(f.names, "self")
            append(f.params, self.structs[owner].ty)
        for p in fn.params:
            t := TINT
            if p.type == null and owner < 0 and not runtime:
                f.generic = true
                t = -1
            elif p.type == null:
                self.error_at(p.line, p.column, "paramètre '" + p.name + "' de " + f.name + " : type requis en natif")
            else:
                t = self.type_of(p.type)
                if t < 0:
                    self.error_at(p.type.line, p.type.column, "type '" + _bt.type_ref_string(p.type) + "' non supporté en natif")
                    t = TINT
            if p.default_value != null and p.default_value.kind != "Literal":
                self.error(p.default_value, "valeur par défaut de '" + p.name + "' : littéral requis en natif")
            append(f.names, p.name)
            append(f.params, t)
        if fn.return_type != null:
            f.ret = self.type_of(fn.return_type, true)
            if f.ret < 0:
                self.error_at(fn.return_type.line, fn.return_type.column, "type de retour '" + _bt.type_ref_string(fn.return_type) + "' non supporté en natif")
                f.ret = TVOID
        elif f.generic:
            f.ret = -2
        fir := ir.IrFunction(f.name)
        fir.params = len(f.params)
        fir.vregs = fir.params
        fir.returns_value = f.ret != TVOID
        fir.runtime = runtime
        fir.inline = self.mods[self.mod_].inline
        fir.file = self.mods[self.mod_].file
        append(self.prog.functions, fir)
        index := len(self.fns)
        f.index = index
        if owner >= 0:
            s := self.structs[owner]
            if not (fn.name in s.methods):
                append(s.method_order, fn.name)
            s.methods[fn.name] = index
            if fn.name == "init" and f.ret != TVOID:
                self.error(fn, "init ne renvoie pas de valeur")
        else:
            key := fn.name if runtime else self.qual(fn.name)
            if runtime and (key in self.fn_by_name):
                self.error(fn, "fonction du runtime '" + key + "' définie deux fois")
            self.fn_by_name[key] = index
        append(self.fns, f)

    func lower_function(f):
        self.fn_ = self.prog.functions[f.id]
        self.in_main = false
        self.mod_ = f.module
        self.cur_owner = f.owner
        self.in_runtime = f.runtime
        self.ret_ty = f.ret
        self.fn_name = f.name
        self.cur_line = f.decl.line
        self.fn_scope_base = len(self.scopes)
        self.push_scope()
        self.box_names = self.captured_names(f.decl.body.statements, false)
        i := 0
        while i < len(f.params):
            pv := Var(f.params[i], false, i)
            if f.names[i] in self.box_names:
                pv.boxed = true
                pv.index = self.rt("__rt_alloc", [self.constant(8), self.constant(0)])
                self.emit_op(ir.STORE64, -1, pv.index, i, 0)
            self.scopes[len(self.scopes) - 1][f.names[i]] = pv
            i += 1
        self.statements(f.decl.body.statements)
        body := f.decl.body.statements
        if len(body) > 0:
            self.cur_line = body[len(body) - 1].line
        if f.ret == TVOID:
            self.emit(ir.Ins(ir.RET))
        else:
            self.emit_op(ir.FAIL, -1, -1, -1, self.message("TypeError: valeur de retour de " + f.decl.name + " : attendu " + self.ty_name(f.ret) + ", obtenu null"))
        self.pop_scope()
        self.fn_scope_base = 0
        self.in_runtime = false

    func setup_modules(modules):
        self.entry_mod = len(modules) - 1
        i := 0
        while i < len(modules):
            m := ModInfo()
            m.prefix = "" if i == self.entry_mod else "m" + str(i) + "::"
            m.file = len(self.prog.files)
            m.stdlib = _starts(modules[i].file, "<stdlib natif>")
            m.inline = modules[i].inline
            append(self.prog.files, modules[i].file)
            append(self.mods, m)
            i += 1
        i = 0
        while i < len(modules):
            self.mod_ = i
            for s in modules[i].program.top_level:
                if s.kind != "ImportStmt":
                    continue
                if not (s.uid in modules[i].imports):
                    continue
                t := modules[i].imports[s.uid]
                self.mods[i].resolved[s.uid] = true
                dotted := _s.join(".", s.module_path)
                if not s.is_from:
                    self.mods[i].ns[s.alias if s.alias != null else s.module_path[len(s.module_path) - 1]] = t
                    continue
                for name in s.names:
                    if not _exports(modules[t].program, name):
                        self.error(s, "'" + name + "' n'est pas exporté par le module '" + dotted + "'")
                    self.mods[i].frm[name] = self.mods[t].prefix + name
            i += 1

    func module_member(m, target):
        key := self.mods[target].prefix + m.member
        if key in self.scopes[0]:
            return self.read(self.scopes[0][key].copy())
        if key in self.fn_by_name:
            return self.function_value(m, self.fn_by_name[key])
        self.error(m, "'" + m.member + "' n'est pas défini dans le module '" + m.object.name + "'")
        return self.bad()

    func run(modules, runtime):
        self.setup_modules(modules)
        p := self.prog
        p.freestanding = self.freestanding
        p.uefi = self.uefi
        p.windows = self.windows
        p.a64 = self.a64
        self.scopes = [{}]
        main := ir.IrFunction("<link>" if len(modules) > 1 else "<module>")
        main.runtime = len(modules) > 1
        main.file = self.mods[len(self.mods) - 1].file
        append(p.functions, main)
        p.entry = 0
        self.mod_ = self.entry_mod
        self.in_runtime = true
        for s in runtime.top_level:
            if s.kind == "FunctionDecl":
                self.declare_function(s, -1, true)
        self.in_runtime = false
        i := 0
        while i < len(modules):
            self.mod_ = i
            self.register_enums(modules[i].program.top_level)
            self.declare_structs(modules[i].program.top_level)
            i += 1
        i = 0
        while i < len(modules):
            self.mod_ = i
            self.resolve_enums(modules[i].program.top_level)
            i += 1
        i = 0
        while i < len(modules):
            self.mod_ = i
            for s in modules[i].program.top_level:
                if s.kind != "FunctionDecl":
                    continue
                if s.extends_type != "":
                    self.error(s, "'extend " + s.extends_type + "' n'est pas supporté par le compilateur natif")
                    continue
                for prm in s.params:
                    if prm.is_rest:
                        self.error(s, "le paramètre variadique '*" + prm.name + "' n'est pas supporté par le compilateur natif")
                if _starts(s.name, "__") and not self.mods[i].stdlib:
                    self.error(s, "les noms commençant par '__' sont réservés au runtime natif")
                self.declare_function(s, -1, false)
            i += 1
        i = 0
        while i < len(modules):
            fid := 0
            if len(modules) > 1:
                init := ir.IrFunction("<module>")
                init.file = self.mods[i].file
                fid = len(p.functions)
                append(p.functions, init)
                cl := ir.Ins(ir.CALL)
                cl.callee = fid
                append(p.functions[0].code, cl)
            self.mod_ = i
            self.cur_owner = -1
            self.fn_ = p.functions[fid]
            self.in_main = true
            self.fn_scope_base = 0
            self.box_names = self.captured_names(modules[i].program.top_level, true)
            self.statements(modules[i].program.top_level)
            if i == self.entry_mod and self.uses_async:
                self.rt("__rt_async_end", [], false)
            self.emit(ir.Ins(ir.RET))
            i += 1
        if len(modules) > 1:
            append(p.functions[0].code, ir.Ins(ir.RET))
        for f in self.fns:
            if not f.abstract and not f.generic:
                self.lower_function(f)
        if self.extend != null and len(self.diags) == 0:
            self.extend(self)
        if len(self.diags) > 0:
            self.diags = _stable_sort(self.diags, _diag_less)
            raise("NativeError", _s.substring(join_diags(self.file, self.diags), 13, len(join_diags(self.file, self.diags))))
        return self.prune()

    # Ne garde que les fonctions atteignables depuis les racines (module, rapport d'erreur, allocateur...).
    func prune():
        p := self.prog
        remap := [-1 for i in 0..len(p.functions)]
        order := [p.entry, self._fid("__rt_report"), self._fid("__rt_alloc"), self._fid("__rt_raise_msg"), self._fid("__rt_cpu_fault"), self._fid("__rt_fiber_main")]
        if self.windows:
            append(order, self._fid("__rt_win_init"))
        for m in self.mods:
            if p.files[m.file] != "<stdlib natif>/hw.al":
                continue
            if (m.prefix + "_dispatch") in self.fn_by_name:
                p.irq_entry = len(order)
                append(order, self.fns[self.fn_by_name[m.prefix + "_dispatch"]].id)
            if (m.prefix + "_syscall") in self.fn_by_name:
                p.syscall_entry = len(order)
                append(order, self.fns[self.fn_by_name[m.prefix + "_syscall"]].id)
        work := [x for x in order]
        k := 0
        while k < len(order):
            remap[order[k]] = k
            k += 1
        while len(work) > 0:
            f := work[len(work) - 1]
            work = work[0:len(work) - 1]
            for ins in p.functions[f].code:
                if ins.callee < 0:
                    continue
                g := ins.callee
                if remap[g] < 0:
                    remap[g] = len(order)
                    append(order, g)
                    append(work, g)
        kept := []
        for g in order:
            fn := p.functions[g]
            for ins in fn.code:
                if ins.callee >= 0:
                    ins.callee = remap[ins.callee]
            append(kept, fn)
        p.functions = kept
        p.entry = 0
        if len(p.imports) > 0:
            used := [-1 for i in 0..len(p.imports)]
            imports := []
            for fn in p.functions:
                for ins in fn.code:
                    if ins.op != ir.IMPORT_ADDR:
                        continue
                    if used[ins.imm] < 0:
                        used[ins.imm] = len(imports)
                        append(imports, p.imports[ins.imm])
                    ins.imm = used[ins.imm]
            p.imports = imports
        if p.irq_entry >= 0:
            p.functions[p.irq_entry].runtime = true
        if p.syscall_entry >= 0:
            p.functions[p.syscall_entry].runtime = true
        return p

    func _fid(name):
        return self.fns[self.fn_by_name[name]].id

    # ---- accès du traducteur de bytecode (mode dynamique, IrHost du C++) ----
    func runtime_function(name):
        if not (name in self.fn_by_name):
            raise("RuntimeError", "mode dynamique : fonction du runtime absente : " + name)
        return self.fns[self.fn_by_name[name]].id

    func has_runtime_function(name):
        return name in self.fn_by_name

    func string_index(s):
        return self.str_index_of(s)

    func new_global():
        g := self.prog.globals
        self.prog.globals += 1
        return g

    func file_index(path):
        i := 0
        while i < len(self.prog.files):
            if self.prog.files[i] == path:
                return i
            i += 1
        append(self.prog.files, path)
        return len(self.prog.files) - 1

# AST -> IR. `modules` : dépendances d'abord, programme principal en dernier ; `runtime` : programme du runtime.
func lower(modules, runtime, freestanding=false, uefi=false, windows=false, a64=false):
    l := Lowerer(modules[len(modules) - 1].file)
    l.freestanding = freestanding or uefi
    l.uefi = uefi
    l.windows = windows and not freestanding and not uefi
    l.a64 = a64
    return l.run(modules, runtime)

# Mode dynamique (lowerDynamic du C++) : runtime natif + runtime dynamique abaissés pour un programme vide de nom
# `file`, puis `extend(lowerer)` ajoute les fonctions traduites du bytecode (native.dyn) avant l'élimination
# des fonctions inutilisées.
func lower_dynamic(file, runtime, empty_program, extend, windows=false, a64=false):
    l := Lowerer(file)
    l.windows = windows
    l.a64 = a64
    l.dyn = true
    l.extend = extend
    return l.run([SourceModule(empty_program, file)], runtime)

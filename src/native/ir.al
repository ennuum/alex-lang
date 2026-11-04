# ALEX — native.ir
#
# Représentation intermédiaire du compilateur natif écrit en ALEX (étape C) : portage de
# include/alex/native/Ir.hpp. Code à trois adresses sur des registres virtuels de 64 bits ; une fonction est une
# liste linéaire d'instructions avec étiquettes. Mêmes opérations, dans le même ordre, que le C++.
#
#   use native.ir as ir
#   f := ir.IrFunction("main")
#   i := ir.Ins(ir.CONST)
#   i.dst = 0
#   i.imm = 42
#   print(ir.dump_full(prog))     # même texte que dumpIrFull (C++), oracle des tests
#
# Erreurs : aucune (structures de données).

from core use len, type
from collections use append
use string as _s

const OP_NAMES := ["const", "copy", "add", "sub", "mul", "and", "or", "xor", "shl", "shr", "floordiv", "mod",
    "pow", "neg", "bitnot", "not", "eq", "ne", "lt", "le", "gt", "ge", "fadd", "fsub", "fmul", "fdiv", "feq", "fne",
    "flt", "fle", "fgt", "fge", "i2f", "f2i", "label", "jmp", "jz", "jnz", "call", "ret", "loadg", "storeg", "str",
    "load64", "store64", "load8", "store8", "loadelem", "storeelem", "memcopy", "bounds", "int2str", "print_int",
    "print_str", "print_empty", "fail", "fail_str", "write_err", "code_base", "trace_info", "argv_base", "rt_state",
    "mmap", "munmap", "sp", "stack_top", "save_regs", "globals_start", "globals_end", "memzero", "try_begin",
    "try_end", "landing", "unwind", "handler_top", "frame", "flush", "exit", "func_addr", "call_ind", "syscall",
    "port_out", "port_in", "cpu", "fiber_entry", "ctx_switch", "enter_user", "leave_user", "load16", "load32",
    "store16", "store32", "raw_code", "ms_call", "import_addr", "fsqrt", "win_thunk", "sysv_call"]

const CONST := 0
const COPY := 1
const ADD := 2
const SUB := 3
const MUL := 4
const AND := 5
const OR := 6
const XOR := 7
const SHL := 8
const SHR := 9
const FLOORDIV := 10
const MOD := 11
const POW := 12
const NEG := 13
const BITNOT := 14
const NOT := 15
const EQ := 16
const NE := 17
const LT := 18
const LE := 19
const GT := 20
const GE := 21
const FADD := 22
const FSUB := 23
const FMUL := 24
const FDIV := 25
const FEQ := 26
const FNE := 27
const FLT := 28
const FLE := 29
const FGT := 30
const FGE := 31
const INT_TO_FLOAT := 32
const FLOAT_TO_INT := 33
const LABEL := 34
const JMP := 35
const JMP_IF_ZERO := 36
const JMP_IF_NON_ZERO := 37
const CALL := 38
const RET := 39
const LOAD_GLOBAL := 40
const STORE_GLOBAL := 41
const STR_CONST := 42
const LOAD64 := 43
const STORE64 := 44
const LOAD8 := 45
const STORE8 := 46
const LOAD_ELEM := 47
const STORE_ELEM := 48
const MEM_COPY := 49
const BOUNDS_CHECK := 50
const INT_TO_STR := 51
const PRINT_INT := 52
const PRINT_STR := 53
const PRINT_EMPTY := 54
const FAIL := 55
const FAIL_STR := 56
const WRITE_ERR := 57
const CODE_BASE := 58
const TRACE_INFO := 59
const ARGV_BASE := 60
const RT_STATE := 61
const MMAP := 62
const MUNMAP := 63
const STACK_PTR := 64
const STACK_TOP := 65
const SAVE_REGS := 66
const GLOBALS_START := 67
const GLOBALS_END := 68
const MEM_ZERO := 69
const TRY_BEGIN := 70
const TRY_END := 71
const LANDING := 72
const UNWIND := 73
const HANDLER_TOP := 74
const FRAME_PTR := 75
const FLUSH := 76
const EXIT := 77
const FUNC_ADDR := 78
const CALL_IND := 79
const SYSCALL := 80
const PORT_OUT := 81
const PORT_IN := 82
const CPU_OP := 83
const FIBER_ENTRY := 84
const CTX_SWITCH := 85
const ENTER_USER := 86
const LEAVE_USER := 87
const LOAD16 := 88
const LOAD32 := 89
const STORE16 := 90
const STORE32 := 91
const RAW_CODE := 92
const MS_CALL := 93
const IMPORT_ADDR := 94
const FSQRT := 95
const WIN_THUNK := 96
# Appel d'une fonction C (convention System V x86-64) : a = adresse, b = cadre d'appel (voir nt_codegen) ; VM
# écrite en ALEX seulement (ffi, bibliothèques chargées par dlopen).
const SYSV_CALL := 97

# Messages d'exécution prédéfinis (IrProgram.messages, dans cet ordre) : enum Msg du C++.
const MSG_FLOOR_DIV_ZERO := 0
const MSG_MOD_ZERO := 1
const MSG_SHL := 2
const MSG_SHR := 3
const MSG_RECURSION := 4
const MSG_POW_NEGATIVE := 5
const MSG_DIV_ZERO_INT := 6
const MSG_DIV_ZERO_FLOAT := 7
const MSG_FLOOR_DIV_ZERO_FLOAT := 8
const MSG_MOD_ZERO_FLOAT := 9
const MSG_OUT_OF_MEMORY := 10
const MSG_KEY_ERROR := 11

class Ins:
    func init(op=0):
        self.op = op
        self.dst = -1
        self.a = -1
        self.b = -1
        self.imm = 0
        self.label = -1
        self.callee = -1
        self.line = 0
        self.args = []

    func copy():
        c := Ins(self.op)
        c.dst = self.dst
        c.a = self.a
        c.b = self.b
        c.imm = self.imm
        c.label = self.label
        c.callee = self.callee
        c.line = self.line
        c.args = [x for x in self.args]
        return c

class IrFunction:
    func init(name=""):
        self.name = name
        self.params = 0
        self.vregs = 0
        self.returns_value = false
        self.code = []
        self.labels = 0
        self.runtime = false
        self.inline = false     # fonction d'un module « # alex: inline » (intégrable comme celles du runtime)
        self.has_try = false
        self.file = 0

class IrProgram:
    func init():
        self.functions = []
        self.entry = 0
        self.globals = 0
        self.strings = []       # chaînes : listes d'octets (les littéraux peuvent contenir des octets bruts)
        self.messages = []      # textes (str)
        self.files = []
        self.freestanding = false
        self.uefi = false
        self.windows = false
        self.imports = []
        self.windows_gui = false
        self.windows_icon = null # octets d'un fichier .ico (ressources de l'exécutable Windows), ou null
        self.a64 = false
        self.irq_entry = -1
        self.syscall_entry = -1

func op_name(op):
    return OP_NAMES[op] if op >= 0 and op < len(OP_NAMES) else "?"

const _HEX := "0123456789abcdef"

# Littéral entre guillemets, octets hors ASCII imprimable en \xNN (même forme que dumpIrFull).
func quote_bytes(bs):
    out := ["\""]
    for c in bs:
        if c >= 0x20 and c < 0x7f and c != 0x22 and c != 0x5c:
            append(out, _s.byte_pack([c]))
        else:
            append(out, "\\x" + str(_HEX[c >> 4]) + str(_HEX[c & 15]))
    append(out, "\"")
    return _s.join("", out)

func quote_text(s):
    return quote_bytes(_s.byte_unpack(s))

func _b(v):
    return "1" if v else "0"

func dump_full(p):
    out := ["entry " + str(p.entry) + " globals " + str(p.globals) + " irq " + str(p.irq_entry) + " sys " + str(p.syscall_entry) + " flags " + _b(p.freestanding) + _b(p.uefi) + _b(p.windows) + _b(p.windows_gui) + _b(p.a64)]
    i := 0
    while i < len(p.strings):
        append(out, "s" + str(i) + " " + quote_bytes(p.strings[i]))
        i += 1
    i = 0
    while i < len(p.messages):
        append(out, "m" + str(i) + " " + quote_text(p.messages[i]))
        i += 1
    i = 0
    while i < len(p.files):
        append(out, "f" + str(i) + " " + quote_text(p.files[i]))
        i += 1
    i = 0
    while i < len(p.imports):
        append(out, "i" + str(i) + " " + quote_text(p.imports[i]))
        i += 1
    f := 0
    while f < len(p.functions):
        fn := p.functions[f]
        append(out, "fn " + str(f) + " " + quote_text(fn.name) + " params " + str(fn.params) + " vregs " + str(fn.vregs) + " labels " + str(fn.labels) + " ret " + _b(fn.returns_value) + " rt " + _b(fn.runtime) + " try " + _b(fn.has_try) + " file " + str(fn.file))
        for ins in fn.code:
            line := "  " + OP_NAMES[ins.op] + " " + str(ins.dst) + " " + str(ins.a) + " " + str(ins.b) + " " + str(ins.imm) + " " + str(ins.label) + " " + str(ins.callee) + " @" + str(ins.line)
            for a in ins.args:
                line += " " + str(a)
            append(out, line)
        f += 1
    return _s.join("\n", out) + "\n"

# Forme courte (dumpIr, `alexc build --native --emit-ir`).
func dump_ir(p):
    out := []
    for fn in p.functions:
        append(out, "fn " + fn.name + " (params " + str(fn.params) + ", vregs " + str(fn.vregs) + ")")
        for ins in fn.code:
            if ins.op == LABEL:
                append(out, "  L" + str(ins.label) + ":")
                continue
            line := "    " + OP_NAMES[ins.op]
            if ins.dst >= 0:
                line += " v" + str(ins.dst) + " ="
            if ins.a >= 0:
                line += " v" + str(ins.a)
            if ins.b >= 0:
                line += ", v" + str(ins.b)
            if ins.imm != 0 or ins.op == CONST:
                line += " #" + str(ins.imm)
            if ins.label >= 0:
                line += " -> L" + str(ins.label)
            if ins.callee >= 0:
                line += " " + p.functions[ins.callee].name + "(" + _s.join(", ", ["v" + str(a) for a in ins.args]) + ")"
            elif len(ins.args) > 0:
                line += " [v" + str(ins.args[0]) + "]"
            append(out, line)
    return _s.join("\n", out) + "\n"

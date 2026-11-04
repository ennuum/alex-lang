# ALEX — bytecode.format
#
# Format de bytecode .albc de la machine virtuelle ALEX, écrit en ALEX : jeu d'opcodes (même numérotation que
# include/alex/bc/Opcode.hpp), constantes, instructions à largeur fixe (1 octet d'opcode + 4 octets par
# opérande), modèle d'un module (BcModule), sérialisation octet pour octet identique à celle du compilateur de
# référence (src/Writer.cpp), lecture (src/Reader.cpp), fusion de modules (src/Module.cpp mergeModules) et
# désassemblage lisible (même présentation que l'outil alex-bc dump).
#
#   use bytecode.format as bf
#   m := bf.BcModule()
#   c := m.intern(bf.const_str("bonjour"))
#   octets := bf.write_module(m)                 # liste d'entiers 0..255
#   m2 := bf.read_module(io.read_bytes("prog.albc"))
#   print(bf.dump(m2))
#   fusion := bf.merge_modules([prelude, programme])
#
# Constantes : listes [étiquette, valeur] — NULL, BOOL, INT, FLOAT, CHAR (point de code), BYTE, STRING.
# Erreurs : BytecodeError (fichier tronqué, signature, opcode inconnu, version non prise en charge).

from core use len, type
from collections use append
use string as _s
use _native_net as _n

# ---------------------------------------------------------------------------------------------- opcodes
const OPCODE_NAMES := ["CONST", "LOAD_LOCAL", "STORE_LOCAL", "LOAD_GLOBAL", "STORE_GLOBAL", "ADD", "SUB", "MUL",
    "DIV", "FLOORDIV", "MOD", "POW", "EQ", "NE", "LT", "LE", "GT", "GE", "NOT", "BAND", "BOR", "BXOR", "SHL", "SHR",
    "BITNOT", "JUMP", "JUMP_FALSE", "CALL", "CALL_NATIVE", "RETURN", "BUILD_LIST", "BUILD_TUPLE", "BUILD_DICT",
    "GET_INDEX", "SET_INDEX", "GET_MEMBER", "SET_MEMBER", "TRY_BEGIN", "TRY_END", "THROW", "POP", "DUP", "PRINT",
    "INPUT", "IMPORT", "IMPORT_MODULE", "TO_STRING", "NEW_INSTANCE", "TYPE_NAME", "LEN", "DICT_KEYS", "LIST_APPEND",
    "LIST_INSERT", "LIST_REMOVE_AT", "LIST_CLEAR", "RAISE", "DICT_REMOVE_KEY", "HALT", "DEF_CLASS", "ADD_INTERFACE",
    "GET_SUPER", "INSTANCE_OF", "NEW_CELL", "CELL_GET", "CELL_SET", "UPVALUE_CELL", "MAKE_CLOSURE", "NEW_CELL_EMPTY",
    "ASYNC_ENTRY", "AWAIT", "EXC_MATCHES", "CHECK_TYPE", "DECLARE_FIELD_TYPE", "CONTAINS", "GET_SLICE", "DEL_ITEM",
    "LIST_EXTEND", "LIST_TO_TUPLE", "DICT_UPDATE", "CALL_SPREAD"]

const CONST := 0
const LOAD_LOCAL := 1
const STORE_LOCAL := 2
const LOAD_GLOBAL := 3
const STORE_GLOBAL := 4
const ADD := 5
const SUB := 6
const MUL := 7
const DIV := 8
const FLOORDIV := 9
const MOD := 10
const POW := 11
const EQ := 12
const NE := 13
const LT := 14
const LE := 15
const GT := 16
const GE := 17
const NOT := 18
const BAND := 19
const BOR := 20
const BXOR := 21
const SHL := 22
const SHR := 23
const BITNOT := 24
const JUMP := 25
const JUMP_FALSE := 26
const CALL := 27
const CALL_NATIVE := 28
const RETURN := 29
const BUILD_LIST := 30
const BUILD_TUPLE := 31
const BUILD_DICT := 32
const GET_INDEX := 33
const SET_INDEX := 34
const GET_MEMBER := 35
const SET_MEMBER := 36
const TRY_BEGIN := 37
const TRY_END := 38
const THROW := 39
const POP := 40
const DUP := 41
const PRINT := 42
const INPUT := 43
const IMPORT := 44
const IMPORT_MODULE := 45
const TO_STRING := 46
const NEW_INSTANCE := 47
const TYPE_NAME := 48
const LEN := 49
const DICT_KEYS := 50
const LIST_APPEND := 51
const LIST_INSERT := 52
const LIST_REMOVE_AT := 53
const LIST_CLEAR := 54
const RAISE := 55
const DICT_REMOVE_KEY := 56
const HALT := 57
const DEF_CLASS := 58
const ADD_INTERFACE := 59
const GET_SUPER := 60
const INSTANCE_OF := 61
const NEW_CELL := 62
const CELL_GET := 63
const CELL_SET := 64
const UPVALUE_CELL := 65
const MAKE_CLOSURE := 66
const NEW_CELL_EMPTY := 67
const ASYNC_ENTRY := 68
const AWAIT := 69
const EXC_MATCHES := 70
const CHECK_TYPE := 71
const DECLARE_FIELD_TYPE := 72
const CONTAINS := 73
const GET_SLICE := 74
const DEL_ITEM := 75
const LIST_EXTEND := 76
const LIST_TO_TUPLE := 77
const DICT_UPDATE := 78
const CALL_SPREAD := 79
const OPCODE_COUNT := 80

const NO_CONST := 0xFFFFFFFF
const SUPPORTED_VERSION_MAJOR := 0
const CURRENT_VERSION_MINOR := 4
const FLAG_BETA := 1

# Nombre d'opérandes u32 de chaque opcode (src/Opcode.cpp operandCount).
_OPERANDS := [0 for i in 0..80]
for _op in [CONST, LOAD_LOCAL, STORE_LOCAL, LOAD_GLOBAL, STORE_GLOBAL, JUMP, JUMP_FALSE, CALL, CALL_NATIVE,
            BUILD_LIST, BUILD_TUPLE, BUILD_DICT, GET_MEMBER, SET_MEMBER, IMPORT, IMPORT_MODULE, NEW_INSTANCE,
            GET_SUPER, NEW_CELL, NEW_CELL_EMPTY, UPVALUE_CELL]:
    _OPERANDS[_op] = 1
_OPERANDS[TRY_BEGIN] = 2
_OPERANDS[MAKE_CLOSURE] = 2

func operand_count(op):
    return _OPERANDS[op]

func instr_size(op):
    return 1 + 4 * _OPERANDS[op]

func opcode_name(op):
    if op >= 0 and op < OPCODE_COUNT:
        return OPCODE_NAMES[op]
    return "?"

# Opcodes dont l'opérande a est un index de constante (décalé par merge_modules).
func operand_a_is_constant(op):
    return op == CONST or op == LOAD_GLOBAL or op == STORE_GLOBAL or op == GET_MEMBER or op == SET_MEMBER or op == IMPORT or op == IMPORT_MODULE or op == NEW_INSTANCE or op == GET_SUPER or op == MAKE_CLOSURE

# ---------------------------------------------------------------------------------------------- constantes
const T_NULL := 0
const T_BOOL := 1
const T_INT := 2
const T_FLOAT := 3
const T_CHAR := 4
const T_BYTE := 5
const T_STRING := 6

const TAG_NAMES := ["NULL", "BOOL", "INT", "FLOAT", "CHAR", "BYTE", "STRING"]

func const_null():
    return [T_NULL, null]

func const_bool(b):
    return [T_BOOL, b]

func const_int(v):
    return [T_INT, v]

func const_float(v):
    return [T_FLOAT, v]

func const_char(cp):
    return [T_CHAR, cp]

func const_byte(b):
    return [T_BYTE, b]

func const_str(s):
    return [T_STRING, s]

# Clé de dédoublonnage reproduisant Constant::operator== (égalité de double : 0.0 == -0.0, NaN jamais égal).
func const_key(c):
    t := c[0]
    if t == T_NULL:
        return "N"
    if t == T_BOOL:
        return "B1" if c[1] else "B0"
    if t == T_INT:
        return "I" + str(c[1])
    if t == T_FLOAT:
        v := c[1]
        if v != v:
            return null
        if v == 0.0:
            return "F0"
        return "F" + str(_n.f64_bits(v))
    if t == T_CHAR:
        return "C" + str(c[1])
    if t == T_BYTE:
        return "Y" + str(c[1])
    return "S" + c[1]

func _qstr(s):
    out := "\""
    for ch in s:
        if ch == '"':
            out += "\\\""
        elif ch == '\\':
            out += "\\\\"
        elif ch == '\n':
            out += "\\n"
        elif ch == '\t':
            out += "\\t"
        else:
            out += str(ch)
    return out + "\""

func const_text(c):
    t := c[0]
    if t == T_NULL:
        return "NULL null"
    if t == T_BOOL:
        return "BOOL " + ("1" if c[1] else "0")
    if t == T_INT:
        return "INT " + str(c[1])
    if t == T_FLOAT:
        return "FLOAT " + _n.repr_float(c[1])
    if t == T_CHAR:
        return "CHAR " + str(c[1])
    if t == T_BYTE:
        return "BYTE " + str(c[1])
    return "STRING " + _qstr(c[1])

# ---------------------------------------------------------------------------------------------- modèle
class FunctionEntry:
    func init(function_id=0, name_const=0):
        self.function_id = function_id
        self.name_const = name_const
        self.code_offset = 0
        self.code_length = 0
        self.arity_min = 0
        self.arity_max = 0
        self.locals_count = 0
        self.flags = 0
        self.debug_lines = []      # [[offset, ligne], ...]
        self.source_const = NO_CONST
        self.local_names = []

class BcModule:
    func init():
        self.version_major = 0
        self.version_minor = 2
        self.flags = 0
        self.producer = ""
        self.constants = []
        self.functions = []
        self.code = []             # octets
        self.entry_function = 0
        self._index = {}

    # Index de la constante (ajoutée si absente), avec le même dédoublonnage que le compilateur de référence.
    func intern(c):
        k := const_key(c)
        if k != null and k in self._index:
            return self._index[k]
        append(self.constants, c)
        i := len(self.constants) - 1
        if k != null:
            self._index[k] = i
        return i

    func function_name(fn):
        c := self.constants[fn.name_const]
        return c[1] if c[0] == T_STRING else "?"

    func find_function(name):
        for fn in self.functions:
            if self.function_name(fn) == name:
                return fn
        return null

    # Instructions [op, a, b] d'une fonction, avec leur offset relatif : [[offset, [op, a, b]], ...].
    func decode_function(fn):
        return decode_code(self.code, fn.code_offset, fn.code_length)

# ---------------------------------------------------------------------------------------------- encodage
func _u16(out, v):
    append(out, v & 255)
    append(out, (v >> 8) & 255)

func _u32(out, v):
    append(out, v & 255)
    append(out, (v >> 8) & 255)
    append(out, (v >> 16) & 255)
    append(out, (v >> 24) & 255)

func _u64(out, v):
    i := 0
    while i < 8:
        append(out, (v >> (8 * i)) & 255)
        i += 1

# Instructions [op, a, b] -> octets (largeur fixe, même encodage que bc::encodeInstructions).
func encode_instructions(instrs, out=null):
    o := out if out != null else []
    for ins in instrs:
        op := ins[0]
        append(o, op)
        n := _OPERANDS[op]
        if n >= 1:
            a := ins[1]
            append(o, a & 255)
            append(o, (a >> 8) & 255)
            append(o, (a >> 16) & 255)
            append(o, (a >> 24) & 255)
        if n >= 2:
            b := ins[2]
            append(o, b & 255)
            append(o, (b >> 8) & 255)
            append(o, (b >> 16) & 255)
            append(o, (b >> 24) & 255)
    return o

func _rd32(b, p):
    return b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)

func decode_code(code, offset, length):
    out := []
    p := offset
    end := offset + length
    if end > len(code):
        raise("BytecodeError", "code_offset/code_length dépasse CODE_SECTION")
    while p < end:
        op := code[p]
        if op >= OPCODE_COUNT:
            raise("BytecodeError", "octet d'opcode " + str(op) + " non reconnu à l'offset " + str(p))
        a := 0
        b := 0
        n := _OPERANDS[op]
        if p + 1 + 4 * n > end:
            raise("BytecodeError", "instruction tronquée à l'offset " + str(p))
        if n >= 1:
            a = _rd32(code, p + 1)
        if n >= 2:
            b = _rd32(code, p + 5)
        append(out, [p - offset, [op, a, b]])
        p += 1 + 4 * n
    return out

func _bytes_of(s):
    return _s.byte_unpack(s)

func _write_constant(out, c):
    t := c[0]
    append(out, t)
    if t == T_NULL:
        return
    if t == T_BOOL:
        append(out, 1 if c[1] else 0)
    elif t == T_INT:
        _u64(out, c[1])
    elif t == T_FLOAT:
        _u64(out, _n.f64_bits(c[1]))
    elif t == T_CHAR:
        _u32(out, c[1])
    elif t == T_BYTE:
        append(out, c[1] & 255)
    else:
        bs := _bytes_of(c[1])
        _u32(out, len(bs))
        for x in bs:
            append(out, x)

# Module -> octets du fichier .albc (identique à bc::writeModule).
func write_module(m):
    out := [65, 76, 66, 67]
    _u16(out, m.version_major)
    _u16(out, m.version_minor)
    _u32(out, m.flags)
    _u32(out, len(m.constants))
    _u32(out, len(m.functions))
    _u32(out, len(m.code))
    _u32(out, m.entry_function)
    for c in m.constants:
        _write_constant(out, c)
    for fn in m.functions:
        _u32(out, fn.function_id)
        _u32(out, fn.name_const)
        _u32(out, fn.code_offset)
        _u32(out, fn.code_length)
        _u16(out, fn.arity_min)
        _u16(out, fn.arity_max)
        _u16(out, fn.locals_count)
        _u16(out, fn.flags)
    for x in m.code:
        append(out, x)
    for fn in m.functions:
        if m.version_minor >= 2:
            _u32(out, fn.source_const)
        _u32(out, len(fn.debug_lines))
        for pr in fn.debug_lines:
            _u32(out, pr[0])
            _u32(out, pr[1])
        if m.version_minor >= 3:
            _u32(out, len(fn.local_names))
            for nm in fn.local_names:
                bs := _bytes_of(nm)
                _u32(out, len(bs))
                for x in bs:
                    append(out, x)
    if m.version_minor >= 4:
        bs := _bytes_of(m.producer)
        _u32(out, len(bs))
        for x in bs:
            append(out, x)
    return out

# ---------------------------------------------------------------------------------------------- lecture
class _Reader:
    func init(b):
        self.b = b
        self.p = 0

    func need(n):
        if self.p + n > len(self.b):
            raise("BytecodeError", "fichier .albc tronqué à l'octet " + str(self.p))

    func u8():
        self.need(1)
        v := self.b[self.p]
        self.p += 1
        return v

    func u16():
        self.need(2)
        v := self.b[self.p] | (self.b[self.p + 1] << 8)
        self.p += 2
        return v

    func u32():
        self.need(4)
        v := _rd32(self.b, self.p)
        self.p += 4
        return v

    func u64():
        self.need(8)
        v := 0
        i := 7
        while i >= 0:
            v = (v << 8) | self.b[self.p + i]
            i -= 1
        self.p += 8
        return v

    func bytes(n):
        self.need(n)
        out := [self.b[k] for k in self.p..self.p + n]
        self.p += n
        return out

    func text(n):
        return _s.byte_pack(self.bytes(n))

func read_module(b):
    r := _Reader(b)
    if r.bytes(4) != [65, 76, 66, 67]:
        raise("BytecodeError", "signature ALBC absente")
    m := BcModule()
    m.version_major = r.u16()
    m.version_minor = r.u16()
    if m.version_major != 0:
        raise("BytecodeError", "version majeure " + str(m.version_major) + " non prise en charge")
    if m.version_minor > CURRENT_VERSION_MINOR:
        raise("BytecodeError", "bytecode au format 0." + str(m.version_minor) + " (plus récent que 0." + str(CURRENT_VERSION_MINOR) + ")")
    m.flags = r.u32()
    nconst := r.u32()
    nfn := r.u32()
    ncode := r.u32()
    m.entry_function = r.u32()
    i := 0
    while i < nconst:
        t := r.u8()
        if t == T_NULL:
            append(m.constants, const_null())
        elif t == T_BOOL:
            append(m.constants, const_bool(r.u8() != 0))
        elif t == T_INT:
            append(m.constants, const_int(r.u64()))
        elif t == T_FLOAT:
            append(m.constants, const_float(_n.bits_f64(r.u64())))
        elif t == T_CHAR:
            append(m.constants, const_char(r.u32()))
        elif t == T_BYTE:
            append(m.constants, const_byte(r.u8()))
        elif t == T_STRING:
            append(m.constants, const_str(r.text(r.u32())))
        else:
            raise("BytecodeError", "étiquette de constante inconnue " + str(t))
        i += 1
    i = 0
    while i < nfn:
        fn := FunctionEntry()
        fn.function_id = r.u32()
        fn.name_const = r.u32()
        fn.code_offset = r.u32()
        fn.code_length = r.u32()
        fn.arity_min = r.u16()
        fn.arity_max = r.u16()
        fn.locals_count = r.u16()
        fn.flags = r.u16()
        append(m.functions, fn)
        i += 1
    m.code = r.bytes(ncode)
    for fn in m.functions:
        if m.version_minor >= 2:
            fn.source_const = r.u32()
        nl := r.u32()
        k := 0
        while k < nl:
            off := r.u32()
            ln := r.u32()
            append(fn.debug_lines, [off, ln])
            k += 1
        if m.version_minor >= 3:
            nn := r.u32()
            k = 0
            while k < nn:
                append(fn.local_names, r.text(r.u32()))
                k += 1
    if m.version_minor >= 4:
        m.producer = r.text(r.u32())
    return m

# ---------------------------------------------------------------------------------------------- fusion
# Fusionne des modules compilés séparément (bc::mergeModules) : constantes concaténées, opérandes constants
# décalés, identifiants de fonction renumérotés ; point d'entrée = celui du dernier module. Renvoie [module,
# identifiants des points d'entrée d'origine de chaque module].
func merge_modules(modules):
    out := BcModule()
    entries := [0 for i in 0..len(modules)]
    if len(modules) > 0:
        last := modules[len(modules) - 1]
        out.version_major = last.version_major
        out.version_minor = last.version_minor
        out.flags = last.flags
        for m in modules:
            if m.version_minor > out.version_minor:
                out.version_minor = m.version_minor
        out.producer = last.producer
        for m in modules:
            if out.producer == "" and m.producer != "":
                out.producer = m.producer
    next_id := 0
    mi := 0
    while mi < len(modules):
        m := modules[mi]
        off := len(out.constants)
        for c in m.constants:
            append(out.constants, c)
        for fn in m.functions:
            instrs := []
            for pr in decode_code(m.code, fn.code_offset, fn.code_length):
                ins := pr[1]
                if operand_a_is_constant(ins[0]):
                    append(instrs, [ins[0], ins[1] + off, ins[2]])
                else:
                    append(instrs, ins)
            nf := FunctionEntry(next_id, fn.name_const + off)
            next_id += 1
            if fn.function_id == m.entry_function:
                entries[mi] = nf.function_id
                if mi == len(modules) - 1:
                    out.entry_function = nf.function_id
            nf.code_offset = len(out.code)
            nf.code_length = fn.code_length
            nf.arity_min = fn.arity_min
            nf.arity_max = fn.arity_max
            nf.locals_count = fn.locals_count
            nf.flags = fn.flags
            nf.debug_lines = fn.debug_lines
            nf.local_names = fn.local_names
            nf.source_const = NO_CONST if fn.source_const == NO_CONST else fn.source_const + off
            before := len(out.code)
            encode_instructions(instrs, out.code)
            if len(out.code) - before != fn.code_length:
                raise("BytecodeError", "merge_modules : ré-encodage de taille différente (fonction " + str(fn.function_id) + ")")
            append(out.functions, nf)
        mi += 1
    return [out, entries]

# ---------------------------------------------------------------------------------------------- désassemblage
func dump(m):
    lines := ["VERSION " + str(m.version_major) + "." + str(m.version_minor), "FLAGS 0x" + _hex(m.flags),
              "ENTRY_FUNCTION " + str(m.entry_function), "", "CONST_SECTION (" + str(len(m.constants)) + ")"]
    i := 0
    while i < len(m.constants):
        append(lines, "  [" + str(i) + "] " + const_text(m.constants[i]))
        i += 1
    append(lines, "")
    append(lines, "FUNCTION_SECTION (" + str(len(m.functions)) + ")")
    for fn in m.functions:
        append(lines, "  fn #" + str(fn.function_id) + " " + m.function_name(fn) + " arity=" + str(fn.arity_min) + ".." + str(fn.arity_max) + " locals=" + str(fn.locals_count) + " code=" + str(fn.code_offset) + "+" + str(fn.code_length))
        for pr in m.decode_function(fn):
            ins := pr[1]
            t := "      " + _pad(str(pr[0]), 5) + " " + opcode_name(ins[0])
            n := _OPERANDS[ins[0]]
            if n >= 1:
                t += " " + str(ins[1])
                if operand_a_is_constant(ins[0]) and ins[1] < len(m.constants):
                    t += "  ; " + const_text(m.constants[ins[1]])
            if n >= 2:
                t += " " + ("NO_CONST" if ins[2] == NO_CONST else str(ins[2]))
            append(lines, t)
    return _s.join("\n", lines)

func _pad(t, w):
    while len(t) < w:
        t = " " + t
    return t

func _hex(v):
    d := "0123456789abcdef"
    if v == 0:
        return "0"
    out := ""
    n := v
    while n > 0:
        out = str(d[n % 16]) + out
        n = n // 16
    return out

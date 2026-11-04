# ALEX STANDARD LIBRARY — modules.abi
#
# ABI binaire : tailles, alignements et DISPOSITION des structures C selon la plateforme, pour échanger des
# données avec du code natif (ffi, fichiers binaires, pilotes) sans deviner les décalages.
#
#   use modules.abi as abi
#   a := abi.current()                               # ABI de la machine (ex. "sysv-x86_64")
#   l := a.layout([["id", "u32"], ["flag", "u8"], ["value", "f64"]])
#   print(l.size, l.align, l.offset("value"))        # 16 8 8
#   print(l.describe())                              # tableau champ / décalage / taille / bourrage
#   p := abi.ABI("sysv-i386").layout([["a", "u8"], ["b", "f64"]])
#   print(p.offset("b"))                             # 4 (i386 : double aligné sur 4 dans les structures)
#   print(abi.mangle_c("ma_fonction", "win32-x86"))  # "_ma_fonction"
#
# ABI connues : sysv-x86_64, sysv-aarch64, win64 (x64 et ARM64), sysv-i386, win32-x86, sysv-arm32.
# Types : bool i8 u8 i16 u16 i32 u32 i64 u64 f32 f64 ptr size_t char, et structures imbriquées (Layout),
# tableaux [type, n].
# Erreurs : ABIError (ABI ou type inconnu), TypeError.

from core use len, type
from collections use append
use string as _s
use os as _os

const ERROR := "ABIError"

const KNOWN := ["sysv-x86_64", "sysv-aarch64", "win64", "sysv-i386", "win32-x86", "sysv-arm32"]

class Field:
    func init(name, type_name, offset, size, align, count=1):
        self.name = name
        self.type = type_name
        self.offset = offset
        self.size = size
        self.align = align
        self.count = count

class Layout:
    func init(fields, size, align, abi_name):
        self.fields = fields
        self.size = size
        self.align = align
        self.abi = abi_name

    func field(name):
        for f in self.fields:
            if f.name == name:
                return f
        raise(ERROR, "Layout : champ '" + name + "' absent")

    func offset(name):
        return self.field(name).offset

    func names():
        return [f.name for f in self.fields]

    # Octets de bourrage avant chaque champ et en fin de structure.
    func padding():
        out := []
        cur := 0
        for f in self.fields:
            append(out, [f.name, f.offset - cur])
            cur = f.offset + f.size
        append(out, ["<fin>", self.size - cur])
        return out

    func total_padding():
        n := 0
        for p in self.padding():
            n += p[1]
        return n

    func describe():
        lines := ["struct (" + self.abi + ") : " + str(self.size) + " octets, alignement " + str(self.align)]
        pads := self.padding()
        i := 0
        for f in self.fields:
            pad := ""
            if pads[i][1] > 0:
                pad = "   (+" + str(pads[i][1]) + " bourrage avant)"
            t := f.type
            if f.count > 1:
                t = t + "[" + str(f.count) + "]"
            append(lines, "  " + _pad(str(f.offset), 5) + _pad(f.name, 16) + _pad(t, 12) + str(f.size) + pad)
            i += 1
        if pads[len(pads) - 1][1] > 0:
            append(lines, "  bourrage final : " + str(pads[len(pads) - 1][1]))
        return _s.join("\n", lines)

func _pad(s, n):
    out := s
    while len(out) < n:
        out += " "
    return out

func _round(n, a):
    return ((n + a - 1) // a) * a

class ABI:
    func init(name):
        ok := false
        for k in KNOWN:
            if k == name:
                ok = true
        if not ok:
            raise(ERROR, "ABI inconnue '" + str(name) + "' (" + _s.join(", ", KNOWN) + ")")
        self.name = name
        self.pointer_size = 8
        if name == "sysv-i386" or name == "win32-x86" or name == "sysv-arm32":
            self.pointer_size = 4
        self.long_size = 8
        if name == "win64" or self.pointer_size == 4:
            self.long_size = 4
        self.big_endian = false

    # [taille, alignement] d'un type scalaire.
    func scalar(t):
        p := self.pointer_size
        sizes := {"bool": 1, "char": 1, "i8": 1, "u8": 1, "byte": 1, "i16": 2, "u16": 2, "i32": 4, "u32": 4,
                  "int": 4, "uint": 4, "f32": 4, "float": 4, "i64": 8, "u64": 8, "f64": 8, "double": 8,
                  "ptr": p, "size_t": p, "intptr": p, "long": self.long_size, "ulong": self.long_size}
        if not (t in sizes):
            raise(ERROR, "ABI.scalar : type inconnu '" + str(t) + "'")
        size := sizes[t]
        align := size
        # i386 System V : double et long long alignés sur 4 dans les structures.
        if self.name == "sysv-i386" and size == 8:
            align = 4
        return [size, align]

    func size_of(t):
        if isinstance(t, Layout):
            return t.size
        return self.scalar(t)[0]

    func align_of(t):
        if isinstance(t, Layout):
            return t.align
        return self.scalar(t)[1]

    # fields : [[nom, type], ...] ; type = scalaire, Layout, ou [type, nombre] (tableau).
    # packed=true : aucun bourrage (#pragma pack(1)).
    func layout(fields, packed=false):
        out := []
        off := 0
        max_align := 1
        for f in fields:
            name := f[0]
            t := f[1]
            count := 1
            if type(t) == "list":
                count = t[1]
                t = t[0]
            size := self.size_of(t)
            align := self.align_of(t)
            if packed:
                align = 1
            off = _round(off, align)
            tn := t
            if isinstance(t, Layout):
                tn = "struct"
            append(out, Field(name, tn, off, size * count, align, count))
            off += size * count
            if align > max_align:
                max_align = align
        total := _round(off, max_align)
        return Layout(out, total, max_align, self.name)

    # Disposition d'une union : tous les champs au décalage 0.
    func union_layout(fields):
        out := []
        size := 0
        max_align := 1
        for f in fields:
            s := self.size_of(f[1])
            a := self.align_of(f[1])
            append(out, Field(f[0], f[1], 0, s, a))
            if s > size:
                size = s
            if a > max_align:
                max_align = a
        return Layout(out, _round(size, max_align), max_align, self.name)

    # Registres d'arguments entiers de la convention d'appel.
    func integer_argument_registers():
        if self.name == "sysv-x86_64":
            return ["rdi", "rsi", "rdx", "rcx", "r8", "r9"]
        if self.name == "win64":
            return ["rcx", "rdx", "r8", "r9"]
        if self.name == "sysv-aarch64":
            return ["x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7"]
        if self.name == "sysv-arm32":
            return ["r0", "r1", "r2", "r3"]
        return []

    # Alignement de pile exigé à l'appel.
    func stack_alignment():
        if self.pointer_size == 4 and self.name != "sysv-arm32":
            return 4
        if self.name == "sysv-arm32":
            return 8
        return 16

    func __str__():
        return "ABI(" + self.name + ")"

# ABI de la machine courante.
func current():
    plat := _os.platform()
    arch := _os.arch()
    if plat == "windows":
        if arch == "x86":
            return ABI("win32-x86")
        return ABI("win64")
    if arch == "aarch64" or arch == "arm64":
        return ABI("sysv-aarch64")
    if arch == "x86":
        return ABI("sysv-i386")
    if arch == "arm":
        return ABI("sysv-arm32")
    return ABI("sysv-x86_64")

func layout(fields, abi_name=null, packed=false):
    a := current()
    if abi_name != null:
        a = ABI(abi_name)
    return a.layout(fields, packed)

# Symbole C tel que vu par l'éditeur de liens (« _f » en 32 bits Windows et sous macOS).
func mangle_c(name, abi_name=null, macos=false):
    n := abi_name
    if n == null:
        n = current().name
    if n == "win32-x86" or macos:
        return "_" + name
    return name

func known():
    return KNOWN[:]

# ALEX — native.x64
#
# Assembleur x86-64 du compilateur natif écrit en ALEX (étape C) : portage fidèle de src/NativeX64.cpp et de
# l'écriture ELF64 de src/NativeElf.cpp. Encode directement les instructions utilisées par le générateur de
# code (mov, alu, imul, idiv, sauts, appels, SSE2...), gère étiquettes, correctifs de sauts et relocations
# absolues ; write_elf construit l'exécutable statique Linux (deux segments : en-têtes + code + données en
# lecture seule à 0x40000000, bss sur la page suivante).
#
#   use native.x64 as x
#   a := x.Assembler()
#   a.mov_imm(x.RAX, 60)
#   a.syscall()
#   x.write_elf(x.ElfImage(a, [], 8, 0), "sortie")
#
# Erreurs : RuntimeError (étiquette non liée, adresse hors 32 bits, adressage indexé non pris en charge).

from core use len, type
from collections use append
use io as _io
use os as _os
use string as _s

const RAX := 0
const RCX := 1
const RDX := 2
const RBX := 3
const RSP := 4
const RBP := 5
const RSI := 6
const RDI := 7
const R8 := 8
const R9 := 9
const R10 := 10
const R11 := 11
const R12 := 12
const R13 := 13
const R14 := 14
const R15 := 15

# Conditions (suffixe de Jcc / SETcc)
const C_O := 0
const C_NO := 1
const C_B := 2
const C_AE := 3
const C_E := 4
const C_NE := 5
const C_BE := 6
const C_A := 7
const C_S := 8
const C_NS := 9
const C_P := 10
const C_NP := 11
const C_L := 12
const C_GE := 13
const C_LE := 14
const C_G := 15

# Opérations ALU
const ALU_ADD := 0
const ALU_OR := 1
const ALU_AND := 4
const ALU_SUB := 5
const ALU_XOR := 6
const ALU_CMP := 7

# Sections
const S_RODATA := 0
const S_BSS := 1
const S_CODE := 2
const S_IMPORT := 3

const INT32_MIN := -2147483648
const INT32_MAX := 2147483647

class Mem:
    func init(base=5, disp=0, absolute=false, section=1, offset=0):
        self.base = base
        self.disp = disp
        self.absolute = absolute
        self.section = section
        self.offset = offset

func at(b, d=0):
    return Mem(b, d, false, S_BSS, 0)

func data(s, off, d=0):
    return Mem(RAX, d, true, s, off)

# Relocation : [pos, section, offset, addend, rel, trail]
class Assembler:
    func init():
        self.pic = false
        self.code = []
        self.relocs = []
        self.labels = []
        self.trail = 0
        self.fixups = []
        self.label_relocs = []

    func new_label():
        append(self.labels, -1)
        return len(self.labels) - 1

    func bind(l):
        self.labels[l] = len(self.code)

    func is_bound(l):
        return self.labels[l] >= 0

    func label_pos(l):
        return self.labels[l]

    func size():
        return len(self.code)

    func resolve():
        for f in self.fixups:
            target := self.labels[f[1]]
            if target < 0:
                raise("RuntimeError", "assembleur : label non lié")
            rel := target - (f[0] + 4)
            i := 0
            while i < 4:
                self.code[f[0] + i] = (rel >> (8 * i)) & 0xFF
                i += 1
        self.fixups = []
        for lr in self.label_relocs:
            target := self.labels[lr[1]]
            if target < 0:
                raise("RuntimeError", "assembleur : label non lié")
            self.relocs[lr[0]][2] = target
        self.label_relocs = []

    func byte(b):
        append(self.code, b & 0xFF)

    func raw(bs):
        for b in bs:
            append(self.code, b & 0xFF)

    func u32(v):
        append(self.code, v & 0xFF)
        append(self.code, (v >> 8) & 0xFF)
        append(self.code, (v >> 16) & 0xFF)
        append(self.code, (v >> 24) & 0xFF)

    func rex(w, reg, index, base, force=false):
        r := 0x40 | (8 if w else 0) | (4 if (reg & 8) != 0 else 0) | (2 if (index & 8) != 0 else 0) | (1 if (base & 8) != 0 else 0)
        if r != 0x40 or force:
            self.byte(r)

    func modrm_reg(reg, rm):
        self.byte(0xC0 | ((reg & 7) << 3) | (rm & 7))

    func modrm_mem(reg, m):
        r := (reg & 7) << 3
        if m.absolute:
            if self.pic:
                self.byte(0x05 | r)
                append(self.relocs, [len(self.code), m.section, m.offset, m.disp, true, self.trail])
                self.trail = 0
                self.u32(0)
                return
            self.byte(0x04 | r)
            self.byte(0x25)
            append(self.relocs, [len(self.code), m.section, m.offset, m.disp, false, 0])
            self.u32(0)
            return
        self.trail = 0
        b := m.base & 7
        need_sib := b == 4
        if m.disp == 0 and b != 5:
            self.byte(0x00 | r | (4 if need_sib else b))
            if need_sib:
                self.byte(0x24)
        elif m.disp >= -128 and m.disp <= 127:
            self.byte(0x40 | r | (4 if need_sib else b))
            if need_sib:
                self.byte(0x24)
            self.byte(m.disp)
        else:
            self.byte(0x80 | r | (4 if need_sib else b))
            if need_sib:
                self.byte(0x24)
            self.u32(m.disp)

    func op_mem(w, opcode, reg, m, byte_reg=false):
        self.rex(w, reg, 0, 0 if m.absolute else m.base, byte_reg and reg >= 4 and reg < 8)
        for o in opcode:
            self.byte(o)
        self.modrm_mem(reg, m)

    func op_reg(w, opcode, reg, rm, byte_reg=false):
        self.rex(w, reg, 0, rm, byte_reg and ((reg >= 4 and reg < 8) or (rm >= 4 and rm < 8)))
        for o in opcode:
            self.byte(o)
        self.modrm_reg(reg, rm)

    func rel32(l):
        append(self.fixups, [len(self.code), l])
        self.u32(0)

    func mov_imm(r, imm):
        if imm >= 0 and imm <= 0xFFFFFFFF:
            self.rex(false, 0, 0, r)
            self.byte(0xB8 + (r & 7))
            self.u32(imm)
        elif imm >= INT32_MIN and imm <= INT32_MAX:
            self.op_reg(true, [0xC7], 0, r)
            self.u32(imm)
        else:
            self.rex(true, 0, 0, r)
            self.byte(0xB8 + (r & 7))
            self.u32(imm)
            self.u32(imm >> 32)

    func mov_addr(r, s, off):
        if self.pic:
            self.rex(true, r, 0, 0)
            self.byte(0x8D)
            self.byte(0x05 | ((r & 7) << 3))
            append(self.relocs, [len(self.code), s, off, 0, true, 0])
            self.u32(0)
            return
        self.rex(false, 0, 0, r)
        self.byte(0xB8 + (r & 7))
        append(self.relocs, [len(self.code), s, off, 0, false, 0])
        self.u32(0)

    func mov_label_addr(r, l):
        self.mov_addr(r, S_CODE, 0)
        append(self.label_relocs, [len(self.relocs) - 1, l])

    func jmp_reg(r):
        self.op_reg(false, [0xFF], 4, r)

    func call_reg(r):
        self.op_reg(false, [0xFF], 2, r)

    func mov(dst, src):
        if dst != src:
            self.op_reg(true, [0x89], src, dst)

    func load(dst, m):
        self.op_mem(true, [0x8B], dst, m)

    func store(m, src):
        self.op_mem(true, [0x89], src, m)

    func store_imm(m, imm):
        self.trail = 4
        self.op_mem(true, [0xC7], 0, m)
        self.u32(imm)

    func store8(m, src):
        self.op_mem(false, [0x88], src, m, true)

    func load8zx(dst, m):
        self.op_mem(false, [0x0F, 0xB6], dst, m)

    func load16zx(dst, m):
        self.op_mem(false, [0x0F, 0xB7], dst, m)

    func load32(dst, m):
        self.op_mem(false, [0x8B], dst, m)

    func store16(m, src):
        self.prefixed_mem(0x66, false, [0x89], src, m)

    func store32(m, src):
        self.op_mem(false, [0x89], src, m)

    func lea(dst, m):
        self.op_mem(true, [0x8D], dst, m)

    func alu_rr(op, dst, src):
        self.op_reg(true, [op * 8 + 1], src, dst)

    func alu_rm(op, dst, m):
        self.op_mem(true, [op * 8 + 3], dst, m)

    func alu_ri(op, dst, imm):
        if imm >= -128 and imm <= 127:
            self.op_reg(true, [0x83], op, dst)
            self.byte(imm)
        else:
            self.op_reg(true, [0x81], op, dst)
            self.u32(imm)

    func alu_mi(op, m, imm):
        small := imm >= -128 and imm <= 127
        self.trail = 1 if small else 4
        self.op_mem(true, [0x83 if small else 0x81], op, m)
        if small:
            self.byte(imm)
        else:
            self.u32(imm)

    func imul(dst, src):
        self.op_reg(true, [0x0F, 0xAF], dst, src)

    func imul_m(dst, m):
        self.op_mem(true, [0x0F, 0xAF], dst, m)

    func test(a, b):
        self.op_reg(true, [0x85], b, a)

    func cqo():
        self.byte(0x48)
        self.byte(0x99)

    func idiv(r):
        self.op_reg(true, [0xF7], 7, r)

    func divu(r):
        self.op_reg(true, [0xF7], 6, r)

    func rep_movsb():
        self.byte(0xF3)
        self.byte(0xA4)

    func rep_stosb():
        self.byte(0xF3)
        self.byte(0xAA)

    func neg(r):
        self.op_reg(true, [0xF7], 3, r)

    func notr(r):
        self.op_reg(true, [0xF7], 2, r)

    func shl_cl(r):
        self.op_reg(true, [0xD3], 4, r)

    func sar_cl(r):
        self.op_reg(true, [0xD3], 7, r)

    func shr_imm(r, n):
        self.op_reg(true, [0xC1], 5, r)
        self.byte(n)

    func inc(m):
        self.op_mem(true, [0xFF], 0, m)

    func dec(m):
        self.op_mem(true, [0xFF], 1, m)

    func setcc(c, r8):
        self.op_reg(false, [0x0F, 0x90 + c], 0, r8, true)

    func movzx8(dst, src8):
        self.op_reg(false, [0x0F, 0xB6], dst, src8, true)

    func prefixed_mem(prefix, w, opcode, reg, m):
        self.byte(prefix)
        self.op_mem(w, opcode, reg, m)

    func prefixed_reg(prefix, w, opcode, reg, rm):
        self.byte(prefix)
        self.op_reg(w, opcode, reg, rm)

    func sse_op_rr(op, xmm, src):
        self.prefixed_reg(0xF2, false, [0x0F, op], xmm, src)

    func ucomisd_rr(xmm, src):
        self.prefixed_reg(0x66, false, [0x0F, 0x2E], xmm, src)

    func cvtsi2sd_r(xmm, gpr):
        self.prefixed_reg(0xF2, true, [0x0F, 0x2A], xmm, gpr)

    func cvttsd2si_r(gpr, xmm):
        self.prefixed_reg(0xF2, true, [0x0F, 0x2C], gpr, xmm)

    func movq_to_xmm(xmm, gpr):
        self.prefixed_reg(0x66, true, [0x0F, 0x6E], xmm, gpr)

    func movq_from_xmm(gpr, xmm):
        self.prefixed_reg(0x66, true, [0x0F, 0x7E], xmm, gpr)

    func movsd_load(xmm, m):
        self.prefixed_mem(0xF2, false, [0x0F, 0x10], xmm, m)

    func movsd_store(m, xmm):
        self.prefixed_mem(0xF2, false, [0x0F, 0x11], xmm, m)

    func sse_op(op, xmm, m):
        self.prefixed_mem(0xF2, false, [0x0F, op], xmm, m)

    func ucomisd(xmm, m):
        self.prefixed_mem(0x66, false, [0x0F, 0x2E], xmm, m)

    func cvtsi2sd(xmm, m):
        self.prefixed_mem(0xF2, true, [0x0F, 0x2A], xmm, m)

    func cvttsd2si(dst, m):
        self.prefixed_mem(0xF2, true, [0x0F, 0x2C], dst, m)

    func sib8(opcode, reg, base, index):
        if (base & 7) == 5 or index == RSP:
            raise("RuntimeError", "assembleur : adressage indexé non pris en charge")
        self.rex(true, reg, index, base)
        self.byte(opcode)
        self.byte(0x04 | ((reg & 7) << 3))
        self.byte(0xC0 | ((index & 7) << 3) | (base & 7))

    func load_idx(dst, base, index):
        self.sib8(0x8B, dst, base, index)

    func store_idx(base, index, src):
        self.sib8(0x89, src, base, index)

    func push(r):
        self.rex(false, 0, 0, r)
        self.byte(0x50 + (r & 7))

    func push_m(m):
        self.op_mem(false, [0xFF], 6, m)

    func pop(r):
        self.rex(false, 0, 0, r)
        self.byte(0x58 + (r & 7))

    func call(l):
        self.byte(0xE8)
        self.rel32(l)

    func jmp(l):
        self.byte(0xE9)
        self.rel32(l)

    func jcc(c, l):
        self.byte(0x0F)
        self.byte(0x80 + c)
        self.rel32(l)

    func ret():
        self.byte(0xC3)

    func leave():
        self.byte(0xC9)

    func syscall():
        self.byte(0x0F)
        self.byte(0x05)

# ---------------------------------------------------------------------------------------------- ELF
const IMAGE_BASE := 0x40000000
const EHDR_SIZE := 64
const PHDR_SIZE := 56
const PAGE := 0x1000

class ElfImage:
    func init(code, rodata, bss_size, entry_offset):
        self.code = code
        self.rodata = rodata
        self.bss_size = bss_size
        self.entry_offset = entry_offset
        self.symbols = []        # [début, fin, nom]
        self.imports = []        # [« lib.so!symbole »] : ELF dynamique (VM écrite en ALEX), sinon statique
        self.base = IMAGE_BASE   # adresse de chargement de l'ELF statique (--image-base, outils de test)

func put(out, v, n):
    i := 0
    while i < n:
        append(out, (v >> (8 * i)) & 0xFF)
        i += 1

func align(out, a):
    while len(out) % a != 0:
        append(out, 0)

const _HEX := "0123456789abcdef"

func _hex16(v):
    s := ""
    i := 15
    while i >= 0:
        s += str(_HEX[(v >> (4 * i)) & 15])
        i -= 1
    return s

func write_map(image, code_base, path):
    if len(image.symbols) == 0:
        return
    out := []
    for s in image.symbols:
        append(out, _hex16(code_base + s[0]) + " " + _hex16(code_base + s[1]) + " " + s[2] + "\n")
    t := ""
    for x in out:
        t += x
    _io.write_file(path + ".map", t)

# Image ELF64 (liste d'octets) ; les relocations du code sont résolues en place.
func build_elf(image, path=null):
    if len(image.imports) > 0:
        return build_elf_dynamic(image, path)
    a := image.code
    a.resolve()
    ibase := image.base
    headers := EHDR_SIZE + 2 * PHDR_SIZE
    code_off := (headers + 15) & ~15
    rodata_off := (code_off + len(a.code) + 15) & ~15
    file_size := rodata_off + len(image.rodata)
    bss_addr := (ibase + file_size + PAGE - 1) // PAGE * PAGE + PAGE
    if path != null:
        write_map(image, ibase + code_off, path)
    for r in a.relocs:
        base := ibase + rodata_off if r[1] == S_RODATA else ibase + code_off if r[1] == S_CODE else bss_addr
        addr := base + r[2] + r[3]
        if addr > 0x7FFFFFFF:
            raise("RuntimeError", "ELF : adresse hors de la plage 32 bits")
        i := 0
        while i < 4:
            a.code[r[0] + i] = (addr >> (8 * i)) & 0xFF
            i += 1
    out := [0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    put(out, 2, 2)
    put(out, 62, 2)
    put(out, 1, 4)
    put(out, ibase + code_off + image.entry_offset, 8)
    put(out, EHDR_SIZE, 8)
    put(out, 0, 8)
    put(out, 0, 4)
    put(out, EHDR_SIZE, 2)
    put(out, PHDR_SIZE, 2)
    put(out, 2, 2)
    put(out, 64, 2)
    put(out, 0, 2)
    put(out, 0, 2)
    put(out, 1, 4)
    put(out, 5, 4)
    put(out, 0, 8)
    put(out, ibase, 8)
    put(out, ibase, 8)
    put(out, file_size, 8)
    put(out, file_size, 8)
    put(out, PAGE, 8)
    put(out, 1, 4)
    put(out, 6, 4)
    put(out, 0, 8)
    put(out, bss_addr, 8)
    put(out, bss_addr, 8)
    put(out, 0, 8)
    put(out, image.bss_size if image.bss_size != 0 else 8, 8)
    put(out, PAGE, 8)
    align(out, 16)
    for b in a.code:
        append(out, b)
    align(out, 16)
    for b in image.rodata:
        append(out, b)
    return out

# ELF dynamique : comme l'image statique (code et données à adresses fixes), plus un interpréteur (ld-linux), les
# bibliothèques nécessaires et une table des adresses importées (GOT) remplie au chargement (R_X86_64_GLOB_DAT,
# liaison immédiate). Segments : PT_INTERP, PT_LOAD R+X (en-têtes, code, données, tables), PT_LOAD RW (.dynamic,
# GOT), PT_LOAD RW (bss), PT_DYNAMIC. Utilisé par la VM écrite en ALEX (dlopen pour ffi et TLS).
const INTERP := "/lib64/ld-linux-x86-64.so.2"

func _cstr_bytes(t):
    out := _s.byte_unpack(t)
    append(out, 0)
    return out

func build_elf_dynamic(image, path=null):
    a := image.code
    a.resolve()
    nph := 5
    headers := EHDR_SIZE + nph * PHDR_SIZE
    code_off := (headers + 15) & ~15
    rodata_off := (code_off + len(a.code) + 15) & ~15
    # tables en lecture seule, après les données
    libs := []
    syms := []
    for full in image.imports:
        bang := _s.find(full, "!")
        lib := _s.substring(full, 0, bang)
        if not (lib in libs):
            append(libs, lib)
        append(syms, _s.substring(full, bang + 1, len(full)))
    if "libdl.so.2" in libs and not ("libc.so.6" in libs):
        append(libs, "libc.so.6")
    t := []
    interp_off := rodata_off + len(image.rodata)
    for b in _cstr_bytes(INTERP):
        append(t, b)
    while (interp_off + len(t)) % 8 != 0:
        append(t, 0)
    dynstr_off := interp_off + len(t)
    strtab := [0]
    lib_name := []
    for lib in libs:
        append(lib_name, len(strtab))
        for b in _cstr_bytes(lib):
            append(strtab, b)
    sym_name := []
    for sy in syms:
        append(sym_name, len(strtab))
        for b in _cstr_bytes(sy):
            append(strtab, b)
    for b in strtab:
        append(t, b)
    while (interp_off + len(t)) % 8 != 0:
        append(t, 0)
    dynsym_off := interp_off + len(t)
    put(t, 0, 8)
    put(t, 0, 8)
    put(t, 0, 8)
    k := 0
    while k < len(syms):
        put(t, sym_name[k], 4)
        put(t, 0x12, 1)
        put(t, 0, 1)
        put(t, 0, 2)
        put(t, 0, 8)
        put(t, 0, 8)
        k += 1
    hash_off := interp_off + len(t)
    nsym := len(syms) + 1
    put(t, 1, 4)
    put(t, nsym, 4)
    put(t, 0, 4)
    k = 0
    while k < nsym:
        put(t, 0, 4)
        k += 1
    while (interp_off + len(t)) % 8 != 0:
        append(t, 0)
    rela_off := interp_off + len(t)
    rela_at := len(t)
    k = 0
    while k < len(syms):
        put(t, 0, 8)    # complété quand l'adresse de la GOT est connue
        put(t, 0, 8)
        put(t, 0, 8)
        k += 1
    ro_end := interp_off + len(t)
    # segment RW : .dynamic puis GOT, à une frontière de page (adresse = décalage dans le fichier + base)
    data_off := (ro_end + PAGE - 1) // PAGE * PAGE
    ndyn := len(libs) + 11
    dyn_size := 16 * ndyn
    got_off := data_off + dyn_size
    data_size := dyn_size + 8 * len(syms)
    file_size := data_off + data_size
    got_addr := IMAGE_BASE + got_off
    bss_addr := (IMAGE_BASE + file_size + PAGE - 1) // PAGE * PAGE + PAGE
    k = 0
    while k < len(syms):
        e := rela_at + 24 * k
        v := got_addr + 8 * k
        i := 0
        while i < 8:
            t[e + i] = (v >> (8 * i)) & 0xFF
            t[e + 8 + i] = ((((k + 1) << 32) | 6) >> (8 * i)) & 0xFF
            i += 1
        k += 1
    if path != null:
        write_map(image, IMAGE_BASE + code_off, path)
    for r in a.relocs:
        base := IMAGE_BASE + rodata_off if r[1] == S_RODATA else IMAGE_BASE + code_off if r[1] == S_CODE else got_addr if r[1] == S_IMPORT else bss_addr
        addr := base + r[2] + r[3]
        if addr > 0x7FFFFFFF:
            raise("RuntimeError", "ELF : adresse hors de la plage 32 bits")
        i := 0
        while i < 4:
            a.code[r[0] + i] = (addr >> (8 * i)) & 0xFF
            i += 1
    out := [0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    put(out, 2, 2)
    put(out, 62, 2)
    put(out, 1, 4)
    put(out, IMAGE_BASE + code_off + image.entry_offset, 8)
    put(out, EHDR_SIZE, 8)
    put(out, 0, 8)
    put(out, 0, 4)
    put(out, EHDR_SIZE, 2)
    put(out, PHDR_SIZE, 2)
    put(out, nph, 2)
    put(out, 64, 2)
    put(out, 0, 2)
    put(out, 0, 2)
    # PT_INTERP
    put(out, 3, 4)
    put(out, 4, 4)
    put(out, interp_off, 8)
    put(out, IMAGE_BASE + interp_off, 8)
    put(out, IMAGE_BASE + interp_off, 8)
    put(out, len(INTERP) + 1, 8)
    put(out, len(INTERP) + 1, 8)
    put(out, 1, 8)
    # PT_LOAD R+X
    put(out, 1, 4)
    put(out, 5, 4)
    put(out, 0, 8)
    put(out, IMAGE_BASE, 8)
    put(out, IMAGE_BASE, 8)
    put(out, ro_end, 8)
    put(out, ro_end, 8)
    put(out, PAGE, 8)
    # PT_LOAD RW (.dynamic, GOT)
    put(out, 1, 4)
    put(out, 6, 4)
    put(out, data_off, 8)
    put(out, IMAGE_BASE + data_off, 8)
    put(out, IMAGE_BASE + data_off, 8)
    put(out, data_size, 8)
    put(out, data_size, 8)
    put(out, PAGE, 8)
    # PT_LOAD RW (bss)
    put(out, 1, 4)
    put(out, 6, 4)
    put(out, 0, 8)
    put(out, bss_addr, 8)
    put(out, bss_addr, 8)
    put(out, 0, 8)
    put(out, image.bss_size if image.bss_size != 0 else 8, 8)
    put(out, PAGE, 8)
    # PT_DYNAMIC
    put(out, 2, 4)
    put(out, 6, 4)
    put(out, data_off, 8)
    put(out, IMAGE_BASE + data_off, 8)
    put(out, IMAGE_BASE + data_off, 8)
    put(out, dyn_size, 8)
    put(out, dyn_size, 8)
    put(out, 8, 8)
    align(out, 16)
    for b in a.code:
        append(out, b)
    align(out, 16)
    for b in image.rodata:
        append(out, b)
    for b in t:
        append(out, b)
    while len(out) < data_off:
        append(out, 0)
    for no in lib_name:
        put(out, 1, 8)
        put(out, no, 8)
    for kv in [[4, IMAGE_BASE + hash_off], [5, IMAGE_BASE + dynstr_off], [6, IMAGE_BASE + dynsym_off], [10, len(strtab)], [11, 24], [7, IMAGE_BASE + rela_off], [8, 24 * len(syms)], [9, 24], [24, 0], [30, 8], [0, 0]]:
        put(out, kv[0], 8)
        put(out, kv[1], 8)
    k = 0
    while k < len(syms):
        put(out, 0, 8)
        k += 1
    return out

# ---------------------------------------------------------------------------------------------- AEX
# Format binaire natif d'Alex OS (docs/FORMAT_AEX.md d'Alex OS). En-tête de 64 octets :
#   0 « AEX » 0x1A   4 version (u16 = 1)   6 machine (u16, 1 = x86-64)   8 drapeaux (u32)   12 taille de l'en-tête (64)
#   16 point d'entrée (u64)   24 nombre de segments (u32)   28 décalage de la table des segments (u32)
#   32 décalage du manifeste (u32)   36 taille du manifeste (u32)   40 ABI (u32 = 1)   44 réservé
# Segment (32 octets) : adresse (u64), décalage dans le fichier (u32), taille dans le fichier (u32), taille en
# mémoire (u64), droits (u32 : 1 lecture, 2 écriture, 4 exécution ; jamais 2 et 4 ensemble), réservé (u32).
# Manifeste : texte UTF-8 « clé = valeur » par ligne. Le premier segment couvre le fichier depuis l'octet 0 (en-têtes,
# code, constantes) à l'adresse de base ; le second est la zone à zéro (bss).
const AEX_HDR := 64
const AEX_SEG := 32

func _aex_manifest(path):
    name := path
    k := len(name) - 1
    while k >= 0:
        if _s.substring(name, k, k + 1) == "/":
            name = _s.substring(name, k + 1, len(name))
            break
        k -= 1
    if len(name) > 4 and _s.substring(name, len(name) - 4, len(name)) == ".aex":
        name = _s.substring(name, 0, len(name) - 4)
    return _s.byte_unpack("format = AEX\nversion = 1\nabi = 1\nmachine = x86-64\nnom = " + name + "\n")

func build_aex(image, path):
    if len(image.imports) > 0:
        raise("RuntimeError", "AEX : un exécutable Alex OS n'importe aucune bibliothèque partagée")
    a := image.code
    a.resolve()
    ibase := image.base
    man := _aex_manifest(path)
    man_off := AEX_HDR + 2 * AEX_SEG
    headers := man_off + len(man)
    code_off := (headers + 15) & ~15
    rodata_off := (code_off + len(a.code) + 15) & ~15
    file_size := rodata_off + len(image.rodata)
    bss_addr := (ibase + file_size + PAGE - 1) // PAGE * PAGE + PAGE
    if path != null:
        write_map(image, ibase + code_off, path)
    for r in a.relocs:
        base := ibase + rodata_off if r[1] == S_RODATA else ibase + code_off if r[1] == S_CODE else bss_addr
        addr := base + r[2] + r[3]
        if addr > 0x7FFFFFFF:
            raise("RuntimeError", "AEX : adresse hors de la plage 32 bits")
        i := 0
        while i < 4:
            a.code[r[0] + i] = (addr >> (8 * i)) & 0xFF
            i += 1
    out := [0x41, 0x45, 0x58, 0x1A]
    put(out, 1, 2)
    put(out, 1, 2)
    put(out, 0, 4)
    put(out, AEX_HDR, 4)
    put(out, ibase + code_off + image.entry_offset, 8)
    put(out, 2, 4)
    put(out, AEX_HDR, 4)
    put(out, man_off, 4)
    put(out, len(man), 4)
    put(out, 1, 4)
    put(out, 0, 4)
    put(out, 0, 8)
    put(out, 0, 8)
    # segment 1 : en-têtes, code, constantes (lecture + exécution)
    put(out, ibase, 8)
    put(out, 0, 4)
    put(out, file_size, 4)
    put(out, file_size, 8)
    put(out, 5, 4)
    put(out, 0, 4)
    # segment 2 : zone à zéro (lecture + écriture)
    put(out, bss_addr, 8)
    put(out, 0, 4)
    put(out, 0, 4)
    put(out, image.bss_size if image.bss_size != 0 else 8, 8)
    put(out, 3, 4)
    put(out, 0, 4)
    for b in man:
        append(out, b)
    align(out, 16)
    for b in a.code:
        append(out, b)
    align(out, 16)
    for b in image.rodata:
        append(out, b)
    return out

func write_aex(image, path):
    _io.write_bytes(path, build_aex(image, path))
    try:
        _os.chmod(path, 0o755)
    catch e:
        pass_ := 0

func write_elf(image, path):
    out := build_elf(image, path)
    _io.write_bytes(path, out)
    try:
        _os.chmod(path, 0o755)
    catch e:
        pass_ := 0

# ---------------------------------------------------------------------------------------------- Multiboot
# Sans OS : image binaire chargée à 1 Mio par un chargeur Multiboot (GRUB, `qemu -kernel`). En tête : en-tête
# Multiboot 1, puis un amorçage 32 bits qui construit les tables de pages (1 Gio identité en pages de 2 Mio, et la
# fenêtre des périphériques PML4[1] : adresse virtuelle MMIO_BASE + p -> physique p < 4 Gio, sans cache), active
# SSE et le mode long, charge une GDT 64 bits et saute au point d'entrée 64 bits (entry_offset).
const KERNEL_BASE := 0x100000
const BOOT_TABLE_PAGES := 8
const MMIO_BASE := 0x8000000000
# Page de démarrage des autres cœurs (copiée en 0x8000, vecteur SIPI 0x08) : données cr3, entrée, bloc du cœur.
const AP_CR3 := 0x130
const AP_ENTRY := 0x138
const AP_BLOCK := 0x140

func _put32(c, v):
    put(c, v & 0xFFFFFFFF, 4)

func _add(c, bs):
    for b in bs:
        append(c, b)

# Amorçage 32 bits ; adresses absolues : m = infos Multiboot, t = tables de pages, g = descripteur de GDT,
# e = point d'entrée 64 bits.
func boot32(m, t, g, e):
    c := []
    _add(c, [0xFA])
    _add(c, [0x89, 0x1D])
    _put32(c, m)
    _add(c, [0xBF])
    _put32(c, t)
    _add(c, [0x31, 0xC0])
    _add(c, [0xB9])
    _put32(c, BOOT_TABLE_PAGES * 4096 // 4)
    _add(c, [0xF3, 0xAB])
    _add(c, [0xC7, 0x05])
    _put32(c, t)
    _put32(c, (t + 4096) | 3)
    _add(c, [0xC7, 0x05])
    _put32(c, t + 4096)
    _put32(c, (t + 8192) | 3)
    _add(c, [0xC7, 0x05])
    _put32(c, t + 8)
    _put32(c, (t + 12288) | 3)
    k := 0
    while k < 4:
        _add(c, [0xC7, 0x05])
        _put32(c, t + 12288 + 8 * k)
        _put32(c, (t + 16384 + 4096 * k) | 3)
        k += 1
    _add(c, [0xBF])
    _put32(c, t + 8192)
    _add(c, [0xB8])
    _put32(c, 0x83)
    _add(c, [0xB9])
    _put32(c, 512)
    _add(c, [0x89, 0x07])
    _add(c, [0x05])
    _put32(c, 0x200000)
    _add(c, [0x83, 0xC7, 0x08])
    _add(c, [0xE2, 0xF4])
    _add(c, [0xBF])
    _put32(c, t + 16384)
    _add(c, [0xB8])
    _put32(c, 0x9B)
    _add(c, [0xB9])
    _put32(c, 2048)
    _add(c, [0x89, 0x07])
    _add(c, [0x05])
    _put32(c, 0x200000)
    _add(c, [0x83, 0xC7, 0x08])
    _add(c, [0xE2, 0xF4])
    _add(c, [0xB8])
    _put32(c, t)
    _add(c, [0x0F, 0x22, 0xD8])
    _add(c, [0x0F, 0x20, 0xE0])
    _add(c, [0x0D])
    _put32(c, 0x620)
    _add(c, [0x0F, 0x22, 0xE0])
    _add(c, [0xB9])
    _put32(c, 0xC0000080)
    _add(c, [0x0F, 0x32])
    _add(c, [0x0D])
    _put32(c, 0x100)
    _add(c, [0x0F, 0x30])
    _add(c, [0x0F, 0x20, 0xC0])
    _add(c, [0x25])
    _put32(c, 0xFFFFFFFB)
    _add(c, [0x0D])
    _put32(c, 0x80000003)
    _add(c, [0x0F, 0x22, 0xC0])
    _add(c, [0x0F, 0x01, 0x15])
    _put32(c, g)
    _add(c, [0xEA])
    _put32(c, e)
    put(c, 0x08, 2)
    return c

# Page de démarrage des autres cœurs, chargée en 0x8000 : mode réel -> protégé -> long (cr3 donné), puis saut au
# point d'entrée 64 bits du noyau, bloc du cœur dans rdi.
func ap_trampoline():
    base := 0x8000
    k_gdt := 0x100
    k_gdtr := 0x120
    c := []
    _add(c, [0xFA, 0x31, 0xC0, 0x8E, 0xD8])
    _add(c, [0x0F, 0x01, 0x16])
    put(c, base + k_gdtr, 2)
    _add(c, [0x0F, 0x20, 0xC0, 0x66, 0x83, 0xC8, 0x01, 0x0F, 0x22, 0xC0])
    far32 := len(c) + 2
    _add(c, [0x66, 0xEA])
    _put32(c, 0)
    put(c, 0x08, 2)
    pm32 := len(c)
    _add(c, [0x66, 0xB8, 0x10, 0x00, 0x8E, 0xD8, 0x8E, 0xC0, 0x8E, 0xD0])
    _add(c, [0x0F, 0x20, 0xE0, 0x0D])
    _put32(c, 0x620)
    _add(c, [0x0F, 0x22, 0xE0])
    _add(c, [0xA1])
    _put32(c, base + AP_CR3)
    _add(c, [0x0F, 0x22, 0xD8])
    _add(c, [0xB9])
    _put32(c, 0xC0000080)
    _add(c, [0x0F, 0x32, 0x0D])
    _put32(c, 0x100)
    _add(c, [0x0F, 0x30])
    _add(c, [0x0F, 0x20, 0xC0, 0x25])
    _put32(c, 0xFFFFFFFB)
    _add(c, [0x0D])
    _put32(c, 0x80000003)
    _add(c, [0x0F, 0x22, 0xC0])
    far64 := len(c) + 1
    _add(c, [0xEA])
    _put32(c, 0)
    put(c, 0x18, 2)
    lm64 := len(c)
    _add(c, [0x48, 0x8B, 0x3C, 0x25])
    _put32(c, base + AP_BLOCK)
    _add(c, [0x48, 0x8B, 0x04, 0x25])
    _put32(c, base + AP_ENTRY)
    _add(c, [0xFF, 0xE0])
    i := 0
    while i < 4:
        c[far32 + i] = ((base + pm32) >> (8 * i)) & 0xFF
        c[far64 + i] = ((base + lm64) >> (8 * i)) & 0xFF
        i += 1
    if len(c) > k_gdt:
        raise("RuntimeError", "page de démarrage des cœurs trop longue")
    while len(c) < k_gdt:
        append(c, 0xCC)
    put(c, 0, 8)
    put(c, 0x00CF9A000000FFFF, 8)
    put(c, 0x00CF92000000FFFF, 8)
    put(c, 0x00AF9A000000FFFF, 8)
    put(c, 31, 2)
    _put32(c, base + k_gdt)
    while len(c) < AP_BLOCK + 8:
        append(c, 0)
    return c

# Image Multiboot (liste d'octets) ; mb_info / tables : décalages dans le bss (informations Multiboot écrites par
# l'amorçage, tables de pages alignées sur 4 Kio).
func build_multiboot(image, mb_info, tables, path=null):
    a := image.code
    a.resolve()
    stub_off := 40
    stub_size := len(boot32(0, 0, 0, 0))
    gdt_off := (stub_off + stub_size + 7) & ~7
    gdtr_off := gdt_off + 24
    code_off := (gdtr_off + 6 + 15) & ~15
    rodata_off := (code_off + len(a.code) + 4095) & ~4095
    file_size := rodata_off + len(image.rodata)
    bss_addr := (KERNEL_BASE + file_size + PAGE - 1) // PAGE * PAGE
    bss_end := bss_addr + image.bss_size
    if bss_end > 0x40000000:
        raise("RuntimeError", "image sans OS : plus de 1 Gio")
    if path != null:
        write_map(image, KERNEL_BASE + code_off, path)
    for r in a.relocs:
        base := KERNEL_BASE + rodata_off if r[1] == S_RODATA else KERNEL_BASE + code_off if r[1] == S_CODE else bss_addr
        addr := base + r[2] + r[3]
        i := 0
        while i < 4:
            a.code[r[0] + i] = (addr >> (8 * i)) & 0xFF
            i += 1
    out := []
    magic := 0x1BADB002
    flags := 0x00010002
    _put32(out, magic)
    _put32(out, flags)
    _put32(out, 0 - magic - flags)
    _put32(out, KERNEL_BASE)
    _put32(out, KERNEL_BASE)
    _put32(out, KERNEL_BASE + file_size)
    _put32(out, bss_end)
    _put32(out, KERNEL_BASE + stub_off)
    put(out, KERNEL_BASE + rodata_off, 8)
    _add(out, boot32(bss_addr + mb_info, bss_addr + tables, KERNEL_BASE + gdtr_off, KERNEL_BASE + code_off + image.entry_offset))
    align(out, 8)
    put(out, 0, 8)
    put(out, 0x00AF9A000000FFFF, 8)
    put(out, 0x00CF92000000FFFF, 8)
    put(out, 23, 2)
    _put32(out, KERNEL_BASE + gdt_off)
    align(out, 16)
    _add(out, a.code)
    align(out, 4096)
    _add(out, image.rodata)
    return out

func write_multiboot(image, mb_info, tables, path):
    _io.write_bytes(path, build_multiboot(image, mb_info, tables, path))

# ---------------------------------------------------------------------------------------------- PE32+
# Cible Windows (`windows` non nul) : exécutable console (sous-système 3) ou graphique (2, manifeste en ressource),
# indépendant de la position (code en mode pic, .reloc sans correction). Sections : .text, .rdata, .idata (IAT en
# tête), [.rsrc], .reloc, .bss. Sans `windows` : application UEFI (sous-système 10), .text, .rdata, .bss.
# Ressources (.rsrc) : le manifeste des applications graphiques, l'icône (`icon` : octets d'un fichier .ico).
class PeWindows:
    func init(imports, gui=false, icon=null):
        self.imports = imports   # [[dll, [noms]]]
        self.gui = gui
        self.icon = icon

const RT_ICON := 3
const RT_GROUP_ICON := 14
const RT_MANIFEST := 24
const _LANG := 0x409

func _u16(b, at):
    return b[at] | (b[at + 1] << 8)

func _u32(b, at):
    return _u16(b, at) | (_u16(b, at + 2) << 16)

# Fichier .ico -> ressources [type, id, langue, octets] : une RT_ICON par image (BMP ou PNG, telle quelle) et la
# RT_GROUP_ICON n° 1 qui les décrit (entrées ICONDIRENTRY de 16 octets, le décalage remplacé par le numéro sur 2).
func icon_resources(ico):
    if len(ico) < 6 or _u16(ico, 0) != 0 or _u16(ico, 2) != 1 or _u16(ico, 4) == 0:
        raise("RuntimeError", "icône : fichier .ico invalide")
    n := _u16(ico, 4)
    if len(ico) < 6 + 16 * n:
        raise("RuntimeError", "icône : fichier .ico tronqué")
    out := []
    grp := [0, 0, 1, 0, n & 0xFF, n >> 8]
    k := 0
    while k < n:
        e := 6 + 16 * k
        size := _u32(ico, e + 8)
        off := _u32(ico, e + 12)
        if size == 0 or off + size > len(ico):
            raise("RuntimeError", "icône : image " + str(k + 1) + " hors du fichier .ico")
        append(out, [RT_ICON, k + 1, _LANG, ico[off:off + size]])
        for b in ico[e:e + 12]:
            append(grp, b)
        append(grp, (k + 1) & 0xFF)
        append(grp, (k + 1) >> 8)
        k += 1
    append(out, [RT_GROUP_ICON, 1, _LANG, grp])
    return out

# Section .rsrc à l'adresse `rva` pour des ressources [type, id, langue, octets] (identifiants numériques, une langue
# par ressource), triées par type puis id : répertoire racine (types), un répertoire par type (ids), un par ressource
# (langue), les entrées de données, puis les données (alignées sur 8).
func _rsrc_section(res, rva):
    types := []
    for r in res:
        if not (r[0] in types):
            append(types, r[0])
    by_type := []
    for t in types:
        rs := []
        for r in res:
            if r[0] == t:
                append(rs, r)
        append(by_type, rs)
    n := len(res)
    type_off := 16 + 8 * len(types)
    off := type_off
    type_dir := []
    for rs in by_type:
        append(type_dir, off)
        off += 16 + 8 * len(rs)
    lang_off := off
    entry_off := lang_off + 24 * n
    data_off := entry_off + 16 * n
    out := []
    _rsrc_dir(out, len(types))
    i := 0
    while i < len(types):
        put(out, types[i], 4)
        put(out, 0x80000000 | type_dir[i], 4)
        i += 1
    k := 0
    for rs in by_type:
        _rsrc_dir(out, len(rs))
        for r in rs:
            put(out, r[1], 4)
            put(out, 0x80000000 | (lang_off + 24 * k), 4)
            k += 1
    k = 0
    for rs in by_type:
        for r in rs:
            _rsrc_dir(out, 1)
            put(out, r[2], 4)
            put(out, entry_off + 16 * k, 4)
            k += 1
    d := data_off
    for rs in by_type:
        for r in rs:
            put(out, rva + d, 4)
            put(out, len(r[3]), 4)
            put(out, 0, 4)
            put(out, 0, 4)
            d = _up(d + len(r[3]), 8)
    for rs in by_type:
        for r in rs:
            for b in r[3]:
                append(out, b)
            align(out, 8)
    return out

func _rsrc_dir(out, ids):
    put(out, 0, 4)
    put(out, 0, 4)
    put(out, 0, 4)
    put(out, 0, 2)
    put(out, ids, 2)

const _MANIFEST := "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\r\n<assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\">\r\n  <dependency><dependentAssembly><assemblyIdentity type=\"win32\" name=\"Microsoft.Windows.Common-Controls\" version=\"6.0.0.0\" processorArchitecture=\"*\" publicKeyToken=\"6595b64144ccf1df\" language=\"*\"/></dependentAssembly></dependency>\r\n  <application xmlns=\"urn:schemas-microsoft-com:asm.v3\"><windowsSettings><dpiAware xmlns=\"http://schemas.microsoft.com/SMI/2005/WindowsSettings\">true</dpiAware></windowsSettings></application>\r\n  <compatibility xmlns=\"urn:schemas-microsoft-com:compatibility.v1\"><application><supportedOS Id=\"{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}\"/></application></compatibility>\r\n</assembly>\r\n"

func _up(v, a):
    return (v + a - 1) // a * a

func _set32(buf, at, v):
    i := 0
    while i < 4:
        buf[at + i] = (v >> (8 * i)) & 0xFF
        i += 1

func _pad_to(out, n):
    while len(out) < n:
        append(out, 0)

func _pe_section(out, name, vsize, rva, raw, ptr, flags):
    bs := _s.byte_unpack(name)
    i := 0
    while i < 8:
        append(out, bs[i] if i < len(bs) else 0)
        i += 1
    put(out, vsize, 4)
    put(out, rva, 4)
    put(out, raw, 4)
    put(out, ptr, 4)
    put(out, 0, 4)
    put(out, 0, 4)
    put(out, 0, 2)
    put(out, 0, 2)
    put(out, flags, 4)

# machine : 0x8664 (x86-64) ou 0xAA64 (ARM64) ; code_fn (ARM64) : (rva_rodata, rva_code, rva_import, rva_bss) ->
# octets du code, relocations résolues (le code d'image.code est alors de taille code_size octets).
func build_pe(image, path=null, windows=null, machine=0x8664, code_size=-1, code_fn=null):
    a := image.code
    if code_fn == null:
        a.resolve()
    arm := machine == 0xAA64
    win := windows != null
    what := "Windows" if win else "UEFI"
    SECT := 0x1000
    FILE := 0x200
    headers := 0x400 if win else 0x200
    # .idata
    idata := []
    iat_size := 0
    desc_off := 0
    desc_size := 0
    iat_start := []
    ilt_start := []
    name_off := []
    hint_off := []
    if win:
        dlls := windows.imports
        for d in dlls:
            append(iat_start, iat_size)
            iat_size += 8 * (len(d[1]) + 1)
        desc_off = iat_size
        desc_size = 20 * (len(dlls) + 1)
        off := desc_off + desc_size
        for d in dlls:
            append(ilt_start, off)
            off += 8 * (len(d[1]) + 1)
        _pad_to(idata, off)
        for d in dlls:
            hs := []
            for n in d[1]:
                append(hs, len(idata))
                put(idata, 0, 2)
                for b in _s.byte_unpack(n):
                    append(idata, b)
                append(idata, 0)
                align(idata, 2)
            append(hint_off, hs)
        for d in dlls:
            append(name_off, len(idata))
            for b in _s.byte_unpack(d[0]):
                append(idata, b)
            append(idata, 0)
        align(idata, 8)
    text_rva := SECT
    text_size := len(a.code) if code_fn == null else code_size
    rodata_rva := _up(text_rva + text_size, SECT)
    rodata_size := len(image.rodata) if len(image.rodata) > 1 else 1
    idata_rva := _up(rodata_rva + rodata_size, SECT)
    idata_size := len(idata)
    gui := win and windows.gui
    # ressources triées par type : icônes (3), groupe d'icônes (14), manifeste (24)
    res := []
    if win and windows.icon != null:
        res = icon_resources(windows.icon)
    if gui:
        append(res, [RT_MANIFEST, 1, _LANG, _s.byte_unpack(_MANIFEST)])
    has_rsrc := len(res) > 0
    rsrc_rva := _up(idata_rva + idata_size, SECT) if has_rsrc else 0
    rsrc := _rsrc_section(res, rsrc_rva) if has_rsrc else []
    rsrc_size := len(rsrc)
    reloc_rva := 0
    if win:
        reloc_rva = _up(rsrc_rva + rsrc_size, SECT) if has_rsrc else _up(idata_rva + idata_size, SECT)
    reloc_size := 12 if win else 0
    bss_rva := _up(reloc_rva + reloc_size, SECT) if win else idata_rva
    bss_size := image.bss_size if image.bss_size > 8 else 8
    image_size := _up(bss_rva + bss_size, SECT)
    if image_size > 0x7FFFFFFF:
        raise("RuntimeError", what + " : image de plus de 2 Gio")
    if win:
        dlls := windows.imports
        g := 0
        while g < len(dlls):
            k := 0
            while k < len(dlls[g][1]):
                rva := idata_rva + hint_off[g][k]
                _set32(idata, iat_start[g] + 8 * k, rva)
                _set32(idata, ilt_start[g] + 8 * k, rva)
                k += 1
            d := desc_off + 20 * g
            _set32(idata, d, idata_rva + ilt_start[g])
            _set32(idata, d + 12, idata_rva + name_off[g])
            _set32(idata, d + 16, idata_rva + iat_start[g])
            g += 1
    code_bytes := a.code
    if code_fn != null:
        code_bytes = code_fn(rodata_rva, text_rva, idata_rva if win else -1, bss_rva)
    # relocations relatives à RIP
    for r in (a.relocs if code_fn == null else []):
        if not r[4]:
            raise("RuntimeError", what + " : relocation absolue (le code doit être assemblé en mode pic)")
        sec := r[1]
        if sec == S_IMPORT and not win:
            raise("RuntimeError", "UEFI : pas de table d'import")
        base := rodata_rva if sec == S_RODATA else text_rva if sec == S_CODE else idata_rva if sec == S_IMPORT else bss_rva
        target := base + r[2] + r[3]
        nxt := text_rva + r[0] + 4 + r[5]
        d := (target - nxt) & 0xFFFFFFFF
        i := 0
        while i < 4:
            a.code[r[0] + i] = (d >> (8 * i)) & 0xFF
            i += 1
    image_base := 0x140000000 if win else 0x10000000
    if path != null:
        write_map(image, image_base + text_rva, path)
    text_raw := _up(text_size, FILE)
    rodata_raw := _up(rodata_size, FILE)
    idata_raw := _up(idata_size, FILE)
    reloc_raw := _up(reloc_size, FILE)
    rsrc_raw := _up(rsrc_size, FILE)
    text_ptr := headers
    rodata_ptr := text_ptr + text_raw
    idata_ptr := rodata_ptr + rodata_raw
    rsrc_ptr := idata_ptr + idata_raw
    reloc_ptr := rsrc_ptr + rsrc_raw
    sections := (6 if has_rsrc else 5) if win else 3
    out := []
    put(out, 0x5A4D, 2)
    _pad_to(out, 0x3C)
    put(out, 0x40, 4)
    put(out, 0x00004550, 4)
    put(out, machine, 2)
    put(out, sections, 2)
    put(out, 0, 4)
    put(out, 0, 4)
    put(out, 0, 4)
    put(out, 240, 2)
    put(out, 0x0022, 2)
    put(out, 0x20B, 2)
    put(out, 0, 2)
    put(out, text_raw, 4)
    put(out, rodata_raw + idata_raw + rsrc_raw + reloc_raw, 4)
    put(out, _up(bss_size, FILE), 4)
    put(out, text_rva + image.entry_offset, 4)
    put(out, text_rva, 4)
    put(out, image_base, 8)
    put(out, SECT, 4)
    put(out, FILE, 4)
    if win:
        put(out, 10 if arm else 6, 2)
        put(out, 0, 2)
        put(out, 0, 4)
        put(out, 10 if arm else 6, 2)
        put(out, 0, 2)
    else:
        put(out, 0, 8)
        put(out, 0, 4)
    put(out, 0, 4)
    put(out, image_size, 4)
    put(out, headers, 4)
    put(out, 0, 4)
    put(out, 2 if gui else 3 if win else 10, 2)
    put(out, 0x8160 if win else 0x0160, 2)
    put(out, 0x100000, 8)
    put(out, 0x1000, 8)
    put(out, 0x100000, 8)
    put(out, 0x1000, 8)
    put(out, 0, 4)
    put(out, 16, 4)
    i := 0
    while i < 16:
        if win and i == 1:
            put(out, idata_rva + desc_off, 4)
            put(out, desc_size, 4)
        elif has_rsrc and i == 2:
            put(out, rsrc_rva, 4)
            put(out, rsrc_size, 4)
        elif win and i == 5:
            put(out, reloc_rva, 4)
            put(out, reloc_size, 4)
        elif win and i == 12:
            put(out, idata_rva, 4)
            put(out, iat_size, 4)
        else:
            put(out, 0, 8)
        i += 1
    _pe_section(out, ".text", text_size, text_rva, text_raw, text_ptr, 0x60000020)
    _pe_section(out, ".rdata", rodata_size, rodata_rva, rodata_raw, rodata_ptr, 0x40000040)
    if win:
        _pe_section(out, ".idata", idata_size, idata_rva, idata_raw, idata_ptr, 0xC0000040)
        if has_rsrc:
            _pe_section(out, ".rsrc", rsrc_size, rsrc_rva, rsrc_raw, rsrc_ptr, 0x40000040)
        _pe_section(out, ".reloc", reloc_size, reloc_rva, reloc_raw, reloc_ptr, 0x42000040)
    _pe_section(out, ".bss", bss_size, bss_rva, 0, 0, 0xC0000080)
    if len(out) > headers:
        raise("RuntimeError", what + " : en-têtes trop grands")
    _pad_to(out, headers)
    for b in code_bytes:
        append(out, b)
    _pad_to(out, rodata_ptr)
    for b in image.rodata:
        append(out, b)
    _pad_to(out, rodata_ptr + rodata_raw)
    if win:
        for b in idata:
            append(out, b)
        _pad_to(out, idata_ptr + idata_raw)
        for b in rsrc:
            append(out, b)
        _pad_to(out, rsrc_ptr + rsrc_raw)
        put(out, text_rva, 4)
        put(out, 12, 4)
        put(out, 0, 2)
        put(out, 0, 2)
        _pad_to(out, reloc_ptr + reloc_raw)
    return out

func write_pe(image, path, windows=null):
    _io.write_bytes(path, build_pe(image, path, windows))

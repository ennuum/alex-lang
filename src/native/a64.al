# ALEX — native.a64
#
# Assembleur AArch64 (A64) du compilateur natif écrit en ALEX : encode directement les instructions utilisées par
# le générateur ARM64 (native.codegen_a64). Instructions de 32 bits, petit-boutistes. Écrit aussi
# l'exécutable : ELF64 statique Linux (EM_AARCH64) ou PE32+ Windows ARM64 (machine 0xAA64, via native.x64).
#
# Registres : X0..X30 ; le numéro 31 vaut SP ou XZR selon l'instruction (SP pour les bases d'adresse et
# ADD/SUB immédiats, XZR ailleurs). x16 / x17 (IP0 / IP1) sont réservés à l'assembleur (grands immédiats,
# adresses de données, décalages hors limites).
#
#   use native.a64 as a64
#   a := a64.Asm()
#   a.mov_imm(a64.X0, 0)
#   a.mov_imm(a64.X8, 93)
#   a.svc()
#   a64.write_elf_a64(a64.A64Image(a, [], 8, 0), "sortie")
#
# Erreurs : RuntimeError (étiquette non liée, branchement ou ADRP hors de portée, décalage non aligné).

from core use len, type
from collections use append
use io as _io
use os as _os
use string as _s
use native.x64 as _x

const X0 := 0
const X1 := 1
const X2 := 2
const X3 := 3
const X4 := 4
const X5 := 5
const X6 := 6
const X7 := 7
const X8 := 8
const X9 := 9
const X10 := 10
const X11 := 11
const X12 := 12
const X13 := 13
const X14 := 14
const X15 := 15
const X16 := 16
const X17 := 17
const X18 := 18
const X19 := 19
const X20 := 20
const X21 := 21
const X22 := 22
const X23 := 23
const X24 := 24
const X25 := 25
const X26 := 26
const X27 := 27
const X28 := 28
const X29 := 29
const X30 := 30
const SP := 31
const XZR := 31
const FP := 29
const LR := 30
const IP0 := 16
const IP1 := 17

# Conditions (champ cond des B.cond / CSEL / CSET).
const EQ := 0
const NE := 1
const HS := 2
const LO := 3
const MI := 4
const PL := 5
const VS := 6
const VC := 7
const HI := 8
const LS := 9
const GE := 10
const LT := 11
const GT := 12
const LE := 13
const AL := 14

func invert(c):
    return c ^ 1

# Registres système (MRS / MSR).
func sysreg(op0, op1, crn, crm, op2):
    return ((op0 & 1) << 14) | (op1 << 11) | (crn << 7) | (crm << 3) | op2

SYS_DAIF := sysreg(3, 3, 4, 2, 1)
SYS_CURRENT_EL := sysreg(3, 0, 4, 2, 2)
SYS_SPSEL := sysreg(3, 0, 4, 2, 0)
SYS_FAR_EL1 := sysreg(3, 0, 6, 0, 0)
SYS_ESR_EL1 := sysreg(3, 0, 5, 2, 0)
SYS_ELR_EL1 := sysreg(3, 0, 4, 0, 1)
SYS_SPSR_EL1 := sysreg(3, 0, 4, 0, 0)
SYS_VBAR_EL1 := sysreg(3, 0, 12, 0, 0)
SYS_SCTLR_EL1 := sysreg(3, 0, 1, 0, 0)
SYS_CPACR_EL1 := sysreg(3, 0, 1, 0, 2)
SYS_TTBR0_EL1 := sysreg(3, 0, 2, 0, 0)
SYS_TCR_EL1 := sysreg(3, 0, 2, 0, 2)
SYS_MAIR_EL1 := sysreg(3, 0, 10, 2, 0)
SYS_HCR_EL2 := sysreg(3, 4, 1, 1, 0)
SYS_SPSR_EL2 := sysreg(3, 4, 4, 0, 0)
SYS_ELR_EL2 := sysreg(3, 4, 4, 0, 1)
SYS_SP_EL1 := sysreg(3, 4, 4, 1, 0)
SYS_CNTHCTL_EL2 := sysreg(3, 4, 14, 1, 0)
SYS_CNTVOFF_EL2 := sysreg(3, 4, 14, 0, 3)
SYS_CNTFRQ_EL0 := sysreg(3, 3, 14, 0, 0)
SYS_CNTVCT_EL0 := sysreg(3, 3, 14, 0, 2)

# Sections (mêmes numéros que native.x64).
const S_RODATA := 0
const S_BSS := 1
const S_CODE := 2
const S_IMPORT := 3

# Relocations : [indice du mot, genre, section, décalage, ajout].
const REL_ADRP := 0
const REL_ADD_LO12 := 1
const REL_LDST64_LO12 := 2

const M32 := 0xFFFFFFFF

func _r(r):
    return r & 31

class Asm:
    func init():
        self.code = []
        self.relocs = []
        self.labels = []
        self.fixups = []         # [indice du mot, étiquette, genre : 0 imm26, 1 imm19]
        self.label_relocs = []   # [indice de la relocation, étiquette]

    func new_label():
        append(self.labels, -1)
        return len(self.labels) - 1

    func bind(l):
        self.labels[l] = self.size()

    func is_bound(l):
        return self.labels[l] >= 0

    func size():
        return 4 * len(self.code)

    func word(w):
        append(self.code, w & M32)

    func resolve():
        for f in self.fixups:
            target := self.labels[f[1]]
            if target < 0:
                raise("RuntimeError", "assembleur A64 : label non lié")
            delta := (target - 4 * f[0]) // 4
            if f[2] == 0:
                if delta < -(1 << 25) or delta >= (1 << 25):
                    raise("RuntimeError", "assembleur A64 : branchement hors de portée (128 Mio)")
                self.code[f[0]] = self.code[f[0]] | (delta & 0x3FFFFFF)
            else:
                if delta < -(1 << 18) or delta >= (1 << 18):
                    raise("RuntimeError", "assembleur A64 : branchement conditionnel hors de portée (1 Mio)")
                self.code[f[0]] = self.code[f[0]] | ((delta & 0x7FFFF) << 5)
        self.fixups = []
        for lr in self.label_relocs:
            target := self.labels[lr[1]]
            if target < 0:
                raise("RuntimeError", "assembleur A64 : label non lié")
            self.relocs[lr[0]][3] = target
        self.label_relocs = []

    # ---- données ----
    # Suite MOVZ / MOVN / MOVK minimale.
    func mov_imm(rd, v):
        x := v
        zeros := 0
        ffff := 0
        i := 0
        while i < 4:
            h := (x >> (16 * i)) & 0xFFFF
            if h == 0:
                zeros += 1
            if h == 0xFFFF:
                ffff += 1
            i += 1
        inverted := ffff > zeros
        skip := 0xFFFF if inverted else 0
        first := true
        i = 0
        while i < 4:
            h := (x >> (16 * i)) & 0xFFFF
            if h != skip:
                if first:
                    imm := ((~h) & 0xFFFF) if inverted else h
                    self.word((0x92800000 if inverted else 0xD2800000) | (i << 21) | (imm << 5) | _r(rd))
                    first = false
                else:
                    self.word(0xF2800000 | (i << 21) | (h << 5) | _r(rd))
            i += 1
        if first:
            self.word((0x92800000 if inverted else 0xD2800000) | _r(rd))

    # Registres généraux (ORR) ; avec SP : ADD #0.
    func mov(rd, rn):
        if rd == rn:
            return
        if rd == SP or rn == SP:
            self.word(0x91000000 | (_r(rn) << 5) | _r(rd))
        else:
            self.word(0xAA0003E0 | (_r(rn) << 16) | _r(rd))

    # rd = rn + imm (SP accepté), imm quelconque (via x16).
    func add_imm(rd, rn, imm):
        if imm >= 0 and imm < 4096:
            self.word(0x91000000 | (imm << 10) | (_r(rn) << 5) | _r(rd))
        elif imm < 0 and imm > -4096:
            self.word(0xD1000000 | ((-imm) << 10) | (_r(rn) << 5) | _r(rd))
        elif imm > 0 and imm < (4096 << 12) and (imm & 4095) == 0:
            self.word(0x91400000 | ((imm >> 12) << 10) | (_r(rn) << 5) | _r(rd))
        elif imm < 0 and imm > -(4096 << 12) and ((-imm) & 4095) == 0:
            self.word(0xD1400000 | (((-imm) >> 12) << 10) | (_r(rn) << 5) | _r(rd))
        else:
            t := IP1 if rn == IP0 else IP0
            self.mov_imm(t, imm)
            self.word(0x8B206000 | (_r(t) << 16) | (_r(rn) << 5) | _r(rd))

    func sub_imm(rd, rn, imm):
        self.add_imm(rd, rn, -imm)

    func add(rd, rn, rm, lsl=0):
        self.word(0x8B000000 | (_r(rm) << 16) | (lsl << 10) | (_r(rn) << 5) | _r(rd))

    func sub(rd, rn, rm, lsl=0):
        self.word(0xCB000000 | (_r(rm) << 16) | (lsl << 10) | (_r(rn) << 5) | _r(rd))

    # SUB (registre étendu, UXTX) : rd / rn peuvent être SP.
    func sub_sp(rd, rn, rm):
        self.word(0xCB206000 | (_r(rm) << 16) | (_r(rn) << 5) | _r(rd))

    func adds(rd, rn, rm):
        self.word(0xAB000000 | (_r(rm) << 16) | (_r(rn) << 5) | _r(rd))

    func subs(rd, rn, rm):
        self.word(0xEB000000 | (_r(rm) << 16) | (_r(rn) << 5) | _r(rd))

    func cmp(rn, rm):
        self.subs(XZR, rn, rm)

    # CMP / CMN #imm12, sinon via x16.
    func cmp_imm(rn, imm):
        if imm >= 0 and imm < 4096:
            self.word(0xF100001F | (imm << 10) | (_r(rn) << 5))
        elif imm < 0 and imm > -4096:
            self.word(0xB100001F | ((-imm) << 10) | (_r(rn) << 5))
        else:
            t := IP1 if rn == IP0 else IP0
            self.mov_imm(t, imm)
            self.cmp(rn, t)

    func logical(opc, inv, rd, rn, rm):
        self.word(0x8A000000 | (opc << 29) | ((1 << 21) if inv else 0) | (_r(rm) << 16) | (_r(rn) << 5) | _r(rd))

    func tst(rn, rm):
        self.logical(3, false, XZR, rn, rm)

    func and_(rd, rn, rm):
        self.logical(0, false, rd, rn, rm)

    func orr(rd, rn, rm):
        self.logical(1, false, rd, rn, rm)

    func eor(rd, rn, rm):
        self.logical(2, false, rd, rn, rm)

    func mvn(rd, rm):
        self.logical(1, true, rd, XZR, rm)

    func neg(rd, rm):
        self.sub(rd, XZR, rm)

    func mul(rd, rn, rm):
        self.word(0x9B000000 | (_r(rm) << 16) | (31 << 10) | (_r(rn) << 5) | _r(rd))

    # rd = ra - rn * rm
    func msub(rd, rn, rm, ra):
        self.word(0x9B008000 | (_r(rm) << 16) | (_r(ra) << 10) | (_r(rn) << 5) | _r(rd))

    func dp2(opcode, rd, rn, rm):
        self.word(0x9AC00000 | (_r(rm) << 16) | (opcode << 10) | (_r(rn) << 5) | _r(rd))

    func sdiv(rd, rn, rm):
        self.dp2(3, rd, rn, rm)

    func udiv(rd, rn, rm):
        self.dp2(2, rd, rn, rm)

    func lslv(rd, rn, rm):
        self.dp2(8, rd, rn, rm)

    func lsrv(rd, rn, rm):
        self.dp2(9, rd, rn, rm)

    func asrv(rd, rn, rm):
        self.dp2(10, rd, rn, rm)

    func lsl_imm(rd, rn, sh):
        sh = sh & 63
        self.word(0xD3400000 | (((64 - sh) & 63) << 16) | ((63 - sh) << 10) | (_r(rn) << 5) | _r(rd))

    func lsr_imm(rd, rn, sh):
        self.word(0xD3400000 | ((sh & 63) << 16) | (63 << 10) | (_r(rn) << 5) | _r(rd))

    func asr_imm(rd, rn, sh):
        self.word(0x93400000 | ((sh & 63) << 16) | (63 << 10) | (_r(rn) << 5) | _r(rd))

    # CSINC rd, xzr, xzr, !c
    func cset(rd, c):
        self.word(0x9A9F07E0 | (invert(c) << 12) | _r(rd))

    func csel(rd, rn, rm, c):
        self.word(0x9A800000 | (_r(rm) << 16) | (c << 12) | (_r(rn) << 5) | _r(rd))

    # ---- mémoire : [rn + off] 64 / 32 / 16 / 8 bits (zéro-étendus) ; tout décalage (via x16 si besoin) ----
    func ldst(size, opc, rt, rn, off):
        unit := 1 << size
        if off >= 0 and off % unit == 0 and off // unit < 4096:
            self.word((size << 30) | 0x39000000 | (opc << 22) | ((off // unit) << 10) | (_r(rn) << 5) | _r(rt))
        elif off >= -256 and off <= 255:
            self.word((size << 30) | 0x38000000 | (opc << 22) | ((off & 0x1FF) << 12) | (_r(rn) << 5) | _r(rt))
        else:
            t := IP1 if rn == IP0 or rt == IP0 else IP0
            self.add_imm(t, rn, off)
            self.word((size << 30) | 0x39000000 | (opc << 22) | (_r(t) << 5) | _r(rt))

    func ldr(rt, rn, off=0):
        self.ldst(3, 1, rt, rn, off)

    func strx(rt, rn, off=0):
        self.ldst(3, 0, rt, rn, off)

    func ldrw(rt, rn, off=0):
        self.ldst(2, 1, rt, rn, off)

    func strw(rt, rn, off=0):
        self.ldst(2, 0, rt, rn, off)

    func ldrh(rt, rn, off=0):
        self.ldst(1, 1, rt, rn, off)

    func strh(rt, rn, off=0):
        self.ldst(1, 0, rt, rn, off)

    func ldrb(rt, rn, off=0):
        self.ldst(0, 1, rt, rn, off)

    func strb(rt, rn, off=0):
        self.ldst(0, 0, rt, rn, off)

    # [rn + rm << 3]
    func ldr_idx(rt, rn, rm):
        self.word(0xF8607800 | (_r(rm) << 16) | (_r(rn) << 5) | _r(rt))

    func str_idx(rt, rn, rm):
        self.word(0xF8207800 | (_r(rm) << 16) | (_r(rn) << 5) | _r(rt))

    # [rn + rm]
    func ldrb_idx(rt, rn, rm):
        self.word(0x38606800 | (_r(rm) << 16) | (_r(rn) << 5) | _r(rt))

    # STP a, b, [rn, #off]!
    func stp_pre(a, b, rn, off):
        self.word(0xA9800000 | _imm7(off) | (_r(b) << 10) | (_r(rn) << 5) | _r(a))

    # LDP a, b, [rn], #off
    func ldp_post(a, b, rn, off):
        self.word(0xA8C00000 | _imm7(off) | (_r(b) << 10) | (_r(rn) << 5) | _r(a))

    func stp(a, b, rn, off):
        self.word(0xA9000000 | _imm7(off) | (_r(b) << 10) | (_r(rn) << 5) | _r(a))

    func ldp(a, b, rn, off):
        self.word(0xA9400000 | _imm7(off) | (_r(b) << 10) | (_r(rn) << 5) | _r(a))

    func ldaxr(rt, rn):
        self.word(0xC85FFC00 | (_r(rn) << 5) | _r(rt))

    # rs = 0 si réussi
    func stlxr(rs, rt, rn):
        self.word(0xC800FC00 | (_r(rs) << 16) | (_r(rn) << 5) | _r(rt))

    # ---- adresses ----
    # ADRP + ADD
    func adr_data(rd, s, off, addend=0):
        append(self.relocs, [len(self.code), REL_ADRP, s, off, addend])
        self.word(0x90000000 | _r(rd))
        append(self.relocs, [len(self.code), REL_ADD_LO12, s, off, addend])
        self.word(0x91000000 | (_r(rd) << 5) | _r(rd))

    # ADRP + ADD vers une étiquette du code
    func adr_label(rd, l):
        append(self.label_relocs, [len(self.relocs), l])
        append(self.relocs, [len(self.code), REL_ADRP, S_CODE, 0, 0])
        self.word(0x90000000 | _r(rd))
        append(self.label_relocs, [len(self.relocs), l])
        append(self.relocs, [len(self.code), REL_ADD_LO12, S_CODE, 0, 0])
        self.word(0x91000000 | (_r(rd) << 5) | _r(rd))

    # ADRP x16 + LDR rt, [x16, lo12] (8 octets)
    func ldr_data(rt, s, off):
        if off % 8 != 0:
            raise("RuntimeError", "assembleur A64 : donnée 64 bits non alignée")
        append(self.relocs, [len(self.code), REL_ADRP, s, off, 0])
        self.word(0x90000000 | _r(IP0))
        append(self.relocs, [len(self.code), REL_LDST64_LO12, s, off, 0])
        self.word(0xF9400000 | (_r(IP0) << 5) | _r(rt))

    # ADRP x16 + STR (rt != x16)
    func str_data(rt, s, off):
        if off % 8 != 0:
            raise("RuntimeError", "assembleur A64 : donnée 64 bits non alignée")
        if rt == IP0:
            raise("RuntimeError", "assembleur A64 : strData depuis x16")
        append(self.relocs, [len(self.code), REL_ADRP, s, off, 0])
        self.word(0x90000000 | _r(IP0))
        append(self.relocs, [len(self.code), REL_LDST64_LO12, s, off, 0])
        self.word(0xF9000000 | (_r(IP0) << 5) | _r(rt))

    # ---- branchements ----
    func b(l):
        append(self.fixups, [len(self.code), l, 0])
        self.word(0x14000000)

    func bl(l):
        append(self.fixups, [len(self.code), l, 0])
        self.word(0x94000000)

    func bcond(c, l):
        append(self.fixups, [len(self.code), l, 1])
        self.word(0x54000000 | c)

    func cbz(rt, l):
        append(self.fixups, [len(self.code), l, 1])
        self.word(0xB4000000 | _r(rt))

    func cbnz(rt, l):
        append(self.fixups, [len(self.code), l, 1])
        self.word(0xB5000000 | _r(rt))

    func br(rn):
        self.word(0xD61F0000 | (_r(rn) << 5))

    func blr(rn):
        self.word(0xD63F0000 | (_r(rn) << 5))

    func ret():
        self.word(0xD65F03C0)

    func svc():
        self.word(0xD4000001)

    func brk(imm):
        self.word(0xD4200000 | ((imm & 0xFFFF) << 5))

    # DMB ISH
    func dmb():
        self.word(0xD5033BBF)

    # ---- système (UEFI et sans OS) : registre (op0, op1, CRn, CRm, op2) dans le champ de 15 bits de MRS / MSR ----
    func mrs(rt, sysreg):
        self.word(0xD5300000 | (sysreg << 5) | _r(rt))

    func msr(sysreg, rt):
        self.word(0xD5100000 | (sysreg << 5) | _r(rt))

    func daif_set(imm):
        self.word(0xD50340DF | ((imm & 15) << 8))

    func daif_clr(imm):
        self.word(0xD50340FF | ((imm & 15) << 8))

    func wfi():
        self.word(0xD503207F)

    func yield_():
        self.word(0xD503203F)

    func isb():
        self.word(0xD5033FDF)

    func dsb_sy():
        self.word(0xD5033F9F)

    func tlbi_vmalle1():
        self.word(0xD508871F)

    func eret():
        self.word(0xD69F03E0)

    func hlt(imm):
        self.word(0xD4400000 | ((imm & 0xFFFF) << 5))

    func hvc(imm):
        self.word(0xD4000002 | ((imm & 0xFFFF) << 5))

    func smc(imm):
        self.word(0xD4000003 | ((imm & 0xFFFF) << 5))

    # ---- flottants (registres d0..d31) ----
    # FMOV Dd, Xn
    func fmov_to_d(d, xn):
        self.word(0x9E670000 | (_r(xn) << 5) | (d & 31))

    # FMOV Xd, Dn
    func fmov_from_d(xd, d):
        self.word(0x9E660000 | ((d & 31) << 5) | _r(xd))

    func fadd(d, n, m):
        self.word(0x1E602800 | ((m & 31) << 16) | ((n & 31) << 5) | (d & 31))

    func fsub(d, n, m):
        self.word(0x1E603800 | ((m & 31) << 16) | ((n & 31) << 5) | (d & 31))

    func fmul(d, n, m):
        self.word(0x1E600800 | ((m & 31) << 16) | ((n & 31) << 5) | (d & 31))

    func fdiv(d, n, m):
        self.word(0x1E601800 | ((m & 31) << 16) | ((n & 31) << 5) | (d & 31))

    func fsqrt(d, n):
        self.word(0x1E61C000 | ((n & 31) << 5) | (d & 31))

    func fcmp(n, m):
        self.word(0x1E602000 | ((m & 31) << 16) | ((n & 31) << 5))

    func scvtf(d, xn):
        self.word(0x9E620000 | (_r(xn) << 5) | (d & 31))

    func fcvtzs(xd, n):
        self.word(0x9E780000 | ((n & 31) << 5) | _r(xd))

func _imm7(off):
    if off % 8 != 0 or off < -512 or off > 504:
        raise("RuntimeError", "assembleur A64 : décalage de paire hors limites")
    return ((off // 8) & 0x7F) << 15

# ---------------------------------------------------------------------------------------------- image
# Exécutable AArch64 : code (assembleur Asm), données en lecture seule, taille du bss, entrée (octets dans le
# code), carte des symboles éventuelle ([début, fin, nom]).
class A64Image:
    func init(code, rodata, bss_size, entry_offset):
        self.code = code
        self.rodata = rodata
        self.bss_size = bss_size
        self.entry_offset = entry_offset
        self.symbols = []
        self.imports = []

# Relocations : `bases` = [rodata, bss, code, import] (adresses ou RVA de chaque section), `code_base` celle du
# code. ADRP : écart de pages de 4 Kio (±4 Gio) ; ADD : 12 bits bas ; LDR/STR 64 bits : 12 bits bas / 8.
func relocate(a, bases, code_base):
    for r in a.relocs:
        target := bases[r[2]] + r[3] + r[4]
        pc := code_base + 4 * r[0]
        w := a.code[r[0]]
        if r[1] == REL_ADRP:
            pages := (target >> 12) - (pc >> 12)
            if pages < -(1 << 20) or pages >= (1 << 20):
                raise("RuntimeError", "AArch64 : ADRP hors de portée")
            imm := pages & 0x1FFFFF
            w = w | ((imm & 3) << 29) | ((imm >> 2) << 5)
        elif r[1] == REL_ADD_LO12:
            w = w | ((target & 0xFFF) << 10)
        else:
            if (target & 7) != 0:
                raise("RuntimeError", "AArch64 : donnée 64 bits non alignée")
            w = w | (((target & 0xFFF) >> 3) << 10)
        a.code[r[0]] = w & M32

func _code_bytes(a):
    out := []
    for w in a.code:
        _x.put(out, w, 4)
    return out

const ELF_ALIGN := 0x10000

# AArch64 (Linux) : ELF64 statique, EM_AARCH64. Segment R+X (en-têtes, code, données en lecture seule) à 1 Gio,
# bss RW 64 Kio plus loin ; segments alignés sur 64 Kio (noyaux à pages de 4, 16 ou 64 Kio).
func build_elf_a64(image, path=null):
    a := image.code
    a.resolve()
    headers := _x.EHDR_SIZE + 2 * _x.PHDR_SIZE
    code_off := (headers + 15) & ~15
    code_bytes := a.size()
    rodata_off := (code_off + code_bytes + 15) & ~15
    file_size := rodata_off + len(image.rodata)
    base := _x.IMAGE_BASE
    bss_addr := (base + file_size + ELF_ALIGN - 1) // ELF_ALIGN * ELF_ALIGN + ELF_ALIGN
    if path != null:
        _x.write_map(image, base + code_off, path)
    relocate(a, [base + rodata_off, bss_addr, base + code_off, bss_addr], base + code_off)
    out := [0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    put := _x.put
    put(out, 2, 2)
    put(out, 183, 2)
    put(out, 1, 4)
    put(out, base + code_off + image.entry_offset, 8)
    put(out, _x.EHDR_SIZE, 8)
    put(out, 0, 8)
    put(out, 0, 4)
    put(out, _x.EHDR_SIZE, 2)
    put(out, _x.PHDR_SIZE, 2)
    put(out, 2, 2)
    put(out, 64, 2)
    put(out, 0, 2)
    put(out, 0, 2)
    put(out, 1, 4)
    put(out, 5, 4)
    put(out, 0, 8)
    put(out, base, 8)
    put(out, base, 8)
    put(out, file_size, 8)
    put(out, file_size, 8)
    put(out, ELF_ALIGN, 8)
    put(out, 1, 4)
    put(out, 6, 4)
    put(out, 0, 8)
    put(out, bss_addr, 8)
    put(out, bss_addr, 8)
    put(out, 0, 8)
    put(out, image.bss_size if image.bss_size != 0 else 8, 8)
    put(out, ELF_ALIGN, 8)
    while len(out) < code_off:
        append(out, 0)
    for w in a.code:
        put(out, w, 4)
    while len(out) < rodata_off:
        append(out, 0)
    for b in image.rodata:
        append(out, b)
    return out

func write_elf_a64(image, path):
    _io.write_bytes(path, build_elf_a64(image, path))
    try:
        _os.chmod(path, 0o755)
    catch e:
        pass_ := 0

# Windows ARM64 : PE32+ (machine 0xAA64) ; relocations ADRP / ADD / LDR résolues sur les RVA (image chargée à une
# adresse alignée sur 4 Kio au moins : les écarts de pages entre sections sont conservés).
func write_pe_a64(image, path, windows):
    a := image.code
    a.resolve()
    fn := (ro, code, imp, bss_rva) => _pe_code(a, [ro, bss_rva, code, imp], code)
    _io.write_bytes(path, _x.build_pe(image, path, windows, 0xAA64, a.size(), fn))

func _pe_code(a, bases, code_rva):
    relocate(a, bases, code_rva)
    return _code_bytes(a)

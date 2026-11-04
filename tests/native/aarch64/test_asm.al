# Assembleur AArch64 du compilateur natif écrit en ALEX (native.a64) : chaque cas émet des instructions,
# dont les encodages doivent être ceux de tests/native/aarch64/asm_expected.txt (« mot<TAB>texte », encodages de
# référence vérifiés contre llvm-mc). Lancé par tests/native/run_aarch64_tests.sh :
#   alex run tests/native/aarch64/test_asm.al
use io
use string as s
from collections use append
use native.a64 as A

const MIN := -9223372036854775807 - 1

func c0(a):
    a.mov_imm(A.X0, 0)

func c1(a):
    a.mov_imm(A.X1, 42)

func c2(a):
    a.mov_imm(A.X2, -1)

func c3(a):
    a.mov_imm(A.X3, -2)

func c4(a):
    a.mov_imm(A.X4, 0x12345678)

func c5(a):
    a.mov_imm(A.X5, 0x1234000000000000)

func c6(a):
    a.mov_imm(A.X6, -100000)

func c7(a):
    a.mov_imm(A.X7, MIN)

func c8(a):
    a.mov_imm(A.X9, 0x7FFFFFFFFFFFFFFF)

func c9(a):
    a.mov_imm(A.X10, 0x0123456789ABCDEF)

func c10(a):
    a.mov(A.X19, A.X0)

func c11(a):
    a.mov(A.X9, A.SP)

func c12(a):
    a.mov(A.SP, A.X1)

func c13(a):
    a.add_imm(A.X0, A.X1, 5)

func c14(a):
    a.add_imm(A.SP, A.SP, 4095)

func c15(a):
    a.add_imm(A.X0, A.X29, -24)

func c16(a):
    a.add_imm(A.X2, A.X3, 8192)

func c17(a):
    a.add_imm(A.SP, A.SP, -65536)

func c18(a):
    a.add_imm(A.X1, A.X29, -40000)

func c19(a):
    a.add_imm(A.X1, A.X16, 100000)

func c20(a):
    a.add(A.X0, A.X1, A.X2)

func c21(a):
    a.add(A.X0, A.X1, A.X2, 3)

func c22(a):
    a.sub(A.X3, A.X4, A.X5)

func c23(a):
    a.sub_sp(A.SP, A.SP, A.X16)

func c24(a):
    a.adds(A.X0, A.X1, A.X2)

func c25(a):
    a.cmp(A.X9, A.X10)

func c26(a):
    a.cmp_imm(A.X9, 63)

func c27(a):
    a.cmp_imm(A.X9, -1)

func c28(a):
    a.cmp_imm(A.X28, 100000)

func c29(a):
    a.tst(A.X1, A.X2)

func c30(a):
    a.and_(A.X0, A.X1, A.X2)

func c31(a):
    a.orr(A.X0, A.X1, A.X2)

func c32(a):
    a.eor(A.X0, A.X1, A.X2)

func c33(a):
    a.mvn(A.X0, A.X1)

func c34(a):
    a.neg(A.X0, A.X1)

func c35(a):
    a.mul(A.X9, A.X9, A.X10)

func c36(a):
    a.msub(A.X11, A.X12, A.X10, A.X9)

func c37(a):
    a.sdiv(A.X11, A.X9, A.X10)

func c38(a):
    a.udiv(A.X11, A.X9, A.X10)

func c39(a):
    a.lslv(A.X9, A.X9, A.X10)

func c40(a):
    a.lsrv(A.X9, A.X9, A.X10)

func c41(a):
    a.asrv(A.X9, A.X9, A.X10)

func c42(a):
    a.lsl_imm(A.X1, A.X2, 3)

func c43(a):
    a.lsr_imm(A.X1, A.X2, 1)

func c44(a):
    a.asr_imm(A.X1, A.X2, 63)

func c45(a):
    a.cset(A.X9, A.EQ)

func c46(a):
    a.cset(A.X9, A.LT)

func c47(a):
    a.cset(A.X9, A.HS)

func c48(a):
    a.cset(A.X9, A.MI)

func c49(a):
    a.cset(A.X9, A.LE)

func c50(a):
    a.cset(A.X9, A.GT)

func c51(a):
    a.csel(A.X9, A.X10, A.X9, A.VS)

func c52(a):
    a.ldr(A.X9, A.X29, -8)

func c53(a):
    a.ldr(A.X9, A.X29, -256)

func c54(a):
    a.ldr(A.X9, A.X29, -264)

func c55(a):
    a.ldr(A.X9, A.X0, 32760)

func c56(a):
    a.ldr(A.X9, A.X0, 32768)

func c57(a):
    a.ldr(A.X9, A.X0, 12)

func c58(a):
    a.ldr(A.X9, A.SP, 16)

func c59(a):
    a.strx(A.X19, A.X29, -48)

func c60(a):
    a.strx(A.X1, A.X0, 8)

func c61(a):
    a.strx(A.X16, A.X29, -1000)

func c62(a):
    a.ldrw(A.X9, A.X0, 4)

func c63(a):
    a.strw(A.X9, A.X0, 0)

func c64(a):
    a.ldrh(A.X9, A.X0, 2)

func c65(a):
    a.strh(A.X9, A.X0, -2)

func c66(a):
    a.ldrb(A.X9, A.X0, 7)

func c67(a):
    a.strb(A.X10, A.X1, 0)

func c68(a):
    a.ldr_idx(A.X9, A.X9, A.X10)

func c69(a):
    a.str_idx(A.X11, A.X9, A.X10)

func c70(a):
    a.ldrb_idx(A.X9, A.X1, A.X2)

func c71(a):
    a.stp_pre(A.X29, A.X30, A.SP, -16)

func c72(a):
    a.ldp_post(A.X29, A.X30, A.SP, 16)

func c73(a):
    a.stp(A.X19, A.X20, A.X9, 32)

func c74(a):
    a.ldp(A.X21, A.X22, A.X9, 48)

func c75(a):
    a.ldaxr(A.X9, A.X1)

func c76(a):
    a.stlxr(A.X12, A.X2, A.X1)

func c77(a):
    l := a.new_label()
    a.b(l)
    a.word(0xD503201F)
    a.bind(l)
    a.resolve()

func c78(a):
    l := a.new_label()
    a.bind(l)
    a.word(0xD503201F)
    a.bl(l)
    a.resolve()

func c79(a):
    l := a.new_label()
    a.bcond(A.GT, l)
    a.bind(l)
    a.resolve()

func c80(a):
    l := a.new_label()
    a.bind(l)
    a.cbz(A.X9, l)
    a.resolve()

func c81(a):
    l := a.new_label()
    a.cbnz(A.X1, l)
    a.word(0xD503201F)
    a.word(0xD503201F)
    a.bind(l)
    a.resolve()

func c82(a):
    a.br(A.X16)

func c83(a):
    a.blr(A.X16)

func c84(a):
    a.ret()

func c85(a):
    a.svc()

func c86(a):
    a.brk(1)

func c87(a):
    a.dmb()

func c88(a):
    a.fmov_to_d(0, A.X9)

func c89(a):
    a.fmov_from_d(A.X9, 1)

func c90(a):
    a.fadd(0, 0, 1)

func c91(a):
    a.fsub(0, 0, 1)

func c92(a):
    a.fmul(0, 0, 1)

func c93(a):
    a.fdiv(0, 0, 1)

func c94(a):
    a.fcmp(0, 1)

func c95(a):
    a.scvtf(0, A.X9)

func c96(a):
    a.fcvtzs(A.X9, 0)

func c97(a):
    a.mrs(A.X9, A.SYS_DAIF)

func c98(a):
    a.msr(A.SYS_DAIF, A.X9)

func c99(a):
    a.mrs(A.X0, A.SYS_CURRENT_EL)

func c100(a):
    a.msr(A.SYS_SPSEL, A.X1)

func c101(a):
    a.mrs(A.X9, A.SYS_FAR_EL1)

func c102(a):
    a.mrs(A.X1, A.SYS_ESR_EL1)

func c103(a):
    a.mrs(A.X2, A.SYS_ELR_EL1)

func c104(a):
    a.msr(A.SYS_ELR_EL1, A.X2)

func c105(a):
    a.mrs(A.X3, A.SYS_SPSR_EL1)

func c106(a):
    a.msr(A.SYS_SPSR_EL1, A.X3)

func c107(a):
    a.msr(A.SYS_VBAR_EL1, A.X9)

func c108(a):
    a.mrs(A.X9, A.SYS_SCTLR_EL1)

func c109(a):
    a.msr(A.SYS_SCTLR_EL1, A.X9)

func c110(a):
    a.msr(A.SYS_CPACR_EL1, A.X9)

func c111(a):
    a.mrs(A.X9, A.SYS_TTBR0_EL1)

func c112(a):
    a.msr(A.SYS_TTBR0_EL1, A.X9)

func c113(a):
    a.msr(A.SYS_TCR_EL1, A.X9)

func c114(a):
    a.msr(A.SYS_MAIR_EL1, A.X9)

func c115(a):
    a.msr(A.SYS_HCR_EL2, A.X9)

func c116(a):
    a.msr(A.SYS_SPSR_EL2, A.X9)

func c117(a):
    a.msr(A.SYS_ELR_EL2, A.X9)

func c118(a):
    a.msr(A.SYS_SP_EL1, A.X9)

func c119(a):
    a.msr(A.SYS_CNTHCTL_EL2, A.X9)

func c120(a):
    a.msr(A.SYS_CNTVOFF_EL2, A.XZR)

func c121(a):
    a.mrs(A.X9, A.SYS_CNTFRQ_EL0)

func c122(a):
    a.mrs(A.X9, A.SYS_CNTVCT_EL0)

func c123(a):
    a.daif_set(2)

func c124(a):
    a.daif_clr(2)

func c125(a):
    a.daif_set(15)

func c126(a):
    a.wfi()

func c127(a):
    a.yield_()

func c128(a):
    a.isb()

func c129(a):
    a.dsb_sy()

func c130(a):
    a.tlbi_vmalle1()

func c131(a):
    a.eret()

func c132(a):
    a.hlt(0xF000)

func c133(a):
    a.hvc(0)

func c134(a):
    a.smc(0)

CASES := [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15, c16, c17, c18, c19, c20, c21, c22, c23, c24, c25, c26, c27, c28, c29, c30, c31, c32, c33, c34, c35, c36, c37, c38, c39, c40, c41, c42, c43, c44, c45, c46, c47, c48, c49, c50, c51, c52, c53, c54, c55, c56, c57, c58, c59, c60, c61, c62, c63, c64, c65, c66, c67, c68, c69, c70, c71, c72, c73, c74, c75, c76, c77, c78, c79, c80, c81, c82, c83, c84, c85, c86, c87, c88, c89, c90, c91, c92, c93, c94, c95, c96, c97, c98, c99, c100, c101, c102, c103, c104, c105, c106, c107, c108, c109, c110, c111, c112, c113, c114, c115, c116, c117, c118, c119, c120, c121, c122, c123, c124, c125, c126, c127, c128, c129, c130, c131, c132, c133, c134]


expected := []
for l in s.split(io.read_file("tests/native/aarch64/asm_expected.txt"), "\n"):
    if l != "":
        append(expected, s.split(l, "\t"))
hx := ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]
func hex8(w):
    r := ""
    i := 7
    while i >= 0:
        r += hx[(w >> (4 * i)) & 15]
        i -= 1
    return r
k := 0
bad := 0
for f in CASES:
    a := A.Asm()
    f(a)
    for w in a.code:
        if k >= len(expected):
            bad += 1
            break
        if hex8(w) != expected[k][0]:
            print("ÉCHEC " + expected[k][1] + " : " + hex8(w) + " au lieu de " + expected[k][0])
            bad += 1
        k += 1
if k != len(expected):
    print("ÉCHEC : " + str(k) + " instructions émises, " + str(len(expected)) + " attendues")
    bad += 1
if bad == 0:
    print("ok    assembleur AArch64 (" + str(k) + " instructions identiques aux encodages de référence)")
else:
    raise("TestError", "assembleur AArch64 : " + str(bad) + " écart(s)")

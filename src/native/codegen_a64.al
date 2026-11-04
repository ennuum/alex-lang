# ALEX — native.codegen_a64
#
# IR -> code machine AArch64 (Linux, Windows ARM64) + runtime minimal en assembleur (appels système, sans libc),
# docs/NATIVE.md « ARM64 ». Même IR, même runtime ALEX et mêmes tables de traces que le générateur x86-64
# (native.codegen_x64), dont celui-ci reprend la structure et les conventions :
#
#   x0..x7    arguments (8 en registres, les suivants sur la pile en [x29 + 16 + 8i] chez l'appelé), résultat x0
#   x9..x15   temporaires du générateur ; x16 / x17 réservés à l'assembleur
#   x19..x22  registres virtuels les plus utilisés (préservés par l'appelé ; équivalents de rbx, r12..r14)
#   x28       profondeur d'appel (équivalent de r15) ; x29 / x30 : chaîne des cadres ([fp] = cadre précédent,
#             [fp + 8] = adresse de retour, comme rbp sous x86-64) et adresse de retour
#   d0, d1    flottants
#
# Les dispositions partagées avec le runtime ALEX sont celles de x86-64 : enregistrement d'un try (9 mots :
# précédent, fp, sp, profondeur, x19..x22, reprise), registres rangés pour le GC (4 mots), pile initiale d'une
# tâche (9 mots en hi - 72). sp devant rester aligné sur 16 sous Linux AArch64, la commutation de tâche lit et
# écrit cet enregistrement par x9 / x1.
#
#   use native.codegen_a64 as cg64
#   cg64.generate_a64(prog, "sortie")       # IrProgram (après nt_inline) -> exécutable ELF AArch64 ou PE ARM64
#
# Cibles : Linux (ELF), Windows ARM64 (PE32+, console ou --gui). Sans OS et UEFI : x86-64 seulement.
#
# Erreurs : RuntimeError (cible, instruction sans équivalent, assembleur).

from core use len, type
from collections use append
use string as _s
use native.ir as ir
use native.a64 as A
use native.x64 as _x

const K_OUT_LEN := 0
const K_STACK_TOP := 8
const K_ARGV := 16
const K_REG_SAVE := 24
const K_HANDLER := 56
const K_RT_STATE := 64
const K_SMP := 64 + 2048
const K_CPU0 := 64 + 2048 + 64
const K_CPU_SIZE := 256
const K_GLOBALS := 64 + 2048 + 64 + 256
const DEPTH := 28
const T0 := 9
const T1 := 10
const T2 := 11
const T3 := 12
const T4 := 13
const T5 := 14
const ARG_REGS := [0, 1, 2, 3, 4, 5, 6, 7]
const REG_ARGS := 8
const BUF_SIZE := 65536
const STACK_SIZE := 268435456
const MAX_DEPTH := 100000
const TRACE_CAP := 100016
const TRACE_HEADER := 24
const WIN_WIDE_CHARS := 8192
const WIN_ERR_CAP := 16384
const INT64_MAX := 9223372036854775807
const INT64_MIN := -9223372036854775807 - 1

func _bytes(s):
    return _s.byte_unpack(s)

class Site:
    func init(label, line, msg, bounds):
        self.label = label
        self.line = line
        self.msg = msg
        self.bounds = bounds

class GenA64:
    func init(p):
        self.p = p
        self.a = A.Asm()
        self.ro = []
        self.str_off = []
        self.msg_off = []
        self.name_off = []
        self.file_off = []
        self.buf_off = 0
        self.trace_off = 0
        self.fn_label = []
        self.msg_stub_ = []
        self.msg_used = []
        self.L = {}
        self.sites = []
        self.lines = []
        self.fn_range = []
        self.cur_line = 0
        self.win = p.windows
        self.gui = p.windows and p.windows_gui
        self.pe_imports = []     # [[dll, [noms]]]
        self.imports = []
        self.imp_off = []
        self.win_scratch = 0
        self.win_wide = 0
        self.win_err_len = 0
        self.win_err = 0
        self.win_err_title = 0
        self.thunks = []         # [[fonction, étiquette]]
        self.params = 0
        self.frame_slots = 0
        self.cur_runtime = false
        self.reg_of = []
        self.uses = []
        self.is_const = []
        self.const_val = []
        self.saved_regs = []

    # ------------------------------------------------------------------ outils
    func add_rodata(bs):
        ro := self.ro
        while len(ro) % 8 != 0:
            append(ro, 0)
        off := len(ro)
        n := len(bs)
        i := 0
        while i < 8:
            append(ro, (n >> (8 * i)) & 0xFF)
            i += 1
        for b in bs:
            append(ro, b)
        return off

    func put64(v):
        i := 0
        while i < 8:
            append(self.ro, (v >> (8 * i)) & 0xFF)
            i += 1

    func msg_stub(msg):
        self.msg_used[msg] = true
        return self.msg_stub_[msg]

    func site(msg):
        s := Site(self.a.new_label(), self.cur_line, msg, null)
        append(self.sites, s)
        return s.label

    func mark_line(line):
        if line <= 0:
            return
        if len(self.lines) > 0 and self.lines[len(self.lines) - 1][1] == line:
            return
        append(self.lines, [self.a.size(), line])

    func slot_off(v):
        if v >= REG_ARGS and v < self.params:
            return 16 + 8 * (v - REG_ARGS)
        k := v if v < self.params else (self.params if self.params < REG_ARGS else REG_ARGS) + (v - self.params)
        return -8 * (k + 1)

    func save_off(k):
        return -8 * (self.frame_slots + k + 1)

    # registre machine du registre virtuel, -1 s'il vit dans sa case
    func in_reg(v):
        if v < 0 or self.reg_of[v] < 0:
            return -1
        return self.reg_of[v]

    func const_of(v):
        return v >= 0 and v < len(self.is_const) and self.is_const[v]

    func ld(t, v):
        r := self.in_reg(v)
        if r >= 0:
            self.a.mov(t, r)
        elif self.const_of(v):
            self.a.mov_imm(t, self.const_val[v])
        else:
            self.a.ldr(t, A.FP, self.slot_off(v))

    func st(v, t):
        if v < 0:
            return
        r := self.in_reg(v)
        if r >= 0:
            self.a.mov(r, t)
        else:
            self.a.strx(t, A.FP, self.slot_off(v))

    func fld(d, v, via):
        self.ld(via, v)
        self.a.fmov_to_d(d, via)

    # exit_group(code) ; ne revient pas
    func exit_with(code):
        if self.win:
            self.exit_windows(code)
            return
        if code != A.X0:
            self.a.mov(A.X0, code)
        self.a.mov_imm(A.X8, 94)
        self.a.svc()

    # Appel d'une fonction importée : arguments déjà dans x0..x7 ; x0..x17 détruits (x16 : adresse lue dans l'IAT).
    func win_call(name):
        self.a.ldr_data(A.X16, A.S_IMPORT, self.imp_off[self.import_index(name)])
        self.a.blr(A.X16)

    # Résultat de 32 bits (BOOL, DWORD, int) : la moitié haute de x0 est indéfinie.
    func mask32(r):
        self.a.mov_imm(A.X17, 0xFFFFFFFF)
        self.a.and_(r, r, A.X17)

    func thunk_for(fn):
        for t in self.thunks:
            if t[0] == fn:
                return t[1]
        l := self.a.new_label()
        append(self.thunks, [fn, l])
        return l

    # ------------------------------------------------------------------ runtime en assembleur
    # Convention : arguments x0.., résultat x0 ; détruit x0..x17 ; préserve x19..x28, x29.

    # x0 -> x1 = début, x2 = longueur (décimal signé dans [x29 + .., x29 + buf_end))
    func digits(buf_end):
        a := self.a
        pos := a.new_label()
        dig := a.new_label()
        done := a.new_label()
        a.add_imm(A.X8, A.FP, buf_end)
        a.mov(A.X4, A.X0)
        a.cmp_imm(A.X0, 0)
        a.bcond(A.GE, pos)
        a.neg(A.X4, A.X0)
        a.bind(pos)
        a.mov_imm(A.X5, 10)
        a.bind(dig)
        a.udiv(A.X6, A.X4, A.X5)
        a.msub(A.X7, A.X6, A.X5, A.X4)
        a.add_imm(A.X7, A.X7, 48)
        a.add_imm(A.X8, A.X8, -1)
        a.strb(A.X7, A.X8, 0)
        a.mov(A.X4, A.X6)
        a.cbnz(A.X4, dig)
        a.cmp_imm(A.X0, 0)
        a.bcond(A.GE, done)
        a.mov_imm(A.X7, 45)
        a.add_imm(A.X8, A.X8, -1)
        a.strb(A.X7, A.X8, 0)
        a.bind(done)
        a.mov(A.X1, A.X8)
        a.add_imm(A.X2, A.FP, buf_end)
        a.sub(A.X2, A.X2, A.X8)

    func runtime():
        a := self.a
        L := self.L
        # write_fd(x0 = fd, x1 = adresse, x2 = longueur) : écrit tout (write, 64).
        a.bind(L["write_fd"])
        if self.win:
            self.win_write_fd()
        else:
            loop := a.new_label()
            done := a.new_label()
            a.mov(A.X3, A.X0)
            a.mov(A.X4, A.X1)
            a.mov(A.X5, A.X2)
            a.bind(loop)
            a.cbz(A.X5, done)
            a.mov(A.X0, A.X3)
            a.mov(A.X1, A.X4)
            a.mov(A.X2, A.X5)
            a.mov_imm(A.X8, 64)
            a.svc()
            a.cmp_imm(A.X0, 0)
            a.bcond(A.LE, done)
            a.add(A.X4, A.X4, A.X0)
            a.sub(A.X5, A.X5, A.X0)
            a.b(loop)
            a.bind(done)
            a.ret()
        # write_err(x0 = chaîne)
        a.bind(L["write_err"])
        a.ldr(A.X2, A.X0, 0)
        a.add_imm(A.X1, A.X0, 8)
        a.mov_imm(A.X0, 2)
        a.b(L["write_fd"])
        # flush()
        a.bind(L["flush"])
        a.stp_pre(A.FP, A.LR, A.SP, -16)
        a.mov(A.FP, A.SP)
        a.ldr_data(A.X2, A.S_BSS, K_OUT_LEN)
        a.adr_data(A.X1, A.S_BSS, self.buf_off)
        a.mov_imm(A.X0, 1)
        a.bl(L["write_fd"])
        a.str_data(A.XZR, A.S_BSS, K_OUT_LEN)
        a.ldp_post(A.FP, A.LR, A.SP, 16)
        a.ret()
        # write(x0 = adresse, x1 = longueur) : ajoute au tampon (vidé s'il déborde ; écriture directe si plus grand).
        a.bind(L["write"])
        fits := a.new_label()
        copy := a.new_label()
        out := a.new_label()
        a.stp_pre(A.FP, A.LR, A.SP, -32)
        a.mov(A.FP, A.SP)
        a.stp(A.X0, A.X1, A.SP, 16)
        a.mov(A.X6, A.X0)
        a.mov(A.X7, A.X1)
        a.ldr_data(A.X9, A.S_BSS, K_OUT_LEN)
        a.add(A.X10, A.X9, A.X7)
        a.cmp_imm(A.X10, BUF_SIZE)
        a.bcond(A.LS, fits)
        a.bl(L["flush"])
        a.ldp(A.X6, A.X7, A.SP, 16)
        a.cmp_imm(A.X7, BUF_SIZE)
        a.bcond(A.LS, fits)
        a.mov_imm(A.X0, 1)
        a.mov(A.X1, A.X6)
        a.mov(A.X2, A.X7)
        a.bl(L["write_fd"])
        a.b(out)
        a.bind(fits)
        a.ldr_data(A.X9, A.S_BSS, K_OUT_LEN)
        a.adr_data(A.X10, A.S_BSS, self.buf_off)
        a.add(A.X10, A.X10, A.X9)
        a.add(A.X11, A.X9, A.X7)
        a.str_data(A.X11, A.S_BSS, K_OUT_LEN)
        a.bind(copy)
        a.cbz(A.X7, out)
        a.ldrb(A.X12, A.X6, 0)
        a.strb(A.X12, A.X10, 0)
        a.add_imm(A.X6, A.X6, 1)
        a.add_imm(A.X10, A.X10, 1)
        a.add_imm(A.X7, A.X7, -1)
        a.b(copy)
        a.bind(out)
        a.ldp_post(A.FP, A.LR, A.SP, 32)
        a.ret()
        # newline()
        a.bind(L["newline"])
        ok := a.new_label()
        a.stp_pre(A.FP, A.LR, A.SP, -16)
        a.mov(A.FP, A.SP)
        a.ldr_data(A.X9, A.S_BSS, K_OUT_LEN)
        a.cmp_imm(A.X9, BUF_SIZE)
        a.bcond(A.LO, ok)
        a.bl(L["flush"])
        a.mov_imm(A.X9, 0)
        a.bind(ok)
        a.adr_data(A.X10, A.S_BSS, self.buf_off)
        a.add(A.X10, A.X10, A.X9)
        a.mov_imm(A.X11, 10)
        a.strb(A.X11, A.X10, 0)
        a.add_imm(A.X9, A.X9, 1)
        a.str_data(A.X9, A.S_BSS, K_OUT_LEN)
        a.ldp_post(A.FP, A.LR, A.SP, 16)
        a.ret()
        # print_str(x0 = chaîne [longueur][octets])
        a.bind(L["print_str"])
        a.stp_pre(A.FP, A.LR, A.SP, -16)
        a.mov(A.FP, A.SP)
        a.ldr(A.X1, A.X0, 0)
        a.add_imm(A.X0, A.X0, 8)
        a.bl(L["write"])
        a.bl(L["newline"])
        a.ldp_post(A.FP, A.LR, A.SP, 16)
        a.ret()
        # print_int(x0)
        a.bind(L["print_int"])
        a.stp_pre(A.FP, A.LR, A.SP, -48)
        a.mov(A.FP, A.SP)
        self.digits(48)
        a.mov(A.X0, A.X1)
        a.mov(A.X1, A.X2)
        a.bl(L["write"])
        a.bl(L["newline"])
        a.ldp_post(A.FP, A.LR, A.SP, 48)
        a.ret()
        # int_to_str(x0) -> x0 : nouvelle chaîne (__rt_alloc, racine 2).
        a.bind(L["int_to_str"])
        copy2 := a.new_label()
        done2 := a.new_label()
        a.stp_pre(A.FP, A.LR, A.SP, -64)
        a.mov(A.FP, A.SP)
        self.digits(64)
        a.strx(A.X1, A.FP, 16)
        a.strx(A.X2, A.FP, 24)
        a.add_imm(A.X0, A.X2, 8)
        a.mov_imm(A.X1, 1)
        a.bl(self.fn_label[2])
        a.ldr(A.X1, A.FP, 16)
        a.ldr(A.X2, A.FP, 24)
        a.strx(A.X2, A.X0, 0)
        a.add_imm(A.X3, A.X0, 8)
        a.bind(copy2)
        a.cbz(A.X2, done2)
        a.ldrb(A.X4, A.X1, 0)
        a.strb(A.X4, A.X3, 0)
        a.add_imm(A.X1, A.X1, 1)
        a.add_imm(A.X3, A.X3, 1)
        a.add_imm(A.X2, A.X2, -1)
        a.b(copy2)
        a.bind(done2)
        a.ldp_post(A.FP, A.LR, A.SP, 64)
        a.ret()
        # fail(x1 = message), x30 = adresse de retour du site fautif. Un try est actif : exception par
        # __rt_raise_msg (racine 3). Sinon : vidage, trace, __rt_report (racine 1), exit(1).
        a.bind(L["fail"])
        uncaught := a.new_label()
        walk := a.new_label()
        done3 := a.new_label()
        a.ldr_data(A.X9, A.S_BSS, K_HANDLER)
        a.cbz(A.X9, uncaught)
        a.add_imm(A.SP, A.SP, -16)
        a.strx(A.LR, A.SP, 0)
        a.mov(A.X0, A.X1)
        a.bl(self.fn_label[3])
        a.brk(2)
        a.bind(uncaught)
        a.mov(A.X20, A.X1)
        a.mov(A.X21, A.LR)
        a.mov(A.X22, A.FP)
        a.bl(L["flush"])
        a.adr_data(A.X9, A.S_BSS, self.trace_off)
        a.strx(A.X21, A.X9, 8)
        a.mov_imm(A.X10, 1)
        a.bind(walk)
        a.cbz(A.X22, done3)
        a.cmp_imm(A.X10, TRACE_CAP - 1)
        a.bcond(A.HS, done3)
        a.ldr(A.X11, A.X22, 8)
        a.add_imm(A.X10, A.X10, 1)
        a.str_idx(A.X11, A.X9, A.X10)
        a.ldr(A.X22, A.X22, 0)
        a.b(walk)
        a.bind(done3)
        a.strx(A.X10, A.X9, 0)
        a.mov_imm(DEPTH, 0)
        a.mov(A.X1, A.X9)
        a.mov(A.X0, A.X20)
        a.bl(self.fn_label[1])
        a.mov_imm(A.X0, 1)
        self.exit_with(A.X0)
        # switch(x0 = case où ranger le pointeur d'enregistrement, x1 = enregistrement de la tâche à reprendre).
        a.bind(L["switch"])
        a.add_imm(A.X9, A.SP, -72)
        a.strx(A.XZR, A.X9, 0)
        a.strx(DEPTH, A.X9, 8)
        a.strx(A.X22, A.X9, 16)
        a.strx(A.X21, A.X9, 24)
        a.strx(A.X20, A.X9, 32)
        a.strx(A.X19, A.X9, 40)
        a.strx(A.FP, A.X9, 48)
        a.strx(A.LR, A.X9, 56)
        a.strx(A.XZR, A.X9, 64)
        a.add_imm(A.SP, A.SP, -80)
        a.strx(A.X9, A.X0, 0)
        a.ldr(DEPTH, A.X1, 8)
        a.ldr(A.X22, A.X1, 16)
        a.ldr(A.X21, A.X1, 24)
        a.ldr(A.X20, A.X1, 32)
        a.ldr(A.X19, A.X1, 40)
        a.ldr(A.FP, A.X1, 48)
        a.ldr(A.LR, A.X1, 56)
        a.add_imm(A.X9, A.X1, 72)
        a.mov(A.SP, A.X9)
        a.ret()
        # Première exécution d'une tâche : __rt_fiber_main (racine 5).
        a.bind(L["fiber_entry"])
        a.bl(self.fn_label[5])
        a.brk(3)
        # memcpy(x0 = destination, x1 = source, x2 = n) : copie vers l'avant, comme rep movsb.
        a.bind(L["memcpy"])
        words := a.new_label()
        bytes := a.new_label()
        out2 := a.new_label()
        a.sub(A.X4, A.X0, A.X1)
        a.cmp_imm(A.X4, 8)
        a.bcond(A.LO, bytes)
        a.bind(words)
        a.cmp_imm(A.X2, 8)
        a.bcond(A.LO, bytes)
        a.ldr(A.X3, A.X1, 0)
        a.strx(A.X3, A.X0, 0)
        a.add_imm(A.X0, A.X0, 8)
        a.add_imm(A.X1, A.X1, 8)
        a.add_imm(A.X2, A.X2, -8)
        a.b(words)
        a.bind(bytes)
        a.cbz(A.X2, out2)
        a.ldrb(A.X3, A.X1, 0)
        a.strb(A.X3, A.X0, 0)
        a.add_imm(A.X0, A.X0, 1)
        a.add_imm(A.X1, A.X1, 1)
        a.add_imm(A.X2, A.X2, -1)
        a.b(bytes)
        a.bind(out2)
        a.ret()
        # memzero(x0 = adresse, x1 = n)
        a.bind(L["memzero"])
        zwords := a.new_label()
        zbytes := a.new_label()
        zout := a.new_label()
        a.bind(zwords)
        a.cmp_imm(A.X1, 8)
        a.bcond(A.LO, zbytes)
        a.strx(A.XZR, A.X0, 0)
        a.add_imm(A.X0, A.X0, 8)
        a.add_imm(A.X1, A.X1, -8)
        a.b(zwords)
        a.bind(zbytes)
        a.cbz(A.X1, zout)
        a.strb(A.XZR, A.X0, 0)
        a.add_imm(A.X0, A.X0, 1)
        a.add_imm(A.X1, A.X1, -1)
        a.b(zbytes)
        a.bind(zout)
        a.ret()
        # pow(x0 = base, x1 = exposant >= 0) -> x0, par carrés successifs (enroulement modulo 2^64).
        a.bind(L["pow"])
        ploop := a.new_label()
        pskip := a.new_label()
        pdone := a.new_label()
        pneg := a.new_label()
        a.cmp_imm(A.X1, 0)
        a.bcond(A.LT, pneg)
        a.mov_imm(A.X2, 1)
        a.mov_imm(A.X4, 1)
        a.bind(ploop)
        a.cbz(A.X1, pdone)
        a.and_(A.X3, A.X1, A.X4)
        a.cbz(A.X3, pskip)
        a.mul(A.X2, A.X2, A.X0)
        a.bind(pskip)
        a.mul(A.X0, A.X0, A.X0)
        a.lsr_imm(A.X1, A.X1, 1)
        a.b(ploop)
        a.bind(pdone)
        a.mov(A.X0, A.X2)
        a.ret()
        a.bind(pneg)
        a.b(self.msg_stub(ir.MSG_POW_NEGATIVE))

    # ------------------------------------------------------------------ allocation et fonctions
    func allocate(f):
        n := f.vregs
        self.reg_of = [-1 for i in 0..n]
        self.uses = [0 for i in 0..n]
        self.is_const = [false for i in 0..n]
        self.const_val = [0 for i in 0..n]
        defs := [0 for i in 0..n]
        def_const := [false for i in 0..n]
        weight := [0.0 for i in 0..n]
        code := f.code
        nc := len(code)
        label_pos := [0 for i in 0..f.labels]
        k := 0
        while k < nc:
            if code[k].op == ir.LABEL:
                label_pos[code[k].label] = k
            k += 1
        delta := [0 for i in 0..(nc + 1)]
        k = 0
        while k < nc:
            ins := code[k]
            if ins.op == ir.JMP or ins.op == ir.JMP_IF_ZERO or ins.op == ir.JMP_IF_NON_ZERO:
                lp := label_pos[ins.label]
                if lp < k:
                    delta[lp] += 1
                    delta[k + 1] -= 1
            k += 1
        depth := 0
        k = 0
        while k < nc:
            depth += delta[k]
            ins := code[k]
            w := 1.0
            d := 0
            while d < depth and d < 6:
                w *= 8.0
                d += 1
            if ins.a >= 0:
                self.uses[ins.a] += 1
                weight[ins.a] += w
            if ins.b >= 0:
                self.uses[ins.b] += 1
                weight[ins.b] += w
            for r in ins.args:
                if r >= 0:
                    self.uses[r] += 1
                    weight[r] += w
            if ins.dst >= 0:
                defs[ins.dst] += 1
                weight[ins.dst] += w
                if ins.op == ir.CONST:
                    self.const_val[ins.dst] = ins.imm
                    def_const[ins.dst] = true
            k += 1
        v := 0
        while v < n:
            self.is_const[v] = defs[v] == 1 and def_const[v] and v >= f.params
            v += 1
        cand := []
        if not f.has_try:
            v = 0
            while v < n:
                cost := 2.0 + (1.0 if v < f.params else 0.0)
                if not self.is_const[v] and self.uses[v] >= 2 and weight[v] > cost + 1.0:
                    append(cand, v)
                v += 1
        cand = _stable_by_weight(cand, weight)
        pool := [A.X19, A.X20, A.X21, A.X22]
        self.saved_regs = []
        k = 0
        while k < len(cand) and k < 4:
            self.reg_of[cand[k]] = pool[k]
            append(self.saved_regs, pool[k])
            k += 1

    func epilogue():
        a := self.a
        k := 0
        while k < len(self.saved_regs):
            a.ldr(self.saved_regs[k], A.FP, self.save_off(k))
            k += 1
        if not self.cur_runtime:
            a.add_imm(DEPTH, DEPTH, -1)
        a.mov(A.SP, A.FP)
        a.ldp_post(A.FP, A.LR, A.SP, 16)
        a.ret()

    # Arguments d'un appel (hidden >= 0 : objet fonction en paramètre 0) : au-delà du 8e dans une zone de pile
    # (alignée sur 16, retirée par l'appelant après l'appel), puis registres x0..x7. Renvoie la taille de la zone.
    func call_args(args, hidden):
        all := []
        if hidden >= 0:
            append(all, hidden)
        for r in args:
            append(all, r)
        stacked := len(all) - REG_ARGS if len(all) > REG_ARGS else 0
        area := (8 * stacked + 15) & ~15
        if area != 0:
            self.a.add_imm(A.SP, A.SP, -area)
            i := REG_ARGS
            while i < len(all):
                self.ld(T0, all[i])
                self.a.strx(T0, A.SP, 8 * (i - REG_ARGS))
                i += 1
        i := 0
        while i < len(all) and i < REG_ARGS:
            self.ld(ARG_REGS[i], all[i])
            i += 1
        return area

    func function(index):
        f := self.p.functions[index]
        a := self.a
        self.params = f.params
        self.sites = []
        self.allocate(f)
        self.frame_slots = f.vregs - f.params + (f.params if f.params < REG_ARGS else REG_ARGS)
        labels := [a.new_label() for i in 0..f.labels]
        start := a.size()
        a.bind(self.fn_label[index])
        self.cur_line = 0 if len(f.code) == 0 else f.code[0].line
        self.mark_line(self.cur_line)
        self.cur_runtime = f.runtime
        if not f.runtime:
            a.add_imm(DEPTH, DEPTH, 1)
            a.cmp_imm(DEPTH, MAX_DEPTH)
            a.bcond(A.GT, self.msg_stub(ir.MSG_RECURSION))
        a.stp_pre(A.FP, A.LR, A.SP, -16)
        a.mov(A.FP, A.SP)
        frame := 8 * (self.frame_slots + len(self.saved_regs))
        frame = (frame + 15) & ~15
        if frame != 0:
            a.add_imm(A.SP, A.SP, -frame)
        if frame != 0 and frame <= 128:
            o := 0
            while o < frame:
                a.strx(A.XZR, A.SP, o)
                o += 8
        elif frame != 0 and not f.runtime:
            a.add_imm(A.IP1, A.SP, 0)
            loop := a.new_label()
            a.bind(loop)
            a.strx(A.XZR, A.IP1, 0)
            a.add_imm(A.IP1, A.IP1, 8)
            a.cmp(A.IP1, A.FP)
            a.bcond(A.LO, loop)
        k := 0
        while k < len(self.saved_regs):
            a.strx(self.saved_regs[k], A.FP, self.save_off(k))
            k += 1
        p := 0
        while p < f.params:
            r := self.in_reg(p)
            if p < REG_ARGS:
                if r >= 0:
                    a.mov(r, ARG_REGS[p])
                else:
                    a.strx(ARG_REGS[p], A.FP, self.slot_off(p))
            elif r >= 0:
                a.ldr(r, A.FP, self.slot_off(p))
            p += 1
        code := f.code
        nc := len(code)
        k = 0
        while k < nc:
            ins := code[k]
            if k + 1 < nc and self.fuse_compare_jump(ins, code[k + 1], labels):
                k += 2
                continue
            self.instruction(ins, labels)
            k += 1
        for s in self.sites:
            a.bind(s.label)
            append(self.lines, [a.size(), s.line])
            if s.bounds != null:
                self.ld(A.X0, s.bounds.a)
                self.ld(A.X1, s.bounds.b)
                a.bl(self.fn_label[s.bounds.callee])
            else:
                a.bl(self.msg_stub(s.msg))
        self.fn_range[index] = [start, a.size()]

    func fuse_compare_jump(cmp, jump, labels):
        conds := {16: A.EQ, 17: A.NE, 18: A.LT, 19: A.LE, 20: A.GT, 21: A.GE}
        if not (cmp.op in conds):
            return false
        c := conds[cmp.op]
        if (jump.op != ir.JMP_IF_ZERO and jump.op != ir.JMP_IF_NON_ZERO) or jump.a != cmp.dst or self.uses[cmp.dst] != 1:
            return false
        if jump.op == ir.JMP_IF_ZERO:
            c = A.invert(c)
        self.mark_line(cmp.line)
        self.cur_line = cmp.line
        self.ld(T0, cmp.a)
        if self.const_of(cmp.b) and self.const_val[cmp.b] > -4096 and self.const_val[cmp.b] < 4096:
            self.a.cmp_imm(T0, self.const_val[cmp.b])
        else:
            self.ld(T1, cmp.b)
            self.a.cmp(T0, T1)
        self.a.bcond(c, labels[jump.label])
        return true

    func _binop(ins, op):
        self.ld(T0, ins.a)
        self.ld(T1, ins.b)
        if op == 0:
            self.a.and_(T0, T0, T1)
        elif op == 1:
            self.a.orr(T0, T0, T1)
        elif op == 2:
            self.a.eor(T0, T0, T1)
        else:
            self.a.mul(T0, T0, T1)
        self.st(ins.dst, T0)

    func _compare(ins, c):
        self.ld(T0, ins.a)
        if self.const_of(ins.b) and self.const_val[ins.b] > -4096 and self.const_val[ins.b] < 4096:
            self.a.cmp_imm(T0, self.const_val[ins.b])
        else:
            self.ld(T1, ins.b)
            self.a.cmp(T0, T1)
        self.a.cset(T0, c)
        self.st(ins.dst, T0)

    func _fop(ins, op):
        self.fld(0, ins.a, T0)
        self.fld(1, ins.b, T1)
        if op == 0:
            self.a.fadd(0, 0, 1)
        elif op == 1:
            self.a.fsub(0, 0, 1)
        elif op == 2:
            self.a.fmul(0, 0, 1)
        else:
            self.a.fdiv(0, 0, 1)
        self.a.fmov_from_d(T0, 0)
        self.st(ins.dst, T0)

    func _fcompare(ins, c):
        self.fld(0, ins.a, T0)
        self.fld(1, ins.b, T1)
        self.a.fcmp(0, 1)
        self.a.cset(T0, c)
        self.st(ins.dst, T0)

    func instruction(ins, labels):
        a := self.a
        L := self.L
        op := ins.op
        if op != ir.LABEL:
            self.mark_line(ins.line)
        self.cur_line = ins.line
        if op == ir.CONST:
            r := self.in_reg(ins.dst)
            if r >= 0:
                a.mov_imm(r, ins.imm)
            elif not self.is_const[ins.dst]:
                a.mov_imm(T0, ins.imm)
                self.st(ins.dst, T0)
            return
        if op == ir.COPY:
            if ins.dst == ins.a:
                return
            r := self.in_reg(ins.dst)
            if r >= 0:
                self.ld(r, ins.a)
                return
            self.ld(T0, ins.a)
            self.st(ins.dst, T0)
            return
        if op == ir.ADD or op == ir.SUB:
            if self.const_of(ins.b) and self.const_val[ins.b] > -4096 and self.const_val[ins.b] < 4096:
                k := self.const_val[ins.b]
                self.ld(T0, ins.a)
                a.add_imm(T0, T0, k if op == ir.ADD else -k)
                self.st(ins.dst, T0)
                return
            self.ld(T0, ins.a)
            self.ld(T1, ins.b)
            if op == ir.ADD:
                a.add(T0, T0, T1)
            else:
                a.sub(T0, T0, T1)
            self.st(ins.dst, T0)
            return
        if op == ir.AND:
            self._binop(ins, 0)
            return
        if op == ir.OR:
            self._binop(ins, 1)
            return
        if op == ir.XOR:
            self._binop(ins, 2)
            return
        if op == ir.MUL:
            self._binop(ins, 3)
            return
        if op == ir.SHL or op == ir.SHR:
            self.ld(T1, ins.b)
            a.cmp_imm(T1, 63)
            a.bcond(A.HI, self.site(ir.MSG_SHL if op == ir.SHL else ir.MSG_SHR))
            self.ld(T0, ins.a)
            if op == ir.SHL:
                a.lslv(T0, T0, T1)
            else:
                a.asrv(T0, T0, T1)
            self.st(ins.dst, T0)
            return
        if op == ir.FLOORDIV or op == ir.MOD:
            # arrondi vers -inf, comme la VM ; reste = a - q * b
            div := op == ir.FLOORDIV
            done := a.new_label()
            self.ld(T1, ins.b)
            a.cbz(T1, self.site(ir.MSG_FLOOR_DIV_ZERO if div else ir.MSG_MOD_ZERO))
            self.ld(T0, ins.a)
            a.sdiv(T2, T0, T1)
            a.msub(T3, T2, T1, T0)
            a.cbz(T3, done)
            a.eor(T4, T3, T1)
            a.cmp_imm(T4, 0)
            a.bcond(A.GE, done)
            if div:
                a.add_imm(T2, T2, -1)
            else:
                a.add(T3, T3, T1)
            a.bind(done)
            self.st(ins.dst, T2 if div else T3)
            return
        if op == ir.POW:
            self.ld(A.X0, ins.a)
            self.ld(A.X1, ins.b)
            a.bl(L["pow"])
            self.st(ins.dst, A.X0)
            return
        if op == ir.NEG:
            self.ld(T0, ins.a)
            a.neg(T0, T0)
            self.st(ins.dst, T0)
            return
        if op == ir.BITNOT:
            self.ld(T0, ins.a)
            a.mvn(T0, T0)
            self.st(ins.dst, T0)
            return
        if op == ir.NOT:
            self.ld(T0, ins.a)
            a.cmp_imm(T0, 0)
            a.cset(T0, A.EQ)
            self.st(ins.dst, T0)
            return
        if op >= ir.EQ and op <= ir.GE:
            self._compare(ins, [A.EQ, A.NE, A.LT, A.LE, A.GT, A.GE][op - ir.EQ])
            return
        if op >= ir.FADD and op <= ir.FDIV:
            self._fop(ins, op - ir.FADD)
            return
        if op == ir.FSQRT:
            self.fld(0, ins.a, T0)
            a.fsqrt(0, 0)
            a.fmov_from_d(T0, 0)
            self.st(ins.dst, T0)
            return
        # comme la VM : < et > faux avec NaN, <= et >= vrais (après FCMP, NaN donne C = V = 1)
        if op >= ir.FEQ and op <= ir.FGE:
            self._fcompare(ins, [A.EQ, A.NE, A.MI, A.LE, A.GT, A.HS][op - ir.FEQ])
            return
        if op == ir.INT_TO_FLOAT:
            self.ld(T0, ins.a)
            a.scvtf(0, T0)
            a.fmov_from_d(T0, 0)
            self.st(ins.dst, T0)
            return
        if op == ir.FLOAT_TO_INT:
            # résultat de cvttsd2si (x86-64, la VM) : INT64_MIN pour NaN et hors limites (FCVTZS sature)
            self.fld(0, ins.a, T0)
            a.fcvtzs(T0, 0)
            a.mov_imm(T1, INT64_MAX)
            a.mov_imm(T2, INT64_MIN)
            a.cmp(T0, T1)
            a.csel(T0, T2, T0, A.EQ)
            a.fcmp(0, 0)
            a.csel(T0, T2, T0, A.VS)
            self.st(ins.dst, T0)
            return
        if op == ir.LABEL:
            a.bind(labels[ins.label])
            return
        if op == ir.JMP:
            a.b(labels[ins.label])
            return
        if op == ir.JMP_IF_ZERO or op == ir.JMP_IF_NON_ZERO:
            self.ld(T0, ins.a)
            if op == ir.JMP_IF_ZERO:
                a.cbz(T0, labels[ins.label])
            else:
                a.cbnz(T0, labels[ins.label])
            return
        if op == ir.CALL:
            area := self.call_args(ins.args, -1)
            a.bl(self.fn_label[ins.callee])
            if area != 0:
                a.add_imm(A.SP, A.SP, area)
            self.st(ins.dst, A.X0)
            return
        if op == ir.CALL_IND:
            area := self.call_args(ins.args, ins.a)
            a.ldr(A.X16, A.X0, ins.imm)
            a.blr(A.X16)
            if area != 0:
                a.add_imm(A.SP, A.SP, area)
            self.st(ins.dst, A.X0)
            return
        if op == ir.RET:
            if ins.a >= 0:
                self.ld(A.X0, ins.a)
            self.epilogue()
            return
        if op == ir.LOAD_GLOBAL:
            a.ldr_data(T0, A.S_BSS, K_GLOBALS + 8 * ins.imm)
            self.st(ins.dst, T0)
            return
        if op == ir.STORE_GLOBAL:
            self.ld(T0, ins.a)
            a.str_data(T0, A.S_BSS, K_GLOBALS + 8 * ins.imm)
            return
        if op == ir.STR_CONST:
            a.adr_data(T0, A.S_RODATA, self.str_off[ins.imm])
            self.st(ins.dst, T0)
            return
        if op == ir.LOAD64 or op == ir.LOAD32 or op == ir.LOAD16 or op == ir.LOAD8:
            self.ld(T0, ins.a)
            if op == ir.LOAD64:
                a.ldr(T0, T0, ins.imm)
            elif op == ir.LOAD32:
                a.ldrw(T0, T0, ins.imm)
            elif op == ir.LOAD16:
                a.ldrh(T0, T0, ins.imm)
            else:
                a.ldrb(T0, T0, ins.imm)
            self.st(ins.dst, T0)
            return
        if op == ir.STORE64 or op == ir.STORE32 or op == ir.STORE16 or op == ir.STORE8:
            self.ld(T0, ins.a)
            self.ld(T1, ins.b)
            if op == ir.STORE64:
                a.strx(T1, T0, ins.imm)
            elif op == ir.STORE32:
                a.strw(T1, T0, ins.imm)
            elif op == ir.STORE16:
                a.strh(T1, T0, ins.imm)
            else:
                a.strb(T1, T0, ins.imm)
            return
        if op == ir.LOAD_ELEM:
            self.ld(T0, ins.a)
            self.ld(T1, ins.b)
            a.ldr_idx(T2, T0, T1)
            self.st(ins.dst, T2)
            return
        if op == ir.STORE_ELEM:
            self.ld(T0, ins.a)
            self.ld(T1, ins.b)
            self.ld(T2, ins.args[0])
            a.str_idx(T2, T0, T1)
            return
        if op == ir.MEM_COPY:
            self.ld(A.X0, ins.a)
            self.ld(A.X1, ins.b)
            self.ld(A.X2, ins.args[0])
            a.bl(L["memcpy"])
            return
        if op == ir.MEM_ZERO:
            self.ld(A.X0, ins.a)
            self.ld(A.X1, ins.b)
            a.bl(L["memzero"])
            return
        if op == ir.BOUNDS_CHECK:
            s := Site(a.new_label(), self.cur_line, -1, ins)
            append(self.sites, s)
            self.ld(T0, ins.a)
            self.ld(T1, ins.b)
            a.cmp(T0, T1)
            a.bcond(A.HS, s.label)
            return
        if op == ir.INT_TO_STR:
            self.ld(A.X0, ins.a)
            a.bl(L["int_to_str"])
            self.st(ins.dst, A.X0)
            return
        if op == ir.PRINT_INT:
            self.ld(A.X0, ins.a)
            a.bl(L["print_int"])
            return
        if op == ir.PRINT_STR:
            self.ld(A.X0, ins.a)
            a.bl(L["print_str"])
            return
        if op == ir.PRINT_EMPTY:
            a.bl(L["newline"])
            return
        if op == ir.FAIL:
            a.bl(self.msg_stub(ins.imm))
            return
        if op == ir.FAIL_STR:
            self.ld(A.X1, ins.a)
            a.bl(L["fail"])
            return
        if op == ir.WRITE_ERR:
            self.ld(A.X0, ins.a)
            a.bl(L["write_err"])
            return
        if op == ir.CODE_BASE:
            a.adr_data(T0, A.S_CODE, 0)
            self.st(ins.dst, T0)
            return
        if op == ir.TRACE_INFO:
            a.adr_data(T0, A.S_RODATA, 0)
            self.st(ins.dst, T0)
            return
        if op == ir.ARGV_BASE:
            a.ldr_data(T0, A.S_BSS, K_ARGV)
            self.st(ins.dst, T0)
            return
        if op == ir.RT_STATE:
            a.adr_data(T0, A.S_BSS, K_RT_STATE)
            self.st(ins.dst, T0)
            return
        if op == ir.MMAP:
            if self.win:
                # VirtualAlloc(0, n, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE) ; échec : -ENOMEM
                ok := a.new_label()
                self.ld(A.X1, ins.a)
                a.mov_imm(A.X0, 0)
                a.mov_imm(A.X2, 0x3000)
                a.mov_imm(A.X3, 4)
                self.win_call("VirtualAlloc")
                a.cbnz(A.X0, ok)
                a.mov_imm(A.X0, -12)
                a.bind(ok)
                self.st(ins.dst, A.X0)
                return
            self.ld(A.X1, ins.a)
            a.mov_imm(A.X0, 0)
            a.mov_imm(A.X2, 3)
            a.mov_imm(A.X3, 0x4022)
            a.mov_imm(A.X4, -1)
            a.mov_imm(A.X5, 0)
            a.mov_imm(A.X8, 222)
            a.svc()
            self.st(ins.dst, A.X0)
            return
        if op == ir.MUNMAP:
            if self.win:
                self.ld(A.X0, ins.a)
                a.mov_imm(A.X1, 0)
                a.mov_imm(A.X2, 0x8000)
                self.win_call("VirtualFree")
                return
            self.ld(A.X0, ins.a)
            self.ld(A.X1, ins.b)
            a.mov_imm(A.X8, 215)
            a.svc()
            return
        if op == ir.STACK_PTR:
            a.mov(T0, A.SP)
            self.st(ins.dst, T0)
            return
        if op == ir.STACK_TOP:
            a.ldr_data(T0, A.S_BSS, K_STACK_TOP)
            self.st(ins.dst, T0)
            return
        if op == ir.SAVE_REGS:
            a.adr_data(T0, A.S_BSS, K_REG_SAVE)
            a.stp(A.X19, A.X20, T0, 0)
            a.stp(A.X21, A.X22, T0, 16)
            self.st(ins.dst, T0)
            return
        if op == ir.GLOBALS_START or op == ir.GLOBALS_END:
            a.adr_data(T0, A.S_BSS, K_GLOBALS + (8 * self.p.globals if op == ir.GLOBALS_END else 0))
            self.st(ins.dst, T0)
            return
        if op == ir.TRY_BEGIN:
            a.add_imm(T0, A.FP, self.slot_off(ins.a))
            a.ldr_data(T1, A.S_BSS, K_HANDLER)
            a.strx(T1, T0, 0)
            a.strx(A.FP, T0, 8)
            a.mov(T1, A.SP)
            a.strx(T1, T0, 16)
            a.strx(DEPTH, T0, 24)
            a.stp(A.X19, A.X20, T0, 32)
            a.stp(A.X21, A.X22, T0, 48)
            a.adr_label(T1, labels[ins.label])
            a.strx(T1, T0, 64)
            a.str_data(T0, A.S_BSS, K_HANDLER)
            return
        if op == ir.TRY_END:
            a.add_imm(T0, A.FP, self.slot_off(ins.a))
            a.ldr(T1, T0, 0)
            a.str_data(T1, A.S_BSS, K_HANDLER)
            return
        if op == ir.LANDING:
            self.st(ins.dst, A.X0)
            return
        if op == ir.UNWIND:
            # retire le gestionnaire courant, restaure son état et reprend à son adresse, exception dans x0
            self.ld(A.X0, ins.a)
            a.ldr_data(T0, A.S_BSS, K_HANDLER)
            a.ldr(T1, T0, 0)
            a.str_data(T1, A.S_BSS, K_HANDLER)
            a.ldr(A.FP, T0, 8)
            a.ldr(T1, T0, 16)
            a.mov(A.SP, T1)
            a.ldr(DEPTH, T0, 24)
            a.ldp(A.X19, A.X20, T0, 32)
            a.ldp(A.X21, A.X22, T0, 48)
            a.ldr(T1, T0, 64)
            a.br(T1)
            return
        if op == ir.HANDLER_TOP:
            a.ldr_data(T0, A.S_BSS, K_HANDLER)
            self.st(ins.dst, T0)
            return
        if op == ir.FRAME_PTR:
            a.mov(T0, A.FP)
            self.st(ins.dst, T0)
            return
        if op == ir.FLUSH:
            a.bl(L["flush"])
            return
        if op == ir.FIBER_ENTRY:
            a.adr_label(T0, L["fiber_entry"])
            self.st(ins.dst, T0)
            return
        if op == ir.CTX_SWITCH:
            self.ld(A.X0, ins.a)
            self.ld(A.X1, ins.b)
            a.bl(L["switch"])
            return
        if op == ir.EXIT:
            self.ld(A.X0, ins.a)
            self.exit_with(A.X0)
            return
        if op == ir.FUNC_ADDR:
            a.adr_label(T0, self.fn_label[ins.callee])
            self.st(ins.dst, T0)
            return
        if op == ir.SYSCALL:
            # appel système AArch64 brut : numéro args[0] dans x8, arguments x0..x5
            if self.win:
                raise("RuntimeError", "appel système Linux dans un exécutable Windows (doit être émulé)")
            i := 1
            while i < len(ins.args) and i <= 6:
                self.ld(ARG_REGS[i - 1], ins.args[i])
                i += 1
            self.ld(A.X8, ins.args[0])
            a.svc()
            self.st(ins.dst, A.X0)
            return
        if op == ir.CPU_OP:
            self.cpu_op(ins)
            return
        if op == ir.IMPORT_ADDR:
            if not self.win:
                raise("RuntimeError", "import Windows hors de la cible --windows")
            a.ldr_data(T0, A.S_IMPORT, self.imp_off[ins.imm])
            self.st(ins.dst, T0)
            return
        if op == ir.WIN_THUNK:
            if not self.win:
                raise("RuntimeError", "rappel Windows hors de la cible --windows")
            a.adr_label(T0, self.thunk_for(ins.callee))
            self.st(ins.dst, T0)
            return
        if op == ir.MS_CALL:
            # Windows ARM64 et UEFI ARM64 : convention AAPCS64 (x0..x7 puis la pile), x18 intact
            area := self.call_args(ins.args, -1)
            self.ld(A.X9, ins.a)
            a.blr(A.X9)
            if area != 0:
                a.add_imm(A.SP, A.SP, area)
            self.st(ins.dst, A.X0)
            return
        if op == ir.PORT_OUT or op == ir.PORT_IN or op == ir.ENTER_USER or op == ir.LEAVE_USER or op == ir.RAW_CODE or op == ir.SYSV_CALL:
            raise("RuntimeError", "instruction de l'IR sans équivalent sur AArch64 (ports d'E/S, anneau 3 ou code x86 en ligne)")
        raise("RuntimeError", "AArch64 : opération de l'IR inconnue (" + ir.op_name(op) + ")")

    func cpu_op(ins):
        a := self.a
        imm := ins.imm
        if imm == 4 or imm == 6 or imm == 7 or imm == 11 or imm == 13 or imm == 14 or imm == 25:
            a.mov_imm(T0, 0)
            self.st(ins.dst, T0)
        elif imm == 10:
            a.adr_data(T0, A.S_BSS, K_CPU0)
            self.st(ins.dst, T0)
        elif imm == 15:
            a.adr_data(T0, A.S_BSS, K_SMP)
            self.st(ins.dst, T0)
        elif imm == 16:
            # dst = ancienne valeur ; [a] = args[0] si [a] == b (exclusifs)
            loop := a.new_label()
            done := a.new_label()
            self.ld(T0, ins.a)
            self.ld(T1, ins.b)
            self.ld(T2, ins.args[0])
            a.bind(loop)
            a.ldaxr(T3, T0)
            a.cmp(T3, T1)
            a.bcond(A.NE, done)
            a.stlxr(T4, T2, T0)
            a.cbnz(T4, loop)
            a.bind(done)
            self.st(ins.dst, T3)
        elif imm == 17:
            # dst = ancienne valeur ; [a] += b
            loop := a.new_label()
            self.ld(T0, ins.a)
            self.ld(T1, ins.b)
            a.bind(loop)
            a.ldaxr(T3, T0)
            a.add(T4, T3, T1)
            a.stlxr(T5, T4, T0)
            a.cbnz(T5, loop)
            self.st(ins.dst, T3)
        elif ins.dst >= 0:
            # instructions privilégiées et mécanismes du noyau : sans objet sous Linux
            a.mov_imm(T0, 0)
            self.st(ins.dst, T0)

    # ------------------------------------------------------------------ Windows ARM64
    func import_index(name):
        full := name if _s.find(name, "!") >= 0 else "kernel32.dll!" + name
        i := 0
        while i < len(self.imports):
            if self.imports[i] == full:
                return i
            i += 1
        raise("RuntimeError", "import Windows non déclaré : " + full)

    # Fonctions importées groupées par DLL dans l'ordre de première apparition (même disposition que x86-64).
    func layout_imports():
        self.imports = [s for s in self.p.imports]
        for n in ["GetStdHandle", "GetConsoleMode", "WriteFile", "WriteConsoleW", "MultiByteToWideChar", "ExitProcess", "VirtualAlloc", "VirtualFree"]:
            full := "kernel32.dll!" + n
            if not (full in self.imports):
                append(self.imports, full)
        if self.gui and not ("user32.dll!MessageBoxW" in self.imports):
            append(self.imports, "user32.dll!MessageBoxW")
        where := []
        for imp in self.imports:
            bang := _s.find(imp, "!")
            dll := _s.lower(imp[0:bang])
            fn := imp[bang + 1:len(imp)]
            g := 0
            while g < len(self.pe_imports) and self.pe_imports[g][0] != dll:
                g += 1
            if g == len(self.pe_imports):
                append(self.pe_imports, [dll, []])
            append(where, [g, len(self.pe_imports[g][1])])
            append(self.pe_imports[g][1], fn)
        start := []
        off := 0
        for grp in self.pe_imports:
            append(start, off)
            off += 8 * (len(grp[1]) + 1)
        for w in where:
            append(self.imp_off, start[w[0]] + 8 * w[1])

    # Point d'entrée Windows : pile du programme de 256 Mio engagée par VirtualAlloc (64 puis 16 Mio si la limite
    # d'engagement est atteinte, sinon pile du fil principal) ; limites de pile du TEB (x18) élargies ; bloc
    # argc / argv / envp (__rt_win_init, racine 6) ; programme ; vidage de la sortie ; ExitProcess(0).
    func start_windows():
        a := self.a
        retry := a.new_label()
        got := a.new_label()
        keep := a.new_label()
        a.mov_imm(A.X19, STACK_SIZE)
        a.bind(retry)
        a.mov_imm(A.X0, 0)
        a.mov(A.X1, A.X19)
        a.mov_imm(A.X2, 0x3000)
        a.mov_imm(A.X3, 4)
        self.win_call("VirtualAlloc")
        a.cbnz(A.X0, got)
        a.lsr_imm(A.X19, A.X19, 2)
        a.mov_imm(A.X9, 1 << 24)
        a.cmp(A.X19, A.X9)
        a.bcond(A.HS, retry)
        a.b(keep)
        a.bind(got)
        a.add(A.X9, A.X0, A.X19)
        a.mov(A.SP, A.X9)
        a.mov_imm(A.X9, 0x7FFFFFFFFFFF)
        a.strx(A.X9, A.X18, 8)
        a.strx(A.XZR, A.X18, 16)
        a.bind(keep)
        a.mov(A.X9, A.SP)
        a.str_data(A.X9, A.S_BSS, K_STACK_TOP)
        a.mov_imm(DEPTH, 0)
        a.mov_imm(A.FP, 0)
        a.bl(self.fn_label[6])
        a.str_data(A.X0, A.S_BSS, K_ARGV)
        a.bl(self.fn_label[self.p.entry])
        a.bl(self.L["flush"])
        a.mov_imm(A.X0, 0)
        self.exit_with(A.X0)

    # write_fd sous Windows : poignée GetStdHandle(-10 - fd) ; console : UTF-8 -> UTF-16 par tranches qui ne
    # coupent pas un caractère, puis WriteConsoleW ; tube ou fichier : WriteFile. Application graphique sans
    # poignée : la sortie d'erreur est gardée pour MessageBoxW. Cadre : x19..x23 en 16..48, tranche en 56.
    func win_write_fd():
        a := self.a
        loop := a.new_label()
        file := a.new_label()
        done := a.new_label()
        small := a.new_label()
        back := a.new_label()
        cut := a.new_label()
        ok := a.new_label()
        a.stp_pre(A.FP, A.LR, A.SP, -64)
        a.mov(A.FP, A.SP)
        a.stp(A.X19, A.X20, A.SP, 16)
        a.stp(A.X21, A.X22, A.SP, 32)
        a.strx(A.X23, A.SP, 48)
        a.mov(A.X21, A.X0)
        a.mov(A.X19, A.X1)
        a.mov(A.X20, A.X2)
        a.mov_imm(A.X0, -10)
        a.sub(A.X0, A.X0, A.X21)
        self.win_call("GetStdHandle")
        a.mov(A.X22, A.X0)
        if self.gui:
            have := a.new_label()
            none := a.new_label()
            fits := a.new_label()
            a.cbz(A.X22, none)
            a.cmp_imm(A.X22, -1)
            a.bcond(A.NE, have)
            a.bind(none)
            a.cmp_imm(A.X21, 2)
            a.bcond(A.NE, done)
            a.ldr_data(A.X1, A.S_BSS, self.win_err_len)
            a.mov_imm(A.X2, WIN_ERR_CAP)
            a.sub(A.X2, A.X2, A.X1)
            a.cmp(A.X2, A.X20)
            a.bcond(A.LS, fits)
            a.mov(A.X2, A.X20)
            a.bind(fits)
            a.add(A.X3, A.X1, A.X2)
            a.str_data(A.X3, A.S_BSS, self.win_err_len)
            a.adr_data(A.X0, A.S_BSS, self.win_err)
            a.add(A.X0, A.X0, A.X1)
            a.mov(A.X1, A.X19)
            a.bl(self.L["memcpy"])
            a.b(done)
            a.bind(have)
        a.mov(A.X0, A.X22)
        a.adr_data(A.X1, A.S_BSS, self.win_scratch)
        self.win_call("GetConsoleMode")
        self.mask32(A.X0)
        a.cmp_imm(A.X0, 0)
        a.cset(A.X23, A.NE)
        a.bind(loop)
        a.cbz(A.X20, done)
        a.cbz(A.X23, file)
        a.mov(A.X2, A.X20)
        a.cmp_imm(A.X2, WIN_WIDE_CHARS)
        a.bcond(A.LS, small)
        a.mov_imm(A.X2, WIN_WIDE_CHARS)
        a.bind(small)
        a.mov(A.X3, A.X2)
        a.bind(back)
        a.cmp(A.X2, A.X20)
        a.bcond(A.HS, cut)
        a.ldrb_idx(A.X4, A.X19, A.X2)
        a.mov_imm(A.X5, 0xC0)
        a.and_(A.X4, A.X4, A.X5)
        a.cmp_imm(A.X4, 0x80)
        a.bcond(A.NE, cut)
        a.add_imm(A.X2, A.X2, -1)
        a.cbnz(A.X2, back)
        a.mov(A.X2, A.X3)
        a.bind(cut)
        a.strx(A.X2, A.FP, 56)
        a.mov(A.X3, A.X2)
        a.mov(A.X2, A.X19)
        a.mov_imm(A.X0, 65001)
        a.mov_imm(A.X1, 0)
        a.adr_data(A.X4, A.S_BSS, self.win_wide)
        a.mov_imm(A.X5, WIN_WIDE_CHARS)
        self.win_call("MultiByteToWideChar")
        self.mask32(A.X0)
        a.mov(A.X2, A.X0)
        a.mov(A.X0, A.X22)
        a.adr_data(A.X1, A.S_BSS, self.win_wide)
        a.adr_data(A.X3, A.S_BSS, self.win_scratch)
        a.mov_imm(A.X4, 0)
        self.win_call("WriteConsoleW")
        a.ldr(A.X2, A.FP, 56)
        a.add(A.X19, A.X19, A.X2)
        a.sub(A.X20, A.X20, A.X2)
        a.b(loop)
        a.bind(file)
        a.mov(A.X2, A.X20)
        a.mov_imm(A.X3, 1 << 30)
        a.cmp(A.X2, A.X3)
        a.bcond(A.LS, ok)
        a.mov(A.X2, A.X3)
        a.bind(ok)
        a.str_data(A.XZR, A.S_BSS, self.win_scratch)
        a.mov(A.X0, A.X22)
        a.mov(A.X1, A.X19)
        a.adr_data(A.X3, A.S_BSS, self.win_scratch)
        a.mov_imm(A.X4, 0)
        self.win_call("WriteFile")
        self.mask32(A.X0)
        a.cbz(A.X0, done)
        a.adr_data(A.X1, A.S_BSS, self.win_scratch)
        a.ldrw(A.X0, A.X1, 0)
        a.cbz(A.X0, done)
        a.add(A.X19, A.X19, A.X0)
        a.sub(A.X20, A.X20, A.X0)
        a.b(loop)
        a.bind(done)
        a.ldp(A.X19, A.X20, A.SP, 16)
        a.ldp(A.X21, A.X22, A.SP, 32)
        a.ldr(A.X23, A.SP, 48)
        a.ldp_post(A.FP, A.LR, A.SP, 64)
        a.ret()

    # Fin du programme sous Windows : application graphique avec une sortie d'erreur gardée -> MessageBoxW ; puis
    # ExitProcess(code). Ne revient pas.
    func exit_windows(code):
        a := self.a
        if code != A.X19:
            a.mov(A.X19, code)
        if self.gui:
            none := a.new_label()
            a.ldr_data(A.X3, A.S_BSS, self.win_err_len)
            a.cbz(A.X3, none)
            a.mov_imm(A.X0, 65001)
            a.mov_imm(A.X1, 0)
            a.adr_data(A.X2, A.S_BSS, self.win_err)
            a.adr_data(A.X4, A.S_BSS, self.win_wide)
            a.mov_imm(A.X5, WIN_WIDE_CHARS - 1)
            self.win_call("MultiByteToWideChar")
            self.mask32(A.X0)
            a.adr_data(A.X1, A.S_BSS, self.win_wide)
            a.add(A.X1, A.X1, A.X0, 1)
            a.strh(A.XZR, A.X1, 0)
            a.mov_imm(A.X0, 0)
            a.adr_data(A.X1, A.S_BSS, self.win_wide)
            a.adr_data(A.X2, A.S_RODATA, self.win_err_title + 8)
            a.mov_imm(A.X3, 0x10)
            self.win_call("user32.dll!MessageBoxW")
            a.bind(none)
        a.mov(A.X0, A.X19)
        self.win_call("ExitProcess")
        a.brk(1)

    # Points d'entrée appelables par Windows (procédure de fenêtre...) : AAPCS64 en entrée ; x29 = 0 ; x28
    # repart de 0 ; chaîne des try isolée. Cadre de 96 octets : x29, x30, x19..x22, x28, gestionnaire try sauvé.
    func win_thunks():
        a := self.a
        k := 0
        while k < len(self.thunks):   # la liste peut grandir : indices
            a.bind(self.thunks[k][1])
            a.add_imm(A.SP, A.SP, -96)
            a.stp(A.FP, A.LR, A.SP, 0)
            a.stp(A.X19, A.X20, A.SP, 16)
            a.stp(A.X21, A.X22, A.SP, 32)
            a.strx(DEPTH, A.SP, 48)
            a.ldr_data(A.X9, A.S_BSS, K_HANDLER)
            a.strx(A.X9, A.SP, 56)
            a.str_data(A.XZR, A.S_BSS, K_HANDLER)
            a.mov_imm(A.FP, 0)
            a.mov_imm(DEPTH, 0)
            a.bl(self.fn_label[self.thunks[k][0]])
            a.ldr(A.X9, A.SP, 56)
            a.str_data(A.X9, A.S_BSS, K_HANDLER)
            a.ldp(A.X19, A.X20, A.SP, 16)
            a.ldp(A.X21, A.X22, A.SP, 32)
            a.ldr(DEPTH, A.SP, 48)
            a.ldp(A.FP, A.LR, A.SP, 0)
            a.add_imm(A.SP, A.SP, 96)
            a.ret()
            k += 1

    func build_trace_tables():
        ro := self.ro
        while len(ro) % 8 != 0:
            append(ro, 0)
        funcs := len(ro)
        order := _sort_by_start([i for i in 0..len(self.p.functions)], self.fn_range)
        self.put64(len(order))
        for i in order:
            self.put64(self.fn_range[i][0])
            self.put64(self.fn_range[i][1])
            self.put64(self.name_off[i])
            fn := self.p.functions[i]
            self.put64(0 if fn.runtime else self.file_off[fn.file])
        lines := _stable_by_offset(self.lines)
        self.lines = lines
        lns := len(ro)
        self.put64(len(lines))
        for pr in lines:
            self.put64(pr[0])
            self.put64(pr[1])
        header := [funcs, lns, 0]
        k := 0
        while k < 3:
            i := 0
            while i < 8:
                ro[8 * k + i] = (header[k] >> (8 * i)) & 0xFF if i < 4 else 0
                i += 1
            k += 1

    func run(emit_map):
        p := self.p
        a := self.a
        if p.freestanding or p.uefi:
            raise("RuntimeError", "AArch64 : cibles Linux et Windows seulement (--uefi et --freestanding : x86-64)")
        if self.win:
            self.layout_imports()
        self.ro = [0 for i in 0..TRACE_HEADER]
        for s in p.strings:
            append(self.str_off, self.add_rodata(s))
        for m in p.messages:
            append(self.msg_off, self.add_rodata(_bytes(m)))
        for f in p.functions:
            append(self.name_off, self.add_rodata(_bytes(f.name)))
        for f in p.files:
            append(self.file_off, self.add_rodata(_bytes(f)))
        self.buf_off = (K_GLOBALS + 8 * p.globals + 15) & ~15
        self.trace_off = self.buf_off + BUF_SIZE
        bss_used := self.trace_off + 8 * TRACE_CAP
        if self.win:
            self.win_scratch = (bss_used + 15) & ~15
            self.win_wide = self.win_scratch + 16
            bss_used = self.win_wide + 2 * WIN_WIDE_CHARS
            if self.gui:
                self.win_err_len = (bss_used + 7) & ~7
                self.win_err = self.win_err_len + 8
                bss_used = self.win_err + WIN_ERR_CAP
                t := []
                for b in _bytes("Erreur ALEX"):
                    append(t, b)
                    append(t, 0)
                append(t, 0)
                append(t, 0)
                self.win_err_title = self.add_rodata(t)
        self.fn_range = [[0, 0] for i in 0..len(p.functions)]
        self.fn_label = [a.new_label() for i in 0..len(p.functions)]
        self.msg_stub_ = [a.new_label() for i in 0..len(p.messages)]
        self.msg_used = [false for i in 0..len(p.messages)]
        for nm in ["flush", "write_fd", "write", "newline", "print_int", "print_str", "fail", "pow", "int_to_str", "write_err", "switch", "fiber_entry", "memcpy", "memzero"]:
            self.L[nm] = a.new_label()
        # _start : sp désigne argc / argv / envp ; pile de 256 Mio (mmap, pages à la demande), modules, vidage de
        # la sortie, exit_group(0).
        entry := a.size()
        if self.win:
            self.start_windows()
        else:
            keep := a.new_label()
            a.mov(T0, A.SP)
            a.str_data(T0, A.S_BSS, K_ARGV)
            a.mov_imm(A.X0, 0)
            a.mov_imm(A.X1, STACK_SIZE)
            a.mov_imm(A.X2, 3)
            a.mov_imm(A.X3, 0x4022)
            a.mov_imm(A.X4, -1)
            a.mov_imm(A.X5, 0)
            a.mov_imm(A.X8, 222)
            a.svc()
            a.cmp_imm(A.X0, 0)
            a.bcond(A.LT, keep)
            a.mov_imm(T0, STACK_SIZE)
            a.add(T0, A.X0, T0)
            a.mov(A.SP, T0)
            a.bind(keep)
            a.mov(T0, A.SP)
            a.str_data(T0, A.S_BSS, K_STACK_TOP)
            a.mov_imm(DEPTH, 0)
            a.mov_imm(A.FP, 0)
            a.mov_imm(A.LR, 0)
            a.bl(self.fn_label[p.entry])
            a.bl(self.L["flush"])
            a.mov_imm(A.X0, 0)
            self.exit_with(A.X0)
        self.runtime()
        i := 0
        while i < len(p.functions):
            self.function(i)
            i += 1
        if self.win:
            self.win_thunks()
        m := 0
        while m < len(p.messages):
            a.bind(self.msg_stub_[m])
            if self.msg_used[m]:
                a.adr_data(A.X1, A.S_RODATA, self.msg_off[m])
                a.b(self.L["fail"])
            m += 1
        self.build_trace_tables()
        img := A.A64Image(a, self.ro, bss_used, entry)
        if emit_map:
            i = 0
            while i < len(p.functions):
                append(img.symbols, [self.fn_range[i][0], self.fn_range[i][1], p.functions[i].name])
                i += 1
        return img

# Tri stable par poids décroissant (std::stable_sort avec weight[x] > weight[y]) : tri fusion.
func _stable_by_weight(cand, weight):
    if len(cand) <= 1:
        return cand
    mid := len(cand) // 2
    l := _stable_by_weight(cand[0:mid], weight)
    r := _stable_by_weight(cand[mid:len(cand)], weight)
    out := []
    i := 0
    j := 0
    while i < len(l) and j < len(r):
        if weight[r[j]] > weight[l[i]]:
            append(out, r[j])
            j += 1
        else:
            append(out, l[i])
            i += 1
    while i < len(l):
        append(out, l[i])
        i += 1
    while j < len(r):
        append(out, r[j])
        j += 1
    return out

func _merge_sort(xs, key):
    if len(xs) <= 1:
        return xs
    mid := len(xs) // 2
    l := _merge_sort(xs[0:mid], key)
    r := _merge_sort(xs[mid:len(xs)], key)
    out := []
    i := 0
    j := 0
    while i < len(l) and j < len(r):
        if key(r[j]) < key(l[i]):
            append(out, r[j])
            j += 1
        else:
            append(out, l[i])
            i += 1
    while i < len(l):
        append(out, l[i])
        i += 1
    while j < len(r):
        append(out, r[j])
        j += 1
    return out

func _sort_by_start(order, ranges):
    return _merge_sort(order, (i) => ranges[i][0])

func _stable_by_offset(lines):
    return _merge_sort(lines, (pr) => pr[0])

# IrProgram -> exécutable AArch64 écrit dans `path` : ELF Linux, ou PE32+ Windows ARM64 si p.windows.
func generate_a64(p, path, emit_map=false):
    g := GenA64(p)
    img := g.run(emit_map)
    if g.win:
        A.write_pe_a64(img, path, _x.PeWindows(g.pe_imports, g.gui, p.windows_icon))
    else:
        A.write_elf_a64(img, path)

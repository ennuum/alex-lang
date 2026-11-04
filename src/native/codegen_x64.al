# ALEX — native.codegen_x64
#
# Génération de code x86-64 du compilateur natif écrit en ALEX (étape C) : portage fidèle de src/NativeCodegen.cpp
# pour la cible Linux (exécutable ELF statique, appels système directs, sans libc). Chaque registre virtuel a une
# case de pile ([rbp - 8k] ; paramètres au-delà du 6e en [rbp + 16 + 8i]), sauf les plus utilisés, placés dans
# rbx / r12 / r13 / r14 ; r15 compte la profondeur d'appel. Runtime minimal en assembleur : tampon de sortie,
# écriture des entiers, erreurs avec trace de pile (tables lues par __rt_report), commutation de tâches, puissance.
#
#   use native.codegen_x64 as cg
#   cg.generate_x64(prog, "sortie")       # IrProgram (après nt_inline) -> exécutable
#
# Cibles : Linux (ELF), Windows x64 (PE32+, console ou --gui), UEFI x86-64 (PE32+). Sans OS (--freestanding,
# image Multiboot) : NativeError.
#
# Erreurs : NativeError (cible non portée), RuntimeError (assembleur, ELF).

from core use len, type
from collections use append
use string as _s
use native.ir as ir
use native.x64 as x
from native.x64 use Mem

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
const K_CPU_HANDLER := 192
const K_BKL := 64 + 2048
# Bloc par cœur (sans OS, gs:[...]) : voir src/NativeCodegen.cpp d'origine et docs/NATIVE.md.
const K_CPU_SELF := 0
const K_CPU_INDEX := 8
const K_CPU_USER_RSP := 24
const K_CPU_KERNEL_RSP := 32
const K_CPU_TSS := 40
const K_CPU_IDLE_SP := 64
const K_CPU_ONLINE := 72
const K_CPU_TSS_SEL := 80
const K_CPU_BOOT_STACK := 88
const K_CPU_FROM_USER := 184
const K_CPU_GC_SP := 200
const K_CPU_GC_STATE := 208
const K_BOOT_INFO := 64 + 1960
const K_SHOOT_VECTOR := 251
const K_SHOOT_COUNT := 64 + 1760
const K_SHOOT_EOI := 64 + 1768
const K_CPU_BLOCKS := 64 + 1792
const K_OUT_LOCK := 64 + 1992
const K_PARALLEL := 64 + 2000
const K_GC_REQUEST := 64 + 1976
const K_NO_BKL := 64 + 2016
const K_FREE_VEC := 64 + 2024
const K_BOOT_STACK := 16777216
const K_ZERO_FRAME_MAX := 128
const DEPTH_REG := 15
const XMM0 := 0
const XMM1 := 1
const ARG_REGS := [7, 6, 2, 1, 8, 9]
# Appel System V (ir.SYSV_CALL) : r10 = cadre, rax = fonction.
const SYSV_TRAMPOLINE := [0x53, 0x48, 0x89, 0xE3, 0x41, 0x52, 0x48, 0x83, 0xE4, 0xF0,
    0x49, 0x8B, 0x8A, 0x70, 0, 0, 0, 0x48, 0xF7, 0xC1, 1, 0, 0, 0, 0x74, 0x04, 0x48, 0x83, 0xEC, 0x08,
    0x48, 0x85, 0xC9, 0x74, 0x0D, 0x48, 0xFF, 0xC9, 0x41, 0xFF, 0xB4, 0xCA, 0xA0, 0, 0, 0, 0xEB, 0xEE,
    0x49, 0x89, 0xC3,
    0xF2, 0x41, 0x0F, 0x10, 0x42, 0x30, 0xF2, 0x41, 0x0F, 0x10, 0x4A, 0x38, 0xF2, 0x41, 0x0F, 0x10, 0x52, 0x40,
    0xF2, 0x41, 0x0F, 0x10, 0x5A, 0x48, 0xF2, 0x41, 0x0F, 0x10, 0x62, 0x50, 0xF2, 0x41, 0x0F, 0x10, 0x6A, 0x58,
    0xF2, 0x41, 0x0F, 0x10, 0x72, 0x60, 0xF2, 0x41, 0x0F, 0x10, 0x7A, 0x68,
    0x49, 0x8B, 0x3A, 0x49, 0x8B, 0x72, 0x08, 0x49, 0x8B, 0x52, 0x10, 0x49, 0x8B, 0x4A, 0x18,
    0x4D, 0x8B, 0x42, 0x20, 0x4D, 0x8B, 0x4A, 0x28, 0x49, 0x8B, 0x42, 0x78,
    0x41, 0xFF, 0xD3,
    0x4C, 0x8B, 0x53, 0xF8, 0x49, 0x89, 0x82, 0x80, 0, 0, 0, 0xF2, 0x41, 0x0F, 0x11, 0x82, 0x88, 0, 0, 0,
    0x48, 0x89, 0xDC, 0x5B]
const REG_ARGS := 6
const BUF_SIZE := 65536
const STACK_SIZE := 268435456
const MAX_DEPTH := 100000
const TRACE_CAP := 100016
const TRACE_HEADER := 24
const MSG_POW_NEGATIVE := 5
const MSG_RECURSION := 4
const K_MAX_CPUS := 16
const K_TSS_STRIDE := 112
const K_IST_SIZE := 8192
const K_BOOT_TABLE_PAGES := 8
const WIN_WIDE_CHARS := 8192
const K_UEFI_IMAGE := 64 + 1920
const K_UEFI_SYSTAB := 64 + 1928
const K_UEFI_RSP := 64 + 1936
const K_UEFI_HEAP := 64 + 1944
const K_UEFI_FLAGS := 64 + 1952
const K_UEFI_HEAP_PAGES := 16384
const WIN_ERR_CAP := 16384

const INT32_MIN := -2147483648
const INT32_MAX := 2147483647

# Opérations qui chargent leur opérande a en premier dans rax (relais par rax).
const FIRST_LOAD := {2: true, 3: true, 5: true, 6: true, 7: true, 4: true, 16: true, 17: true, 18: true, 19: true,
    20: true, 21: true, 1: true, 13: true, 14: true, 15: true, 43: true, 45: true, 44: true, 46: true, 47: true,
    48: true, 32: true, 39: true, 41: true}

const FLOAT_SLOT_OPS := {22: true, 23: true, 24: true, 25: true, 95: true, 26: true, 27: true, 28: true, 29: true,
    30: true, 31: true, 33: true}

func bss(off):
    return x.data(x.S_BSS, off)

func _bytes(s):
    return _s.byte_unpack(s)

class Site:
    func init(label, line, msg, bounds):
        self.label = label
        self.line = line
        self.msg = msg
        self.bounds = bounds

class Gen:
    func init(p):
        self.p = p
        self.a = x.Assembler()
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
        self.fs = p.freestanding
        self.uefi = p.uefi
        self.win = p.windows
        self.gui = p.windows and p.windows_gui
        self.params = 0
        self.cur_line = 0
        self.sites = []
        self.lines = []
        self.fn_range = []
        self.reg_of = []
        self.uses = []
        self.is_const = []
        self.need_slot = []
        self.const_val = []
        self.saved_regs = []
        self.frame_slots = 0
        self.cur_runtime = false
        self.forward = -1
        self.pending = -1
        self.next_ = null
        self.labels_ = {}
        self.imports = []
        self.imp_off = []
        self.pe_imports = []     # [[dll, [noms]]]
        self.win_scratch = 0
        self.win_wide = 0
        self.win_err = 0
        self.win_err_len = 0
        self.win_err_title = 0
        self.thunks = []         # [[fonction, label]]
        self.fs_argv = 0
        self.stack_top = 0
        self.mb_info = 0
        self.tables = 0
        self.idt = 0
        self.gdt = 0
        self.tss = 0
        self.ist = 0
        self.df_msg_off = 0
        self.trampoline_off = 0

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

    func slot(v):
        if v >= REG_ARGS and v < self.params:
            return x.at(x.RBP, 16 + 8 * (v - REG_ARGS))
        k := v if v < self.params else (self.params if self.params < REG_ARGS else REG_ARGS) + (v - self.params)
        return x.at(x.RBP, -8 * (k + 1))

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

    func handler_gs():
        return self.fs and not self.uefi

    func handler_mem():
        return bss(K_CPU0 + K_CPU_HANDLER) if self.uefi else bss(K_HANDLER)

    # Accès au bloc du cœur courant (sans OS) : gs:[off].
    func gs_load(r, off):
        self.a.raw([0x65, 0x48 | (4 if r >= 8 else 0), 0x8B, 0x04 | ((r & 7) << 3), 0x25])
        self.a.u32(off)

    func gs_push(off):
        self.a.raw([0x65, 0xFF, 0x34, 0x25])
        self.a.u32(off)

    # mov qword gs:[off], imm32
    func gs_imm(off, v):
        self.a.raw([0x65, 0x48, 0xC7, 0x04, 0x25])
        self.a.u32(off)
        self.a.u32(v)

    func handler_load(r):
        if self.handler_gs():
            self.gs_load(r, K_CPU_HANDLER)
        else:
            self.a.load(r, self.handler_mem())

    func handler_store(r):
        if self.handler_gs():
            self.gs_store(K_CPU_HANDLER, r)
        else:
            self.a.store(self.handler_mem(), r)

    func handler_cmp_zero():
        if self.handler_gs():
            self.a.raw([0x65, 0x48, 0x83, 0x3C, 0x25])
            self.a.u32(K_CPU_HANDLER)
            self.a.raw([0])
        else:
            self.a.alu_mi(x.ALU_CMP, self.handler_mem(), 0)

    func handler_push():
        if self.handler_gs():
            self.gs_push(K_CPU_HANDLER)
        else:
            self.a.push_m(self.handler_mem())

    func handler_clear():
        if self.handler_gs():
            self.a.raw([0x65, 0x48, 0xC7, 0x04, 0x25])
            self.a.u32(K_CPU_HANDLER)
            self.a.raw([0, 0, 0, 0])
        else:
            self.a.store_imm(self.handler_mem(), 0)

    # mov gs:[off], r
    func gs_store(off, r):
        self.a.raw([0x65, 0x48 | (4 if r >= 8 else 0), 0x89, 0x04 | ((r & 7) << 3), 0x25])
        self.a.u32(off)

    # APIC local : x2APIC (MSR) si IA32_APIC_BASE.EXTD, sinon xAPIC en MMIO par la fenêtre des périphériques.
    # Détruisent rax, rcx, rdx.
    func apic_icr(low):
        a := self.a
        x2 := a.new_label()
        wait := a.new_label()
        done := a.new_label()
        a.mov_imm(x.RCX, 0x1B)
        a.raw([0x0F, 0x32])
        a.raw([0xA9, 0x00, 0x04, 0x00, 0x00])
        a.jcc(x.C_NE, x2)
        a.alu_ri(x.ALU_AND, x.RAX, -4096)
        a.mov_imm(x.RCX, x.MMIO_BASE)
        a.alu_rr(x.ALU_ADD, x.RAX, x.RCX)
        a.mov_imm(x.RCX, low)
        a.store32(x.at(x.RAX, 0x300), x.RCX)
        a.bind(wait)
        a.raw([0xF3, 0x90])
        a.load32(x.RCX, x.at(x.RAX, 0x300))
        a.alu_ri(x.ALU_AND, x.RCX, 0x1000)
        a.jcc(x.C_NE, wait)
        a.jmp(done)
        a.bind(x2)
        a.mov_imm(x.RCX, 0x830)
        a.mov_imm(x.RAX, low)
        a.mov_imm(x.RDX, 0)
        a.raw([0x0F, 0x30])
        a.bind(done)

    func apic_eoi():
        a := self.a
        x2 := a.new_label()
        done := a.new_label()
        a.mov_imm(x.RCX, 0x1B)
        a.raw([0x0F, 0x32])
        a.raw([0xA9, 0x00, 0x04, 0x00, 0x00])
        a.jcc(x.C_NE, x2)
        a.alu_ri(x.ALU_AND, x.RAX, -4096)
        a.mov_imm(x.RCX, x.MMIO_BASE)
        a.alu_rr(x.ALU_ADD, x.RAX, x.RCX)
        a.mov_imm(x.RCX, 0)
        a.store32(x.at(x.RAX, 0xB0), x.RCX)
        a.jmp(done)
        a.bind(x2)
        a.mov_imm(x.RCX, 0x80B)
        a.mov_imm(x.RAX, 0)
        a.mov_imm(x.RDX, 0)
        a.raw([0x0F, 0x30])
        a.bind(done)

    # Rend le verrou global s'il appartient à ce cœur (gs requis) ; détruit rcx.
    func bkl_release_mine():
        a := self.a
        skip := a.new_label()
        self.gs_load(x.RCX, K_CPU_INDEX)
        a.alu_ri(x.ALU_ADD, x.RCX, 1)
        a.alu_rm(x.ALU_CMP, x.RCX, bss(K_BKL))
        a.jcc(x.C_NE, skip)
        a.store_imm(bss(K_BKL), 0)
        a.bind(skip)

    # MSR msr = rax (64 bits) ; détruit rcx, rdx.
    func wrmsr(msr):
        a := self.a
        a.mov_imm(x.RCX, msr)
        a.mov(x.RDX, x.RAX)
        a.raw([0x48, 0xC1, 0xEA, 0x20])
        a.raw([0x0F, 0x30])

    # Sans OS : appel au runtime de sortie interruptions masquées (pushfq ; cli ; call ; popfq) ; noyau
    # parallèle : le tampon de sortie est aussi protégé par un verrou tournant (out_lock).
    func guarded_call(l):
        if self.fs:
            self.a.raw([0x9C, 0xFA])
        if self.fs and not self.uefi:
            self.a.call(self.labels_["out_lock"])
        self.a.call(l)
        if self.fs and not self.uefi:
            self.a.call(self.labels_["out_unlock"])
        if self.fs:
            self.a.raw([0x9D])

    # Point d'entrée UEFI (convention Microsoft x64 : rcx = image, rdx = table système) : tas demandé au
    # micrologiciel (AllocatePages : 64 Mio, sinon 16, 4), pile de 4 Mio dans le bss.
    func start_uefi():
        a := self.a
        for r in [x.RBX, x.RBP, x.RDI, x.RSI, x.R12, x.R13, x.R14, x.R15]:
            a.push(r)
        a.mov(x.RAX, x.RSP)
        a.store(bss(K_UEFI_RSP), x.RAX)
        a.store(bss(K_UEFI_IMAGE), x.RCX)
        a.store(bss(K_UEFI_SYSTAB), x.RDX)
        a.raw([0x9C])
        a.pop(x.RAX)
        a.store(bss(K_UEFI_FLAGS), x.RAX)
        a.raw([0xFC])
        for io in [[0x3F9, 0], [0x3FB, 0x80], [0x3F8, 3], [0x3F9, 0], [0x3FB, 3], [0x3FA, 0xC1], [0x3FC, 0x0B]]:
            a.mov_imm(x.RDX, io[0])
            a.mov_imm(x.RAX, io[1])
            a.raw([0xEE])
        a.mov_addr(x.RAX, x.S_BSS, self.fs_argv)
        a.store(bss(K_ARGV), x.RAX)
        retry := a.new_label()
        got := a.new_label()
        a.mov_imm(x.R12, K_UEFI_HEAP_PAGES)
        a.bind(retry)
        a.load(x.RAX, bss(K_UEFI_SYSTAB))
        a.load(x.RAX, x.at(x.RAX, 0x60))
        a.load(x.RAX, x.at(x.RAX, 0x28))
        a.mov_imm(x.RCX, 0)
        a.mov_imm(x.RDX, 2)
        a.mov(x.R8, x.R12)
        a.mov_addr(x.R9, x.S_BSS, K_UEFI_HEAP)
        a.alu_ri(x.ALU_SUB, x.RSP, 40)
        a.call_reg(x.RAX)
        a.alu_ri(x.ALU_ADD, x.RSP, 40)
        a.test(x.RAX, x.RAX)
        a.jcc(x.C_E, got)
        a.shr_imm(x.R12, 2)
        a.alu_ri(x.ALU_CMP, x.R12, 1024)
        a.jcc(x.C_AE, retry)
        self.exit_with(x.RAX)
        a.bind(got)
        a.load(x.RAX, bss(K_UEFI_HEAP))
        a.store(bss(K_RT_STATE + 880), x.RAX)
        a.mov(x.RCX, x.R12)
        a.mov_imm(x.RDX, 4096)
        a.imul(x.RCX, x.RDX)
        a.alu_rr(x.ALU_ADD, x.RCX, x.RAX)
        a.store(bss(K_RT_STATE + 888), x.RCX)
        a.mov_addr(x.RSP, x.S_BSS, self.stack_top)
        a.mov(x.RAX, x.RSP)
        a.store(bss(K_STACK_TOP), x.RAX)
        a.mov_imm(DEPTH_REG, 0)
        a.mov_imm(x.RBP, 0)
        a.call(self.fn_label[self.p.entry])
        a.call(self.labels_["flush"])
        a.mov_imm(x.RDI, 0)
        self.exit_with(x.RDI)

    # ------------------------------------------------------------------ Windows
    # Fonctions importées, « dll!Nom » ou « Nom » (kernel32.dll).
    func import_index(name):
        full := name if _s.find(name, "!") >= 0 else "kernel32.dll!" + name
        i := 0
        while i < len(self.imports):
            if self.imports[i] == full:
                return i
            i += 1
        raise("RuntimeError", "import Windows non déclaré : " + full)

    func layout_imports():
        imps := [s for s in self.p.imports]
        for n in ["GetStdHandle", "GetConsoleMode", "WriteFile", "WriteConsoleW", "MultiByteToWideChar", "ExitProcess", "VirtualAlloc", "VirtualFree"]:
            full := "kernel32.dll!" + n
            if not (full in imps):
                append(imps, full)
        if self.gui and not ("user32.dll!MessageBoxW" in imps):
            append(imps, "user32.dll!MessageBoxW")
        self.imports = imps
        groups := self.pe_imports
        where := []
        for full in imps:
            bang := _s.find(full, "!")
            dll := _s.lower(_s.substring(full, 0, bang))
            fn := _s.substring(full, bang + 1, len(full))
            g := 0
            while g < len(groups) and groups[g][0] != dll:
                g += 1
            if g == len(groups):
                append(groups, [dll, []])
            append(where, [g, len(groups[g][1])])
            append(groups[g][1], fn)
        start := []
        off := 0
        for g in groups:
            append(start, off)
            off += 8 * (len(g[1]) + 1)
        for w in where:
            append(self.imp_off, start[w[0]] + 8 * w[1])

    # Appel d'une fonction importée : rsp aligné sur 16, 32 octets réservés, arguments au-delà du 4e en place.
    func win_call(name):
        self.a.load(x.RAX, x.data(x.S_IMPORT, self.imp_off[self.import_index(name)]))
        self.a.call_reg(x.RAX)

    func thunk_for(fn):
        for t in self.thunks:
            if t[0] == fn:
                return t[1]
        l := self.a.new_label()
        append(self.thunks, [fn, l])
        return l

    # Point d'entrée Windows : pile de 256 Mio engagée par VirtualAlloc, bloc argc/argv/envp, programme, ExitProcess(0).
    func start_windows():
        a := self.a
        retry := a.new_label()
        got := a.new_label()
        keep := a.new_label()
        a.alu_ri(x.ALU_AND, x.RSP, -16)
        a.alu_ri(x.ALU_SUB, x.RSP, 32)
        a.mov_imm(x.R12, STACK_SIZE)
        a.bind(retry)
        a.mov_imm(x.RCX, 0)
        a.mov(x.RDX, x.R12)
        a.mov_imm(x.R8, 0x3000)
        a.mov_imm(x.R9, 4)
        self.win_call("VirtualAlloc")
        a.test(x.RAX, x.RAX)
        a.jcc(x.C_NE, got)
        a.shr_imm(x.R12, 2)
        a.alu_ri(x.ALU_CMP, x.R12, 1 << 24)
        a.jcc(x.C_AE, retry)
        a.jmp(keep)
        a.bind(got)
        a.lea(x.RSP, x.at(x.RAX))
        a.alu_rr(x.ALU_ADD, x.RSP, x.R12)
        a.mov_imm(x.RAX, 0x7FFFFFFFFFFF)
        self.gs_store(8, x.RAX)
        a.mov_imm(x.RAX, 0)
        self.gs_store(16, x.RAX)
        a.bind(keep)
        a.mov(x.RAX, x.RSP)
        a.store(bss(K_STACK_TOP), x.RAX)
        a.mov_imm(DEPTH_REG, 0)
        a.mov_imm(x.RBP, 0)
        a.call(self.fn_label[6])
        a.store(bss(K_ARGV), x.RAX)
        a.call(self.fn_label[self.p.entry])
        a.call(self.labels_["flush"])
        a.mov_imm(x.RDI, 0)
        self.exit_with(x.RDI)

    # Points d'entrée appelables par Windows (convention Microsoft x64 -> convention interne).
    func win_thunks():
        a := self.a
        k := 0
        while k < len(self.thunks):
            a.bind(self.thunks[k][1])
            for r in [x.RBP, x.RBX, x.RDI, x.RSI, x.R12, x.R13, x.R14, x.R15]:
                a.push(r)
            self.handler_push()
            self.handler_clear()
            a.mov(x.RDI, x.RCX)
            a.mov(x.RSI, x.RDX)
            a.mov(x.RDX, x.R8)
            a.mov(x.RCX, x.R9)
            a.mov_imm(x.RBP, 0)
            a.mov_imm(DEPTH_REG, 0)
            a.call(self.fn_label[self.thunks[k][0]])
            a.pop(x.RCX)
            self.handler_store(x.RCX)
            for r in [x.R15, x.R14, x.R13, x.R12, x.RSI, x.RDI, x.RBX, x.RBP]:
                a.pop(r)
            a.ret()
            k += 1

    # write_fd Windows : GetStdHandle ; console : UTF-8 -> UTF-16 par tranches + WriteConsoleW ; sinon WriteFile.
    func win_write_fd():
        a := self.a
        loop := a.new_label()
        file := a.new_label()
        done := a.new_label()
        small := a.new_label()
        back := a.new_label()
        cut := a.new_label()
        ok := a.new_label()
        for r in [x.RBX, x.R12, x.R13, x.R14]:
            a.push(r)
        a.mov(x.R12, x.RSI)
        a.mov(x.R13, x.RDX)
        a.mov(x.RBX, x.RSP)
        a.alu_ri(x.ALU_AND, x.RSP, -16)
        a.alu_ri(x.ALU_SUB, x.RSP, 80)
        a.store(x.at(x.RSP, 64), x.R10)
        a.mov_imm(x.RCX, -10)
        a.alu_rr(x.ALU_SUB, x.RCX, x.R10)
        self.win_call("GetStdHandle")
        a.mov(x.R14, x.RAX)
        if self.gui:
            have := a.new_label()
            none := a.new_label()
            fits := a.new_label()
            a.test(x.R14, x.R14)
            a.jcc(x.C_E, none)
            a.alu_ri(x.ALU_CMP, x.R14, -1)
            a.jcc(x.C_NE, have)
            a.bind(none)
            a.alu_mi(x.ALU_CMP, x.at(x.RSP, 64), 2)
            a.jcc(x.C_NE, done)
            a.mov_imm(x.RCX, WIN_ERR_CAP)
            a.alu_rm(x.ALU_SUB, x.RCX, bss(self.win_err_len))
            a.alu_rr(x.ALU_CMP, x.RCX, x.R13)
            a.jcc(x.C_BE, fits)
            a.mov(x.RCX, x.R13)
            a.bind(fits)
            a.mov_addr(x.RDI, x.S_BSS, self.win_err)
            a.alu_rm(x.ALU_ADD, x.RDI, bss(self.win_err_len))
            a.load(x.RAX, bss(self.win_err_len))
            a.alu_rr(x.ALU_ADD, x.RAX, x.RCX)
            a.store(bss(self.win_err_len), x.RAX)
            a.mov(x.RSI, x.R12)
            a.rep_movsb()
            a.jmp(done)
            a.bind(have)
        a.mov(x.RCX, x.R14)
        a.mov_addr(x.RDX, x.S_BSS, self.win_scratch)
        self.win_call("GetConsoleMode")
        a.raw([0x85, 0xC0])
        a.setcc(x.C_NE, x.RAX)
        a.movzx8(x.RAX, x.RAX)
        a.store(x.at(x.RSP, 48), x.RAX)
        a.bind(loop)
        a.test(x.R13, x.R13)
        a.jcc(x.C_E, done)
        a.alu_mi(x.ALU_CMP, x.at(x.RSP, 48), 0)
        a.jcc(x.C_E, file)
        a.mov(x.R8, x.R13)
        a.alu_ri(x.ALU_CMP, x.R8, WIN_WIDE_CHARS)
        a.jcc(x.C_BE, small)
        a.mov_imm(x.R8, WIN_WIDE_CHARS)
        a.bind(small)
        a.mov(x.R9, x.R8)
        a.bind(back)
        a.alu_rr(x.ALU_CMP, x.R8, x.R13)
        a.jcc(x.C_AE, cut)
        a.lea(x.RAX, x.at(x.R12))
        a.alu_rr(x.ALU_ADD, x.RAX, x.R8)
        a.load8zx(x.RAX, x.at(x.RAX))
        a.alu_ri(x.ALU_AND, x.RAX, 0xC0)
        a.alu_ri(x.ALU_CMP, x.RAX, 0x80)
        a.jcc(x.C_NE, cut)
        a.alu_ri(x.ALU_SUB, x.R8, 1)
        a.jcc(x.C_NE, back)
        a.mov(x.R8, x.R9)
        a.bind(cut)
        a.store(x.at(x.RSP, 56), x.R8)
        a.mov(x.R9, x.R8)
        a.mov(x.R8, x.R12)
        a.mov_imm(x.RCX, 65001)
        a.mov_imm(x.RDX, 0)
        a.mov_addr(x.RAX, x.S_BSS, self.win_wide)
        a.store(x.at(x.RSP, 32), x.RAX)
        a.mov_imm(x.RAX, WIN_WIDE_CHARS)
        a.store(x.at(x.RSP, 40), x.RAX)
        self.win_call("MultiByteToWideChar")
        a.raw([0x41, 0x89, 0xC0])
        a.mov(x.RCX, x.R14)
        a.mov_addr(x.RDX, x.S_BSS, self.win_wide)
        a.mov_addr(x.R9, x.S_BSS, self.win_scratch)
        a.store_imm(x.at(x.RSP, 32), 0)
        self.win_call("WriteConsoleW")
        a.load(x.RAX, x.at(x.RSP, 56))
        a.alu_rr(x.ALU_ADD, x.R12, x.RAX)
        a.alu_rr(x.ALU_SUB, x.R13, x.RAX)
        a.jmp(loop)
        a.bind(file)
        # mode texte de la CRT (état du runtime [1600], fixé par la VM écrite en ALEX) : LF -> CR LF
        raw := a.new_label()
        crlf := a.new_label()
        a.alu_mi(x.ALU_CMP, bss(K_RT_STATE + 1600), 0)
        a.jcc(x.C_E, raw)
        a.mov(x.RDI, x.R12)
        a.mov(x.RCX, x.R13)
        a.raw([0xB0, 0x0A])
        a.raw([0xF2, 0xAE])
        a.jcc(x.C_NE, raw)
        a.mov(x.R8, x.RDI)
        a.alu_rr(x.ALU_SUB, x.R8, x.R12)
        a.alu_ri(x.ALU_SUB, x.R8, 1)
        a.jcc(x.C_NE, ok)
        a.bind(crlf)
        a.mov_imm(x.RAX, 0x0A0D)
        a.store(x.at(x.RSP, 72), x.RAX)
        a.mov(x.RCX, x.R14)
        a.lea(x.RDX, x.at(x.RSP, 72))
        a.mov_imm(x.R8, 2)
        a.store_imm(bss(self.win_scratch), 0)
        a.mov_addr(x.R9, x.S_BSS, self.win_scratch)
        a.store_imm(x.at(x.RSP, 32), 0)
        self.win_call("WriteFile")
        a.raw([0x85, 0xC0])
        a.jcc(x.C_E, done)
        a.alu_ri(x.ALU_ADD, x.R12, 1)
        a.alu_ri(x.ALU_SUB, x.R13, 1)
        a.jmp(loop)
        a.bind(raw)
        a.mov(x.R8, x.R13)
        a.alu_ri(x.ALU_CMP, x.R8, 1 << 30)
        a.jcc(x.C_BE, ok)
        a.mov_imm(x.R8, 1 << 30)
        a.bind(ok)
        a.mov(x.RCX, x.R14)
        a.mov(x.RDX, x.R12)
        a.store_imm(bss(self.win_scratch), 0)
        a.mov_addr(x.R9, x.S_BSS, self.win_scratch)
        a.store_imm(x.at(x.RSP, 32), 0)
        self.win_call("WriteFile")
        a.raw([0x85, 0xC0])
        a.jcc(x.C_E, done)
        a.load32(x.RAX, bss(self.win_scratch))
        a.test(x.RAX, x.RAX)
        a.jcc(x.C_E, done)
        a.alu_rr(x.ALU_ADD, x.R12, x.RAX)
        a.alu_rr(x.ALU_SUB, x.R13, x.RAX)
        a.jmp(loop)
        a.bind(done)
        a.mov(x.RSP, x.RBX)
        for r in [x.R14, x.R13, x.R12, x.RBX]:
            a.pop(r)
        a.ret()

    # ------------------------------------------------------------------ runtime assembleur
    # ------------------------------------------------------------------ sans OS (--freestanding)
    # Une entrée de 16 octets par vecteur (code d'erreur fictif si le processeur n'en empile pas, numéro du
    # vecteur), puis une partie commune : registres non préservés, xmm0 / xmm1, chaîne des try isolée, cadre
    # fictif (adresse interrompue : traces), répartiteur Alex.
    func interrupt_stubs():
        a := self.a
        L := self.labels_
        p := self.p
        a.bind(L["isr_stubs"])
        v := 0
        while v < 256:
            start := a.size()
            err := v == 8 or v == 10 or v == 11 or v == 12 or v == 13 or v == 14 or v == 17 or v == 21 or v == 29 or v == 30
            if v == 8 or v == K_SHOOT_VECTOR:
                a.jmp(L["df_stub"] if v == 8 else L["shoot_stub"])
                while a.size() - start < 16:
                    a.raw([0xCC])
                v += 1
                continue
            if not err:
                a.raw([0x6A, 0x00])
            a.raw([0x68, v, 0, 0, 0])
            a.jmp(L["isr_common"])
            while a.size() - start < 16:
                a.raw([0xCC])
            if a.size() - start != 16:
                raise("RuntimeError", "entrée d'interruption > 16 octets")
            v += 1
        a.bind(L["isr_common"])
        k1 := a.new_label()
        held := a.new_label()
        k2 := a.new_label()
        k3 := a.new_label()
        k4 := a.new_label()
        a.raw([0xF6, 0x44, 0x24, 0x18, 0x03])
        a.jcc(x.C_E, k1)
        a.raw([0x0F, 0x01, 0xF8])
        a.bind(k1)
        for r in [x.RAX, x.RCX, x.RDX, x.RSI, x.RDI, x.R8, x.R9, x.R10, x.R11]:
            a.push(r)
        acquire := a.new_label()
        no_acquire := a.new_label()
        self.gs_load(x.RCX, K_CPU_INDEX)
        a.alu_ri(x.ALU_ADD, x.RCX, 1)
        a.mov_addr(x.RDX, x.S_BSS, K_BKL)
        a.mov_imm(x.RAX, 0)
        a.alu_rm(x.ALU_CMP, x.RCX, x.at(x.RDX))
        a.jcc(x.C_E, held)
        a.alu_mi(x.ALU_CMP, bss(K_PARALLEL), 0)
        a.jcc(x.C_E, acquire)
        a.load(x.RAX, x.at(x.RSP, 72))
        a.alu_ri(x.ALU_CMP, x.RAX, 64)
        a.jcc(x.C_AE, acquire)
        a.load(x.RDX, bss(K_FREE_VEC))
        a.raw([0x48, 0x0F, 0xA3, 0xC2])
        a.jcc(x.C_B, no_acquire)
        a.bind(acquire)
        a.call(L["bkl_acquire"])
        a.bind(no_acquire)
        a.mov_imm(x.RAX, 1)
        a.bind(held)
        a.push(x.RAX)
        a.push(x.R15)
        a.raw([0xF6, 0x44, 0x24, 0x70, 0x03])
        a.jcc(x.C_E, k2)
        a.mov_imm(x.R15, 0)
        a.bind(k2)
        self.gs_load(x.RAX, K_CPU_FROM_USER)
        a.push(x.RAX)
        a.load(x.RAX, x.at(x.RSP, 120))
        a.alu_ri(x.ALU_AND, x.RAX, 3)
        self.gs_store(K_CPU_FROM_USER, x.RAX)
        a.alu_ri(x.ALU_SUB, x.RSP, 32)
        a.raw([0x0F, 0x11, 0x04, 0x24])
        a.raw([0x0F, 0x11, 0x4C, 0x24, 0x10])
        self.handler_push()
        self.handler_clear()
        a.push_m(x.at(x.RSP, 152))
        a.push(x.RBP)
        a.mov(x.RBP, x.RSP)
        a.load(x.RDI, x.at(x.RSP, 152))
        a.load(x.RSI, x.at(x.RSP, 160))
        a.call(self.fn_label[p.irq_entry if p.irq_entry >= 0 else 4])
        a.mov(x.RSP, x.RBP)
        a.pop(x.RBP)
        a.alu_ri(x.ALU_ADD, x.RSP, 8)
        a.pop(x.RAX)
        self.handler_store(x.RAX)
        a.raw([0x0F, 0x10, 0x04, 0x24])
        a.raw([0x0F, 0x10, 0x4C, 0x24, 0x10])
        a.alu_ri(x.ALU_ADD, x.RSP, 32)
        a.pop(x.RAX)
        self.gs_store(K_CPU_FROM_USER, x.RAX)
        a.pop(x.R15)
        a.pop(x.RAX)
        a.test(x.RAX, x.RAX)
        a.jcc(x.C_E, k3)
        self.bkl_release_mine()
        a.bind(k3)
        for r in [x.R11, x.R10, x.R9, x.R8, x.RDI, x.RSI, x.RDX, x.RCX, x.RAX]:
            a.pop(r)
        a.alu_ri(x.ALU_ADD, x.RSP, 16)
        a.raw([0xF6, 0x44, 0x24, 0x08, 0x03])
        a.jcc(x.C_E, k4)
        a.raw([0x0F, 0x01, 0xF8])
        a.bind(k4)
        a.raw([0x48, 0xCF])
        # TLB shootdown (vecteur K_SHOOT_VECTOR) : cr3 rechargé, un accusé de moins, fin d'interruption à l'APIC.
        a.bind(L["shoot_stub"])
        sx2 := a.new_label()
        sdone := a.new_label()
        a.push(x.RAX)
        a.push(x.RCX)
        a.push(x.RDX)
        a.raw([0x0F, 0x20, 0xD8, 0x0F, 0x22, 0xD8])
        a.mov_addr(x.RCX, x.S_BSS, K_SHOOT_COUNT)
        a.raw([0xF0, 0x48, 0xFF, 0x09])
        a.load(x.RCX, bss(K_SHOOT_EOI))
        a.test(x.RCX, x.RCX)
        a.jcc(x.C_E, sx2)
        a.raw([0xC7, 0x01, 0x00, 0x00, 0x00, 0x00])
        a.jmp(sdone)
        a.bind(sx2)
        a.raw([0xB9, 0x0B, 0x08, 0x00, 0x00, 0x31, 0xC0, 0x31, 0xD2, 0x0F, 0x30])
        a.bind(sdone)
        a.pop(x.RDX)
        a.pop(x.RCX)
        a.pop(x.RAX)
        a.raw([0x48, 0xCF])
        # Double faute (pile IST 1) : message sur COM1 et sur la dernière ligne de l'écran texte, cœur arrêté.
        a.bind(L["df_stub"])
        dloop := a.new_label()
        ddone := a.new_label()
        a.raw([0xFA])
        a.mov_addr(x.RSI, x.S_RODATA, self.df_msg_off)
        a.raw([0x48, 0x8B, 0x0E])
        a.raw([0x48, 0x83, 0xC6, 0x08])
        a.raw([0xBF, 0x00, 0x8F, 0x0B, 0x00])
        a.bind(dloop)
        a.raw([0x48, 0x85, 0xC9])
        a.jcc(x.C_E, ddone)
        a.raw([0xBA, 0xFD, 0x03, 0x00, 0x00])
        a.raw([0xEC, 0xA8, 0x20, 0x74, 0xFB])
        a.raw([0xBA, 0xF8, 0x03, 0x00, 0x00])
        a.raw([0x8A, 0x06, 0xEE])
        a.raw([0xB4, 0x4F, 0x66, 0x89, 0x07])
        a.raw([0x48, 0x83, 0xC7, 0x02])
        a.raw([0x48, 0xFF, 0xC6, 0x48, 0xFF, 0xC9])
        a.jmp(dloop)
        a.bind(ddone)
        a.raw([0xF4])
        a.jmp(ddone)

    # Programmes en anneau 3 : appel système (syscall, convention Linux) vers hw._syscall sur la pile noyau du
    # programme ; entrée en mode utilisateur (iretq) et retour au noyau à la fin du programme.
    func user_mode_stubs():
        a := self.a
        L := self.labels_
        p := self.p
        a.bind(L["syscall_entry"])
        a.raw([0x0F, 0x01, 0xF8])
        self.gs_store(K_CPU_USER_RSP, x.RSP)
        self.gs_load(x.RSP, K_CPU_KERNEL_RSP)
        self.gs_push(K_CPU_USER_RSP)
        for r in [x.RCX, x.R11, x.RDI, x.RSI, x.RDX, x.R10, x.R8, x.R9, x.RBP, x.R15, x.RBX, x.R12, x.R13, x.R14]:
            a.push(r)
        a.push(x.RAX)
        skip := a.new_label()
        a.alu_mi(x.ALU_CMP, bss(K_PARALLEL), 0)
        a.jcc(x.C_NE, skip)
        a.call(L["bkl_acquire"])
        a.bind(skip)
        a.pop(x.RAX)
        a.load(x.RDX, x.at(x.RSP, 72))
        a.mov_imm(x.RBP, 0)
        a.mov_imm(x.R15, 0)
        a.alu_ri(x.ALU_SUB, x.RSP, 32)
        a.raw([0x0F, 0x11, 0x04, 0x24])
        a.raw([0x0F, 0x11, 0x4C, 0x24, 0x10])
        self.handler_push()
        self.handler_clear()
        a.mov(x.R9, x.R8)
        a.mov(x.R8, x.R10)
        a.mov(x.RCX, x.RDX)
        a.mov(x.RDX, x.RSI)
        a.mov(x.RSI, x.RDI)
        a.mov(x.RDI, x.RAX)
        if p.syscall_entry >= 0:
            a.call(self.fn_label[p.syscall_entry])
        else:
            a.mov_imm(x.RAX, -38)
        a.raw([0xFA])
        a.pop(x.RCX)
        self.handler_store(x.RCX)
        a.raw([0x0F, 0x10, 0x04, 0x24])
        a.raw([0x0F, 0x10, 0x4C, 0x24, 0x10])
        a.alu_ri(x.ALU_ADD, x.RSP, 32)
        self.bkl_release_mine()
        for r in [x.R14, x.R13, x.R12, x.RBX, x.R15, x.RBP, x.R9, x.R8, x.R10, x.RDX, x.RSI, x.RDI, x.R11, x.RCX]:
            a.pop(r)
        a.pop(x.RSP)
        a.raw([0x0F, 0x01, 0xF8])
        a.raw([0x48, 0x0F, 0x07])
        # enter_user(rdi = rip, rsi = rsp, rdx = entrée de la tâche) -> rax
        a.bind(L["enter_user"])
        for r in [x.RBP, x.RBX, x.R12, x.R13, x.R14, x.R15]:
            a.push(r)
        a.raw([0x9C])
        self.handler_push()
        a.store(x.at(x.RDX, 64), x.RSP)
        a.store(x.at(x.RDX, 0), x.RSP)
        self.gs_store(K_CPU_KERNEL_RSP, x.RSP)
        self.gs_load(x.RAX, K_CPU_TSS)
        a.store(x.at(x.RAX, 4), x.RSP)
        a.raw([0xFA])
        a.raw([0x6A, 0x1B])
        a.push(x.RSI)
        a.raw([0x68, 0x02, 0x02, 0x00, 0x00])
        a.raw([0x6A, 0x23])
        a.push(x.RDI)
        self.bkl_release_mine()
        for r in [x.RAX, x.RBX, x.RCX, x.RDX, x.RSI, x.RDI, x.RBP, x.R8, x.R9, x.R10, x.R11, x.R12, x.R13, x.R14, x.R15]:
            a.mov_imm(r, 0)
        a.raw([0x0F, 0x01, 0xF8])
        a.raw([0x48, 0xCF])
        # enter_user_frame(rsi = cadre de 18 mots, rdx = entrée de la tâche) : tous les registres rétablis (fork).
        a.bind(L["enter_user_frame"])
        for r in [x.RBP, x.RBX, x.R12, x.R13, x.R14, x.R15]:
            a.push(r)
        a.raw([0x9C])
        self.handler_push()
        a.store(x.at(x.RDX, 64), x.RSP)
        a.store(x.at(x.RDX, 0), x.RSP)
        self.gs_store(K_CPU_KERNEL_RSP, x.RSP)
        self.gs_load(x.RAX, K_CPU_TSS)
        a.store(x.at(x.RAX, 4), x.RSP)
        a.raw([0xFA])
        a.raw([0x6A, 0x1B])
        a.push_m(x.at(x.RSI, 8))
        a.load(x.RAX, x.at(x.RSI, 16))
        a.alu_ri(x.ALU_AND, x.RAX, 0xCD5)
        a.alu_ri(x.ALU_OR, x.RAX, 0x202)
        a.push(x.RAX)
        a.raw([0x6A, 0x23])
        a.push_m(x.at(x.RSI, 0))
        self.bkl_release_mine()
        regs := [x.RAX, x.RBX, x.RCX, x.RDX, x.RSI, x.RDI, x.RBP, x.R8, x.R9, x.R10, x.R11, x.R12, x.R13, x.R14, x.R15]
        i := 0
        while i < 15:
            if regs[i] != x.RSI:
                a.load(regs[i], x.at(x.RSI, 24 + 8 * i))
            i += 1
        a.load(x.RSI, x.at(x.RSI, 24 + 8 * 4))
        a.raw([0x0F, 0x01, 0xF8])
        a.raw([0x48, 0xCF])
        # leave_user(rdi = code, rsi = pile sauvée par enter_user)
        a.bind(L["leave_user"])
        a.mov(x.RSP, x.RSI)
        a.pop(x.RAX)
        self.handler_store(x.RAX)
        a.raw([0x9D])
        for r in [x.R15, x.R14, x.R13, x.R12, x.RBX, x.RBP]:
            a.pop(r)
        a.mov(x.RAX, x.RDI)
        a.ret()

    # Multiprocesseur : verrou global du noyau, attente d'interruption verrou rendu, configuration d'un cœur,
    # point d'entrée des autres cœurs.
    func smp_stubs():
        a := self.a
        L := self.labels_
        # bkl_acquire : prend le verrou pour ce cœur (attente active) ; détruit rax, rcx, rdx.
        # Toutes les 64 attentes, une écriture sur le port 0x80 (délai d'E/S classique, ~1 µs sur un vrai PC) fait
        # sortir le processeur virtuel vers l'hyperviseur : sans elle, un cœur qui attend ici (pause et lectures
        # mémoire, interruptions masquées) ne rend jamais la main à un hyperviseur qui n'intercepte pas PAUSE
        # (VirtualBox au-dessus de Hyper-V), et les minuteries de la machine, servies par le processeur virtuel 0,
        # s'arrêtent : plus de tic, et le cœur qui détient le verrou en attend un.
        a.bind(L["bkl_acquire"])
        retry := a.new_label()
        spin := a.new_label()
        done := a.new_label()
        a.alu_mi(x.ALU_CMP, bss(K_NO_BKL), 0)
        a.jcc(x.C_NE, done)
        self.gs_load(x.RCX, K_CPU_INDEX)
        a.alu_ri(x.ALU_ADD, x.RCX, 1)
        a.mov_addr(x.RDX, x.S_BSS, K_BKL)
        slow := a.new_label()
        got := a.new_label()
        a.mov_imm(x.RAX, 0)
        a.raw([0xF0, 0x48, 0x0F, 0xB1, 0x0A])
        a.jcc(x.C_E, done)
        a.bind(slow)
        a.raw([0xF0, 0x48, 0xFF, 0x42, 0x30])
        a.push(x.R8)
        a.mov_imm(x.R8, 64)
        a.bind(retry)
        self.gs_load(x.RCX, K_CPU_INDEX)
        a.alu_ri(x.ALU_ADD, x.RCX, 1)
        a.mov_imm(x.RAX, 0)
        a.raw([0xF0, 0x48, 0x0F, 0xB1, 0x0A])
        a.jcc(x.C_E, got)
        a.bind(spin)
        a.raw([0xF3, 0x90])
        no_exit := a.new_label()
        a.alu_ri(x.ALU_SUB, x.R8, 1)
        a.jcc(x.C_NE, no_exit)
        a.mov_imm(x.R8, 64)
        a.raw([0xE6, 0x80])          # out 0x80, al : sortie vers l'hyperviseur
        a.bind(no_exit)
        self.gs_load(x.RCX, K_CPU_INDEX)
        a.alu_ri(x.ALU_ADD, x.RCX, 1)
        a.alu_mi(x.ALU_CMP, bss(K_NO_BKL), 0)
        a.jcc(x.C_NE, got)
        nogc := a.new_label()
        a.alu_mi(x.ALU_CMP, bss(K_GC_REQUEST), 0)
        a.jcc(x.C_E, nogc)
        a.alu_rm(x.ALU_CMP, x.RCX, bss(K_GC_REQUEST))
        a.jcc(x.C_E, nogc)
        a.call(L["gc_park"])
        a.bind(nogc)
        a.alu_mi(x.ALU_CMP, x.at(x.RDX), 0)
        a.jcc(x.C_NE, spin)
        a.jmp(retry)
        a.bind(got)
        a.raw([0xF0, 0x48, 0xFF, 0x4A, 0x30])
        a.pop(x.R8)
        a.bind(done)
        a.ret()
        # park(rdi = case du pointeur de pile, rsi = 1 : attendre une interruption, 0 : céder un instant)
        a.bind(L["park"])
        relax := a.new_label()
        loop := a.new_label()
        reacq := a.new_label()
        full := a.new_label()
        a.test(x.RSI, x.RSI)
        a.jcc(x.C_NE, full)
        a.alu_mi(x.ALU_CMP, bss(K_SMP + 48), 0)
        a.jcc(x.C_NE, full)
        a.ret()
        a.bind(full)
        for r in [x.RBP, x.RBX, x.R12, x.R13, x.R14, x.R15]:
            a.push(r)
        a.raw([0x9C])
        self.handler_push()
        a.store(x.at(x.RDI, 0), x.RSP)
        nh := a.new_label()
        self.gs_load(x.RCX, K_CPU_INDEX)
        a.alu_ri(x.ALU_ADD, x.RCX, 1)
        a.mov_imm(x.RAX, 0)
        a.alu_rm(x.ALU_CMP, x.RCX, bss(K_BKL))
        a.jcc(x.C_NE, nh)
        a.mov_imm(x.RAX, 1)
        a.store_imm(bss(K_BKL), 0)
        a.bind(nh)
        a.push(x.RAX)
        a.test(x.RSI, x.RSI)
        a.jcc(x.C_E, relax)
        a.raw([0xFB, 0xF4, 0xFA])
        a.jmp(reacq)
        a.bind(relax)
        a.mov_imm(x.RCX, 16384)
        a.bind(loop)
        a.raw([0xF3, 0x90])
        a.alu_mi(x.ALU_CMP, bss(K_BKL), 0)
        a.jcc(x.C_NE, reacq)
        a.alu_ri(x.ALU_SUB, x.RCX, 1)
        a.jcc(x.C_NE, loop)
        a.bind(reacq)
        no := a.new_label()
        a.pop(x.RAX)
        a.test(x.RAX, x.RAX)
        a.jcc(x.C_E, no)
        a.call(L["bkl_acquire"])
        a.bind(no)
        a.pop(x.RAX)
        self.handler_store(x.RAX)
        a.raw([0x9D])
        for r in [x.R15, x.R14, x.R13, x.R12, x.RBX, x.RBP]:
            a.pop(r)
        a.ret()
        # cpu_setup(rdi = bloc du cœur) : GDT, cs et segments, TSS du cœur, IDT, gs, syscall / sysret.
        a.bind(L["cpu_setup"])
        reload := a.new_label()
        a.load(x.RAX, bss(K_SMP + 32))
        a.raw([0x0F, 0x01, 0x10])
        a.raw([0x6A, 0x08])
        a.mov_label_addr(x.RAX, reload)
        a.push(x.RAX)
        a.raw([0x48, 0xCB])
        a.bind(reload)
        a.raw([0x66, 0xB8, 0x10, 0x00, 0x8E, 0xD8, 0x8E, 0xC0, 0x8E, 0xD0])
        a.raw([0x31, 0xC0, 0x8E, 0xE0, 0x8E, 0xE8])
        a.load(x.RAX, x.at(x.RDI, K_CPU_TSS_SEL))
        a.raw([0x0F, 0x00, 0xD8])
        a.load(x.RAX, bss(K_SMP + 40))
        a.raw([0x0F, 0x01, 0x18])
        a.mov(x.RAX, x.RDI)
        self.wrmsr(0xC0000101)
        a.mov_imm(x.RAX, 0)
        self.wrmsr(0xC0000102)
        a.mov_imm(x.RCX, 0xC0000080)
        a.raw([0x0F, 0x32])
        a.alu_ri(x.ALU_OR, x.RAX, 1)
        a.raw([0x0F, 0x30])
        a.mov_imm(x.RCX, 0xC0000081)
        a.mov_imm(x.RAX, 0)
        a.mov_imm(x.RDX, 0x00100008)
        a.raw([0x0F, 0x30])
        a.mov_imm(x.RCX, 0xC0000082)
        a.mov_label_addr(x.RAX, L["syscall_entry"])
        a.mov_imm(x.RDX, 0)
        a.raw([0x0F, 0x30])
        a.mov_imm(x.RCX, 0xC0000084)
        a.mov_imm(x.RAX, 0x40700)
        a.mov_imm(x.RDX, 0)
        a.raw([0x0F, 0x30])
        a.ret()
        # Point d'entrée 64 bits d'un autre cœur (rdi = son bloc).
        a.bind(L["ap_entry"])
        a.load(x.RSP, x.at(x.RDI, K_CPU_BOOT_STACK))
        a.call(L["cpu_setup"])
        a.store_imm(x.at(x.RDI, K_CPU_ONLINE), 1)
        a.mov_addr(x.RAX, x.S_BSS, K_SMP + 8)
        a.raw([0xF0, 0x48, 0xFF, 0x00])
        a.call(L["bkl_acquire"])
        a.mov_imm(x.R15, 0)
        a.mov_imm(x.RBP, 0)
        a.load(x.RSP, x.at(x.RDI, K_CPU_IDLE_SP))
        a.raw([0x9D])
        for r in [x.R15, x.R14, x.R13, x.R12, x.RBX, x.RBP]:
            a.pop(r)
        a.ret()

    # Noyau parallèle : verrou du tampon de sortie, arrêt d'un cœur pendant le GC d'un autre.
    func parallel_stubs():
        a := self.a
        L := self.labels_
        a.bind(L["out_lock"])
        done := a.new_label()
        retry := a.new_label()
        spin := a.new_label()
        got := a.new_label()
        a.alu_mi(x.ALU_CMP, bss(K_PARALLEL), 0)
        a.jcc(x.C_E, done)
        a.push(x.RAX)
        a.push(x.RCX)
        a.push(x.RDX)
        self.gs_load(x.RCX, K_CPU_INDEX)
        a.alu_ri(x.ALU_ADD, x.RCX, 1)
        a.mov_addr(x.RDX, x.S_BSS, K_OUT_LOCK)
        a.bind(retry)
        a.mov_imm(x.RAX, 0)
        a.raw([0xF0, 0x48, 0x0F, 0xB1, 0x0A])
        a.jcc(x.C_E, got)
        a.bind(spin)
        a.raw([0xF3, 0x90])
        a.alu_mi(x.ALU_CMP, x.at(x.RDX), 0)
        a.jcc(x.C_NE, spin)
        a.jmp(retry)
        a.bind(got)
        a.pop(x.RDX)
        a.pop(x.RCX)
        a.pop(x.RAX)
        a.bind(done)
        a.ret()
        a.bind(L["out_unlock"])
        done2 := a.new_label()
        a.alu_mi(x.ALU_CMP, bss(K_PARALLEL), 0)
        a.jcc(x.C_E, done2)
        a.store_imm(bss(K_OUT_LOCK), 0)
        a.bind(done2)
        a.ret()
        a.bind(L["gc_park"])
        wait := a.new_label()
        for r in [x.RBX, x.RBP, x.R12, x.R13, x.R14, x.R15, x.RAX, x.RCX, x.RDX, x.RSI, x.RDI, x.R8, x.R9, x.R10, x.R11]:
            a.push(r)
        a.raw([0x9C])
        self.gs_store(K_CPU_GC_SP, x.RSP)
        self.gs_imm(K_CPU_GC_STATE, 1)
        a.mov_addr(x.RDX, x.S_BSS, K_GC_REQUEST)
        a.bind(wait)
        a.raw([0xF3, 0x90])
        a.alu_mi(x.ALU_CMP, x.at(x.RDX), 0)
        a.jcc(x.C_NE, wait)
        self.gs_imm(K_CPU_GC_STATE, 0)
        a.raw([0x9D])
        for r in [x.R11, x.R10, x.R9, x.R8, x.RDI, x.RSI, x.RDX, x.RCX, x.RAX, x.R15, x.R14, x.R13, x.R12, x.RBP, x.RBX]:
            a.pop(r)
        a.ret()

    # Point d'entrée 64 bits (après l'amorçage 32 bits de l'image Multiboot) : segments, pile, port série, GDT,
    # TSS, IDT, cœur 0, tas.
    func start_freestanding():
        a := self.a
        p := self.p
        a.raw([0x66, 0xB8, 0x10, 0x00])
        a.raw([0x8E, 0xD8, 0x8E, 0xC0, 0x8E, 0xD0, 0x8E, 0xE0, 0x8E, 0xE8])
        a.mov_addr(x.RSP, x.S_BSS, self.stack_top)
        a.mov(x.RCX, x.RSP)
        a.alu_ri(x.ALU_ADD, x.RSP, 0x1FFFFFF)
        a.alu_ri(x.ALU_AND, x.RSP, -0x2000000)
        room := a.new_label()
        a.mov(x.RDX, x.RSP)
        a.alu_rr(x.ALU_SUB, x.RDX, x.RCX)
        a.alu_ri(x.ALU_CMP, x.RDX, K_BOOT_STACK)
        a.jcc(x.C_AE, room)
        a.alu_ri(x.ALU_ADD, x.RSP, 0x2000000)
        a.bind(room)
        for io in [[0x3F9, 0], [0x3FB, 0x80], [0x3F8, 3], [0x3F9, 0], [0x3FB, 3], [0x3FA, 0xC1], [0x3FC, 0x0B]]:
            a.mov_imm(x.RDX, io[0])
            a.mov_imm(x.RAX, io[1])
            a.raw([0xEE])
        a.mov_addr(x.RAX, x.S_BSS, self.fs_argv)
        a.store(bss(K_ARGV), x.RAX)
        a.mov_addr(x.RAX, x.S_BSS, K_CPU0)
        a.store(bss(K_CPU_BLOCKS), x.RAX)
        a.load(x.RAX, bss(self.mb_info))
        a.mov_imm(x.RCX, 0xFFFFFFFF)
        a.alu_rr(x.ALU_AND, x.RAX, x.RCX)
        a.store(bss(K_BOOT_INFO), x.RAX)
        # GDT définitive : noyau 0x08 / 0x10, utilisateur 0x18 / 0x20, puis la TSS de chaque cœur.
        a.mov_addr(x.RDI, x.S_BSS, self.gdt)
        descs := [0, 0x00AF9A000000FFFF, 0x00CF92000000FFFF, 0x00CFF2000000FFFF, 0x00AFFA000000FFFF]
        k := 0
        while k < 5:
            a.mov_imm(x.RAX, descs[k])
            a.store(x.at(x.RDI, 8 * k), x.RAX)
            k += 1
        cpu := 0
        while cpu < K_MAX_CPUS:
            a.mov_addr(x.RSI, x.S_BSS, self.tss + K_TSS_STRIDE * cpu)
            a.mov_imm(x.RAX, 0x67 | (0x89 << 40))
            a.mov(x.RDX, x.RSI)
            a.alu_ri(x.ALU_AND, x.RDX, 0xFFFF)
            a.mov_imm(x.R8, 1 << 16)
            a.imul(x.RDX, x.R8)
            a.alu_rr(x.ALU_OR, x.RAX, x.RDX)
            a.mov(x.RDX, x.RSI)
            a.alu_ri(x.ALU_AND, x.RDX, 0xFF0000)
            a.imul(x.RDX, x.R8)
            a.alu_rr(x.ALU_OR, x.RAX, x.RDX)
            a.mov(x.RDX, x.RSI)
            a.mov_imm(x.R9, 0xFF000000)
            a.alu_rr(x.ALU_AND, x.RDX, x.R9)
            a.mov_imm(x.R8, 1 << 32)
            a.imul(x.RDX, x.R8)
            a.alu_rr(x.ALU_OR, x.RAX, x.RDX)
            a.store(x.at(x.RDI, 40 + 16 * cpu), x.RAX)
            a.store_imm(x.at(x.RDI, 48 + 16 * cpu), 0)
            a.mov_imm(x.RAX, 104)
            a.store16(x.at(x.RSI, 102), x.RAX)
            a.mov_addr(x.RAX, x.S_BSS, self.ist + K_IST_SIZE * (cpu + 1))
            a.store(x.at(x.RSI, 36), x.RAX)
            cpu += 1
        a.mov_imm(x.RAX, 40 + 16 * K_MAX_CPUS - 1)
        a.store16(x.at(x.RDI, 40 + 16 * K_MAX_CPUS), x.RAX)
        a.store(x.at(x.RDI, 42 + 16 * K_MAX_CPUS), x.RDI)
        a.lea(x.RAX, x.at(x.RDI, 40 + 16 * K_MAX_CPUS))
        a.store(bss(K_SMP + 32), x.RAX)
        a.mov_addr(x.RAX, x.S_BSS, self.tss)
        a.store(bss(K_SMP + 24), x.RAX)
        a.mov_addr(x.RAX, x.S_BSS, self.idt + 4096)
        a.store(bss(K_SMP + 40), x.RAX)
        # PIC 8259 : toutes les lignes masquées.
        for port in [0x21, 0xA1]:
            a.mov_imm(x.RDX, port)
            a.mov_imm(x.RAX, 0xFF)
            a.raw([0xEE])
        # IDT : 256 portes d'interruption (sélecteur 0x08, présent, DPL 0) vers les entrées de interrupt_stubs.
        loop := a.new_label()
        a.mov_label_addr(x.RSI, self.labels_["isr_stubs"])
        a.mov_addr(x.RDI, x.S_BSS, self.idt)
        a.mov_imm(x.RCX, 256)
        a.mov_imm(x.R8, 1 << 32)
        a.mov_imm(x.R9, 0xFFFF0000)
        a.bind(loop)
        a.mov(x.RAX, x.RSI)
        a.alu_ri(x.ALU_AND, x.RAX, 0xFFFF)
        a.mov_imm(x.RDX, 0x8E0000080000)
        a.alu_rr(x.ALU_OR, x.RAX, x.RDX)
        a.mov(x.RDX, x.RSI)
        a.alu_rr(x.ALU_AND, x.RDX, x.R9)
        a.imul(x.RDX, x.R8)
        a.alu_rr(x.ALU_OR, x.RAX, x.RDX)
        a.store(x.at(x.RDI, 0), x.RAX)
        a.store_imm(x.at(x.RDI, 8), 0)
        a.alu_ri(x.ALU_ADD, x.RSI, 16)
        a.alu_ri(x.ALU_ADD, x.RDI, 16)
        a.alu_ri(x.ALU_SUB, x.RCX, 1)
        a.jcc(x.C_NE, loop)
        a.mov_addr(x.RDI, x.S_BSS, self.idt + 16 * 8)
        a.load(x.RAX, x.at(x.RDI, 0))
        a.mov_imm(x.RDX, 1 << 32)
        a.alu_rr(x.ALU_OR, x.RAX, x.RDX)
        a.store(x.at(x.RDI, 0), x.RAX)
        a.mov_addr(x.RAX, x.S_BSS, self.idt + 4096)
        a.mov_imm(x.RDX, 4095)
        a.store16(x.at(x.RAX, 0), x.RDX)
        a.mov_addr(x.RDX, x.S_BSS, self.idt)
        a.store(x.at(x.RAX, 2), x.RDX)
        # Cœur 0 : bloc (gs), verrou global détenu, cr3 du noyau ; puis GDT, TSS, IDT, appels système.
        a.mov_addr(x.RDI, x.S_BSS, K_CPU0)
        a.store(x.at(x.RDI, K_CPU_SELF), x.RDI)
        a.mov_addr(x.RAX, x.S_BSS, self.tss)
        a.store(x.at(x.RDI, K_CPU_TSS), x.RAX)
        a.store_imm(x.at(x.RDI, K_CPU_TSS_SEL), 0x28)
        a.store_imm(x.at(x.RDI, K_CPU_ONLINE), 1)
        a.store_imm(bss(K_SMP + 8), 1)
        a.store_imm(bss(K_BKL), 1)
        a.raw([0x0F, 0x20, 0xD8])
        a.store(bss(K_SMP + 16), x.RAX)
        a.call(self.labels_["cpu_setup"])
        # Tas : de la fin du bss arrondie à 32 Mio jusqu'à la fin de la mémoire (Multiboot mem_upper, 128 Mio par
        # défaut, au plus 1 Gio).
        a.mov_addr(x.RAX, x.S_BSS, self.stack_top)
        a.mov(x.RCX, x.RAX)
        a.alu_ri(x.ALU_ADD, x.RAX, 0x1FFFFFF)
        a.alu_ri(x.ALU_AND, x.RAX, -0x2000000)
        room2 := a.new_label()
        a.mov(x.RDX, x.RAX)
        a.alu_rr(x.ALU_SUB, x.RDX, x.RCX)
        a.alu_ri(x.ALU_CMP, x.RDX, K_BOOT_STACK)
        a.jcc(x.C_AE, room2)
        a.alu_ri(x.ALU_ADD, x.RAX, 0x2000000)
        a.bind(room2)
        a.store(bss(K_RT_STATE + 880), x.RAX)
        no_info := a.new_label()
        capped := a.new_label()
        a.mov_imm(x.RCX, 128 << 20)
        a.load(x.RAX, bss(self.mb_info))
        a.test(x.RAX, x.RAX)
        a.jcc(x.C_E, no_info)
        a.load(x.RDX, x.at(x.RAX, 0))
        a.alu_ri(x.ALU_AND, x.RDX, 1)
        a.jcc(x.C_E, no_info)
        a.load(x.RDX, x.at(x.RAX, 8))
        a.mov_imm(x.R8, 0xFFFFFFFF)
        a.alu_rr(x.ALU_AND, x.RDX, x.R8)
        a.alu_ri(x.ALU_ADD, x.RDX, 1024)
        a.mov_imm(x.R8, 1024)
        a.imul(x.RDX, x.R8)
        a.mov(x.RCX, x.RDX)
        a.bind(no_info)
        a.mov_imm(x.RDX, 1 << 30)
        a.alu_rr(x.ALU_CMP, x.RCX, x.RDX)
        a.jcc(x.C_BE, capped)
        a.mov(x.RCX, x.RDX)
        a.bind(capped)
        a.store(bss(K_RT_STATE + 888), x.RCX)
        a.mov(x.RAX, x.RSP)
        a.store(bss(K_STACK_TOP), x.RAX)
        a.mov_imm(DEPTH_REG, 0)
        a.mov_imm(x.RBP, 0)
        a.call(self.fn_label[p.entry])
        a.call(self.labels_["flush"])
        a.mov_imm(x.RDI, 0)
        self.exit_with(x.RDI)

    func runtime():
        a := self.a
        L := self.labels_
        a.bind(L["write_fd"])
        if self.win:
            self.win_write_fd()
        elif self.fs:
            # port série COM1 (0x3F8) : sorties standard et d'erreur confondues
            top := a.new_label()
            wait := a.new_label()
            done := a.new_label()
            a.mov(x.RCX, x.RDX)
            a.bind(top)
            a.test(x.RCX, x.RCX)
            a.jcc(x.C_E, done)
            a.bind(wait)
            a.mov_imm(x.RDX, 0x3FD)
            a.raw([0xEC])
            a.raw([0xA8, 0x20])
            a.jcc(x.C_E, wait)
            a.mov_imm(x.RDX, 0x3F8)
            a.load8zx(x.RAX, x.at(x.RSI))
            a.raw([0xEE])
            a.alu_ri(x.ALU_ADD, x.RSI, 1)
            a.alu_ri(x.ALU_SUB, x.RCX, 1)
            a.jmp(top)
            a.bind(done)
            a.ret()
        else:
            top := a.new_label()
            done := a.new_label()
            a.bind(top)
            a.test(x.RDX, x.RDX)
            a.jcc(x.C_E, done)
            a.mov_imm(x.RAX, 1)
            a.mov(x.RDI, x.R10)
            a.syscall()
            a.test(x.RAX, x.RAX)
            a.jcc(x.C_LE, done)
            a.alu_rr(x.ALU_ADD, x.RSI, x.RAX)
            a.alu_rr(x.ALU_SUB, x.RDX, x.RAX)
            a.jmp(top)
            a.bind(done)
            a.ret()
        # write_err(rsi = chaîne)
        a.bind(L["write_err"])
        a.load(x.RDX, x.at(x.RSI))
        a.alu_ri(x.ALU_ADD, x.RSI, 8)
        a.mov_imm(x.R10, 2)
        a.jmp(L["write_fd"])
        # flush()
        a.bind(L["flush"])
        a.load(x.RDX, bss(K_OUT_LEN))
        a.mov_addr(x.RSI, x.S_BSS, self.buf_off)
        a.mov_imm(x.R10, 1)
        a.call(L["write_fd"])
        a.store_imm(bss(K_OUT_LEN), 0)
        a.ret()
        # write(rsi, rdx)
        a.bind(L["write"])
        fits := a.new_label()
        a.load(x.RAX, bss(K_OUT_LEN))
        a.alu_rr(x.ALU_ADD, x.RAX, x.RDX)
        a.alu_ri(x.ALU_CMP, x.RAX, BUF_SIZE)
        a.jcc(x.C_BE, fits)
        a.push(x.RSI)
        a.push(x.RDX)
        a.call(L["flush"])
        a.pop(x.RDX)
        a.pop(x.RSI)
        a.alu_ri(x.ALU_CMP, x.RDX, BUF_SIZE)
        a.jcc(x.C_BE, fits)
        a.mov_imm(x.R10, 1)
        a.jmp(L["write_fd"])
        a.bind(fits)
        a.mov_addr(x.RDI, x.S_BSS, self.buf_off)
        a.alu_rm(x.ALU_ADD, x.RDI, bss(K_OUT_LEN))
        a.load(x.RAX, bss(K_OUT_LEN))
        a.alu_rr(x.ALU_ADD, x.RAX, x.RDX)
        a.store(bss(K_OUT_LEN), x.RAX)
        a.mov(x.RCX, x.RDX)
        a.rep_movsb()
        a.ret()
        # newline()
        a.bind(L["newline"])
        ok := a.new_label()
        a.load(x.RAX, bss(K_OUT_LEN))
        a.alu_ri(x.ALU_CMP, x.RAX, BUF_SIZE)
        a.jcc(x.C_B, ok)
        a.call(L["flush"])
        a.mov_imm(x.RAX, 0)
        a.bind(ok)
        a.mov_addr(x.RDI, x.S_BSS, self.buf_off)
        a.alu_rr(x.ALU_ADD, x.RDI, x.RAX)
        a.mov_imm(x.RCX, 10)
        a.store8(x.at(x.RDI), x.RCX)
        a.alu_ri(x.ALU_ADD, x.RAX, 1)
        a.store(bss(K_OUT_LEN), x.RAX)
        a.ret()
        # print_str(rsi)
        a.bind(L["print_str"])
        a.load(x.RDX, x.at(x.RSI))
        a.alu_ri(x.ALU_ADD, x.RSI, 8)
        a.call(L["write"])
        a.jmp(L["newline"])
        # digits(rdi)
        a.bind(L["digits"])
        pos := a.new_label()
        digit := a.new_label()
        done2 := a.new_label()
        a.lea(x.R8, x.at(x.RSP, 40))
        a.mov(x.RAX, x.RDI)
        a.mov(x.R9, x.RDI)
        a.test(x.RAX, x.RAX)
        a.jcc(x.C_NS, pos)
        a.neg(x.RAX)
        a.bind(pos)
        a.mov_imm(x.RCX, 10)
        a.bind(digit)
        a.mov_imm(x.RDX, 0)
        a.divu(x.RCX)
        a.alu_ri(x.ALU_ADD, x.RDX, 48)
        a.alu_ri(x.ALU_SUB, x.R8, 1)
        a.store8(x.at(x.R8), x.RDX)
        a.test(x.RAX, x.RAX)
        a.jcc(x.C_NE, digit)
        a.test(x.R9, x.R9)
        a.jcc(x.C_NS, done2)
        a.alu_ri(x.ALU_SUB, x.R8, 1)
        a.mov_imm(x.RDX, 45)
        a.store8(x.at(x.R8), x.RDX)
        a.bind(done2)
        a.mov(x.RSI, x.R8)
        a.lea(x.RDX, x.at(x.RSP, 40))
        a.alu_rr(x.ALU_SUB, x.RDX, x.R8)
        a.ret()
        # print_int(rdi)
        a.bind(L["print_int"])
        a.alu_ri(x.ALU_SUB, x.RSP, 32)
        a.call(L["digits"])
        a.call(L["write"])
        a.alu_ri(x.ALU_ADD, x.RSP, 32)
        a.jmp(L["newline"])
        # int_to_str(rdi) -> rax
        a.bind(L["int_to_str"])
        a.alu_ri(x.ALU_SUB, x.RSP, 32)
        a.call(L["digits"])
        a.push(x.RSI)
        a.push(x.RDX)
        a.lea(x.RDI, x.at(x.RDX, 8))
        a.mov_imm(x.RSI, 1)
        a.call(self.fn_label[2])
        a.pop(x.RDX)
        a.pop(x.RSI)
        a.store(x.at(x.RAX), x.RDX)
        a.lea(x.RDI, x.at(x.RAX, 8))
        a.mov(x.RCX, x.RDX)
        a.rep_movsb()
        a.alu_ri(x.ALU_ADD, x.RSP, 32)
        a.ret()
        # fail(rsi = message)
        a.bind(L["fail"])
        walk := a.new_label()
        done3 := a.new_label()
        uncaught := a.new_label()
        self.handler_cmp_zero()
        a.jcc(x.C_E, uncaught)
        a.mov(x.RDI, x.RSI)
        a.call(self.fn_label[3])
        a.bind(uncaught)
        a.mov(x.R12, x.RSI)
        a.load(x.R13, x.at(x.RSP))
        a.mov(x.R14, x.RBP)
        a.call(L["flush"])
        a.mov_addr(x.RDI, x.S_BSS, self.trace_off)
        a.store(x.at(x.RDI, 8), x.R13)
        a.mov_imm(x.RCX, 1)
        a.bind(walk)
        a.test(x.R14, x.R14)
        a.jcc(x.C_E, done3)
        a.alu_ri(x.ALU_CMP, x.RCX, TRACE_CAP - 1)
        a.jcc(x.C_AE, done3)
        a.load(x.RAX, x.at(x.R14, 8))
        a.alu_ri(x.ALU_ADD, x.RCX, 1)
        a.store_idx(x.RDI, x.RCX, x.RAX)
        a.load(x.R14, x.at(x.R14))
        a.jmp(walk)
        a.bind(done3)
        a.store(x.at(x.RDI), x.RCX)
        a.mov_imm(DEPTH_REG, 0)
        a.mov(x.RSI, x.RDI)
        a.mov(x.RDI, x.R12)
        a.call(self.fn_label[1])
        a.mov_imm(x.RDI, 1)
        self.exit_with(x.RDI)
        # switch(rdi, rsi)
        a.bind(L["switch"])
        for r in [x.RBP, x.RBX, x.R12, x.R13, x.R14, x.R15]:
            a.push(r)
        a.raw([0x9C])
        a.store(x.at(x.RDI, 0), x.RSP)
        a.mov(x.RSP, x.RSI)
        a.raw([0x9D])
        for r in [x.R15, x.R14, x.R13, x.R12, x.RBX, x.RBP]:
            a.pop(r)
        a.ret()
        a.bind(L["fiber_entry"])
        a.call(self.fn_label[5])
        a.raw([0x0F, 0x0B])
        if self.fs and not self.uefi:
            # UEFI : IDT, GDT et cœurs restent au micrologiciel
            self.interrupt_stubs()
            self.user_mode_stubs()
            self.smp_stubs()
            self.parallel_stubs()
        # pow(rdi, rsi)
        a.bind(L["pow"])
        top2 := a.new_label()
        skip := a.new_label()
        done4 := a.new_label()
        negl := a.new_label()
        a.test(x.RSI, x.RSI)
        a.jcc(x.C_S, negl)
        a.mov_imm(x.RAX, 1)
        a.bind(top2)
        a.test(x.RSI, x.RSI)
        a.jcc(x.C_E, done4)
        a.mov(x.RCX, x.RSI)
        a.alu_ri(x.ALU_AND, x.RCX, 1)
        a.jcc(x.C_E, skip)
        a.imul(x.RAX, x.RDI)
        a.bind(skip)
        a.imul(x.RDI, x.RDI)
        a.shr_imm(x.RSI, 1)
        a.jmp(top2)
        a.bind(done4)
        a.ret()
        a.bind(negl)
        a.load(x.RAX, x.at(x.RSP))
        a.jmp(self.msg_stub(MSG_POW_NEGATIVE))

    func exit_with(code):
        if self.win:
            a := self.a
            if code != x.R12:
                a.mov(x.R12, code)
            a.alu_ri(x.ALU_AND, x.RSP, -16)
            a.alu_ri(x.ALU_SUB, x.RSP, 48)
            if self.gui:
                none := a.new_label()
                a.load(x.R9, bss(self.win_err_len))
                a.test(x.R9, x.R9)
                a.jcc(x.C_E, none)
                a.mov_imm(x.RCX, 65001)
                a.mov_imm(x.RDX, 0)
                a.mov_addr(x.R8, x.S_BSS, self.win_err)
                a.mov_addr(x.RAX, x.S_BSS, self.win_wide)
                a.store(x.at(x.RSP, 32), x.RAX)
                a.mov_imm(x.RAX, WIN_WIDE_CHARS - 1)
                a.store(x.at(x.RSP, 40), x.RAX)
                self.win_call("MultiByteToWideChar")
                a.raw([0x89, 0xC0])
                a.mov_addr(x.RCX, x.S_BSS, self.win_wide)
                a.raw([0x66, 0xC7, 0x04, 0x41, 0x00, 0x00])
                a.mov_imm(x.RCX, 0)
                a.mov_addr(x.RDX, x.S_BSS, self.win_wide)
                a.mov_addr(x.R8, x.S_RODATA, self.win_err_title + 8)
                a.mov_imm(x.R9, 0x10)
                self.win_call("user32.dll!MessageBoxW")
                a.bind(none)
            a.mov(x.RCX, x.R12)
            self.win_call("ExitProcess")
            a.raw([0x0F, 0x0B])
            return
        if self.uefi:
            # retour au micrologiciel (pile et registres de l'entrée) ; code non nul -> statut d'erreur EFI
            a := self.a
            ok := a.new_label()
            a.mov(x.RAX, code)
            a.test(x.RAX, x.RAX)
            a.jcc(x.C_E, ok)
            a.mov_imm(x.RDX, -9223372036854775807 - 1)
            a.alu_rr(x.ALU_OR, x.RAX, x.RDX)
            a.bind(ok)
            a.load(x.RSP, bss(K_UEFI_RSP))
            a.push_m(bss(K_UEFI_FLAGS))
            a.raw([0x9D])
            for r in [x.R15, x.R14, x.R13, x.R12, x.RSI, x.RDI, x.RBP, x.RBX]:
                a.pop(r)
            a.ret()
            return
        if self.fs:
            # isa-debug-exit de QEMU (port 0xF4), puis arrêt du processeur
            a := self.a
            stop := a.new_label()
            a.mov(x.RAX, code)
            a.mov_imm(x.RDX, 0xF4)
            a.raw([0xEF])
            a.bind(stop)
            a.raw([0xFA, 0xF4])
            a.jmp(stop)
            return
        if code != x.RDI:
            self.a.mov(x.RDI, code)
        # exit_group (comme AArch64) : termine TOUT le processus, y compris les fils créés par une bibliothèque
        # chargée par ffi (pilote OpenGL, son) ; `exit` (60) ne terminait que le fil appelant et laissait le
        # processus vivant
        self.a.mov_imm(x.RAX, 231)
        self.a.syscall()

    # ------------------------------------------------------------------ emplacements
    func imm32(v):
        if v < 0 or v >= len(self.const_val) or not self.is_const[v]:
            return null
        c := self.const_val[v]
        if c < INT32_MIN or c > INT32_MAX:
            return null
        return c

    func in_reg(v):
        if v < 0 or self.reg_of[v] < 0:
            return -1
        return self.reg_of[v]

    func save_slot(k):
        return -8 * (self.frame_slots + k + 1)

    func ld(dst, v):
        p := self.pending
        self.pending = -1
        if p >= 0 and v == p:
            self.a.mov(dst, x.RAX)
            return
        r := self.in_reg(v)
        if r >= 0:
            self.a.mov(dst, r)
            return
        c := self.imm32(v)
        if c != null:
            self.a.mov_imm(dst, c)
        else:
            self.a.load(dst, self.slot(v))

    func st(v, src):
        r := self.in_reg(v)
        if r >= 0:
            self.a.mov(r, src)
            return
        if src == x.RAX:
            self.forward = v
            if self.next_ != null and self.uses[v] == 1 and _first_load(self.next_) == v:
                return
        self.a.store(self.slot(v), src)

    func alu_v(op, dst, v):
        r := self.in_reg(v)
        if r >= 0:
            self.a.alu_rr(op, dst, r)
            return
        c := self.imm32(v)
        if c != null:
            self.a.alu_ri(op, dst, c)
        else:
            self.a.alu_rm(op, dst, self.slot(v))

    func fld(xmm, v):
        r := self.in_reg(v)
        if r >= 0:
            self.a.movq_to_xmm(xmm, r)
        else:
            self.a.movsd_load(xmm, self.slot(v))

    func fst(v, xmm):
        r := self.in_reg(v)
        if r >= 0:
            self.a.movq_from_xmm(r, xmm)
        else:
            self.a.movsd_store(self.slot(v), xmm)

    # Arguments d'un appel ; renvoie le nombre de mots empilés.
    func call_args(args, hidden):
        al := []
        if hidden >= 0:
            append(al, hidden)
        for v in args:
            append(al, v)
        stacked := len(al) - REG_ARGS if len(al) > REG_ARGS else 0
        i := len(al)
        while i > REG_ARGS:
            self.push_v(al[i - 1])
            i -= 1
        self.pending = -1
        i = 0
        while i < len(al) and i < REG_ARGS:
            self.ld(ARG_REGS[i], al[i])
            i += 1
        return stacked

    func push_v(v):
        r := self.in_reg(v)
        if r >= 0:
            self.a.push(r)
        else:
            self.a.push_m(self.slot(v))

    func float_compare(ins):
        a := self.a
        op := ins.op
        swap := op == ir.FLT or op == ir.FGE
        self.fld(XMM0, ins.b if swap else ins.a)
        self.fld(XMM1, ins.a if swap else ins.b)
        a.ucomisd_rr(XMM0, XMM1)
        if op == ir.FLT or op == ir.FGT:
            a.setcc(x.C_A, x.RAX)
        elif op == ir.FLE or op == ir.FGE:
            a.setcc(x.C_BE, x.RAX)
        elif op == ir.FEQ or op == ir.FNE:
            a.setcc(x.C_E if op == ir.FEQ else x.C_NE, x.RAX)
            a.setcc(x.C_NP if op == ir.FEQ else x.C_P, x.RCX)
            a.movzx8(x.RAX, x.RAX)
            a.movzx8(x.RCX, x.RCX)
            a.alu_rr(x.ALU_AND if op == ir.FEQ else x.ALU_OR, x.RAX, x.RCX)
            self.st(ins.dst, x.RAX)
            return
        else:
            return
        a.movzx8(x.RAX, x.RAX)
        self.st(ins.dst, x.RAX)

    func _binop(ins, op):
        self.ld(x.RAX, ins.a)
        self.alu_v(op, x.RAX, ins.b)
        self.st(ins.dst, x.RAX)

    func _fop(ins, code):
        self.fld(XMM0, ins.a)
        self.fld(XMM1, ins.b)
        self.a.sse_op_rr(code, XMM0, XMM1)
        self.fst(ins.dst, XMM0)

    func _compare(ins, c):
        self.ld(x.RAX, ins.a)
        self.alu_v(x.ALU_CMP, x.RAX, ins.b)
        self.a.setcc(c, x.RAX)
        self.a.movzx8(x.RAX, x.RAX)
        self.st(ins.dst, x.RAX)

    func instruction(ins, labels):
        a := self.a
        op := ins.op
        self.pending = -1 if op == ir.LABEL else self.forward
        self.forward = -1
        if op != ir.LABEL:
            self.mark_line(ins.line)
        self.cur_line = ins.line
        L := self.labels_
        if op == ir.CONST:
            r := self.in_reg(ins.dst)
            if r >= 0:
                a.mov_imm(r, ins.imm)
            elif self.is_const[ins.dst] and not self.need_slot[ins.dst]:
                pass_ := 0
            elif ins.imm >= INT32_MIN and ins.imm <= INT32_MAX:
                a.store_imm(self.slot(ins.dst), ins.imm)
            else:
                a.mov_imm(x.RAX, ins.imm)
                a.store(self.slot(ins.dst), x.RAX)
            return
        if op == ir.COPY:
            if ins.dst == ins.a:
                return
            r := self.in_reg(ins.dst)
            if r >= 0:
                self.ld(r, ins.a)
                return
            self.ld(x.RAX, ins.a)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.ADD:
            self._binop(ins, x.ALU_ADD)
            return
        if op == ir.SUB:
            self._binop(ins, x.ALU_SUB)
            return
        if op == ir.AND:
            self._binop(ins, x.ALU_AND)
            return
        if op == ir.OR:
            self._binop(ins, x.ALU_OR)
            return
        if op == ir.XOR:
            self._binop(ins, x.ALU_XOR)
            return
        if op == ir.MUL:
            self.ld(x.RAX, ins.a)
            self.ld(x.RCX, ins.b)
            a.imul(x.RAX, x.RCX)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.SHL or op == ir.SHR:
            self.ld(x.RCX, ins.b)
            a.alu_ri(x.ALU_CMP, x.RCX, 63)
            a.jcc(x.C_A, self.site(ir.MSG_SHL if op == ir.SHL else ir.MSG_SHR))
            self.ld(x.RAX, ins.a)
            if op == ir.SHL:
                a.shl_cl(x.RAX)
            else:
                a.sar_cl(x.RAX)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.FLOORDIV or op == ir.MOD:
            div := op == ir.FLOORDIV
            minus_one := a.new_label()
            done := a.new_label()
            self.ld(x.RCX, ins.b)
            a.test(x.RCX, x.RCX)
            a.jcc(x.C_E, self.site(ir.MSG_FLOOR_DIV_ZERO if div else ir.MSG_MOD_ZERO))
            self.ld(x.RAX, ins.a)
            a.alu_ri(x.ALU_CMP, x.RCX, -1)
            a.jcc(x.C_E, minus_one)
            a.cqo()
            a.idiv(x.RCX)
            if div:
                a.test(x.RDX, x.RDX)
                a.jcc(x.C_E, done)
                a.alu_rr(x.ALU_XOR, x.RDX, x.RCX)
                a.jcc(x.C_NS, done)
                a.alu_ri(x.ALU_SUB, x.RAX, 1)
                a.jmp(done)
                a.bind(minus_one)
                a.neg(x.RAX)
            else:
                a.mov(x.RAX, x.RDX)
                a.test(x.RDX, x.RDX)
                a.jcc(x.C_E, done)
                a.mov(x.R8, x.RDX)
                a.alu_rr(x.ALU_XOR, x.R8, x.RCX)
                a.jcc(x.C_NS, done)
                a.alu_rr(x.ALU_ADD, x.RAX, x.RCX)
                a.jmp(done)
                a.bind(minus_one)
                a.mov_imm(x.RAX, 0)
            a.bind(done)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.POW:
            self.ld(x.RDI, ins.a)
            self.ld(x.RSI, ins.b)
            a.call(L["pow"])
            self.st(ins.dst, x.RAX)
            return
        if op == ir.NEG or op == ir.BITNOT:
            self.ld(x.RAX, ins.a)
            if op == ir.NEG:
                a.neg(x.RAX)
            else:
                a.notr(x.RAX)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.NOT:
            self.ld(x.RAX, ins.a)
            a.test(x.RAX, x.RAX)
            a.setcc(x.C_E, x.RAX)
            a.movzx8(x.RAX, x.RAX)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.EQ:
            self._compare(ins, x.C_E)
            return
        if op == ir.NE:
            self._compare(ins, x.C_NE)
            return
        if op == ir.LT:
            self._compare(ins, x.C_L)
            return
        if op == ir.LE:
            self._compare(ins, x.C_LE)
            return
        if op == ir.GT:
            self._compare(ins, x.C_G)
            return
        if op == ir.GE:
            self._compare(ins, x.C_GE)
            return
        if op == ir.FADD:
            self._fop(ins, 0x58)
            return
        if op == ir.FSUB:
            self._fop(ins, 0x5C)
            return
        if op == ir.FMUL:
            self._fop(ins, 0x59)
            return
        if op == ir.FDIV:
            self._fop(ins, 0x5E)
            return
        if op == ir.FSQRT:
            self.fld(XMM1, ins.a)
            a.sse_op_rr(0x51, XMM0, XMM1)
            self.fst(ins.dst, XMM0)
            return
        if op >= ir.FEQ and op <= ir.FGE:
            self.float_compare(ins)
            return
        if op == ir.INT_TO_FLOAT:
            self.ld(x.RAX, ins.a)
            a.cvtsi2sd_r(XMM0, x.RAX)
            self.fst(ins.dst, XMM0)
            return
        if op == ir.FLOAT_TO_INT:
            self.fld(XMM0, ins.a)
            a.cvttsd2si_r(x.RAX, XMM0)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.LABEL:
            a.bind(labels[ins.label])
            return
        if op == ir.JMP:
            a.jmp(labels[ins.label])
            return
        if op == ir.JMP_IF_ZERO or op == ir.JMP_IF_NON_ZERO:
            r := self.in_reg(ins.a)
            if r >= 0:
                a.test(r, r)
            else:
                a.alu_mi(x.ALU_CMP, self.slot(ins.a), 0)
            a.jcc(x.C_E if op == ir.JMP_IF_ZERO else x.C_NE, labels[ins.label])
            return
        if op == ir.CALL:
            stacked := self.call_args(ins.args, -1)
            a.call(self.fn_label[ins.callee])
            if stacked > 0:
                a.alu_ri(x.ALU_ADD, x.RSP, 8 * stacked)
            if ins.dst >= 0:
                self.st(ins.dst, x.RAX)
            return
        if op == ir.RET:
            if ins.a >= 0:
                self.ld(x.RAX, ins.a)
            self.epilogue()
            return
        if op == ir.LOAD_GLOBAL:
            a.load(x.RAX, bss(K_GLOBALS + 8 * ins.imm))
            self.st(ins.dst, x.RAX)
            return
        if op == ir.STORE_GLOBAL:
            self.ld(x.RAX, ins.a)
            a.store(bss(K_GLOBALS + 8 * ins.imm), x.RAX)
            return
        if op == ir.STR_CONST:
            a.mov_addr(x.RAX, x.S_RODATA, self.str_off[ins.imm])
            self.st(ins.dst, x.RAX)
            return
        if op == ir.LOAD64:
            self.ld(x.RAX, ins.a)
            a.load(x.RAX, x.at(x.RAX, ins.imm))
            self.st(ins.dst, x.RAX)
            return
        if op == ir.STORE64:
            self.ld(x.RAX, ins.a)
            self.ld(x.RCX, ins.b)
            a.store(x.at(x.RAX, ins.imm), x.RCX)
            return
        if op == ir.LOAD8:
            self.ld(x.RAX, ins.a)
            a.load8zx(x.RAX, x.at(x.RAX, ins.imm))
            self.st(ins.dst, x.RAX)
            return
        if op == ir.STORE8:
            self.ld(x.RAX, ins.a)
            self.ld(x.RCX, ins.b)
            a.store8(x.at(x.RAX, ins.imm), x.RCX)
            return
        if op == ir.LOAD16 or op == ir.LOAD32:
            self.ld(x.RAX, ins.a)
            if op == ir.LOAD16:
                a.load16zx(x.RAX, x.at(x.RAX, ins.imm))
            else:
                a.load32(x.RAX, x.at(x.RAX, ins.imm))
            self.st(ins.dst, x.RAX)
            return
        if op == ir.STORE16 or op == ir.STORE32:
            self.ld(x.RAX, ins.a)
            self.ld(x.RCX, ins.b)
            if op == ir.STORE16:
                a.store16(x.at(x.RAX, ins.imm), x.RCX)
            else:
                a.store32(x.at(x.RAX, ins.imm), x.RCX)
            return
        if op == ir.LOAD_ELEM:
            self.ld(x.RAX, ins.a)
            self.ld(x.RCX, ins.b)
            a.load_idx(x.RAX, x.RAX, x.RCX)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.STORE_ELEM:
            self.ld(x.RAX, ins.a)
            self.ld(x.RCX, ins.b)
            self.ld(x.RDX, ins.args[0])
            a.store_idx(x.RAX, x.RCX, x.RDX)
            return
        if op == ir.MEM_COPY:
            self.ld(x.RDI, ins.a)
            self.ld(x.RSI, ins.b)
            self.ld(x.RCX, ins.args[0])
            a.rep_movsb()
            return
        if op == ir.BOUNDS_CHECK:
            s := Site(a.new_label(), self.cur_line, -1, ins)
            append(self.sites, s)
            self.ld(x.RAX, ins.a)
            self.alu_v(x.ALU_CMP, x.RAX, ins.b)
            a.jcc(x.C_AE, s.label)
            return
        if op == ir.INT_TO_STR:
            self.ld(x.RDI, ins.a)
            a.call(L["int_to_str"])
            self.st(ins.dst, x.RAX)
            return
        if op == ir.PRINT_INT:
            self.ld(x.RDI, ins.a)
            self.guarded_call(L["print_int"])
            return
        if op == ir.PRINT_STR:
            self.ld(x.RSI, ins.a)
            self.guarded_call(L["print_str"])
            return
        if op == ir.PRINT_EMPTY:
            self.guarded_call(L["newline"])
            return
        if op == ir.FAIL:
            a.call(self.msg_stub(ins.imm))
            return
        if op == ir.FAIL_STR:
            self.ld(x.RSI, ins.a)
            a.call(L["fail"])
            return
        if op == ir.WRITE_ERR:
            self.ld(x.RSI, ins.a)
            a.call(L["write_err"])
            return
        if op == ir.CODE_BASE:
            a.mov_addr(x.RAX, x.S_CODE, 0)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.TRACE_INFO:
            a.mov_addr(x.RAX, x.S_RODATA, 0)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.ARGV_BASE:
            a.load(x.RAX, bss(K_ARGV))
            self.st(ins.dst, x.RAX)
            return
        if op == ir.RT_STATE:
            a.mov_addr(x.RAX, x.S_BSS, K_RT_STATE)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.MMAP:
            if self.win:
                ok := a.new_label()
                self.ld(x.RDX, ins.a)
                a.mov(x.R11, x.RSP)
                a.alu_ri(x.ALU_AND, x.RSP, -16)
                a.alu_ri(x.ALU_SUB, x.RSP, 48)
                a.store(x.at(x.RSP, 40), x.R11)
                a.mov_imm(x.RCX, 0)
                a.mov_imm(x.R8, 0x3000)
                a.mov_imm(x.R9, 4)
                self.win_call("VirtualAlloc")
                a.load(x.RSP, x.at(x.RSP, 40))
                a.test(x.RAX, x.RAX)
                a.jcc(x.C_NE, ok)
                a.mov_imm(x.RAX, -12)
                a.bind(ok)
                self.st(ins.dst, x.RAX)
                return
            self.ld(x.RSI, ins.a)
            a.mov_imm(x.RAX, 9)
            a.mov_imm(x.RDI, 0)
            a.mov_imm(x.RDX, 3)
            a.mov_imm(x.R10, 0x4022)
            a.mov_imm(x.R8, -1)
            a.mov_imm(x.R9, 0)
            a.syscall()
            self.st(ins.dst, x.RAX)
            return
        if op == ir.MUNMAP:
            if self.win:
                self.ld(x.RCX, ins.a)
                a.mov(x.R11, x.RSP)
                a.alu_ri(x.ALU_AND, x.RSP, -16)
                a.alu_ri(x.ALU_SUB, x.RSP, 48)
                a.store(x.at(x.RSP, 40), x.R11)
                a.mov_imm(x.RDX, 0)
                a.mov_imm(x.R8, 0x8000)
                self.win_call("VirtualFree")
                a.load(x.RSP, x.at(x.RSP, 40))
                return
            self.ld(x.RDI, ins.a)
            self.ld(x.RSI, ins.b)
            a.mov_imm(x.RAX, 11)
            a.syscall()
            return
        if op == ir.STACK_PTR:
            a.mov(x.RAX, x.RSP)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.STACK_TOP:
            a.load(x.RAX, bss(K_STACK_TOP))
            self.st(ins.dst, x.RAX)
            return
        if op == ir.SAVE_REGS:
            a.store(bss(K_REG_SAVE), x.RBX)
            a.store(bss(K_REG_SAVE + 8), x.R12)
            a.store(bss(K_REG_SAVE + 16), x.R13)
            a.store(bss(K_REG_SAVE + 24), x.R14)
            a.mov_addr(x.RAX, x.S_BSS, K_REG_SAVE)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.GLOBALS_START or op == ir.GLOBALS_END:
            a.mov_addr(x.RAX, x.S_BSS, K_GLOBALS + (8 * self.p.globals if op == ir.GLOBALS_END else 0))
            self.st(ins.dst, x.RAX)
            return
        if op == ir.MEM_ZERO:
            self.ld(x.RDI, ins.a)
            self.ld(x.RCX, ins.b)
            a.mov_imm(x.RAX, 0)
            big := a.new_label()
            words := a.new_label()
            bts := a.new_label()
            done := a.new_label()
            a.alu_ri(x.ALU_CMP, x.RCX, 256)
            a.jcc(x.C_A, big)
            a.bind(words)
            a.alu_ri(x.ALU_CMP, x.RCX, 8)
            a.jcc(x.C_B, bts)
            a.store(x.at(x.RDI), x.RAX)
            a.alu_ri(x.ALU_ADD, x.RDI, 8)
            a.alu_ri(x.ALU_SUB, x.RCX, 8)
            a.jmp(words)
            a.bind(bts)
            a.test(x.RCX, x.RCX)
            a.jcc(x.C_E, done)
            a.store8(x.at(x.RDI), x.RAX)
            a.alu_ri(x.ALU_ADD, x.RDI, 1)
            a.alu_ri(x.ALU_SUB, x.RCX, 1)
            a.jmp(bts)
            a.bind(big)
            a.rep_stosb()
            a.bind(done)
            return
        if op == ir.TRY_BEGIN:
            rec := self.slot(ins.a)
            a.lea(x.RAX, rec)
            self.handler_load(x.RCX)
            a.store(x.at(x.RAX, 0), x.RCX)
            a.store(x.at(x.RAX, 8), x.RBP)
            a.store(x.at(x.RAX, 16), x.RSP)
            a.store(x.at(x.RAX, 24), DEPTH_REG)
            a.store(x.at(x.RAX, 32), x.RBX)
            a.store(x.at(x.RAX, 40), x.R12)
            a.store(x.at(x.RAX, 48), x.R13)
            a.store(x.at(x.RAX, 56), x.R14)
            a.mov_label_addr(x.RCX, labels[ins.label])
            a.store(x.at(x.RAX, 64), x.RCX)
            self.handler_store(x.RAX)
            return
        if op == ir.TRY_END:
            a.lea(x.RAX, self.slot(ins.a))
            a.load(x.RCX, x.at(x.RAX, 0))
            self.handler_store(x.RCX)
            return
        if op == ir.LANDING:
            self.st(ins.dst, x.RDI)
            return
        if op == ir.FRAME_PTR:
            a.mov(x.RAX, x.RBP)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.FLUSH:
            self.guarded_call(L["flush"])
            return
        if op == ir.FIBER_ENTRY:
            a.mov_label_addr(x.RAX, L["fiber_entry"])
            self.st(ins.dst, x.RAX)
            return
        if op == ir.CTX_SWITCH:
            self.ld(x.RDI, ins.a)
            self.ld(x.RSI, ins.b)
            a.call(L["switch"])
            return
        if op == ir.ENTER_USER:
            if not self.fs or self.uefi:
                raise("RuntimeError", "mode utilisateur : seulement avec --freestanding")
            if ins.imm == 1:
                self.ld(x.RSI, ins.a)
                self.ld(x.RDX, ins.b)
                a.call(L["enter_user_frame"])
                self.st(ins.dst, x.RAX)
                return
            self.ld(x.RDI, ins.a)
            self.ld(x.RSI, ins.b)
            self.ld(x.RDX, ins.args[0])
            a.call(L["enter_user"])
            self.st(ins.dst, x.RAX)
            return
        if op == ir.LEAVE_USER:
            if not self.fs or self.uefi:
                raise("RuntimeError", "mode utilisateur : seulement avec --freestanding")
            self.ld(x.RDI, ins.a)
            self.ld(x.RSI, ins.b)
            a.jmp(L["leave_user"])
            return
        if op == ir.FUNC_ADDR:
            a.mov_label_addr(x.RAX, self.fn_label[ins.callee])
            self.st(ins.dst, x.RAX)
            return
        if op == ir.CALL_IND:
            stacked := self.call_args(ins.args, ins.a)
            a.load(x.RAX, x.at(x.RDI, ins.imm))
            a.call_reg(x.RAX)
            if stacked > 0:
                a.alu_ri(x.ALU_ADD, x.RSP, 8 * stacked)
            if ins.dst >= 0:
                self.st(ins.dst, x.RAX)
            return
        if op == ir.EXIT:
            self.ld(x.RDI, ins.a)
            self.exit_with(x.RDI)
            return
        if op == ir.WIN_THUNK:
            if not self.win:
                raise("RuntimeError", "rappel Windows hors de la cible --windows")
            a.mov_label_addr(x.RAX, self.thunk_for(ins.callee))
            self.st(ins.dst, x.RAX)
            return
        if op == ir.IMPORT_ADDR:
            if not self.win and (self.uefi or self.fs or len(self.imports) == 0):
                raise("RuntimeError", "import Windows hors de la cible --windows")
            a.load(x.RAX, x.data(x.S_IMPORT, self.imp_off[ins.imm]))
            self.st(ins.dst, x.RAX)
            return
        if op == ir.SYSCALL:
            if self.win:
                raise("RuntimeError", "appel système Linux dans un exécutable Windows (doit être émulé)")
            if self.fs:
                a.mov_imm(x.RAX, -38)
                if ins.dst >= 0:
                    self.st(ins.dst, x.RAX)
                return
            sys_regs := [x.RDI, x.RSI, x.RDX, x.R10, x.R8, x.R9]
            self.pending = -1
            i := 1
            while i < len(ins.args) and i <= 6:
                self.ld(sys_regs[i - 1], ins.args[i])
                i += 1
            self.ld(x.RAX, ins.args[0])
            a.syscall()
            if ins.dst >= 0:
                self.st(ins.dst, x.RAX)
            return
        if op == ir.PORT_OUT:
            self.ld(x.RDX, ins.a)
            self.ld(x.RAX, ins.b)
            if ins.imm == 1:
                a.raw([0xEE])
            elif ins.imm == 2:
                a.raw([0x66, 0xEF])
            else:
                a.raw([0xEF])
            return
        if op == ir.PORT_IN:
            self.ld(x.RDX, ins.a)
            a.mov_imm(x.RAX, 0)
            if ins.imm == 1:
                a.raw([0xEC])
            elif ins.imm == 2:
                a.raw([0x66, 0xED])
            else:
                a.raw([0xED])
            self.st(ins.dst, x.RAX)
            return
        if op == ir.CPU_OP:
            self.cpu_op(ins)
            return
        if op == ir.MS_CALL:
            n := len(ins.args)
            area := 8 * (n if n > 4 else 4)
            frame := (area + 8 + 15) & ~15
            self.pending = -1
            a.mov(x.R11, x.RSP)
            a.alu_ri(x.ALU_AND, x.RSP, -16)
            a.alu_ri(x.ALU_SUB, x.RSP, frame)
            a.store(x.at(x.RSP, frame - 8), x.R11)
            k := 0
            while k < n:
                self.ld(x.RAX, ins.args[k])
                a.store(x.at(x.RSP, 8 * k), x.RAX)
                k += 1
            ms_regs := [x.RCX, x.RDX, x.R8, x.R9]
            k = 0
            while k < n and k < 4:
                a.load(ms_regs[k], x.at(x.RSP, 8 * k))
                # convention Windows x64 : un argument flottant de rang 1 à 4 est lu dans xmm0..xmm3 ; on y copie
                # aussi chaque argument (comme un appelant variadique), les bits d'un flottant passant par l'entier
                a.movsd_load(k, x.at(x.RSP, 8 * k))
                k += 1
            self.ld(x.RAX, ins.a)
            a.call_reg(x.RAX)
            a.load(x.RSP, x.at(x.RSP, frame - 8))
            if ins.imm == 1:
                a.movq_from_xmm(x.RAX, 0)     # __mscall_f : bits du flottant rendu dans xmm0
            if ins.dst >= 0:
                self.st(ins.dst, x.RAX)
            return
        if op == ir.SYSV_CALL:
            # cadre (r10) : [0..40] 6 entiers  [48..104] 8 flottants  [112] arguments sur la pile  [120] al (registres
            # vectoriels)  [128] rax rendu  [136] xmm0 rendu  [160..] arguments sur la pile. rbx (préservé) garde rsp.
            self.pending = -1
            self.ld(x.R10, ins.b)
            self.ld(x.RAX, ins.a)
            a.raw(SYSV_TRAMPOLINE)
            if ins.dst >= 0:
                self.st(ins.dst, x.RAX)
            return
        if op == ir.RAW_CODE:
            a.raw(self.p.strings[ins.imm])
            if ins.dst >= 0:
                self.st(ins.dst, x.RAX)
            return
        if op == ir.HANDLER_TOP:
            self.handler_load(x.RAX)
            self.st(ins.dst, x.RAX)
            return
        if op == ir.UNWIND:
            self.ld(x.RDI, ins.a)
            self.handler_load(x.RAX)
            a.load(x.RCX, x.at(x.RAX, 0))
            self.handler_store(x.RCX)
            a.load(x.RBP, x.at(x.RAX, 8))
            a.load(x.RSP, x.at(x.RAX, 16))
            a.load(DEPTH_REG, x.at(x.RAX, 24))
            a.load(x.RBX, x.at(x.RAX, 32))
            a.load(x.R12, x.at(x.RAX, 40))
            a.load(x.R13, x.at(x.RAX, 48))
            a.load(x.R14, x.at(x.RAX, 56))
            a.load(x.RCX, x.at(x.RAX, 64))
            a.jmp_reg(x.RCX)
            return

    # CpuOp sous Linux (fs_ faux) : seuls les cas sans accès matériel produisent du code.
    func cpu_op(ins):
        a := self.a
        imm := ins.imm
        fs := self.fs
        full := self.fs and not self.uefi     # noyau sans OS (multiboot) : non porté
        if imm < 4:
            a.raw([[0xF4], [0xFA], [0xFB], [0xF3, 0x90]][imm])
        elif imm == 4:
            a.raw([0x9C])
            a.pop(x.RAX)
            if fs:
                a.raw([0xFA])
            self.st(ins.dst, x.RAX)
        elif imm == 5:
            if fs:
                keep := a.new_label()
                self.ld(x.RAX, ins.a)
                a.alu_ri(x.ALU_AND, x.RAX, 0x200)
                a.jcc(x.C_E, keep)
                a.raw([0xFB])
                a.bind(keep)
        elif imm == 6 or imm == 7:
            a.raw([0x0F, 0x20, 0xD0 if imm == 6 else 0xD8])
            self.st(ins.dst, x.RAX)
        elif imm == 8:
            self.ld(x.RAX, ins.a)
            a.raw([0x0F, 0x01, 0x38])
        elif imm == 9:
            if fs:
                self.ld(x.RAX, ins.a)
                a.raw([0x0F, 0x22, 0xD8])
        elif imm == 10:
            if full:
                self.gs_load(x.RAX, K_CPU_SELF)
            else:
                a.mov_addr(x.RAX, x.S_BSS, K_CPU0)
            self.st(ins.dst, x.RAX)
        elif imm == 11:
            a.mov_imm(x.RAX, 0)
            if fs:
                self.ld(x.RCX, ins.a)
                a.raw([0x0F, 0x32, 0x48, 0xC1, 0xE2, 0x20, 0x48, 0x09, 0xD0])
            self.st(ins.dst, x.RAX)
        elif imm == 12:
            if fs:
                self.ld(x.RCX, ins.a)
                self.ld(x.RAX, ins.b)
                a.mov(x.RDX, x.RAX)
                a.raw([0x48, 0xC1, 0xEA, 0x20, 0x0F, 0x30])
        elif imm == 13 or imm == 14 or imm == 15:
            if imm == 13 and full:
                a.mov_label_addr(x.RAX, self.labels_["ap_entry"])
            elif imm == 14 and full:
                a.mov_addr(x.RAX, x.S_RODATA, self.trampoline_off)
            elif imm == 15:
                a.mov_addr(x.RAX, x.S_BSS, K_SMP)
            else:
                a.mov_imm(x.RAX, 0)
            self.st(ins.dst, x.RAX)
        elif imm == 16:
            self.ld(x.RCX, ins.a)
            self.ld(x.RDX, ins.args[0])
            self.ld(x.RAX, ins.b)
            a.raw([0xF0, 0x48, 0x0F, 0xB1, 0x11])
            self.st(ins.dst, x.RAX)
        elif imm == 17:
            self.ld(x.RCX, ins.a)
            self.ld(x.RAX, ins.b)
            a.raw([0xF0, 0x48, 0x0F, 0xC1, 0x01])
            self.st(ins.dst, x.RAX)
        elif imm == 26 or imm == 27:
            if fs:
                self.ld(x.RAX, ins.a)
                a.raw([0x48, 0x0F, 0xAE, 0x00 if imm == 26 else 0x08])
        elif imm == 25:
            a.mov_imm(x.RAX, 0)
            if full:
                no := a.new_label()
                self.gs_load(x.RCX, K_CPU_INDEX)
                a.alu_ri(x.ALU_ADD, x.RCX, 1)
                a.alu_rm(x.ALU_CMP, x.RCX, bss(K_BKL))
                a.jcc(x.C_NE, no)
                a.mov_imm(x.RAX, 1)
                a.bind(no)
            self.st(ins.dst, x.RAX)
        elif imm == 18:
            if full:
                self.ld(x.RDI, ins.a)
                self.ld(x.RSI, ins.b)
                a.call(self.labels_["park"])
        elif imm == 23:
            if full:
                have := a.new_label()
                self.gs_load(x.RCX, K_CPU_INDEX)
                a.alu_ri(x.ALU_ADD, x.RCX, 1)
                a.alu_rm(x.ALU_CMP, x.RCX, bss(K_BKL))
                a.jcc(x.C_E, have)
                a.call(self.labels_["bkl_acquire"])
                a.bind(have)
        elif imm == 24:
            if full:
                self.bkl_release_mine()
        elif imm == 20:
            if full:
                a.call(self.labels_["gc_park"])
        elif imm == 21:
            if full:
                self.apic_icr(0xC40FD)
        elif imm == 22:
            if full:
                self.apic_eoi()
        elif imm == 19:
            if full:
                self.ld(x.RAX, ins.a)
                self.gs_store(K_CPU_KERNEL_RSP, x.RAX)
                self.gs_load(x.RCX, K_CPU_TSS)
                a.store(x.at(x.RCX, 4), x.RAX)

    func fuse_compare_jump(cmp, jump, labels):
        conds := {16: x.C_E, 17: x.C_NE, 18: x.C_L, 19: x.C_LE, 20: x.C_G, 21: x.C_GE}
        if not (cmp.op in conds):
            return false
        c := conds[cmp.op]
        if (jump.op != ir.JMP_IF_ZERO and jump.op != ir.JMP_IF_NON_ZERO) or jump.a != cmp.dst or self.uses[cmp.dst] != 1:
            return false
        if jump.op == ir.JMP_IF_ZERO:
            c = c ^ 1
        self.mark_line(cmp.line)
        self.pending = self.forward
        self.forward = -1
        ra := self.in_reg(cmp.a)
        if ra >= 0:
            self.alu_v(x.ALU_CMP, ra, cmp.b)
        else:
            self.ld(x.RAX, cmp.a)
            self.alu_v(x.ALU_CMP, x.RAX, cmp.b)
        self.a.jcc(c, labels[jump.label])
        self.pending = -1
        return true

    func epilogue():
        k := 0
        while k < len(self.saved_regs):
            self.a.load(self.saved_regs[k], x.at(x.RBP, self.save_slot(k)))
            k += 1
        if not self.cur_runtime:
            self.a.alu_ri(x.ALU_SUB, DEPTH_REG, 1)
        self.a.leave()
        self.a.ret()

    func allocate(f):
        n := f.vregs
        self.reg_of = [-1 for i in 0..n]
        self.uses = [0 for i in 0..n]
        self.is_const = [false for i in 0..n]
        self.need_slot = [false for i in 0..n]
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
        # profondeur de boucle : différence de compteurs (+1 au début d'un saut arrière, -1 après sa fin)
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
            cv := self.const_val[v]
            self.is_const[v] = defs[v] == 1 and def_const[v] and v >= f.params and cv >= INT32_MIN and cv <= INT32_MAX
            v += 1
        for ins in code:
            if ins.op == ir.CALL or ins.op == ir.CALL_IND:
                i := REG_ARGS - 1 if ins.op == ir.CALL_IND else REG_ARGS
                while i < len(ins.args):
                    self.need_slot[ins.args[i]] = true
                    i += 1
            if (ins.op == ir.JMP_IF_ZERO or ins.op == ir.JMP_IF_NON_ZERO) and ins.a >= 0:
                self.need_slot[ins.a] = true
            if ins.op in FLOAT_SLOT_OPS:
                if ins.a >= 0:
                    self.need_slot[ins.a] = true
                if ins.b >= 0:
                    self.need_slot[ins.b] = true
        cand := []
        if not f.has_try:
            v = 0
            while v < n:
                cost := 2.0 + (1.0 if v < f.params else 0.0)
                if not self.is_const[v] and self.uses[v] >= 2 and weight[v] > cost + 1.0:
                    append(cand, v)
                v += 1
        # tri stable par poids décroissant (stable_sort)
        cand = _stable_by_weight(cand, weight)
        pool := [x.RBX, x.R12, x.R13, x.R14]
        self.saved_regs = []
        k = 0
        while k < len(cand) and k < 4:
            self.reg_of[cand[k]] = pool[k]
            append(self.saved_regs, pool[k])
            k += 1

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
        # fonctions du runtime et des modules « # alex: inline » : ni compteur de profondeur, ni grand cadre remis à zéro
        rt_like := f.runtime or f.inline
        self.cur_runtime = rt_like
        if not rt_like:
            a.alu_ri(x.ALU_ADD, DEPTH_REG, 1)
            a.alu_ri(x.ALU_CMP, DEPTH_REG, MAX_DEPTH)
            a.jcc(x.C_G, self.msg_stub(MSG_RECURSION))
        a.push(x.RBP)
        a.mov(x.RBP, x.RSP)
        frame := 8 * (self.frame_slots + len(self.saved_regs))
        frame = (frame + 15) & ~15
        if frame != 0:
            a.alu_ri(x.ALU_SUB, x.RSP, frame)
        if frame != 0 and frame <= K_ZERO_FRAME_MAX:
            o := 0
            while o < frame:
                a.store_imm(x.at(x.RSP, o), 0)
                o += 8
        elif frame != 0 and not rt_like:
            a.mov(x.R11, x.RSP)
            loop := a.new_label()
            a.bind(loop)
            a.store_imm(x.at(x.R11), 0)
            a.alu_ri(x.ALU_ADD, x.R11, 8)
            a.alu_rr(x.ALU_CMP, x.R11, x.RBP)
            a.jcc(x.C_B, loop)
        k := 0
        while k < len(self.saved_regs):
            a.store(x.at(x.RBP, self.save_slot(k)), self.saved_regs[k])
            k += 1
        p := 0
        while p < f.params:
            r := self.in_reg(p)
            if p < REG_ARGS:
                if r >= 0:
                    a.mov(r, ARG_REGS[p])
                else:
                    a.store(self.slot(p), ARG_REGS[p])
            elif r >= 0:
                a.load(r, self.slot(p))
            p += 1
        self.forward = -1
        self.pending = -1
        code := f.code
        nc := len(code)
        k = 0
        while k < nc:
            ins := code[k]
            if k + 1 < nc and self.fuse_compare_jump(ins, code[k + 1], labels):
                k += 2
                continue
            self.next_ = code[k + 1] if k + 1 < nc else null
            self.instruction(ins, labels)
            k += 1
        self.next_ = null
        self.forward = -1
        self.pending = -1
        for s in self.sites:
            a.bind(s.label)
            append(self.lines, [a.size(), s.line])
            if s.bounds != null:
                self.call_args([s.bounds.a, s.bounds.b], -1)
                a.call(self.fn_label[s.bounds.callee])
            else:
                a.call(self.msg_stub(s.msg))
        self.fn_range[index] = [start, a.size()]

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

    func run(path, emit_map=false):
        p := self.p
        a := self.a
        a.pic = self.win or self.uefi
        if self.win:
            self.layout_imports()
        elif len(p.imports) > 0:
            # ELF dynamique (VM écrite en ALEX) : table des adresses importées, une case par symbole
            self.imports = [s for s in p.imports]
            self.imp_off = [8 * k for k in 0..len(p.imports)]
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
        self.fn_range = [[0, 0] for i in 0..len(p.functions)]
        self.fn_label = [a.new_label() for i in 0..len(p.functions)]
        self.msg_stub_ = [a.new_label() for i in 0..len(p.messages)]
        self.msg_used = [false for i in 0..len(p.messages)]
        for nm in ["flush", "write_fd", "write", "newline", "print_int", "print_str", "fail", "pow", "int_to_str", "write_err", "digits", "switch", "fiber_entry", "isr_stubs", "isr_common", "syscall_entry", "enter_user", "leave_user", "enter_user_frame", "ap_entry", "park", "bkl_acquire", "cpu_setup", "out_lock", "out_unlock", "gc_park", "df_stub", "shoot_stub"]:
            self.labels_[nm] = a.new_label()
        bss_used := self.trace_off + 8 * TRACE_CAP
        if self.win:
            self.win_scratch = (bss_used + 15) & ~15
            self.win_wide = self.win_scratch + 16
            bss_used = self.win_wide + 2 * WIN_WIDE_CHARS
            if self.gui:
                self.win_err_len = bss_used
                self.win_err = self.win_err_len + 8
                bss_used = self.win_err + WIN_ERR_CAP
                t := []
                for b in _bytes("Erreur ALEX"):
                    append(t, b)
                    append(t, 0)
                append(t, 0)
                append(t, 0)
                self.win_err_title = self.add_rodata(t)
        fs_argv := (bss_used + 7) & ~7
        mb_info := fs_argv + 24
        tables := (mb_info + 8 + 4095) & ~4095
        idt := tables + K_BOOT_TABLE_PAGES * 4096
        gdt := idt + 4096 + 16
        tss := gdt + 320
        ist := (tss + K_MAX_CPUS * K_TSS_STRIDE + 4095) & ~4095
        self.fs_argv = fs_argv
        self.stack_top = ist + K_MAX_CPUS * K_IST_SIZE + ((4 << 20) if self.uefi else 0)
        self.mb_info = mb_info
        self.tables = tables
        self.idt = idt
        self.gdt = gdt
        self.tss = tss
        self.ist = ist
        self.df_msg_off = self.add_rodata(_bytes("\r\n*** Alex OS : DOUBLE FAUTE - debordement probable d'une pile du noyau (page de garde). Coeur arrete.\r\n"))
        if self.fs and not self.uefi:
            self.trampoline_off = self.add_rodata(x.ap_trampoline())
        entry := a.size()
        if self.uefi:
            self.start_uefi()
        elif self.win:
            self.start_windows()
        elif self.fs:
            self.start_freestanding()
        else:
            self.start_linux()
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
                a.mov_addr(x.RSI, x.S_RODATA, self.msg_off[m])
                a.jmp(self.labels_["fail"])
            m += 1
        self.build_trace_tables()
        img := x.ElfImage(a, self.ro, self.stack_top if self.fs else bss_used, entry)
        if not self.win and not self.uefi:
            img.imports = self.imports
        if emit_map:
            i = 0
            while i < len(p.functions):
                append(img.symbols, [self.fn_range[i][0], self.fn_range[i][1], p.functions[i].name])
                i += 1
        return img

    func start_linux():
        a := self.a
        p := self.p
        keep := a.new_label()
        a.mov(x.RAX, x.RSP)
        a.store(bss(K_ARGV), x.RAX)
        a.mov_imm(x.RAX, 9)
        a.mov_imm(x.RDI, 0)
        a.mov_imm(x.RSI, STACK_SIZE)
        a.mov_imm(x.RDX, 3)
        a.mov_imm(x.R10, 0x4022)
        a.mov_imm(x.R8, -1)
        a.mov_imm(x.R9, 0)
        a.syscall()
        a.test(x.RAX, x.RAX)
        a.jcc(x.C_S, keep)
        a.lea(x.RSP, x.at(x.RAX, STACK_SIZE))
        a.bind(keep)
        a.mov(x.RAX, x.RSP)
        a.store(bss(K_STACK_TOP), x.RAX)
        a.mov_imm(DEPTH_REG, 0)
        a.mov_imm(x.RBP, 0)
        a.call(self.fn_label[p.entry])
        a.call(self.labels_["flush"])
        a.mov_imm(x.RDI, 0)
        self.exit_with(x.RDI)

func _first_load(ins):
    return ins.a if ins.op in FIRST_LOAD else -1

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

# IrProgram -> exécutable ELF x86-64 Linux écrit dans `path`.
# Cible Windows (p.windows) : exécutable PE32+ (console, ou graphique si p.windows_gui).
# Sortie AEX (cible Alex OS) au lieu d'ELF.
_alexos_out := [false]

func set_alexos(on):
    _alexos_out[0] = on

func generate_x64(p, path, emit_map=false, image_base=0):
    g := Gen(p)
    img := g.run(path, emit_map)
    if image_base != 0:
        img.base = image_base
    if g.uefi:
        x.write_pe(img, path)
    elif g.fs:
        x.write_multiboot(img, g.mb_info, g.tables, path)
    elif g.win:
        x.write_pe(img, path, x.PeWindows(g.pe_imports, g.gui, p.windows_icon))
    elif _alexos_out[0]:
        x.write_aex(img, path)
    else:
        x.write_elf(img, path)

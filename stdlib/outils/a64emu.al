# alex: native
# alex: intrinsics
# alex: inline
# ALEX STANDARD LIBRARY — outils.a64emu
#
# Émulateur AArch64 écrit en ALEX (remplace tests/native/aarch64/a64run.cpp) : exécute un programme Linux
# AArch64 (ELF statique) sur une machine Linux x86-64, pour les tests du backend natif ARM64 (`alexc build
# --native --target linux-aarch64`, tests/native/run_aarch64_tests.sh). Programme : tests/native/aarch64/a64run.al,
# compilé en code machine (`alexc build --native --static --image-base 0x10000000`, l'image de l'invité occupant
# 0x40000000).
#
# Interpréteur du jeu d'instructions A64 (sous-ensemble : entiers, chargements / rangements, branchements,
# exclusifs, flottants scalaires, quelques SIMD), appels système Linux AArch64 traduits vers ceux de l'hôte. La
# mémoire de l'invité est celle de l'hôte (adresses identiques : segments ELF placés à leur adresse, mmap de
# l'invité = mmap de l'hôte). Comme Linux, il vérifie l'alignement de sp sur 16 octets pour tout accès mémoire qui
# l'utilise comme base et l'alignement des accès exclusifs. Les NaN suivent les règles d'ARM (NaN par défaut
# positif, propagation du premier opérande NaN).
#
#   use outils.a64emu as emu
#   emu.main()          # a64run programme [arguments...]   A64RUN_TRACE=1 : trace des instructions
#
# Limites : FMADD et ses variantes sont calculées en double-double (et non par une vraie multiplication-addition
# fusionnée) ; une faute mémoire de l'invité termine l'émulateur par le signal de l'hôte (code 139).
#
# Erreurs : message « a64run: ... » sur la sortie d'erreur, code 99.

from core use len

# ---- état de la machine (bloc mmap, adresse dans _S) ------------------------------------------------------------
#   [0..247] x0..x30   [248] sp   [256] pc   [264] n  [272] z  [280] c  [288] v   [296] moniteur exclusif
#   [304] compteur d'instructions   [312] trace   [320..335] intervalle intercepté (bas, haut)   [336] svc interdit
#   [344] wmask  [352] tmask (decode_bit_masks)   [512 + 16 r] registre q[r] (bas, haut)
const MIN := -9223372036854775807 - 1
const M32 := 0xFFFFFFFF
const O_SP := 248
const O_PC := 256
const O_N := 264
const O_Z := 272
const O_C := 280
const O_V := 288
const O_EXCL := 296
const O_COUNT := 304
const O_TRACE := 312
const O_TRAP_LO := 320
const O_TRAP_HI := 328
const O_NOSVC := 336
const O_WM := 344
const O_TM := 352
const O_Q := 512

_S := 0

func state() -> int:
    return _S

func _e(s: str):
    __write_err(s)

func _hex(v: int) -> str:
    buf := __alloc_raw(24)
    n := 0
    i := 15
    started := false
    while i >= 0:
        k := lsr(v, 4 * i) & 15
        if k != 0 or started or i == 0:
            c := 48 + k
            if k >= 10:
                c = 87 + k
            __store8(buf + n, c)
            n += 1
            started = true
        i -= 1
    __store8(buf + n, 0)
    return "0x" + _cstr(buf)

func die(msg: str):
    __flush()
    _e("a64run: " + msg + "\n")
    __exit(99)

func die_code(msg: str, code: int):
    __flush()
    _e("a64run: " + msg + "\n")
    __exit(code)

# ---- arithmétique non signée sur des entiers de 64 bits ----------------------------------------------------------
func lsr(v: int, n: int) -> int:
    if n == 0:
        return v
    if n >= 64:
        return 0
    return (v >> n) & ((1 << (64 - n)) - 1)

func lsl(v: int, n: int) -> int:
    if n >= 64:
        return 0
    return v << n

func ult(a: int, b: int) -> bool:
    return (a ^ MIN) < (b ^ MIN)

func ones(n: int) -> int:
    if n >= 64:
        return -1
    return (1 << n) - 1

func bits(w: int, hi: int, lo: int) -> int:
    return lsr(w, lo) & ones(hi - lo + 1)

func sext(v: int, width: int) -> int:
    if width >= 64:
        return v
    m := 1 << (width - 1)
    return ((v & ones(width)) ^ m) - m

func udiv(a: int, b: int) -> int:
    if b == 0:
        return 0
    if b < 0:
        if ult(a, b):
            return 0
        return 1
    if a >= 0:
        return a // b
    q := (lsr(a, 1) // b) << 1
    r := a - q * b
    if not ult(r, b):
        q += 1
    return q

# division signée tronquée vers zéro (SDIV)
func sdiv(a: int, b: int) -> int:
    if b == 0:
        return 0
    if a == MIN and b == -1:
        return a
    q := a // b
    if q * b != a and ((a < 0) != (b < 0)):
        q += 1
    return q

func umulh(a: int, b: int) -> int:
    a0 := a & M32
    a1 := lsr(a, 32)
    b0 := b & M32
    b1 := lsr(b, 32)
    p00 := a0 * b0
    p01 := a0 * b1
    p10 := a1 * b0
    p11 := a1 * b1
    mid := lsr(p00, 32) + (p01 & M32) + (p10 & M32)
    return p11 + lsr(p01, 32) + lsr(p10, 32) + lsr(mid, 32)

func smulh(a: int, b: int) -> int:
    h := umulh(a, b)
    if a < 0:
        h = h - b
    if b < 0:
        h = h - a
    return h

func clz(v: int, width: int) -> int:
    n := 0
    i := width - 1
    while i >= 0:
        if (lsr(v, i) & 1) != 0:
            return n
        n += 1
        i -= 1
    return width

func popcount8(v: int) -> int:
    n := 0
    while v != 0:
        n += v & 1
        v = v >> 1
    return n

# ---- registres ------------------------------------------------------------------------------------------------
func xr(r: int) -> int:
    if r == 31:
        return 0
    return __load64(_S + 8 * r)

func xs(r: int) -> int:
    if r == 31:
        return __load64(_S + O_SP)
    return __load64(_S + 8 * r)

func setx(r: int, v: int):
    if r != 31:
        __store64(_S + 8 * r, v)

func setxs(r: int, v: int):
    if r == 31:
        __store64(_S + O_SP, v)
    else:
        __store64(_S + 8 * r, v)

func getx(r: int) -> int:
    return __load64(_S + 8 * r)

func pc() -> int:
    return __load64(_S + O_PC)

func set_pc(v: int):
    __store64(_S + O_PC, v)

func sp() -> int:
    return __load64(_S + O_SP)

func set_sp(v: int):
    __store64(_S + O_SP, v)

func qlo(r: int) -> int:
    return __load64(_S + O_Q + 16 * r)

func qhi(r: int) -> int:
    return __load64(_S + O_Q + 16 * r + 8)

func setq(r: int, lo: int, hi: int):
    __store64(_S + O_Q + 16 * r, lo)
    __store64(_S + O_Q + 16 * r + 8, hi)

func flag(o: int) -> bool:
    return __load64(_S + o) != 0

func set_flag(o: int, b: bool):
    if b:
        __store64(_S + o, 1)
    else:
        __store64(_S + o, 0)

func set_nzcv(nzcv: int):
    set_flag(O_N, (nzcv & 8) != 0)
    set_flag(O_Z, (nzcv & 4) != 0)
    set_flag(O_C, (nzcv & 2) != 0)
    set_flag(O_V, (nzcv & 1) != 0)

# Base d'adresse : sp doit être aligné sur 16 octets quand il sert de base (Linux, EL0).
func base(rn: int) -> int:
    if rn == 31:
        s := sp()
        if (s & 15) != 0:
            die("sp non aligné sur 16 octets (" + _hex(s) + ") utilisé comme base mémoire, pc=" + _hex(pc()))
        return s
    return __load64(_S + 8 * rn)

func cond(c: int) -> bool:
    k := c >> 1
    r := true
    if k == 0:
        r = flag(O_Z)
    elif k == 1:
        r = flag(O_C)
    elif k == 2:
        r = flag(O_N)
    elif k == 3:
        r = flag(O_V)
    elif k == 4:
        r = flag(O_C) and not flag(O_Z)
    elif k == 5:
        r = flag(O_N) == flag(O_V)
    elif k == 6:
        r = flag(O_N) == flag(O_V) and not flag(O_Z)
    if (c & 1) != 0 and c != 15:
        r = not r
    return r

# Addition avec retenue et indicateurs, sur 32 ou 64 bits.
func addc(a: int, b: int, carry: int, sf: bool, setf: bool) -> int:
    if sf:
        r := a + b + carry
        if setf:
            set_flag(O_N, r < 0)
            set_flag(O_Z, r == 0)
            if carry != 0:
                set_flag(O_C, not ult(a, r))
            else:
                set_flag(O_C, ult(r, a))
            set_flag(O_V, ((a ^ r) & (b ^ r)) < 0)
        return r
    a32 := a & M32
    b32 := b & M32
    u := a32 + b32 + carry
    r := u & M32
    if setf:
        s := sext(a32, 32) + sext(b32, 32) + carry
        set_flag(O_N, ((r >> 31) & 1) != 0)
        set_flag(O_Z, r == 0)
        set_flag(O_C, (u >> 32) != 0)
        set_flag(O_V, s != sext(r, 32))
    return r

func shift_reg(v: int, typ: int, amount: int, sf: bool) -> int:
    w := 64
    if not sf:
        w = 32
        v = v & M32
    amount = amount % w
    r := 0
    if typ == 0:
        r = lsl(v, amount)
    elif typ == 1:
        r = lsr(v, amount)
    elif typ == 2:
        if sf:
            r = v >> amount
        else:
            r = (sext(v, 32) >> amount) & M32
    else:
        if amount == 0:
            r = v
        else:
            r = lsr(v, amount) | lsl(v, w - amount)
    if sf:
        return r
    return r & M32

func extend_reg(v: int, option: int, shift: int) -> int:
    if option == 0:
        v = v & 255
    elif option == 1:
        v = v & 0xFFFF
    elif option == 2:
        v = v & M32
    elif option == 4:
        v = sext(v, 8)
    elif option == 5:
        v = sext(v, 16)
    elif option == 6:
        v = sext(v, 32)
    return lsl(v, shift)

func ror(v: int, r: int, w: int) -> int:
    if r == 0:
        return v
    return (lsr(v, r) | lsl(v, w - r)) & ones(w)

func replicate(v: int, e: int, w: int) -> int:
    r := 0
    i := 0
    while i < w:
        r = r | lsl(v, i)
        i += e
    return r

# DecodeBitMasks (immédiats logiques et champs de bits) : wmask en [O_WM], tmask en [O_TM].
func decode_bit_masks(nbit: int, imms: int, immr: int, immediate: bool, w: int) -> bool:
    combined := (nbit << 6) | ((~imms) & 63)
    ln := -1
    i := 6
    while i >= 0:
        if (combined & (1 << i)) != 0:
            ln = i
            break
        i -= 1
    if ln < 1:
        return false
    levels := (1 << ln) - 1
    if immediate and (imms & levels) == levels:
        return false
    s := imms & levels
    r := immr & levels
    diff := (s - r) & levels
    esize := 1 << ln
    welem := ones(s + 1)
    telem := ones(diff + 1)
    __store64(_S + O_WM, replicate(ror(welem, r, esize), esize, w) & ones(w))
    __store64(_S + O_TM, replicate(telem, esize, w) & ones(w))
    return true

# ---- flottants : registres d (64 bits) et s (32 bits), règles NaN d'ARM ------------------------------------------
func isnan(d: float) -> bool:
    return d != d

func fbits(d: float) -> int:
    return __f2bits(d)

func fof(u: int) -> float:
    return __bits2f(u)

func getd(r: int) -> float:
    return __bits2f(qlo(r))

func setd(r: int, d: float):
    setq(r, __f2bits(d), 0)

# Simple précision : bits IEEE 754 binary32 <-> double.
func f32_to_f64(u: int) -> float:
    sign := (u >> 31) & 1
    ex := (u >> 23) & 255
    frac := u & 8388607
    if ex == 255:
        return __bits2f((sign << 63) | (2047 << 52) | (frac << 29))
    if ex == 0:
        if frac == 0:
            return __bits2f(sign << 63)
        v := __i2f(frac) * fof(3936146074321813504)   # frac × 2^-149 (exact)
        if sign != 0:
            return -v
        return v
    return __bits2f((sign << 63) | ((ex - 127 + 1023) << 52) | (frac << 29))

# arrondi au plus proche pair de m >> sh (sh >= 1)
func _rne(m: int, sh: int) -> int:
    if sh >= 63:
        return 0
    q := lsr(m, sh)
    rem := m & ones(sh)
    half := 1 << (sh - 1)
    if rem > half or (rem == half and (q & 1) != 0):
        q += 1
    return q

func f64_to_f32(d: float) -> int:
    u := __f2bits(d)
    sign := lsr(u, 63) << 31
    ex := (u >> 52) & 2047
    frac := u & ones(52)
    if ex == 2047:
        if frac == 0:
            return sign | 2139095040
        return sign | 0x7FC00000 | lsr(frac, 29)
    if ex == 0:
        return sign
    m := frac | (1 << 52)
    e := ex - 1023 + 127
    if e >= 255:
        return sign | 2139095040
    if e <= 0:
        return sign | _rne(m, 29 + 1 - e)
    q := _rne(m, 29)
    if q == (1 << 24):
        q = q >> 1
        e += 1
        if e >= 255:
            return sign | 2139095040
    return sign | (e << 23) | (q & 8388607)

func gets(r: int) -> float:
    return f32_to_f64(qlo(r) & M32)

func sets(r: int, f: float):
    setq(r, f64_to_f32(f), 0)

func is_snan(d: float) -> bool:
    return isnan(d) and (fbits(d) & (1 << 51)) == 0

func quiet(d: float) -> float:
    return fof(fbits(d) | (1 << 51))

# Résultat d'une opération : NaN d'opérande propagé (signalant d'abord, puis le premier), sinon NaN par défaut.
func arm_nan3(r: float, a: float, b: float, c: float, n: int) -> float:
    if not isnan(r):
        return r
    if n >= 1 and is_snan(a):
        return quiet(a)
    if n >= 2 and is_snan(b):
        return quiet(b)
    if n >= 3 and is_snan(c):
        return quiet(c)
    if n >= 1 and isnan(a):
        return a
    if n >= 2 and isnan(b):
        return b
    if n >= 3 and isnan(c):
        return c
    return fof(0x7FF8000000000000)

# simple précision : premier NaN d'opérande, rendu silencieux ; sinon NaN par défaut (bits binary32)
func arm_nan_f(r: float, a: float, b: float, c: float, n: int) -> int:
    if not isnan(r):
        return f64_to_f32(r)
    if n >= 1 and isnan(a):
        return f64_to_f32(a) | 0x400000
    if n >= 2 and isnan(b):
        return f64_to_f32(b) | 0x400000
    if n >= 3 and isnan(c):
        return f64_to_f32(c) | 0x400000
    return 0x7FC00000

func fcmp(a: float, b: float):
    if isnan(a) or isnan(b):
        set_nzcv(3)
    elif a == b:
        set_nzcv(6)
    elif a < b:
        set_nzcv(8)
    else:
        set_nzcv(2)

func fabs(d: float) -> float:
    return fof(fbits(d) & (~MIN))

func copysign0(r: float, d: float) -> float:
    # zéro du signe de d (trunc(-0.5) = -0.0)
    if r == 0.0:
        return fof(fbits(d) & MIN)
    return r

func ftrunc(d: float) -> float:
    if isnan(d) or fabs(d) >= 4503599627370496.0:
        return d
    return copysign0(__i2f(__f2i(d)), d)

func ffloor(d: float) -> float:
    if isnan(d) or fabs(d) >= 4503599627370496.0:
        return d
    t := ftrunc(d)
    if t > d:
        t = t - 1.0
    return copysign0(t, d)

func fceil(d: float) -> float:
    if isnan(d) or fabs(d) >= 4503599627370496.0:
        return d
    t := ftrunc(d)
    if t < d:
        t = t + 1.0
    return copysign0(t, d)

# 0 au plus proche pair, 1 vers +inf, 2 vers -inf, 3 vers zéro, 4 au plus proche (milieux loin de zéro)
func round_mode(d: float, mode: int) -> float:
    if mode == 1:
        return fceil(d)
    if mode == 2:
        return ffloor(d)
    if mode == 3:
        return ftrunc(d)
    if isnan(d) or fabs(d) >= 4503599627370496.0:
        return d
    t := ftrunc(d)
    f := fabs(d - t)
    sg := 1.0
    if d < 0.0:
        sg = -1.0
    if f > 0.5:
        t = t + sg
    elif f == 0.5:
        if mode == 4:
            t = t + sg
        else:
            ti := __f2i(t)
            if (ti & 1) != 0:
                t = t + sg
    return copysign0(t, d)

func u2f(u: int) -> float:
    if u >= 0:
        return __i2f(u)
    return __i2f(lsr(u, 1) | (u & 1)) * 2.0

# Conversion saturante d'ARM (FCVT*S / FCVT*U) : NaN -> 0.
func fcvt_int(d: float, mode: int, sgn: bool, sf: bool) -> int:
    if isnan(d):
        return 0
    r := round_mode(d, mode)
    if sgn:
        lo := -2147483648.0
        hi := 2147483648.0
        if sf:
            lo = -9223372036854775808.0
            hi = 9223372036854775808.0
        v := 0
        if r < lo:
            v = MIN
            if not sf:
                v = -0x80000000
        elif r >= hi:
            v = MIN - 1
            if not sf:
                v = 2147483647
        else:
            v = __f2i(r)
        if sf:
            return v
        return v & M32
    hiu := 4294967296.0
    if sf:
        hiu = 18446744073709551616.0
    if r <= 0.0:
        return 0
    if r >= hiu:
        if sf:
            return -1
        return M32
    if r >= 9223372036854775808.0:
        return __f2i(r - 9223372036854775808.0) + MIN
    return __f2i(r)

# VFPExpandImm (double)
func fp_imm8(imm8: int) -> float:
    sign := (imm8 >> 7) & 1
    b6 := (imm8 >> 6) & 1
    ex := ((b6 ^ 1) << 10) | ((imm8 >> 4) & 3)
    if b6 != 0:
        ex = ex | 1020
    return fof((sign << 63) | (ex << 52) | ((imm8 & 15) << 48))

# multiplication-addition : produit exact (Dekker) puis somme compensée
func _split(a: float) -> float:
    c := 134217729.0 * a
    return c - (c - a)

func ffma(a: float, b: float, c: float) -> float:
    p := a * b
    if isnan(p) or isnan(c) or fabs(p) > 1e300 or fabs(c) > 1e300 or p == 0.0:
        return p + c
    ah := _split(a)
    al := a - ah
    bh := _split(b)
    bl := b - bh
    e := ((ah * bh - p) + ah * bl + al * bh) + al * bl
    s := p + c
    bb := s - p
    t := (p - (s - bb)) + (c - bb)
    return s + (t + e)

func fmax_c(a: float, b: float) -> float:
    if isnan(a):
        return b
    if isnan(b):
        return a
    if a == 0.0 and b == 0.0:
        if fbits(a) < 0:
            return b
        return a
    if a > b:
        return a
    return b

func fmin_c(a: float, b: float) -> float:
    if isnan(a):
        return b
    if isnan(b):
        return a
    if a == 0.0 and b == 0.0:
        if fbits(a) < 0:
            return a
        return b
    if a < b:
        return a
    return b

# ---- appels système Linux AArch64 -> hôte x86-64 ----------------------------------------------------------------
# O_DIRECTORY, O_NOFOLLOW, O_LARGEFILE diffèrent entre AArch64 et x86-64
func open_flags(f: int) -> int:
    h := f & (~(16384 | 32768 | 131072))
    if (f & 16384) != 0:
        h = h | 65536
    if (f & 32768) != 0:
        h = h | 131072
    return h

# struct stat x86-64 (144 octets) -> struct stat d'asm-generic (128 octets)
func stat_to_arm(s: int, out: int):
    i := 0
    while i < 128:
        __store64(out + i, 0)
        i += 8
    __store64(out, __load64(s))
    __store64(out + 8, __load64(s + 8))
    __store32(out + 16, __load32(s + 24))
    __store32(out + 20, __load64(s + 16) & M32)
    __store32(out + 24, __load32(s + 28))
    __store32(out + 28, __load32(s + 32))
    __store64(out + 32, __load64(s + 40))
    __store64(out + 48, __load64(s + 48))
    __store32(out + 56, __load64(s + 56) & M32)
    __store64(out + 64, __load64(s + 64))
    __store64(out + 72, __load64(s + 72))
    __store64(out + 80, __load64(s + 80))
    __store64(out + 88, __load64(s + 88))
    __store64(out + 96, __load64(s + 96))
    __store64(out + 104, __load64(s + 104))
    __store64(out + 112, __load64(s + 112))

func _cstrlen(p: int) -> int:
    n := 0
    while __load8(p + n) != 0:
        n += 1
    return n

# relais direct : numéro AArch64 -> numéro x86-64 (même sens des arguments, mêmes structures)
func _relay(nr: int) -> int:
    if nr == 63:
        return 0
    if nr == 64:
        return 1
    if nr == 57:
        return 3
    if nr == 62:
        return 8
    if nr == 226:
        return 10
    if nr == 215:
        return 11
    if nr == 172:
        return 39
    if nr == 173:
        return 110
    if nr == 49:
        return 80
    if nr == 34:
        return 258
    if nr == 35:
        return 263
    if nr == 113:
        return 228
    if nr == 101:
        return 35
    if nr == 278:
        return 318
    if nr == 61:
        return 217
    if nr == 78:
        return 267
    if nr == 23:
        return 32
    if nr == 24:
        return 292
    if nr == 59:
        return 293
    if nr == 260:
        return 61
    if nr == 129:
        return 62
    if nr == 48:
        return 269
    if nr == 25:
        return 72
    if nr == 29:
        return 16
    if nr == 38:
        return 264
    if nr == 37:
        return 265
    if nr == 36:
        return 266
    if nr == 53:
        return 268
    if nr == 54:
        return 260
    if nr == 166:
        return 95
    if nr == 163:
        return 97
    if nr == 164:
        return 160
    if nr == 174:
        return 102
    if nr == 175:
        return 107
    if nr == 176:
        return 104
    if nr == 177:
        return 108
    if nr == 146:
        return 105
    if nr == 144:
        return 106
    if nr == 154:
        return 109
    if nr == 155:
        return 121
    if nr == 158:
        return 115
    if nr == 159:
        return 116
    if nr == 147:
        return 117
    if nr == 148:
        return 118
    if nr == 149:
        return 119
    if nr == 150:
        return 120
    if nr == 115:
        return 230
    if nr == 198:
        return 41
    if nr == 200:
        return 49
    if nr == 201:
        return 50
    if nr == 202:
        return 43
    if nr == 203:
        return 42
    if nr == 205:
        return 52
    if nr == 206:
        return 44
    if nr == 207:
        return 45
    return -1

func do_syscall() -> int:
    nr := getx(8)
    a := getx(0)
    b := getx(1)
    c := getx(2)
    d := getx(3)
    e := getx(4)
    f := getx(5)
    if nr == 56:
        return __syscall(257, a, b, open_flags(c), d)
    if nr == 79:
        s := __alloc_raw(256)
        r := __syscall(262, a, b, s, d)
        if r == 0:
            stat_to_arm(s, c)
        return r
    if nr == 80:
        s := __alloc_raw(256)
        r := __syscall(5, a, s)
        if r == 0:
            stat_to_arm(s, b)
        return r
    if nr == 222:
        return __syscall(9, a, b, c, d, e, f)
    if nr == 93 or nr == 94:
        __flush()
        __syscall(231, a & 255)
        return 0
    if nr == 160:
        r := __syscall(63, a)
        if r == 0:
            m := a + 4 * 65
            i := 0
            while i < 65:
                __store8(m + i, 0)
                i += 1
            # « aarch64 »
            __store64(m, 14696520761893217)
        return r
    if nr == 17:
        r := __syscall(79, a, b)
        if r < 0:
            return r
        return _cstrlen(a) + 1
    if nr == 220:
        # clone(SIGCHLD, 0, ...) : fork ; l'émulateur entier est dupliqué, l'invité avec lui
        if (a & 255) == 17 and b == 0:
            return __syscall(57)
        return -38
    if nr == 221:
        return -38
    if nr == 214:
        return -12
    if nr == 81:
        __syscall(162)
        return 0
    if nr == 134:
        # rt_sigaction : seulement SIG_DFL / SIG_IGN (pas de gestionnaire invité)
        h := 0
        if b != 0:
            h = __load64(b)
        if b != 0 and h > 1:
            return -38
        act := __alloc_raw(64)
        old := __alloc_raw(64)
        i := 0
        while i < 64:
            __store64(act + i, 0)
            __store64(old + i, 0)
            i += 8
        __store64(act, h)
        pact := 0
        if b != 0:
            pact = act
        r := __syscall(13, a, pact, old, 8)
        if r < 0:
            return r
        if c != 0:
            k := 0
            while k < 32:
                __store64(c + k, 0)
                k += 8
            if __load64(old) == 1:
                __store64(c, 1)
        return 0
    if nr == 96:
        return __syscall(39)
    if nr == 99:
        return 0
    h := _relay(nr)
    if h >= 0:
        return __syscall(h, a, b, c, d, e, f)
    _e("a64run: appel système " + __int_to_str(nr) + " non pris en charge (ENOSYS)\n")
    return -38

# ---- exécution --------------------------------------------------------------------------------------------------
func undef(w: int):
    die("instruction non prise en charge " + _hex(w) + " à pc=" + _hex(pc()))

# Accroche (chargeur hôte, par exemple d'exécutables Windows ARM64) : fonction appelée pour une adresse interceptée [lo, hi) au lieu de l'exécuter.
func set_trap(lo: int, hi: int):
    __store64(_S + O_TRAP_LO, lo)
    __store64(_S + O_TRAP_HI, hi)

func step():
    p := pc()
    lo := __load64(_S + O_TRAP_LO)
    if lo != 0 and not ult(p, lo) and ult(p, __load64(_S + O_TRAP_HI)):
        trap(p)
        return
    w := __load32(p)
    if __load64(_S + O_TRACE) != 0:
        _e(_hex(p) + ": " + _hex(w) + "\n")
    __store64(_S + O_COUNT, __load64(_S + O_COUNT) + 1)
    nxt := p + 4
    op0 := bits(w, 28, 25)
    if (op0 & 14) == 8:
        data_imm(w)
    elif (op0 & 14) == 10:
        nxt = branch_sys(w, p, nxt)
    elif (op0 & 5) == 4:
        load_store(w)
    elif (op0 & 7) == 5:
        data_reg(w)
    elif (op0 & 7) == 7:
        fp_simd(w)
    else:
        undef(w)
    set_pc(nxt)

# Fonction interceptée : rien par défaut (l'émulateur Windows ARM64 remplace trap).
func trap(p: int):
    die("adresse interceptée sans gestionnaire : " + _hex(p))

func data_imm(w: int):
    op := bits(w, 25, 23)
    rd := bits(w, 4, 0)
    rn := bits(w, 9, 5)
    sf := bits(w, 31, 31) != 0
    if op == 0 or op == 1:
        # ADR / ADRP
        imm := sext((bits(w, 23, 5) << 2) | bits(w, 30, 29), 21)
        if bits(w, 31, 31) != 0:
            setx(rd, (pc() & (~4095)) + (imm << 12))
        else:
            setx(rd, pc() + imm)
    elif op == 2:
        # ADD/SUB immédiat
        imm := bits(w, 21, 10)
        if bits(w, 22, 22) != 0:
            imm = imm << 12
        sub := bits(w, 30, 30) != 0
        s := bits(w, 29, 29) != 0
        a := xs(rn)
        r := 0
        if sub:
            r = addc(a, ~imm, 1, sf, s)
        else:
            r = addc(a, imm, 0, sf, s)
        if s:
            setx(rd, r)
        else:
            setxs(rd, r)
    elif op == 4:
        # logique immédiat
        width := 32
        if sf:
            width = 64
        if not decode_bit_masks(bits(w, 22, 22), bits(w, 15, 10), bits(w, 21, 16), true, width):
            undef(w)
        wm := __load64(_S + O_WM)
        a := xr(rn)
        opc := bits(w, 30, 29)
        r := 0
        if opc == 0 or opc == 3:
            r = a & wm
        elif opc == 1:
            r = a | wm
        else:
            r = a ^ wm
        if not sf:
            r = r & M32
        if opc == 3:
            if sf:
                set_flag(O_N, r < 0)
            else:
                set_flag(O_N, ((r >> 31) & 1) != 0)
            set_flag(O_Z, r == 0)
            set_flag(O_C, false)
            set_flag(O_V, false)
            setx(rd, r)
        else:
            setxs(rd, r)
    elif op == 5:
        # MOVN / MOVZ / MOVK
        hw := bits(w, 22, 21)
        imm := lsl(bits(w, 20, 5), 16 * hw)
        opc := bits(w, 30, 29)
        r := 0
        if opc == 0:
            r = ~imm
        elif opc == 2:
            r = imm
        elif opc == 3:
            r = (xr(rd) & (~lsl(0xFFFF, 16 * hw))) | imm
        else:
            undef(w)
        if not sf:
            r = r & M32
        setx(rd, r)
    elif op == 6:
        # SBFM / BFM / UBFM
        width := 32
        if sf:
            width = 64
        immr := bits(w, 21, 16)
        imms := bits(w, 15, 10)
        if not decode_bit_masks(bits(w, 22, 22), imms, immr, false, width):
            undef(w)
        wm := __load64(_S + O_WM)
        tm := __load64(_S + O_TM)
        opc := bits(w, 30, 29)
        src := xr(rn) & ones(width)
        bot := ror(src, immr, width) & wm
        r := 0
        if opc == 1:
            dst := xr(rd) & ones(width)
            b2 := (dst & (~wm)) | bot
            r = (dst & (~tm)) | (b2 & tm)
        else:
            top := 0
            if opc == 0 and (lsr(src, imms) & 1) != 0:
                top = ones(width)
            r = (top & (~tm)) | (bot & tm)
        setx(rd, r & ones(width))
    elif op == 7:
        # EXTR
        width := 32
        if sf:
            width = 64
        lsb := bits(w, 15, 10)
        rm := bits(w, 20, 16)
        hi := xr(rn) & ones(width)
        lo := xr(rm) & ones(width)
        r := lo
        if lsb != 0:
            r = lsr(lo, lsb) | lsl(hi, width - lsb)
        setx(rd, r & ones(width))
    else:
        undef(w)

func branch_sys(w: int, p: int, nxt: int) -> int:
    if (w & 0x7C000000) == 0x14000000:
        # B / BL
        off := sext(bits(w, 25, 0), 26) * 4
        if (w & 0x80000000) != 0:
            setx(30, nxt)
        return p + off
    if (w & 0xFF000010) == 0x54000000:
        # B.cond
        if cond(bits(w, 3, 0)):
            return p + sext(bits(w, 23, 5), 19) * 4
        return nxt
    if (w & 0x7E000000) == 0x34000000:
        # CBZ / CBNZ
        v := xr(bits(w, 4, 0))
        if (w & 0x80000000) == 0:
            v = v & M32
        nz := (w & 0x1000000) != 0
        if (v != 0) == nz:
            return p + sext(bits(w, 23, 5), 19) * 4
        return nxt
    if (w & 0x7E000000) == 0x36000000:
        # TBZ / TBNZ
        bit := (bits(w, 31, 31) << 5) | bits(w, 23, 19)
        bset := (lsr(xr(bits(w, 4, 0)), bit) & 1) != 0
        if bset == ((w & 0x1000000) != 0):
            return p + sext(bits(w, 18, 5), 14) * 4
        return nxt
    if (w & 0xFE1FFC1F) == 0xD61F0000:
        # BR / BLR / RET
        opc := bits(w, 24, 21)
        target := xr(bits(w, 9, 5))
        if opc == 1:
            setx(30, nxt)
        elif opc != 0 and opc != 2:
            undef(w)
        return target
    if (w & 0xFFE0001F) == 0xD4000001:
        # SVC
        if __load64(_S + O_NOSVC) != 0:
            die("appel système Linux dans un exécutable Windows (svc à pc=" + _hex(p) + ")")
        setx(0, do_syscall())
        return nxt
    if (w & 0xFFE0001F) == 0xD4200000:
        # BRK
        die("brk #" + __int_to_str(bits(w, 20, 5)) + " à pc=" + _hex(p))
    if (w & 0xFFFFF01F) == 0xD503201F or (w & 0xFFFFF01F) == 0xD503301F:
        # hints, barrières
        return nxt
    if (w & 0xFFF00000) == 0xD5300000:
        # MRS
        sysreg := bits(w, 19, 5)
        v := 0
        if sysreg == 0x5A20 or sysreg == 0x5A21:
            v = 0
        elif sysreg == 0x5F02:
            v = 0x1000000
        elif sysreg == 0x5F01:
            v = __load64(_S + O_COUNT)
        else:
            undef(w)
        setx(bits(w, 4, 0), v)
        return nxt
    if (w & 0xFFF00000) == 0xD5100000:
        # MSR (FPCR / FPSR ignorés)
        sysreg := bits(w, 19, 5)
        if sysreg != 0x5A20 and sysreg != 0x5A21:
            undef(w)
        return nxt
    undef(w)
    return nxt

# copie de n octets entre la mémoire et un registre q
func q_load(r: int, addr: int, n: int):
    lo := 0
    hi := 0
    i := 0
    while i < n:
        b := __load8(addr + i)
        if i < 8:
            lo = lo | (b << (8 * i))
        else:
            hi = hi | (b << (8 * (i - 8)))
        i += 1
    setq(r, lo, hi)

func q_store(r: int, addr: int, n: int):
    lo := qlo(r)
    hi := qhi(r)
    i := 0
    while i < n:
        b := 0
        if i < 8:
            b = lsr(lo, 8 * i) & 255
        else:
            b = lsr(hi, 8 * (i - 8)) & 255
        __store8(addr + i, b)
        i += 1

func load_store_reg(size: int, vec: bool, opc: int, addr: int, rt: int, w: int):
    if vec:
        n := 1 << size
        if (opc & 2) != 0:
            n = 16
        if (opc & 1) != 0:
            q_load(rt, addr, n)
        else:
            q_store(rt, addr, n)
        return
    if opc == 0:
        if size == 0:
            __store8(addr, xr(rt) & 255)
        elif size == 1:
            __store16(addr, xr(rt) & 0xFFFF)
        elif size == 2:
            __store32(addr, xr(rt) & M32)
        else:
            __store64(addr, xr(rt))
    elif opc == 1:
        if size == 0:
            setx(rt, __load8(addr))
        elif size == 1:
            setx(rt, __load16(addr))
        elif size == 2:
            setx(rt, __load32(addr))
        else:
            setx(rt, __load64(addr))
    elif opc == 2:
        if size == 0:
            setx(rt, sext(__load8(addr), 8))
        elif size == 1:
            setx(rt, sext(__load16(addr), 16))
        elif size == 2:
            setx(rt, sext(__load32(addr), 32))
    else:
        if size == 0:
            setx(rt, sext(__load8(addr), 8) & M32)
        elif size == 1:
            setx(rt, sext(__load16(addr), 16) & M32)
        else:
            undef(w)

func load_store(w: int):
    rt := bits(w, 4, 0)
    rn := bits(w, 9, 5)
    vec := bits(w, 26, 26) != 0
    if (w & 0x3F000000) == 0x8000000:
        # exclusifs, acquisition / libération
        size := bits(w, 31, 30)
        o2 := bits(w, 23, 23) != 0
        load := bits(w, 22, 22) != 0
        o1 := bits(w, 21, 21) != 0
        rs := bits(w, 20, 16)
        addr := base(rn)
        if o1:
            undef(w)
        if (addr & ((1 << size) - 1)) != 0:
            die("accès exclusif / atomique non aligné (" + _hex(addr) + ") à pc=" + _hex(pc()))
        if load:
            load_store_reg(size, false, 1, addr, rt, w)
            if not o2:
                __store64(_S + O_EXCL, addr)
        elif not o2:
            ok := __load64(_S + O_EXCL) == addr
            __store64(_S + O_EXCL, 0)
            if ok:
                load_store_reg(size, false, 0, addr, rt, w)
                setx(rs, 0)
            else:
                setx(rs, 1)
        else:
            load_store_reg(size, false, 0, addr, rt, w)
        return
    if (w & 0x3B000000) == 0x18000000:
        # chargement littéral
        addr := pc() + sext(bits(w, 23, 5), 19) * 4
        opc := bits(w, 31, 30)
        if vec:
            n := 16
            if opc == 0:
                n = 4
            elif opc == 1:
                n = 8
            q_load(rt, addr, n)
        elif opc == 0:
            setx(rt, __load32(addr))
        elif opc == 1:
            setx(rt, __load64(addr))
        elif opc == 2:
            setx(rt, sext(__load32(addr), 32))
        return
    if (w & 0x38000000) == 0x28000000:
        # paires
        opc := bits(w, 31, 30)
        idx := bits(w, 24, 23)
        load := bits(w, 22, 22) != 0
        rt2 := bits(w, 14, 10)
        scale := 2 + (opc >> 1)
        if vec:
            scale = 2 + opc
        off := sext(bits(w, 21, 15), 7) << scale
        b := base(rn)
        addr := b + off
        if idx == 1:
            addr = b
        n := 1 << scale
        if vec:
            k := 0
            while k < 2:
                r := rt
                if k == 1:
                    r = rt2
                if load:
                    q_load(r, addr + k * n, n)
                else:
                    q_store(r, addr + k * n, n)
                k += 1
        elif load:
            v1 := 0
            v2 := 0
            if n == 8:
                v1 = __load64(addr)
                v2 = __load64(addr + 8)
            elif opc == 1:
                v1 = sext(__load32(addr), 32)
                v2 = sext(__load32(addr + 4), 32)
            else:
                v1 = __load32(addr)
                v2 = __load32(addr + 4)
            setx(rt, v1)
            setx(rt2, v2)
        else:
            if n == 8:
                __store64(addr, xr(rt))
                __store64(addr + 8, xr(rt2))
            else:
                __store32(addr, xr(rt) & M32)
                __store32(addr + 4, xr(rt2) & M32)
        if idx == 1 or idx == 3:
            setxs(rn, b + off)
        return
    if (w & 0x38000000) == 0x38000000:
        # registre unique
        size := bits(w, 31, 30)
        opc := bits(w, 23, 22)
        scale := size
        if vec and (opc & 2) != 0:
            scale = 4
        if not vec and size == 3 and opc == 2:
            return
        if bits(w, 24, 24) != 0:
            addr := base(rn) + (bits(w, 21, 10) << scale)
            load_store_reg(size, vec, opc, addr, rt, w)
            return
        if bits(w, 21, 21) != 0:
            if bits(w, 11, 10) != 2:
                undef(w)
            rm := bits(w, 20, 16)
            option := bits(w, 15, 13)
            sh := 0
            if bits(w, 12, 12) != 0:
                sh = scale
            addr := base(rn) + extend_reg(xr(rm), option, sh)
            load_store_reg(size, vec, opc, addr, rt, w)
            return
        imm := sext(bits(w, 20, 12), 9)
        mode := bits(w, 11, 10)
        b := base(rn)
        if mode == 0 or mode == 2:
            load_store_reg(size, vec, opc, b + imm, rt, w)
        elif mode == 1:
            load_store_reg(size, vec, opc, b, rt, w)
            setxs(rn, b + imm)
        else:
            load_store_reg(size, vec, opc, b + imm, rt, w)
            setxs(rn, b + imm)
        return
    undef(w)

func data_reg(w: int):
    rd := bits(w, 4, 0)
    rn := bits(w, 9, 5)
    rm := bits(w, 20, 16)
    sf := bits(w, 31, 31) != 0
    mask := M32
    if sf:
        mask = -1
    if (w & 0x1F000000) == 0xA000000:
        # logique, registre décalé
        opc := bits(w, 30, 29)
        b := shift_reg(xr(rm), bits(w, 23, 22), bits(w, 15, 10), sf)
        if bits(w, 21, 21) != 0:
            b = (~b) & mask
        a := xr(rn) & mask
        r := 0
        if opc == 0 or opc == 3:
            r = a & b
        elif opc == 1:
            r = a | b
        else:
            r = a ^ b
        r = r & mask
        if opc == 3:
            if sf:
                set_flag(O_N, r < 0)
            else:
                set_flag(O_N, ((r >> 31) & 1) != 0)
            set_flag(O_Z, r == 0)
            set_flag(O_C, false)
            set_flag(O_V, false)
        setx(rd, r)
        return
    if (w & 0x1F200000) == 0xB000000:
        # ADD/SUB registre décalé
        sub := bits(w, 30, 30) != 0
        s := bits(w, 29, 29) != 0
        b := shift_reg(xr(rm), bits(w, 23, 22), bits(w, 15, 10), sf)
        r := 0
        if sub:
            r = addc(xr(rn), ~b, 1, sf, s)
        else:
            r = addc(xr(rn), b, 0, sf, s)
        setx(rd, r)
        return
    if (w & 0x1F200000) == 0xB200000:
        # ADD/SUB registre étendu
        sub := bits(w, 30, 30) != 0
        s := bits(w, 29, 29) != 0
        b := extend_reg(xr(rm), bits(w, 15, 13), bits(w, 12, 10))
        r := 0
        if sub:
            r = addc(xs(rn), ~b, 1, sf, s)
        else:
            r = addc(xs(rn), b, 0, sf, s)
        if s:
            setx(rd, r)
        else:
            setxs(rd, r)
        return
    if (w & 0x1FE00000) == 0x1A000000:
        # ADC / SBC
        sub := bits(w, 30, 30) != 0
        s := bits(w, 29, 29) != 0
        b := xr(rm)
        if sub:
            b = ~b
        cin := 0
        if flag(O_C):
            cin = 1
        setx(rd, addc(xr(rn), b, cin, sf, s))
        return
    if (w & 0x1FE00000) == 0x1A400000:
        # CCMN / CCMP
        sub := bits(w, 30, 30) != 0
        if cond(bits(w, 15, 12)):
            b := xr(rm)
            if bits(w, 11, 11) != 0:
                b = rm
            if sub:
                addc(xr(rn), ~b, 1, sf, true)
            else:
                addc(xr(rn), b, 0, sf, true)
        else:
            set_nzcv(bits(w, 3, 0))
        return
    if (w & 0x1FE00000) == 0x1A800000:
        # CSEL / CSINC / CSINV / CSNEG
        op := bits(w, 30, 30)
        op2 := bits(w, 11, 10)
        r := 0
        if cond(bits(w, 15, 12)):
            r = xr(rn)
        else:
            r = xr(rm)
            if op == 0 and op2 == 1:
                r = r + 1
            elif op == 1 and op2 == 0:
                r = ~r
            elif op == 1 and op2 == 1:
                r = 0 - r
        setx(rd, r & mask)
        return
    if (w & 0x5FE00000) == 0x1AC00000:
        # 2 sources
        opc := bits(w, 15, 10)
        a := xr(rn) & mask
        b := xr(rm) & mask
        r := 0
        width := 32
        if sf:
            width = 64
        if opc == 2:
            r = udiv(a, b)
        elif opc == 3:
            if sf:
                r = sdiv(a, b)
            else:
                r = sdiv(sext(a, 32), sext(b, 32)) & M32
        elif opc >= 8 and opc <= 11:
            r = shift_reg(a, opc - 8, b & (width - 1), sf)
        else:
            undef(w)
        setx(rd, r & mask)
        return
    if (w & 0x5FE00000) == 0x5AC00000:
        # 1 source
        opc := bits(w, 15, 10)
        a := xr(rn) & mask
        r := 0
        width := 32
        if sf:
            width = 64
        if opc == 0:
            i := 0
            while i < width:
                if (lsr(a, i) & 1) != 0:
                    r = r | lsl(1, width - 1 - i)
                i += 1
        elif opc == 1:
            i := 0
            while i < width:
                r = r | lsl(((lsr(a, i) & 255) << 8) | (lsr(a, i + 8) & 255), i)
                i += 16
        elif opc == 2 or opc == 3:
            # REV32 (opc 2, sf) ou REV (32 / 64 bits)
            step_ := width
            if opc == 2 and sf:
                step_ = 32
            i := 0
            while i < width:
                k := 0
                nb := step_ // 8
                while k < nb:
                    bt := lsr(a, i + 8 * k) & 255
                    r = r | lsl(bt, i + 8 * (nb - 1 - k))
                    k += 1
                i += step_
        elif opc == 4:
            r = clz(a, width)
        elif opc == 5:
            x := (a ^ lsr(a, 1)) & ones(width - 1)
            if x == 0:
                r = width - 1
            else:
                r = clz(x, width) - 1
        else:
            undef(w)
        setx(rd, r & mask)
        return
    if (w & 0x1F000000) == 0x1B000000:
        # 3 sources
        op31 := bits(w, 23, 21)
        o0 := bits(w, 15, 15) != 0
        ra := bits(w, 14, 10)
        a := xr(rn)
        b := xr(rm)
        acc := xr(ra)
        r := 0
        if op31 == 0:
            if o0:
                r = acc - a * b
            else:
                r = acc + a * b
        elif op31 == 1:
            pr := sext(a, 32) * sext(b, 32)
            if o0:
                r = acc - pr
            else:
                r = acc + pr
        elif op31 == 2:
            r = smulh(a, b)
        elif op31 == 5:
            pr := (a & M32) * (b & M32)
            if o0:
                r = acc - pr
            else:
                r = acc + pr
        elif op31 == 6:
            r = umulh(a, b)
        else:
            undef(w)
        if not sf:
            r = r & M32
        setx(rd, r)
        return
    undef(w)

func fp_simd(w: int):
    rd := bits(w, 4, 0)
    rn := bits(w, 9, 5)
    rm := bits(w, 20, 16)
    # SIMD utilisés pour les copies et mises à zéro : MOVI #0, ORR (MOV) vectoriel, DUP / INS de x.
    if (w & 0xBFFFFC00) == 0x2F00E400:
        setq(rd, 0, 0)
        return
    if (w & 0xBFE0FC00) == 0xEA01C00 and rn == rm:
        hi := 0
        if (w & 0x40000000) != 0:
            hi = qhi(rn)
        setq(rd, qlo(rn), hi)
        return
    if (w & 0xFFFFFC00) == 0x4E080C00:
        setq(rd, xr(rn), xr(rn))
        return
    if (w & 0xBFE0FC00) == 0xE003C00 or (w & 0xFFE0FC00) == 0x4E001C00:
        imm5 := bits(w, 20, 16)
        size := -1
        if (imm5 & 1) != 0:
            size = 0
        elif (imm5 & 2) != 0:
            size = 1
        elif (imm5 & 4) != 0:
            size = 2
        elif (imm5 & 8) != 0:
            size = 3
        if size < 0:
            undef(w)
        idx := imm5 >> (size + 1)
        nb := 1 << size
        if (w & 0xBFE0FC00) == 0xE003C00:
            # UMOV Rd, Vn.T[i]
            r := 0
            i := 0
            while i < nb:
                pos := idx * nb + i
                bt := 0
                if pos < 8:
                    bt = lsr(qlo(rn), 8 * pos) & 255
                else:
                    bt = lsr(qhi(rn), 8 * (pos - 8)) & 255
                r = r | (bt << (8 * i))
                i += 1
            setx(rd, r)
        else:
            # INS Vd.T[i], Rn
            lo := qlo(rd)
            hi := qhi(rd)
            x := xr(rn)
            i := 0
            while i < nb:
                pos := idx * nb + i
                bt := lsr(x, 8 * i) & 255
                if pos < 8:
                    lo = (lo & (~lsl(255, 8 * pos))) | lsl(bt, 8 * pos)
                else:
                    hi = (hi & (~lsl(255, 8 * (pos - 8)))) | lsl(bt, 8 * (pos - 8))
                i += 1
            setq(rd, lo, hi)
        return
    if (w & 0xDFBFFC00) == 0x5E21D800 or (w & 0xDFBFFC00) == 0x5EA1B800:
        # SCVTF/UCVTF, FCVTZS/FCVTZU scalaires (registres v)
        dbl2 := (w & 0x400000) != 0
        uns := (w & 0x20000000) != 0
        to_fp := (w & 0xF000) == 0xD000
        if to_fp:
            if dbl2:
                if uns:
                    setd(rd, u2f(qlo(rn)))
                else:
                    setd(rd, __i2f(qlo(rn)))
            else:
                u := qlo(rn) & M32
                if uns:
                    sets(rd, __i2f(u))
                else:
                    sets(rd, __i2f(sext(u, 32)))
        else:
            d := 0.0
            if dbl2:
                d = getd(rn)
            else:
                d = gets(rn)
            r := fcvt_int(d, 3, not uns, dbl2)
            if not dbl2:
                r = r & M32
            setq(rd, r, 0)
        return
    if (w & 0xBFFFFC00) == 0xE205800:
        # CNT Vd.8B / 16B
        nb := 8
        if (w & 0x40000000) != 0:
            nb = 16
        lo := 0
        hi := 0
        i := 0
        while i < nb:
            if i < 8:
                lo = lo | (popcount8(lsr(qlo(rn), 8 * i) & 255) << (8 * i))
            else:
                hi = hi | (popcount8(lsr(qhi(rn), 8 * (i - 8)) & 255) << (8 * (i - 8)))
            i += 1
        setq(rd, lo, hi)
        return
    if (w & 0xBFFFFC00) == 0x2E303800:
        # UADDLV Hd, Vn.8B / 16B
        nb := 8
        if (w & 0x40000000) != 0:
            nb = 16
        total := 0
        i := 0
        while i < nb:
            if i < 8:
                total += lsr(qlo(rn), 8 * i) & 255
            else:
                total += lsr(qhi(rn), 8 * (i - 8)) & 255
            i += 1
        setq(rd, total & 0xFFFF, 0)
        return
    if (w & 0x5F000000) != 0x1E000000 and (w & 0x5F000000) != 0x1F000000:
        undef(w)
    typ := bits(w, 23, 22)
    dbl := typ == 1
    if typ != 0 and typ != 1:
        undef(w)
    if (w & 0x5F000000) == 0x1F000000:
        # FMADD / FMSUB / FNMADD / FNMSUB
        ra := bits(w, 14, 10)
        o1 := bits(w, 21, 21) != 0
        o0 := bits(w, 15, 15) != 0
        neg_n := o0 != o1
        neg_a := o1
        if dbl:
            n := getd(rn)
            m := getd(rm)
            a := getd(ra)
            nn := n
            if neg_n:
                nn = -n
            aa := a
            if neg_a:
                aa = -a
            setd(rd, arm_nan3(ffma(nn, m, aa), a, n, m, 3))
        else:
            n := gets(rn)
            m := gets(rm)
            a := gets(ra)
            nn := n
            if neg_n:
                nn = -n
            aa := a
            if neg_a:
                aa = -a
            setq(rd, arm_nan_f(ffma(nn, m, aa), a, n, m, 3), 0)
        return
    if bits(w, 21, 21) == 0:
        # conversions en virgule fixe (#fbits)
        sf := bits(w, 31, 31) != 0
        rmode := bits(w, 20, 19)
        opcode := bits(w, 18, 16)
        fb := 64 - bits(w, 15, 10)
        scale := fof((1023 + fb) << 52)
        if rmode == 0 and (opcode == 2 or opcode == 3):
            v := xr(rn)
            d := 0.0
            if opcode == 2:
                if sf:
                    d = __i2f(v)
                else:
                    d = __i2f(sext(v, 32))
            else:
                if sf:
                    d = u2f(v)
                else:
                    d = __i2f(v & M32)
            d = d / scale
            if dbl:
                setd(rd, d)
            else:
                sets(rd, d)
            return
        if rmode == 3 and (opcode == 0 or opcode == 1):
            d := 0.0
            if dbl:
                d = getd(rn)
            else:
                d = gets(rn)
            setx(rd, fcvt_int(d * scale, 3, opcode == 0, sf))
            return
        undef(w)
    if bits(w, 15, 10) == 0:
        # conversions entier <-> flottant, FMOV général
        sf := bits(w, 31, 31) != 0
        rmode := bits(w, 20, 19)
        opcode := bits(w, 18, 16)
        if opcode == 6 and rmode == 0:
            if dbl:
                setx(rd, qlo(rn))
            else:
                setx(rd, qlo(rn) & M32)
            if not sf and dbl:
                undef(w)
            return
        if opcode == 7 and rmode == 0:
            if dbl:
                setq(rd, xr(rn), 0)
            else:
                setq(rd, xr(rn) & M32, 0)
            return
        if rmode == 0 and (opcode == 2 or opcode == 3):
            v := xr(rn)
            d := 0.0
            if opcode == 2:
                if sf:
                    d = __i2f(v)
                else:
                    d = __i2f(sext(v, 32))
            else:
                if sf:
                    d = u2f(v)
                else:
                    d = __i2f(v & M32)
            if dbl:
                setd(rd, d)
            else:
                sets(rd, d)
            return
        if opcode <= 1 or opcode == 4 or opcode == 5:
            d := 0.0
            if dbl:
                d = getd(rn)
            else:
                d = gets(rn)
            mode := rmode
            if opcode >= 4:
                mode = 4
            setx(rd, fcvt_int(d, mode, (opcode & 1) == 0, sf))
            return
        undef(w)
    if bits(w, 14, 10) == 16:
        # 1 source
        opcode := bits(w, 20, 15)
        if dbl:
            a := getd(rn)
            if opcode == 0:
                setd(rd, a)
            elif opcode == 1:
                setd(rd, fof(fbits(a) & (~MIN)))
            elif opcode == 2:
                setd(rd, fof(fbits(a) ^ MIN))
            elif opcode == 3:
                setd(rd, arm_nan3(__fsqrt(a), a, 0.0, 0.0, 1))
            elif opcode == 4:
                setq(rd, arm_nan_f(a, 0.0, 0.0, 0.0, 0), 0)
            elif opcode == 8 or opcode == 9 or opcode == 10 or opcode == 11 or opcode == 12 or opcode == 14 or opcode == 15:
                if isnan(a):
                    setd(rd, arm_nan3(a, a, 0.0, 0.0, 1))
                else:
                    mode := 0
                    if opcode == 9:
                        mode = 1
                    elif opcode == 10:
                        mode = 2
                    elif opcode == 11:
                        mode = 3
                    elif opcode == 12:
                        mode = 4
                    setd(rd, round_mode(a, mode))
            else:
                undef(w)
        else:
            a := gets(rn)
            if opcode == 0:
                setq(rd, qlo(rn) & M32, 0)
            elif opcode == 1:
                setq(rd, qlo(rn) & 2147483647, 0)
            elif opcode == 2:
                setq(rd, (qlo(rn) & M32) ^ 0x80000000, 0)
            elif opcode == 3:
                setq(rd, arm_nan_f(__fsqrt(a), a, 0.0, 0.0, 1), 0)
            elif opcode == 5:
                if isnan(a):
                    setd(rd, fof(0x7FF8000000000000))
                else:
                    setd(rd, a)
            else:
                undef(w)
        return
    if bits(w, 13, 10) == 8 and bits(w, 15, 14) == 0:
        # FCMP / FCMPE
        zero := bits(w, 3, 3) != 0
        a := 0.0
        b := 0.0
        if dbl:
            a = getd(rn)
            if not zero:
                b = getd(rm)
        else:
            a = gets(rn)
            if not zero:
                b = gets(rm)
        fcmp(a, b)
        return
    if bits(w, 12, 10) == 4:
        # FMOV immédiat
        d := fp_imm8(bits(w, 20, 13))
        if dbl:
            setd(rd, d)
        else:
            sets(rd, d)
        return
    if bits(w, 11, 10) == 1:
        # FCCMP
        if cond(bits(w, 15, 12)):
            if dbl:
                fcmp(getd(rn), getd(rm))
            else:
                fcmp(gets(rn), gets(rm))
        else:
            set_nzcv(bits(w, 3, 0))
        return
    if bits(w, 11, 10) == 3:
        # FCSEL
        lo := qlo(rm)
        if cond(bits(w, 15, 12)):
            lo = qlo(rn)
        if not dbl:
            lo = lo & M32
        setq(rd, lo, 0)
        return
    if bits(w, 11, 10) == 2:
        # 2 sources
        opcode := bits(w, 15, 12)
        if dbl:
            a := getd(rn)
            b := getd(rm)
            r := 0.0
            if opcode == 0:
                r = a * b
            elif opcode == 1:
                r = a / b
            elif opcode == 2:
                r = a + b
            elif opcode == 3:
                r = a - b
            elif opcode == 4:
                if isnan(a) or isnan(b):
                    r = fof(0x7FF8000000000000)
                else:
                    r = fmax_c(a, b)
            elif opcode == 5:
                if isnan(a) or isnan(b):
                    r = fof(0x7FF8000000000000)
                else:
                    r = fmin_c(a, b)
            elif opcode == 6:
                r = fmax_c(a, b)
            elif opcode == 7:
                r = fmin_c(a, b)
            elif opcode == 8:
                r = -(a * b)
            else:
                undef(w)
            setd(rd, arm_nan3(r, a, b, 0.0, 2))
        else:
            a := gets(rn)
            b := gets(rm)
            r := 0.0
            if opcode == 0:
                r = a * b
            elif opcode == 1:
                r = a / b
            elif opcode == 2:
                r = a + b
            elif opcode == 3:
                r = a - b
            elif opcode == 8:
                r = -(a * b)
            else:
                undef(w)
            setq(rd, arm_nan_f(r, a, b, 0.0, 2), 0)
        return
    undef(w)

# ---- chargement de l'ELF, pile initiale -------------------------------------------------------------------------
func _cstr(p: int) -> str:
    n := _cstrlen(p)
    s := __alloc(8 + n)
    __store64(s, n)
    __copy(s + 8, p, n)
    return __as_str(s)

func _strz(s: str) -> int:
    n := __rt_str_len(s)
    p := __alloc_raw(n + 1)
    __copy(p, __str_addr(s) + 8, n)
    __store8(p + n, 0)
    return p

# Lit un fichier entier dans une zone mmap ; renvoie son adresse (taille en [O_WM]).
func read_file(path: str) -> int:
    fd := __syscall(2, _strz(path), 0)
    if fd < 0:
        die("fichier introuvable")
    size := __syscall(8, fd, 0, 2)
    if size < 0:
        die("fichier illisible")
    __syscall(8, fd, 0, 0)
    buf := __mmap((size + 4096) & (~4095))
    done := 0
    while done < size:
        k := __syscall(0, fd, buf + done, size - done)
        if k <= 0:
            die("lecture du fichier")
        done += k
    __syscall(3, fd)
    __store64(_S + O_WM, size)
    return buf

func init():
    _S = __mmap(4096)
    i := 0
    while i < 4096:
        __store64(_S + i, 0)
        i += 8

func run_loop():
    while true:
        step()

func main():
    init()
    argv0 := __argv_base()
    argc := __load64(argv0)
    if argc < 2:
        die("usage : a64run programme [arguments...]")
    envp := argv0 + 8 * (argc + 2)
    k := 0
    while __load64(envp + 8 * k) != 0:
        e := _cstr(__load64(envp + 8 * k))
        if __rt_str_len(e) >= 13 and _prefix(e, "A64RUN_TRACE="):
            __store64(_S + O_TRACE, 1)
        k += 1
    file := read_file(_cstr(__load64(argv0 + 16)))
    fsize := __load64(_S + O_WM)
    if fsize < 64 or __load32(file) != 1179403647:
        die("pas un fichier ELF")
    if __load8(file + 4) != 2 or __load8(file + 5) != 1:
        die("ELF 64 bits petit-boutiste attendu")
    if __load16(file + 16) != 2:
        die("exécutable statique (ET_EXEC) attendu")
    if __load16(file + 18) != 183:
        die("machine " + __int_to_str(__load16(file + 18)) + " : AArch64 (183) attendu")
    entry := __load64(file + 24)
    phoff := __load64(file + 32)
    phentsize := __load16(file + 54)
    phnum := __load16(file + 56)
    i := 0
    while i < phnum:
        ph := file + phoff + i * phentsize
        i += 1
        if __load32(ph) != 1:
            continue
        flags := __load32(ph + 4)
        off := __load64(ph + 8)
        vaddr := __load64(ph + 16)
        filesz := __load64(ph + 32)
        memsz := __load64(ph + 40)
        align := __load64(ph + 48)
        if align > 4096 and (vaddr % align) != (off % align):
            die("segment mal aligné (vaddr " + _hex(vaddr) + ")")
        page := vaddr & (~4095)
        pend := (vaddr + memsz + 4095) & (~4095)
        # PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE
        p := __syscall(9, page, pend - page, 3, 1048610, -1, 0)
        if p != page:
            die("impossible de placer le segment en " + _hex(vaddr))
        if off + filesz > fsize:
            die("segment hors du fichier")
        __copy(vaddr, file + off, filesz)
        prot := 0
        if (flags & 4) != 0:
            prot = prot | 1
        if (flags & 2) != 0:
            prot = prot | 2
        if (flags & 1) != 0 and (flags & 2) != 0:
            die("segment à la fois inscriptible et exécutable")
        if prot == 0:
            prot = 1
        __syscall(10, p, pend - page, prot)
    # Pile initiale : argc, argv..., 0, envp..., 0, auxv (AT_PAGESZ, AT_RANDOM), 0.
    kstack := 8388608
    stack := __mmap(kstack)
    top := stack + kstack
    nargs := argc - 1
    argp := __alloc_raw(8 * nargs + 8)
    j := 0
    while j < nargs:
        s := __load64(argv0 + 16 + 8 * j)
        n := _cstrlen(s) + 1
        top -= n
        __copy(top, s, n)
        __store64(argp + 8 * j, top)
        j += 1
    nenv := k
    envs := __alloc_raw(8 * nenv + 8)
    j = 0
    while j < nenv:
        s := __load64(envp + 8 * j)
        n := _cstrlen(s) + 1
        top -= n
        __copy(top, s, n)
        __store64(envs + 8 * j, top)
        j += 1
    top -= 16
    rnd := top
    j = 0
    while j < 16:
        __store8(rnd + j, 90)
        j += 1
    top = top & (~15)
    words := 1 + nargs + 1 + nenv + 1 + 4 + 2
    top -= 8 * words
    top = top & (~15)
    p := top
    __store64(p, nargs)
    p += 8
    j = 0
    while j < nargs:
        __store64(p, __load64(argp + 8 * j))
        p += 8
        j += 1
    __store64(p, 0)
    p += 8
    j = 0
    while j < nenv:
        __store64(p, __load64(envs + 8 * j))
        p += 8
        j += 1
    __store64(p, 0)
    p += 8
    __store64(p, 6)
    __store64(p + 8, 4096)
    __store64(p + 16, 25)
    __store64(p + 24, rnd)
    __store64(p + 32, 0)
    __store64(p + 40, 0)
    set_sp(top)
    set_pc(entry)
    run_loop()

func _prefix(s: str, pre: str) -> bool:
    n := __rt_str_len(pre)
    if __rt_str_len(s) < n:
        return false
    a := __str_addr(s) + 8
    b := __str_addr(pre) + 8
    i := 0
    while i < n:
        if __load8(a + i) != __load8(b + i):
            return false
        i += 1
    return true

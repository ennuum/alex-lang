# ALEX STANDARD LIBRARY — crypto.bigint
# Entiers naturels de taille arbitraire pour la cryptographie (RSA, courbes elliptiques) : listes de limbes de
# 26 bits, poids faible en tête, sans limbe nul en tête (zéro : []). Un produit de deux limbes (< 2^52) plus les
# retenues tient dans un entier ALEX de 64 bits.
#
#   use crypto.bigint as bn
#   n := bn.from_hex("c0ffee…")             # aussi from_int, from_bytes (big-endian)
#   bn.to_bytes(bn.modpow(m, e, n), 256)   # exponentiation modulaire (Montgomery si le module est impair)
#   q := bn.divmod(a, b)                   # [quotient, reste] (Knuth, algorithme D)
#   bn.modinv(a, p)                        # inverse modulaire (Euclide étendu), erreur s'il n'existe pas
#
# Opérations : add, sub (a >= b), mul, sqr, shl, shr, divmod, mod, cmp, eq, is_zero, is_odd, bit_length,
# test_bit, modpow, modinv, gcd, to_int, to_hex. Toutes rendent des valeurs neuves (les arguments ne sont pas
# modifiés). Vérifié contre les entiers de Python (valeurs aléatoires, jusqu'à 4096 bits) dans
# tests/stdlib2/test_crypto_tls.al.
# LIMITES : temps d'exécution dépendant des valeurs (pas de garantie contre les attaques temporelles).
# Erreurs : ValueError (valeur négative, division par zéro, inverse inexistant, soustraction négative).

from core use len, type
from collections use append

const BITS := 26
const BASE := 67108864
const MASK := 67108863

func _fail(message):
    raise("ValueError", "bigint : " + message)

func _norm(x):
    n := len(x)
    while n > 0 and x[n - 1] == 0:
        n -= 1
    return x if n == len(x) else x[0:n]

# ---------------------------------------------------------------- conversions

func from_int(n):
    if type(n) != "int" or n < 0:
        _fail("entier naturel attendu")
    out := []
    v := n
    while v > 0:
        append(out, v & MASK)
        v = v >> BITS
    return out

func to_int(x):
    if bit_length(x) > 62:
        _fail("valeur trop grande pour un entier (" + str(bit_length(x)) + " bits)")
    v := 0
    i := len(x) - 1
    while i >= 0:
        v = (v << BITS) | x[i]
        i -= 1
    return v

# Octets big-endian (liste d'entiers 0..255) -> entier.
func from_bytes(b):
    out := []
    acc := 0
    nb := 0
    i := len(b) - 1
    while i >= 0:
        acc = acc | (b[i] << nb)
        nb += 8
        if nb >= BITS:
            append(out, acc & MASK)
            acc = acc >> BITS
            nb -= BITS
        i -= 1
    if nb > 0:
        append(out, acc)
    return _norm(out)

# Entier -> octets big-endian ; length : taille exacte (zéros en tête), erreur si la valeur ne tient pas.
func to_bytes(x, length=null):
    rev := []
    acc := 0
    nb := 0
    for limb in x:
        acc = acc | (limb << nb)
        nb += BITS
        while nb >= 8:
            append(rev, acc & 255)
            acc = acc >> 8
            nb -= 8
    if nb > 0:
        append(rev, acc & 255)
    n := len(rev)
    while n > 0 and rev[n - 1] == 0:
        n -= 1
    if length != null:
        if n > length:
            _fail("la valeur ne tient pas sur " + str(length) + " octets")
        n = length
    out := []
    i := n - 1
    while i >= 0:
        append(out, rev[i] if i < len(rev) else 0)
        i -= 1
    return out

const _HEXD := "0123456789abcdef"

func from_hex(t):
    out := []
    for ch in t:
        c := str(ch)
        v := -1
        k := 0
        while k < 16:
            if _HEXD[k:k + 1] == c or "0123456789ABCDEF"[k:k + 1] == c:
                v = k
            k += 1
        if v < 0:
            _fail("chiffre hexadécimal invalide : " + c)
        append(out, v)
    b := []
    i := len(out) % 2
    if i == 1:
        append(b, out[0])
    while i < len(out):
        append(b, out[i] * 16 + out[i + 1])
        i += 2
    return from_bytes(b)

func to_hex(x):
    if len(x) == 0:
        return "0"
    s := ""
    for b in to_bytes(x):
        s = s + _HEXD[b >> 4:(b >> 4) + 1] + _HEXD[b & 15:(b & 15) + 1]
    if s[0:1] == "0":
        s = s[1:len(s)]
    return s

# ---------------------------------------------------------------- comparaisons

func is_zero(x):
    return len(x) == 0

func is_odd(x):
    return len(x) > 0 and (x[0] & 1) == 1

func cmp(a, b):
    if len(a) != len(b):
        return -1 if len(a) < len(b) else 1
    i := len(a) - 1
    while i >= 0:
        if a[i] != b[i]:
            return -1 if a[i] < b[i] else 1
        i -= 1
    return 0

func eq(a, b):
    return cmp(a, b) == 0

func bit_length(x):
    if len(x) == 0:
        return 0
    top := x[len(x) - 1]
    n := 0
    while top > 0:
        n += 1
        top = top >> 1
    return (len(x) - 1) * BITS + n

func test_bit(x, i):
    k := i // BITS
    return k < len(x) and ((x[k] >> (i % BITS)) & 1) == 1

# ---------------------------------------------------------------- arithmétique

func add(a, b):
    x := a if len(a) >= len(b) else b
    y := b if len(a) >= len(b) else a
    out := []
    c := 0
    i := 0
    while i < len(x):
        s := x[i] + (y[i] if i < len(y) else 0) + c
        append(out, s & MASK)
        c = s >> BITS
        i += 1
    if c > 0:
        append(out, c)
    return out

func sub(a, b):
    if cmp(a, b) < 0:
        _fail("soustraction négative")
    out := []
    br := 0
    i := 0
    while i < len(a):
        s := a[i] - (b[i] if i < len(b) else 0) - br
        if s < 0:
            s += BASE
            br = 1
        else:
            br = 0
        append(out, s)
        i += 1
    return _norm(out)

func mul(a, b):
    if len(a) == 0 or len(b) == 0:
        return []
    na := len(a)
    nb := len(b)
    t := [0] * (na + nb)
    i := 0
    while i < na:
        ai := a[i]
        if ai != 0:
            c := 0
            j := 0
            while j < nb:
                s := t[i + j] + ai * b[j] + c
                t[i + j] = s & MASK
                c = s >> BITS
                j += 1
            k := i + nb
            while c > 0:
                s := t[k] + c
                t[k] = s & MASK
                c = s >> BITS
                k += 1
        i += 1
    return _norm(t)

func sqr(a):
    return mul(a, a)

func shl(x, k):
    if len(x) == 0 or k == 0:
        return x + []
    w := k // BITS
    b := k % BITS
    out := [0] * w
    if b == 0:
        return out + x
    c := 0
    for limb in x:
        v := (limb << b) | c
        append(out, v & MASK)
        c = v >> BITS
    if c > 0:
        append(out, c)
    return out

func shr(x, k):
    w := k // BITS
    b := k % BITS
    if w >= len(x):
        return []
    out := []
    i := w
    while i < len(x):
        lo := x[i] >> b
        hi := ((x[i + 1] << (BITS - b)) & MASK) if (b > 0 and i + 1 < len(x)) else 0
        append(out, lo | hi)
        i += 1
    return _norm(out)

# Division par un limbe : [quotient, reste (int)].
func _divmod_small(a, d):
    q := [0] * len(a)
    r := 0
    i := len(a) - 1
    while i >= 0:
        cur := (r << BITS) | a[i]
        q[i] = cur // d
        r = cur - q[i] * d
        i -= 1
    return [_norm(q), r]

# [quotient, reste] (Knuth, TAOCP vol. 2, 4.3.1, algorithme D).
func divmod(u, v):
    if len(v) == 0:
        _fail("division par zéro")
    if cmp(u, v) < 0:
        return [[], u + []]
    if len(v) == 1:
        r := _divmod_small(u, v[0])
        return [r[0], from_int(r[1])]
    n := len(v)
    m := len(u)
    top := v[n - 1]
    s := 0
    while (top << s) < (BASE >> 1):
        s += 1
    vn := [0] * n
    i := n - 1
    while i > 0:
        vn[i] = ((v[i] << s) | (v[i - 1] >> (BITS - s))) & MASK
        i -= 1
    vn[0] = (v[0] << s) & MASK
    un := [0] * (m + 1)
    un[m] = u[m - 1] >> (BITS - s)
    i = m - 1
    while i > 0:
        un[i] = ((u[i] << s) | (u[i - 1] >> (BITS - s))) & MASK
        i -= 1
    un[0] = (u[0] << s) & MASK
    q := [0] * (m - n + 1)
    vtop := vn[n - 1]
    vnext := vn[n - 2]
    j := m - n
    while j >= 0:
        num := un[j + n] * BASE + un[j + n - 1]
        qhat := num // vtop
        rhat := num - qhat * vtop
        while qhat >= BASE or qhat * vnext > rhat * BASE + un[j + n - 2]:
            qhat -= 1
            rhat += vtop
            if rhat >= BASE:
                break
        k := 0
        i = 0
        while i < n:
            p := qhat * vn[i]
            t := un[i + j] - k - (p & MASK)
            un[i + j] = t & MASK
            k = (p >> BITS) - (t >> BITS)
            i += 1
        t := un[j + n] - k
        un[j + n] = t
        if t < 0:
            qhat -= 1
            k = 0
            i = 0
            while i < n:
                t2 := un[i + j] + vn[i] + k
                un[i + j] = t2 & MASK
                k = t2 >> BITS
                i += 1
            un[j + n] = (un[j + n] + k) & MASK
        q[j] = qhat
        j -= 1
    r := [0] * n
    i = 0
    while i < n:
        hi := (un[i + 1] << (BITS - s)) & MASK if s > 0 else 0
        r[i] = (un[i] >> s) | hi
        i += 1
    return [_norm(q), _norm(r)]

func mod(a, m):
    return divmod(a, m)[1]

func gcd(a, b):
    x := a
    y := b
    while len(y) > 0:
        r := mod(x, y)
        x = y
        y = r
    return x

# Inverse de a modulo m (Euclide étendu, coefficients gardés modulo m).
func modinv(a, m):
    if len(m) == 0:
        _fail("module nul")
    r0 := m
    r1 := mod(a, m)
    s0 := []
    s1 := [1]
    while len(r1) > 0:
        qr := divmod(r0, r1)
        r0 = r1
        r1 = qr[1]
        qs := mod(mul(qr[0], s1), m)
        ns := sub(s0, qs) if cmp(s0, qs) >= 0 else sub(add(s0, m), qs)
        s0 = s1
        s1 = ns
    if not eq(r0, [1]):
        _fail("pas d'inverse modulaire (pgcd différent de 1)")
    return mod(s0, m)

# ---------------------------------------------------------------- Montgomery

# Contexte de Montgomery pour un module impair m : R = 2^(26 n).
class Montgomery:
    func init(m):
        if not is_odd(m):
            _fail("Montgomery : module impair attendu")
        self.m = m
        self.n = len(m)
        # m' = -m^-1 mod 2^26 (Newton : chaque tour double les bits justes)
        inv := 1
        k := 0
        while k < 5:
            inv = (inv * (2 - m[0] * inv)) & MASK
            k += 1
        self.mprime = (BASE - inv) & MASK
        self.r2 = mod(shl([1], 2 * BITS * self.n), m)

    func _pad(x):
        if len(x) == self.n:
            return x
        return x + [0] * (self.n - len(x))

    # a * b * R^-1 mod m (CIOS) ; a, b < m, de n limbes (complétés de zéros).
    func mul(a, b):
        n := self.n
        m := self.m
        mp := self.mprime
        t := [0] * (n + 2)
        x := self._pad(a)
        y := self._pad(b)
        i := 0
        while i < n:
            ai := x[i]
            c := 0
            j := 0
            while j < n:
                s := t[j] + ai * y[j] + c
                t[j] = s & MASK
                c = s >> BITS
                j += 1
            s := t[n] + c
            t[n] = s & MASK
            t[n + 1] = s >> BITS
            u := (t[0] * mp) & MASK
            s = t[0] + u * m[0]
            c = s >> BITS
            j = 1
            while j < n:
                s = t[j] + u * m[j] + c
                t[j - 1] = s & MASK
                c = s >> BITS
                j += 1
            s = t[n] + c
            t[n - 1] = s & MASK
            t[n] = t[n + 1] + (s >> BITS)
            t[n + 1] = 0
            i += 1
        r := _norm(t[0:n + 1])
        if cmp(r, m) >= 0:
            r = sub(r, m)
        return r

    func to_mont(x):
        return self.mul(mod(x, self.m), self.r2)

    func from_mont(x):
        return self.mul(x, [1])

    # base^e mod m, fenêtre fixe de 4 bits.
    func pow(base, e):
        one := self.to_mont([1])
        if len(e) == 0:
            return mod([1], self.m)
        b := self.to_mont(base)
        tab := [one, b]
        k := 2
        while k < 16:
            append(tab, self.mul(tab[k - 1], b))
            k += 1
        acc := one
        started := false                 # pas d'élévation au carré avant la première fenêtre non nulle
        nbits := bit_length(e)
        top := ((nbits + 3) // 4) * 4 - 4
        while top >= 0:
            if started:
                acc = self.mul(acc, acc)
                acc = self.mul(acc, acc)
                acc = self.mul(acc, acc)
                acc = self.mul(acc, acc)
            w := 0
            k = 3
            while k >= 0:
                w = (w << 1) | (1 if test_bit(e, top + k) else 0)
                k -= 1
            if w != 0:
                acc = self.mul(acc, tab[w])
                started = true
            top -= 4
        return self.from_mont(acc)

# base^e mod m.
func modpow(base, e, m):
    if len(m) == 0:
        _fail("module nul")
    if eq(m, [1]):
        return []
    if is_odd(m):
        return Montgomery(m).pow(base, e)
    acc := [1]
    b := mod(base, m)
    i := bit_length(e) - 1
    while i >= 0:
        acc = mod(mul(acc, acc), m)
        if test_bit(e, i):
            acc = mod(mul(acc, b), m)
        i -= 1
    return acc

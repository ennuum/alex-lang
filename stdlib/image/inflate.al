# alex: native
# alex: intrinsics
# NOVA (édition bureau) — décompression DEFLATE (RFC 1951), zlib (RFC 1950) et gzip (RFC 1952).
#
# Travaille en mémoire brute (mmap) avec des tables de décodage directes : chaque table de Huffman est indexée
# par les `bits` prochains bits du flux (codes renversés), une entrée vaut (symbole << 4) | longueur.
#
#   inflate.gunzip_str(s)     corps gzip → octets (plusieurs membres acceptés)
#   inflate.deflate_str(s)    « deflate » HTTP : flux zlib, ou DEFLATE brut (erreur fréquente des serveurs)
#   inflate.zlib_str(s)       flux zlib → octets
#   inflate.raw_str(s)        DEFLATE brut → octets
#   inflate.inflate_mem(addr, n, out)   bas niveau : décompresse dans un Buf (utilisé par le décodeur PNG)
#
# Erreurs : InflateError (flux invalide ou tronqué, limite dépassée).

from core use len

const LIMIT := 268435456        # 256 Mio décompressés au plus (bombes de décompression)

const LBASE := [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
const LEXT := [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
const DBASE := [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
const DEXT := [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
const CLORDER := [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

# Tampon de sortie extensible (mémoire brute).
class Buf:
    addr: int := 0
    n: int := 0
    cap: int := 0

    func reserve(extra: int):
        need := self.n + extra
        if need <= self.cap:
            return
        if need > LIMIT:
            raise("InflateError", "données décompressées trop volumineuses")
        c := self.cap * 2
        if c < 65536:
            c = 65536
        while c < need:
            c = c * 2
        c = (c + 4095) & ~4095
        a := __mmap(c)
        if self.n > 0:
            __copy(a, self.addr, self.n)
        if self.cap > 0:
            __munmap(self.addr, self.cap)
        self.addr = a
        self.cap = c

    func free():
        if self.cap > 0:
            __munmap(self.addr, self.cap)
        self.addr = 0
        self.cap = 0
        self.n = 0

    func to_str() -> str:
        return mem_str(self.addr, self.n)

# Chaîne de n octets copiés depuis addr.
func mem_str(addr: int, n: int) -> str:
    r := __rt_str_new(n)
    if n > 0:
        __copy(r + 8, addr, n)
    return __as_str(r)

func str_addr(s: str) -> int:
    return __str_addr(s) + 8

func str_len(s: str) -> int:
    return __load64(__str_addr(s))

class _In:
    src: int := 0
    n: int := 0
    pos: int := 0
    bb: int := 0
    bc: int := 0
    over: int := 0

class _Table:
    addr: int := 0
    bits: int := 0
    size: int := 0

func _need(s: _In, k: int):
    while s.bc < k:
        if s.pos < s.n:
            s.bb = s.bb | (__load8(s.src + s.pos) << s.bc)
            s.pos += 1
        else:
            s.over += 1
            if s.over > 8:
                raise("InflateError", "flux DEFLATE tronqué")
        s.bc += 8

func _bits(s: _In, k: int) -> int:
    if k == 0:
        return 0
    _need(s, k)
    v := s.bb & ((1 << k) - 1)
    s.bb = s.bb >> k
    s.bc -= k
    return v

# Table de décodage pour n longueurs de codes (int32 à l'adresse lens).
func _build(lens: int, n: int) -> _Table:
    t := _Table()
    maxb := 0
    counts := _mem(16 * 8)
    __zero(counts, 128)
    i := 0
    while i < n:
        l := __load32(lens + i * 4)
        if l > 0:
            __store64(counts + l * 8, __load64(counts + l * 8) + 1)
            if l > maxb:
                maxb = l
        i += 1
    if maxb == 0:
        maxb = 1
    t.bits = maxb
    t.size = (1 << maxb) * 4
    t.addr = __mmap((t.size + 4095) & ~4095)
    nxt := _mem(16 * 8)
    code := 0
    b := 1
    while b <= 15:
        code = (code + __load64(counts + (b - 1) * 8)) << 1
        __store64(nxt + b * 8, code)
        b += 1
    # longueur 1 : code de départ 0 (la boucle ci-dessus commence avec counts[0] = 0)
    i = 0
    while i < n:
        l := __load32(lens + i * 4)
        if l > 0:
            c := __load64(nxt + l * 8)
            __store64(nxt + l * 8, c + 1)
            r := 0
            k := 0
            while k < l:
                r = (r << 1) | ((c >> k) & 1)
                k += 1
            step := 1 << l
            e := (i << 4) | l
            j := r
            lim := 1 << maxb
            while j < lim:
                __store32(t.addr + j * 4, e)
                j += step
        i += 1
    return t

func _free(t: _Table):
    if t.addr != 0:
        __munmap(t.addr, (t.size + 4095) & ~4095)
        t.addr = 0

func _decode(s: _In, t: _Table) -> int:
    if s.bc < t.bits:
        while s.bc < t.bits and s.pos < s.n:
            s.bb = s.bb | (__load8(s.src + s.pos) << s.bc)
            s.pos += 1
            s.bc += 8
        if s.bc < t.bits:
            # fin du flux : complète par des zéros (le code peut être plus court que t.bits)
            s.over += 1
            if s.over > 8:
                raise("InflateError", "flux DEFLATE tronqué")
            s.bc += 8
    e := __load32(t.addr + (s.bb & ((1 << t.bits) - 1)) * 4)
    l := e & 15
    if l == 0:
        raise("InflateError", "code de Huffman invalide")
    s.bb = s.bb >> l
    s.bc -= l
    return e >> 4

func _codes(s: _In, o: Buf, lt: _Table, dt: _Table):
    while true:
        sym := _decode(s, lt)
        if sym < 256:
            if o.n >= o.cap:
                o.reserve(1)
            __store8(o.addr + o.n, sym)
            o.n += 1
        elif sym == 256:
            return
        else:
            sym -= 257
            if sym >= 29:
                raise("InflateError", "longueur invalide")
            ln := LBASE[sym] + _bits(s, LEXT[sym])
            ds := _decode(s, dt)
            if ds >= 30:
                raise("InflateError", "distance invalide")
            dist := DBASE[ds] + _bits(s, DEXT[ds])
            if dist > o.n:
                raise("InflateError", "distance hors de la fenêtre")
            o.reserve(ln)
            d := o.addr + o.n
            src := d - dist
            if dist >= ln:
                __copy(d, src, ln)
            else:
                k := 0
                while k < ln:
                    __store8(d + k, __load8(src + k))
                    k += 1
            o.n += ln

func _fixed(s: _In, o: Buf):
    lens := _mem(320 * 4)
    i := 0
    while i < 288:
        v := 8
        if i >= 144 and i < 256:
            v = 9
        elif i >= 256 and i < 280:
            v = 7
        __store32(lens + i * 4, v)
        i += 1
    lt := _build(lens, 288)
    i = 0
    while i < 30:
        __store32(lens + i * 4, 5)
        i += 1
    dt := _build(lens, 30)
    try:
        _codes(s, o, lt, dt)
    catch e:
        _free(lt)
        _free(dt)
        raise(e)
    _free(lt)
    _free(dt)

func _dynamic(s: _In, o: Buf):
    nlen := _bits(s, 5) + 257
    ndist := _bits(s, 5) + 1
    ncode := _bits(s, 4) + 4
    if nlen > 286 or ndist > 30:
        raise("InflateError", "en-tête de bloc dynamique invalide")
    lens := _mem(320 * 4)
    __zero(lens, 320 * 4)
    i := 0
    while i < ncode:
        __store32(lens + CLORDER[i] * 4, _bits(s, 3))
        i += 1
    ct := _build(lens, 19)
    __zero(lens, 320 * 4)
    i = 0
    total := nlen + ndist
    while i < total:
        sym := _decode(s, ct)
        if sym < 16:
            __store32(lens + i * 4, sym)
            i += 1
        else:
            rep := 0
            val := 0
            if sym == 16:
                if i == 0:
                    _free(ct)
                    raise("InflateError", "répétition sans longueur précédente")
                val = __load32(lens + (i - 1) * 4)
                rep = 3 + _bits(s, 2)
            elif sym == 17:
                rep = 3 + _bits(s, 3)
            else:
                rep = 11 + _bits(s, 7)
            if i + rep > total:
                _free(ct)
                raise("InflateError", "trop de longueurs de codes")
            while rep > 0:
                __store32(lens + i * 4, val)
                i += 1
                rep -= 1
    _free(ct)
    lt := _build(lens, nlen)
    dt := _build(lens + nlen * 4, ndist)
    try:
        _codes(s, o, lt, dt)
    catch e:
        _free(lt)
        _free(dt)
        raise(e)
    _free(lt)
    _free(dt)

# Décompresse le DEFLATE brut [addr, addr + n) à la suite de o ; rend le nombre d'octets d'entrée consommés.
func inflate_mem(addr: int, n: int, o: Buf) -> int:
    s := _In()
    s.src = addr
    s.n = n
    last := 0
    while last == 0:
        last = _bits(s, 1)
        kind := _bits(s, 2)
        if kind == 0:
            s.bb = 0
            s.bc = 0
            if s.pos + 4 > s.n:
                raise("InflateError", "bloc stocké tronqué")
            ln := __load8(s.src + s.pos) | (__load8(s.src + s.pos + 1) << 8)
            s.pos += 4
            if s.pos + ln > s.n:
                raise("InflateError", "bloc stocké tronqué")
            o.reserve(ln)
            __copy(o.addr + o.n, s.src + s.pos, ln)
            o.n += ln
            s.pos += ln
        elif kind == 1:
            _fixed(s, o)
        elif kind == 2:
            _dynamic(s, o)
        else:
            raise("InflateError", "type de bloc invalide")
    used := s.pos - s.bc // 8
    if used > n:
        used = n
    return used

func raw_str(data: str) -> str:
    o := Buf()
    inflate_mem(str_addr(data), str_len(data), o)
    r := o.to_str()
    o.free()
    return r

func is_zlib(data: str) -> bool:
    n := str_len(data)
    if n < 2:
        return false
    a := str_addr(data)
    cmf := __load8(a)
    flg := __load8(a + 1)
    return (cmf & 15) == 8 and (cmf >> 4) <= 7 and ((cmf * 256 + flg) % 31) == 0 and (flg & 32) == 0

func zlib_str(data: str) -> str:
    if not is_zlib(data):
        raise("InflateError", "en-tête zlib invalide")
    o := Buf()
    inflate_mem(str_addr(data) + 2, str_len(data) - 2, o)
    r := o.to_str()
    o.free()
    return r

func deflate_str(data: str) -> str:
    if is_zlib(data):
        try:
            return zlib_str(data)
        catch e:
            pass
    return raw_str(data)

func gunzip_str(data: str) -> str:
    a := str_addr(data)
    n := str_len(data)
    o := Buf()
    p := 0
    members := 0
    while p + 18 <= n and __load8(a + p) == 31 and __load8(a + p + 1) == 139:
        if __load8(a + p + 2) != 8:
            o.free()
            raise("InflateError", "méthode gzip inconnue")
        flg := __load8(a + p + 3)
        q := p + 10
        if (flg & 4) != 0:
            xl := __load8(a + q) | (__load8(a + q + 1) << 8)
            q += 2 + xl
        if (flg & 8) != 0:
            while q < n and __load8(a + q) != 0:
                q += 1
            q += 1
        if (flg & 16) != 0:
            while q < n and __load8(a + q) != 0:
                q += 1
            q += 1
        if (flg & 2) != 0:
            q += 2
        if q >= n:
            break
        used := inflate_mem(a + q, n - q, o)
        p = q + used + 8
        members += 1
    if members == 0:
        o.free()
        raise("InflateError", "en-tête gzip invalide")
    r := o.to_str()
    o.free()
    return r

# Mémoire brute hors du ramasse-miettes.
func _mem(n: int) -> int:
    return __mmap((n + 4095) & ~4095)

# alex: native
# alex: intrinsics
# NOVA (édition bureau) — encodeurs d'images et transformations pour les vignettes, sur les Raster de
# image.raster (ARGB 32 bits) :
#
#   jpeg(r, qualité)          JPEG de base (JFIF), 4:2:0, tables standard, qualité 1..100 (échelle d'IJG) ;
#                             les zones transparentes sont composées sur du blanc
#   png(r)                    PNG 8 bits RGB (ou RGBA si une transparence existe), filtre choisi ligne par ligne,
#                             deflate (codes fixes, recherche de répétitions LZ77)
#   has_alpha(r)              un point au moins n'est pas opaque
#   exif_orientation(octets)  orientation Exif d'un JPEG (1 à 8 ; 1 si absente)
#   orient(r, o)              applique une orientation Exif (rotation, miroir) ; rend un nouveau Raster
#   crop(r, x, y, l, h)       découpe
#   load(octets)              décodage (première image) et orientation Exif ; resize(r, l, h, mode) ;
#   encode(r, format, qualité)
#   thumbnail(octets, l, h, mode, format, qualité) -> octets
#                             décodage (image.decode, première image), orientation Exif, réduction « fit »
#                             (tient dans l × h, proportions gardées) ou « cover » (remplit l × h, recadré au
#                             centre), jamais d'agrandissement ; format « jpeg », « png » ou « auto » (PNG s'il
#                             reste de la transparence, sinon JPEG)
#
# Erreurs : ImageError.
use image.inflate as inf
from image.inflate use Buf
use image.raster as rs
from image.raster use Raster
use image.image as im
from image.image use Anim
from core use len
from collections use append

const ZIGZAG := [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]
# cos((2x + 1)uπ/16) · c(u), c(0) = √(1/8), c(u) = √(2/8), × 8192 : DCT orthonormée (celle de JPEG)
const DCT := [2896, 2896, 2896, 2896, 2896, 2896, 2896, 2896, 4017, 3406, 2276, 799, -799, -2276, -3406, -4017, 3784, 1567, -1567, -3784, -3784, -1567, 1567, 3784, 3406, -799, -4017, -2276, 2276, 4017, 799, -3406, 2896, -2896, -2896, 2896, 2896, -2896, -2896, 2896, 2276, -4017, 799, 3406, -3406, -799, 4017, -2276, 1567, -3784, 3784, -1567, -1567, 3784, -3784, 1567, 799, -2276, 3406, -4017, 4017, -3406, 2276, -799]
# tables de quantification de l'annexe K (ordre naturel, ligne par ligne)
const Q_LUM := [16, 11, 10, 16, 24, 40, 51, 61, 12, 12, 14, 19, 26, 58, 60, 55, 14, 13, 16, 24, 40, 57, 69, 56, 14, 17, 22, 29, 51, 87, 80, 62, 18, 22, 37, 56, 68, 109, 103, 77, 24, 35, 55, 64, 81, 104, 113, 92, 49, 64, 78, 87, 103, 121, 120, 101, 72, 92, 95, 98, 112, 100, 103, 99]
const Q_CHR := [17, 18, 24, 47, 99, 99, 99, 99, 18, 21, 26, 66, 99, 99, 99, 99, 24, 26, 56, 99, 99, 99, 99, 99, 47, 66, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99, 99]
# tables de Huffman standard (annexe K.3) : nombres de codes par longueur (1..16), puis symboles
const DC_LUM_BITS := [0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0]
const DC_LUM_VALS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const DC_CHR_BITS := [0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0]
const DC_CHR_VALS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const AC_LUM_BITS := [0, 2, 1, 3, 3, 2, 4, 3, 5, 5, 4, 4, 0, 0, 1, 125]
const AC_LUM_VALS := [1, 2, 3, 0, 4, 17, 5, 18, 33, 49, 65, 6, 19, 81, 97, 7, 34, 113, 20, 50, 129, 145, 161, 8, 35, 66, 177, 193, 21, 82, 209, 240, 36, 51, 98, 114, 130, 9, 10, 22, 23, 24, 25, 26, 37, 38, 39, 40, 41, 42, 52, 53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105, 106, 115, 116, 117, 118, 119, 120, 121, 122, 131, 132, 133, 134, 135, 136, 137, 138, 146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167, 168, 169, 170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198, 199, 200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250]
const AC_CHR_BITS := [0, 2, 1, 2, 4, 4, 3, 4, 7, 5, 4, 4, 0, 1, 2, 119]
const AC_CHR_VALS := [0, 1, 2, 3, 17, 4, 5, 33, 49, 6, 18, 65, 81, 7, 97, 113, 19, 34, 50, 129, 8, 20, 66, 145, 161, 177, 193, 9, 35, 51, 82, 240, 21, 98, 114, 209, 10, 22, 36, 52, 225, 37, 241, 23, 24, 25, 26, 38, 39, 40, 41, 42, 53, 54, 55, 56, 57, 58, 67, 68, 69, 70, 71, 72, 73, 74, 83, 84, 85, 86, 87, 88, 89, 90, 99, 100, 101, 102, 103, 104, 105, 106, 115, 116, 117, 118, 119, 120, 121, 122, 130, 131, 132, 133, 134, 135, 136, 137, 138, 146, 147, 148, 149, 150, 151, 152, 153, 154, 162, 163, 164, 165, 166, 167, 168, 169, 170, 178, 179, 180, 181, 182, 183, 184, 185, 186, 194, 195, 196, 197, 198, 199, 200, 201, 202, 210, 211, 212, 213, 214, 215, 216, 217, 218, 226, 227, 228, 229, 230, 231, 232, 233, 234, 242, 243, 244, 245, 246, 247, 248, 249, 250]
# deflate : longueurs 3..258 (codes 257..285) et distances 1..32768 (codes 0..29)
const LEN_BASE := [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
const LEN_EXTRA := [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
const DIST_BASE := [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
const DIST_EXTRA := [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

func _err(msg: str):
    raise("ImageError", msg)

# ================================================================================================ sortie

func _put8(b: Buf, v: int):
    b.reserve(1)
    __store8(b.addr + b.n, v & 255)
    b.n += 1

func _put16(b: Buf, v: int):
    _put8(b, v >> 8)
    _put8(b, v)

func _put32(b: Buf, v: int):
    _put16(b, (v >> 16) & 65535)
    _put16(b, v & 65535)

func _put_str(b: Buf, s: str):
    a := inf.str_addr(s)
    n := inf.str_len(s)
    b.reserve(n)
    __copy(b.addr + b.n, a, n)
    b.n += n

# ================================================================================================ JPEG

# Écriture de bits, poids fort d'abord, avec bourrage 0xFF 0x00.
class _JBits:
    out: Buf := Buf()
    acc: int := 0
    nb: int := 0

    func init(out: Buf):
        self.out = out
        self.acc = 0
        self.nb = 0

    func put(code: int, size: int):
        self.acc = (self.acc << size) | (code & ((1 << size) - 1))
        self.nb += size
        while self.nb >= 8:
            v := (self.acc >> (self.nb - 8)) & 255
            _put8(self.out, v)
            if v == 255:
                _put8(self.out, 0)
            self.nb -= 8
        self.acc = self.acc & ((1 << self.nb) - 1)

    func flush():
        if self.nb > 0:
            self.put((1 << (8 - self.nb)) - 1, 8 - self.nb)

# Codes de Huffman (code, longueur) par symbole, depuis les tables BITS / VALS.
class _HTable:
    code: list[int] := []
    size: list[int] := []

func _htable(bits: list[int], vals: list[int]) -> _HTable:
    t := _HTable()
    t.code = []
    t.size = []
    i := 0
    while i < 256:
        append(t.code, 0)
        append(t.size, 0)
        i += 1
    code := 0
    k := 0
    l := 1
    while l <= 16:
        c := 0
        while c < bits[l - 1]:
            t.code[vals[k]] = code
            t.size[vals[k]] = l
            code += 1
            k += 1
            c += 1
        code = code << 1
        l += 1
    return t

func _scale_q(base: list[int], quality: int) -> list[int]:
    q := quality
    if q < 1:
        q = 1
    if q > 100:
        q = 100
    s := 5000 // q if q < 50 else 200 - q * 2
    out: list[int] := []
    i := 0
    while i < 64:
        v := (base[i] * s + 50) // 100
        if v < 1:
            v = 1
        if v > 255:
            v = 255
        append(out, v)
        i += 1
    return out

func _div_round(a: int, b: int) -> int:
    if a >= 0:
        return (a + b // 2) // b
    return -((-a + b // 2) // b)

func _bits_of(v: int) -> int:
    x := v if v >= 0 else -v
    n := 0
    while x > 0:
        n += 1
        x = x >> 1
    return n

# DCT de blk (64 valeurs centrées, ordre naturel), quantification, codage ; rend le nouveau DC.
func _encode_block(w: _JBits, blk: int, tmp: int, coefs: int, q: list[int], prev_dc: int, dc: _HTable, ac: _HTable) -> int:
    # lignes
    y := 0
    while y < 8:
        u := 0
        while u < 8:
            s := 0
            x := 0
            while x < 8:
                s += _s32(blk + (y * 8 + x) * 4) * DCT[u * 8 + x]
                x += 1
            __store64(tmp + (y * 8 + u) * 8, s)
            u += 1
        y += 1
    # colonnes, puis quantification dans l'ordre zigzag
    v := 0
    while v < 8:
        u := 0
        while u < 8:
            s := 0
            yy := 0
            while yy < 8:
                s += __load64(tmp + (yy * 8 + u) * 8) * DCT[v * 8 + yy]
                yy += 1
            idx := v * 8 + u
            __store64(coefs + idx * 8, _div_round(s, q[idx] << 26))
            u += 1
        v += 1
    # DC
    d := __load64(coefs) - prev_dc
    nb := _bits_of(d)
    w.put(dc.code[nb], dc.size[nb])
    if nb > 0:
        w.put(d if d >= 0 else d - 1, nb)
    # AC
    run := 0
    k := 1
    while k < 64:
        c := __load64(coefs + ZIGZAG[k] * 8)
        if c == 0:
            run += 1
        else:
            while run > 15:
                w.put(ac.code[240], ac.size[240])
                run -= 16
            nb2 := _bits_of(c)
            sym := (run << 4) | nb2
            w.put(ac.code[sym], ac.size[sym])
            w.put(c if c >= 0 else c - 1, nb2)
            run = 0
        k += 1
    if run > 0:
        w.put(ac.code[0], ac.size[0])
    return __load64(coefs)

func _s32(a: int) -> int:
    v := __load32(a)
    return v - 4294967296 if v >= 2147483648 else v

# Point (x, y) bordé (les blocs qui dépassent répètent le bord), composé sur blanc : [R, G, B] dans un int.
func _rgb_at(r: Raster, x0: int, y0: int) -> int:
    x := x0 if x0 < r.width else r.width - 1
    y := y0 if y0 < r.height else r.height - 1
    c := __load32(r.addr + (y * r.width + x) * 4)
    a := (c >> 24) & 255
    if a == 255:
        return c & 16777215
    rr := (((c >> 16) & 255) * a + 255 * (255 - a)) // 255
    gg := (((c >> 8) & 255) * a + 255 * (255 - a)) // 255
    bb := ((c & 255) * a + 255 * (255 - a)) // 255
    return (rr << 16) | (gg << 8) | bb

func _dqt(b: Buf, id: int, q: list[int]):
    _put16(b, 0xFFDB)
    _put16(b, 67)
    _put8(b, id)
    k := 0
    while k < 64:
        _put8(b, q[ZIGZAG[k]])
        k += 1

func _dht(b: Buf, cls: int, id: int, bits: list[int], vals: list[int]):
    _put16(b, 0xFFC4)
    _put16(b, 3 + 16 + len(vals))
    _put8(b, (cls << 4) | id)
    for v in bits:
        _put8(b, v)
    for v in vals:
        _put8(b, v)

func jpeg(r: Raster, quality: int) -> str:
    if r.width > 65535 or r.height > 65535:
        _err("JPEG : image trop grande")
    ql := _scale_q(Q_LUM, quality)
    qc := _scale_q(Q_CHR, quality)
    b := Buf()
    _put16(b, 0xFFD8)
    _put16(b, 0xFFE0)                          # APP0 JFIF 1.01, sans vignette
    _put16(b, 16)
    _put_str(b, "JFIF")
    _put8(b, 0)
    _put16(b, 0x0101)
    _put8(b, 0)
    _put16(b, 1)
    _put16(b, 1)
    _put16(b, 0)
    _dqt(b, 0, ql)
    _dqt(b, 1, qc)
    _put16(b, 0xFFC0)                          # SOF0 : 3 composantes, Y 2×2, Cb et Cr 1×1
    _put16(b, 17)
    _put8(b, 8)
    _put16(b, r.height)
    _put16(b, r.width)
    _put8(b, 3)
    _put8(b, 1)
    _put8(b, 0x22)
    _put8(b, 0)
    _put8(b, 2)
    _put8(b, 0x11)
    _put8(b, 1)
    _put8(b, 3)
    _put8(b, 0x11)
    _put8(b, 1)
    _dht(b, 0, 0, DC_LUM_BITS, DC_LUM_VALS)
    _dht(b, 1, 0, AC_LUM_BITS, AC_LUM_VALS)
    _dht(b, 0, 1, DC_CHR_BITS, DC_CHR_VALS)
    _dht(b, 1, 1, AC_CHR_BITS, AC_CHR_VALS)
    _put16(b, 0xFFDA)                          # SOS
    _put16(b, 12)
    _put8(b, 3)
    _put8(b, 1)
    _put8(b, 0x00)
    _put8(b, 2)
    _put8(b, 0x11)
    _put8(b, 3)
    _put8(b, 0x11)
    _put8(b, 0)
    _put8(b, 63)
    _put8(b, 0)
    dcl := _htable(DC_LUM_BITS, DC_LUM_VALS)
    acl := _htable(AC_LUM_BITS, AC_LUM_VALS)
    dcc := _htable(DC_CHR_BITS, DC_CHR_VALS)
    acc := _htable(AC_CHR_BITS, AC_CHR_VALS)
    w := _JBits(b)
    ys := __mmap(4096)                         # Y d'un MCU 16×16 (4 octets par valeur)
    cb := __mmap(4096)
    cr := __mmap(4096)
    blk := __mmap(4096)
    tmp := __mmap(4096)
    coefs := __mmap(4096)
    pdy := 0
    pdb := 0
    pdr := 0
    my := 0
    while my < r.height:
        mx := 0
        while mx < r.width:
            # conversion YCbCr (BT.601, virgule fixe 16 bits), centrée sur 0
            yy := 0
            while yy < 16:
                xx := 0
                while xx < 16:
                    c := _rgb_at(r, mx + xx, my + yy)
                    rr := (c >> 16) & 255
                    gg := (c >> 8) & 255
                    bb := c & 255
                    o := (yy * 16 + xx) * 4
                    __store32(ys + o, ((19595 * rr + 38470 * gg + 7471 * bb + 32768) >> 16) - 128)
                    __store32(cb + o, (-11059 * rr - 21709 * gg + 32768 * bb + 32768) >> 16)
                    __store32(cr + o, (32768 * rr - 27439 * gg - 5329 * bb + 32768) >> 16)
                    xx += 1
                yy += 1
            # quatre blocs Y
            by := 0
            while by < 2:
                bx := 0
                while bx < 2:
                    i := 0
                    while i < 64:
                        __store32(blk + i * 4, __load32(ys + (((by * 8 + i // 8) * 16) + bx * 8 + i % 8) * 4))
                        i += 1
                    pdy = _encode_block(w, blk, tmp, coefs, ql, pdy, dcl, acl)
                    bx += 1
                by += 1
            # Cb et Cr : moyenne de 2×2
            pass_n := 0
            while pass_n < 2:
                src := cb if pass_n == 0 else cr
                i := 0
                while i < 64:
                    sx := (i % 8) * 2
                    sy := (i // 8) * 2
                    s := _s32(src + (sy * 16 + sx) * 4) + _s32(src + (sy * 16 + sx + 1) * 4) + _s32(src + ((sy + 1) * 16 + sx) * 4) + _s32(src + ((sy + 1) * 16 + sx + 1) * 4)
                    __store32(blk + i * 4, _div_round(s, 4))
                    i += 1
                if pass_n == 0:
                    pdb = _encode_block(w, blk, tmp, coefs, qc, pdb, dcc, acc)
                else:
                    pdr = _encode_block(w, blk, tmp, coefs, qc, pdr, dcc, acc)
                pass_n += 1
            mx += 16
        my += 16
    w.flush()
    _put16(b, 0xFFD9)
    __munmap(ys, 4096)
    __munmap(cb, 4096)
    __munmap(cr, 4096)
    __munmap(blk, 4096)
    __munmap(tmp, 4096)
    __munmap(coefs, 4096)
    out := b.to_str()
    b.free()
    return out

# ================================================================================================ PNG

const _CRC_POLY := 0xEDB88320
_crc_table: list[int] := []

func _crc_init():
    if len(_crc_table) == 256:
        return
    t: list[int] := []
    n := 0
    while n < 256:
        c := n
        k := 0
        while k < 8:
            c = (_CRC_POLY ^ (c >> 1)) if (c & 1) != 0 else (c >> 1)
            k += 1
        append(t, c)
        n += 1
    _crc_table = t

func _crc(a: int, n: int) -> int:
    _crc_init()
    c := 0xFFFFFFFF
    i := 0
    while i < n:
        c = _crc_table[(c ^ __load8(a + i)) & 255] ^ (c >> 8)
        i += 1
    return c ^ 0xFFFFFFFF

func _chunk(b: Buf, kind: str, data: Buf):
    _put32(b, data.n)
    start := b.n
    _put_str(b, kind)
    if data.n > 0:
        b.reserve(data.n)
        __copy(b.addr + b.n, data.addr, data.n)
        b.n += data.n
    _put32(b, _crc(b.addr + start, b.n - start))

# Écriture de bits, poids faible d'abord (deflate).
class _ZBits:
    out: Buf := Buf()
    acc: int := 0
    nb: int := 0

    func init(out: Buf):
        self.out = out
        self.acc = 0
        self.nb = 0

    func put(v: int, n: int):
        self.acc = self.acc | ((v & ((1 << n) - 1)) << self.nb)
        self.nb += n
        while self.nb >= 8:
            _put8(self.out, self.acc & 255)
            self.acc = self.acc >> 8
            self.nb -= 8

    # code de Huffman : écrit poids fort d'abord
    func code(c: int, n: int):
        r := 0
        i := 0
        while i < n:
            r = (r << 1) | ((c >> i) & 1)
            i += 1
        self.put(r, n)

    func flush():
        if self.nb > 0:
            _put8(self.out, self.acc & 255)
        self.acc = 0
        self.nb = 0

func _lit(z: _ZBits, v: int):
    if v < 144:
        z.code(0x30 + v, 8)
    elif v < 256:
        z.code(0x190 + v - 144, 9)
    elif v < 280:
        z.code(v - 256, 7)
    else:
        z.code(0xC0 + v - 280, 8)

func _match(z: _ZBits, length: int, dist: int):
    i := 0
    while i < 28 and LEN_BASE[i + 1] <= length:
        i += 1
    _lit(z, 257 + i)
    if LEN_EXTRA[i] > 0:
        z.put(length - LEN_BASE[i], LEN_EXTRA[i])
    j := 0
    while j < 29 and DIST_BASE[j + 1] <= dist:
        j += 1
    z.code(j, 5)
    if DIST_EXTRA[j] > 0:
        z.put(dist - DIST_BASE[j], DIST_EXTRA[j])

# zlib (deflate, un seul bloc à codes fixes ; répétitions cherchées par hachage de 3 octets, 8 candidats).
func _zlib(a: int, n: int) -> Buf:
    out := Buf()
    _put8(out, 0x78)
    _put8(out, 0x5E)
    z := _ZBits(out)
    z.put(1, 1)
    z.put(1, 2)
    hsize := 65536
    head := __mmap(hsize * 8)
    prev := __mmap(32768 * 8)
    i := 0
    while i < hsize:
        __store64(head + i * 8, -1)
        i += 1
    p := 0
    while p < n:
        best := 0
        bdist := 0
        if p + 3 <= n:
            h := ((__load8(a + p) << 10) ^ (__load8(a + p + 1) << 5) ^ __load8(a + p + 2)) & 65535
            cand := __load64(head + h * 8)
            tries := 0
            while cand >= 0 and p - cand <= 32768 and tries < 8:
                l := 0
                maxl := n - p
                if maxl > 258:
                    maxl = 258
                while l < maxl and __load8(a + cand + l) == __load8(a + p + l):
                    l += 1
                if l > best:
                    best = l
                    bdist = p - cand
                    if l == maxl:
                        break
                cand = __load64(prev + (cand & 32767) * 8)
                tries += 1
            __store64(prev + (p & 32767) * 8, __load64(head + h * 8))
            __store64(head + h * 8, p)
        if best >= 3:
            _match(z, best, bdist)
            k := 1
            while k < best:
                q := p + k
                if q + 3 <= n:
                    h2 := ((__load8(a + q) << 10) ^ (__load8(a + q + 1) << 5) ^ __load8(a + q + 2)) & 65535
                    __store64(prev + (q & 32767) * 8, __load64(head + h2 * 8))
                    __store64(head + h2 * 8, q)
                k += 1
            p += best
        else:
            _lit(z, __load8(a + p))
            p += 1
    _lit(z, 256)
    z.flush()
    __munmap(head, hsize * 8)
    __munmap(prev, 32768 * 8)
    s1 := 1
    s2 := 0
    i = 0
    while i < n:
        s1 = (s1 + __load8(a + i)) % 65521
        s2 = (s2 + s1) % 65521
        i += 1
    _put32(out, (s2 << 16) | s1)
    return out

func _paeth(a: int, b: int, c: int) -> int:
    p := a + b - c
    pa := p - a if p >= a else a - p
    pb := p - b if p >= b else b - p
    pc := p - c if p >= c else c - p
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c

func has_alpha(r: Raster) -> bool:
    i := 0
    n := r.width * r.height
    while i < n:
        if ((__load32(r.addr + i * 4) >> 24) & 255) != 255:
            return true
        i += 1
    return false

func png(r: Raster) -> str:
    alpha := has_alpha(r)
    bpp := 4 if alpha else 3
    stride := r.width * bpp
    raw := __mmap(stride * r.height + 4096)
    filt := __mmap((stride + 1) * r.height + 4096)
    y := 0
    while y < r.height:
        x := 0
        while x < r.width:
            c := __load32(r.addr + (y * r.width + x) * 4)
            o := raw + y * stride + x * bpp
            __store8(o, (c >> 16) & 255)
            __store8(o + 1, (c >> 8) & 255)
            __store8(o + 2, c & 255)
            if alpha:
                __store8(o + 3, (c >> 24) & 255)
            x += 1
        y += 1
    # filtre par ligne : celui dont la somme des valeurs absolues (signées) est la plus petite
    y = 0
    while y < r.height:
        best := 0
        bsum := -1
        f := 0
        while f < 5:
            s := 0
            i := 0
            while i < stride:
                v := _filtered(raw, stride, bpp, y, i, f)
                s += v if v < 128 else 256 - v
                i += 1
            if bsum < 0 or s < bsum:
                bsum = s
                best = f
            f += 1
        o := filt + y * (stride + 1)
        __store8(o, best)
        i := 0
        while i < stride:
            __store8(o + 1 + i, _filtered(raw, stride, bpp, y, i, best))
            i += 1
        y += 1
    z := _zlib(filt, (stride + 1) * r.height)
    __munmap(raw, stride * r.height + 4096)
    __munmap(filt, (stride + 1) * r.height + 4096)
    b := Buf()
    _put32(b, 0x89504E47)
    _put32(b, 0x0D0A1A0A)
    hd := Buf()
    _put32(hd, r.width)
    _put32(hd, r.height)
    _put8(hd, 8)
    _put8(hd, 6 if alpha else 2)
    _put8(hd, 0)
    _put8(hd, 0)
    _put8(hd, 0)
    _chunk(b, "IHDR", hd)
    _chunk(b, "IDAT", z)
    _chunk(b, "IEND", Buf())
    hd.free()
    z.free()
    out := b.to_str()
    b.free()
    return out

func _filtered(raw: int, stride: int, bpp: int, y: int, i: int, f: int) -> int:
    p := raw + y * stride + i
    v := __load8(p)
    left := __load8(p - bpp) if i >= bpp else 0
    up := __load8(p - stride) if y > 0 else 0
    ul := __load8(p - stride - bpp) if y > 0 and i >= bpp else 0
    if f == 1:
        return (v - left) & 255
    if f == 2:
        return (v - up) & 255
    if f == 3:
        return (v - (left + up) // 2) & 255
    if f == 4:
        return (v - _paeth(left, up, ul)) & 255
    return v

# ================================================================================================ transformations

func _be16(a: int) -> int:
    return (__load8(a) << 8) | __load8(a + 1)

func _rd16(a: int, le: bool) -> int:
    if le:
        return __load8(a) | (__load8(a + 1) << 8)
    return _be16(a)

func _rd32(a: int, le: bool) -> int:
    if le:
        return __load8(a) | (__load8(a + 1) << 8) | (__load8(a + 2) << 16) | (__load8(a + 3) << 24)
    return (__load8(a) << 24) | (__load8(a + 1) << 16) | (__load8(a + 2) << 8) | __load8(a + 3)

# Orientation Exif (balise 0x0112 de l'IFD0, segment APP1 d'un JPEG) ; 1 si absente ou illisible.
func exif_orientation(data: str) -> int:
    a := inf.str_addr(data)
    n := inf.str_len(data)
    if n < 4 or __load8(a) != 255 or __load8(a + 1) != 0xD8:
        return 1
    p := 2
    while p + 4 <= n:
        if __load8(a + p) != 255:
            return 1
        m := __load8(a + p + 1)
        if m == 0xDA or m == 0xD9:
            return 1
        seg := _be16(a + p + 2)
        if m == 0xE1 and seg >= 16 and p + 2 + seg <= n and __load8(a + p + 4) == 69 and __load8(a + p + 5) == 120 and __load8(a + p + 6) == 105 and __load8(a + p + 7) == 102:
            t := a + p + 10
            tn := seg - 8
            le := __load8(t) == 73
            ifd := _rd32(t + 4, le)
            if ifd + 2 > tn:
                return 1
            cnt := _rd16(t + ifd, le)
            k := 0
            while k < cnt and ifd + 2 + k * 12 + 12 <= tn:
                e := t + ifd + 2 + k * 12
                if _rd16(e, le) == 0x0112:
                    o := _rd16(e + 8, le)
                    return o if o >= 1 and o <= 8 else 1
                k += 1
            return 1
        p += 2 + seg
    return 1

# Applique une orientation Exif : le résultat s'affiche droit.
func orient(r: Raster, o: int) -> Raster:
    if o <= 1 or o > 8:
        return r
    w := r.width
    h := r.height
    swap := o >= 5
    d := rs.create(h if swap else w, w if swap else h)
    y := 0
    while y < d.height:
        x := 0
        while x < d.width:
            sx := x
            sy := y
            if o == 2:
                sx = w - 1 - x
            elif o == 3:
                sx = w - 1 - x
                sy = h - 1 - y
            elif o == 4:
                sy = h - 1 - y
            elif o == 5:
                sx = y
                sy = x
            elif o == 6:
                sx = y
                sy = h - 1 - x
            elif o == 7:
                sx = w - 1 - y
                sy = h - 1 - x
            elif o == 8:
                sx = w - 1 - y
                sy = x
            __store32(d.addr + (y * d.width + x) * 4, __load32(r.addr + (sy * w + sx) * 4))
            x += 1
        y += 1
    return d

func crop(r: Raster, x0: int, y0: int, cw: int, ch: int) -> Raster:
    if x0 < 0 or y0 < 0 or cw < 1 or ch < 1 or x0 + cw > r.width or y0 + ch > r.height:
        _err("découpe hors de l'image")
    d := rs.create(cw, ch)
    y := 0
    while y < ch:
        __copy(d.addr + y * cw * 4, r.addr + ((y0 + y) * r.width + x0) * 4, cw * 4)
        y += 1
    return d

# Image décodée (première image d'une animation), orientation Exif appliquée pour un JPEG.
func load(data: str) -> Raster:
    an: Anim := im.decode(data)
    if len(an.frames) == 0:
        _err("image vide")
    src: Raster := an.frames[0]
    if im.kind(data) == "jpeg":
        return orient(src, exif_orientation(data))
    return src

# Réduction « fit » (tient dans tw × th) ou « cover » (remplit tw × th, recadré au centre) ; jamais agrandie.
func resize(src: Raster, tw: int, th: int, mode: str) -> Raster:
    if tw < 1 or th < 1:
        _err("taille de vignette invalide")
    w := src.width
    h := src.height
    nw := w
    nh := h
    cut: Raster := src
    if mode == "cover":
        # plus grande zone au centre qui a les proportions de tw × th
        cw := w
        ch := (w * th) // tw
        if ch > h:
            ch = h
            cw = (h * tw) // th
        if cw < 1:
            cw = 1
        if ch < 1:
            ch = 1
        if cw != w or ch != h:
            cut = crop(src, (w - cw) // 2, (h - ch) // 2, cw, ch)
        nw = tw if tw < cw else cw
        nh = th if th < ch else ch
        if nw * ch != nh * cw:
            if (nw * ch) // cw < nh:
                nh = (nw * ch + cw // 2) // cw
            else:
                nw = (nh * cw + ch // 2) // ch
    elif mode == "fit":
        if w > tw or h > th:
            if w * th > h * tw:
                nw = tw
                nh = (h * tw + w // 2) // w
            else:
                nh = th
                nw = (w * th + h // 2) // h
    else:
        _err("mode de vignette inconnu : " + mode + " (fit ou cover)")
    if nw < 1:
        nw = 1
    if nh < 1:
        nh = 1
    return rs.shrink(cut, nw, nh)

# Octets JPEG ou PNG ; « auto » : PNG s'il reste de la transparence, sinon JPEG.
func encode(r: Raster, fmt: str, quality: int) -> str:
    f := fmt
    if f == "auto":
        f = "png" if has_alpha(r) else "jpeg"
    if f == "png":
        return png(r)
    if f == "jpeg" or f == "jpg":
        return jpeg(r, quality)
    _err("format de vignette inconnu : " + fmt + " (jpeg, png ou auto)")
    return ""

# Vignette : voir l'en-tête. Rend les octets JPEG ou PNG.
func thumbnail(data: str, tw: int, th: int, mode: str, fmt: str, quality: int) -> str:
    return encode(resize(load(data), tw, th, mode), fmt, quality)

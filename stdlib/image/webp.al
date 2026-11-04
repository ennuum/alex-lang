# alex: native
# alex: intrinsics
# NOVA (édition bureau) — décodeur WebP : conteneur RIFF (VP8, VP8L, VP8X), images avec perte (VP8 image
# clé, RFC 6386 : arbres de modes, coefficients, quantification, prédiction intra, transformées, filtre de
# boucle, YUV → RVB avec suréchantillonnage « fancy » de libwebp), sans perte (VP8L, RFC 9649 : codes
# préfixes, LZ77, cache de couleurs, transformations), canal alpha (ALPH brut ou sans perte, filtres) et
# animation (ANMF : position, fusion, effacement).
#
#   f := webp.decode(adresse, longueur)   -> WebpFrames : f.frames (list[Raster]), f.delays (ms)
use image.raster as rs
from image.raster use Raster
use image.vp8tab as tab
from core use len
from collections use append

const MAX_FRAMES := 400

class WebpFrames:
    frames: list[Raster] := []
    delays: list[int] := []

    func init():
        self.frames = []
        self.delays = []

func _err(msg: str):
    raise("ImageError", "WebP : " + msg)

func _mem(n: int) -> int:
    return __mmap((n + 4095) & ~4095)

func _free(a: int, n: int):
    if a != 0:
        __munmap(a, (n + 4095) & ~4095)

func _le16(a: int) -> int:
    return __load8(a) | (__load8(a + 1) << 8)

func _le24(a: int) -> int:
    return __load8(a) | (__load8(a + 1) << 8) | (__load8(a + 2) << 16)

func _le32(a: int) -> int:
    return __load8(a) | (__load8(a + 1) << 8) | (__load8(a + 2) << 16) | (__load8(a + 3) << 24)

func _clip255(v: int) -> int:
    if v < 0:
        return 0
    if v > 255:
        return 255
    return v

func _divup(n: int, k: int) -> int:
    return (n + (1 << k) - 1) >> k

func _fourcc(a: int, s: str) -> bool:
    i := 0
    while i < 4:
        if __load8(a + i) != __load8(__str_addr(s) + 8 + i):
            return false
        i += 1
    return true

# =============================================================================================== VP8L

# Lecteur de bits du format sans perte : poids faible d'abord ; au-delà de la fin, des zéros.
class _Bits:
    a: int := 0
    end: int := 0
    pos: int := 0
    buf: int := 0
    cnt: int := 0

func _bits(a: int, n: int) -> _Bits:
    b := _Bits()
    b.a = a
    b.pos = a
    b.end = a + n
    return b

func _fill(b: _Bits, k: int):
    while b.cnt < k:
        v := 0
        if b.pos < b.end:
            v = __load8(b.pos)
        b.pos += 1
        b.buf = b.buf | (v << b.cnt)
        b.cnt += 8

func _rd(b: _Bits, k: int) -> int:
    if k == 0:
        return 0
    _fill(b, k)
    v := b.buf & ((1 << k) - 1)
    b.buf = b.buf >> k
    b.cnt -= k
    return v

# Code préfixe canonique : table directe sur 8 bits (codes courts) et décodage bit à bit au-delà.
class _Huff:
    single: int := -1           # un seul symbole : aucun bit lu
    lut: list[int] := []        # (longueur << 16) | symbole, 0 : code de plus de 8 bits
    first: list[int] := []      # par longueur : premier code canonique
    count: list[int] := []
    index: list[int] := []      # par longueur : position du premier symbole dans syms
    syms: list[int] := []

func _rev(c: int, n: int) -> int:
    r := 0
    i := 0
    while i < n:
        r = (r << 1) | ((c >> i) & 1)
        i += 1
    return r

func _huff(lengths: list[int]) -> _Huff:
    h := _Huff()
    h.count = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    nsym := 0
    last := 0
    i := 0
    while i < len(lengths):
        l := lengths[i]
        if l > 0:
            if l > 15:
                _err("code préfixe invalide")
            h.count[l] = h.count[l] + 1
            nsym += 1
            last = i
        i += 1
    if nsym <= 1:
        h.single = last
        return h
    h.first = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    h.index = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    # premiers codes par longueur (méthode de deflate)
    code := 0
    idx := 0
    l3 := 1
    while l3 <= 15:
        h.first[l3] = code
        h.index[l3] = idx
        code = (code + h.count[l3]) << 1
        idx += h.count[l3]
        l3 += 1
    h.syms = []
    k := 0
    while k < nsym:
        append(h.syms, 0)
        k += 1
    next_code := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    pos := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    l4 := 1
    while l4 <= 15:
        next_code[l4] = h.first[l4]
        pos[l4] = h.index[l4]
        l4 += 1
    h.lut = []
    m := 0
    while m < 256:
        append(h.lut, 0)
        m += 1
    s := 0
    while s < len(lengths):
        l5 := lengths[s]
        if l5 > 0:
            h.syms[pos[l5]] = s
            pos[l5] = pos[l5] + 1
            c := next_code[l5]
            next_code[l5] = c + 1
            if l5 <= 8:
                r := _rev(c, l5)
                step := 1 << l5
                j := r
                while j < 256:
                    h.lut[j] = (l5 << 16) | s
                    j += step
        s += 1
    return h

func _sym(b: _Bits, h: _Huff) -> int:
    if h.single >= 0:
        return h.single
    _fill(b, 8)
    e := h.lut[b.buf & 255]
    if e != 0:
        l := e >> 16
        b.buf = b.buf >> l
        b.cnt -= l
        return e & 65535
    code := 0
    l2 := 1
    while l2 <= 15:
        code = (code << 1) | _rd(b, 1)
        d := code - h.first[l2]
        if d >= 0 and d < h.count[l2]:
            return h.syms[h.index[l2] + d]
        l2 += 1
    _err("code préfixe introuvable")
    return 0

const _CL_ORDER := [17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]

func _read_code(b: _Bits, alphabet: int) -> _Huff:
    lengths: list[int] := []
    i := 0
    while i < alphabet:
        append(lengths, 0)
        i += 1
    if _rd(b, 1) == 1:
        # code simple : un ou deux symboles
        nsym := _rd(b, 1) + 1
        first8 := _rd(b, 1)
        s0 := _rd(b, 1 + 7 * first8)
        if s0 >= alphabet:
            _err("symbole hors alphabet")
        lengths[s0] = 1
        if nsym == 2:
            s1 := _rd(b, 8)
            if s1 >= alphabet:
                _err("symbole hors alphabet")
            lengths[s1] = 1
        return _huff(lengths)
    cl := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    ncl := 4 + _rd(b, 4)
    k := 0
    while k < ncl:
        cl[_CL_ORDER[k]] = _rd(b, 3)
        k += 1
    clh := _huff(cl)
    max_symbol := alphabet
    if _rd(b, 1) == 1:
        nb := 2 + 2 * _rd(b, 3)
        max_symbol = 2 + _rd(b, nb)
        if max_symbol > alphabet:
            _err("nombre de symboles invalide")
    prev := 8
    s := 0
    while s < alphabet:
        if max_symbol == 0:
            break
        max_symbol -= 1
        c := _sym(b, clh)
        if c < 16:
            lengths[s] = c
            s += 1
            if c != 0:
                prev = c
        else:
            rep := 0
            val := 0
            if c == 16:
                rep = 3 + _rd(b, 2)
                val = prev
            elif c == 17:
                rep = 3 + _rd(b, 3)
            else:
                rep = 11 + _rd(b, 7)
            if s + rep > alphabet:
                _err("longueurs de codes invalides")
            while rep > 0:
                lengths[s] = val
                s += 1
                rep -= 1
    return _huff(lengths)

class _Group:
    g: _Huff
    r: _Huff
    b: _Huff
    a: _Huff
    d: _Huff

func _prefix_value(b: _Bits, code: int) -> int:
    if code < 4:
        return code + 1
    extra := (code - 2) >> 1
    offset := (2 + (code & 1)) << extra
    return offset + _rd(b, extra) + 1

class _Tf:
    kind: int := 0          # 0 prédiction, 1 couleurs, 2 soustraction du vert, 3 palette
    bits: int := 0
    xsize: int := 0         # largeur de l'image produite par la transformation inverse
    data: int := 0          # sous-image (ou palette)
    dlen: int := 0
    ncolors: int := 0

# Pixels ARGB (xs x ys) d'une image codée par entropie ; level0 : image principale (codes méta autorisés).
func _vp8l_pixels(b: _Bits, xs: int, ys: int, level0: bool) -> int:
    cache_bits := 0
    if _rd(b, 1) == 1:
        cache_bits = _rd(b, 4)
        if cache_bits < 1 or cache_bits > 11:
            _err("cache de couleurs invalide")
    hbits := 0
    ent := 0
    ew := 0
    eh := 0
    ngroups := 1
    if level0 and _rd(b, 1) == 1:
        hbits = _rd(b, 3) + 2
        ew = _divup(xs, hbits)
        eh = _divup(ys, hbits)
        ent = _vp8l_pixels(b, ew, eh, false)
        i := 0
        while i < ew * eh:
            gv := (__load32(ent + i * 4) >> 8) & 65535
            if gv + 1 > ngroups:
                ngroups = gv + 1
            i += 1
    csize := 0
    if cache_bits > 0:
        csize = 1 << cache_bits
    groups: list[_Group] := []
    gi := 0
    while gi < ngroups:
        g := _Group()
        g.g = _read_code(b, 256 + 24 + csize)
        g.r = _read_code(b, 256)
        g.b = _read_code(b, 256)
        g.a = _read_code(b, 256)
        g.d = _read_code(b, 40)
        append(groups, g)
        gi += 1
    total := xs * ys
    out := _mem(total * 4)
    cache := 0
    if csize > 0:
        cache = _mem(csize * 4)
    shift := 32 - cache_bits
    i2 := 0
    x := 0
    y := 0
    gr := groups[0]
    while i2 < total:
        if ent != 0:
            gr = groups[(__load32(ent + ((y >> hbits) * ew + (x >> hbits)) * 4) >> 8) & 65535]
        s := _sym(b, gr.g)
        if s < 256:
            red := _sym(b, gr.r)
            blue := _sym(b, gr.b)
            alpha := _sym(b, gr.a)
            argb := (alpha << 24) | (red << 16) | (s << 8) | blue
            __store32(out + i2 * 4, argb)
            if cache != 0:
                __store32(cache + (((0x1e35a7bd * argb) & 0xFFFFFFFF) >> shift) * 4, argb)
            i2 += 1
            x += 1
            if x == xs:
                x = 0
                y += 1
        elif s < 280:
            length := _prefix_value(b, s - 256)
            dcode := _prefix_value(b, _sym(b, gr.d))
            dist := 0
            if dcode > 120:
                dist = dcode - 120
            else:
                dist = tab.VP8L_DIST[(dcode - 1) * 2] + tab.VP8L_DIST[(dcode - 1) * 2 + 1] * xs
                if dist < 1:
                    dist = 1
            if dist > i2 or i2 + length > total:
                _err("référence arrière invalide")
            k := 0
            while k < length:
                v := __load32(out + (i2 - dist) * 4)
                __store32(out + i2 * 4, v)
                if cache != 0:
                    __store32(cache + (((0x1e35a7bd * v) & 0xFFFFFFFF) >> shift) * 4, v)
                i2 += 1
                k += 1
            x += length
            while x >= xs:
                x -= xs
                y += 1
        else:
            ci := s - 280
            if ci >= csize:
                _err("index de cache invalide")
            v2 := __load32(cache + ci * 4)
            __store32(out + i2 * 4, v2)
            i2 += 1
            x += 1
            if x == xs:
                x = 0
                y += 1
    _free(cache, csize * 4)
    _free(ent, ew * eh * 4)
    return out

func _avg2(a: int, b: int) -> int:
    return (((a ^ b) & 0xFEFEFEFE) >> 1) + (a & b)

func _sel(l: int, t: int, tl: int) -> int:
    pl := 0
    pt := 0
    sh := 0
    while sh < 32:
        cl := (l >> sh) & 255
        ct := (t >> sh) & 255
        ctl := (tl >> sh) & 255
        p := cl + ct - ctl
        dl := p - cl
        dt := p - ct
        if dl < 0:
            dl = -dl
        if dt < 0:
            dt = -dt
        pl += dl
        pt += dt
        sh += 8
    if pl < pt:
        return l
    return t

func _clamp_full(a: int, b: int, c: int) -> int:
    r := 0
    sh := 0
    while sh < 32:
        v := _clip255(((a >> sh) & 255) + ((b >> sh) & 255) - ((c >> sh) & 255))
        r = r | (v << sh)
        sh += 8
    return r

func _clamp_half(a: int, b: int) -> int:
    r := 0
    sh := 0
    while sh < 32:
        ca := (a >> sh) & 255
        d := ca - ((b >> sh) & 255)
        # division tronquée vers zéro (comme en C)
        h := d // 2
        if d < 0:
            h = -((-d) // 2)
        r = r | (_clip255(ca + h) << sh)
        sh += 8
    return r

# Somme canal par canal, modulo 256.
func _add_px(a: int, b: int) -> int:
    return (((a & 0xFF00FF00) + (b & 0xFF00FF00)) & 0xFF00FF00) | (((a & 0x00FF00FF) + (b & 0x00FF00FF)) & 0x00FF00FF)

func _predict(mode: int, l: int, t: int, tr: int, tl: int) -> int:
    if mode == 0:
        return 0xFF000000
    if mode == 1:
        return l
    if mode == 2:
        return t
    if mode == 3:
        return tr
    if mode == 4:
        return tl
    if mode == 5:
        return _avg2(_avg2(l, tr), t)
    if mode == 6:
        return _avg2(l, tl)
    if mode == 7:
        return _avg2(l, t)
    if mode == 8:
        return _avg2(tl, t)
    if mode == 9:
        return _avg2(t, tr)
    if mode == 10:
        return _avg2(_avg2(l, tl), _avg2(t, tr))
    if mode == 11:
        return _sel(l, t, tl)
    if mode == 12:
        return _clamp_full(l, t, tl)
    if mode == 13:
        return _clamp_half(_avg2(l, t), tl)
    return 0xFF000000

func _s8(v: int) -> int:
    v = v & 255
    if v >= 128:
        return v - 256
    return v

# Transformations inverses, de la dernière lue à la première ; rend les pixels (largeur finale).
func _inverse(tfs: list[_Tf], pix0: int, ys: int) -> int:
    pix := pix0
    k := len(tfs) - 1
    while k >= 0:
        t := tfs[k]
        w := t.xsize
        if t.kind == 0:
            bw := _divup(w, t.bits)
            y := 0
            while y < ys:
                x := 0
                while x < w:
                    i := y * w + x
                    p := pix + i * 4
                    pred := 0
                    if y == 0:
                        if x == 0:
                            pred = 0xFF000000
                        else:
                            pred = __load32(p - 4)
                    elif x == 0:
                        pred = __load32(p - w * 4)
                    else:
                        mode := (__load32(t.data + ((y >> t.bits) * bw + (x >> t.bits)) * 4) >> 8) & 15
                        pred = _predict(mode, __load32(p - 4), __load32(p - w * 4), __load32(p - w * 4 + 4), __load32(p - w * 4 - 4))
                    __store32(p, _add_px(__load32(p), pred))
                    x += 1
                y += 1
        elif t.kind == 1:
            bw2 := _divup(w, t.bits)
            y2 := 0
            while y2 < ys:
                x2 := 0
                while x2 < w:
                    e := __load32(t.data + ((y2 >> t.bits) * bw2 + (x2 >> t.bits)) * 4)
                    g2r := _s8(e)
                    g2b := _s8(e >> 8)
                    r2b := _s8(e >> 16)
                    p2 := pix + (y2 * w + x2) * 4
                    c := __load32(p2)
                    green := _s8(c >> 8)
                    red := (((c >> 16) & 255) + ((g2r * green) >> 5)) & 255
                    blue := ((c & 255) + ((g2b * green) >> 5)) & 255
                    blue = (blue + ((r2b * _s8(red)) >> 5)) & 255
                    __store32(p2, (c & 0xFF00FF00) | (red << 16) | blue)
                    x2 += 1
                y2 += 1
        elif t.kind == 2:
            n := w * ys
            i3 := 0
            while i3 < n:
                p3 := pix + i3 * 4
                c3 := __load32(p3)
                g := (c3 >> 8) & 255
                __store32(p3, (c3 & 0xFF00FF00) | ((((c3 >> 16) + g) & 255) << 16) | (((c3 & 255) + g) & 255))
                i3 += 1
        else:
            pw := _divup(w, t.bits)
            out := _mem(w * ys * 4)
            bpp := 8 >> t.bits
            mask := (1 << bpp) - 1
            y4 := 0
            while y4 < ys:
                x4 := 0
                while x4 < w:
                    packed := (__load32(pix + (y4 * pw + (x4 >> t.bits)) * 4) >> 8) & 255
                    idx := (packed >> ((x4 & ((1 << t.bits) - 1)) * bpp)) & mask
                    col := 0
                    if idx < t.ncolors:
                        col = __load32(t.data + idx * 4)
                    __store32(out + (y4 * w + x4) * 4, col)
                    x4 += 1
                y4 += 1
            _free(pix, pw * ys * 4)
            pix = out
        k -= 1
    return pix

# Flux d'image sans perte (transformations puis image principale) de dimensions w x h : pixels ARGB.
func _vp8l_stream(b: _Bits, w: int, h: int) -> int:
    tfs: list[_Tf] := []
    xs := w
    seen := 0
    while _rd(b, 1) == 1:
        kind := _rd(b, 2)
        if (seen & (1 << kind)) != 0:
            _err("transformation répétée")
        seen = seen | (1 << kind)
        t := _Tf()
        t.kind = kind
        t.xsize = xs
        if kind == 0 or kind == 1:
            t.bits = _rd(b, 3) + 2
            t.data = _vp8l_pixels(b, _divup(xs, t.bits), _divup(h, t.bits), false)
        elif kind == 3:
            nc := _rd(b, 8) + 1
            t.ncolors = nc
            if nc > 16:
                t.bits = 0
            elif nc > 4:
                t.bits = 1
            elif nc > 2:
                t.bits = 2
            else:
                t.bits = 3
            pal := _vp8l_pixels(b, nc, 1, false)
            i := 1
            while i < nc:
                __store32(pal + i * 4, _add_px(__load32(pal + i * 4), __load32(pal + (i - 1) * 4)))
                i += 1
            t.data = pal
            xs = _divup(xs, t.bits)
        append(tfs, t)
    pix := _vp8l_pixels(b, xs, h, true)
    return _inverse(tfs, pix, h)

func vp8l(a: int, n: int) -> Raster:
    if n < 5 or __load8(a) != 0x2F:
        _err("signature VP8L absente")
    b := _bits(a + 1, n - 1)
    w := _rd(b, 14) + 1
    h := _rd(b, 14) + 1
    _rd(b, 1)
    if _rd(b, 3) != 0:
        _err("version VP8L inconnue")
    r := rs.create(w, h)
    pix := _vp8l_stream(b, w, h)
    __copy(r.addr, pix, w * h * 4)
    _free(pix, w * h * 4)
    return r

# =============================================================================================== VP8

# Décodeur booléen (RFC 6386, 7.3).
class _Bool:
    pos: int := 0
    end: int := 0
    value: int := 0
    range: int := 255
    bits: int := 0

func _bool(a: int, n: int) -> _Bool:
    d := _Bool()
    d.end = a + n
    b0 := 0
    b1 := 0
    if n > 0:
        b0 = __load8(a)
    if n > 1:
        b1 = __load8(a + 1)
    d.value = (b0 << 8) | b1
    d.pos = a + 2
    return d

func _bget(d: _Bool, prob: int) -> int:
    split := 1 + (((d.range - 1) * prob) >> 8)
    big := split << 8
    r := 0
    if d.value >= big:
        r = 1
        d.range -= split
        d.value -= big
    else:
        d.range = split
    while d.range < 128:
        d.value = d.value << 1
        d.range = d.range << 1
        d.bits += 1
        if d.bits == 8:
            d.bits = 0
            if d.pos < d.end:
                d.value = d.value | __load8(d.pos)
            d.pos += 1
    return r

func _blit(d: _Bool, n: int) -> int:
    v := 0
    i := 0
    while i < n:
        v = (v << 1) | _bget(d, 128)
        i += 1
    return v

func _bsigned(d: _Bool, n: int) -> int:
    v := _blit(d, n)
    if _bget(d, 128) == 1:
        return -v
    return v

func _bopt(d: _Bool, n: int) -> int:
    if _bget(d, 128) == 1:
        return _bsigned(d, n)
    return 0

# Arbre des modes 4x4 (RFC 6386, 11.2) ; feuilles : valeurs négatives ou nulles.
const _BMODE_TREE := [0, 2, -1, 4, -2, 6, 8, 12, -3, 10, -5, -6, -4, 14, -7, 16, -8, -9]

class _Vp8:
    w: int := 0
    h: int := 0
    mbw: int := 0
    mbh: int := 0
    ys: int := 0            # pas des plans (avec bordures)
    cs: int := 0
    py: int := 0            # plans Y, U, V : origine (0, 0) après une ligne et une colonne de bordure
    pu: int := 0
    pv: int := 0
    ysize: int := 0
    csize: int := 0
    probs: list[int] := []
    coef: list[int] := []   # 16 blocs Y, 4 U, 4 V, puis Y2 : 25 x 16 coefficients
    tmp: list[int] := []
    q: list[int] := []      # par segment : y1dc y1ac y2dc y2ac uvdc uvac

func _yat(v: _Vp8, x: int, y: int) -> int:
    return v.py + (y + 1) * v.ys + x + 1

func _cat(v: _Vp8, base: int, x: int, y: int) -> int:
    return base + (y + 1) * v.cs + x + 1

# Coefficients d'un bloc (libwebp GetCoeffs) : rend la position après le dernier coefficient lu.
func _coeffs(v: _Vp8, d: _Bool, typ: int, ctx: int, dcq: int, acq: int, first: int, out: int) -> int:
    n := first
    pr := v.probs
    p := ((typ * 8 + tab.VP8_BANDS[n]) * 3 + ctx) * 11
    while n < 16:
        if _bget(d, pr[p]) == 0:
            return n
        while _bget(d, pr[p + 1]) == 0:
            n += 1
            if n == 16:
                return 16
            p = ((typ * 8 + tab.VP8_BANDS[n]) * 3) * 11
        val := 0
        nctx := 0
        if _bget(d, pr[p + 2]) == 0:
            val = 1
            nctx = 1
        else:
            nctx = 2
            if _bget(d, pr[p + 3]) == 0:
                if _bget(d, pr[p + 4]) == 0:
                    val = 2
                else:
                    val = 3 + _bget(d, pr[p + 5])
            elif _bget(d, pr[p + 6]) == 0:
                if _bget(d, pr[p + 7]) == 0:
                    val = 5 + _bget(d, 159)
                else:
                    val = 7 + 2 * _bget(d, 165)
                    val += _bget(d, 145)
            else:
                b1 := _bget(d, pr[p + 8])
                b0 := _bget(d, pr[p + 9 + b1])
                cat := 2 * b1 + b0
                extra := 0
                if cat == 0:
                    extra = (_bget(d, 173) << 2) | (_bget(d, 148) << 1)
                    extra = extra | _bget(d, 140)
                elif cat == 1:
                    extra = (_bget(d, 176) << 3) | (_bget(d, 155) << 2)
                    extra = extra | (_bget(d, 140) << 1)
                    extra = extra | _bget(d, 135)
                elif cat == 2:
                    extra = (_bget(d, 180) << 4) | (_bget(d, 157) << 3)
                    extra = extra | (_bget(d, 141) << 2)
                    extra = extra | (_bget(d, 134) << 1)
                    extra = extra | _bget(d, 130)
                else:
                    k := 0
                    while k < 11:
                        extra = (extra << 1) | _bget(d, tab.VP8_PCAT6[k])
                        k += 1
                val = extra + 3 + (8 << cat)
        if _bget(d, 128) == 1:
            val = -val
        qv := acq
        if n == 0:
            qv = dcq
        v.coef[out + tab.VP8_ZIGZAG[n]] = val * qv
        n += 1
        if n < 16:
            p = ((typ * 8 + tab.VP8_BANDS[n]) * 3 + nctx) * 11
    return 16

func _mul1(a: int) -> int:
    return ((a * 20091) >> 16) + a

func _mul2(a: int) -> int:
    return (a * 35468) >> 16

# Transformée inverse 4x4 ajoutée à la prédiction (dst, pas stride).
func _idct_add(v: _Vp8, off: int, dst: int, stride: int):
    c := v.coef
    nonzero := false
    k := 0
    while k < 16:
        if c[off + k] != 0:
            nonzero = true
            break
        k += 1
    if not nonzero:
        return
    t := v.tmp
    i := 0
    while i < 4:
        i0 := c[off + i]
        i4 := c[off + 4 + i]
        i8 := c[off + 8 + i]
        i12 := c[off + 12 + i]
        a := i0 + i8
        b := i0 - i8
        cc := _mul2(i4) - _mul1(i12)
        dd := _mul1(i4) + _mul2(i12)
        t[i * 4] = a + dd
        t[i * 4 + 1] = b + cc
        t[i * 4 + 2] = b - cc
        t[i * 4 + 3] = a - dd
        i += 1
    j := 0
    while j < 4:
        dc := t[j] + 4
        a2 := dc + t[8 + j]
        b2 := dc - t[8 + j]
        c2 := _mul2(t[4 + j]) - _mul1(t[12 + j])
        d2 := _mul1(t[4 + j]) + _mul2(t[12 + j])
        row := dst + j * stride
        __store8(row, _clip255(__load8(row) + ((a2 + d2) >> 3)))
        __store8(row + 1, _clip255(__load8(row + 1) + ((b2 + c2) >> 3)))
        __store8(row + 2, _clip255(__load8(row + 2) + ((b2 - c2) >> 3)))
        __store8(row + 3, _clip255(__load8(row + 3) + ((a2 - d2) >> 3)))
        j += 1

# Walsh-Hadamard inverse du bloc Y2 : coefficient continu de chacun des 16 blocs Y.
func _iwht(v: _Vp8):
    c := v.coef
    t := v.tmp
    i := 0
    while i < 4:
        a1 := c[384 + i] + c[384 + 12 + i]
        b1 := c[384 + 4 + i] + c[384 + 8 + i]
        c1 := c[384 + 4 + i] - c[384 + 8 + i]
        d1 := c[384 + i] - c[384 + 12 + i]
        t[i] = a1 + b1
        t[4 + i] = c1 + d1
        t[8 + i] = a1 - b1
        t[12 + i] = d1 - c1
        i += 1
    j := 0
    while j < 4:
        a2 := t[j * 4] + t[j * 4 + 3]
        b2 := t[j * 4 + 1] + t[j * 4 + 2]
        c2 := t[j * 4 + 1] - t[j * 4 + 2]
        d2 := t[j * 4] - t[j * 4 + 3]
        c[(j * 4) * 16] = (a2 + b2 + 3) >> 3
        c[(j * 4 + 1) * 16] = (c2 + d2 + 3) >> 3
        c[(j * 4 + 2) * 16] = (a2 - b2 + 3) >> 3
        c[(j * 4 + 3) * 16] = (d2 - c2 + 3) >> 3
        j += 1

# Prédiction d'un bloc n x n (16 luma, 8 chroma) : DC, V, H, TM ; mode selon l'énumération de la RFC.
func _pred_block(dst: int, stride: int, n: int, mode: int, has_top: bool, has_left: bool):
    top := dst - stride
    if mode == 0:
        s := 0
        cnt := 0
        shift := 3
        if n == 16:
            shift = 4
        k := 0
        if has_top:
            while k < n:
                s += __load8(top + k)
                k += 1
            cnt += 1
        if has_left:
            k = 0
            while k < n:
                s += __load8(dst + k * stride - 1)
                k += 1
            cnt += 1
        val := 128
        if cnt == 2:
            val = (s + n) >> (shift + 1)
        elif cnt == 1:
            val = (s + (n >> 1)) >> shift
        y := 0
        while y < n:
            x := 0
            while x < n:
                __store8(dst + y * stride + x, val)
                x += 1
            y += 1
    elif mode == 1:
        y1 := 0
        while y1 < n:
            __copy(dst + y1 * stride, top, n)
            y1 += 1
    elif mode == 2:
        y2 := 0
        while y2 < n:
            l := __load8(dst + y2 * stride - 1)
            x2 := 0
            while x2 < n:
                __store8(dst + y2 * stride + x2, l)
                x2 += 1
            y2 += 1
    else:
        p := __load8(top - 1)
        y3 := 0
        while y3 < n:
            l3 := __load8(dst + y3 * stride - 1) - p
            x3 := 0
            while x3 < n:
                __store8(dst + y3 * stride + x3, _clip255(l3 + __load8(top + x3)))
                x3 += 1
            y3 += 1

func _a3(x: int, y: int, z: int) -> int:
    return (x + y + y + z + 2) >> 2

func _a2(x: int, y: int) -> int:
    return (x + y + 1) >> 1

# Prédiction 4x4 (RFC 6386, 12.3) ; tr : adresse des 4 pixels au-dessus à droite.
func _pred4(dst: int, stride: int, mode: int, tr: int):
    top := dst - stride
    pp := __load8(top - 1)
    a0 := __load8(top)
    a1 := __load8(top + 1)
    a2 := __load8(top + 2)
    a3 := __load8(top + 3)
    a4 := __load8(tr)
    a5 := __load8(tr + 1)
    a6 := __load8(tr + 2)
    a7 := __load8(tr + 3)
    l0 := __load8(dst - 1)
    l1 := __load8(dst + stride - 1)
    l2 := __load8(dst + 2 * stride - 1)
    l3 := __load8(dst + 3 * stride - 1)
    b := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]       # b[r * 4 + c]
    if mode == 0:
        v := (a0 + a1 + a2 + a3 + l0 + l1 + l2 + l3 + 4) >> 3
        i := 0
        while i < 16:
            b[i] = v
            i += 1
    elif mode == 1:
        ls := [l0, l1, l2, l3]
        tv := [a0, a1, a2, a3]
        r := 0
        while r < 4:
            c := 0
            while c < 4:
                b[r * 4 + c] = _clip255(ls[r] + tv[c] - pp)
                c += 1
            r += 1
    elif mode == 2:
        vs := [_a3(pp, a0, a1), _a3(a0, a1, a2), _a3(a1, a2, a3), _a3(a2, a3, a4)]
        r2 := 0
        while r2 < 4:
            c2 := 0
            while c2 < 4:
                b[r2 * 4 + c2] = vs[c2]
                c2 += 1
            r2 += 1
    elif mode == 3:
        hs := [_a3(pp, l0, l1), _a3(l0, l1, l2), _a3(l1, l2, l3), _a3(l2, l3, l3)]
        r3 := 0
        while r3 < 4:
            c3 := 0
            while c3 < 4:
                b[r3 * 4 + c3] = hs[r3]
                c3 += 1
            r3 += 1
    else:
        # E[0..8] = L3 L2 L1 L0 P A0 A1 A2 A3 ; A[0..7]
        e := [l3, l2, l1, l0, pp, a0, a1, a2, a3]
        a := [a0, a1, a2, a3, a4, a5, a6, a7]
        if mode == 4:
            b[0] = _a3(a[0], a[1], a[2])
            b[1] = _a3(a[1], a[2], a[3])
            b[4] = b[1]
            b[2] = _a3(a[2], a[3], a[4])
            b[5] = b[2]
            b[8] = b[2]
            b[3] = _a3(a[3], a[4], a[5])
            b[6] = b[3]
            b[9] = b[3]
            b[12] = b[3]
            b[7] = _a3(a[4], a[5], a[6])
            b[10] = b[7]
            b[13] = b[7]
            b[11] = _a3(a[5], a[6], a[7])
            b[14] = b[11]
            b[15] = _a3(a[6], a[7], a[7])
        elif mode == 5:
            b[12] = _a3(e[0], e[1], e[2])
            b[13] = _a3(e[1], e[2], e[3])
            b[8] = b[13]
            b[14] = _a3(e[2], e[3], e[4])
            b[9] = b[14]
            b[4] = b[14]
            b[15] = _a3(e[3], e[4], e[5])
            b[10] = b[15]
            b[5] = b[15]
            b[0] = b[15]
            b[11] = _a3(e[4], e[5], e[6])
            b[6] = b[11]
            b[1] = b[11]
            b[7] = _a3(e[5], e[6], e[7])
            b[2] = b[7]
            b[3] = _a3(e[6], e[7], e[8])
        elif mode == 6:
            b[12] = _a3(e[1], e[2], e[3])
            b[8] = _a3(e[2], e[3], e[4])
            b[13] = _a3(e[3], e[4], e[5])
            b[4] = b[13]
            b[9] = _a2(e[4], e[5])
            b[0] = b[9]
            b[14] = _a3(e[4], e[5], e[6])
            b[5] = b[14]
            b[10] = _a2(e[5], e[6])
            b[1] = b[10]
            b[15] = _a3(e[5], e[6], e[7])
            b[6] = b[15]
            b[11] = _a2(e[6], e[7])
            b[2] = b[11]
            b[7] = _a3(e[6], e[7], e[8])
            b[3] = _a2(e[7], e[8])
        elif mode == 7:
            b[0] = _a2(a[0], a[1])
            b[4] = _a3(a[0], a[1], a[2])
            b[8] = _a2(a[1], a[2])
            b[1] = b[8]
            b[5] = _a3(a[1], a[2], a[3])
            b[12] = b[5]
            b[9] = _a2(a[2], a[3])
            b[2] = b[9]
            b[13] = _a3(a[2], a[3], a[4])
            b[6] = b[13]
            b[10] = _a2(a[3], a[4])
            b[3] = b[10]
            b[14] = _a3(a[3], a[4], a[5])
            b[7] = b[14]
            b[11] = _a3(a[4], a[5], a[6])
            b[15] = _a3(a[5], a[6], a[7])
        elif mode == 8:
            b[12] = _a2(e[0], e[1])
            b[13] = _a3(e[0], e[1], e[2])
            b[8] = _a2(e[1], e[2])
            b[14] = b[8]
            b[9] = _a3(e[1], e[2], e[3])
            b[15] = b[9]
            b[10] = _a2(e[2], e[3])
            b[4] = b[10]
            b[11] = _a3(e[2], e[3], e[4])
            b[5] = b[11]
            b[6] = _a2(e[3], e[4])
            b[0] = b[6]
            b[7] = _a3(e[3], e[4], e[5])
            b[1] = b[7]
            b[2] = _a3(e[4], e[5], e[6])
            b[3] = _a3(e[5], e[6], e[7])
        else:
            # HU : L[0..3] = l0..l3
            b[0] = _a2(l0, l1)
            b[1] = _a3(l0, l1, l2)
            b[2] = _a2(l1, l2)
            b[4] = b[2]
            b[3] = _a3(l1, l2, l3)
            b[5] = b[3]
            b[6] = _a2(l2, l3)
            b[8] = b[6]
            b[7] = _a3(l2, l3, l3)
            b[9] = b[7]
            b[10] = l3
            b[11] = l3
            b[12] = l3
            b[13] = l3
            b[14] = l3
            b[15] = l3
    r4 := 0
    while r4 < 4:
        c4 := 0
        while c4 < 4:
            __store8(dst + r4 * stride + c4, b[r4 * 4 + c4])
            c4 += 1
        r4 += 1

# --- filtre de boucle (RFC 6386, 15)

func _c8(v: int) -> int:
    if v < -128:
        return -128
    if v > 127:
        return 127
    return v

func _abs(v: int) -> int:
    if v < 0:
        return -v
    return v

# Ajustement commun ; p : adresse de q0, step : pas perpendiculaire au bord. Rend a.
func _common(p: int, step: int, outer: bool) -> int:
    p1 := __load8(p - 2 * step) - 128
    p0 := __load8(p - step) - 128
    q0 := __load8(p) - 128
    q1 := __load8(p + step) - 128
    a := 3 * (q0 - p0)
    if outer:
        a += _c8(p1 - q1)
    a = _c8(a)
    b := _c8(a + 3) >> 3
    a = _c8(a + 4) >> 3
    __store8(p, _c8(q0 - a) + 128)
    __store8(p - step, _c8(p0 + b) + 128)
    return a

func _simple_ok(p: int, step: int, e: int) -> bool:
    return _abs(__load8(p - step) - __load8(p)) * 2 + (_abs(__load8(p - 2 * step) - __load8(p + step)) >> 1) <= e

func _normal_ok(p: int, step: int, e: int, il: int) -> bool:
    if not _simple_ok(p, step, e):
        return false
    p3 := __load8(p - 4 * step)
    p2 := __load8(p - 3 * step)
    p1 := __load8(p - 2 * step)
    p0 := __load8(p - step)
    q0 := __load8(p)
    q1 := __load8(p + step)
    q2 := __load8(p + 2 * step)
    q3 := __load8(p + 3 * step)
    return _abs(p3 - p2) <= il and _abs(p2 - p1) <= il and _abs(p1 - p0) <= il and _abs(q3 - q2) <= il and _abs(q2 - q1) <= il and _abs(q1 - q0) <= il

func _hev(p: int, step: int, t: int) -> bool:
    return _abs(__load8(p - 2 * step) - __load8(p - step)) > t or _abs(__load8(p + step) - __load8(p)) > t

# Bord entre macroblocs : n segments à partir de p (q0 du premier), along : pas le long du bord.
func _mb_edge(p0: int, step: int, along: int, n: int, e: int, il: int, hv: int):
    i := 0
    while i < n:
        p := p0 + i * along
        if _normal_ok(p, step, e, il):
            if _hev(p, step, hv):
                _common(p, step, true)
            else:
                sp1 := __load8(p - 2 * step) - 128
                sp0 := __load8(p - step) - 128
                sq0 := __load8(p) - 128
                sq1 := __load8(p + step) - 128
                sp2 := __load8(p - 3 * step) - 128
                sq2 := __load8(p + 2 * step) - 128
                w := _c8(_c8(sp1 - sq1) + 3 * (sq0 - sp0))
                a := _c8((27 * w + 63) >> 7)
                __store8(p, _c8(sq0 - a) + 128)
                __store8(p - step, _c8(sp0 + a) + 128)
                a = _c8((18 * w + 63) >> 7)
                __store8(p + step, _c8(sq1 - a) + 128)
                __store8(p - 2 * step, _c8(sp1 + a) + 128)
                a = _c8((9 * w + 63) >> 7)
                __store8(p + 2 * step, _c8(sq2 - a) + 128)
                __store8(p - 3 * step, _c8(sp2 + a) + 128)
        i += 1

func _sub_edge(p0: int, step: int, along: int, n: int, e: int, il: int, hv: int):
    i := 0
    while i < n:
        p := p0 + i * along
        if _normal_ok(p, step, e, il):
            h := _hev(p, step, hv)
            sp1 := __load8(p - 2 * step) - 128
            sq1 := __load8(p + step) - 128
            a := (_common(p, step, h) + 1) >> 1
            if not h:
                __store8(p + step, _c8(sq1 - a) + 128)
                __store8(p - 2 * step, _c8(sp1 + a) + 128)
        i += 1

func _simple_edge(p0: int, step: int, along: int, n: int, e: int):
    i := 0
    while i < n:
        p := p0 + i * along
        if _simple_ok(p, step, e):
            _common(p, step, true)
        i += 1

# Image clé VP8 (fichier sans en-tête RIFF) : pixels ARGB opaques.
func vp8(a: int, n: int) -> Raster:
    if n < 10:
        _err("trame VP8 trop courte")
    bits := _le24(a)
    if (bits & 1) != 0:
        _err("trame VP8 non clé")
    part0 := (bits >> 5) & 0x7FFFF
    if __load8(a + 3) != 0x9D or __load8(a + 4) != 0x01 or __load8(a + 5) != 0x2A:
        _err("code de départ VP8 absent")
    w := _le16(a + 6) & 0x3FFF
    h := _le16(a + 8) & 0x3FFF
    if w == 0 or h == 0:
        _err("dimensions VP8 nulles")
    p := a + 10
    if 10 + part0 > n:
        _err("partition VP8 tronquée")
    d := _bool(p, part0)
    _bget(d, 128)              # espace de couleurs
    _bget(d, 128)              # type d'écrêtage
    seg_on := _bget(d, 128) == 1
    seg_map := false
    seg_abs := false
    seg_q := [0, 0, 0, 0]
    seg_lf := [0, 0, 0, 0]
    seg_p := [255, 255, 255]
    if seg_on:
        seg_map = _bget(d, 128) == 1
        if _bget(d, 128) == 1:
            seg_abs = _bget(d, 128) == 1
            i := 0
            while i < 4:
                seg_q[i] = _bopt(d, 7)
                i += 1
            i = 0
            while i < 4:
                seg_lf[i] = _bopt(d, 6)
                i += 1
        if seg_map:
            k := 0
            while k < 3:
                if _bget(d, 128) == 1:
                    seg_p[k] = _blit(d, 8)
                k += 1
    simple := _bget(d, 128) == 1
    level := _blit(d, 6)
    sharp := _blit(d, 3)
    ref_d0 := 0
    mode_d0 := 0
    if _bget(d, 128) == 1:
        if _bget(d, 128) == 1:
            j := 0
            while j < 4:
                if _bget(d, 128) == 1:
                    vref := _bsigned(d, 6)
                    if j == 0:
                        ref_d0 = vref
                j += 1
            j = 0
            while j < 4:
                if _bget(d, 128) == 1:
                    vmode := _bsigned(d, 6)
                    if j == 0:
                        mode_d0 = vmode
                j += 1
    nparts := 1 << _blit(d, 2)
    # partitions des coefficients
    pp := p + part0
    pend := a + n
    pdata := pp + 3 * (nparts - 1)
    if pdata > pend:
        _err("partitions VP8 tronquées")
    toks: list[_Bool] := []
    pk := 0
    while pk < nparts:
        sz := pend - pdata
        if pk < nparts - 1:
            sz = _le24(pp + 3 * pk)
        if pdata + sz > pend:
            sz = pend - pdata
        append(toks, _bool(pdata, sz))
        pdata += sz
        pk += 1
    base_q := _blit(d, 7)
    dq_y1dc := _bopt(d, 4)
    dq_y2dc := _bopt(d, 4)
    dq_y2ac := _bopt(d, 4)
    dq_uvdc := _bopt(d, 4)
    dq_uvac := _bopt(d, 4)
    _bget(d, 128)              # refresh_entropy_probs
    v := _Vp8()
    v.probs = []
    pi := 0
    while pi < 1056:
        pv := tab.VP8_COEF_DEF[pi]
        if _bget(d, tab.VP8_COEF_UPD[pi]) == 1:
            pv = _blit(d, 8)
        append(v.probs, pv)
        pi += 1
    skip_on := _bget(d, 128) == 1
    skip_p := 0
    if skip_on:
        skip_p = _blit(d, 8)
    # quantification par segment
    v.q = []
    s := 0
    while s < 4:
        qi := base_q
        if seg_on:
            qi = seg_q[s]
            if not seg_abs:
                qi += base_q
        append(v.q, tab.VP8_DC_Q[_qclip(qi + dq_y1dc, 127)])
        append(v.q, tab.VP8_AC_Q[_qclip(qi, 127)])
        append(v.q, tab.VP8_DC_Q[_qclip(qi + dq_y2dc, 127)] * 2)
        y2ac := (tab.VP8_AC_Q[_qclip(qi + dq_y2ac, 127)] * 101581) >> 16
        if y2ac < 8:
            y2ac = 8
        append(v.q, y2ac)
        append(v.q, tab.VP8_DC_Q[_qclip(qi + dq_uvdc, 117)])
        append(v.q, tab.VP8_AC_Q[_qclip(qi + dq_uvac, 127)])
        s += 1
    # filtre par segment et selon B_PRED : niveau, limite intérieure, seuil de variation
    flt: list[int] := []
    s2 := 0
    while s2 < 4:
        i4 := 0
        while i4 < 2:
            lv := level
            if seg_on:
                lv = seg_lf[s2]
                if not seg_abs:
                    lv += level
            lv += ref_d0
            if i4 == 1:
                lv += mode_d0
            if lv < 0:
                lv = 0
            if lv > 63:
                lv = 63
            il := lv
            if sharp > 0:
                if sharp > 4:
                    il = il >> 2
                else:
                    il = il >> 1
                if il > 9 - sharp:
                    il = 9 - sharp
            if il < 1:
                il = 1
            hv := 0
            if lv >= 40:
                hv = 2
            elif lv >= 15:
                hv = 1
            append(flt, lv)
            append(flt, il)
            append(flt, hv)
            i4 += 1
        s2 += 1
    v.w = w
    v.h = h
    v.mbw = (w + 15) >> 4
    v.mbh = (h + 15) >> 4
    _planes(v)
    v.coef = []
    ci := 0
    while ci < 400:
        append(v.coef, 0)
        ci += 1
    v.tmp = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    # contextes : modes 4x4 au-dessus (4 par colonne de macroblocs), coefficients non nuls
    intra_t: list[int] := []
    nz_t: list[int] := []          # par colonne : 4 Y, 2 U, 2 V, Y2
    mbinfo: list[int] := []        # par macrobloc : segment | B_PRED << 2 | intérieur << 3
    k2 := 0
    while k2 < v.mbw * 9:
        append(nz_t, 0)
        k2 += 1
    k2 = 0
    while k2 < v.mbw * 4:
        append(intra_t, 0)
        k2 += 1
    bmodes := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    mby := 0
    while mby < v.mbh:
        intra_l := [0, 0, 0, 0]
        nz_l := [0, 0, 0, 0, 0, 0, 0, 0, 0]
        tok := toks[mby % nparts]
        mbx := 0
        while mbx < v.mbw:
            seg := 0
            if seg_map:
                if _bget(d, seg_p[0]) == 0:
                    seg = _bget(d, seg_p[1])
                else:
                    seg = 2 + _bget(d, seg_p[2])
            skip := false
            if skip_on:
                skip = _bget(d, skip_p) == 1
            is4 := _bget(d, 145) == 0
            ymode := 0
            if not is4:
                if _bget(d, 156) == 1:
                    if _bget(d, 128) == 1:
                        ymode = 3
                    else:
                        ymode = 2
                elif _bget(d, 163) == 1:
                    ymode = 1
                # contexte des modes 4x4 : DC → B_DC, V → B_VE, H → B_HE, TM → B_TM
                bm := 0
                if ymode == 1:
                    bm = 2
                elif ymode == 2:
                    bm = 3
                elif ymode == 3:
                    bm = 1
                q4 := 0
                while q4 < 4:
                    intra_t[mbx * 4 + q4] = bm
                    intra_l[q4] = bm
                    q4 += 1
            else:
                by := 0
                while by < 4:
                    lm := intra_l[by]
                    bx := 0
                    while bx < 4:
                        tm := intra_t[mbx * 4 + bx]
                        base := (tm * 10 + lm) * 9
                        ti := 0
                        while true:
                            ti = _BMODE_TREE[ti + _bget(d, tab.VP8_KF_BMODE[base + (ti >> 1)])]
                            if ti <= 0:
                                break
                        lm = -ti
                        intra_t[mbx * 4 + bx] = lm
                        bmodes[by * 4 + bx] = lm
                        bx += 1
                    intra_l[by] = lm
                    by += 1
            uvmode := 0
            if _bget(d, 142) == 1:
                if _bget(d, 114) == 0:
                    uvmode = 1
                elif _bget(d, 183) == 1:
                    uvmode = 3
                else:
                    uvmode = 2
            # coefficients
            nonzero := false
            if not skip:
                nonzero = _residuals(v, tok, seg, is4, mbx, nz_t, nz_l)
            else:
                z := 0
                while z < 8:
                    nz_t[mbx * 9 + z] = 0
                    nz_l[z] = 0
                    z += 1
                if not is4:
                    nz_t[mbx * 9 + 8] = 0
                    nz_l[8] = 0
                _zero(v)
            _reconstruct(v, mbx, mby, is4, ymode, bmodes, uvmode)
            info := seg
            if is4:
                info = info | 4
            if is4 or nonzero:
                info = info | 8
            append(mbinfo, info)
            mbx += 1
        mby += 1
    if level > 0:
        _loop_filter(v, simple, sharp, flt, mbinfo)
    r := rs.create(w, h)
    _to_rgb(v, r)
    _free(v.py - 0, v.ysize)
    _free(v.pu, v.csize)
    _free(v.pv, v.csize)
    return r

func _qclip(q: int, m: int) -> int:
    if q < 0:
        return 0
    if q > m:
        return m
    return q

func _planes(v: _Vp8):
    yw := v.mbw * 16
    yh := v.mbh * 16
    v.ys = yw + 1 + 4 + 3
    v.ysize = v.ys * (yh + 1)
    v.py = _mem(v.ysize)
    cw := v.mbw * 8
    ch := v.mbh * 8
    v.cs = cw + 1 + 7
    v.csize = v.cs * (ch + 1)
    v.pu = _mem(v.csize)
    v.pv = _mem(v.csize)
    # bordures : ligne du haut à 127, colonne de gauche à 129 (coin à 127)
    _set(v.py, 127, v.ys)
    _set(v.pu, 127, v.cs)
    _set(v.pv, 127, v.cs)
    y := 0
    while y < yh:
        __store8(v.py + (y + 1) * v.ys, 129)
        y += 1
    y = 0
    while y < ch:
        __store8(v.pu + (y + 1) * v.cs, 129)
        __store8(v.pv + (y + 1) * v.cs, 129)
        y += 1

func _set(a: int, val: int, n: int):
    i := 0
    while i < n:
        __store8(a + i, val)
        i += 1

func _zero(v: _Vp8):
    i := 0
    while i < 400:
        v.coef[i] = 0
        i += 1

# Coefficients d'un macrobloc ; rend vrai si l'un d'eux est non nul.
func _residuals(v: _Vp8, tok: _Bool, seg: int, is4: bool, mbx: int, nz_t: list[int], nz_l: list[int]) -> bool:
    _zero(v)
    qb := seg * 6
    first := 0
    ytype := 3
    if not is4:
        ctx := nz_t[mbx * 9 + 8] + nz_l[8]
        nz := _coeffs(v, tok, 1, ctx, v.q[qb + 2], v.q[qb + 3], 0, 384)
        f := 0
        if nz > 0:
            f = 1
        nz_t[mbx * 9 + 8] = f
        nz_l[8] = f
        _iwht(v)
        first = 1
        ytype = 0
    y := 0
    while y < 4:
        l := nz_l[y]
        x := 0
        while x < 4:
            ctx2 := l + nz_t[mbx * 9 + x]
            nz2 := _coeffs(v, tok, ytype, ctx2, v.q[qb], v.q[qb + 1], first, (y * 4 + x) * 16)
            l = 0
            if nz2 > first:
                l = 1
            nz_t[mbx * 9 + x] = l
            x += 1
        nz_l[y] = l
        y += 1
    ch := 0
    while ch < 2:
        y2 := 0
        while y2 < 2:
            l2 := nz_l[4 + ch * 2 + y2]
            x2 := 0
            while x2 < 2:
                ctx3 := l2 + nz_t[mbx * 9 + 4 + ch * 2 + x2]
                nz3 := _coeffs(v, tok, 2, ctx3, v.q[qb + 4], v.q[qb + 5], 0, 256 + ch * 64 + (y2 * 2 + x2) * 16)
                l2 = 0
                if nz3 > 0:
                    l2 = 1
                nz_t[mbx * 9 + 4 + ch * 2 + x2] = l2
                x2 += 1
            nz_l[4 + ch * 2 + y2] = l2
            y2 += 1
        ch += 1
    i := 0
    while i < 384:
        if v.coef[i] != 0:
            return true
        i += 1
    return false

func _reconstruct(v: _Vp8, mbx: int, mby: int, is4: bool, ymode: int, bmodes: list[int], uvmode: int):
    x0 := mbx * 16
    y0 := mby * 16
    ys := v.ys
    if mby > 0 and mbx == v.mbw - 1:
        # au-dessus à droite du dernier macrobloc de la ligne : dernier pixel de la ligne du dessus répété
        rp := _yat(v, x0 + 15, y0 - 1)
        __store8(rp + 1, __load8(rp))
        __store8(rp + 2, __load8(rp))
        __store8(rp + 3, __load8(rp))
        __store8(rp + 4, __load8(rp))
    dst := _yat(v, x0, y0)
    if not is4:
        _pred_block(dst, ys, 16, ymode, mby > 0, mbx > 0)
        b := 0
        while b < 16:
            _idct_add(v, b * 16, dst + (b >> 2) * 4 * ys + (b & 3) * 4, ys)
            b += 1
    else:
        mbtr := _yat(v, x0 + 16, y0 - 1)
        b2 := 0
        while b2 < 16:
            bx := b2 & 3
            by := b2 >> 2
            bd := dst + by * 4 * ys + bx * 4
            tr := bd - ys + 4
            if bx == 3 and by > 0:
                tr = mbtr
            _pred4(bd, ys, bmodes[b2], tr)
            _idct_add(v, b2 * 16, bd, ys)
            b2 += 1
    cs := v.cs
    du := _cat(v, v.pu, mbx * 8, mby * 8)
    dv := _cat(v, v.pv, mbx * 8, mby * 8)
    _pred_block(du, cs, 8, uvmode, mby > 0, mbx > 0)
    _pred_block(dv, cs, 8, uvmode, mby > 0, mbx > 0)
    c := 0
    while c < 4:
        off := (c >> 1) * 4 * cs + (c & 1) * 4
        _idct_add(v, 256 + c * 16, du + off, cs)
        _idct_add(v, 320 + c * 16, dv + off, cs)
        c += 1

func _loop_filter(v: _Vp8, simple: bool, sharp: int, flt: list[int], mbinfo: list[int]):
    ys := v.ys
    cs := v.cs
    mby := 0
    while mby < v.mbh:
        mbx := 0
        while mbx < v.mbw:
            info := mbinfo[mby * v.mbw + mbx]
            fi := ((info & 3) * 2 + ((info >> 2) & 1)) * 3
            lv := flt[fi]
            if lv > 0:
                il := flt[fi + 1]
                hv := flt[fi + 2]
                inner := (info & 8) != 0
                mbe := (lv + 2) * 2 + il
                sbe := lv * 2 + il
                yp := _yat(v, mbx * 16, mby * 16)
                up := _cat(v, v.pu, mbx * 8, mby * 8)
                vp := _cat(v, v.pv, mbx * 8, mby * 8)
                if simple:
                    if mbx > 0:
                        _simple_edge(yp, 1, ys, 16, mbe)
                    if inner:
                        _simple_edge(yp + 4, 1, ys, 16, sbe)
                        _simple_edge(yp + 8, 1, ys, 16, sbe)
                        _simple_edge(yp + 12, 1, ys, 16, sbe)
                    if mby > 0:
                        _simple_edge(yp, ys, 1, 16, mbe)
                    if inner:
                        _simple_edge(yp + 4 * ys, ys, 1, 16, sbe)
                        _simple_edge(yp + 8 * ys, ys, 1, 16, sbe)
                        _simple_edge(yp + 12 * ys, ys, 1, 16, sbe)
                else:
                    if mbx > 0:
                        _mb_edge(yp, 1, ys, 16, mbe, il, hv)
                        _mb_edge(up, 1, cs, 8, mbe, il, hv)
                        _mb_edge(vp, 1, cs, 8, mbe, il, hv)
                    if inner:
                        _sub_edge(yp + 4, 1, ys, 16, sbe, il, hv)
                        _sub_edge(yp + 8, 1, ys, 16, sbe, il, hv)
                        _sub_edge(yp + 12, 1, ys, 16, sbe, il, hv)
                        _sub_edge(up + 4, 1, cs, 8, sbe, il, hv)
                        _sub_edge(vp + 4, 1, cs, 8, sbe, il, hv)
                    if mby > 0:
                        _mb_edge(yp, ys, 1, 16, mbe, il, hv)
                        _mb_edge(up, cs, 1, 8, mbe, il, hv)
                        _mb_edge(vp, cs, 1, 8, mbe, il, hv)
                    if inner:
                        _sub_edge(yp + 4 * ys, ys, 1, 16, sbe, il, hv)
                        _sub_edge(yp + 8 * ys, ys, 1, 16, sbe, il, hv)
                        _sub_edge(yp + 12 * ys, ys, 1, 16, sbe, il, hv)
                        _sub_edge(up + 4 * cs, cs, 1, 8, sbe, il, hv)
                        _sub_edge(vp + 4 * cs, cs, 1, 8, sbe, il, hv)
            mbx += 1
        mby += 1

# --- YUV → ARGB (conversion et suréchantillonnage de libwebp, pour des couleurs identiques)

func _mhi(v: int, c: int) -> int:
    return (v * c) >> 8

func _clip8(v: int) -> int:
    if (v & ~16383) == 0:
        return v >> 6
    if v < 0:
        return 0
    return 255

func _yuv(y: int, u: int, v: int) -> int:
    r := _clip8(_mhi(y, 19077) + _mhi(v, 26149) - 14234)
    g := _clip8(_mhi(y, 19077) - _mhi(u, 6419) - _mhi(v, 13320) + 8708)
    b := _clip8(_mhi(y, 19077) + _mhi(u, 33050) - 17685)
    return 0xFF000000 | (r << 16) | (g << 8) | b

# Chrominance suréchantillonnée d'une ligne : near (ligne de chroma la plus proche), far (l'autre).
func _up_row(near: int, far: int, w: int, out: list[int]):
    out[0] = (3 * __load8(near) + __load8(far) + 2) >> 2
    last := (w - 1) >> 1
    x := 1
    while x <= last:
        n0 := __load8(near + x - 1)
        n1 := __load8(near + x)
        f0 := __load8(far + x - 1)
        f1 := __load8(far + x)
        avg := n0 + n1 + f0 + f1 + 8
        d12 := (avg + 2 * (n1 + f0)) >> 3
        d03 := (avg + 2 * (n0 + f1)) >> 3
        out[2 * x - 1] = (d12 + n0) >> 1
        out[2 * x] = (d03 + n1) >> 1
        x += 1
    if (w & 1) == 0:
        out[w - 1] = (3 * __load8(near + last) + __load8(far + last) + 2) >> 2

func _to_rgb(v: _Vp8, r: Raster):
    w := v.w
    h := v.h
    uu: list[int] := []
    vv: list[int] := []
    i := 0
    while i < w + 2:
        append(uu, 0)
        append(vv, 0)
        i += 1
    ch := (h + 1) >> 1
    y := 0
    while y < h:
        near := 0
        far := 0
        if y == 0:
            near = 0
            far = 0
        elif (y & 1) == 1:
            near = y >> 1
            far = near + 1
            if far >= ch:
                far = near
        else:
            near = y >> 1
            far = near - 1
        _up_row(_cat(v, v.pu, 0, near), _cat(v, v.pu, 0, far), w, uu)
        _up_row(_cat(v, v.pv, 0, near), _cat(v, v.pv, 0, far), w, vv)
        yr := _yat(v, 0, y)
        o := r.addr + y * w * 4
        x := 0
        while x < w:
            __store32(o + x * 4, _yuv(__load8(yr + x), uu[x], vv[x]))
            x += 1
        y += 1

# =============================================================================================== alpha

# Canal alpha (chunk ALPH) appliqué aux pixels de r.
func _alpha(a: int, n: int, r: Raster):
    if n < 1:
        return
    hdr := __load8(a)
    comp := hdr & 3
    filt := (hdr >> 2) & 3
    w := r.width
    h := r.height
    al := _mem(w * h)
    if comp == 0:
        m := n - 1
        if m > w * h:
            m = w * h
        __copy(al, a + 1, m)
    elif comp == 1:
        b := _bits(a + 1, n - 1)
        pix := _vp8l_stream(b, w, h)
        i := 0
        while i < w * h:
            __store8(al + i, (__load32(pix + i * 4) >> 8) & 255)
            i += 1
        _free(pix, w * h * 4)
    else:
        _free(al, w * h)
        _err("compression alpha inconnue")
    if filt != 0:
        y := 0
        while y < h:
            x := 0
            while x < w:
                p := al + y * w + x
                pred := 0
                if x == 0 and y == 0:
                    pred = 0
                elif y == 0:
                    pred = __load8(p - 1)
                elif x == 0:
                    pred = __load8(p - w)
                elif filt == 1:
                    pred = __load8(p - 1)
                elif filt == 2:
                    pred = __load8(p - w)
                else:
                    pred = _clip255(__load8(p - 1) + __load8(p - w) - __load8(p - w - 1))
                __store8(p, (__load8(p) + pred) & 255)
                x += 1
            y += 1
    j := 0
    while j < w * h:
        q := r.addr + j * 4
        __store32(q, (__load32(q) & 0x00FFFFFF) | (__load8(al + j) << 24))
        j += 1
    _free(al, w * h)

# =============================================================================================== conteneur

# Image d'une trame : chunks ALPH éventuel puis VP8 ou VP8L dans [a, end).
func _frame_image(a: int, end: int) -> Raster:
    pos := a
    alph := 0
    alen := 0
    while pos + 8 <= end:
        sz := _le32(pos + 4)
        data := pos + 8
        if data + sz > end:
            sz = end - data
        if _fourcc(pos, "ALPH"):
            alph = data
            alen = sz
        elif _fourcc(pos, "VP8 "):
            r := vp8(data, sz)
            if alph != 0:
                _alpha(alph, alen, r)
            return r
        elif _fourcc(pos, "VP8L"):
            return vp8l(data, sz)
        pos = data + sz + (sz & 1)
    _err("aucune image dans le fichier")
    return rs.create(1, 1)

func _blend(dst: int, src: int) -> int:
    sa := (src >> 24) & 255
    if sa == 255:
        return src
    if sa == 0:
        return dst
    da := (dst >> 24) & 255
    dfa := da * (255 - sa) // 255
    oa := sa + dfa
    if oa == 0:
        return 0
    out := oa << 24
    sh := 0
    while sh < 24:
        c := ((((src >> sh) & 255) * sa + ((dst >> sh) & 255) * dfa) // oa) & 255
        out = out | (c << sh)
        sh += 8
    return out

func decode(a: int, n: int) -> WebpFrames:
    res := WebpFrames()
    if n < 20 or not _fourcc(a, "RIFF") or not _fourcc(a + 8, "WEBP"):
        _err("en-tête RIFF absent")
    end := a + n
    rsz := _le32(a + 4) + 8
    if rsz < n:
        end = a + rsz
    pos := a + 12
    if not _fourcc(pos, "VP8X"):
        append(res.frames, _frame_image(pos, end))
        append(res.delays, 0)
        return res
    vsz := _le32(pos + 4)
    flags := __load8(pos + 8)
    cw := _le24(pos + 12) + 1
    chh := _le24(pos + 15) + 1
    first := pos + 8 + vsz + (vsz & 1)
    if (flags & 2) == 0:
        append(res.frames, _frame_image(first, end))
        append(res.delays, 0)
        return res
    # animation : chaque trame est composée sur la toile
    canvas := rs.create(cw, chh)
    p := first
    while p + 8 <= end and len(res.frames) < MAX_FRAMES:
        sz := _le32(p + 4)
        data := p + 8
        if data + sz > end:
            sz = end - data
        if _fourcc(p, "ANMF") and sz >= 16:
            fx := _le24(data) * 2
            fy := _le24(data + 3) * 2
            fl := __load8(data + 15)
            dur := _le24(data + 12)
            img := _frame_image(data + 16, data + sz)
            blend := (fl & 2) == 0
            yy := 0
            while yy < img.height:
                cy := fy + yy
                if cy < chh:
                    xx := 0
                    while xx < img.width:
                        cx := fx + xx
                        if cx < cw:
                            q := canvas.addr + (cy * cw + cx) * 4
                            s := __load32(img.addr + (yy * img.width + xx) * 4)
                            if blend:
                                __store32(q, _blend(__load32(q), s))
                            else:
                                __store32(q, s)
                        xx += 1
                yy += 1
            append(res.frames, rs.copy(canvas))
            if dur <= 10:
                dur = 100
            append(res.delays, dur)
            if (fl & 1) != 0:
                # effacement : rectangle de la trame rendu transparent
                y2 := fy
                while y2 < fy + img.height and y2 < chh:
                    x2 := fx
                    while x2 < fx + img.width and x2 < cw:
                        __store32(canvas.addr + (y2 * cw + x2) * 4, 0)
                        x2 += 1
                    y2 += 1
            rs.free(img)
        p = data + sz + (sz & 1)
    rs.free(canvas)
    if len(res.frames) == 0:
        _err("animation sans trame")
    return res

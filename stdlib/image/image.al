# alex: native
# alex: intrinsics
# NOVA (édition bureau) — décodeurs d'images : PNG (toutes profondeurs, palette, transparence, entrelacé),
# JPEG (de base et progressif, sous-échantillonnage, niveaux de gris, CMJN Adobe), GIF (animé : disposition,
# transparence, entrelacé), BMP (1 à 32 bits), ICO (BMP ou PNG intégré) et WebP (avec et sans perte, alpha,
# animation : voir webp.al).
#
#   a := image.decode(octets)     -> Anim : a.frames (list[Raster]), a.delays (ms par image)
#   image.kind(octets)            -> "png" | "jpeg" | "gif" | "bmp" | "ico" | "webp" | ""
#
# Erreurs : ImageError (format inconnu ou données invalides), InflateError (PNG).
use image.inflate as inf
from image.inflate use Buf
use image.raster as rs
from image.raster use Raster
use image.webp as wp
from core use len
from collections use append

const MAX_FRAMES := 400

class Anim:
    frames: list[Raster] := []
    delays: list[int] := []

    func init():
        self.frames = []
        self.delays = []

func _single(r: Raster) -> Anim:
    a := Anim()
    append(a.frames, r)
    append(a.delays, 0)
    return a

func _err(msg: str):
    raise("ImageError", msg)

func _be16(a: int) -> int:
    return (__load8(a) << 8) | __load8(a + 1)

func _be32(a: int) -> int:
    return (__load8(a) << 24) | (__load8(a + 1) << 16) | (__load8(a + 2) << 8) | __load8(a + 3)

func _le16(a: int) -> int:
    return __load8(a) | (__load8(a + 1) << 8)

func _le32(a: int) -> int:
    return __load8(a) | (__load8(a + 1) << 8) | (__load8(a + 2) << 16) | (__load8(a + 3) << 24)

func _s32(v: int) -> int:
    v = v & 0xFFFFFFFF
    if v >= 2147483648:
        return v - 4294967296
    return v

func kind(data: str) -> str:
    n := inf.str_len(data)
    a := inf.str_addr(data)
    if n >= 8 and __load8(a) == 137 and __load8(a + 1) == 80 and __load8(a + 2) == 78 and __load8(a + 3) == 71:
        return "png"
    if n >= 3 and __load8(a) == 255 and __load8(a + 1) == 216 and __load8(a + 2) == 255:
        return "jpeg"
    if n >= 6 and __load8(a) == 71 and __load8(a + 1) == 73 and __load8(a + 2) == 70 and __load8(a + 3) == 56:
        return "gif"
    if n >= 26 and __load8(a) == 66 and __load8(a + 1) == 77:
        return "bmp"
    if n >= 6 and _le16(a) == 0 and (_le16(a + 2) == 1 or _le16(a + 2) == 2) and _le16(a + 4) > 0:
        return "ico"
    if n >= 12 and __load8(a) == 82 and __load8(a + 1) == 73 and __load8(a + 8) == 87 and __load8(a + 9) == 69:
        return "webp"
    return ""

func decode(data: str) -> Anim:
    k := kind(data)
    a := inf.str_addr(data)
    n := inf.str_len(data)
    if k == "png":
        return _single(png(a, n))
    if k == "jpeg":
        return mjpeg(a, n)
    if k == "gif":
        return gif(a, n)
    if k == "bmp":
        return _single(bmp(a + 14, n - 14, a, n, false))
    if k == "ico":
        return _single(ico(a, n))
    if k == "webp":
        f := wp.decode(a, n)
        an := Anim()
        an.frames = f.frames
        an.delays = f.delays
        return an
    _err("format d'image inconnu")
    return Anim()

# =============================================================================================== Motion-JPEG

# JPEG, ou flux Motion-JPEG (images JPEG mises bout à bout) : une image par JPEG, 25 images/s (40 ms).
func mjpeg(a: int, n: int) -> Anim:
    starts: list[int] := [0]
    # début d'une image suivante : FF D9 (fin) suivi de FF D8 FF (début)
    i := 2
    while i + 4 < n:
        if __load8(a + i) == 255 and __load8(a + i + 1) == 217 and __load8(a + i + 2) == 255 and __load8(a + i + 3) == 216 and __load8(a + i + 4) == 255:
            append(starts, i + 2)
            i += 5
        else:
            i += 1
    if len(starts) == 1:
        return _single(jpeg(a, n))
    an := Anim()
    k := 0
    while k < len(starts) and len(an.frames) < MAX_FRAMES:
        s := starts[k]
        e := n
        if k + 1 < len(starts):
            e = starts[k + 1]
        try:
            append(an.frames, jpeg(a + s, e - s))
            append(an.delays, 40)
        catch err:
            if len(an.frames) == 0:
                raise(err.type, err.message)
        k += 1
    return an

# =============================================================================================== PNG

func _paeth(a: int, b: int, c: int) -> int:
    p := a + b - c
    pa := p - a
    if pa < 0:
        pa = -pa
    pb := p - b
    if pb < 0:
        pb = -pb
    pc := p - c
    if pc < 0:
        pc = -pc
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c

# Défait le filtre de la ligne cur (rowlen octets) avec la précédente prev (0 : aucune).
func _unfilter(ft: int, cur: int, prev: int, rowlen: int, bpp: int):
    i := 0
    if ft == 0:
        return
    if ft == 1:
        i = bpp
        while i < rowlen:
            __store8(cur + i, (__load8(cur + i) + __load8(cur + i - bpp)) & 255)
            i += 1
    elif ft == 2:
        if prev == 0:
            return
        while i < rowlen:
            __store8(cur + i, (__load8(cur + i) + __load8(prev + i)) & 255)
            i += 1
    elif ft == 3:
        while i < rowlen:
            left := 0
            if i >= bpp:
                left = __load8(cur + i - bpp)
            up := 0
            if prev != 0:
                up = __load8(prev + i)
            __store8(cur + i, (__load8(cur + i) + ((left + up) >> 1)) & 255)
            i += 1
    elif ft == 4:
        while i < rowlen:
            left := 0
            ul := 0
            up := 0
            if i >= bpp:
                left = __load8(cur + i - bpp)
            if prev != 0:
                up = __load8(prev + i)
                if i >= bpp:
                    ul = __load8(prev + i - bpp)
            __store8(cur + i, (__load8(cur + i) + _paeth(left, up, ul)) & 255)
            i += 1
    else:
        _err("PNG : filtre invalide")

class _Png:
    w: int := 0
    h: int := 0
    depth: int := 0
    ctype: int := 0
    chans: int := 1
    pal: int := 0           # palette ARGB (256 entrées, mémoire brute)
    trns_g: int := -1
    trns_r: int := -1
    trns_gg: int := -1
    trns_b: int := -1

# Convertit la ligne défiltrée row (largeur pw) en pixels ARGB écrits à x0 + k * dx sur la ligne y.
func _png_row(p: _Png, r: Raster, row: int, pw: int, y: int, x0: int, dx: int):
    d := p.depth
    ct := p.ctype
    dst := r.addr + y * r.width * 4
    x := 0
    while x < pw:
        c := 0
        if ct == 6:
            if d == 8:
                q := row + x * 4
                c = (__load8(q + 3) << 24) | (__load8(q) << 16) | (__load8(q + 1) << 8) | __load8(q + 2)
            else:
                q := row + x * 8
                c = (__load8(q + 6) << 24) | (__load8(q) << 16) | (__load8(q + 2) << 8) | __load8(q + 4)
        elif ct == 2:
            rr := 0
            gg := 0
            bb := 0
            a := 255
            if d == 8:
                q := row + x * 3
                rr = __load8(q)
                gg = __load8(q + 1)
                bb = __load8(q + 2)
                if rr == p.trns_r and gg == p.trns_gg and bb == p.trns_b:
                    a = 0
            else:
                q := row + x * 6
                if _be16(q) == p.trns_r and _be16(q + 2) == p.trns_gg and _be16(q + 4) == p.trns_b:
                    a = 0
                rr = __load8(q)
                gg = __load8(q + 2)
                bb = __load8(q + 4)
            c = (a << 24) | (rr << 16) | (gg << 8) | bb
        elif ct == 4:
            g := 0
            a := 0
            if d == 8:
                g = __load8(row + x * 2)
                a = __load8(row + x * 2 + 1)
            else:
                g = __load8(row + x * 4)
                a = __load8(row + x * 4 + 2)
            c = (a << 24) | (g << 16) | (g << 8) | g
        elif ct == 0:
            g := 0
            raw := 0
            if d == 16:
                raw = _be16(row + x * 2)
                g = raw >> 8
            elif d == 8:
                raw = __load8(row + x)
                g = raw
            else:
                per := 8 // d
                byte := __load8(row + x // per)
                sh := 8 - d - (x % per) * d
                raw = (byte >> sh) & ((1 << d) - 1)
                g = raw * 255 // ((1 << d) - 1)
            a := 255
            if raw == p.trns_g:
                a = 0
            c = (a << 24) | (g << 16) | (g << 8) | g
        else:
            idx := 0
            if d == 8:
                idx = __load8(row + x)
            else:
                per := 8 // d
                byte := __load8(row + x // per)
                sh := 8 - d - (x % per) * d
                idx = (byte >> sh) & ((1 << d) - 1)
            c = __load32(p.pal + idx * 4)
        __store32(dst + (x0 + x * dx) * 4, c)
        x += 1

func png(a: int, n: int) -> Raster:
    p := _Png()
    idat := Buf()
    pos := 8
    seen_ihdr := false
    while pos + 8 <= n:
        ln := _be32(a + pos)
        typ := _be32(a + pos + 4)
        body := a + pos + 8
        if pos + 12 + ln > n:
            if typ == 0x49444154 and ln > 0:
                ln = n - pos - 8           # IDAT tronqué : on prend ce qui est là
                if ln < 0:
                    break
            else:
                break
        if typ == 0x49484452:              # IHDR
            p.w = _be32(body)
            p.h = _be32(body + 4)
            p.depth = __load8(body + 8)
            p.ctype = __load8(body + 9)
            if __load8(body + 12) != 0:
                p.chans = -1               # entrelacé : marqué ci-dessous
            seen_ihdr = true
        elif typ == 0x504C5445:            # PLTE
            if p.pal == 0:
                p.pal = _mem(1024)
                i := 0
                while i < 256:
                    __store32(p.pal + i * 4, 0xFF000000)
                    i += 1
            i := 0
            while i < 256 and i * 3 + 2 < ln:
                q := body + i * 3
                __store32(p.pal + i * 4, 0xFF000000 | (__load8(q) << 16) | (__load8(q + 1) << 8) | __load8(q + 2))
                i += 1
        elif typ == 0x74524E53:            # tRNS
            if p.ctype == 3 and p.pal != 0:
                i := 0
                while i < ln and i < 256:
                    c := __load32(p.pal + i * 4)
                    __store32(p.pal + i * 4, (c & 0xFFFFFF) | (__load8(body + i) << 24))
                    i += 1
            elif p.ctype == 0 and ln >= 2:
                p.trns_g = _be16(body)
            elif p.ctype == 2 and ln >= 6:
                p.trns_r = _be16(body)
                p.trns_gg = _be16(body + 2)
                p.trns_b = _be16(body + 4)
        elif typ == 0x49444154:            # IDAT
            idat.reserve(ln)
            __copy(idat.addr + idat.n, body, ln)
            idat.n += ln
        elif typ == 0x49454E44:            # IEND
            break
        pos += 12 + ln
    if not seen_ihdr or p.w <= 0 or p.h <= 0:
        idat.free()
        _err("PNG : en-tête absent")
    interlaced := p.chans == -1
    ct := p.ctype
    if ct == 0 or ct == 3:
        p.chans = 1
    elif ct == 2:
        p.chans = 3
    elif ct == 4:
        p.chans = 2
    elif ct == 6:
        p.chans = 4
    else:
        idat.free()
        _err("PNG : type de couleur invalide")
    if ct == 3 and p.pal == 0:
        p.pal = _mem(1024)
        __zero(p.pal, 1024)
    if ct == 2 and p.depth == 8:
        # la transparence d'une couleur est comparée aux octets
        if p.trns_r >= 0:
            p.trns_r = p.trns_r & 255
            p.trns_gg = p.trns_gg & 255
            p.trns_b = p.trns_b & 255
    if ct == 0 and p.trns_g >= 0 and p.depth < 16:
        p.trns_g = p.trns_g & ((1 << p.depth) - 1)
    bits := p.chans * p.depth
    bpp := (bits + 7) // 8
    raw := Buf()
    if idat.n < 2:
        idat.free()
        _err("PNG : aucune donnée")
    try:
        inf.inflate_mem(idat.addr + 2, idat.n - 2, raw)
    catch e:
        if raw.n == 0:
            idat.free()
            raw.free()
            raise(e)
    idat.free()
    r := rs.create(p.w, p.h)
    src := raw.addr
    end := raw.addr + raw.n
    if not interlaced:
        rowlen := (p.w * bits + 7) // 8
        prev := 0
        y := 0
        while y < p.h and src + 1 + rowlen <= end:
            ft := __load8(src)
            cur := src + 1
            _unfilter(ft, cur, prev, rowlen, bpp)
            _png_row(p, r, cur, p.w, y, 0, 1)
            prev = cur
            src = cur + rowlen
            y += 1
    else:
        sx := [0, 4, 0, 2, 0, 1, 0]
        sy := [0, 0, 4, 0, 2, 0, 1]
        dxs := [8, 8, 4, 4, 2, 2, 1]
        dys := [8, 8, 8, 4, 4, 2, 2]
        pass := 0
        while pass < 7:
            pw := (p.w - sx[pass] + dxs[pass] - 1) // dxs[pass]
            ph := (p.h - sy[pass] + dys[pass] - 1) // dys[pass]
            if pw > 0 and ph > 0:
                rowlen := (pw * bits + 7) // 8
                prev := 0
                k := 0
                while k < ph and src + 1 + rowlen <= end:
                    ft := __load8(src)
                    cur := src + 1
                    _unfilter(ft, cur, prev, rowlen, bpp)
                    _png_row(p, r, cur, pw, sy[pass] + k * dys[pass], sx[pass], dxs[pass])
                    prev = cur
                    src = cur + rowlen
                    k += 1
            pass += 1
    raw.free()
    return r

# =============================================================================================== GIF

func _gif_palette(a: int, count: int) -> int:
    pal := _mem(1024)
    i := 0
    while i < 256:
        __store32(pal + i * 4, 0xFF000000)
        i += 1
    i = 0
    while i < count:
        q := a + i * 3
        __store32(pal + i * 4, 0xFF000000 | (__load8(q) << 16) | (__load8(q + 1) << 8) | __load8(q + 2))
        i += 1
    return pal

# Décode le flux LZW des sous-blocs à partir de a + pos : `npix` indices écrits dans out ; rend la position
# après le bloc de fin.
func _gif_lzw(a: int, n: int, pos0: int, minsize: int, out: int, npix: int) -> int:
    pos := pos0
    # assemble les sous-blocs
    data := Buf()
    while pos < n:
        bl := __load8(a + pos)
        pos += 1
        if bl == 0:
            break
        if pos + bl > n:
            bl = n - pos
        data.reserve(bl)
        __copy(data.addr + data.n, a + pos, bl)
        data.n += bl
        pos += bl
    if minsize < 2 or minsize > 11:
        data.free()
        return pos
    prefix := _mem(4096 * 4)
    suffix := _mem(4096)
    stack := _mem(4097)
    clear := 1 << minsize
    eoi := clear + 1
    size := minsize + 1
    avail := clear + 2
    old := -1
    first := 0
    bb := 0
    bc := 0
    ip := 0
    op := 0
    i := 0
    while i < clear:
        __store32(prefix + i * 4, 0xFFFF)
        __store8(suffix + i, i)
        i += 1
    while op < npix:
        while bc < size and ip < data.n:
            bb = bb | (__load8(data.addr + ip) << bc)
            ip += 1
            bc += 8
        if bc < size:
            break
        code := bb & ((1 << size) - 1)
        bb = bb >> size
        bc -= size
        if code == clear:
            size = minsize + 1
            avail = clear + 2
            old = -1
            continue
        if code == eoi:
            break
        if old == -1:
            if code >= clear:
                break
            __store8(out + op, code)
            op += 1
            old = code
            first = code
            continue
        incode := code
        sp := 0
        if code >= avail:
            if code > avail:
                break
            __store8(stack + sp, first)
            sp += 1
            code = old
        while code >= clear:
            __store8(stack + sp, __load8(suffix + code))
            sp += 1
            code = __load32(prefix + code * 4)
            if sp >= 4096:
                break
        first = __load8(suffix + code)
        __store8(stack + sp, first)
        sp += 1
        if avail < 4096:
            __store32(prefix + avail * 4, old)
            __store8(suffix + avail, first)
            avail += 1
            if avail >= (1 << size) and size < 12:
                size += 1
        old = incode
        while sp > 0 and op < npix:
            sp -= 1
            __store8(out + op, __load8(stack + sp))
            op += 1
    data.free()
    return pos

func gif(a: int, n: int) -> Anim:
    if n < 13:
        _err("GIF : en-tête tronqué")
    sw := _le16(a + 6)
    sh := _le16(a + 8)
    flags := __load8(a + 10)
    bgi := __load8(a + 11)
    pos := 13
    gpal := 0
    if (flags & 128) != 0:
        cnt := 1 << ((flags & 7) + 1)
        gpal = _gif_palette(a + pos, cnt)
        pos += cnt * 3
    anim := Anim()
    if sw <= 0 or sh <= 0:
        _err("GIF : dimensions invalides")
    canvas := rs.create(sw, sh)
    delay := 0
    transp := -1
    disposal := 0
    while pos < n and len(anim.frames) < MAX_FRAMES:
        b := __load8(a + pos)
        pos += 1
        if b == 0x3B:
            break
        if b == 0x21:
            if pos >= n:
                break
            label := __load8(a + pos)
            pos += 1
            if label == 0xF9 and pos + 5 < n and __load8(a + pos) >= 4:
                pk := __load8(a + pos + 1)
                disposal = (pk >> 2) & 7
                delay = _le16(a + pos + 2) * 10
                if (pk & 1) != 0:
                    transp = __load8(a + pos + 4)
                else:
                    transp = -1
            while pos < n:
                bl := __load8(a + pos)
                pos += 1 + bl
                if bl == 0:
                    break
        elif b == 0x2C:
            if pos + 9 > n:
                break
            fx := _le16(a + pos)
            fy := _le16(a + pos + 2)
            fw := _le16(a + pos + 4)
            fh := _le16(a + pos + 6)
            ff := __load8(a + pos + 8)
            pos += 9
            pal := gpal
            if (ff & 128) != 0:
                cnt := 1 << ((ff & 7) + 1)
                pal = _gif_palette(a + pos, cnt)
                pos += cnt * 3
            if pal == 0:
                pal = _gif_palette(a, 0)
            if pos >= n:
                break
            minsize := __load8(a + pos)
            pos += 1
            npix := fw * fh
            idx := __mmap(((npix + 1) + 4095) & ~4095)
            pos = _gif_lzw(a, n, pos, minsize, idx, npix)
            saved := Raster()
            if disposal == 3:
                saved = rs.copy(canvas)
            # ordre des lignes (entrelacement : 0, 8, 16… / 4, 12… / 2, 6… / 1, 3…)
            rows: list[int] := []
            if (ff & 64) != 0:
                for st in [[0, 8], [4, 8], [2, 4], [1, 2]]:
                    yy := st[0]
                    while yy < fh:
                        append(rows, yy)
                        yy += st[1]
            k := 0
            while k < fh:
                ry := k
                if len(rows) == fh:
                    ry = rows[k]
                cy := fy + ry
                if cy >= 0 and cy < sh:
                    x := 0
                    while x < fw:
                        cx := fx + x
                        if cx >= 0 and cx < sw:
                            ci := __load8(idx + k * fw + x)
                            if ci != transp:
                                __store32(canvas.addr + (cy * sw + cx) * 4, __load32(pal + ci * 4))
                        x += 1
                k += 1
            __munmap(idx, ((npix + 1) + 4095) & ~4095)
            append(anim.frames, rs.copy(canvas))
            d := delay
            if d <= 10:
                d = 100
            append(anim.delays, d)
            if disposal == 2:
                yy := fy
                while yy < fy + fh and yy < sh:
                    xx := fx
                    while xx < fx + fw and xx < sw:
                        if yy >= 0 and xx >= 0:
                            __store32(canvas.addr + (yy * sw + xx) * 4, 0)
                        xx += 1
                    yy += 1
            elif disposal == 3 and saved.addr != 0:
                rs.free(canvas)
                canvas = saved
            delay = 0
            transp = -1
            disposal = 0
        else:
            break
    if len(anim.frames) == 0:
        _err("GIF : aucune image")
    rs.free(canvas)
    return anim

# =============================================================================================== BMP / ICO

# Bitmap à partir de l'en-tête BITMAPINFOHEADER en h0 (n octets) ; file/fn : fichier entier (décalage des
# pixels). ico : hauteur doublée et masque ET à la suite.
func bmp(h0: int, n: int, file: int, fn: int, ico: bool) -> Raster:
    hs := _le32(h0)
    w := 0
    h := 0
    bpp := 0
    comp := 0
    ncol := 0
    if hs == 12:
        w = _le16(h0 + 4)
        h = _le16(h0 + 6)
        bpp = _le16(h0 + 10)
    else:
        w = _s32(_le32(h0 + 4))
        h = _s32(_le32(h0 + 8))
        bpp = _le16(h0 + 14)
        comp = _le32(h0 + 16)
        if hs >= 36:
            ncol = _le32(h0 + 32)
    top_down := false
    if h < 0:
        h = -h
        top_down = true
    if ico:
        h = h // 2
    if w <= 0 or h <= 0:
        _err("BMP : dimensions invalides")
    rmask := 0xFF0000
    gmask := 0xFF00
    bmask := 0xFF
    amask := 0
    if bpp == 32 and comp == 0:
        amask = 0xFF000000
    if comp == 3 or comp == 6:
        rmask = _le32(h0 + 40)
        gmask = _le32(h0 + 44)
        bmask = _le32(h0 + 48)
        if hs >= 56 or comp == 6:
            amask = _le32(h0 + 52)
    if comp != 0 and comp != 3 and comp != 6:
        _err("BMP : compression non prise en charge")
    palp := h0 + hs
    if hs == 12:
        palp = h0 + 12
    if (comp == 3 or comp == 6) and hs == 40:
        palp = h0 + 52
    if ncol == 0 and bpp <= 8:
        ncol = 1 << bpp
    pal := _mem(1024)
    __zero(pal, 1024)
    psz := 4
    if hs == 12:
        psz = 3
    i := 0
    while i < ncol and i < 256:
        q := palp + i * psz
        __store32(pal + i * 4, 0xFF000000 | (__load8(q + 2) << 16) | (__load8(q + 1) << 8) | __load8(q))
        i += 1
    pix := palp
    if bpp <= 8:
        pix = palp + ncol * psz
    if not ico and fn >= 14:
        pix = file + _le32(file + 10)
    stride := ((w * bpp + 31) // 32) * 4
    if pix + stride * h > file + fn:
        _err("BMP : données tronquées")
    r := rs.create(w, h)
    any_alpha := false
    y := 0
    while y < h:
        sy := h - 1 - y
        if top_down:
            sy = y
        row := pix + sy * stride
        x := 0
        while x < w:
            c := 0
            if bpp == 24:
                q := row + x * 3
                c = 0xFF000000 | (__load8(q + 2) << 16) | (__load8(q + 1) << 8) | __load8(q)
            elif bpp == 32 or bpp == 16:
                v := 0
                if bpp == 32:
                    v = _le32(row + x * 4)
                else:
                    v = _le16(row + x * 2)
                    if comp == 0:
                        rmask = 0x7C00
                        gmask = 0x3E0
                        bmask = 0x1F
                c = (_chan(v, amask, 255) << 24) | (_chan(v, rmask, 0) << 16) | (_chan(v, gmask, 0) << 8) | _chan(v, bmask, 0)
                if amask != 0 and (c >> 24) != 0:
                    any_alpha = true
            else:
                per := 8 // bpp
                byte := __load8(row + x // per)
                sh := 8 - bpp - (x % per) * bpp
                c = __load32(pal + ((byte >> sh) & ((1 << bpp) - 1)) * 4)
            __store32(r.addr + (y * w + x) * 4, c)
            x += 1
        y += 1
    if amask != 0 and not any_alpha:
        # canal alpha entièrement nul : image opaque (fréquent en BMP 32 bits)
        i = 0
        while i < w * h:
            __store32(r.addr + i * 4, __load32(r.addr + i * 4) | 0xFF000000)
            i += 1
    if ico and bpp < 32:
        mstride := ((w + 31) // 32) * 4
        mrow0 := pix + stride * h
        if mrow0 + mstride * h <= file + fn:
            y = 0
            while y < h:
                mrow := mrow0 + (h - 1 - y) * mstride
                x := 0
                while x < w:
                    if ((__load8(mrow + x // 8) >> (7 - x % 8)) & 1) != 0:
                        __store32(r.addr + (y * w + x) * 4, 0)
                    x += 1
                y += 1
    return r

func _chan(v: int, mask: int, dflt: int) -> int:
    if mask == 0:
        return dflt
    sh := 0
    m := mask
    while (m & 1) == 0:
        m = m >> 1
        sh += 1
    x := (v & mask) >> sh
    if m == 255:
        return x
    return x * 255 // m

func ico(a: int, n: int) -> Raster:
    cnt := _le16(a + 4)
    best := -1
    bestsz := -1
    i := 0
    while i < cnt and 6 + i * 16 + 16 <= n:
        e := a + 6 + i * 16
        w := __load8(e)
        if w == 0:
            w = 256
        bits := _le16(e + 6)
        score := w * 64 + bits
        if score > bestsz:
            bestsz = score
            best = i
        i += 1
    if best < 0:
        _err("ICO : aucune image")
    e := a + 6 + best * 16
    size := _le32(e + 8)
    off := _le32(e + 12)
    if off + size > n:
        _err("ICO : données tronquées")
    p := a + off
    if size >= 8 and __load8(p) == 137 and __load8(p + 1) == 80:
        return png(p, size)
    return bmp(p, size, p, size, true)

# =============================================================================================== JPEG

const ZIGZAG := [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63]

class _Huff:
    ok: bool := false
    lookup: int := 0        # 9 bits : (longueur << 8) | valeur ; 0 : chemin lent
    maxcode: int := 0       # 18 entrées int64
    valptr: int := 0        # 17 entrées
    mincode: int := 0
    vals: int := 0          # 256 octets

class _Comp:
    id: int := 0
    h: int := 1
    v: int := 1
    tq: int := 0
    bpl: int := 0           # blocs par ligne (alignés sur les MCU)
    bpc: int := 0           # blocs par colonne
    coefs: int := 0         # int32 x 64 par bloc
    csize: int := 0
    dc: int := 0
    pred: int := 0
    td: int := 0
    ta: int := 0
    pix: int := 0           # échantillons 8 bits (bpl * 8) x (bpc * 8)

class _Jpeg:
    a: int := 0
    n: int := 0
    pos: int := 0
    bb: int := 0
    bc: int := 0
    marker: int := 0
    w: int := 0
    h: int := 0
    progressive: bool := false
    comps: list[_Comp] := []
    qt: int := 0            # 4 tables x 64 int64
    hdc: list[_Huff] := []
    hac: list[_Huff] := []
    hmax: int := 1
    vmax: int := 1
    mcux: int := 0
    mcuy: int := 0
    restart: int := 0
    eobrun: int := 0
    adobe: int := -1

    func init():
        self.comps = []
        self.hdc = [_Huff(), _Huff(), _Huff(), _Huff()]
        self.hac = [_Huff(), _Huff(), _Huff(), _Huff()]

func _jfill(j: _Jpeg):
    while j.bc <= 24:
        b := 0
        if j.marker == 0 and j.pos < j.n:
            b = __load8(j.a + j.pos)
            if b == 255:
                c := 0
                if j.pos + 1 < j.n:
                    c = __load8(j.a + j.pos + 1)
                if c == 0:
                    j.pos += 2
                else:
                    j.marker = c
                    b = 0
            else:
                j.pos += 1
        j.bb = j.bb | (b << (24 - j.bc))
        j.bc += 8

func _jbits(j: _Jpeg, k: int) -> int:
    if k == 0:
        return 0
    if j.bc < k:
        _jfill(j)
    v := (j.bb >> (32 - k)) & ((1 << k) - 1)
    j.bb = (j.bb << k) & 0xFFFFFFFF
    j.bc -= k
    return v

func _jbit(j: _Jpeg) -> int:
    return _jbits(j, 1)

func _extend(v: int, t: int) -> int:
    if t == 0:
        return 0
    if v < (1 << (t - 1)):
        return v - (1 << t) + 1
    return v

func _jdecode(j: _Jpeg, hf: _Huff) -> int:
    if not hf.ok:
        _err("JPEG : table de Huffman absente")
    if j.bc < 16:
        _jfill(j)
    look := (j.bb >> 23) & 511
    e := __load32(hf.lookup + look * 4)
    if e != 0:
        l := e >> 8
        j.bb = (j.bb << l) & 0xFFFFFFFF
        j.bc -= l
        return e & 255
    code := 0
    l := 1
    while l <= 16:
        code = (code << 1) | ((j.bb >> 31) & 1)
        j.bb = (j.bb << 1) & 0xFFFFFFFF
        j.bc -= 1
        if j.bc < 0:
            _jfill(j)
        if code <= __load64(hf.maxcode + l * 8):
            return __load8(hf.vals + __load64(hf.valptr + l * 8) + code - __load64(hf.mincode + l * 8))
        l += 1
    return 0

func _jhuff_build(hf: _Huff, counts: int, vals: int, nvals: int):
    hf.ok = true
    hf.lookup = _mem(512 * 4)
    __zero(hf.lookup, 2048)
    hf.maxcode = _mem(18 * 8)
    hf.valptr = _mem(18 * 8)
    hf.mincode = _mem(18 * 8)
    hf.vals = _mem(256)
    __zero(hf.vals, 256)
    __copy(hf.vals, vals, nvals)
    code := 0
    k := 0
    l := 1
    while l <= 16:
        cnt := __load8(counts + l - 1)
        __store64(hf.valptr + l * 8, k)
        __store64(hf.mincode + l * 8, code)
        if cnt > 0:
            i := 0
            while i < cnt:
                if l <= 9:
                    base := (code << (9 - l))
                    fill := 1 << (9 - l)
                    f := 0
                    while f < fill:
                        __store32(hf.lookup + (base + f) * 4, (l << 8) | __load8(vals + k + i))
                        f += 1
                code += 1
                i += 1
            k += cnt
            __store64(hf.maxcode + l * 8, code - 1)
        else:
            __store64(hf.maxcode + l * 8, -1)
        code = code << 1
        l += 1

func _coef_addr(c: _Comp, row: int, col: int) -> int:
    return c.coefs + (row * c.bpl + col) * 256

func _store(addr: int, v: int):
    __store32(addr, v & 0xFFFFFFFF)

func _load(addr: int) -> int:
    v := __load32(addr)
    if v >= 2147483648:
        return v - 4294967296
    return v

func _block_baseline(j: _Jpeg, c: _Comp, blk: int):
    t := _jdecode(j, j.hdc[c.td])
    diff := 0
    if t > 0:
        diff = _extend(_jbits(j, t), t)
    c.pred += diff
    _store(blk, c.pred)
    k := 1
    hf := j.hac[c.ta]
    while k < 64:
        rs0 := _jdecode(j, hf)
        s := rs0 & 15
        r := rs0 >> 4
        if s == 0:
            if r < 15:
                break
            k += 16
            continue
        k += r
        if k > 63:
            break
        _store(blk + ZIGZAG[k] * 4, _extend(_jbits(j, s), s))
        k += 1

func _block_dc_first(j: _Jpeg, c: _Comp, blk: int, al: int):
    t := _jdecode(j, j.hdc[c.td])
    diff := 0
    if t > 0:
        diff = _extend(_jbits(j, t), t)
    c.pred += diff
    _store(blk, c.pred << al)

func _block_dc_refine(j: _Jpeg, blk: int, al: int):
    if _jbit(j) != 0:
        _store(blk, _load(blk) | (1 << al))

func _block_ac_first(j: _Jpeg, c: _Comp, blk: int, ss: int, se: int, al: int):
    if j.eobrun > 0:
        j.eobrun -= 1
        return
    k := ss
    hf := j.hac[c.ta]
    while k <= se:
        rs0 := _jdecode(j, hf)
        s := rs0 & 15
        r := rs0 >> 4
        if s == 0:
            if r < 15:
                j.eobrun = (1 << r) - 1
                if r > 0:
                    j.eobrun += _jbits(j, r)
                break
            k += 16
            continue
        k += r
        if k > 63:
            break
        _store(blk + ZIGZAG[k] * 4, _extend(_jbits(j, s), s) * (1 << al))
        k += 1

func _refine_coef(j: _Jpeg, addr: int, p1: int):
    v := _load(addr)
    if _jbit(j) != 0:
        if (v & p1) == 0:
            if v >= 0:
                _store(addr, v + p1)
            else:
                _store(addr, v - p1)

func _block_ac_refine(j: _Jpeg, c: _Comp, blk: int, ss: int, se: int, al: int):
    p1 := 1 << al
    m1 := -1 * p1
    k := ss
    hf := j.hac[c.ta]
    if j.eobrun <= 0:
        while k <= se:
            rs0 := _jdecode(j, hf)
            s := rs0 & 15
            r := rs0 >> 4
            val := 0
            if s == 0:
                if r < 15:
                    j.eobrun = (1 << r)
                    if r > 0:
                        j.eobrun += _jbits(j, r)
                    break
            else:
                if _jbit(j) != 0:
                    val = p1
                else:
                    val = m1
            while k <= se:
                z := blk + ZIGZAG[k] * 4
                if _load(z) != 0:
                    _refine_coef(j, z, p1)
                else:
                    if r == 0:
                        if val != 0:
                            _store(z, val)
                        k += 1
                        break
                    r -= 1
                k += 1
    if j.eobrun > 0:
        while k <= se:
            z := blk + ZIGZAG[k] * 4
            if _load(z) != 0:
                _refine_coef(j, z, p1)
            k += 1
        j.eobrun -= 1

func _jreset(j: _Jpeg):
    j.bb = 0
    j.bc = 0
    j.eobrun = 0
    for c in j.comps:
        c.pred = 0
    # saute le marqueur RST
    if j.marker >= 0xD0 and j.marker <= 0xD7:
        j.pos += 2
        j.marker = 0
    else:
        # cherche le prochain RST
        while j.pos + 1 < j.n:
            if __load8(j.a + j.pos) == 255:
                m := __load8(j.a + j.pos + 1)
                if m >= 0xD0 and m <= 0xD7:
                    j.pos += 2
                    break
                if m != 0 and m != 255:
                    break
            j.pos += 1
        j.marker = 0

# Analyse d'un balayage (SOS) dont l'en-tête commence en p ; rend la position après les données.
func _scan(j: _Jpeg, p: int) -> int:
    ns := __load8(j.a + p + 2)
    sc: list[_Comp] := []
    q := p + 3
    i := 0
    while i < ns:
        cid := __load8(j.a + q)
        tt := __load8(j.a + q + 1)
        for c in j.comps:
            if c.id == cid:
                c.td = tt >> 4
                c.ta = tt & 15
                append(sc, c)
        q += 2
        i += 1
    ss := __load8(j.a + q)
    se := __load8(j.a + q + 1)
    ah := __load8(j.a + q + 2) >> 4
    al := __load8(j.a + q + 2) & 15
    j.pos = p + _be16(j.a + p)
    j.bb = 0
    j.bc = 0
    j.marker = 0
    j.eobrun = 0
    for c in j.comps:
        c.pred = 0
    mode := 0                           # 0 de base, 1 DC premier, 2 DC affinage, 3 AC premier, 4 AC affinage
    if j.progressive:
        if ss == 0:
            if ah == 0:
                mode = 1
            else:
                mode = 2
        else:
            if ah == 0:
                mode = 3
            else:
                mode = 4
    todo := 0
    if len(sc) == 1:
        # balayage non entrelacé : blocs de la composante, dans les limites de l'image
        c := sc[0]
        bw := ((j.w * c.h + j.hmax - 1) // j.hmax + 7) // 8
        bh := ((j.h * c.v + j.vmax - 1) // j.vmax + 7) // 8
        if bw < 1:
            bw = 1
        if bh < 1:
            bh = 1
        total := bw * bh
        n := 0
        while n < total:
            if j.restart > 0 and n > 0 and n % j.restart == 0:
                _jreset(j)
            row := n // bw
            col := n % bw
            blk := _coef_addr(c, row, col)
            _jblock(j, c, blk, mode, ss, se, al)
            n += 1
    else:
        total := j.mcux * j.mcuy
        m := 0
        while m < total:
            if j.restart > 0 and m > 0 and m % j.restart == 0:
                _jreset(j)
            my := m // j.mcux
            mx := m % j.mcux
            for c in sc:
                vy := 0
                while vy < c.v:
                    hx := 0
                    while hx < c.h:
                        blk := _coef_addr(c, my * c.v + vy, mx * c.h + hx)
                        _jblock(j, c, blk, mode, ss, se, al)
                        hx += 1
                    vy += 1
            m += 1
    # avance jusqu'au marqueur suivant
    pp := j.pos
    while pp + 1 < j.n:
        if __load8(j.a + pp) == 255:
            m2 := __load8(j.a + pp + 1)
            if m2 != 0 and not (m2 >= 0xD0 and m2 <= 0xD7) and m2 != 255:
                return pp
        pp += 1
    return j.n

func _jblock(j: _Jpeg, c: _Comp, blk: int, mode: int, ss: int, se: int, al: int):
    if mode == 0:
        _block_baseline(j, c, blk)
    elif mode == 1:
        _block_dc_first(j, c, blk, al)
    elif mode == 2:
        _block_dc_refine(j, blk, al)
    elif mode == 3:
        _block_ac_first(j, c, blk, ss, se, al)
    else:
        _block_ac_refine(j, c, blk, ss, se, al)

# Échantillon sous-échantillonné interpolé (bilinéaire, centré) au pixel (x, y) de l'image.
func _sample(c: _Comp, x: int, y: int, hmax: int, vmax: int, w: int, h: int) -> int:
    cw := (w * c.h + hmax - 1) // hmax
    ch := (h * c.v + vmax - 1) // vmax
    stride := c.bpl * 8
    # position en 1/256 de pixel : (x + 0,5) * h / hmax - 0,5
    fx := ((2 * x + 1) * c.h * 128) // hmax - 128
    fy := ((2 * y + 1) * c.v * 128) // vmax - 128
    if fx < 0:
        fx = 0
    if fy < 0:
        fy = 0
    x0 := fx >> 8
    y0 := fy >> 8
    ax := fx & 255
    ay := fy & 255
    x1 := x0 + 1
    y1 := y0 + 1
    if x1 >= cw:
        x1 = cw - 1
    if y1 >= ch:
        y1 = ch - 1
    if x0 >= cw:
        x0 = cw - 1
    if y0 >= ch:
        y0 = ch - 1
    r0 := c.pix + y0 * stride
    r1 := c.pix + y1 * stride
    top := __load8(r0 + x0) * (256 - ax) + __load8(r0 + x1) * ax
    bot := __load8(r1 + x0) * (256 - ax) + __load8(r1 + x1) * ax
    return (top * (256 - ay) + bot * ay + 32768) >> 16

func _clamp(v: int) -> int:
    if v < 0:
        return 0
    if v > 255:
        return 255
    return v

# IDCT entière (méthode de jidctint, LLM) sur un bloc déquantifié ; écrit 8x8 échantillons dans out (pas : stride).
func _idct(blk: int, q: int, tmp: int, out: int, stride: int):
    i := 0
    while i < 64:
        __store64(tmp + i * 8, _load(blk + i * 4) * __load64(q + i * 8))
        i += 1
    # colonnes
    c := 0
    while c < 8:
        s0 := __load64(tmp + c * 8)
        s1 := __load64(tmp + (8 + c) * 8)
        s2 := __load64(tmp + (16 + c) * 8)
        s3 := __load64(tmp + (24 + c) * 8)
        s4 := __load64(tmp + (32 + c) * 8)
        s5 := __load64(tmp + (40 + c) * 8)
        s6 := __load64(tmp + (48 + c) * 8)
        s7 := __load64(tmp + (56 + c) * 8)
        if s1 == 0 and s2 == 0 and s3 == 0 and s4 == 0 and s5 == 0 and s6 == 0 and s7 == 0:
            dcv := s0 << 2
            k := 0
            while k < 8:
                __store64(tmp + (k * 8 + c) * 8, dcv)
                k += 1
            c += 1
            continue
        p2 := s2
        p3 := s6
        p1 := (p2 + p3) * 2217
        t2 := p1 + p3 * -7567
        t3 := p1 + p2 * 3135
        t0 := (s0 + s4) << 12
        t1 := (s0 - s4) << 12
        x0 := t0 + t3
        x3 := t0 - t3
        x1 := t1 + t2
        x2 := t1 - t2
        a0 := s7
        a1 := s5
        a2 := s3
        a3 := s1
        pa := a0 + a2
        pb := a1 + a3
        pc := a0 + a3
        pd := a1 + a2
        p5 := (pa + pb) * 4816
        a0 = a0 * 1223
        a1 = a1 * 8410
        a2 = a2 * 12586
        a3 = a3 * 6149
        pc = p5 + pc * -3685
        pd = p5 + pd * -10497
        pa = pa * -8034
        pb = pb * -1597
        a3 += pc + pb
        a2 += pd + pa
        a1 += pd + pb
        a0 += pc + pa
        x0 += 512
        x1 += 512
        x2 += 512
        x3 += 512
        __store64(tmp + c * 8, (x0 + a3) >> 10)
        __store64(tmp + (56 + c) * 8, (x0 - a3) >> 10)
        __store64(tmp + (8 + c) * 8, (x1 + a2) >> 10)
        __store64(tmp + (48 + c) * 8, (x1 - a2) >> 10)
        __store64(tmp + (16 + c) * 8, (x2 + a1) >> 10)
        __store64(tmp + (40 + c) * 8, (x2 - a1) >> 10)
        __store64(tmp + (24 + c) * 8, (x3 + a0) >> 10)
        __store64(tmp + (32 + c) * 8, (x3 - a0) >> 10)
        c += 1
    # lignes
    r := 0
    while r < 8:
        b := tmp + r * 64
        s0 := __load64(b)
        s1 := __load64(b + 8)
        s2 := __load64(b + 16)
        s3 := __load64(b + 24)
        s4 := __load64(b + 32)
        s5 := __load64(b + 40)
        s6 := __load64(b + 48)
        s7 := __load64(b + 56)
        p2 := s2
        p3 := s6
        p1 := (p2 + p3) * 2217
        t2 := p1 + p3 * -7567
        t3 := p1 + p2 * 3135
        t0 := (s0 + s4) << 12
        t1 := (s0 - s4) << 12
        x0 := t0 + t3
        x3 := t0 - t3
        x1 := t1 + t2
        x2 := t1 - t2
        a0 := s7
        a1 := s5
        a2 := s3
        a3 := s1
        pa := a0 + a2
        pb := a1 + a3
        pc := a0 + a3
        pd := a1 + a2
        p5 := (pa + pb) * 4816
        a0 = a0 * 1223
        a1 = a1 * 8410
        a2 = a2 * 12586
        a3 = a3 * 6149
        pc = p5 + pc * -3685
        pd = p5 + pd * -10497
        pa = pa * -8034
        pb = pb * -1597
        a3 += pc + pb
        a2 += pd + pa
        a1 += pd + pb
        a0 += pc + pa
        # +128 de décalage de niveau, arrondi : 65536 + (128 << 17)
        bias := 65536 + (128 << 17)
        x0 += bias
        x1 += bias
        x2 += bias
        x3 += bias
        o := out + r * stride
        __store8(o, _clamp((x0 + a3) >> 17))
        __store8(o + 7, _clamp((x0 - a3) >> 17))
        __store8(o + 1, _clamp((x1 + a2) >> 17))
        __store8(o + 6, _clamp((x1 - a2) >> 17))
        __store8(o + 2, _clamp((x2 + a1) >> 17))
        __store8(o + 5, _clamp((x2 - a1) >> 17))
        __store8(o + 3, _clamp((x3 + a0) >> 17))
        __store8(o + 4, _clamp((x3 - a0) >> 17))
        r += 1

func jpeg(a: int, n: int) -> Raster:
    j := _Jpeg()
    j.a = a
    j.n = n
    j.qt = _mem(4 * 64 * 8)
    __zero(j.qt, 4 * 64 * 8)
    p := 2
    frame := false
    while p + 4 <= n:
        if __load8(a + p) != 255:
            p += 1
            continue
        m := __load8(a + p + 1)
        if m == 255:
            p += 1
            continue
        if m == 0xD8 or (m >= 0xD0 and m <= 0xD7) or m == 1:
            p += 2
            continue
        if m == 0xD9:
            break
        seg := a + p + 2
        ln := _be16(seg)
        if p + 2 + ln > n:
            break
        if m == 0xDB:
            q := seg + 2
            while q < seg + ln:
                pq := __load8(q) >> 4
                tq := __load8(q) & 3
                q += 1
                i := 0
                while i < 64:
                    v := 0
                    if pq == 0:
                        v = __load8(q + i)
                    else:
                        v = _be16(q + i * 2)
                    __store64(j.qt + (tq * 64 + ZIGZAG[i]) * 8, v)
                    i += 1
                if pq == 0:
                    q += 64
                else:
                    q += 128
        elif m == 0xC4:
            q := seg + 2
            while q + 17 <= seg + ln:
                tc := __load8(q) >> 4
                th := __load8(q) & 3
                total := 0
                i := 0
                while i < 16:
                    total += __load8(q + 1 + i)
                    i += 1
                if tc == 0:
                    _jhuff_build(j.hdc[th], q + 1, q + 17, total)
                else:
                    _jhuff_build(j.hac[th], q + 1, q + 17, total)
                q += 17 + total
        elif m == 0xC0 or m == 0xC1 or m == 0xC2:
            j.progressive = m == 0xC2
            if __load8(seg + 2) != 8:
                _err("JPEG : précision non prise en charge")
            j.h = _be16(seg + 3)
            j.w = _be16(seg + 5)
            nc := __load8(seg + 7)
            i := 0
            while i < nc:
                c := _Comp()
                c.id = __load8(seg + 8 + i * 3)
                c.h = __load8(seg + 9 + i * 3) >> 4
                c.v = __load8(seg + 9 + i * 3) & 15
                c.tq = __load8(seg + 10 + i * 3) & 3
                if c.h < 1:
                    c.h = 1
                if c.v < 1:
                    c.v = 1
                if c.h > j.hmax:
                    j.hmax = c.h
                if c.v > j.vmax:
                    j.vmax = c.v
                append(j.comps, c)
                i += 1
            if j.w <= 0 or j.h <= 0:
                _err("JPEG : dimensions invalides")
            j.mcux = (j.w + 8 * j.hmax - 1) // (8 * j.hmax)
            j.mcuy = (j.h + 8 * j.vmax - 1) // (8 * j.vmax)
            for c in j.comps:
                c.bpl = j.mcux * c.h
                c.bpc = j.mcuy * c.v
                c.csize = (c.bpl * c.bpc * 256 + 4095) & ~4095
                c.coefs = __mmap(c.csize)
            frame = true
        elif m >= 0xC3 and m <= 0xCF and m != 0xC4 and m != 0xC8 and m != 0xCC:
            _err("JPEG : codage non pris en charge (sans perte ou arithmétique)")
        elif m == 0xDD:
            j.restart = _be16(seg + 2)
        elif m == 0xEE:
            if ln >= 12 and __load8(seg + 2) == 65 and __load8(seg + 3) == 100:
                j.adobe = __load8(seg + 13)
        elif m == 0xDA:
            if not frame:
                _err("JPEG : balayage avant l'en-tête")
            try:
                p = _scan(j, p + 2)
            catch e:
                # données tronquées : on garde ce qui a été décodé
                break
            continue
        p += 2 + ln
    if not frame:
        _err("JPEG : en-tête absent")
    # IDCT de chaque composante
    tmp := _mem(64 * 8)
    for c in j.comps:
        sw := c.bpl * 8
        sh := c.bpc * 8
        c.pix = __mmap((sw * sh + 4095) & ~4095)
        q := j.qt + c.tq * 64 * 8
        row := 0
        while row < c.bpc:
            col := 0
            while col < c.bpl:
                _idct(_coef_addr(c, row, col), q, tmp, c.pix + row * 8 * sw + col * 8, sw)
                col += 1
            row += 1
        __munmap(c.coefs, c.csize)
        c.coefs = 0
    r := rs.create(j.w, j.h)
    nc := len(j.comps)
    transform := true
    if nc == 3 and j.adobe == 0:
        transform = false
    if nc == 3:
        c0 := j.comps[0]
        c1 := j.comps[1]
        c2 := j.comps[2]
        # identifiants « R », « G », « B » : pas de conversion
        if c0.id == 82 and c1.id == 71 and c2.id == 66:
            transform = false
    y := 0
    while y < j.h:
        x := 0
        dst := r.addr + y * j.w * 4
        while x < j.w:
            if nc == 1:
                c0 := j.comps[0]
                g := __load8(c0.pix + y * c0.bpl * 8 + x)
                __store32(dst + x * 4, 0xFF000000 | (g << 16) | (g << 8) | g)
            else:
                v0 := 0
                v1 := 0
                v2 := 0
                v3 := 0
                k := 0
                while k < nc and k < 4:
                    c := j.comps[k]
                    vv := 0
                    if c.h == j.hmax and c.v == j.vmax:
                        vv = __load8(c.pix + y * c.bpl * 8 + x)
                    else:
                        vv = _sample(c, x, y, j.hmax, j.vmax, j.w, j.h)
                    if k == 0:
                        v0 = vv
                    elif k == 1:
                        v1 = vv
                    elif k == 2:
                        v2 = vv
                    else:
                        v3 = vv
                    k += 1
                rr := v0
                gg := v1
                bb := v2
                if nc == 3 and transform or (nc == 4 and j.adobe == 2):
                    yy := v0 << 16
                    cb := v1 - 128
                    cr := v2 - 128
                    rr = _clamp((yy + 91881 * cr + 32768) >> 16)
                    gg = _clamp((yy - 22554 * cb - 46802 * cr + 32768) >> 16)
                    bb = _clamp((yy + 116130 * cb + 32768) >> 16)
                if nc == 4:
                    kk := v3
                    if j.adobe == 2:
                        rr = 255 - rr
                        gg = 255 - gg
                        bb = 255 - bb
                    if j.adobe >= 0:
                        # CMJN Adobe : valeurs inversées
                        rr = rr * kk // 255
                        gg = gg * kk // 255
                        bb = bb * kk // 255
                    else:
                        rr = (255 - rr) * (255 - kk) // 255
                        gg = (255 - gg) * (255 - kk) // 255
                        bb = (255 - bb) * (255 - kk) // 255
                __store32(dst + x * 4, 0xFF000000 | (rr << 16) | (gg << 8) | bb)
            x += 1
        y += 1
    for c in j.comps:
        __munmap(c.pix, (c.bpl * 8 * c.bpc * 8 + 4095) & ~4095)
    return r

# Mémoire brute hors du ramasse-miettes (les adresses gardées dans des champs entiers ne sont pas suivies).
func _mem(n: int) -> int:
    return __mmap((n + 4095) & ~4095)

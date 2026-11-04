# alex: native
# alex: intrinsics
# ALEX STANDARD LIBRARY — pixmap
#
# Moteur de dessin 2D logiciel pour les programmes natifs (`alexc build --native`) : surfaces de pixels en
# mémoire brute, remplissages, mélange alpha, rectangles arrondis anti-crénelés, ombres portées, dégradés,
# polygones, images, texte (polices bitmap lissées .alfont) et enregistrement PNG / PPM. Utilisé par l'interface
# graphique d'Alex OS (gui/), mais indépendant du système : une surface peut aussi envelopper le tampon de trame
# d'un périphérique mappé en mémoire (`wrap`, `map_file`).
#
# Format des pixels : 32 bits, 0xAARRGGBB (octets B, G, R, A en mémoire : l'ordre du tampon de trame Bochs/VBE),
# alpha non prémultiplié. Une surface à 8 bits (`create_mask`) est un masque de couverture (glyphes, icônes
# monochromes) que `draw_mask` teinte à l'affichage.
#
#   use pixmap
#   p := pixmap.create(320, 200)
#   pixmap.fill(p, 0, 0, 320, 200, 0xFF101830)
#   pixmap.fill_round(p, 20, 20, 120, 60, 10, 0xFF8366FF)
#   f := pixmap.load_font("/usr/share/nova/fonts/sans-14.alfont")   # ou pixmap.load_ttf("Sans.ttf", 14)
#   pixmap.draw_text(p, f, 30, 40, "Bonjour", 0xFFFFFFFF)
#   pixmap.save_png(p, "image.png")
#
# Toutes les opérations sont limitées au rectangle de découpe de la surface (`set_clip`). Les coordonnées sont
# en pixels entiers. La mémoire des surfaces vient de mmap (jamais du ramasse-miettes) : `destroy` la rend.
#
# Formats de fichiers (créés par tools/gui_assets/build_assets.py) :
#   image .alpx : « ALPX », largeur, hauteur, type (0 : ARGB 32 bits, 1 : masque 8 bits) — entiers 32 bits
#                 petit-boutiste — puis les pixels ligne par ligne, sans remplissage.
#   police .alfont : « ALFN », version, nombre de glyphes, ascendante, descendante, hauteur de ligne, 0, 0
#                 (8 entiers 32 bits), puis la table des glyphes (20 octets chacun, triée par point de code :
#                 code u32, avance u16 en 1/64 px, décalage x s16, décalage y s16 (haut du glyphe au-dessus de
#                 la ligne de base), largeur u16, hauteur u16, 0 u16, position du masque u32 dans le bloc
#                 des masques), puis les masques 8 bits.

from collections use append, contains_key
from core use len

const OPAQUE := 4278190080      # 0xFF000000
const MASK_RGB := 16777215      # 0x00FFFFFF

class Pixmap:
    addr: int := 0
    width: int := 0
    height: int := 0
    stride: int := 0
    bpp: int := 4               # octets par pixel : 4 (ARGB) ou 1 (masque)
    cx0: int := 0               # rectangle de découpe [cx0, cx1) x [cy0, cy1)
    cy0: int := 0
    cx1: int := 0
    cy1: int := 0
    base: int := 0              # début de la zone mmap à rendre (0 : mémoire qui n'est pas à nous)
    size: int := 0

class Font:
    base: int := 0
    size: int := 0
    count: int := 0
    ascent: int := 0
    descent: int := 0
    height: int := 0
    table: int := 0
    masks: int := 0
    lut: int := 0               # codes 0..767 : indice de glyphe + 1 (0 : absent)
    ttf: int := -1              # police TrueType : indice dans _ttfs (glyphes rastérisés au premier affichage)
    px: int := 0                # taille en pixels (TrueType)

# ------------------------------------------------------------------------------------------ mémoire

func _map(n: int) -> int:
    return __mmap((n + 4095) & ~4095)

func _new(w: int, h: int, bpp: int) -> Pixmap:
    p := Pixmap()
    p.width = w
    p.height = h
    p.bpp = bpp
    p.stride = w * bpp
    p.size = (p.stride * h + 4095) & ~4095
    if p.size == 0:
        p.size = 4096
    p.addr = __mmap(p.size)
    p.base = p.addr
    p.cx0 = 0
    p.cy0 = 0
    p.cx1 = w
    p.cy1 = h
    return p

# Surface ARGB de w x h pixels, transparente (zéros).
func create(w: int, h: int) -> Pixmap:
    return _new(w, h, 4)

# Masque de couverture 8 bits de w x h pixels.
func create_mask(w: int, h: int) -> Pixmap:
    return _new(w, h, 1)

# Enveloppe une mémoire existante (tampon de trame mappé...) ; stride en octets par ligne.
func wrap(addr: int, w: int, h: int, stride: int) -> Pixmap:
    p := Pixmap()
    p.addr = addr
    p.width = w
    p.height = h
    p.stride = stride
    p.bpp = 4
    p.cx0 = 0
    p.cy0 = 0
    p.cx1 = w
    p.cy1 = h
    return p

# Rend la mémoire d'une surface créée par create / create_mask / load.
func destroy(p: Pixmap):
    if p.base != 0 and p.size > 0:
        __munmap(p.base, p.size)
    p.base = 0
    p.addr = 0
    p.width = 0
    p.height = 0
    p.cx1 = 0
    p.cy1 = 0

func width(p: Pixmap) -> int:
    return p.width

func height(p: Pixmap) -> int:
    return p.height

func stride(p: Pixmap) -> int:
    return p.stride

func address(p: Pixmap) -> int:
    return p.addr

func set_clip(p: Pixmap, x: int, y: int, w: int, h: int):
    x0 := x
    y0 := y
    x1 := x + w
    y1 := y + h
    if x0 < 0:
        x0 = 0
    if y0 < 0:
        y0 = 0
    if x1 > p.width:
        x1 = p.width
    if y1 > p.height:
        y1 = p.height
    if x1 < x0:
        x1 = x0
    if y1 < y0:
        y1 = y0
    p.cx0 = x0
    p.cy0 = y0
    p.cx1 = x1
    p.cy1 = y1

func reset_clip(p: Pixmap):
    p.cx0 = 0
    p.cy0 = 0
    p.cx1 = p.width
    p.cy1 = p.height

func clip_x(p: Pixmap) -> int:
    return p.cx0

func clip_y(p: Pixmap) -> int:
    return p.cy0

func clip_w(p: Pixmap) -> int:
    return p.cx1 - p.cx0

func clip_h(p: Pixmap) -> int:
    return p.cy1 - p.cy0

# Pixel (x, y) : 0xAARRGGBB, 0 hors de la surface.
func get(p: Pixmap, x: int, y: int) -> int:
    if x < 0 or y < 0 or x >= p.width or y >= p.height:
        return 0
    if p.bpp == 1:
        return __load8(p.addr + y * p.stride + x)
    return __load32(p.addr + y * p.stride + x * 4)

# Écrit le pixel (x, y) sans mélange (dans le rectangle de découpe).
func put(p: Pixmap, x: int, y: int, c: int):
    if x < p.cx0 or y < p.cy0 or x >= p.cx1 or y >= p.cy1:
        return
    __store32(p.addr + y * p.stride + x * 4, c & 0xFFFFFFFF)

# ------------------------------------------------------------------------------------------ mélange

# Mélange la couleur color (0x00RRGGBB) d'opacité a (0..255) sur le pixel en addr (« source sur destination »).
func _blend_px(addr: int, color: int, a: int):
    if a <= 0:
        return
    if a >= 255:
        __store32(addr, color | OPAQUE)
        return
    d := __load32(addr)
    ia := 255 - a
    sr := (color >> 16) & 255
    sg := (color >> 8) & 255
    sb := color & 255
    dr := (d >> 16) & 255
    dg := (d >> 8) & 255
    db := d & 255
    da := d >> 24
    if da == 255:
        t := sr * a + dr * ia + 128
        r := (t + (t >> 8)) >> 8
        t = sg * a + dg * ia + 128
        g := (t + (t >> 8)) >> 8
        t = sb * a + db * ia + 128
        b := (t + (t >> 8)) >> 8
        __store32(addr, OPAQUE | (r << 16) | (g << 8) | b)
        return
    wd := (da * ia + 127) // 255
    oa := a + wd
    if oa <= 0:
        __store32(addr, 0)
        return
    r2 := (sr * a + dr * wd + oa // 2) // oa
    g2 := (sg * a + dg * wd + oa // 2) // oa
    b2 := (sb * a + db * wd + oa // 2) // oa
    __store32(addr, (oa << 24) | (r2 << 16) | (g2 << 8) | b2)

# Remplit le rectangle avec la couleur c, sans mélange (alpha compris).
func fill(p: Pixmap, x: int, y: int, w: int, h: int, c: int):
    x0 := x
    y0 := y
    x1 := x + w
    y1 := y + h
    if x0 < p.cx0:
        x0 = p.cx0
    if y0 < p.cy0:
        y0 = p.cy0
    if x1 > p.cx1:
        x1 = p.cx1
    if y1 > p.cy1:
        y1 = p.cy1
    if x0 >= x1 or y0 >= y1:
        return
    c32 := c & 0xFFFFFFFF
    pair := c32 | (c32 << 32)
    n := x1 - x0
    first := p.addr + y0 * p.stride + x0 * 4
    a := first
    k := n
    while k >= 2:
        __store64(a, pair)
        a += 8
        k -= 2
    if k == 1:
        __store32(a, c32)
    row := first + p.stride
    yy := y0 + 1
    while yy < y1:
        __copy(row, first, n * 4)
        row += p.stride
        yy += 1

# Efface toute la surface (sans tenir compte du rectangle de découpe).
func clear(p: Pixmap, c: int):
    save_x0 := p.cx0
    save_y0 := p.cy0
    save_x1 := p.cx1
    save_y1 := p.cy1
    reset_clip(p)
    fill(p, 0, 0, p.width, p.height, c)
    p.cx0 = save_x0
    p.cy0 = save_y0
    p.cx1 = save_x1
    p.cy1 = save_y1

# Remplit avec mélange : l'opacité est l'alpha de c.
func blend(p: Pixmap, x: int, y: int, w: int, h: int, c: int):
    a := (c >> 24) & 255
    if a == 255:
        fill(p, x, y, w, h, c)
        return
    if a == 0:
        return
    x0 := x
    y0 := y
    x1 := x + w
    y1 := y + h
    if x0 < p.cx0:
        x0 = p.cx0
    if y0 < p.cy0:
        y0 = p.cy0
    if x1 > p.cx1:
        x1 = p.cx1
    if y1 > p.cy1:
        y1 = p.cy1
    if x0 >= x1 or y0 >= y1:
        return
    ia := 255 - a
    sr := ((c >> 16) & 255) * a + 128
    sg := ((c >> 8) & 255) * a + 128
    sb := (c & 255) * a + 128
    row := p.addr + y0 * p.stride + x0 * 4
    yy := y0
    while yy < y1:
        q := row
        xx := x0
        while xx < x1:
            d := __load32(q)
            if (d >> 24) == 255:
                t := sr + ((d >> 16) & 255) * ia
                r := (t + (t >> 8)) >> 8
                t = sg + ((d >> 8) & 255) * ia
                g := (t + (t >> 8)) >> 8
                t = sb + (d & 255) * ia
                b := (t + (t >> 8)) >> 8
                __store32(q, OPAQUE | (r << 16) | (g << 8) | b)
            else:
                _blend_px(q, c & MASK_RGB, a)
            q += 4
            xx += 1
        row += p.stride
        yy += 1

# Dégradé vertical de c0 (haut) à c1 (bas), opaque.
func gradient_v(p: Pixmap, x: int, y: int, w: int, h: int, c0: int, c1: int):
    if h <= 0:
        return
    yy := 0
    while yy < h:
        t := 0
        if h > 1:
            t = yy * 255 // (h - 1)
        r := (((c0 >> 16) & 255) * (255 - t) + ((c1 >> 16) & 255) * t + 127) // 255
        g := (((c0 >> 8) & 255) * (255 - t) + ((c1 >> 8) & 255) * t + 127) // 255
        b := ((c0 & 255) * (255 - t) + (c1 & 255) * t + 127) // 255
        fill(p, x, y + yy, w, 1, OPAQUE | (r << 16) | (g << 8) | b)
        yy += 1

# Dégradé horizontal de c0 (gauche) à c1 (droite), opaque.
func gradient_h(p: Pixmap, x: int, y: int, w: int, h: int, c0: int, c1: int):
    if w <= 0:
        return
    xx := 0
    while xx < w:
        t := 0
        if w > 1:
            t = xx * 255 // (w - 1)
        r := (((c0 >> 16) & 255) * (255 - t) + ((c1 >> 16) & 255) * t + 127) // 255
        g := (((c0 >> 8) & 255) * (255 - t) + ((c1 >> 8) & 255) * t + 127) // 255
        b := ((c0 & 255) * (255 - t) + (c1 & 255) * t + 127) // 255
        fill(p, x + xx, y, 1, h, OPAQUE | (r << 16) | (g << 8) | b)
        xx += 1

# Couleur intermédiaire entre c0 et c1 (t de 0 à 255), alpha compris.
func mix(c0: int, c1: int, t: int) -> int:
    a := (((c0 >> 24) & 255) * (255 - t) + ((c1 >> 24) & 255) * t + 127) // 255
    r := (((c0 >> 16) & 255) * (255 - t) + ((c1 >> 16) & 255) * t + 127) // 255
    g := (((c0 >> 8) & 255) * (255 - t) + ((c1 >> 8) & 255) * t + 127) // 255
    b := ((c0 & 255) * (255 - t) + (c1 & 255) * t + 127) // 255
    return (a << 24) | (r << 16) | (g << 8) | b

# Même couleur avec l'alpha multiplié par op / 255.
func with_alpha(c: int, op: int) -> int:
    a := (((c >> 24) & 255) * op + 127) // 255
    return (a << 24) | (c & MASK_RGB)

# ------------------------------------------------------------------------------------------ copies

# Copie sans mélange le rectangle (sx, sy, w, h) de src vers (dx, dy) de dst.
func blit(dst: Pixmap, dx: int, dy: int, src: Pixmap, sx: int, sy: int, w: int, h: int):
    x0 := dx
    y0 := dy
    if sx < 0:
        x0 -= sx
        w += sx
        sx = 0
    if sy < 0:
        y0 -= sy
        h += sy
        sy = 0
    if sx + w > src.width:
        w = src.width - sx
    if sy + h > src.height:
        h = src.height - sy
    x1 := x0 + w
    y1 := y0 + h
    if x0 < dst.cx0:
        sx += dst.cx0 - x0
        x0 = dst.cx0
    if y0 < dst.cy0:
        sy += dst.cy0 - y0
        y0 = dst.cy0
    if x1 > dst.cx1:
        x1 = dst.cx1
    if y1 > dst.cy1:
        y1 = dst.cy1
    if x0 >= x1 or y0 >= y1:
        return
    n := (x1 - x0) * 4
    s := src.addr + sy * src.stride + sx * 4
    d := dst.addr + y0 * dst.stride + x0 * 4
    yy := y0
    while yy < y1:
        __copy(d, s, n)
        s += src.stride
        d += dst.stride
        yy += 1

# Copie avec mélange alpha (source sur destination) ; opacity (0..255) s'applique en plus à l'alpha de src.
func blit_alpha(dst: Pixmap, dx: int, dy: int, src: Pixmap, sx: int, sy: int, w: int, h: int, opacity: int):
    if opacity <= 0:
        return
    x0 := dx
    y0 := dy
    if sx < 0:
        x0 -= sx
        w += sx
        sx = 0
    if sy < 0:
        y0 -= sy
        h += sy
        sy = 0
    if sx + w > src.width:
        w = src.width - sx
    if sy + h > src.height:
        h = src.height - sy
    x1 := x0 + w
    y1 := y0 + h
    if x0 < dst.cx0:
        sx += dst.cx0 - x0
        x0 = dst.cx0
    if y0 < dst.cy0:
        sy += dst.cy0 - y0
        y0 = dst.cy0
    if x1 > dst.cx1:
        x1 = dst.cx1
    if y1 > dst.cy1:
        y1 = dst.cy1
    if x0 >= x1 or y0 >= y1:
        return
    s := src.addr + sy * src.stride + sx * 4
    d := dst.addr + y0 * dst.stride + x0 * 4
    yy := y0
    while yy < y1:
        sp := s
        dp := d
        xx := x0
        while xx < x1:
            v := __load32(sp)
            a := v >> 24
            if opacity < 255:
                a = (a * opacity + 127) // 255
            if a >= 255:
                __store32(dp, v | OPAQUE)
            elif a > 0:
                _blend_px(dp, v & MASK_RGB, a)
            sp += 4
            dp += 4
            xx += 1
        s += src.stride
        d += dst.stride
        yy += 1

# Peint color à travers le canal alpha de la surface 32 bits src posée en (dx, dy) (CSS mask-image) :
# seul l'alpha de src compte, multiplié par celui de color.
func draw_tinted(dst: Pixmap, dx: int, dy: int, src: Pixmap, color: int):
    ca := (color >> 24) & 255
    if ca == 0 or src.bpp != 4:
        return
    sx := 0
    sy := 0
    x0 := dx
    y0 := dy
    x1 := x0 + src.width
    y1 := y0 + src.height
    if x0 < dst.cx0:
        sx += dst.cx0 - x0
        x0 = dst.cx0
    if y0 < dst.cy0:
        sy += dst.cy0 - y0
        y0 = dst.cy0
    if x1 > dst.cx1:
        x1 = dst.cx1
    if y1 > dst.cy1:
        y1 = dst.cy1
    if x0 >= x1 or y0 >= y1:
        return
    rgb := color & MASK_RGB
    s := src.addr + sy * src.stride + sx * 4
    d := dst.addr + y0 * dst.stride + x0 * 4
    yy := y0
    while yy < y1:
        sp := s
        dp := d
        xx := x0
        while xx < x1:
            a := __load32(sp) >> 24
            if a != 0:
                if ca != 255:
                    a = (a * ca + 127) // 255
                if a >= 255:
                    __store32(dp, rgb | OPAQUE)
                else:
                    _blend_px(dp, rgb, a)
            sp += 4
            dp += 4
            xx += 1
        s += src.stride
        d += dst.stride
        yy += 1

# Dessine le masque 8 bits m (tout ou partie : rectangle (sx, sy, w, h)) en (dx, dy), teinté par color.
func draw_mask(dst: Pixmap, dx: int, dy: int, m: Pixmap, sx: int, sy: int, w: int, h: int, color: int):
    ca := (color >> 24) & 255
    if ca == 0 or m.bpp != 1:
        return
    x0 := dx
    y0 := dy
    if sx < 0:
        x0 -= sx
        w += sx
        sx = 0
    if sy < 0:
        y0 -= sy
        h += sy
        sy = 0
    if sx + w > m.width:
        w = m.width - sx
    if sy + h > m.height:
        h = m.height - sy
    x1 := x0 + w
    y1 := y0 + h
    if x0 < dst.cx0:
        sx += dst.cx0 - x0
        x0 = dst.cx0
    if y0 < dst.cy0:
        sy += dst.cy0 - y0
        y0 = dst.cy0
    if x1 > dst.cx1:
        x1 = dst.cx1
    if y1 > dst.cy1:
        y1 = dst.cy1
    if x0 >= x1 or y0 >= y1:
        return
    rgb := color & MASK_RGB
    s := m.addr + sy * m.stride + sx
    d := dst.addr + y0 * dst.stride + x0 * 4
    yy := y0
    while yy < y1:
        sp := s
        dp := d
        xx := x0
        while xx < x1:
            a := __load8(sp)
            if a != 0:
                if ca != 255:
                    a = (a * ca + 127) // 255
                _blend_px(dp, rgb, a)
            sp += 1
            dp += 4
            xx += 1
        s += m.stride
        d += dst.stride
        yy += 1

# Copie redimensionnée (interpolation bilinéaire) de toute la surface src vers le rectangle (dx, dy, dw, dh).
func blit_scaled(dst: Pixmap, dx: int, dy: int, dw: int, dh: int, src: Pixmap):
    if dw <= 0 or dh <= 0 or src.width <= 0 or src.height <= 0 or src.bpp != 4:
        return
    y := 0
    while y < dh:
        py := dy + y
        if py >= dst.cy0 and py < dst.cy1:
            fy := ((2 * y + 1) * src.height * 32) // dh - 32   # position source en 1/64 de pixel
            y0 := fy >> 6
            wy := fy & 63
            if fy < 0:
                y0 = -1
                wy = 64 + fy
                if wy < 0:
                    wy = 0
            y1 := y0 + 1
            if y0 < 0:
                y0 = 0
            if y1 >= src.height:
                y1 = src.height - 1
            if y0 >= src.height:
                y0 = src.height - 1
            x := 0
            while x < dw:
                px := dx + x
                if px >= dst.cx0 and px < dst.cx1:
                    fx := ((2 * x + 1) * src.width * 32) // dw - 32
                    x0 := fx >> 6
                    wx := fx & 63
                    if fx < 0:
                        x0 = -1
                        wx = 64 + fx
                        if wx < 0:
                            wx = 0
                    x1 := x0 + 1
                    if x0 < 0:
                        x0 = 0
                    if x1 >= src.width:
                        x1 = src.width - 1
                    if x0 >= src.width:
                        x0 = src.width - 1
                    c00 := __load32(src.addr + y0 * src.stride + x0 * 4)
                    c10 := __load32(src.addr + y0 * src.stride + x1 * 4)
                    c01 := __load32(src.addr + y1 * src.stride + x0 * 4)
                    c11 := __load32(src.addr + y1 * src.stride + x1 * 4)
                    # moyenne pondérée par l'alpha (couleurs non prémultipliées)
                    w00 := (64 - wx) * (64 - wy)
                    w10 := wx * (64 - wy)
                    w01 := (64 - wx) * wy
                    w11 := wx * wy
                    a00 := (c00 >> 24) * w00
                    a10 := (c10 >> 24) * w10
                    a01 := (c01 >> 24) * w01
                    a11 := (c11 >> 24) * w11
                    at := a00 + a10 + a01 + a11
                    if at > 0:
                        r := (((c00 >> 16) & 255) * a00 + ((c10 >> 16) & 255) * a10 + ((c01 >> 16) & 255) * a01 + ((c11 >> 16) & 255) * a11 + at // 2) // at
                        g := (((c00 >> 8) & 255) * a00 + ((c10 >> 8) & 255) * a10 + ((c01 >> 8) & 255) * a01 + ((c11 >> 8) & 255) * a11 + at // 2) // at
                        b := ((c00 & 255) * a00 + (c10 & 255) * a10 + (c01 & 255) * a01 + (c11 & 255) * a11 + at // 2) // at
                        a := (at + 2048) // 4096
                        if a > 255:
                            a = 255
                        _blend_px(dst.addr + py * dst.stride + px * 4, (r << 16) | (g << 8) | b, a)
                x += 1
        y += 1

# ------------------------------------------------------------------------------------------ formes arrondies

func _isqrt(n: int) -> int:
    if n <= 0:
        return 0
    x := n
    y := (x + 1) // 2
    while y < x:
        x = y
        y = (x + n // x) // 2
    return x

_corners: dict[int, int] := {}

# Table de couverture d'un coin arrondi de rayon r (r x r octets) : couverture du pixel (i, j) du coin haut gauche
# (j = ligne depuis le haut, i = colonne depuis la gauche) par le disque de rayon r centré en (r, r).
func _corner(r: int) -> int:
    if contains_key(_corners, r):
        return _corners[r]
    t := __mmap(r * r + 8)
    j := 0
    while j < r:
        i := 0
        while i < r:
            dx2 := 2 * (r - i) - 1
            dy2 := 2 * (r - j) - 1
            d16 := _isqrt(64 * (dx2 * dx2 + dy2 * dy2))     # 16 x distance au centre
            cov16 := 16 * r - d16 + 8
            if cov16 < 0:
                cov16 = 0
            if cov16 > 16:
                cov16 = 16
            __store8(t + j * r + i, (cov16 * 255 + 8) // 16)
            i += 1
        j += 1
    _corners[r] = t
    return t

func _limit_radius(w: int, h: int, r: int) -> int:
    m := w
    if h < m:
        m = h
    m = m // 2
    if r > m:
        return m
    return r

# Pose un pixel de coin : couverture cov (0..255) multipliée par l'opacité du remplissage.
func _corner_px(p: Pixmap, x: int, y: int, rgb: int, ca: int, cov: int):
    if cov == 0:
        return
    if x < p.cx0 or y < p.cy0 or x >= p.cx1 or y >= p.cy1:
        return
    a := cov
    if ca != 255:
        a = (cov * ca + 127) // 255
    _blend_px(p.addr + y * p.stride + x * 4, rgb, a)

# Rectangle plein à coins arrondis (rayon r), avec mélange alpha et bords anti-crénelés.
func fill_round(p: Pixmap, x: int, y: int, w: int, h: int, r: int, c: int):
    if w <= 0 or h <= 0:
        return
    r = _limit_radius(w, h, r)
    if r <= 0:
        blend(p, x, y, w, h, c)
        return
    ca := (c >> 24) & 255
    rgb := c & MASK_RGB
    blend(p, x, y + r, w, h - 2 * r, c)
    blend(p, x + r, y, w - 2 * r, r, c)
    blend(p, x + r, y + h - r, w - 2 * r, r, c)
    t := _corner(r)
    j := 0
    while j < r:
        i := 0
        while i < r:
            cov := __load8(t + j * r + i)
            if cov != 0:
                _corner_px(p, x + i, y + j, rgb, ca, cov)
                _corner_px(p, x + w - 1 - i, y + j, rgb, ca, cov)
                _corner_px(p, x + i, y + h - 1 - j, rgb, ca, cov)
                _corner_px(p, x + w - 1 - i, y + h - 1 - j, rgb, ca, cov)
            i += 1
        j += 1

# Contour (épaisseur t) d'un rectangle à coins arrondis, dans le rectangle lui-même.
func stroke_round(p: Pixmap, x: int, y: int, w: int, h: int, r: int, t: int, c: int):
    if w <= 0 or h <= 0 or t <= 0:
        return
    r = _limit_radius(w, h, r)
    ca := (c >> 24) & 255
    rgb := c & MASK_RGB
    if r <= 0:
        blend(p, x, y, w, t, c)
        blend(p, x, y + h - t, w, t, c)
        blend(p, x, y + t, t, h - 2 * t, c)
        blend(p, x + w - t, y + t, t, h - 2 * t, c)
        return
    blend(p, x + r, y, w - 2 * r, t, c)
    blend(p, x + r, y + h - t, w - 2 * r, t, c)
    blend(p, x, y + r, t, h - 2 * r, c)
    blend(p, x + w - t, y + r, t, h - 2 * r, c)
    outer := _corner(r)
    ri := r - t
    inner := 0
    if ri > 0:
        inner = _corner(ri)
    j := 0
    while j < r:
        i := 0
        while i < r:
            cov := __load8(outer + j * r + i)
            if cov != 0:
                if ri > 0 and i >= t and j >= t:
                    cov -= __load8(inner + (j - t) * ri + (i - t))
                if cov > 0:
                    _corner_px(p, x + i, y + j, rgb, ca, cov)
                    _corner_px(p, x + w - 1 - i, y + j, rgb, ca, cov)
                    _corner_px(p, x + i, y + h - 1 - j, rgb, ca, cov)
                    _corner_px(p, x + w - 1 - i, y + h - 1 - j, rgb, ca, cov)
            i += 1
        j += 1

# Rend transparents (anti-crénelage) les quatre coins d'une surface : fenêtres et tuiles à coins arrondis.
func round_corners(p: Pixmap, r: int):
    round_corners_some(p, r, 15)

# Idem pour certains coins seulement : which = 1 haut gauche, 2 haut droit, 4 bas gauche, 8 bas droit (somme).
func round_corners_some(p: Pixmap, r: int, which: int):
    r = _limit_radius(p.width, p.height, r)
    if r <= 0 or p.bpp != 4:
        return
    t := _corner(r)
    j := 0
    while j < r:
        i := 0
        while i < r:
            cov := __load8(t + j * r + i)
            if cov != 255:
                if (which & 1) != 0:
                    _scale_alpha(p, i, j, cov)
                if (which & 2) != 0:
                    _scale_alpha(p, p.width - 1 - i, j, cov)
                if (which & 4) != 0:
                    _scale_alpha(p, i, p.height - 1 - j, cov)
                if (which & 8) != 0:
                    _scale_alpha(p, p.width - 1 - i, p.height - 1 - j, cov)
            i += 1
        j += 1

func _scale_alpha(p: Pixmap, x: int, y: int, cov: int):
    a := p.addr + y * p.stride + x * 4
    v := __load32(a)
    na := (((v >> 24) & 255) * cov + 127) // 255
    __store32(a, (na << 24) | (v & MASK_RGB))

_shadows: dict[int, int] := {}

# Table d'intensité d'une ombre de flou b : intensité (0..255) selon la distance au bord en demi-pixels (0..2b).
func _shadow_table(b: int) -> int:
    if contains_key(_shadows, b):
        return _shadows[b]
    t := __mmap(2 * b + 16)
    d := 0
    while d <= 2 * b:
        u := 255 - d * 255 // (2 * b)
        if u < 0:
            u = 0
        v := u * u // 255                          # chute douce (cubique)
        v = v * u // 255
        __store8(t + d, v)
        d += 1
    _shadows[b] = t
    return t

# Ombre portée autour du rectangle arrondi (x, y, w, h, rayon r) : halo de flou b pixels, de couleur color
# (son alpha donne l'intensité maximale au bord), décalé de (ox, oy). Rien n'est dessiné sous le rectangle.
func shadow(p: Pixmap, x: int, y: int, w: int, h: int, r: int, b: int, ox: int, oy: int, color: int):
    if b <= 0 or w <= 0 or h <= 0:
        return
    ca := (color >> 24) & 255
    if ca == 0:
        return
    rgb := color & MASK_RGB
    tab := _shadow_table(b)
    sx := x + ox
    sy := y + oy
    cr := _limit_radius(w, h, r)
    ex0 := sx - b
    ey0 := sy - b
    ex1 := sx + w + b
    ey1 := sy + h + b
    if ex0 < p.cx0:
        ex0 = p.cx0
    if ey0 < p.cy0:
        ey0 = p.cy0
    if ex1 > p.cx1:
        ex1 = p.cx1
    if ey1 > p.cy1:
        ey1 = p.cy1
    inner_w := w - 2 * cr          # demi-pixels : largeur du « noyau » (le rectangle sans le rayon des coins)
    inner_h := h - 2 * cr
    yy := ey0
    while yy < ey1:
        qy := (2 * yy + 1 - (2 * sy + h))
        if qy < 0:
            qy = 0 - qy
        qy -= inner_h
        row := p.addr + yy * p.stride
        xx := ex0
        xend := ex1
        skip_from := 0
        skip_to := 0
        if qy <= 0:        # lignes de la partie droite : seuls les bords gauche et droit comptent
            skip_from = sx + 1
            skip_to = sx + w - 1
        while xx < xend:
            if skip_to > skip_from and xx >= skip_from and xx < skip_to:
                xx = skip_to
                continue
            qx := (2 * xx + 1 - (2 * sx + w))
            if qx < 0:
                qx = 0 - qx
            qx -= inner_w
            px := qx
            py := qy
            if px < 0:
                px = 0
            if py < 0:
                py = 0
            dh := 0
            if px == 0:
                dh = py
            elif py == 0:
                dh = px
            else:
                dh = _isqrt(px * px + py * py)
            dh -= 2 * cr
            if dh > 0 and dh <= 2 * b:
                v := __load8(tab + dh)
                if v > 0:
                    _blend_px(row + xx * 4, rgb, (v * ca + 127) // 255)
            xx += 1
        yy += 1

# ------------------------------------------------------------------------------------------ polygones

# Remplit un polygone (suite x0, y0, x1, y1, ... de sommets en pixels) avec bords anti-crénelés (4 sous-lignes,
# couverture horizontale exacte au 1/16 de pixel), couleur c avec mélange alpha.
func fill_poly(p: Pixmap, pts: list[int], c: int):
    n := len(pts) // 2
    if n < 3:
        return
    ca := (c >> 24) & 255
    rgb := c & MASK_RGB
    ymin := pts[1]
    ymax := pts[1]
    i := 1
    while i < n:
        if pts[2 * i + 1] < ymin:
            ymin = pts[2 * i + 1]
        if pts[2 * i + 1] > ymax:
            ymax = pts[2 * i + 1]
        i += 1
    if ymin < p.cy0:
        ymin = p.cy0
    if ymax >= p.cy1:
        ymax = p.cy1 - 1
    acc := __mmap(p.width * 2 + 16)
    xs: list[int] := []
    y := ymin
    while y <= ymax:
        __zero(acc, p.width * 2 + 8)
        lo := p.width
        hi := -1
        sub := 0
        while sub < 4:
            sy16 := y * 16 + sub * 4 + 2           # ordonnée de l'échantillon, en 1/16 de pixel
            xs = []
            e := 0
            while e < n:
                nx := e + 1
                if nx == n:
                    nx = 0
                ya := pts[2 * e + 1] * 16
                yb := pts[2 * nx + 1] * 16
                xa := pts[2 * e] * 16
                xb := pts[2 * nx] * 16
                if (ya <= sy16 and sy16 < yb) or (yb <= sy16 and sy16 < ya):
                    xc := xa + (sy16 - ya) * (xb - xa) // (yb - ya)
                    # insertion triée
                    append(xs, xc)
                    k := len(xs) - 1
                    while k > 0 and xs[k - 1] > xs[k]:
                        tmp := xs[k]
                        xs[k] = xs[k - 1]
                        xs[k - 1] = tmp
                        k -= 1
                e += 1
            k2 := 0
            while k2 + 1 < len(xs):
                xa16 := xs[k2]
                xb16 := xs[k2 + 1]
                k2 += 2
                if xb16 <= xa16:
                    continue
                if xa16 < p.cx0 * 16:
                    xa16 = p.cx0 * 16
                if xb16 > p.cx1 * 16:
                    xb16 = p.cx1 * 16
                if xb16 <= xa16:
                    continue
                px0 := xa16 >> 4
                px1 := (xb16 - 1) >> 4
                if px0 < lo:
                    lo = px0
                if px1 > hi:
                    hi = px1
                if px0 == px1:
                    v := __load16(acc + 2 * px0)
                    __store16(acc + 2 * px0, v + (xb16 - xa16) * 4)
                else:
                    v0 := __load16(acc + 2 * px0)
                    __store16(acc + 2 * px0, v0 + (16 - (xa16 & 15)) * 4)
                    xm := px0 + 1
                    while xm < px1:
                        vm := __load16(acc + 2 * xm)
                        __store16(acc + 2 * xm, vm + 64)
                        xm += 1
                    v1 := __load16(acc + 2 * px1)
                    __store16(acc + 2 * px1, v1 + (((xb16 - 1) & 15) + 1) * 4)
            sub += 1
        if hi >= lo:
            xx := lo
            while xx <= hi:
                v := __load16(acc + 2 * xx)
                if v > 0:
                    if v > 255:
                        v = 255
                    a := v
                    if ca != 255:
                        a = (v * ca + 127) // 255
                    _blend_px(p.addr + y * p.stride + xx * 4, rgb, a)
                xx += 1
        y += 1
    __munmap(acc, (p.width * 2 + 16 + 4095) & ~4095)

# ------------------------------------------------------------------------------------------ fichiers

class Blob:
    addr: int := 0
    size: int := 0
    map_size: int := 0

func _cpath(path: str) -> int:
    p := __str_addr(path)
    n := __load64(p)
    c := __alloc_raw(n + 1)
    __copy(c, p + 8, n)
    __store8(c + n, 0)
    return c

# Contenu d'un fichier en mémoire (mmap) ; null s'il est illisible.
func _read_blob(path: str) -> Blob?:
    fd := __syscall(2, _cpath(path), 0, 0)
    if fd < 0:
        return null
    st := __alloc_raw(144)
    if __syscall(5, fd, st) != 0:
        __syscall(3, fd)
        return null
    size := __load64(st + 48)
    b := Blob()
    b.size = size
    b.map_size = (size + 4095) & ~4095
    if b.map_size == 0:
        b.map_size = 4096
    b.addr = __mmap(b.map_size)
    got := 0
    while got < size:
        k := __syscall(0, fd, b.addr + got, size - got)
        if k <= 0:
            break
        got += k
    __syscall(3, fd)
    b.size = got
    return b

func _u32(a: int) -> int:
    return __load32(a)

# Surface vide (largeur 0) : résultat d'un chargement raté ; `ok` la reconnaît.
func _none() -> Pixmap:
    return Pixmap()

func ok(p: Pixmap) -> bool:
    return p.width > 0 and p.addr != 0

# Charge une image .alpx (ARGB ou masque) ; surface vide (`ok` faux) si absente ou invalide.
func load(path: str) -> Pixmap:
    b := _read_blob(path)
    if b == null:
        return _none()
    if b.size < 16 or __load32(b.addr) != 0x58504C41:      # « ALPX » : 'A' 'L' 'P' 'X' (petit-boutiste)
        __munmap(b.addr, b.map_size)
        return _none()
    w := __load32(b.addr + 4)
    h := __load32(b.addr + 8)
    kind := __load32(b.addr + 12)
    bpp := 4
    if kind == 1:
        bpp = 1
    if b.size < 16 + w * h * bpp:
        __munmap(b.addr, b.map_size)
        return _none()
    p := Pixmap()
    p.addr = b.addr + 16
    p.width = w
    p.height = h
    p.bpp = bpp
    p.stride = w * bpp
    p.base = b.addr
    p.size = b.map_size
    p.cx0 = 0
    p.cy0 = 0
    p.cx1 = w
    p.cy1 = h
    return p

# Ouvre un fichier spécial (tampon de trame /dev/fb0...) et le mappe en mémoire : surface w x h, pitch en octets.
# Surface vide (`ok` faux) si l'ouverture ou le mappage échoue.
func map_file(path: str, w: int, h: int, pitch: int) -> Pixmap:
    fd := __syscall(2, _cpath(path), 2, 0)
    if fd < 0:
        return _none()
    size := pitch * h
    a := __syscall(9, 0, size, 3, 1, fd, 0)
    if a < 0 and a > -4096:
        __syscall(3, fd)
        return _none()
    return wrap(a, w, h, pitch)

# Projette un descripteur déjà ouvert (tampon de trame /dev/fb0) : surface w x h, pitch en octets. destroy()
# rend la projection (changement de définition, de disposition des écrans), sans fermer le descripteur.
func map_fd(fd: int, w: int, h: int, pitch: int) -> Pixmap:
    size := pitch * h
    a := __syscall(9, 0, size, 3, 1, fd, 0)
    if a < 0 and a > -4096:
        return _none()
    p := wrap(a, w, h, pitch)
    p.base = a
    p.size = size
    return p

# ------------------------------------------------------------------------------------------ polices

func font_ok(f: Font) -> bool:
    return f.count > 0

# Charge une police .alfont ; police vide (`font_ok` faux) si absente ou invalide.
func load_font(path: str) -> Font:
    b := _read_blob(path)
    if b == null:
        return Font()
    if b.size < 32 or __load32(b.addr) != 0x4E464C41:      # « ALFN » : 'A' 'L' 'F' 'N' (petit-boutiste)
        __munmap(b.addr, b.map_size)
        return Font()
    f := Font()
    f.base = b.addr
    f.size = b.map_size
    f.count = __load32(b.addr + 8)
    f.ascent = __load32(b.addr + 12)
    f.descent = __load32(b.addr + 16)
    f.height = __load32(b.addr + 20)
    f.table = b.addr + 32
    f.masks = f.table + 20 * f.count
    f.lut = __mmap(768 * 8)
    i := 0
    while i < f.count:
        cp := __load32(f.table + 20 * i)
        if cp < 768:
            __store64(f.lut + 8 * cp, i + 1)
        i += 1
    return f

func font_height(f: Font) -> int:
    return f.height

func font_ascent(f: Font) -> int:
    return f.ascent

# Indice du glyphe de code cp dans la table (-1 : absent).
func _glyph(f: Font, cp: int) -> int:
    if cp < 768:
        return __load64(f.lut + 8 * cp) - 1
    lo := 0
    hi := f.count - 1
    while lo <= hi:
        mid := (lo + hi) // 2
        v := __load32(f.table + 20 * mid)
        if v == cp:
            return mid
        if v < cp:
            lo = mid + 1
        else:
            hi = mid - 1
    return -1

# Point de code UTF-8 en position i de la chaîne d'adresse a (longueur n) ; renvoie (code, longueur) empaquetés :
# code * 8 + longueur.
func _decode(a: int, n: int, i: int) -> int:
    b0 := __load8(a + i)
    if b0 < 128:
        return b0 * 8 + 1
    if b0 >= 240 and i + 3 < n:
        return (((b0 & 7) << 18) | ((__load8(a + i + 1) & 63) << 12) | ((__load8(a + i + 2) & 63) << 6) | (__load8(a + i + 3) & 63)) * 8 + 4
    if b0 >= 224 and i + 2 < n:
        return (((b0 & 15) << 12) | ((__load8(a + i + 1) & 63) << 6) | (__load8(a + i + 2) & 63)) * 8 + 3
    if b0 >= 192 and i + 1 < n:
        return (((b0 & 31) << 6) | (__load8(a + i + 1) & 63)) * 8 + 2
    return 63 * 8 + 1

# Largeur en pixels du texte s dans la police f.
func text_width(f: Font, s: str) -> int:
    a := __str_addr(s) + 8
    n := __load64(__str_addr(s))
    i := 0
    pen := 0
    while i < n:
        d := _decode(a, n, i)
        i += d & 7
        g := _glyph(f, d >> 3)
        if g < 0:
            g = _glyph(f, 63)
        if g >= 0:
            pen += __load16(f.table + 20 * g + 4)
    return (pen + 32) >> 6

# Dessine s avec le haut de la ligne en (x, y), teinté par color (alpha compris).
func draw_text(p: Pixmap, f: Font, x: int, y: int, s: str, color: int):
    draw_text_spaced(p, f, x, y, s, color, 0)

# Largeur de s avec un espacement supplémentaire de spacing pixels entre les caractères.
func text_width_spaced(f: Font, s: str, spacing: int) -> int:
    n := __load64(__str_addr(s))
    a := __str_addr(s) + 8
    i := 0
    count := 0
    while i < n:
        d := _decode(a, n, i)
        i += d & 7
        count += 1
    return text_width(f, s) + spacing * count

# Comme draw_text, avec spacing pixels de plus entre les caractères (titres en capitales espacées).
func draw_text_spaced(p: Pixmap, f: Font, x: int, y: int, s: str, color: int, spacing: int):
    ca := (color >> 24) & 255
    if ca == 0:
        return
    rgb := color & MASK_RGB
    a := __str_addr(s) + 8
    n := __load64(__str_addr(s))
    base := y + f.ascent
    if base - f.ascent >= p.cy1 or base + f.descent < p.cy0:
        return
    i := 0
    pen := x * 64
    while i < n:
        d := _decode(a, n, i)
        i += d & 7
        g := _glyph(f, d >> 3)
        if g < 0:
            g = _glyph(f, 63)
        if g < 0:
            continue
        e := f.table + 20 * g
        if __load16(e + 14) == 1: # glyphe TrueType pas encore rastérisé
            _ttf_glyph_raster(f, g)
        adv := __load16(e + 4)
        gw := __load16(e + 10)
        gh := __load16(e + 12)
        if gw > 0 and gh > 0:
            bx := __load16(e + 6)
            if bx >= 32768:
                bx -= 65536
            by := __load16(e + 8)
            if by >= 32768:
                by -= 65536
            gx := ((pen + 32) >> 6) + bx
            gy := base - by
            off := __load32(e + 16)
            x0 := gx
            y0 := gy
            sx := 0
            sy := 0
            ww := gw
            hh := gh
            if x0 < p.cx0:
                sx = p.cx0 - x0
                x0 = p.cx0
                ww -= sx
            if y0 < p.cy0:
                sy = p.cy0 - y0
                y0 = p.cy0
                hh -= sy
            if x0 + ww > p.cx1:
                ww = p.cx1 - x0
            if y0 + hh > p.cy1:
                hh = p.cy1 - y0
            if ww > 0 and hh > 0:
                ms := f.masks + off + sy * gw + sx
                dp := p.addr + y0 * p.stride + x0 * 4
                yy := 0
                while yy < hh:
                    sp := ms
                    q := dp
                    xx := 0
                    while xx < ww:
                        m := __load8(sp)
                        if m != 0:
                            if ca != 255:
                                m = (m * ca + 127) // 255
                            _blend_px(q, rgb, m)
                        sp += 1
                        q += 4
                        xx += 1
                    ms += gw
                    dp += p.stride
                    yy += 1
        pen += adv + spacing * 64

# ------------------------------------------------------------------------------------------ TrueType

# Police TrueType (.ttf) rastérisée à size pixels par cadratin : même structure en mémoire qu'une police .alfont
# (table des glyphes + masques 8 bits), pour les plages de caractères de l'interface. Contours quadratiques
# (tables glyf / loca, glyphes composés compris), cmap formats 4 et 12, métriques hhea / hmtx ; anticrénelage
# par 5 sous-lignes par pixel et couverture horizontale exacte, règle d'enroulement non nul. Sans hinting.
# Police vide (`font_ok` faux) si le fichier est absent ou n'est pas une police TrueType lisible.
const _TTF_RANGES := [32, 126, 160, 383, 8208, 8231, 8240, 8240, 8249, 8250, 8364, 8364, 8482, 8482, 8592, 8595,
    8722, 8722, 8226, 8226, 9632, 9679, 9472, 9599, 10003, 10004, 10005, 10005]
const _SS := 5

class _Ttf:
    base: int := 0
    size: int := 0
    upem: int := 1000
    loca_long: bool := false
    num_glyphs: int := 0
    num_hm: int := 0
    hmtx: int := 0
    loca: int := 0
    glyf: int := 0
    cmap: int := 0
    cmap_fmt: int := 0
    asc: int := 0
    desc: int := 0

class _Outline:
    xs: list[int] := []
    ys: list[int] := []
    on: list[bool] := []
    ends: list[int] := []

func _u8(a: int) -> int:
    return __load8(a)

func _be16(a: int) -> int:
    return (__load8(a) << 8) | __load8(a + 1)

func _bes16(a: int) -> int:
    v := _be16(a)
    if v >= 32768:
        return v - 65536
    return v

func _be32(a: int) -> int:
    return (_be16(a) << 16) | _be16(a + 2)

func _fdiv(a: int, b: int) -> int:
    if a >= 0:
        return a // b
    return -((-a + b - 1) // b)

func _cdiv(a: int, b: int) -> int:
    return -_fdiv(-a, b)

func _ttf_table(t: _Ttf, tag: str) -> int:
    n := _be16(t.base + 4)
    tp := __str_addr(tag) + 8
    want := (__load8(tp) << 24) | (__load8(tp + 1) << 16) | (__load8(tp + 2) << 8) | __load8(tp + 3)
    i := 0
    while i < n:
        r := t.base + 12 + 16 * i
        if _be32(r) == want:
            off := _be32(r + 8)
            if off + _be32(r + 12) > t.size:
                return 0
            return t.base + off
        i += 1
    return 0

func _ttf_open(path: str) -> _Ttf?:
    b := _read_blob(path)
    if b == null:
        return null
    t := _Ttf()
    t.base = b.addr
    t.size = b.size
    if t.size < 12:
        return null
    v := _be32(t.base)
    if v != 65536 and v != 1953658213: # 0x00010000 ou « true »
        return null
    head := _ttf_table(t, "head")
    hhea := _ttf_table(t, "hhea")
    maxp := _ttf_table(t, "maxp")
    t.hmtx = _ttf_table(t, "hmtx")
    t.loca = _ttf_table(t, "loca")
    t.glyf = _ttf_table(t, "glyf")
    cmap := _ttf_table(t, "cmap")
    if head == 0 or hhea == 0 or maxp == 0 or t.hmtx == 0 or t.loca == 0 or t.glyf == 0 or cmap == 0:
        return null
    t.upem = _be16(head + 18)
    if t.upem <= 0:
        return null
    t.loca_long = _bes16(head + 50) != 0
    t.asc = _bes16(hhea + 4)
    t.desc = _bes16(hhea + 6)
    t.num_hm = _be16(hhea + 34)
    t.num_glyphs = _be16(maxp + 4)
    # sous-table Unicode : (3, 10) format 12, sinon (3, 1) / (0, x) format 4
    n := _be16(cmap + 2)
    best := 0
    fmt := 0
    i := 0
    while i < n:
        r := cmap + 4 + 8 * i
        plat := _be16(r)
        enc := _be16(r + 2)
        st := cmap + _be32(r + 4)
        f := _be16(st)
        if f == 12 and (plat == 3 or plat == 0):
            best = st
            fmt = 12
        elif f == 4 and fmt != 12 and (plat == 3 or plat == 0) and (plat != 3 or enc == 1):
            best = st
            fmt = 4
        i += 1
    if best == 0:
        return null
    t.cmap = best
    t.cmap_fmt = fmt
    return t

func _ttf_glyph_index(t: _Ttf, cp: int) -> int:
    s := t.cmap
    if t.cmap_fmt == 12:
        n := _be32(s + 12)
        i := 0
        while i < n:
            g := s + 16 + 12 * i
            lo := _be32(g)
            hi := _be32(g + 4)
            if cp >= lo and cp <= hi:
                return _be32(g + 8) + (cp - lo)
            i += 1
        return 0
    if cp > 65535:
        return 0
    segx2 := _be16(s + 6)
    ends := s + 14
    starts := ends + segx2 + 2
    deltas := starts + segx2
    ranges := deltas + segx2
    i := 0
    while i < segx2:
        e := _be16(ends + i)
        if cp <= e:
            st := _be16(starts + i)
            if cp < st:
                return 0
            ro := _be16(ranges + i)
            if ro == 0:
                return (cp + _be16(deltas + i)) & 65535
            ga := ranges + i + ro + 2 * (cp - st)
            g := _be16(ga)
            if g == 0:
                return 0
            return (g + _be16(deltas + i)) & 65535
        i += 2
    return 0

func _ttf_advance(t: _Ttf, g: int) -> int:
    if g < t.num_hm:
        return _be16(t.hmtx + 4 * g)
    return _be16(t.hmtx + 4 * (t.num_hm - 1))

func _ttf_glyph_at(t: _Ttf, g: int) -> list[int]:
    if g < 0 or g >= t.num_glyphs:
        return [0, 0]
    if t.loca_long:
        return [_be32(t.loca + 4 * g), _be32(t.loca + 4 * g + 4)]
    return [2 * _be16(t.loca + 2 * g), 2 * _be16(t.loca + 2 * g + 2)]

# Contour du glyphe g ajouté à o, transformé par (a, b, c, d en 1/16384 ; dx, dy en unités de la police).
func _ttf_outline(t: _Ttf, g: int, o: _Outline, a: int, b: int, c: int, d: int, dx: int, dy: int, depth: int):
    if depth > 6:
        return
    r := _ttf_glyph_at(t, g)
    if r[1] <= r[0]:
        return
    p := t.glyf + r[0]
    nc := _bes16(p)
    if nc >= 0:
        ends: list[int] := []
        i := 0
        while i < nc:
            append(ends, _be16(p + 10 + 2 * i))
            i += 1
        if nc == 0:
            return
        npts := ends[nc - 1] + 1
        q := p + 10 + 2 * nc
        q += 2 + _be16(q) # instructions ignorées
        flags: list[int] := []
        while len(flags) < npts:
            f := _u8(q)
            q += 1
            append(flags, f)
            if (f & 8) != 0:
                rep := _u8(q)
                q += 1
                k := 0
                while k < rep and len(flags) < npts:
                    append(flags, f)
                    k += 1
        xs: list[int] := []
        x := 0
        for f in flags:
            if (f & 2) != 0:
                v := _u8(q)
                q += 1
                if (f & 16) == 0:
                    v = -v
                x += v
            elif (f & 16) == 0:
                x += _bes16(q)
                q += 2
            append(xs, x)
        y := 0
        base := len(o.xs)
        k := 0
        for f in flags:
            if (f & 4) != 0:
                v := _u8(q)
                q += 1
                if (f & 32) == 0:
                    v = -v
                y += v
            elif (f & 32) == 0:
                y += _bes16(q)
                q += 2
            px := xs[k]
            append(o.xs, (a * px + c * y) // 16384 + dx)
            append(o.ys, (b * px + d * y) // 16384 + dy)
            append(o.on, (f & 1) != 0)
            k += 1
        for e in ends:
            append(o.ends, base + e)
        return
    # glyphe composé
    q := p + 10
    more := true
    while more:
        fl := _be16(q)
        sub := _be16(q + 2)
        q += 4
        ox := 0
        oy := 0
        if (fl & 1) != 0:
            ox = _bes16(q)
            oy = _bes16(q + 2)
            q += 4
        else:
            ox = _u8(q)
            oy = _u8(q + 1)
            if ox >= 128:
                ox -= 256
            if oy >= 128:
                oy -= 256
            q += 2
        sa := 16384
        sb := 0
        sc := 0
        sd := 16384
        if (fl & 8) != 0:
            sa = _bes16(q)
            sd = sa
            q += 2
        elif (fl & 64) != 0:
            sa = _bes16(q)
            sd = _bes16(q + 2)
            q += 4
        elif (fl & 128) != 0:
            sa = _bes16(q)
            sb = _bes16(q + 2)
            sc = _bes16(q + 4)
            sd = _bes16(q + 6)
            q += 8
        if (fl & 2) == 0: # points appariés : non pris en charge, décalage nul
            ox = 0
            oy = 0
        na := (a * sa + c * sb) // 16384
        nb := (b * sa + d * sb) // 16384
        nc2 := (a * sc + c * sd) // 16384
        nd := (b * sc + d * sd) // 16384
        ndx := (a * ox + c * oy) // 16384 + dx
        ndy := (b * ox + d * oy) // 16384 + dy
        _ttf_outline(t, sub, o, na, nb, nc2, nd, ndx, ndy, depth + 1)
        more = (fl & 32) != 0

# Arêtes (x0, y0, x1, y1 en 1/256 de pixel, y vers le bas) d'un contour, courbes aplaties en segments.
func _ttf_edges(o: _Outline, size: int, upem: int, gx0: int, gy1: int, out: list[int]):
    start := 0
    for e in o.ends:
        n := e - start + 1
        if n >= 2:
            # premier point sur la courbe (ou milieu de deux points de contrôle)
            first := -1
            k := 0
            while k < n:
                if o.on[start + k]:
                    first = k
                    break
                k += 1
            sx := 0
            sy := 0
            if first < 0:
                sx = _tx(o.xs[start], size, upem, gx0) // 2 + _tx(o.xs[start + 1], size, upem, gx0) // 2
                sy = _ty(o.ys[start], size, upem, gy1) // 2 + _ty(o.ys[start + 1], size, upem, gy1) // 2
                first = 0
            else:
                sx = _tx(o.xs[start + first], size, upem, gx0)
                sy = _ty(o.ys[start + first], size, upem, gy1)
            cx := sx
            cy := sy
            ctrl := false
            qx := 0
            qy := 0
            i := 1
            while i <= n:
                j := start + (first + i) % n
                px := _tx(o.xs[j], size, upem, gx0)
                py := _ty(o.ys[j], size, upem, gy1)
                if o.on[j]:
                    if ctrl:
                        _quad(cx, cy, qx, qy, px, py, out)
                        ctrl = false
                    else:
                        _line(cx, cy, px, py, out)
                    cx = px
                    cy = py
                else:
                    if ctrl:
                        mx := (qx + px) // 2
                        my := (qy + py) // 2
                        _quad(cx, cy, qx, qy, mx, my, out)
                        cx = mx
                        cy = my
                    qx = px
                    qy = py
                    ctrl = true
                i += 1
            if ctrl:
                _quad(cx, cy, qx, qy, sx, sy, out)
            elif cx != sx or cy != sy:
                _line(cx, cy, sx, sy, out)
        start = e + 1

func _tx(x: int, size: int, upem: int, gx0: int) -> int:
    return _fdiv(x * size * 256, upem) - gx0 * 256

func _ty(y: int, size: int, upem: int, gy1: int) -> int:
    return gy1 * 256 - _fdiv(y * size * 256, upem)

func _line(x0: int, y0: int, x1: int, y1: int, out: list[int]):
    if y0 == y1:
        return
    append(out, x0)
    append(out, y0)
    append(out, x1)
    append(out, y1)

func _quad(x0: int, y0: int, cx: int, cy: int, x1: int, y1: int, out: list[int]):
    steps := 6
    px := x0
    py := y0
    k := 1
    while k <= steps:
        # B(t) = (1-t)^2 P0 + 2t(1-t) C + t^2 P1, t = k / steps
        u := steps - k
        nx := (u * u * x0 + 2 * k * u * cx + k * k * x1) // (steps * steps)
        ny := (u * u * y0 + 2 * k * u * cy + k * k * y1) // (steps * steps)
        _line(px, py, nx, ny, out)
        px = nx
        py = ny
        k += 1

# Couverture (0..255) de chaque pixel d'un glyphe w x h, écrite en dst.
func _raster(edges: list[int], w: int, h: int, dst: int):
    acc: list[int] := []
    xs: list[int] := []
    dirs: list[int] := []
    row := 0
    while row < h:
        acc = [0 for i in 0..w]
        sub := 0
        while sub < _SS:
            y := row * 256 + (2 * sub + 1) * 256 // (2 * _SS)
            xs = []
            dirs = []
            i := 0
            while i < len(edges):
                y0 := edges[i + 1]
                y1 := edges[i + 3]
                if (y0 <= y and y < y1) or (y1 <= y and y < y0):
                    x0 := edges[i]
                    x1 := edges[i + 2]
                    x := x0 + (y - y0) * (x1 - x0) // (y1 - y0)
                    d := 1
                    if y1 < y0:
                        d = -1
                    # insertion triée
                    k := len(xs)
                    append(xs, x)
                    append(dirs, d)
                    while k > 0 and xs[k - 1] > x:
                        xs[k] = xs[k - 1]
                        dirs[k] = dirs[k - 1]
                        k -= 1
                    xs[k] = x
                    dirs[k] = d
                i += 4
            wind := 0
            j := 0
            while j < len(xs):
                prev := wind
                wind += dirs[j]
                if prev == 0 and wind != 0:
                    sx := xs[j]
                    k := j + 1
                    w2 := wind
                    while k < len(xs) and w2 != 0:
                        w2 += dirs[k]
                        if w2 == 0:
                            break
                        k += 1
                    ex := sx
                    if k < len(xs):
                        ex = xs[k]
                    _span(acc, w, sx, ex)
                    wind = 0
                    j = k + 1
                    continue
                j += 1
            sub += 1
        x := 0
        while x < w:
            v := acc[x] * 255 // (256 * _SS)
            if v > 255:
                v = 255
            __store8(dst + row * w + x, v)
            x += 1
        row += 1

func _span(acc: list[int], w: int, a: int, b: int):
    if b <= a:
        return
    if a < 0:
        a = 0
    if b > w * 256:
        b = w * 256
    if b <= a:
        return
    p0 := a >> 8
    p1 := b >> 8
    if p0 == p1:
        acc[p0] = acc[p0] + (b - a)
        return
    acc[p0] = acc[p0] + 256 - (a & 255)
    p := p0 + 1
    while p < p1:
        acc[p] = acc[p] + 256
        p += 1
    if p1 < w:
        acc[p1] = acc[p1] + (b & 255)

_ttfs: list[_Ttf] := []

# Rastérise le glyphe d'indice gi (table de la police) : contour, boîte en pixels, masque 8 bits.
func _ttf_glyph_raster(f: Font, gi: int):
    e := f.table + 20 * gi
    __store16(e + 14, 0)
    if f.ttf < 0:
        return
    t := _ttfs[f.ttf]
    size := f.px
    lim := 2 * size + 8
    g := _ttf_glyph_index(t, __load32(e))
    o := _Outline()
    o.xs = []
    o.ys = []
    o.on = []
    o.ends = []
    _ttf_outline(t, g, o, 16384, 0, 0, 16384, 0, 0, 0)
    if len(o.xs) == 0:
        return
    xmin := o.xs[0]
    xmax := o.xs[0]
    ymin := o.ys[0]
    ymax := o.ys[0]
    for x in o.xs:
        if x < xmin:
            xmin = x
        if x > xmax:
            xmax = x
    for y in o.ys:
        if y < ymin:
            ymin = y
        if y > ymax:
            ymax = y
    gx0 := _fdiv(xmin * size, t.upem)
    gx1 := _cdiv(xmax * size, t.upem)
    gy0 := _fdiv(ymin * size, t.upem)
    gy1 := _cdiv(ymax * size, t.upem)
    w := gx1 - gx0
    h := gy1 - gy0
    if w > lim:
        w = lim
    if h > lim:
        h = lim
    if w <= 0 or h <= 0:
        return
    edges: list[int] := []
    _ttf_edges(o, size, t.upem, gx0, gy1, edges)
    _raster(edges, w, h, f.masks + __load32(e + 16))
    __store16(e + 6, gx0 & 65535)
    __store16(e + 8, gy1 & 65535)
    __store16(e + 10, w)
    __store16(e + 12, h)

func load_ttf(path: str, size: int) -> Font:
    return load_ttf_ranges(path, size, _TTF_RANGES)

# Comme load_ttf, pour les plages de points de code données ([début, fin, début, fin...], triées ou non) :
# alphabets supplémentaires (grec, cyrillique, latin étendu...) pour le texte des documents.
func load_ttf_ranges(path: str, size: int, ranges: list[int]) -> Font:
    if size <= 0:
        return Font()
    tt := _ttf_open(path)
    if tt == null:
        return Font()
    t: _Ttf := tt
    cps: list[int] := []
    i := 0
    while i + 1 < len(ranges):
        cp := ranges[i]
        while cp <= ranges[i + 1]:
            if cp != 173 and _ttf_glyph_index(t, cp) != 0:
                append(cps, cp)
            cp += 1
        i += 2
    # tri des points de code (recherche dichotomique de _glyph au-delà de 767)
    k := 1
    while k < len(cps):
        v := cps[k]
        j := k
        while j > 0 and cps[j - 1] > v:
            cps[j] = cps[j - 1]
            j -= 1
        cps[j] = v
        k += 1
    count := len(cps)
    if count == 0:
        return Font()
    lim := 2 * size + 8
    total := 32 + 20 * count + count * lim * lim
    base := _map(total)
    f := Font()
    f.base = base
    f.size = (total + 4095) & ~4095
    f.count = count
    f.ascent = _cdiv(t.asc * size, t.upem)
    f.descent = _cdiv(-t.desc * size, t.upem)
    extra := size // 8
    if extra < 1:
        extra = 1
    f.height = f.ascent + f.descent + extra
    f.table = base + 32
    f.masks = f.table + 20 * count
    gi := 0
    while gi < count:
        cp := cps[gi]
        g := _ttf_glyph_index(t, cp)
        e := f.table + 20 * gi
        adv := (_ttf_advance(t, g) * size * 64 + t.upem // 2) // t.upem
        __store32(e, cp)
        __store16(e + 4, adv & 65535)
        __store16(e + 14, 1)               # à rastériser au premier affichage (_ttf_glyph_raster)
        __store32(e + 16, gi * lim * lim) # place réservée du masque (pages allouées à la demande)
        gi += 1
    f.ttf = len(_ttfs)
    f.px = size
    append(_ttfs, t)
    f.lut = __mmap(768 * 8)
    i = 0
    while i < count:
        cp := __load32(f.table + 20 * i)
        if cp < 768:
            __store64(f.lut + 8 * cp, i + 1)
        i += 1
    return f

# Texte tronqué avec « … » pour tenir dans maxw pixels.
func fit_text(f: Font, s: str, maxw: int) -> str:
    if text_width(f, s) <= maxw:
        return s
    ell := "…"
    ew := text_width(f, ell)
    a := __str_addr(s) + 8
    n := __load64(__str_addr(s))
    i := 0
    pen := 0
    cut := 0
    while i < n:
        d := _decode(a, n, i)
        g := _glyph(f, d >> 3)
        if g < 0:
            g = _glyph(f, 63)
        adv := 0
        if g >= 0:
            adv = __load16(f.table + 20 * g + 4)
        if ((pen + adv + 32) >> 6) + ew > maxw:
            break
        pen += adv
        i += d & 7
        cut = i
    r := __rt_str_new(cut)
    __copy(r + 8, a, cut)
    return __as_str(r) + ell

# ------------------------------------------------------------------------------------------ enregistrement

_crc: list[int] := []

func _crc_table():
    if len(_crc) > 0:
        return
    n := 0
    while n < 256:
        c := n
        k := 0
        while k < 8:
            if (c & 1) != 0:
                c = 0xEDB88320 ^ (c >> 1)
            else:
                c = c >> 1
            k += 1
        append(_crc, c)
        n += 1

func _crc32(addr: int, n: int, seed: int) -> int:
    _crc_table()
    c := seed ^ 0xFFFFFFFF
    i := 0
    while i < n:
        c = _crc[(c ^ __load8(addr + i)) & 255] ^ (c >> 8)
        i += 1
    return c ^ 0xFFFFFFFF

func _put_be32(a: int, v: int):
    __store8(a, (v >> 24) & 255)
    __store8(a + 1, (v >> 16) & 255)
    __store8(a + 2, (v >> 8) & 255)
    __store8(a + 3, v & 255)

func _write_all(fd: int, addr: int, n: int) -> bool:
    done := 0
    while done < n:
        k := __syscall(1, fd, addr + done, n - done)
        if k <= 0:
            return false
        done += k
    return true

func _create_file(path: str) -> int:
    return __syscall(2, _cpath(path), 577, 420)      # O_WRONLY | O_CREAT | O_TRUNC, 0644

# Enregistre la surface au format .alpx (ARGB brut, relu sans recopie par load) ; vrai si réussi. Rapide : sert
# aux captures d'écran successives (enregistrement de l'écran).
func save_alpx(p: Pixmap, path: str) -> bool:
    if p.bpp != 4 or p.width <= 0 or p.height <= 0:
        return false
    fd := _create_file(path)
    if fd < 0:
        return false
    head := __mmap(16)
    __store32(head, 0x58504C41)
    __store32(head + 4, p.width)
    __store32(head + 8, p.height)
    __store32(head + 12, 0)
    ok := _write_all(fd, head, 16)
    __munmap(head, 16)
    if ok and p.stride == p.width * 4:
        ok = _write_all(fd, p.addr, p.width * p.height * 4)
    else:
        y := 0
        while ok and y < p.height:
            ok = _write_all(fd, p.addr + y * p.stride, p.width * 4)
            y += 1
    __syscall(3, fd)
    return ok

# Enregistre la surface en PNG (RGB 8 bits, blocs « stockés » non compressés). Vrai si réussi.
func save_png(p: Pixmap, path: str) -> bool:
    if p.bpp != 4 or p.width <= 0 or p.height <= 0:
        return false
    w := p.width
    h := p.height
    rawlen := (w * 3 + 1) * h
    raw := __mmap(rawlen + 16)
    y := 0
    while y < h:
        o := raw + y * (w * 3 + 1)
        __store8(o, 0)
        s := p.addr + y * p.stride
        x := 0
        while x < w:
            v := __load32(s + 4 * x)
            __store8(o + 1 + 3 * x, (v >> 16) & 255)
            __store8(o + 2 + 3 * x, (v >> 8) & 255)
            __store8(o + 3 + 3 * x, v & 255)
            x += 1
        y += 1
    # flux zlib : en-tête, blocs stockés de 65535 octets au plus, Adler-32
    blocks := (rawlen + 65534) // 65535
    zlen := 2 + rawlen + 5 * blocks + 4
    out := __mmap(zlen + 8 + 33 + 12 + 12 + 12 + 64)
    a := out
    # signature + IHDR
    sig := 0x0A1A0A0D474E5089          # 89 50 4E 47 0D 0A 1A 0A en petit-boutiste
    __store64(a, sig)
    a += 8
    _put_be32(a, 13)
    __store8(a + 4, 73)
    __store8(a + 5, 72)
    __store8(a + 6, 68)
    __store8(a + 7, 82)
    _put_be32(a + 8, w)
    _put_be32(a + 12, h)
    __store8(a + 16, 8)
    __store8(a + 17, 2)
    __store8(a + 18, 0)
    __store8(a + 19, 0)
    __store8(a + 20, 0)
    _put_be32(a + 21, _crc32(a + 4, 17, 0))
    a += 25
    # IDAT
    _put_be32(a, zlen)
    __store8(a + 4, 73)
    __store8(a + 5, 68)
    __store8(a + 6, 65)
    __store8(a + 7, 84)
    z := a + 8
    __store8(z, 120)
    __store8(z + 1, 1)
    q := z + 2
    pos := 0
    s1 := 1
    s2 := 0
    while pos < rawlen:
        k := rawlen - pos
        last := 1
        if k > 65535:
            k = 65535
            last = 0
        __store8(q, last)
        __store8(q + 1, k & 255)
        __store8(q + 2, k >> 8)
        __store8(q + 3, (65535 - k) & 255)
        __store8(q + 4, (65535 - k) >> 8)
        __copy(q + 5, raw + pos, k)
        i := 0
        while i < k:
            s1 += __load8(raw + pos + i)
            if s1 >= 65521:
                s1 -= 65521
            s2 += s1
            if s2 >= 65521:
                s2 -= 65521
            i += 1
        q += 5 + k
        pos += k
    _put_be32(q, (s2 << 16) | s1)
    q += 4
    _put_be32(q, _crc32(a + 4, 4 + zlen, 0))
    q += 4
    # IEND
    _put_be32(q, 0)
    __store8(q + 4, 73)
    __store8(q + 5, 69)
    __store8(q + 6, 78)
    __store8(q + 7, 68)
    _put_be32(q + 8, 0xAE426082)       # CRC de « IEND »
    q += 12
    fd := _create_file(path)
    ok := false
    if fd >= 0:
        ok = _write_all(fd, out, q - out)
        __syscall(3, fd)
    __munmap(raw, (rawlen + 16 + 4095) & ~4095)
    __munmap(out, (zlen + 8 + 33 + 12 + 12 + 12 + 64 + 4095) & ~4095)
    return ok

# Somme de contrôle CRC-32 du contenu de la surface (tests : comparer deux rendus).
func checksum(p: Pixmap) -> int:
    c := 0
    y := 0
    while y < p.height:
        c = _crc32(p.addr + y * p.stride, p.width * p.bpp, c)
        y += 1
    return c

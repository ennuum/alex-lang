

# ---- flottants : opérations de la libm reproduites exactement ----

func __uf_neg(x: float) -> float:
    return __bits2f(__f2bits(x) ^ (-9223372036854775807 - 1))

func __uf_fabs(x: float) -> float:
    return __bits2f(__f2bits(x) & 9223372036854775807)

func __uf_ceil(x: float) -> float:
    return __uf_neg(__rt_floor(__uf_neg(x)))

# std::min / std::max (comparaison stricte, comme la bibliothèque C++)
func __uf_min(a: float, b: float) -> float:
    if b < a:
        return b
    return a

func __uf_max(a: float, b: float) -> float:
    if a < b:
        return b
    return a

func __ui_min(a: int, b: int) -> int:
    if b < a:
        return b
    return a

func __ui_max(a: int, b: int) -> int:
    if a < b:
        return b
    return a

func __uf_clamp01(v: float) -> float:
    if v < 0.0:
        return 0.0
    if v > 1.0:
        return 1.0
    return v

func __uf_finite(x: float) -> bool:
    return ((__f2bits(x) >> 52) & 2047) != 2047

# std::round : demi-entier loin de zéro.
func __uf_round(x: float) -> float:
    if not __uf_finite(x):
        return x
    ax := __uf_fabs(x)
    t := __rt_floor(ax)
    if ax - t >= 0.5:
        t = t + 1.0
    if x < 0.0:
        return __uf_neg(t)
    return t

# Arrondi au flottant 32 bits le plus proche (static_cast<float>).
func __uf_f32(x: float) -> float:
    return __nat_f32_value(__nat_f32_bits(x))

# hypot de la glibc (sysdeps/ieee754/dbl-64/e_hypot.c, sans FMA) : résultat identique bit pour bit.
func __uf_hypot_kernel(ax: float, ay: float) -> float:
    t1 := 0.0
    t2 := 0.0
    h := __fsqrt(ax * ax + ay * ay)
    if h <= 2.0 * ay:
        delta := h - ay
        t1 = ax * (2.0 * delta - ax)
        t2 = (delta - 2.0 * (ax - ay)) * delta
    else:
        delta := h - ax
        t1 = 2.0 * delta * (ax - 2.0 * ay)
        t2 = (4.0 * delta - ay) * ay + delta * delta
    h = h - (t1 + t2) / (2.0 * h)
    return h

func __uf_hypot(x0: float, y0: float) -> float:
    if not __uf_finite(x0) or not __uf_finite(y0):
        if (__f2bits(x0) & 9223372036854775807) == 9218868437227405312 or (__f2bits(y0) & 9223372036854775807) == 9218868437227405312:
            return __bits2f(9218868437227405312)
        return x0 + y0
    x := __uf_fabs(x0)
    y := __uf_fabs(y0)
    ax := x
    ay := y
    if x < y:
        ax = y
        ay = x
    scale := __bits2f(1905040627187597312)   # 0x1p-600
    large := __bits2f(6908521828386340864)   # 0x1p+511
    tiny := __bits2f(2310346608841064448)    # 0x1p-511
    eps := __bits2f(4363988038922010624)     # 0x1p-54
    if ax > large:
        if ay <= ax * eps:
            return ax + ay
        return __uf_hypot_kernel(ax * scale, ay * scale) / scale
    if ay < tiny:
        if ax >= ay / eps:
            return ax + ay
        return __uf_hypot_kernel(ax / scale, ay / scale) * scale
    if ay <= ax * eps:
        return ax + ay
    return __uf_hypot_kernel(ax, ay)

func __uf_get(p: int, off: int) -> float:
    return __bits2f(__load64(p + off))

func __uf_set(p: int, off: int, v: float):
    __store64(p + off, __f2bits(v))

# ---- couleurs : r | g << 8 | b << 16 | a << 24 ----

func __uc(r: int, g: int, b: int, a: int) -> int:
    return (r & 255) | ((g & 255) << 8) | ((b & 255) << 16) | ((a & 255) << 24)

func __uc_r(c: int) -> int:
    return c & 255

func __uc_g(c: int) -> int:
    return (c >> 8) & 255

func __uc_b(c: int) -> int:
    return (c >> 16) & 255

func __uc_a(c: int) -> int:
    return (c >> 24) & 255

func __uc_af(c: int) -> float:
    return __i2f(__uc_a(c)) / 255.0

# ---- surface : [0] l [8] h [16] pixels [24] m11 [32] m12 [40] m21 [48] m22 [56] dx [64] dy [72] opacité globale
# [80] clip actif [88] cx0 [96] cy0 [104] cx1 [112] cy1 ----

func __us_new(w: int, h: int) -> int:
    s := __alloc(128)
    __us_resize(s, w, h)
    __us_reset_state(s)
    return s

func __us_resize(s: int, w0: int, h0: int):
    w := __ui_max(1, w0)
    h := __ui_max(1, h0)
    __store64(s, w)
    __store64(s + 8, h)
    p := __alloc_raw(w * h * 4 + 8)
    __zero(p, w * h * 4)
    __store64(s + 16, p)
    __store64(s + 80, 0)

func __us_identity(s: int):
    __uf_set(s, 24, 1.0)
    __uf_set(s, 32, 0.0)
    __uf_set(s, 40, 0.0)
    __uf_set(s, 48, 1.0)
    __uf_set(s, 56, 0.0)
    __uf_set(s, 64, 0.0)

func __us_reset_state(s: int):
    __us_identity(s)
    __uf_set(s, 72, 1.0)
    __store64(s + 80, 0)

func __us_w(s: int) -> int:
    return __load64(s)

func __us_h(s: int) -> int:
    return __load64(s + 8)

func __us_px(s: int) -> int:
    return __load64(s + 16)

# Matrice (6 flottants à m) : x' = x*m11 + y*m21 + dx ; y' = x*m12 + y*m22 + dy. Résultat dans out[0], out[8].
func __um_apply(m: int, x: float, y: float, out: int):
    __uf_set(out, 0, x * __uf_get(m, 0) + y * __uf_get(m, 16) + __uf_get(m, 32))
    __uf_set(out, 8, x * __uf_get(m, 8) + y * __uf_get(m, 24) + __uf_get(m, 40))

func __um_scale(m: int) -> float:
    return __fsqrt(__uf_fabs(__uf_get(m, 0) * __uf_get(m, 24) - __uf_get(m, 8) * __uf_get(m, 16)))

func __um_invert(m: int, o: int) -> bool:
    m11 := __uf_get(m, 0)
    m12 := __uf_get(m, 8)
    m21 := __uf_get(m, 16)
    m22 := __uf_get(m, 24)
    dx := __uf_get(m, 32)
    dy := __uf_get(m, 40)
    det := m11 * m22 - m12 * m21
    if __uf_fabs(det) < 1e-12:
        return false
    id := 1.0 / det
    o11 := m22 * id
    o12 := __uf_neg(m12) * id
    o21 := __uf_neg(m21) * id
    o22 := m11 * id
    __uf_set(o, 0, o11)
    __uf_set(o, 8, o12)
    __uf_set(o, 16, o21)
    __uf_set(o, 24, o22)
    __uf_set(o, 32, __uf_neg(dx * o11 + dy * o21))
    __uf_set(o, 40, __uf_neg(dx * o12 + dy * o22))
    return true

func __um_is_translation(s: int) -> bool:
    return __uf_get(s, 24) == 1.0 and __uf_get(s, 32) == 0.0 and __uf_get(s, 40) == 0.0 and __uf_get(s, 48) == 1.0

# min / max (premier élément le plus petit, comme std::min_element) de 4 flottants consécutifs à p (pas de 16).
func __uf_min4(p: int) -> float:
    m := __uf_get(p, 0)
    k := 1
    while k < 4:
        v := __uf_get(p, 16 * k)
        if v < m:
            m = v
        k += 1
    return m

func __uf_max4(p: int) -> float:
    m := __uf_get(p, 0)
    k := 1
    while k < 4:
        v := __uf_get(p, 16 * k)
        if m < v:
            m = v
        k += 1
    return m

# Coins transformés (x0, y0), (x1, y0), (x0, y1), (x1, y1) : xs à q, ys à q + 8 (pas de 16).
func __us_corners(s: int, x0: float, y0: float, x1: float, y1: float, q: int):
    __um_apply(s + 24, x0, y0, q)
    __um_apply(s + 24, x1, y0, q + 16)
    __um_apply(s + 24, x0, y1, q + 32)
    __um_apply(s + 24, x1, y1, q + 48)

func __us_set_clip(s: int, x: float, y: float, w: float, h: float):
    q := __alloc_raw(64)
    __us_corners(s, x, y, x + w, y + h, q)
    nx0 := __f2i(__rt_floor(__uf_min4(q) + 0.5))
    ny0 := __f2i(__rt_floor(__uf_min4(q + 8) + 0.5))
    nx1 := __f2i(__rt_floor(__uf_max4(q) + 0.5))
    ny1 := __f2i(__rt_floor(__uf_max4(q + 8) + 0.5))
    if __load64(s + 80) != 0:
        nx0 = __ui_max(nx0, __load64(s + 88))
        ny0 = __ui_max(ny0, __load64(s + 96))
        nx1 = __ui_min(nx1, __load64(s + 104))
        ny1 = __ui_min(ny1, __load64(s + 112))
    __store64(s + 88, nx0)
    __store64(s + 96, ny0)
    __store64(s + 104, __ui_max(nx0, nx1))
    __store64(s + 112, __ui_max(ny0, ny1))
    __store64(s + 80, 1)

func __us_clear(s: int, c: int):
    p := __us_px(s)
    n := __us_w(s) * __us_h(s)
    v := __uc_r(c) | (__uc_g(c) << 8) | (__uc_b(c) << 16) | (__uc_a(c) << 24)
    i := 0
    while i < n:
        __store32(p + 4 * i, v)
        i += 1

func __us_blend(s: int, x: int, y: int, c: int, alpha0: float):
    alpha := alpha0
    w := __load64(s)
    if x < 0 or y < 0 or x >= w or y >= __load64(s + 8):
        return
    if __load64(s + 80) != 0:
        if x < __load64(s + 88) or x >= __load64(s + 104) or y < __load64(s + 96) or y >= __load64(s + 112):
            return
    if alpha <= 0.0:
        return
    if alpha > 1.0:
        alpha = 1.0
    d := __load64(s + 16) + (y * w + x) * 4
    cr := __uc_r(c)
    cg := __uc_g(c)
    cb := __uc_b(c)
    if __load8(d + 3) == 255:
        ia := __f2i(alpha * 256.0 + 0.5)
        if ia >= 256:
            __store8(d, cr)
            __store8(d + 1, cg)
            __store8(d + 2, cb)
            return
        ib := 256 - ia
        __store8(d, ((cr * ia + __load8(d) * ib + 128) >> 8) & 255)
        __store8(d + 1, ((cg * ia + __load8(d + 1) * ib + 128) >> 8) & 255)
        __store8(d + 2, ((cb * ia + __load8(d + 2) * ib + 128) >> 8) & 255)
        return
    da := __i2f(__load8(d + 3)) / 255.0
    oa := alpha + da * (1.0 - alpha)
    if oa <= 0.0:
        return
    k := da * (1.0 - alpha)
    __store8(d, __f2i((__i2f(cr) * alpha + __i2f(__load8(d)) * k) / oa + 0.5) & 255)
    __store8(d + 1, __f2i((__i2f(cg) * alpha + __i2f(__load8(d + 1)) * k) / oa + 0.5) & 255)
    __store8(d + 2, __f2i((__i2f(cb) * alpha + __i2f(__load8(d + 2)) * k) / oa + 0.5) & 255)
    __store8(d + 3, __f2i(oa * 255.0 + 0.5) & 255)

# Copie source-over de src en (dx, dy), sans transformation ni clip.
func __us_blit(s: int, src: int, dx: int, dy: int):
    sw := __us_w(src)
    sh := __us_h(src)
    w := __us_w(s)
    h := __us_h(s)
    sp := __us_px(src)
    dp := __us_px(s)
    y := 0
    while y < sh:
        ty := y + dy
        if ty >= 0 and ty < h:
            x := 0
            while x < sw:
                tx := x + dx
                if tx >= 0 and tx < w:
                    a := sp + (y * sw + x) * 4
                    sa8 := __load8(a + 3)
                    if sa8 != 0:
                        d := dp + (ty * w + tx) * 4
                        if sa8 == 255:
                            __store32(d, __load32(a))
                        else:
                            sa := __i2f(sa8) / 255.0
                            da := __i2f(__load8(d + 3)) / 255.0
                            oa := sa + da * (1.0 - sa)
                            k := da * (1.0 - sa)
                            c := 0
                            while c < 3:
                                __store8(d + c, __f2i((__i2f(__load8(a + c)) * sa + __i2f(__load8(d + c)) * k) / oa + 0.5) & 255)
                                c += 1
                            __store8(d + 3, __f2i(oa * 255.0 + 0.5) & 255)
                x += 1
        y += 1

# ---- peinture : [0] contour [8] couleur [16] opacité [24] épaisseur ----

func __up_new(stroke: bool, c: int, op: float, width: float) -> int:
    p := __alloc(32)
    if stroke:
        __store64(p, 1)
    __store64(p + 8, c)
    __uf_set(p, 16, op)
    __uf_set(p, 24, width)
    return p

# ---- distances signées : [0] genre, paramètres flottants à 8.. ----
# 0 rectangle arrondi (cx, cy, hw, hh, r) ; 1 cercle (cx, cy, r) ; 2 ellipse (cx, cy, rx, ry) ;
# 3 segment (x1, y1, x2, y2, épaisseur) ; 4 polyligne (segments, nombre, épaisseur)

func __ud_roundrect(x: float, y: float, w: float, h: float, radius: float) -> int:
    hw := __uf_fabs(w) * 0.5
    hh := __uf_fabs(h) * 0.5
    r := __uf_max(0.0, __uf_min(radius, __uf_min(hw, hh)))
    d := __alloc(48)
    __store64(d, 0)
    __uf_set(d, 8, x + w * 0.5)
    __uf_set(d, 16, y + h * 0.5)
    __uf_set(d, 24, hw)
    __uf_set(d, 32, hh)
    __uf_set(d, 40, r)
    return d

func __ud_rr_eval(d: int, px: float, py: float) -> float:
    r := __uf_get(d, 40)
    qx := __uf_fabs(px - __uf_get(d, 8)) - __uf_get(d, 24) + r
    qy := __uf_fabs(py - __uf_get(d, 16)) - __uf_get(d, 32) + r
    return __uf_hypot(__uf_max(qx, 0.0), __uf_max(qy, 0.0)) + __uf_min(__uf_max(qx, qy), 0.0) - r

func __ud_dist_seg(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    dx := bx - ax
    dy := by - ay
    l2 := dx * dx + dy * dy
    t := 0.0
    if l2 > 1e-18:
        t = __uf_clamp01(((px - ax) * dx + (py - ay) * dy) / l2)
    return __uf_hypot(px - (ax + t * dx), py - (ay + t * dy))

func __ud_eval(d: int, px: float, py: float) -> float:
    k := __load64(d)
    if k == 0:
        return __ud_rr_eval(d, px, py)
    if k == 1:
        return __uf_hypot(px - __uf_get(d, 8), py - __uf_get(d, 16)) - __uf_get(d, 24)
    if k == 2:
        rx := __uf_get(d, 24)
        ry := __uf_get(d, 32)
        x := px - __uf_get(d, 8)
        y := py - __uf_get(d, 16)
        k0 := __uf_hypot(x / rx, y / ry)
        k1 := __uf_hypot(x / (rx * rx), y / (ry * ry))
        if k1 > 1e-12:
            return k0 * (k0 - 1.0) / k1
        return __uf_neg(__uf_min(rx, ry))
    if k == 3:
        return __ud_dist_seg(px, py, __uf_get(d, 8), __uf_get(d, 16), __uf_get(d, 24), __uf_get(d, 32)) - __uf_get(d, 40) * 0.5
    segs := __load64(d + 8)
    n := __load64(d + 16)
    best := 1e18
    i := 0
    while i < n:
        q := segs + 32 * i
        v := __ud_dist_seg(px, py, __uf_get(q, 0), __uf_get(q, 8), __uf_get(q, 16), __uf_get(q, 24))
        if v < best:
            best = v
        i += 1
    return best - __uf_get(d, 24) * 0.5

# ---- couleurs par pixel : [0] genre ; 0 constante [8] ; 1 dégradé [8] c1 [16] c2 [24] x1 [32] y1 [40] dx [48] dy
# [56] l2 ; 2 image [8] image [16] x [24] y [32] l [40] h ----

func __ucol_const(c: int) -> int:
    k := __alloc(16)
    __store64(k + 8, c)
    return k

func __uf_lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t

func __ucol_eval(k: int, lx: float, ly: float) -> int:
    t0 := __load64(k)
    if t0 == 0:
        return __load64(k + 8)
    if t0 == 1:
        c1 := __load64(k + 8)
        c2 := __load64(k + 16)
        l2 := __uf_get(k, 56)
        t := 0.0
        if l2 > 1e-18:
            t = __uf_clamp01(((lx - __uf_get(k, 24)) * __uf_get(k, 40) + (ly - __uf_get(k, 32)) * __uf_get(k, 48)) / l2)
        r := __f2i(__uf_lerp(__i2f(__uc_r(c1)), __i2f(__uc_r(c2)), t) + 0.5)
        g := __f2i(__uf_lerp(__i2f(__uc_g(c1)), __i2f(__uc_g(c2)), t) + 0.5)
        b := __f2i(__uf_lerp(__i2f(__uc_b(c1)), __i2f(__uc_b(c2)), t) + 0.5)
        a := __f2i(__uf_lerp(__i2f(__uc_a(c1)), __i2f(__uc_a(c2)), t) + 0.5)
        return __uc(r, g, b, a)
    img := __load64(k + 8)
    iw := __load64(img)
    ih := __load64(img + 8)
    px := __load64(img + 16)
    x := __uf_get(k, 16)
    y := __uf_get(k, 24)
    w := __uf_get(k, 32)
    h := __uf_get(k, 40)
    u := (lx - x) / w * __i2f(iw) - 0.5
    v := (ly - y) / h * __i2f(ih) - 0.5
    ix := __f2i(__rt_floor(u))
    iy := __f2i(__rt_floor(v))
    fx := u - __i2f(ix)
    fy := v - __i2f(iy)
    x0 := __ui_max(0, __ui_min(ix, iw - 1))
    x1 := __ui_max(0, __ui_min(ix + 1, iw - 1))
    y0 := __ui_max(0, __ui_min(iy, ih - 1))
    y1 := __ui_max(0, __ui_min(iy + 1, ih - 1))
    out := 0
    c := 0
    while c < 4:
        a00 := __i2f(__load8(px + (y0 * iw + x0) * 4 + c))
        a10 := __i2f(__load8(px + (y0 * iw + x1) * 4 + c))
        a01 := __i2f(__load8(px + (y1 * iw + x0) * 4 + c))
        a11 := __i2f(__load8(px + (y1 * iw + x1) * 4 + c))
        v0 := __uf_lerp(a00, a10, fx)
        v1 := __uf_lerp(a01, a11, fx)
        out = out | ((__f2i(__uf_lerp(v0, v1, fy) + 0.5) & 255) << (8 * c))
        c += 1
    return out

# Moteur générique : forme décrite par une distance signée locale (transformation complète).
func __us_draw_sdf(s: int, lx00: float, ly00: float, lx10: float, ly10: float, sdf: int, col: int, p: int, forceFill: bool):
    inv := __alloc_raw(48)
    if not __um_invert(s + 24, inv):
        return
    stroke := __load64(p) != 0 and not forceFill
    pw := __uf_get(p, 24)
    if stroke and pw <= 0.0:
        return
    sc := __uf_max(__um_scale(s + 24), 1e-9)
    margin := 1.5 / sc
    if stroke:
        margin = pw * 0.5 + 1.5 / sc
    else:
        margin = 0.0 + 1.5 / sc
    lx0 := lx00 - margin
    ly0 := ly00 - margin
    lx1 := lx10 + margin
    ly1 := ly10 + margin
    q := __alloc_raw(64)
    __us_corners(s, lx0, ly0, lx1, ly1, q)
    bx0 := __f2i(__rt_floor(__uf_min4(q)))
    bx1 := __f2i(__uf_ceil(__uf_max4(q)))
    by0 := __f2i(__rt_floor(__uf_min4(q + 8)))
    by1 := __f2i(__uf_ceil(__uf_max4(q + 8)))
    bx0 = __ui_max(bx0, 0)
    by0 = __ui_max(by0, 0)
    bx1 = __ui_min(bx1, __us_w(s))
    by1 = __ui_min(by1, __us_h(s))
    if __load64(s + 80) != 0:
        bx0 = __ui_max(bx0, __load64(s + 88))
        by0 = __ui_max(by0, __load64(s + 96))
        bx1 = __ui_min(bx1, __load64(s + 104))
        by1 = __ui_min(by1, __load64(s + 112))
    op := __uf_get(p, 16) * __uf_get(s, 72)
    half := pw * 0.5
    pt := __alloc_raw(16)
    y := by0
    while y < by1:
        x := bx0
        while x < bx1:
            __um_apply(inv, __i2f(x) + 0.5, __i2f(y) + 0.5, pt)
            lx := __uf_get(pt, 0)
            ly := __uf_get(pt, 8)
            d := __ud_eval(sdf, lx, ly)
            cov := 0.0
            if stroke:
                cov = __uf_clamp01(0.5 - (__uf_fabs(d) - half) * sc)
            else:
                cov = __uf_clamp01(0.5 - d * sc)
            if cov > 0.0:
                c := __ucol_eval(col, lx, ly)
                __us_blend(s, x, y, c, cov * __uc_af(c) * op)
            x += 1
        y += 1

# Pixels [x0, x1) de la ligne y, même couverture.
func __us_span(s: int, y: int, x00: int, x10: int, c: int, alpha: float):
    if y < 0 or y >= __us_h(s) or alpha <= 0.0:
        return
    clip := __load64(s + 80) != 0
    if clip and (y < __load64(s + 96) or y >= __load64(s + 112)):
        return
    x0 := __ui_max(x00, 0)
    x1 := __ui_min(x10, __us_w(s))
    if clip:
        x0 = __ui_max(x0, __load64(s + 88))
        x1 = __ui_min(x1, __load64(s + 104))
    if x1 <= x0:
        return
    if alpha >= 0.999:
        d := __us_px(s) + (y * __us_w(s) + x0) * 4
        v := __uc_r(c) | (__uc_g(c) << 8) | (__uc_b(c) << 16) | (255 << 24)
        x := x0
        while x < x1:
            __store32(d, v)
            d += 4
            x += 1
        return
    x := x0
    while x < x1:
        __us_blend(s, x, y, c, alpha)
        x += 1

func __us_fast_rect(s: int, x0: float, y0: float, w0: float, h0: float, c: int, op: float) -> bool:
    if not __um_is_translation(s):
        return false
    x := x0
    y := y0
    w := w0
    h := h0
    if w < 0.0:
        x = x + w
        w = __uf_neg(w)
    if h < 0.0:
        y = y + h
        h = __uf_neg(h)
    X0 := x + __uf_get(s, 56)
    Y0 := y + __uf_get(s, 64)
    X1 := X0 + w
    Y1 := Y0 + h
    a := __uc_af(c) * op
    if a <= 0.0:
        return true
    px0 := __f2i(__rt_floor(X0))
    px1 := __f2i(__uf_ceil(X1))
    py0 := __f2i(__rt_floor(Y0))
    py1 := __f2i(__uf_ceil(Y1))
    py := py0
    while py < py1:
        oy := __uf_min(__i2f(py) + 1.0, Y1) - __uf_max(__i2f(py), Y0)
        if oy > 0.0:
            oxl := __uf_min(__i2f(px0) + 1.0, X1) - __uf_max(__i2f(px0), X0)
            if px1 - px0 == 1:
                __us_blend(s, px0, py, c, a * oy * oxl)
            else:
                oxr := __uf_min(__i2f(px1), X1) - __uf_max(__i2f(px1) - 1.0, X0)
                __us_blend(s, px0, py, c, a * oy * oxl)
                __us_span(s, py, px0 + 1, px1 - 1, c, a * oy)
                __us_blend(s, px1 - 1, py, c, a * oy * oxr)
        py += 1
    return true

func __us_fast_rrect(s: int, x: float, y: float, w: float, h: float, r0: float, c: int, op: float) -> bool:
    if not __um_is_translation(s):
        return false
    if w <= 0.0 or h <= 0.0:
        return true
    r := __uf_max(0.0, __uf_min(r0, __uf_min(w, h) * 0.5))
    if r < 0.5:
        return __us_fast_rect(s, x, y, w, h, c, op)
    X0 := x + __uf_get(s, 56)
    Y0 := y + __uf_get(s, 64)
    X1 := X0 + w
    Y1 := Y0 + h
    a := __uc_af(c) * op
    if a <= 0.0:
        return true
    sdf := __ud_roundrect(X0, Y0, w, h, r)
    py0 := __f2i(__rt_floor(Y0 - 1.0))
    py1 := __f2i(__uf_ceil(Y1 + 1.0))
    px0 := __f2i(__rt_floor(X0 - 1.0))
    px1 := __f2i(__uf_ceil(X1 + 1.0))
    py := py0
    while py < py1:
        cy := __i2f(py) + 0.5
        in0 := 0
        in1 := 0
        if cy > Y0 + r and cy < Y1 - r:
            in0 = __f2i(__uf_ceil(X0 + 1.0))
            in1 = __f2i(__rt_floor(X1 - 1.0))
        elif cy > Y0 + 1.0 and cy < Y1 - 1.0:
            in0 = __f2i(__uf_ceil(X0 + r + 1.0))
            in1 = __f2i(__rt_floor(X1 - r - 1.0))
        if in1 <= in0:
            in0 = px1
            in1 = px1
        px := px0
        lim := __ui_min(in0, px1)
        while px < lim:
            cov := __uf_clamp01(0.5 - __ud_rr_eval(sdf, __i2f(px) + 0.5, cy))
            if cov > 0.0:
                __us_blend(s, px, py, c, cov * a)
            px += 1
        if in1 > in0:
            __us_span(s, py, in0, in1, c, a)
        px = __ui_max(in1, px0)
        while px < px1:
            if not (px >= in0 and px < in1):
                cov := __uf_clamp01(0.5 - __ud_rr_eval(sdf, __i2f(px) + 0.5, cy))
                if cov > 0.0:
                    __us_blend(s, px, py, c, cov * a)
            px += 1
        py += 1
    return true

func __us_fill_rect(s: int, x: float, y: float, w: float, h: float, p: int):
    if __load64(p) == 0 and __us_fast_rect(s, x, y, w, h, __load64(p + 8), __uf_get(p, 16) * __uf_get(s, 72)):
        return
    __us_draw_sdf(s, x, y, x + w, y + h, __ud_roundrect(x, y, w, h, 0.0), __ucol_const(__load64(p + 8)), p, false)

func __us_round_rect(s: int, x: float, y: float, w: float, h: float, radius: float, p: int):
    if __load64(p) == 0 and __us_fast_rrect(s, x, y, w, h, radius, __load64(p + 8), __uf_get(p, 16) * __uf_get(s, 72)):
        return
    __us_draw_sdf(s, x, y, x + w, y + h, __ud_roundrect(x, y, w, h, radius), __ucol_const(__load64(p + 8)), p, false)

func __us_circle(s: int, cx: float, cy: float, r: float, p: int):
    d := __alloc(32)
    __store64(d, 1)
    __uf_set(d, 8, cx)
    __uf_set(d, 16, cy)
    __uf_set(d, 24, r)
    __us_draw_sdf(s, cx - r, cy - r, cx + r, cy + r, d, __ucol_const(__load64(p + 8)), p, false)

func __us_ellipse(s: int, cx: float, cy: float, rx: float, ry: float, p: int):
    if rx <= 0.0 or ry <= 0.0:
        return
    d := __alloc(40)
    __store64(d, 2)
    __uf_set(d, 8, cx)
    __uf_set(d, 16, cy)
    __uf_set(d, 24, rx)
    __uf_set(d, 32, ry)
    __us_draw_sdf(s, cx - rx, cy - ry, cx + rx, cy + ry, d, __ucol_const(__load64(p + 8)), p, false)

func __us_line(s: int, x1: float, y1: float, x2: float, y2: float, p: int):
    w := 1.0
    if __load64(p) != 0 and __uf_get(p, 24) > 0.0:
        w = __uf_get(p, 24)
    d := __alloc(48)
    __store64(d, 3)
    __uf_set(d, 8, x1)
    __uf_set(d, 16, y1)
    __uf_set(d, 24, x2)
    __uf_set(d, 32, y2)
    __uf_set(d, 40, w)
    __us_draw_sdf(s, __uf_min(x1, x2), __uf_min(y1, y2), __uf_max(x1, x2), __uf_max(y1, y2), d, __ucol_const(__load64(p + 8)), p, true)

func __us_gradient_rect(s: int, x: float, y: float, w: float, h: float, x1: float, y1: float, x2: float, y2: float, c1: int, c2: int, op: float):
    dx := x2 - x1
    dy := y2 - y1
    k := __alloc(64)
    __store64(k, 1)
    __store64(k + 8, c1)
    __store64(k + 16, c2)
    __uf_set(k, 24, x1)
    __uf_set(k, 32, y1)
    __uf_set(k, 40, dx)
    __uf_set(k, 48, dy)
    __uf_set(k, 56, dx * dx + dy * dy)
    p := __up_new(false, __uc(0, 0, 0, 255), op, 1.0)
    __us_draw_sdf(s, x, y, x + w, y + h, __ud_roundrect(x, y, w, h, 0.0), k, p, false)

# ---- chemins : liste native de commandes [genre][v0..v5] (0 move, 1 line, 2 cubic, 3 quad, 4 close) ----
# Aplatissement : liste native de sous-chemins [points (liste native de paires flottantes, 16 octets), fermé].

func __upth_pt(l: int, x: float, y: float):
    q := __alloc_raw(16)
    __uf_set(q, 0, x)
    __uf_set(q, 8, y)
    __rt_list_push(l, q)

func __upth_flush(out: int, cur: int, closed: bool) -> int:
    if __load64(cur) >= 2 or (closed and __load64(cur) > 0):
        e := __alloc(16)
        __store64(e, cur)
        if closed:
            __store64(e + 8, 1)
        __rt_list_push(out, e)
        return __rt_list_new(0)
    __store64(cur, 0)
    return cur

func __upth_flatten(cmds: int) -> int:
    out := __rt_list_new(0)
    cur := __rt_list_new(0)
    cx := 0.0
    cy := 0.0
    sx := 0.0
    sy := 0.0
    i := 0
    while i < __load64(cmds):
        c := __rt_vec_at(cmds, i)
        t := __load64(c)
        if t == 0:
            cur = __upth_flush(out, cur, false)
            cx = __uf_get(c, 8)
            sx = cx
            cy = __uf_get(c, 16)
            sy = cy
            __upth_pt(cur, cx, cy)
        elif t == 1:
            if __load64(cur) == 0:
                __upth_pt(cur, cx, cy)
            cx = __uf_get(c, 8)
            cy = __uf_get(c, 16)
            __upth_pt(cur, cx, cy)
        elif t == 2:
            if __load64(cur) == 0:
                __upth_pt(cur, cx, cy)
            k := 1
            while k <= 24:
                tt := __i2f(k) / 24.0
                u := 1.0 - tt
                x := u * u * u * cx + 3.0 * u * u * tt * __uf_get(c, 8) + 3.0 * u * tt * tt * __uf_get(c, 24) + tt * tt * tt * __uf_get(c, 40)
                y := u * u * u * cy + 3.0 * u * u * tt * __uf_get(c, 16) + 3.0 * u * tt * tt * __uf_get(c, 32) + tt * tt * tt * __uf_get(c, 48)
                __upth_pt(cur, x, y)
                k += 1
            cx = __uf_get(c, 40)
            cy = __uf_get(c, 48)
        elif t == 3:
            if __load64(cur) == 0:
                __upth_pt(cur, cx, cy)
            k := 1
            while k <= 16:
                tt := __i2f(k) / 16.0
                u := 1.0 - tt
                __upth_pt(cur, u * u * cx + 2.0 * u * tt * __uf_get(c, 8) + tt * tt * __uf_get(c, 24), u * u * cy + 2.0 * u * tt * __uf_get(c, 16) + tt * tt * __uf_get(c, 32))
                k += 1
            cx = __uf_get(c, 24)
            cy = __uf_get(c, 32)
        elif t == 4:
            if __load64(cur) > 0:
                __upth_pt(cur, sx, sy)
                cx = sx
                cy = sy
            cur = __upth_flush(out, cur, true)
        i += 1
    __upth_flush(out, cur, false)
    return out

func __uf_sort(a: int, n: int):
    # tri par insertion (valeurs flottantes en mots de 64 bits)
    i := 1
    while i < n:
        v := __uf_get(a, 8 * i)
        j := i - 1
        while j >= 0 and v < __uf_get(a, 8 * j):
            __store64(a + 8 * (j + 1), __load64(a + 8 * j))
            j -= 1
        __uf_set(a, 8 * (j + 1), v)
        i += 1

# Remplissage pair/impair, 4 sous-lignes par pixel (couverture en flottants 32 bits).
func __us_fill_polys(s: int, polys: int, c: int, alpha: float):
    W := __us_w(s)
    H := __us_h(s)
    ymin := 1e18
    ymax := -1e18
    npts := 0
    i := 0
    while i < __load64(polys):
        pl := __rt_vec_at(polys, i)
        j := 0
        while j < __load64(pl):
            yv := __uf_get(__rt_vec_at(pl, j), 8)
            ymin = __uf_min(ymin, yv)
            ymax = __uf_max(ymax, yv)
            npts += 1
            j += 1
        i += 1
    if ymin > ymax:
        return
    y0 := __ui_max(0, __f2i(__rt_floor(ymin)))
    y1 := __ui_min(H - 1, __f2i(__uf_ceil(ymax)))
    cov := __alloc_raw(8 * (W + 2) + 8)
    xsv := __alloc_raw(8 * npts + 16)
    y := y0
    while y <= y1:
        k := 0
        while k < W + 2:
            __uf_set(cov, 8 * k, 0.0)
            k += 1
        minx := W
        maxx := -1
        ss := 0
        while ss < 4:
            sy := __i2f(y) + (__i2f(ss) + 0.5) / 4.0
            nx := 0
            i = 0
            while i < __load64(polys):
                pl := __rt_vec_at(polys, i)
                n := __load64(pl)
                if n >= 2:
                    j := 0
                    while j < n:
                        a := __rt_vec_at(pl, j)
                        b := __rt_vec_at(pl, (j + 1) % n)
                        ay := __uf_get(a, 8)
                        by := __uf_get(b, 8)
                        if ay != by:
                            lo := __uf_min(ay, by)
                            hi := __uf_max(ay, by)
                            if not (sy < lo or sy >= hi):
                                ax := __uf_get(a, 0)
                                __uf_set(xsv, 8 * nx, ax + (sy - ay) * (__uf_get(b, 0) - ax) / (by - ay))
                                nx += 1
                        j += 1
                i += 1
            __uf_sort(xsv, nx)
            q := 0
            while q + 1 < nx:
                xa := __uf_max(0.0, __uf_get(xsv, 8 * q))
                xb := __uf_min(__i2f(W), __uf_get(xsv, 8 * (q + 1)))
                if xb > xa:
                    ia := __f2i(__rt_floor(xa))
                    ib := __f2i(__rt_floor(xb))
                    px := ia
                    while px <= ib and px < W:
                        ov := __uf_min(xb, __i2f(px) + 1.0) - __uf_max(xa, __i2f(px))
                        if ov > 0.0:
                            __uf_set(cov, 8 * px, __uf_f32(__uf_get(cov, 8 * px) + __uf_f32(ov / 4.0)))
                        px += 1
                    minx = __ui_min(minx, ia)
                    maxx = __ui_max(maxx, __ui_min(ib, W - 1))
                q += 2
            ss += 1
        x := __ui_max(0, minx)
        while x <= maxx:
            cv := __uf_get(cov, 8 * x)
            if cv > 0.0:
                __us_blend(s, x, y, c, __uf_min(1.0, cv) * alpha)
            x += 1
        y += 1

func __us_path(s: int, cmds: int, p: int):
    subs := __upth_flatten(cmds)
    if __load64(subs) == 0:
        return
    col := __load64(p + 8)
    op := __uf_get(p, 16) * __uf_get(s, 72) * __uc_af(col)
    if __load64(p) == 0:
        polys := __rt_list_new(0)
        pt := __alloc_raw(16)
        i := 0
        while i < __load64(subs):
            pts := __load64(__rt_vec_at(subs, i))
            if __load64(pts) >= 3:
                dev := __rt_list_new(0)
                j := 0
                while j < __load64(pts):
                    q := __rt_vec_at(pts, j)
                    __um_apply(s + 24, __uf_get(q, 0), __uf_get(q, 8), pt)
                    __upth_pt(dev, __uf_get(pt, 0), __uf_get(pt, 8))
                    j += 1
                __rt_list_push(polys, dev)
            i += 1
        __us_fill_polys(s, polys, col, op)
        return
    # contour : distance minimale aux segments
    nseg := 0
    i := 0
    while i < __load64(subs):
        n := __load64(__load64(__rt_vec_at(subs, i)))
        if n > 1:
            nseg += n - 1
        i += 1
    segs := __alloc_raw(32 * nseg + 8)
    x0 := 1e18
    y0 := 1e18
    x1 := -1e18
    y1 := -1e18
    k := 0
    i = 0
    while i < __load64(subs):
        pts := __load64(__rt_vec_at(subs, i))
        j := 0
        while j + 1 < __load64(pts):
            a := __rt_vec_at(pts, j)
            b := __rt_vec_at(pts, j + 1)
            q := segs + 32 * k
            __uf_set(q, 0, __uf_get(a, 0))
            __uf_set(q, 8, __uf_get(a, 8))
            __uf_set(q, 16, __uf_get(b, 0))
            __uf_set(q, 24, __uf_get(b, 8))
            k += 1
            j += 1
        j = 0
        while j < __load64(pts):
            a := __rt_vec_at(pts, j)
            x0 = __uf_min(x0, __uf_get(a, 0))
            x1 = __uf_max(x1, __uf_get(a, 0))
            y0 = __uf_min(y0, __uf_get(a, 8))
            y1 = __uf_max(y1, __uf_get(a, 8))
            j += 1
        i += 1
    if nseg == 0:
        return
    w := 1.0
    if __uf_get(p, 24) > 0.0:
        w = __uf_get(p, 24)
    d := __alloc(32)
    __store64(d, 4)
    __store64(d + 8, segs)
    __store64(d + 16, nseg)
    __uf_set(d, 24, w)
    __us_draw_sdf(s, x0, y0, x1, y1, d, __ucol_const(col), p, true)

# ---- ombre portée : flou gaussien approché par 3 passes de moyenne glissante (flottants 32 bits) ----

func __ub_box_line(inp: int, istep: int, outp: int, ostep: int, n: int, r: int):
    acc := 0.0
    i := 0 - r
    while i <= r:
        if i >= 0 and i < n:
            acc = acc + __uf_get(inp, istep * i)
        i += 1
    inv := 1.0 / __i2f(2 * r + 1)
    i = 0
    while i < n:
        __uf_set(outp, ostep * i, __uf_f32(acc * inv))
        add := i + r + 1
        rem := i - r
        if add < n:
            acc = acc + __uf_get(inp, istep * add)
        if rem >= 0:
            acc = acc - __uf_get(inp, istep * rem)
        i += 1

func __ub_gaussian(buf: int, w: int, h: int, sigma: float):
    if sigma < 0.3:
        return
    n := 3
    wi := __fsqrt(12.0 * sigma * sigma / __i2f(n) + 1.0)
    wl := __f2i(__rt_floor(wi))
    if wl % 2 == 0:
        wl -= 1
    wu := wl + 2
    mi := (12.0 * sigma * sigma - __i2f(n * wl * wl) - 4.0 * __i2f(n) * __i2f(wl) - 3.0 * __i2f(n)) / (__uf_neg(4.0) * __i2f(wl) - 4.0)
    m := __f2i(__uf_round(mi))
    tmp := __alloc_raw(8 * w * h + 8)
    __zero(tmp, 8 * w * h)
    mx := __ui_max(w, h)
    line := __alloc_raw(8 * mx + 8)
    outl := __alloc_raw(8 * mx + 8)
    ps := 0
    while ps < n:
        ww := wu
        if ps < m:
            ww = wl
        r := (ww - 1) // 2
        if r >= 1:
            y := 0
            while y < h:
                __ub_box_line(buf + 8 * y * w, 8, tmp + 8 * y * w, 8, w, r)
                y += 1
            x := 0
            while x < w:
                y = 0
                while y < h:
                    __store64(line + 8 * y, __load64(tmp + 8 * (y * w + x)))
                    y += 1
                __ub_box_line(line, 8, outl, 8, h, r)
                y = 0
                while y < h:
                    __store64(buf + 8 * (y * w + x), __load64(outl + 8 * y))
                    y += 1
                x += 1
        ps += 1

func __us_shadow_rrect(s: int, x: float, y: float, w: float, h: float, radius: float, shadow: int, sop: float, blur: float, ox: float, oy: float, fill: int):
    sc := __um_scale(s + 24)
    q := __alloc_raw(64)
    __us_corners(s, x, y, x + w, y + h, q)
    ddx := ox * __uf_get(s, 24) + oy * __uf_get(s, 40)
    ddy := ox * __uf_get(s, 32) + oy * __uf_get(s, 48)
    rx0 := __uf_min4(q) + ddx
    rx1 := __uf_max4(q) + ddx
    ry0 := __uf_min4(q + 8) + ddy
    ry1 := __uf_max4(q + 8) + ddy
    bd := __uf_max(0.0, blur * sc)
    pad := __f2i(__uf_ceil(bd * 1.5)) + 2
    bx0 := __ui_max(0, __f2i(__rt_floor(rx0)) - pad)
    by0 := __ui_max(0, __f2i(__rt_floor(ry0)) - pad)
    bx1 := __ui_min(__us_w(s), __f2i(__uf_ceil(rx1)) + pad)
    by1 := __ui_min(__us_h(s), __f2i(__uf_ceil(ry1)) + pad)
    if bx1 > bx0 and by1 > by0 and sop > 0.0:
        bw := bx1 - bx0
        bh := by1 - by0
        mask := __alloc_raw(8 * bw * bh + 8)
        sdf := __ud_roundrect(rx0, ry0, rx1 - rx0, ry1 - ry0, radius * sc)
        yy := 0
        while yy < bh:
            xx := 0
            while xx < bw:
                d := __ud_rr_eval(sdf, __i2f(bx0 + xx) + 0.5, __i2f(by0 + yy) + 0.5)
                __uf_set(mask, 8 * (yy * bw + xx), __uf_f32(__uf_clamp01(0.5 - d)))
                xx += 1
            yy += 1
        __ub_gaussian(mask, bw, bh, bd * 0.5)
        op := sop * __uf_get(s, 72) * __uc_af(shadow)
        lim := __uf_f32(0.002)
        yy = 0
        while yy < bh:
            xx := 0
            while xx < bw:
                mv := __uf_get(mask, 8 * (yy * bw + xx))
                if mv > lim:
                    __us_blend(s, bx0 + xx, by0 + yy, shadow, mv * op)
                xx += 1
            yy += 1
    f := __up_new(false, __load64(fill + 8), __uf_get(fill, 16), __uf_get(fill, 24))
    __us_round_rect(s, x, y, w, h, radius, f)

# ---- texte : atlas DejaVu (4 bits par pixel) ----
# Atlas : [0] px [8] ascent [16] descent [24] nombre [32] glyphes (7 mots chacun) [40] bitmaps

func __ua_atlas(font: int) -> int:
    ds := __dyn_ds()
    slot := ds + 464 + 8 * font
    a := __load64(slot)
    if a != 0:
        return a
    met := ""
    gl := ""
    bl := ""
    if font == 1:
        met = __uf_mono_metrics()
        gl = __uf_mono_glyphs()
        bl = __uf_mono_blob()
    else:
        met = __uf_sans_metrics()
        gl = __uf_sans_glyphs()
        bl = __uf_sans_blob()
    a = __alloc(48)
    mp := __nat_split_bytes(met, 58)
    __store64(a, __rt_str_to_int(__as_str(__rt_vec_at(mp, 0))))
    __store64(a + 8, __rt_str_to_int(__as_str(__rt_vec_at(mp, 1))))
    __store64(a + 16, __rt_str_to_int(__as_str(__rt_vec_at(mp, 2))))
    parts := __nat_split_bytes(gl, 44)
    n := __load64(parts)
    t := __alloc_raw(56 * n + 8)
    i := 0
    while i < n:
        f := __nat_split_bytes(__as_str(__rt_vec_at(parts, i)), 58)
        k := 0
        while k < 7:
            __store64(t + 56 * i + 8 * k, __rt_str_to_int(__as_str(__rt_vec_at(f, k))))
            k += 1
        i += 1
    __store64(a + 24, n)
    __store64(a + 32, t)
    nb := __nat_blen(bl) // 2
    b := __alloc_raw(nb + 8)
    hp := __nat_bp(bl)
    i = 0
    while i < nb:
        __store8(b + i, (__ua_hexv(__load8(hp + 2 * i)) << 4) | __ua_hexv(__load8(hp + 2 * i + 1)))
        i += 1
    __store64(a + 40, b)
    __store64(slot, a)
    return a

func __ua_hexv(c: int) -> int:
    if c >= 97:
        return c - 87
    return c - 48

# Glyphe du point de code (adresse de ses 7 champs : cp, adv16, bx, top, l, h, off), ou 0.
func __ua_find(a: int, cp: int) -> int:
    t := __load64(a + 32)
    lo := 0
    hi := __load64(a + 24) - 1
    while lo <= hi:
        mid := (lo + hi) // 2
        c := __load64(t + 56 * mid)
        if c == cp:
            return t + 56 * mid
        if c < cp:
            lo = mid + 1
        else:
            hi = mid - 1
    return 0

func __ua_glyph(a: int, cp: int) -> int:
    g := __ua_find(a, cp)
    if g == 0:
        g = __ua_find(a, 63)
    return g

func __ua_alpha(a: int, g: int, ix: int, iy: int) -> float:
    gw := __load64(g + 32)
    if ix < 0 or iy < 0 or ix >= gw or iy >= __load64(g + 40):
        return 0.0
    i := iy * gw + ix
    b := __load8(__load64(a + 40) + __load64(g + 48) + i // 2)
    if (i & 1) != 0:
        return __i2f(b & 15) / 15.0
    return __i2f(b >> 4) / 15.0

func __ua_font(name: str) -> int:
    n := __nat_case(name, 1)
    if __rt_str_eq(n, "mono") or __rt_str_eq(n, "monospace") or __dyn_find_bytes(n, "mono", 0) >= 0 or __rt_str_eq(n, "consolas") or __rt_str_eq(n, "courier") or __rt_str_eq(n, "courier new") or __rt_str_eq(n, "menlo"):
        return 1
    return 0

# Décodage UTF-8 du rastériseur (séquence invalide : U+FFFD) -> liste native de points de code.
func __ua_decode(s: str) -> int:
    out := __rt_list_new(0)
    p := __nat_bp(s)
    n := __nat_blen(s)
    i := 0
    while i < n:
        c := __load8(p + i)
        cp := 0
        len := 0
        if c < 128:
            cp = c
            len = 1
        elif (c >> 5) == 6:
            cp = c & 31
            len = 2
        elif (c >> 4) == 14:
            cp = c & 15
            len = 3
        elif (c >> 3) == 30:
            cp = c & 7
            len = 4
        else:
            __rt_list_push(out, 65533)
            i += 1
            continue
        if i + len > n:
            __rt_list_push(out, 65533)
            break
        ok := true
        k := 1
        while k < len:
            cc := __load8(p + i + k)
            if (cc & 192) != 128:
                ok = false
                break
            cp = (cp << 6) | (cc & 63)
            k += 1
        if ok:
            __rt_list_push(out, cp)
            i += len
        else:
            __rt_list_push(out, 65533)
            i += 1
    return out

func __ua_text_width(s: str, size: float, font: int) -> float:
    a := __ua_atlas(font)
    w := 0.0
    cps := __ua_decode(s)
    i := 0
    while i < __load64(cps):
        cp := __rt_vec_at(cps, i)
        i += 1
        if cp == 10 or cp == 13:
            continue
        g := __ua_glyph(a, cp)
        if g != 0:
            w = w + __i2f(__load64(g + 8)) / 16.0
    return w * size / __i2f(__load64(a))

func __ua_line_height(size: float, font: int) -> float:
    a := __ua_atlas(font)
    return __i2f(__load64(a + 8) + __load64(a + 16)) * size / __i2f(__load64(a))

func __ua_ascent(size: float, font: int) -> float:
    a := __ua_atlas(font)
    return __i2f(__load64(a + 8)) * size / __i2f(__load64(a))

# Couverture d'un glyphe rééchantillonné (échelle, décalage sous-pixel) : [0] l [8] h [16] octets
func __ua_raster(fa: int, g: int, scale: float, left: float, top: float) -> int:
    gw := __load64(g + 32)
    gh := __load64(g + 40)
    right := left + __i2f(gw) * scale
    bottom := top + __i2f(gh) * scale
    rw := __f2i(__uf_ceil(right))
    rh := __f2i(__uf_ceil(bottom))
    r := __alloc(24)
    __store64(r, rw)
    __store64(r + 8, rh)
    buf := __alloc_raw(rw * rh + 8)
    __zero(buf, rw * rh)
    __store64(r + 16, buf)
    py := 0
    while py < rh:
        px := 0
        while px < rw:
            gx0 := (__i2f(px) - left) / scale
            gx1 := (__i2f(px + 1) - left) / scale
            gy0 := (__i2f(py) - top) / scale
            gy1 := (__i2f(py + 1) - top) / scale
            a := 0.0
            if scale >= 1.0:
                cx := (gx0 + gx1) * 0.5 - 0.5
                cy := (gy0 + gy1) * 0.5 - 0.5
                ix := __f2i(__rt_floor(cx))
                iy := __f2i(__rt_floor(cy))
                fx := cx - __i2f(ix)
                fy := cy - __i2f(iy)
                a = __ua_alpha(fa, g, ix, iy) * (1.0 - fx) * (1.0 - fy) + __ua_alpha(fa, g, ix + 1, iy) * fx * (1.0 - fy) + __ua_alpha(fa, g, ix, iy + 1) * (1.0 - fx) * fy + __ua_alpha(fa, g, ix + 1, iy + 1) * fx * fy
            else:
                sum := 0.0
                sy := __f2i(__rt_floor(gy0))
                sye := __f2i(__uf_ceil(gy1))
                while sy < sye:
                    wy := __uf_min(gy1, __i2f(sy) + 1.0) - __uf_max(gy0, __i2f(sy))
                    if wy > 0.0:
                        sx := __f2i(__rt_floor(gx0))
                        sxe := __f2i(__uf_ceil(gx1))
                        while sx < sxe:
                            wx := __uf_min(gx1, __i2f(sx) + 1.0) - __uf_max(gx0, __i2f(sx))
                            if wx > 0.0:
                                sum = sum + __ua_alpha(fa, g, sx, sy) * wx * wy
                            sx += 1
                    sy += 1
                a = sum / ((gx1 - gx0) * (gy1 - gy0))
            __store8(buf + py * rw + px, __f2i(__uf_min(255.0, a * 255.0 + 0.5)) & 255)
            px += 1
        py += 1
    return r

func __ua_llround(x: float) -> int:
    return __f2i(__uf_round(x))

func __us_text(s: int, text: str, x: float, y: float, c: int, opacity: float, size: float, font: int):
    fa := __ua_atlas(font)
    if size <= 0.5:
        return
    pt := __alloc_raw(16)
    __um_apply(s + 24, x, y, pt)
    ox := __uf_get(pt, 0)
    oy := __uf_get(pt, 8)
    sd := size * __um_scale(s + 24)
    scale := sd / __i2f(__load64(fa))
    baseline := oy + __ua_ascent(sd, font) + 0.15 * sd
    op := opacity * __uf_get(s, 72) * __uc_af(c)
    scaleKey := __ua_llround(scale * 4096.0) & 1048575
    ds := __dyn_ds()
    cache := __load64(ds + 480)
    if cache == 0 or __load64(cache) > 40000:
        cache = __rt_dict_new(64)
        __store64(ds + 480, cache)
    pen := ox
    cps := __ua_decode(text)
    i := 0
    while i < __load64(cps):
        cp := __rt_vec_at(cps, i)
        i += 1
        if cp == 10 or cp == 13:
            continue
        g := __ua_glyph(fa, cp)
        if g == 0:
            continue
        if __load64(g + 32) > 0 and __load64(g + 40) > 0:
            left := pen + __i2f(__load64(g + 16)) * scale
            top := baseline - __i2f(__load64(g + 24)) * scale
            fl := __rt_floor(left)
            ft := __rt_floor(top)
            phx := __f2i((left - fl) * 4.0) & 3
            phy := __f2i((top - ft) * 4.0) & 3
            key := (__load64(g) << 28) | (scaleKey << 8) | ((font & 15) << 4) | (phx << 2) | phy
            e := __rt_dict_index(cache, key, 0)
            gr := 0
            if e >= 0:
                gr = __load64(__load64(cache + 32) + 8 * e)
            else:
                gr = __ua_raster(fa, g, scale, __i2f(phx) / 4.0, __i2f(phy) / 4.0)
                __rt_dict_set(cache, key, gr, 0)
            bx := __f2i(fl)
            by := __f2i(ft)
            rw := __load64(gr)
            rh := __load64(gr + 8)
            buf := __load64(gr + 16)
            py := 0
            while py < rh:
                px := 0
                while px < rw:
                    v := __load8(buf + py * rw + px)
                    if v > 0:
                        __us_blend(s, bx + px, by + py, c, __i2f(v) / 255.0 * op)
                    px += 1
                py += 1
        pen = pen + __i2f(__load64(g + 8)) / 16.0 * scale

# ---- images : [0] l [8] h [16] pixels RGBA ----

func __us_image(s: int, img: int, x: float, y: float, w0: float, h0: float, opacity: float):
    if __load64(img) <= 0 or __load64(img + 8) <= 0:
        return
    w := w0
    h := h0
    if w <= 0.0:
        w = __i2f(__load64(img))
    if h <= 0.0:
        h = __i2f(__load64(img + 8))
    k := __alloc(48)
    __store64(k, 2)
    __store64(k + 8, img)
    __uf_set(k, 16, x)
    __uf_set(k, 24, y)
    __uf_set(k, 32, w)
    __uf_set(k, 40, h)
    p := __up_new(false, __uc(0, 0, 0, 255), opacity, 1.0)
    __us_draw_sdf(s, x, y, x + w, y + h, __ud_roundrect(x, y, w, h, 0.0), k, p, false)

# ---- PNG : écriture (blocs deflate stockés) ----

func __upng_put32(sb: int, v: int):
    __rt_sb_byte(sb, (v >> 24) & 255)
    __rt_sb_byte(sb, (v >> 16) & 255)
    __rt_sb_byte(sb, (v >> 8) & 255)
    __rt_sb_byte(sb, v & 255)

func __upng_crc(p: int, n: int) -> int:
    tab := __load64(__of_tabs() + 40)
    crc := 4294967295
    i := 0
    while i < n:
        crc = __of_get(tab, (crc ^ __load8(p + i)) & 255) ^ (crc >> 8)
        i += 1
    return crc ^ 4294967295

func __upng_chunk(out: int, typ: str, data: int):
    n := 0
    if data != 0:
        n = __load64(data)
    __upng_put32(out, n)
    td := __rt_sb_new()
    __rt_sb_add(td, typ)
    if n > 0:
        __rt_sb_reserve(td, n)
        __copy(__load64(td + 16) + __load64(td), __load64(data + 16), n)
        __store64(td, __load64(td) + n)
    __rt_sb_reserve(out, __load64(td))
    __copy(__load64(out + 16) + __load64(out), __load64(td + 16), __load64(td))
    __store64(out, __load64(out) + __load64(td))
    __upng_put32(out, __upng_crc(__load64(td + 16), __load64(td)))

func __us_png_bytes(s: int) -> str:
    w := __us_w(s)
    h := __us_h(s)
    stride := w * 4
    rawn := h * (stride + 1)
    raw := __alloc_raw(rawn + 8)
    y := 0
    while y < h:
        __store8(raw + y * (stride + 1), 0)
        __copy(raw + y * (stride + 1) + 1, __us_px(s) + y * stride, stride)
        y += 1
    z := __rt_sb_new()
    __rt_sb_byte(z, 120)
    __rt_sb_byte(z, 1)
    pos := 0
    while pos < rawn or rawn == 0:
        n := rawn - pos
        if n > 65535:
            n = 65535
        last := pos + n >= rawn
        if last:
            __rt_sb_byte(z, 1)
        else:
            __rt_sb_byte(z, 0)
        __rt_sb_byte(z, n & 255)
        __rt_sb_byte(z, (n >> 8) & 255)
        __rt_sb_byte(z, (n ^ 65535) & 255)
        __rt_sb_byte(z, ((n ^ 65535) >> 8) & 255)
        __rt_sb_reserve(z, n)
        __copy(__load64(z + 16) + __load64(z), raw + pos, n)
        __store64(z, __load64(z) + n)
        pos += n
        if last:
            break
    a := 1
    b := 0
    i := 0
    while i < rawn:
        a = (a + __load8(raw + i)) % 65521
        b = (b + a) % 65521
        i += 1
    __upng_put32(z, (b << 16) | a)
    png := __rt_sb_new()
    __rt_sb_byte(png, 137)
    __rt_sb_add(png, "PNG")
    __rt_sb_byte(png, 13)
    __rt_sb_byte(png, 10)
    __rt_sb_byte(png, 26)
    __rt_sb_byte(png, 10)
    ihdr := __rt_sb_new()
    __upng_put32(ihdr, w)
    __upng_put32(ihdr, h)
    __rt_sb_byte(ihdr, 8)
    __rt_sb_byte(ihdr, 6)
    __rt_sb_byte(ihdr, 0)
    __rt_sb_byte(ihdr, 0)
    __rt_sb_byte(ihdr, 0)
    __upng_chunk(png, "IHDR", ihdr)
    __upng_chunk(png, "IDAT", z)
    __upng_chunk(png, "IEND", 0)
    return __rt_sb_str(png)

func __us_save_png(s: int, path: str) -> bool:
    data := __us_png_bytes(s)
    fd := __syscall(2, __nat_c(path), 577, 438)
    if fd < 0:
        return false
    ok := __nat_write_fd(fd, data)
    __syscall(3, fd)
    return ok

# ---- décodage d'images (PNG 8 bits non entrelacé, BMP 24/32 bits, PPM P6) ----

func __uimg_new(w: int, h: int) -> int:
    img := __alloc(24)
    __store64(img, w)
    __store64(img + 8, h)
    px := __alloc_raw(w * h * 4 + 8)
    __mem_fill(px, w * h * 4, 255)
    __store64(img + 16, px)
    return img

# Résultat : image, ou 0 avec le message dans err[0].
func __uimg_png(d: int, n: int, err: int) -> int:
    pos := 8
    w := 0
    h := 0
    depth := 0
    ctype := 0
    interlace := 0
    idat := __rt_sb_new()
    plte := ""
    trns := ""
    while pos + 8 <= n:
        len := __pg_be32(d + pos)
        typ := __nat_make(d + pos + 4, 4)
        if pos + 12 + len > n:
            __store64(err, __str_addr("PNG tronqué"))
            return 0
        c := d + pos + 8
        if __rt_str_eq(typ, "IHDR"):
            w = __pg_be32(d + pos + 8)
            h = __pg_be32(d + pos + 12)
            depth = __load8(c + 8)
            ctype = __load8(c + 9)
            interlace = __load8(c + 12)
        elif __rt_str_eq(typ, "PLTE"):
            plte = __nat_make(c, len)
        elif __rt_str_eq(typ, "tRNS"):
            trns = __nat_make(c, len)
        elif __rt_str_eq(typ, "IDAT"):
            __rt_sb_add(idat, __nat_make(c, len))
        elif __rt_str_eq(typ, "IEND"):
            break
        pos += 12 + len
    if w == 0 or h == 0 or w > 16384 or h > 16384:
        __store64(err, __str_addr("PNG : dimensions invalides"))
        return 0
    if interlace != 0:
        __store64(err, __str_addr("PNG entrelacé non supporté"))
        return 0
    if depth != 8:
        __store64(err, __str_addr("PNG : seule la profondeur 8 bits est supportée"))
        return 0
    ch := 0
    if ctype == 0 or ctype == 3:
        ch = 1
    elif ctype == 2:
        ch = 3
    elif ctype == 4:
        ch = 2
    elif ctype == 6:
        ch = 4
    if ch == 0:
        __store64(err, __str_addr("PNG : type de couleur inconnu"))
        return 0
    if __load64(idat) < 6:
        __store64(err, __str_addr("PNG : données absentes"))
        return 0
    st := 0
    ok := true
    try:
        st = __if_run(__load64(idat + 16) + 2, __load64(idat) - 2, -1)
    catch e:
        ok = false
    if not ok:
        __store64(err, __str_addr("PNG : flux deflate corrompu"))
        return 0
    rsb := __load64(st + 40)
    raw := __load64(rsb + 16)
    rn := __load64(rsb)
    stride := w * ch
    if rn < (stride + 1) * h:
        __store64(err, __str_addr("PNG : données incomplètes"))
        return 0
    cur := __alloc_raw(stride + 8)
    prev := __alloc_raw(stride + 8)
    __zero(prev, stride + 8)
    img := __uimg_new(w, h)
    px := __load64(img + 16)
    pn := __nat_blen(plte)
    pp := __nat_bp(plte)
    tn := __nat_blen(trns)
    tp := __nat_bp(trns)
    y := 0
    while y < h:
        line := raw + y * (stride + 1)
        f := __load8(line)
        i := 0
        while i < stride:
            a := 0
            c2 := 0
            if i >= ch:
                a = __load8(cur + i - ch)
                c2 = __load8(prev + i - ch)
            b := __load8(prev + i)
            x := __load8(line + 1 + i)
            v := 0
            if f == 0:
                v = x
            elif f == 1:
                v = x + a
            elif f == 2:
                v = x + b
            elif f == 3:
                v = x + ((a + b) >> 1)
            elif f == 4:
                v = x + __pg_paeth(a, b, c2)
            else:
                __store64(err, __str_addr("PNG : filtre invalide"))
                return 0
            __store8(cur + i, v & 255)
            i += 1
        x := 0
        while x < w:
            o := px + (y * w + x) * 4
            sp := cur + x * ch
            if ctype == 0:
                __store8(o, __load8(sp))
                __store8(o + 1, __load8(sp))
                __store8(o + 2, __load8(sp))
            elif ctype == 2:
                __store8(o, __load8(sp))
                __store8(o + 1, __load8(sp + 1))
                __store8(o + 2, __load8(sp + 2))
            elif ctype == 3:
                k := __load8(sp) * 3
                if k + 2 < pn:
                    __store8(o, __load8(pp + k))
                    __store8(o + 1, __load8(pp + k + 1))
                    __store8(o + 2, __load8(pp + k + 2))
                if __load8(sp) < tn:
                    __store8(o + 3, __load8(tp + __load8(sp)))
            elif ctype == 4:
                __store8(o, __load8(sp))
                __store8(o + 1, __load8(sp))
                __store8(o + 2, __load8(sp))
                __store8(o + 3, __load8(sp + 1))
            elif ctype == 6:
                __store32(o, __load32(sp))
            x += 1
        __copy(prev, cur, stride)
        y += 1
    return img

func __uimg_le32(p: int) -> int:
    v := __load8(p) | (__load8(p + 1) << 8) | (__load8(p + 2) << 16) | (__load8(p + 3) << 24)
    if v >= 2147483648:
        v = v - 4294967296
    return v

func __uimg_bmp(d: int, n: int, err: int) -> int:
    if n < 54:
        __store64(err, __str_addr("BMP tronqué"))
        return 0
    off := __uimg_le32(d + 10)
    w := __uimg_le32(d + 18)
    h := __uimg_le32(d + 22)
    bpp := __load8(d + 28) | (__load8(d + 29) << 8)
    comp := __uimg_le32(d + 30)
    flip := h > 0
    if h < 0:
        h = 0 - h
    if (bpp != 24 and bpp != 32) or (comp != 0 and comp != 3):
        __store64(err, __str_addr("BMP : seuls 24/32 bits non compressés sont supportés"))
        return 0
    if w <= 0 or h <= 0 or w > 16384 or h > 16384:
        __store64(err, __str_addr("BMP : dimensions invalides"))
        return 0
    stride := ((w * bpp // 8) + 3) & (0 - 4)
    if off < 0 or off + stride * h > n:
        __store64(err, __str_addr("BMP tronqué"))
        return 0
    img := __uimg_new(w, h)
    px := __load64(img + 16)
    y := 0
    while y < h:
        ry := y
        if flip:
            ry = h - 1 - y
        row := d + off + stride * ry
        x := 0
        while x < w:
            o := px + (y * w + x) * 4
            sp := row + x * (bpp // 8)
            __store8(o, __load8(sp + 2))
            __store8(o + 1, __load8(sp + 1))
            __store8(o + 2, __load8(sp))
            if bpp == 32:
                __store8(o + 3, __load8(sp + 3))
            else:
                __store8(o + 3, 255)
            x += 1
        y += 1
    return img

# Lecture façon istringstream >> : blancs sautés ; renvoie [valeur, fin] (fin = -1 : échec).
func __uimg_ws(c: int) -> bool:
    return c == 32 or c == 9 or c == 10 or c == 13 or c == 11 or c == 12

func __uimg_ppm(d: int, n0: int, err: int) -> int:
    n := n0
    if n > 64:
        n = 64
    i := 0
    while i < n and __uimg_ws(__load8(d + i)):
        i += 1
    ms := i
    while i < n and not __uimg_ws(__load8(d + i)):
        i += 1
    magic := __nat_make(d + ms, i - ms)
    vals := __alloc_raw(32)
    k := 0
    good := i > ms
    while k < 3 and good:
        while i < n and __uimg_ws(__load8(d + i)):
            i += 1
        neg := false
        if i < n and (__load8(d + i) == 43 or __load8(d + i) == 45):
            neg = __load8(d + i) == 45
            i += 1
        st := i
        v := 0
        while i < n and __load8(d + i) >= 48 and __load8(d + i) <= 57:
            v = v * 10 + (__load8(d + i) - 48)
            i += 1
        if i == st:
            good = false
        if neg:
            v = 0 - v
        __store64(vals + 8 * k, v)
        k += 1
    w := __load64(vals)
    h := __load64(vals + 8)
    mx := __load64(vals + 16)
    if not good or not __rt_str_eq(magic, "P6") or mx != 255 or w <= 0 or h <= 0:
        __store64(err, __str_addr("PPM : seul P6/255 est supporté"))
        return 0
    off := i + 1
    if off + w * h * 3 > n0:
        __store64(err, __str_addr("PPM tronqué"))
        return 0
    img := __uimg_new(w, h)
    px := __load64(img + 16)
    j := 0
    while j < w * h:
        __store8(px + j * 4, __load8(d + off + j * 3))
        __store8(px + j * 4 + 1, __load8(d + off + j * 3 + 1))
        __store8(px + j * 4 + 2, __load8(d + off + j * 3 + 2))
        j += 1
    return img

func __uimg_load(path: str, err: int) -> int:
    fd := __syscall(2, __nat_c(path), 0)
    if fd < 0:
        __store64(err, __str_addr("fichier introuvable : " + path))
        return 0
    data := __nat_read_fd(fd, -1)
    __syscall(3, fd)
    d := __nat_bp(data)
    n := __nat_blen(data)
    if n > 8 and __load8(d) == 137 and __load8(d + 1) == 80 and __load8(d + 2) == 78 and __load8(d + 3) == 71:
        return __uimg_png(d, n, err)
    if n > 2 and __load8(d) == 66 and __load8(d + 1) == 77:
        return __uimg_bmp(d, n, err)
    if n > 2 and __load8(d) == 80 and __load8(d + 1) == 54:
        return __uimg_ppm(d, n, err)
    __store64(err, __str_addr("format d'image non supporté (PNG, BMP, PPM P6)"))
    return 0

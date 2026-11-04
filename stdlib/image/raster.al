# alex: native
# alex: intrinsics
# NOVA (édition bureau) — image décodée en mémoire : pixels ARGB 32 bits (0xAARRGGBB), non prémultipliés.
#
#   r := raster.create(l, h)          pixels transparents
#   raster.put(r, x, y, c) / get       accès (sans contrôle des bornes dans les boucles internes : r.addr)
#   raster.shrink(r, l, h)            réduction par moyenne de zones (qualité correcte pour les vignettes)
#   raster.write_alpx(r, chemin)      fichier .alpx lisible par pixmap.load
#   raster.free(r)

class Raster:
    width: int := 0
    height: int := 0
    addr: int := 0
    size: int := 0

func create(w: int, h: int) -> Raster:
    if w <= 0 or h <= 0 or w > 32768 or h > 32768 or w * h > 100000000:
        raise("ImageError", "dimensions d'image invalides : " + str(w) + "x" + str(h))
    r := Raster()
    r.width = w
    r.height = h
    r.size = (w * h * 4 + 4095) & ~4095
    r.addr = __mmap(r.size)
    return r

func free(r: Raster):
    if r.addr != 0:
        __munmap(r.addr, r.size)
    r.addr = 0

func put(r: Raster, x: int, y: int, c: int):
    if x >= 0 and y >= 0 and x < r.width and y < r.height:
        __store32(r.addr + (y * r.width + x) * 4, c & 0xFFFFFFFF)

func get(r: Raster, x: int, y: int) -> int:
    if x >= 0 and y >= 0 and x < r.width and y < r.height:
        return __load32(r.addr + (y * r.width + x) * 4)
    return 0

func copy(r: Raster) -> Raster:
    d := create(r.width, r.height)
    __copy(d.addr, r.addr, r.width * r.height * 4)
    return d

# Réduction (nw <= largeur, nh <= hauteur) : chaque pixel de destination est la moyenne de sa zone source,
# pondérée par l'opacité (pas de franges sombres autour des zones transparentes).
func shrink(r: Raster, nw0: int, nh0: int) -> Raster:
    nw := nw0
    nh := nh0
    if nw < 1:
        nw = 1
    if nh < 1:
        nh = 1
    if nw >= r.width and nh >= r.height:
        return r
    d := create(nw, nh)
    y := 0
    while y < nh:
        sy0 := y * r.height // nh
        sy1 := (y + 1) * r.height // nh
        if sy1 <= sy0:
            sy1 = sy0 + 1
        x := 0
        while x < nw:
            sx0 := x * r.width // nw
            sx1 := (x + 1) * r.width // nw
            if sx1 <= sx0:
                sx1 = sx0 + 1
            sa := 0
            sr := 0
            sg := 0
            sb := 0
            cnt := 0
            yy := sy0
            while yy < sy1:
                p := r.addr + (yy * r.width + sx0) * 4
                xx := sx0
                while xx < sx1:
                    c := __load32(p)
                    a := (c >> 24) & 255
                    sa += a
                    sr += ((c >> 16) & 255) * a
                    sg += ((c >> 8) & 255) * a
                    sb += (c & 255) * a
                    cnt += 1
                    p += 4
                    xx += 1
                yy += 1
            out := 0
            if sa > 0:
                out = ((sa // cnt) << 24) | ((sr // sa) << 16) | ((sg // sa) << 8) | (sb // sa)
            __store32(d.addr + (y * nw + x) * 4, out)
            x += 1
        y += 1
    return d

func _write_all(fd: int, addr: int, n: int) -> bool:
    done := 0
    while done < n:
        k := __syscall(1, fd, addr + done, n - done)
        if k == -4:
            continue
        if k <= 0:
            return false
        done += k
    return true

func _cpath(path: str) -> int:
    p := __str_addr(path)
    n := __load64(p)
    c := __alloc_raw(n + 1)
    __copy(c, p + 8, n)
    __store8(c + n, 0)
    return c

# Fichier .alpx : « ALPX », largeur, hauteur, 0 (ARGB), puis les pixels.
func write_alpx(r: Raster, path: str):
    fd := __syscall(2, _cpath(path), 577, 420)       # O_WRONLY | O_CREAT | O_TRUNC, 0644
    if fd < 0:
        raise("IoError", "écriture impossible : " + path)
    head := __alloc_raw(16)
    __store32(head, 0x58504C41)
    __store32(head + 4, r.width)
    __store32(head + 8, r.height)
    __store32(head + 12, 0)
    ok := _write_all(fd, head, 16) and _write_all(fd, r.addr, r.width * r.height * 4)
    __syscall(3, fd)
    if not ok:
        raise("IoError", "écriture impossible : " + path)

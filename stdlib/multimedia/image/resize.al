# ALEX STANDARD LIBRARY — multimedia.image.resize
#
# Redimensionnement d'images (tous modes) :
#   nearest(img, w, h)        plus proche voisin (rapide, pixel art)
#   bilinear(img, w, h)       interpolation bilinéaire en virgule fixe (centres des points alignés)
#   box(img, w, h)            moyenne des points couverts : réduction sans crénelage
#   resize(img, w, h, method="auto")   auto : box pour réduire, bilinear pour agrandir
#   fit(img, max_w, max_h)    plus grande taille qui tient dans le cadre, proportions gardées
#   cover(img, w, h)          remplit le cadre puis recadre au centre
#   thumbnail(img, size)      fit dans un carré
#
# Erreurs : FormatError (dimensions cibles invalides, méthode inconnue), LimitError (taille cible au-delà
# des limites passées).

from core use len, type, to_int
from collections use append
use multimedia.core.errors as merr
use multimedia.image.image as mi
use multimedia.security.limits as lim

func _target(w, h, limits):
    if type(w) != "int" or type(h) != "int" or w <= 0 or h <= 0:
        merr.fail(merr.FORMAT, "taille cible invalide : " + str(w) + "x" + str(h))
    lim.of(limits).check_dimensions(w, h)

func nearest(img, w, h, limits=null):
    _target(w, h, limits)
    ch := img.channels
    out := []
    for y in 0..h:
        sy := (y * img.height) // h
        for x in 0..w:
            sx := (x * img.width) // w
            k := (sy * img.width + sx) * ch
            for c in 0..ch:
                append(out, img.pixels[k + c])
    return mi.Image(w, h, img.mode, out)

func bilinear(img, w, h, limits=null):
    _target(w, h, limits)
    ch := img.channels
    p := img.pixels
    sw := img.width
    sh := img.height
    out := []
    for y in 0..h:
        # position source en 1/256 de point, centres alignés
        fy := ((2 * y + 1) * sh * 256) // (2 * h) - 128
        if fy < 0:
            fy = 0
        y0 := fy >> 8
        wy := fy & 255
        y1 := y0 + 1 if y0 + 1 < sh else sh - 1
        for x in 0..w:
            fx := ((2 * x + 1) * sw * 256) // (2 * w) - 128
            if fx < 0:
                fx = 0
            x0 := fx >> 8
            wx := fx & 255
            x1 := x0 + 1 if x0 + 1 < sw else sw - 1
            a := (y0 * sw + x0) * ch
            b := (y0 * sw + x1) * ch
            c0 := (y1 * sw + x0) * ch
            d := (y1 * sw + x1) * ch
            for c in 0..ch:
                top := p[a + c] * (256 - wx) + p[b + c] * wx
                bot := p[c0 + c] * (256 - wx) + p[d + c] * wx
                append(out, (top * (256 - wy) + bot * wy + 32768) >> 16)
    return mi.Image(w, h, img.mode, out)

func box(img, w, h, limits=null):
    _target(w, h, limits)
    ch := img.channels
    p := img.pixels
    out := []
    for y in 0..h:
        ya := (y * img.height) // h
        yb := ((y + 1) * img.height) // h
        if yb <= ya:
            yb = ya + 1
        for x in 0..w:
            xa := (x * img.width) // w
            xb := ((x + 1) * img.width) // w
            if xb <= xa:
                xb = xa + 1
            n := (yb - ya) * (xb - xa)
            for c in 0..ch:
                s := 0
                for yy in ya..yb:
                    for xx in xa..xb:
                        s += p[(yy * img.width + xx) * ch + c]
                append(out, (s + n // 2) // n)
    return mi.Image(w, h, img.mode, out)

func resize(img, w, h, method="auto", limits=null):
    if method == "nearest":
        return nearest(img, w, h, limits)
    if method == "bilinear":
        return bilinear(img, w, h, limits)
    if method == "box":
        return box(img, w, h, limits)
    if method != "auto":
        merr.fail(merr.FORMAT, "méthode de redimensionnement inconnue : " + str(method))
    if w <= img.width and h <= img.height:
        return box(img, w, h, limits)
    return bilinear(img, w, h, limits)

# Taille [w, h] qui tient dans max_w x max_h en gardant les proportions (jamais agrandie si upscale est faux).
func fit_size(width, height, max_w, max_h, upscale=false):
    if not upscale and width <= max_w and height <= max_h:
        return [width, height]
    w := max_w
    h := (height * max_w + width // 2) // width
    if h > max_h:
        h = max_h
        w = (width * max_h + height // 2) // height
    if w < 1:
        w = 1
    if h < 1:
        h = 1
    return [w, h]

func fit(img, max_w, max_h, upscale=false):
    s := fit_size(img.width, img.height, max_w, max_h, upscale)
    if s[0] == img.width and s[1] == img.height:
        return img.copy()
    return resize(img, s[0], s[1])

func cover(img, w, h):
    # échelle qui couvre le cadre, puis recadrage centré
    sw := w
    sh := (img.height * w + img.width - 1) // img.width
    if sh < h:
        sh = h
        sw = (img.width * h + img.height - 1) // img.height
    big := resize(img, sw, sh)
    return big.crop((sw - w) // 2, (sh - h) // 2, w, h)

func thumbnail(img, size=128):
    return fit(img, size, size)

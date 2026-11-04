# ALEX STANDARD LIBRARY — multimedia.image.convert
#
# Conversions d'images :
#   - entre modes : gray <-> rgb <-> rgba (luminance BT.601 entière, alpha opaque ou composé sur un fond) ;
#   - alpha prémultiplié et retour ;
#   - plans YUV 4:2:0 (yuv420p, BT.601 plage limitée) <-> rgb, pour les images vidéo ;
#   - réglages simples : luminosité, contraste, inversion, seuil.
#
#   use multimedia.image.convert as cv
#   g := cv.to_mode(img, "gray")
#   plat := cv.flatten(img_rgba, [255, 255, 255])      # rgba composé sur fond blanc -> rgb
#   yuv := cv.rgb_to_yuv420p(img)                       # [plan Y, plan U, plan V] (dimensions paires)
#   retour := cv.yuv420p_to_rgb(yuv, img.width, img.height)
#
# Erreurs : FormatError (mode inconnu, dimensions impaires pour 4:2:0, plans de mauvaise taille).

from core use len, to_int
from collections use append
use multimedia.core.errors as merr
use multimedia.image.image as mi

func _clamp(v):
    if v < 0:
        return 0
    if v > 255:
        return 255
    return v

func luma(r, g, b):
    return (77 * r + 150 * g + 29 * b + 128) >> 8

func to_mode(img, mode):
    mi.channels_of(mode)
    if img.mode == mode:
        return img.copy()
    n := img.width * img.height
    src := img.pixels
    out := []
    for i in 0..n:
        if img.mode == "gray":
            v := src[i]
            if mode == "rgb":
                append(out, v)
                append(out, v)
                append(out, v)
            else:
                append(out, v)
                append(out, v)
                append(out, v)
                append(out, 255)
        else:
            k := i * img.channels
            if mode == "gray":
                append(out, luma(src[k], src[k + 1], src[k + 2]))
            elif mode == "rgb":
                append(out, src[k])
                append(out, src[k + 1])
                append(out, src[k + 2])
            else:
                append(out, src[k])
                append(out, src[k + 1])
                append(out, src[k + 2])
                append(out, 255)
    return mi.Image(img.width, img.height, mode, out)

# rgba -> rgb composé sur une couleur de fond.
func flatten(img, background=null):
    bg := background if background != null else [0, 0, 0]
    if img.mode != "rgba":
        return to_mode(img, "rgb")
    out := []
    for i in 0..img.width * img.height:
        k := i * 4
        a := img.pixels[k + 3]
        for c in 0..3:
            append(out, (img.pixels[k + c] * a + bg[c] * (255 - a) + 127) // 255)
    return mi.Image(img.width, img.height, "rgb", out)

func premultiply(img):
    if img.mode != "rgba":
        return img.copy()
    out := [p for p in img.pixels]
    for i in 0..img.width * img.height:
        k := i * 4
        a := out[k + 3]
        for c in 0..3:
            out[k + c] = (out[k + c] * a + 127) // 255
    return mi.Image(img.width, img.height, "rgba", out)

func unpremultiply(img):
    if img.mode != "rgba":
        return img.copy()
    out := [p for p in img.pixels]
    for i in 0..img.width * img.height:
        k := i * 4
        a := out[k + 3]
        for c in 0..3:
            if a == 0:
                out[k + c] = 0
            else:
                out[k + c] = _clamp((out[k + c] * 255 + a // 2) // a)
    return mi.Image(img.width, img.height, "rgba", out)

# rgb (ou autre mode, converti) -> [Y, U, V] en 4:2:0 (moyenne des 4 points pour la chrominance).
func rgb_to_yuv420p(img):
    if img.width % 2 != 0 or img.height % 2 != 0:
        merr.fail(merr.FORMAT, "yuv420p exige des dimensions paires : " + img.describe())
    rgb := img if img.mode == "rgb" else to_mode(img, "rgb")
    w := img.width
    h := img.height
    p := rgb.pixels
    ys := []
    for i in 0..w * h:
        k := i * 3
        append(ys, ((66 * p[k] + 129 * p[k + 1] + 25 * p[k + 2] + 128) >> 8) + 16)
    us := []
    vs := []
    for y in 0..h // 2:
        for x in 0..w // 2:
            r := 0
            g := 0
            b := 0
            for dy in 0..2:
                for dx in 0..2:
                    k := ((2 * y + dy) * w + 2 * x + dx) * 3
                    r += p[k]
                    g += p[k + 1]
                    b += p[k + 2]
            r = r // 4
            g = g // 4
            b = b // 4
            append(us, _clamp(((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128))
            append(vs, _clamp(((112 * r - 94 * g - 18 * b + 128) >> 8) + 128))
    return [ys, us, vs]

func yuv420p_to_rgb(planes, width, height):
    if width % 2 != 0 or height % 2 != 0:
        merr.fail(merr.FORMAT, "yuv420p exige des dimensions paires")
    ys := planes[0]
    us := planes[1]
    vs := planes[2]
    if len(ys) != width * height or len(us) != (width // 2) * (height // 2) or len(vs) != len(us):
        merr.fail(merr.FORMAT, "plans yuv420p de taille incorrecte pour " + str(width) + "x" + str(height))
    out := []
    for y in 0..height:
        for x in 0..width:
            ci := (y // 2) * (width // 2) + x // 2
            c := ys[y * width + x] - 16
            d := us[ci] - 128
            e := vs[ci] - 128
            append(out, _clamp((298 * c + 409 * e + 128) >> 8))
            append(out, _clamp((298 * c - 100 * d - 208 * e + 128) >> 8))
            append(out, _clamp((298 * c + 516 * d + 128) >> 8))
    return mi.Image(width, height, "rgb", out)

func _map(img, fn):
    out := [p for p in img.pixels]
    ch := img.channels
    for i in 0..img.width * img.height:
        k := i * ch
        lim := ch
        if ch == 4:
            lim = 3
        for c in 0..lim:
            out[k + c] = _clamp(fn(out[k + c]))
    return mi.Image(img.width, img.height, img.mode, out)

func brightness(img, delta):
    return _map(img, (v) => v + delta)

# factor > 1 : plus de contraste, autour de 128.
func contrast(img, factor):
    return _map(img, (v) => to_int((v - 128) * factor + 128.5))

func invert(img):
    return _map(img, (v) => 255 - v)

func threshold(img, level=128):
    g := to_mode(img, "gray")
    return mi.Image(g.width, g.height, "gray", [255 if v >= level else 0 for v in g.pixels])

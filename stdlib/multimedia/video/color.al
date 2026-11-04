# ALEX STANDARD LIBRARY — multimedia.video.color
#
# Couleur des images vidéo :
#   - conversions YCbCr <-> RGB selon la matrice (« bt601 », « bt709 ») et la plage (« limited » 16..235,
#     « full » 0..255), en virgule fixe ; plans yuv420p, yuyv422, nv12 ;
#   - réglages : luminosité, contraste, saturation, gamma (table précalculée), niveaux de gris.
#
#   use multimedia.video.color as vc
#   ycc := vc.rgb_to_ycbcr(200, 30, 60, "bt709", "limited")
#   rgb := vc.ycbcr_to_rgb(ycc[0], ycc[1], ycc[2], "bt709", "limited")
#   img2 := vc.adjust(img, 10, 1.2, 1.5, 0.9)        # luminosité, contraste, saturation, gamma
#   img3 := vc.from_planes("nv12", octets, w, h)     # Image rgb
#
# Erreurs : FormatError (matrice, plage, format de plans, taille).

from core use len, to_int
from collections use append
use math as _m
use multimedia.core.errors as merr
use multimedia.image.image as mi

# Coefficients Kr, Kb.
const MATRICES := {"bt601": [0.299, 0.114], "bt709": [0.2126, 0.0722]}

func _coefs(matrix):
    if not (matrix in MATRICES):
        merr.fail(merr.FORMAT, "matrice de couleur inconnue : " + str(matrix) + " (bt601, bt709)")
    return MATRICES[matrix]

func _clamp(v):
    if v < 0:
        return 0
    if v > 255:
        return 255
    return v

func _round(x):
    return to_int(x + 0.5) if x >= 0 else -to_int(-x + 0.5)

func rgb_to_ycbcr(r, g, b, matrix="bt601", rng="limited"):
    k := _coefs(matrix)
    kr := k[0]
    kb := k[1]
    kg := 1.0 - kr - kb
    y := kr * r + kg * g + kb * b
    cb := (b - y) / (2.0 * (1.0 - kb))
    cr := (r - y) / (2.0 * (1.0 - kr))
    if rng == "limited":
        return [_clamp(_round(16 + y * 219.0 / 255)), _clamp(_round(128 + cb * 224.0 / 255)), _clamp(_round(128 + cr * 224.0 / 255))]
    if rng == "full":
        return [_clamp(_round(y)), _clamp(_round(128 + cb)), _clamp(_round(128 + cr))]
    merr.fail(merr.FORMAT, "plage inconnue : " + str(rng) + " (limited, full)")

func ycbcr_to_rgb(y, cb, cr, matrix="bt601", rng="limited"):
    k := _coefs(matrix)
    kr := k[0]
    kb := k[1]
    kg := 1.0 - kr - kb
    yy := 0.0
    u := 0.0
    v := 0.0
    if rng == "limited":
        yy = (y - 16) * 255.0 / 219
        u = (cb - 128) * 255.0 / 224
        v = (cr - 128) * 255.0 / 224
    elif rng == "full":
        yy = 1.0 * y
        u = cb - 128.0
        v = cr - 128.0
    else:
        merr.fail(merr.FORMAT, "plage inconnue : " + str(rng))
    r := yy + 2.0 * (1.0 - kr) * v
    b := yy + 2.0 * (1.0 - kb) * u
    g := (yy - kr * r - kb * b) / kg
    return [_clamp(_round(r)), _clamp(_round(g)), _clamp(_round(b))]

# Plans bruts -> Image rgb : « yuv420p » (Y, U, V), « nv12 » (Y, UV entrelacés), « yuyv422 », « gray8 », « rgb24 ».
func from_planes(fmt, data, width, height, matrix="bt601", rng="limited"):
    n := width * height
    out := []
    if fmt == "rgb24":
        if len(data) < 3 * n:
            merr.fail(merr.FORMAT, "rgb24 : données trop courtes")
        return mi.Image(width, height, "rgb", [data[k] for k in 0..3 * n])
    if fmt == "gray8":
        if len(data) < n:
            merr.fail(merr.FORMAT, "gray8 : données trop courtes")
        return mi.Image(width, height, "gray", [data[k] for k in 0..n])
    if fmt == "yuv420p" or fmt == "nv12":
        if width % 2 != 0 or height % 2 != 0:
            merr.fail(merr.FORMAT, fmt + " exige des dimensions paires")
        need := n + n // 2
        if len(data) < need:
            merr.fail(merr.FORMAT, fmt + " : " + str(need) + " octets attendus, " + str(len(data)))
        cw := width // 2
        for y in 0..height:
            for x in 0..width:
                ci := (y // 2) * cw + x // 2
                u := 0
                v := 0
                if fmt == "yuv420p":
                    u = data[n + ci]
                    v = data[n + n // 4 + ci]
                else:
                    u = data[n + 2 * ci]
                    v = data[n + 2 * ci + 1]
                c := ycbcr_to_rgb(data[y * width + x], u, v, matrix, rng)
                append(out, c[0])
                append(out, c[1])
                append(out, c[2])
        return mi.Image(width, height, "rgb", out)
    if fmt == "yuyv422":
        if width % 2 != 0 or len(data) < 2 * n:
            merr.fail(merr.FORMAT, "yuyv422 : largeur paire et 2 octets par point exigés")
        for i in 0..n // 2:
            y0 := data[4 * i]
            u := data[4 * i + 1]
            y1 := data[4 * i + 2]
            v := data[4 * i + 3]
            for yy in [y0, y1]:
                c := ycbcr_to_rgb(yy, u, v, matrix, rng)
                append(out, c[0])
                append(out, c[1])
                append(out, c[2])
        return mi.Image(width, height, "rgb", out)
    merr.fail(merr.FORMAT, "format de plans inconnu : " + str(fmt))

# Image -> plans « yuv420p » (octets Y puis U puis V).
func to_yuv420p(img, matrix="bt601", rng="limited"):
    if img.width % 2 != 0 or img.height % 2 != 0:
        merr.fail(merr.FORMAT, "yuv420p exige des dimensions paires")
    w := img.width
    h := img.height
    ch := img.channels
    ys := []
    for i in 0..w * h:
        k := i * ch
        if ch == 1:
            r := img.pixels[k]
            append(ys, rgb_to_ycbcr(r, r, r, matrix, rng)[0])
        else:
            append(ys, rgb_to_ycbcr(img.pixels[k], img.pixels[k + 1], img.pixels[k + 2], matrix, rng)[0])
    us := []
    vs := []
    for y in 0..h // 2:
        for x in 0..w // 2:
            acc := [0, 0, 0]
            for dy in 0..2:
                for dx in 0..2:
                    k := ((2 * y + dy) * w + 2 * x + dx) * ch
                    for c in 0..3:
                        acc[c] += img.pixels[k + (c if ch >= 3 else 0)]
            c := rgb_to_ycbcr(acc[0] / 4.0, acc[1] / 4.0, acc[2] / 4.0, matrix, rng)
            append(us, c[1])
            append(vs, c[2])
    return ys + us + vs

# Réglages : delta de luminosité (-255..255), contraste (1 = neutre), saturation (0 = gris, 1 = neutre), gamma.
func adjust(img, brightness=0, contrast=1.0, saturation=1.0, gamma=1.0):
    if gamma <= 0:
        merr.fail(merr.FORMAT, "gamma invalide")
    table := []
    for v in 0..256:
        x := (v - 128) * contrast + 128 + brightness
        if x < 0:
            x = 0
        if x > 255:
            x = 255
        if gamma != 1.0:
            x = 255.0 * _m.pow(x / 255.0, 1.0 / gamma)
        append(table, _clamp(_round(x)))
    ch := img.channels
    out := [p for p in img.pixels]
    for i in 0..img.width * img.height:
        k := i * ch
        if ch == 1:
            out[k] = table[out[k]]
            continue
        r := table[out[k]]
        g := table[out[k + 1]]
        b := table[out[k + 2]]
        if saturation != 1.0:
            l := 0.299 * r + 0.587 * g + 0.114 * b
            r = _clamp(_round(l + (r - l) * saturation))
            g = _clamp(_round(l + (g - l) * saturation))
            b = _clamp(_round(l + (b - l) * saturation))
        out[k] = r
        out[k + 1] = g
        out[k + 2] = b
    return mi.Image(img.width, img.height, img.mode, out)

func grayscale(img):
    return adjust(img, 0, 1.0, 0.0)

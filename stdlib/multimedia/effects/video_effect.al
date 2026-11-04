# ALEX STANDARD LIBRARY — multimedia.effects.video_effect
#
# Effets sur images (et VideoFrame) :
#   blur (flou de boîte séparable, rayon r), sharpen (masque flou), edge (Sobel, niveaux de gris), grayscale,
#   sepia, invert, vignette, pixelate, adjust (luminosité, contraste, saturation, gamma : multimedia.video.color),
#   overlay_text_box (rectangle de sous-titre semi-transparent), et Effect(fn) pour composer.
#
#   use multimedia.effects.video_effect as ve
#   img2 := ve.blur(img, 2)
#   f2 := ve.apply(video_frame, (i) => ve.vignette(ve.sepia(i), 0.6))
#
# Erreurs : FormatError (paramètres).

from core use len, to_int
from collections use append
use math as _m
use multimedia.core.errors as merr
use multimedia.image.image as mi
use multimedia.image.convert as cv
use multimedia.video.color as vc
use multimedia.video.frame as vfr

func apply(frame, fn):
    if vfr.is_frame(frame):
        return frame.with_image(fn(frame.image))
    return fn(frame)

func _clamp(v):
    if v < 0:
        return 0
    if v > 255:
        return 255
    return v

# Flou de boîte (2r+1), séparable, bords répétés.
func blur(img, r=1):
    if r < 0:
        merr.fail(merr.FORMAT, "rayon négatif")
    if r == 0:
        return img.copy()
    w := img.width
    h := img.height
    ch := img.channels
    src := img.pixels
    tmp := [0 for p in src]
    n := 2 * r + 1
    for y in 0..h:
        for c in 0..ch:
            acc := 0
            for k in -r..r + 1:
                xx := k if k > 0 else 0
                if xx >= w:
                    xx = w - 1
                acc += src[(y * w + xx) * ch + c]
            for x in 0..w:
                tmp[(y * w + x) * ch + c] = (acc + n // 2) // n
                xo := x - r
                xi := x + r + 1
                if xo < 0:
                    xo = 0
                if xi >= w:
                    xi = w - 1
                acc += src[(y * w + xi) * ch + c] - src[(y * w + xo) * ch + c]
    out := [0 for p in src]
    for x in 0..w:
        for c in 0..ch:
            acc := 0
            for k in -r..r + 1:
                yy := k if k > 0 else 0
                if yy >= h:
                    yy = h - 1
                acc += tmp[(yy * w + x) * ch + c]
            for y in 0..h:
                out[(y * w + x) * ch + c] = (acc + n // 2) // n
                yo := y - r
                yi := y + r + 1
                if yo < 0:
                    yo = 0
                if yi >= h:
                    yi = h - 1
                acc += tmp[(yi * w + x) * ch + c] - tmp[(yo * w + x) * ch + c]
    return mi.Image(w, h, img.mode, out)

func sharpen(img, amount=1.0, r=1):
    b := blur(img, r)
    out := []
    lim := img.channels
    for k in 0..len(img.pixels):
        if img.channels == 4 and k % 4 == 3:
            append(out, img.pixels[k])
        else:
            append(out, _clamp(to_int(img.pixels[k] + amount * (img.pixels[k] - b.pixels[k]) + 0.5)))
    return mi.Image(img.width, img.height, img.mode, out)

func edge(img):
    g := cv.to_mode(img, "gray")
    w := g.width
    h := g.height
    p := g.pixels
    out := [0 for v in p]
    for y in 1..h - 1:
        for x in 1..w - 1:
            i := y * w + x
            gx := -p[i - w - 1] - 2 * p[i - 1] - p[i + w - 1] + p[i - w + 1] + 2 * p[i + 1] + p[i + w + 1]
            gy := -p[i - w - 1] - 2 * p[i - w] - p[i - w + 1] + p[i + w - 1] + 2 * p[i + w] + p[i + w + 1]
            out[i] = _clamp(to_int(_m.sqrt(gx * gx + gy * gy)))
    return mi.Image(w, h, "gray", out)

func grayscale(img):
    return vc.grayscale(img)

func invert(img):
    return cv.invert(img)

func sepia(img):
    src := img if img.mode != "gray" else cv.to_mode(img, "rgb")
    ch := src.channels
    out := [p for p in src.pixels]
    for i in 0..src.width * src.height:
        k := i * ch
        r := out[k]
        g := out[k + 1]
        b := out[k + 2]
        out[k] = _clamp(to_int(0.393 * r + 0.769 * g + 0.189 * b))
        out[k + 1] = _clamp(to_int(0.349 * r + 0.686 * g + 0.168 * b))
        out[k + 2] = _clamp(to_int(0.272 * r + 0.534 * g + 0.131 * b))
    return mi.Image(src.width, src.height, src.mode, out)

# Assombrit les bords : strength 0..1.
func vignette(img, strength=0.5):
    if strength < 0 or strength > 1:
        merr.fail(merr.FORMAT, "intensité hors de 0..1")
    w := img.width
    h := img.height
    ch := img.channels
    cx := (w - 1) / 2.0
    cy := (h - 1) / 2.0
    maxd := _m.sqrt(cx * cx + cy * cy) if cx + cy > 0 else 1.0
    out := [p for p in img.pixels]
    for y in 0..h:
        for x in 0..w:
            d := _m.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / maxd
            f := 1.0 - strength * d * d
            k := (y * w + x) * ch
            for c in 0..(ch if ch != 4 else 3):
                out[k + c] = _clamp(to_int(out[k + c] * f + 0.5))
    return mi.Image(w, h, img.mode, out)

func pixelate(img, block=8):
    if block < 1:
        merr.fail(merr.FORMAT, "bloc invalide")
    out := img.copy()
    ch := img.channels
    for by in 0..(img.height + block - 1) // block:
        for bx in 0..(img.width + block - 1) // block:
            x0 := bx * block
            y0 := by * block
            x1 := x0 + block if x0 + block < img.width else img.width
            y1 := y0 + block if y0 + block < img.height else img.height
            acc := [0 for c in 0..ch]
            n := (x1 - x0) * (y1 - y0)
            for y in y0..y1:
                for x in x0..x1:
                    k := (y * img.width + x) * ch
                    for c in 0..ch:
                        acc[c] += img.pixels[k + c]
            v := [(a + n // 2) // n for a in acc]
            out.fill_rect(x0, y0, x1 - x0, y1 - y0, v)
    return out

func adjust(img, brightness=0, contrast=1.0, saturation=1.0, gamma=1.0):
    return vc.adjust(img, brightness, contrast, saturation, gamma)

# Rectangle semi-transparent (fond de sous-titre) en bas de l'image.
func overlay_text_box(img, height_ratio=0.18, opacity=0.6, color=null):
    c := color if color != null else [0, 0, 0]
    h := to_int(img.height * height_ratio)
    box := mi.new(img.width, h if h > 0 else 1, "rgba", [c[0], c[1], c[2], to_int(255 * opacity)])
    base := img if img.mode != "gray" else cv.to_mode(img, "rgb")
    out := base.copy()
    return out.paste(box, 0, img.height - box.height)

class Effect:
    func init(fn, name="effet"):
        self.fn = fn
        self.name = name

    func process(frame):
        return apply(frame, self.fn)

func chain(effects):
    return Effect((img) => _run_chain(effects, img), "chaîne")

func _run_chain(effects, img):
    out := img
    for e in effects:
        out = e.fn(out)
    return out

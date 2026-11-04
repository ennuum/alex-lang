# ALEX STANDARD LIBRARY — multimedia.image.encode
#
# Encodeurs d'images en ALEX pur :
#   - PNG : gris, RGB, RGBA 8 bits ; filtre choisi ligne par ligne (heuristique de la somme minimale), deflate
#           (office.compression), blocs tEXt pour les métadonnées ;
#   - BMP : 24 bits (gris et RGB) ou 32 bits avec alpha (en-tête BITMAPV4, champs de bits) ;
#   - PNM : PGM (P5) pour le gris, PPM (P6) pour la couleur (l'alpha est composé sur un fond noir).
#
#   use multimedia.image.encode as enc
#   octets := enc.encode_png(img, {"Title": "Essai"})
#   enc.save(img, "sortie.png")                    # format d'après l'extension : .png, .bmp, .ppm, .pgm, .pnm
#
# Erreurs : UnsupportedError (extension ou format inconnu), FormatError.

from core use len
from collections use append, keys
use io as _io
use string as _s
use office.compression as _z
use multimedia.core.errors as merr
use multimedia.image.image as mi
use multimedia.image.convert as cv

func _u32be(v):
    return [(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]

func _u32le(v):
    return [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]

func _u16le(v):
    return [v & 255, (v >> 8) & 255]

func _chunk(out, ctype, data):
    for x in _u32be(len(data)):
        append(out, x)
    tb := _s.byte_unpack(ctype)
    body := tb + data
    for x in tb:
        append(out, x)
    for x in data:
        append(out, x)
    for x in _u32be(_z.crc32(body)):
        append(out, x)

func _abs(v):
    return v if v >= 0 else -v

func _paeth(a, b, c):
    p := a + b - c
    pa := _abs(p - a)
    pb := _abs(p - b)
    pc := _abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c

# Filtre une ligne ; renvoie [type, octets filtrés] de plus petite somme (valeurs signées).
func _best_filter(cur, prev, bpp, adaptive):
    n := len(cur)
    if not adaptive:
        return [0, cur]
    best := null
    best_sum := -1
    for ft in 0..5:
        f := []
        s := 0
        for k in 0..n:
            left := cur[k - bpp] if k >= bpp else 0
            up := prev[k]
            ul := prev[k - bpp] if k >= bpp else 0
            v := cur[k]
            if ft == 1:
                v = (cur[k] - left) & 255
            elif ft == 2:
                v = (cur[k] - up) & 255
            elif ft == 3:
                v = (cur[k] - ((left + up) >> 1)) & 255
            elif ft == 4:
                v = (cur[k] - _paeth(left, up, ul)) & 255
            append(f, v)
            s += v if v < 128 else 256 - v
        if best_sum < 0 or s < best_sum:
            best_sum = s
            best = [ft, f]
    return best

func encode_png(img, text=null, level=6, adaptive=true):
    ct := {"gray": 0, "rgb": 2, "rgba": 6}[img.mode]
    out := [137, 80, 78, 71, 13, 10, 26, 10]
    ihdr := _u32be(img.width) + _u32be(img.height) + [8, ct, 0, 0, 0]
    _chunk(out, "IHDR", ihdr)
    if text != null:
        for k in keys(text):
            _chunk(out, "tEXt", _s.byte_unpack(str(k)) + [0] + _s.byte_unpack(str(text[k])))
    stride := img.width * img.channels
    raw := []
    prev := [0 for i in 0..stride]
    for y in 0..img.height:
        a := y * stride
        cur := [img.pixels[k] for k in a..a + stride]
        f := _best_filter(cur, prev, img.channels, adaptive)
        append(raw, f[0])
        for v in f[1]:
            append(raw, v)
        prev = cur
    _chunk(out, "IDAT", _z.zlib_compress(raw, level))
    _chunk(out, "IEND", [])
    return out

func encode_bmp(img):
    alpha := img.mode == "rgba"
    bpp := 32 if alpha else 24
    stride := ((img.width * bpp + 31) // 32) * 4
    hsize := 108 if alpha else 40
    offset := 14 + hsize
    total := offset + stride * img.height
    out := [66, 77] + _u32le(total) + [0, 0, 0, 0] + _u32le(offset)
    out = out + _u32le(hsize) + _u32le(img.width) + _u32le(img.height) + _u16le(1) + _u16le(bpp)
    out = out + _u32le(3 if alpha else 0) + _u32le(stride * img.height) + _u32le(2835) + _u32le(2835) + _u32le(0) + _u32le(0)
    if alpha:
        out = out + _u32le(0x00FF0000) + _u32le(0x0000FF00) + _u32le(0x000000FF) + _u32le(0xFF000000)
        out = out + _u32le(0x73524742)          # « sRGB »
        out = out + [0 for i in 0..48]          # extrémités et gammas inutilisés
    src := img if img.mode != "gray" else cv.to_mode(img, "rgb")
    ch := src.channels
    pad := stride - img.width * (bpp // 8)
    for row in 0..img.height:
        y := img.height - 1 - row
        for x in 0..img.width:
            k := (y * img.width + x) * ch
            append(out, src.pixels[k + 2])
            append(out, src.pixels[k + 1])
            append(out, src.pixels[k])
            if alpha:
                append(out, src.pixels[k + 3])
        for i in 0..pad:
            append(out, 0)
    return out

func encode_pnm(img):
    if img.mode == "gray":
        out := _s.byte_unpack("P5\n" + str(img.width) + " " + str(img.height) + "\n255\n")
        for v in img.pixels:
            append(out, v)
        return out
    src := cv.flatten(img) if img.mode == "rgba" else img
    out := _s.byte_unpack("P6\n" + str(img.width) + " " + str(img.height) + "\n255\n")
    for v in src.pixels:
        append(out, v)
    return out

func format_for_path(path):
    p := _s.lower(path)
    if _s.ends_with(p, ".png"):
        return "png"
    if _s.ends_with(p, ".bmp"):
        return "bmp"
    if _s.ends_with(p, ".ppm") or _s.ends_with(p, ".pgm") or _s.ends_with(p, ".pnm"):
        return "pnm"
    return null

func encode(img, fmt, meta=null):
    if fmt == "png":
        return encode_png(img, meta)
    if fmt == "bmp":
        return encode_bmp(img)
    if fmt == "pnm" or fmt == "ppm" or fmt == "pgm":
        return encode_pnm(img)
    merr.unsupported("encodage " + str(fmt), "formats écrits : png, bmp, pnm")

func save(img, path, meta=null):
    f := format_for_path(path)
    if f == null:
        merr.unsupported("extension de « " + path + " »", "utiliser .png, .bmp, .ppm, .pgm ou .pnm")
    data := encode(img, f, meta)
    _io.write_bytes(path, data)
    return len(data)

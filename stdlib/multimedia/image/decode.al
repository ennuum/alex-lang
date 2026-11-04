# ALEX STANDARD LIBRARY — multimedia.image.decode
#
# Décodeurs d'images écrits en ALEX pur, pour des fichiers NON FIABLES (lecture bornée, limites vérifiées
# avant toute allocation) :
#   - PNG : tous les types de couleur (gris, RGB, palette, gris + alpha, RGBA), profondeurs 1 à 16 bits
#           (16 bits ramenés à 8), transparence tRNS, entrelacement Adam7, contrôle des CRC, inflate borné ;
#   - BMP : 1, 4, 8, 24 et 32 bits non compressés, champs de bits 16 / 32 bits, haut en bas ou bas en haut ;
#   - PNM : P1 à P6 (PBM, PGM, PPM, texte ou binaire), valeur max jusqu'à 65535 ;
#   - JPEG : séquentiel et progressif, gris / YCbCr, sous-échantillonnage, RST (multimedia.image.jpeg).
# Formats reconnus mais non décodés ici (GIF, WebP, TIFF...) : UnsupportedError explicite.
#
#   use multimedia.image.decode as dec
#   img := dec.load("photo.png")                 # multimedia.image.image.Image
#   img2 := dec.decode(octets, lim.strict())
#   print(dec.detect(octets))                    # "png", "bmp", "pnm", "jpeg", ... ou null
#
# Erreurs : CorruptDataError, UnsupportedError, LimitError, FormatError.

from core use len, type, to_int
from collections use append
use io as _io
use os as _os
use string as _s
use office.compression as _z
use multimedia.core.errors as merr
use multimedia.security.limits as lim
use multimedia.security.validation as val
use multimedia.image.image as mi
use multimedia.image.jpeg as _jpeg

const PNG_MAGIC := [137, 80, 78, 71, 13, 10, 26, 10]

func _starts(b, magic):
    if len(b) < len(magic):
        return false
    for k in 0..len(magic):
        if b[k] != magic[k]:
            return false
    return true

# Format d'image d'après la signature, ou null.
func detect(b):
    if _starts(b, PNG_MAGIC):
        return "png"
    if _starts(b, [66, 77]) and len(b) >= 26:
        return "bmp"
    if len(b) >= 2 and b[0] == 80 and b[1] >= 49 and b[1] <= 54:
        return "pnm"
    if _starts(b, [255, 216, 255]):
        return "jpeg"
    if _starts(b, [71, 73, 70, 56]):
        return "gif"
    if len(b) >= 12 and _starts(b, [82, 73, 70, 70]) and b[8] == 87 and b[9] == 69 and b[10] == 66 and b[11] == 80:
        return "webp"
    if _starts(b, [73, 73, 42, 0]) or _starts(b, [77, 77, 0, 42]):
        return "tiff"
    if len(b) >= 12 and b[4] == 102 and b[5] == 116 and b[6] == 121 and b[7] == 112 and b[8] == 97 and b[9] == 118 and b[10] == 105 and b[11] == 102:
        return "avif"
    if len(b) >= 4 and b[0] == 0 and b[1] == 0 and b[2] == 1 and b[3] == 0:
        return "ico"
    return null

const SUPPORTED := ["png", "bmp", "pnm", "jpeg"]

func decode(b, limits=null):
    l := lim.of(limits)
    if type(b) != "list":
        merr.fail(merr.FORMAT, "decode : octets attendus")
    l.check_file_size(len(b))
    f := detect(b)
    if f == "png":
        return decode_png(b, l)
    if f == "bmp":
        return decode_bmp(b, l)
    if f == "pnm":
        return decode_pnm(b, l)
    if f == "jpeg":
        return _jpeg.decode(b, l)
    if f == null:
        merr.fail(merr.UNSUPPORTED, "multimédia : format d'image inconnu (signature non reconnue)")
    merr.unsupported("décodage " + f, "aucun décodeur " + f + " intégré ; formats décodés : png, bmp, pnm, jpeg")

func load(path, limits=null):
    l := lim.of(limits)
    if not _os.isfile(path):
        merr.fail(merr.MEDIA, "fichier introuvable : " + str(path))
    l.check_file_size(_os.size(path))
    return decode(_io.read_bytes(path), l)

# ======================================================================================== PNG
func _paeth(a, b, c):
    p := a + b - c
    pa := p - a if p >= a else a - p
    pb := p - b if p >= b else b - p
    pc := p - c if p >= c else c - p
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c

# Défiltre `rows` lignes de `stride` octets à partir de raw[pos] ; renvoie [lignes défiltrées (list), position].
func _unfilter(raw, pos, rows, stride, bpp, what):
    out := []
    prev := [0 for i in 0..stride]
    for y in 0..rows:
        if pos >= len(raw):
            merr.corrupt(what, "données d'image tronquées (ligne " + str(y) + ")")
        ft := raw[pos]
        pos += 1
        if pos + stride > len(raw):
            merr.corrupt(what, "données d'image tronquées (ligne " + str(y) + ")")
        cur := [raw[pos + k] for k in 0..stride]
        pos += stride
        if ft == 1:
            for k in bpp..stride:
                cur[k] = (cur[k] + cur[k - bpp]) & 255
        elif ft == 2:
            for k in 0..stride:
                cur[k] = (cur[k] + prev[k]) & 255
        elif ft == 3:
            for k in 0..stride:
                left := cur[k - bpp] if k >= bpp else 0
                cur[k] = (cur[k] + ((left + prev[k]) >> 1)) & 255
        elif ft == 4:
            for k in 0..stride:
                left := cur[k - bpp] if k >= bpp else 0
                ul := prev[k - bpp] if k >= bpp else 0
                cur[k] = (cur[k] + _paeth(left, prev[k], ul)) & 255
        elif ft != 0:
            merr.corrupt(what, "type de filtre " + str(ft) + " invalide (ligne " + str(y) + ")")
        append(out, cur)
        prev = cur
    return [out, pos]

# Échantillons d'une ligne défiltrée -> valeurs 8 bits par canal (n_values valeurs).
func _samples(line, depth, n_values):
    out := []
    if depth == 8:
        for k in 0..n_values:
            append(out, line[k])
    elif depth == 16:
        for k in 0..n_values:
            append(out, line[2 * k])
    else:
        per := 8 // depth
        mask := (1 << depth) - 1
        for k in 0..n_values:
            byte := line[k // per]
            shift := 8 - depth * (k % per + 1)
            append(out, (byte >> shift) & mask)
    return out

func _samples16(line, n_values):
    return [(line[2 * k] << 8) | line[2 * k + 1] for k in 0..n_values]

const ADAM7 := [[0, 0, 8, 8], [4, 0, 8, 8], [0, 4, 4, 8], [2, 0, 4, 4], [0, 2, 2, 4], [1, 0, 2, 2], [0, 1, 1, 2]]

func decode_png(b, limits=null):
    l := lim.of(limits)
    what := "PNG"
    r := val.Reader(b, what)
    val.check_magic(b, 0, PNG_MAGIC, what)
    at := 8
    ihdr := null
    palette := null
    trns := null
    idat := []
    seen_iend := false
    text := {}
    nchunks := 0
    while at < len(b):
        size := r.u32be(at)
        ctype := r.tag(at + 4)
        if ctype == "":
            merr.corrupt(what, "type de bloc illisible à la position " + str(at))
        l.check("max_chunk_bytes", size)
        val.check_chunk(at + 8, size + 4, len(b), "bloc " + ctype)
        crc_have := r.u32be(at + 8 + size)
        crc_want := _z.crc32([b[k] for k in at + 4..at + 8 + size])
        if crc_have != crc_want:
            merr.corrupt(what, "CRC faux pour le bloc " + ctype)
        data_at := at + 8
        nchunks += 1
        if nchunks == 1 and ctype != "IHDR":
            merr.corrupt(what, "le premier bloc doit être IHDR")
        if ctype == "IHDR":
            if size != 13:
                merr.corrupt(what, "IHDR de taille " + str(size))
            ihdr = [r.u32be(data_at), r.u32be(data_at + 4), b[data_at + 8], b[data_at + 9], b[data_at + 10], b[data_at + 11], b[data_at + 12]]
        elif ctype == "PLTE":
            if size % 3 != 0 or size == 0 or size > 768:
                merr.corrupt(what, "palette de " + str(size) + " octets")
            palette = [[b[data_at + 3 * i], b[data_at + 3 * i + 1], b[data_at + 3 * i + 2]] for i in 0..size // 3]
        elif ctype == "tRNS":
            trns = [b[k] for k in data_at..data_at + size]
        elif ctype == "IDAT":
            for k in data_at..data_at + size:
                append(idat, b[k])
        elif ctype == "tEXt":
            raw := [b[k] for k in data_at..data_at + size]
            z := -1
            for k in 0..len(raw):
                if raw[k] == 0:
                    z = k
                    break
            if z > 0:
                text[_s.byte_pack([raw[k] for k in 0..z])] = _s.byte_pack([raw[k] for k in z + 1..len(raw)])
        elif ctype == "IEND":
            seen_iend = true
            break
        at += 12 + size
    if ihdr == null:
        merr.corrupt(what, "IHDR absent")
    if not seen_iend:
        merr.corrupt(what, "IEND absent (fichier tronqué ?)")
    w := ihdr[0]
    h := ihdr[1]
    depth := ihdr[2]
    ct := ihdr[3]
    if w == 0 or h == 0:
        merr.corrupt(what, "dimensions nulles")
    l.check_dimensions(w, h)
    if ihdr[4] != 0 or ihdr[5] != 0:
        merr.corrupt(what, "méthode de compression ou de filtrage inconnue")
    if ihdr[6] > 1:
        merr.corrupt(what, "entrelacement inconnu " + str(ihdr[6]))
    allowed := {0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16]}
    if not (ct in allowed) or not (depth in allowed[ct]):
        merr.corrupt(what, "combinaison type de couleur " + str(ct) + " / profondeur " + str(depth) + " invalide")
    if ct == 3 and palette == null:
        merr.corrupt(what, "image à palette sans PLTE")
    if len(idat) == 0:
        merr.corrupt(what, "aucun bloc IDAT")
    nch := {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    bpp := (nch * depth + 7) // 8
    # taille brute attendue (somme des passes si entrelacé) : sert de limite à l'inflate
    expected := 0
    passes := [[0, 0, 1, 1]]
    if ihdr[6] == 1:
        passes = ADAM7
    for ps in passes:
        pw := (w - ps[0] + ps[2] - 1) // ps[2] if w > ps[0] else 0
        ph := (h - ps[1] + ps[3] - 1) // ps[3] if h > ps[1] else 0
        if pw > 0 and ph > 0:
            expected += ph * (1 + (pw * nch * depth + 7) // 8)
    l.check("max_decoded_bytes", expected)
    raw := null
    try:
        raw = _z.zlib_decompress(idat, expected)
    catch e:
        merr.corrupt(what, "flux compressé invalide : " + e.message)
    # mode de sortie
    has_trns := trns != null and len(trns) > 0
    mode := "rgb"
    if ct == 0:
        mode = "rgba" if has_trns else "gray"
    elif ct == 4 or ct == 6:
        mode = "rgba"
    elif has_trns:
        mode = "rgba"
    img := mi.Image(w, h, mode)
    och := img.channels
    px := img.pixels
    maxv := (1 << depth) - 1
    tkey := null
    if has_trns and ct == 0 and len(trns) >= 2:
        tkey = (trns[0] << 8) | trns[1]
    if has_trns and ct == 2 and len(trns) >= 6:
        tkey = [(trns[0] << 8) | trns[1], (trns[2] << 8) | trns[3], (trns[4] << 8) | trns[5]]
    pos := 0
    for ps in passes:
        pw := (w - ps[0] + ps[2] - 1) // ps[2] if w > ps[0] else 0
        ph := (h - ps[1] + ps[3] - 1) // ps[3] if h > ps[1] else 0
        if pw == 0 or ph == 0:
            continue
        stride := (pw * nch * depth + 7) // 8
        res := _unfilter(raw, pos, ph, stride, bpp, what)
        pos = res[1]
        lines := res[0]
        for ly in 0..ph:
            line := lines[ly]
            vals := _samples(line, depth, pw * nch)
            raw16 := null
            if tkey != null and depth == 16:
                raw16 = _samples16(line, pw * nch)
            y := ps[1] + ly * ps[3]
            for lx in 0..pw:
                x := ps[0] + lx * ps[2]
                o := (y * w + x) * och
                k := lx * nch
                if ct == 3:
                    idx := vals[k]
                    if idx >= len(palette):
                        merr.corrupt(what, "indice de palette " + str(idx) + " hors de la palette")
                    c := palette[idx]
                    px[o] = c[0]
                    px[o + 1] = c[1]
                    px[o + 2] = c[2]
                    if och == 4:
                        px[o + 3] = trns[idx] if idx < len(trns) else 255
                elif ct == 0:
                    v := vals[k]
                    g := v if depth >= 8 else (v * 255) // maxv
                    if och == 1:
                        px[o] = g
                    else:
                        px[o] = g
                        px[o + 1] = g
                        px[o + 2] = g
                        rv := raw16[k] if raw16 != null else v
                        px[o + 3] = 0 if rv == tkey else 255
                elif ct == 4:
                    px[o] = vals[k]
                    px[o + 1] = vals[k]
                    px[o + 2] = vals[k]
                    px[o + 3] = vals[k + 1]
                else:
                    px[o] = vals[k]
                    px[o + 1] = vals[k + 1]
                    px[o + 2] = vals[k + 2]
                    if och == 4:
                        if ct == 6:
                            px[o + 3] = vals[k + 3]
                        else:
                            same := false
                            if raw16 != null:
                                same = raw16[k] == tkey[0] and raw16[k + 1] == tkey[1] and raw16[k + 2] == tkey[2]
                            elif tkey != null:
                                same = vals[k] == tkey[0] and vals[k + 1] == tkey[1] and vals[k + 2] == tkey[2]
                            px[o + 3] = 0 if same else 255
    img.meta = {"format": "png", "bit_depth": depth, "color_type": ct, "interlaced": ihdr[6] == 1, "text": text}
    return img

# ======================================================================================== BMP
func _mask_info(m):
    if m == 0:
        return [0, 0]
    shift := 0
    while ((m >> shift) & 1) == 0:
        shift += 1
    bits := 0
    while ((m >> (shift + bits)) & 1) == 1:
        bits += 1
    return [shift, bits]

func _mask_value(v, info):
    if info[1] == 0:
        return 255
    x := (v >> info[0]) & ((1 << info[1]) - 1)
    return (x * 255 + ((1 << info[1]) - 1) // 2) // ((1 << info[1]) - 1)

func decode_bmp(b, limits=null):
    l := lim.of(limits)
    what := "BMP"
    r := val.Reader(b, what)
    if r.tag(0, 2) != "BM":
        merr.corrupt(what, "signature BM absente")
    offset := r.u32le(10)
    hsize := r.u32le(14)
    w := 0
    h := 0
    bpp := 0
    comp := 0
    ncolors := 0
    masks := null
    if hsize == 12:
        w = r.u16le(18)
        h = r.u16le(20)
        bpp = r.u16le(24)
    elif hsize >= 40:
        w = r.s32le(18)
        h = r.s32le(22)
        bpp = r.u16le(28)
        comp = r.u32le(30)
        ncolors = r.u32le(46)
        if comp == 3 or comp == 6:
            if hsize >= 52:
                masks = [r.u32le(54), r.u32le(58), r.u32le(62), r.u32le(66) if hsize >= 56 else 0]
            else:
                masks = [r.u32le(54), r.u32le(58), r.u32le(62), 0]
    else:
        merr.corrupt(what, "en-tête DIB de " + str(hsize) + " octets")
    top_down := h < 0
    if top_down:
        h = -h
    if w <= 0 or h <= 0:
        merr.corrupt(what, "dimensions invalides " + str(w) + "x" + str(h))
    l.check_dimensions(w, h)
    if comp == 1 or comp == 2:
        merr.unsupported("BMP compressé RLE")
    if comp == 4 or comp == 5:
        merr.unsupported("BMP contenant du JPEG ou du PNG")
    if comp != 0 and comp != 3 and comp != 6:
        merr.corrupt(what, "compression inconnue " + str(comp))
    if not (bpp in [1, 4, 8, 16, 24, 32]):
        merr.corrupt(what, "profondeur " + str(bpp) + " bits invalide")
    palette := null
    if bpp <= 8:
        n := ncolors if ncolors > 0 else (1 << bpp)
        if n > 256:
            merr.corrupt(what, "palette de " + str(n) + " couleurs")
        pal_at := 14 + hsize
        entry := 3 if hsize == 12 else 4
        palette = []
        for i in 0..n:
            p := pal_at + i * entry
            append(palette, [r.u8(p + 2), r.u8(p + 1), r.u8(p)])
    if bpp == 16 and masks == null:
        masks = [0x7C00, 0x03E0, 0x001F, 0]
    if bpp == 32 and masks == null:
        masks = [0x00FF0000, 0x0000FF00, 0x000000FF, 0]
    stride := ((w * bpp + 31) // 32) * 4
    val.check_chunk(offset, stride * h, len(b), "pixels")
    # 32 bits sans champs de bits : le 4e octet est officiellement inutilisé, mais beaucoup d'outils y écrivent
    # l'alpha ; il est pris comme alpha s'il n'est pas nul partout (même règle que les lecteurs courants).
    if bpp == 32 and comp == 0:
        used := false
        for row in 0..h:
            base := offset + row * stride
            for x in 0..w:
                if b[base + 4 * x + 3] != 0:
                    used = true
                    break
            if used:
                break
        if used:
            masks[3] = 0xFF000000
    alpha := masks != null and masks[3] != 0
    img := mi.Image(w, h, "rgba" if alpha else "rgb")
    och := img.channels
    px := img.pixels
    mi_ := null
    if masks != null:
        mi_ = [_mask_info(masks[0]), _mask_info(masks[1]), _mask_info(masks[2]), _mask_info(masks[3])]
    for row in 0..h:
        y := row if top_down else h - 1 - row
        base := offset + row * stride
        for x in 0..w:
            o := (y * w + x) * och
            c := null
            if bpp == 24:
                k := base + 3 * x
                c = [b[k + 2], b[k + 1], b[k]]
            elif bpp == 32 or bpp == 16:
                v := 0
                if bpp == 32:
                    k := base + 4 * x
                    v = b[k] | (b[k + 1] << 8) | (b[k + 2] << 16) | (b[k + 3] << 24)
                else:
                    k := base + 2 * x
                    v = b[k] | (b[k + 1] << 8)
                c = [_mask_value(v, mi_[0]), _mask_value(v, mi_[1]), _mask_value(v, mi_[2])]
                if alpha:
                    append(c, _mask_value(v, mi_[3]))
            else:
                per := 8 // bpp
                byte := b[base + x // per]
                shift := 8 - bpp * (x % per + 1)
                idx := (byte >> shift) & ((1 << bpp) - 1)
                if idx >= len(palette):
                    merr.corrupt(what, "indice de palette " + str(idx) + " hors de la palette")
                c = palette[idx]
            for k in 0..och:
                px[o + k] = c[k]
    img.meta = {"format": "bmp", "bit_depth": bpp, "top_down": top_down}
    return img

# ======================================================================================== PNM
func _pnm_tokens(b, count, what):
    # renvoie [valeurs entières, position après le dernier séparateur]
    out := []
    pos := 2
    while len(out) < count:
        while pos < len(b) and (b[pos] == 32 or b[pos] == 9 or b[pos] == 10 or b[pos] == 13 or b[pos] == 35):
            if b[pos] == 35:
                while pos < len(b) and b[pos] != 10:
                    pos += 1
            else:
                pos += 1
        if pos >= len(b):
            merr.corrupt(what, "en-tête tronqué")
        v := 0
        start := pos
        while pos < len(b) and b[pos] >= 48 and b[pos] <= 57:
            v = v * 10 + b[pos] - 48
            pos += 1
            if pos - start > 9:
                merr.corrupt(what, "nombre trop long dans l'en-tête")
        if pos == start:
            merr.corrupt(what, "caractère inattendu dans l'en-tête")
        append(out, v)
    return [out, pos]

func decode_pnm(b, limits=null):
    l := lim.of(limits)
    what := "PNM"
    kind := b[1] - 48
    if kind < 1 or kind > 6:
        merr.corrupt(what, "type P" + str(kind) + " inconnu")
    bitmap := kind == 1 or kind == 4
    ncount := 2 if bitmap else 3
    hdr := _pnm_tokens(b, ncount, what)
    w := hdr[0][0]
    h := hdr[0][1]
    maxv := 1 if bitmap else hdr[0][2]
    pos := hdr[1]
    if w <= 0 or h <= 0:
        merr.corrupt(what, "dimensions invalides")
    l.check_dimensions(w, h)
    if maxv <= 0 or maxv > 65535:
        merr.corrupt(what, "valeur maximale " + str(maxv) + " invalide")
    color := kind == 3 or kind == 6
    nch := 3 if color else 1
    n := w * h * nch
    vals := []
    if kind <= 3:
        rest := _pnm_ascii(b, pos, n, bitmap, what)
        vals = rest
    else:
        pos += 1          # un seul blanc après l'en-tête
        if kind == 4:
            stride := (w + 7) // 8
            val.check_chunk(pos, stride * h, len(b), "points")
            for y in 0..h:
                for x in 0..w:
                    byte := b[pos + y * stride + x // 8]
                    append(vals, (byte >> (7 - x % 8)) & 1)
        else:
            width := 2 if maxv > 255 else 1
            val.check_chunk(pos, n * width, len(b), "points")
            for k in 0..n:
                if width == 1:
                    append(vals, b[pos + k])
                else:
                    append(vals, (b[pos + 2 * k] << 8) | b[pos + 2 * k + 1])
    out := []
    for v in vals:
        if v > maxv:
            merr.corrupt(what, "valeur " + str(v) + " supérieure au maximum " + str(maxv))
        if bitmap:
            append(out, 0 if v == 1 else 255)          # PBM : 1 = noir
        elif maxv == 255:
            append(out, v)
        else:
            append(out, (v * 255 + maxv // 2) // maxv)
    img := mi.Image(w, h, "rgb" if color else "gray", out)
    img.meta = {"format": "pnm", "kind": "P" + str(kind), "maxval": maxv}
    return img

func _pnm_ascii(b, pos, n, bitmap, what):
    out := []
    while len(out) < n:
        while pos < len(b) and (b[pos] == 32 or b[pos] == 9 or b[pos] == 10 or b[pos] == 13 or b[pos] == 35):
            if b[pos] == 35:
                while pos < len(b) and b[pos] != 10:
                    pos += 1
            else:
                pos += 1
        if pos >= len(b):
            merr.corrupt(what, "points tronqués (" + str(len(out)) + " sur " + str(n) + ")")
        if bitmap:
            if b[pos] != 48 and b[pos] != 49:
                merr.corrupt(what, "point PBM invalide")
            append(out, b[pos] - 48)
            pos += 1
        else:
            v := 0
            start := pos
            while pos < len(b) and b[pos] >= 48 and b[pos] <= 57:
                v = v * 10 + b[pos] - 48
                pos += 1
                if pos - start > 6:
                    merr.corrupt(what, "valeur trop longue")
            if pos == start:
                merr.corrupt(what, "caractère inattendu dans les points")
            append(out, v)
    return out

# ALEX STANDARD LIBRARY — multimedia.image.metadata
#
# Métadonnées d'images SANS décoder les points : format, dimensions, profondeur, type de couleur,
# entrelacement, textes PNG (tEXt), résolution BMP. Lecture bornée de l'en-tête seulement.
#
#   use multimedia.image.metadata as imeta
#   m := imeta.read("photo.png")
#   print(m["format"], m["width"], m["height"], m["text"])
#
# Erreurs : CorruptDataError, UnsupportedError (format inconnu).

from core use len
use io as _io
use os as _os
use string as _s
use multimedia.core.errors as merr
use multimedia.security.validation as val
use multimedia.image.decode as dec

const COLOR_TYPES := {0: "gris", 2: "rgb", 3: "palette", 4: "gris + alpha", 6: "rgba"}

func inspect(b):
    f := dec.detect(b)
    if f == null:
        merr.fail(merr.UNSUPPORTED, "multimédia : format d'image inconnu")
    r := val.Reader(b, f)
    m := {"format": f, "width": null, "height": null, "bit_depth": null, "color": null, "text": {}}
    if f == "png":
        if r.tag(12) != "IHDR":
            merr.corrupt("PNG", "IHDR absent")
        m["width"] = r.u32be(16)
        m["height"] = r.u32be(20)
        m["bit_depth"] = r.u8(24)
        ct := r.u8(25)
        m["color"] = COLOR_TYPES[ct] if ct in COLOR_TYPES else "inconnu"
        m["interlaced"] = r.u8(28) == 1
        at := 8
        while at + 12 <= len(b):
            size := r.u32be(at)
            t := r.tag(at + 4)
            if t == "IEND" or t == "" or at + 12 + size > len(b):
                break
            if t == "tEXt":
                raw := r.bytes(at + 8, size)
                z := -1
                for k in 0..len(raw):
                    if raw[k] == 0:
                        z = k
                        break
                if z > 0:
                    m["text"][_s.byte_pack([raw[k] for k in 0..z])] = _s.byte_pack([raw[k] for k in z + 1..len(raw)])
            at += 12 + size
    elif f == "bmp":
        hs := r.u32le(14)
        if hs == 12:
            m["width"] = r.u16le(18)
            m["height"] = r.u16le(20)
            m["bit_depth"] = r.u16le(24)
        else:
            m["width"] = r.s32le(18)
            h := r.s32le(22)
            m["height"] = h if h >= 0 else -h
            m["bit_depth"] = r.u16le(28)
            if hs >= 40:
                m["dpi"] = [(r.u32le(38) * 254 + 5000) // 10000, (r.u32le(42) * 254 + 5000) // 10000]
        m["color"] = "palette" if m["bit_depth"] <= 8 else ("rgba" if m["bit_depth"] == 32 else "rgb")
    elif f == "pnm":
        img := dec.decode_pnm(b)
        m["width"] = img.width
        m["height"] = img.height
        m["bit_depth"] = 8
        m["color"] = "rgb" if img.mode == "rgb" else "gris"
    elif f == "gif":
        m["width"] = r.u16le(6)
        m["height"] = r.u16le(8)
    elif f == "jpeg":
        _jpeg_size(r, m)
    return m

# Dimensions JPEG : parcours des segments jusqu'au premier SOFn.
func _jpeg_size(r, m):
    at := 2
    while at + 4 <= r.size:
        if r.u8(at) != 255:
            return
        marker := r.u8(at + 1)
        if marker == 0xD8 or marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7):
            at += 2
            continue
        seg := r.u16be(at + 2)
        if marker >= 0xC0 and marker <= 0xCF and marker != 0xC4 and marker != 0xC8 and marker != 0xCC:
            m["bit_depth"] = r.u8(at + 4)
            m["height"] = r.u16be(at + 5)
            m["width"] = r.u16be(at + 7)
            m["color"] = "gris" if r.u8(at + 9) == 1 else "ycbcr"
            return
        at += 2 + seg

func read(path):
    if not _os.isfile(path):
        merr.fail(merr.MEDIA, "fichier introuvable : " + str(path))
    n := _os.size(path)
    head := _io.read_bytes(path, 0, n if n < 1048576 else 1048576)
    m := inspect(head)
    m["size"] = n
    return m

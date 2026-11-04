# Générateur de JPEG de test (outil de développement, non utilisé à l'exécution).
#
# Pilote par ctypes la libjpeg-turbo 3 embarquée par Pillow pour produire les variantes que les encodeurs courants
# n'exposent pas : codage arithmétique (séquentiel / progressif), sans perte (SOF3), 12 bits, CMYK, YCCK, Exif.
# Écrit aussi, pour chaque fichier, l'image de référence décodée par Pillow (<nom>.ref.png, RGBA).
#
#   python3 tests/gamedev/data/mkjpeg_ref.py tests/gamedev/data
#
# Disposition de jpeg_compress_struct : ABI 6.2 de libjpeg-turbo, x86_64 (520 octets).

import ctypes, glob, io, os, struct, sys
from PIL import Image

LIB = ctypes.CDLL(glob.glob(os.path.join(os.path.dirname(Image.__file__), "..", "pillow.libs", "libjpeg*"))[0])
LIB.jpeg_std_error.restype = ctypes.c_void_p

JCS = {"gray": 1, "rgb": 2, "ycc": 3, "cmyk": 4, "ycck": 5}


def _i32(buf, off, v=None):
    if v is None:
        return struct.unpack_from("<i", buf, off)[0]
    struct.pack_into("<i", buf, off, v)


def encode(pixels, w, h, nc, incs, jcs=None, quality=90, arith=False, progressive=False, lossless=None,
           precision=8, sampling=None, restart=0, app=None):
    err = ctypes.create_string_buffer(1024)
    LIB.jpeg_std_error(err)
    c = ctypes.create_string_buffer(520)
    struct.pack_into("<Q", c, 0, ctypes.addressof(err))
    LIB.jpeg_CreateCompress(c, 62, 520)
    outbuf = ctypes.c_void_p()
    outsize = ctypes.c_ulong()
    LIB.jpeg_mem_dest(c, ctypes.byref(outbuf), ctypes.byref(outsize))
    _i32(c, 48, w)
    _i32(c, 52, h)
    _i32(c, 56, nc)
    _i32(c, 60, JCS[incs])
    LIB.jpeg_set_defaults(c)
    assert _i32(c, 72) == 8 and _i32(c, 76) == nc, "disposition de la structure inattendue"
    _i32(c, 72, precision)
    if jcs is not None:
        LIB.jpeg_set_colorspace(c, JCS[jcs])
    LIB.jpeg_set_quality(c, quality, 1)
    ci = struct.unpack_from("<Q", c, 88)[0]
    ncomp = _i32(c, 76)
    if sampling is not None:
        for k in range(ncomp):
            hv = sampling[k] if k < len(sampling) else (1, 1)
            ctypes.memmove(ci + 96 * k + 8, struct.pack("<ii", hv[0], hv[1]), 8)
    if arith:
        _i32(c, 260, 1)
    if restart:
        _i32(c, 280, restart)
    if progressive:
        LIB.jpeg_simple_progression(c)
    if lossless is not None:
        LIB.jpeg_enable_lossless(c, lossless[0], lossless[1])
    LIB.jpeg_start_compress(c, 1)
    if app is not None:
        LIB.jpeg_write_marker(c, app[0], app[1], len(app[1]))
    bps = 2 if precision > 8 else 1
    row = w * nc * bps
    data = bytes(pixels)
    rows = (ctypes.c_char_p * h)()
    keep = []
    for y in range(h):
        b = ctypes.create_string_buffer(data[y * row:(y + 1) * row], row)
        keep.append(b)
        rows[y] = ctypes.cast(b, ctypes.c_char_p)
    fn = LIB.jpeg_write_scanlines if precision == 8 else (LIB.jpeg12_write_scanlines if precision == 12 else LIB.jpeg16_write_scanlines)
    done = 0
    while done < h:
        n = fn(c, ctypes.byref(rows, done * 8), h - done)
        done += n
    LIB.jpeg_finish_compress(c)
    out = ctypes.string_at(outbuf, outsize.value)
    LIB.jpeg_destroy_compress(c)
    return out


def scene(w, h, nc=3, maxv=255):
    # dégradés + disque + damier, pour exercer toutes les fréquences
    px = []
    for y in range(h):
        for x in range(w):
            r = x * 255 // max(1, w - 1)
            g = y * 255 // max(1, h - 1)
            b = 255 if (x - w // 2) ** 2 + (y - h // 2) ** 2 < (min(w, h) // 3) ** 2 else (40 if (x // 8 + y // 8) % 2 else 200)
            v = [r, g, b, (x + y) * 255 // (w + h)][:nc]
            if nc == 1:
                v = [(r + g + b) // 3]
            px += [vv * maxv // 255 for vv in v]
    return px


def exif(orient):
    tiff = b"MM\x00\x2a\x00\x00\x00\x08" + struct.pack(">H", 1) + struct.pack(">HHIHH", 0x0112, 3, 1, orient, 0) + b"\x00\x00\x00\x00"
    return b"Exif\x00\x00" + tiff


def rgb_ref(jpg):
    im = Image.open(io.BytesIO(jpg))
    im.load()
    if im.mode == "CMYK":
        # Pillow rend l'encre (0 = rien) ; R = (255 - C) * (255 - K) / 255
        d = im.tobytes()
        out = bytearray()
        for i in range(0, len(d), 4):
            k = 255 - d[i + 3]
            out += bytes([((255 - d[i + j]) * k + 127) // 255 for j in range(3)])
        return bytes(out)
    return im.convert("RGB").tobytes()


def _png(dest, base, rgb, w, h):
    Image.frombytes("RGB", (w, h), rgb).convert("RGBA").save(os.path.join(dest, base + ".ref.png"))


def main(dest):
    W, H = 61, 47
    files = {
        "arith_seq.jpg": encode(scene(W, H), W, H, 3, "rgb", arith=True, sampling=[(2, 2)]),
        "arith_prog.jpg": encode(scene(W, H), W, H, 3, "rgb", arith=True, progressive=True, sampling=[(2, 1)]),
        "arith_gray_rst.jpg": encode(scene(W, H, 1), W, H, 1, "gray", arith=True, restart=3),
        "lossless_gray.jpg": encode(scene(W, H, 1), W, H, 1, "gray", lossless=(1, 0)),
        "lossless_rgb.jpg": encode(scene(W, H), W, H, 3, "rgb", jcs="rgb", lossless=(7, 0), sampling=[(1, 1)], restart=W),
        "lossless_ycc.jpg": encode(scene(W, H), W, H, 3, "rgb", lossless=(4, 1), sampling=[(1, 1)]),
        "cmyk.jpg": encode(scene(W, H, 4), W, H, 4, "cmyk"),
        "ycck.jpg": encode(scene(W, H, 4), W, H, 4, "cmyk", jcs="ycck", sampling=[(2, 2), (1, 1), (1, 1), (2, 2)]),
        "exif6.jpg": encode(scene(W, H), W, H, 3, "rgb", app=(0xE1, exif(6))),
    }
    for name, data in files.items():
        with open(os.path.join(dest, name), "wb") as f:
            f.write(data)
        _png(dest, name[:-4], rgb_ref(data), W, H)
    # 12 bits : pas de référence Pillow (décodeur 8 bits) ; la source (échelle 0..4095) sert de référence
    src12 = scene(W, H, 3, 4095)
    with open(os.path.join(dest, "p12.jpg"), "wb") as f:
        f.write(encode(struct.pack("<%dH" % len(src12), *src12), W, H, 3, "rgb", precision=12, quality=95))
    with open(os.path.join(dest, "p12_prog.jpg"), "wb") as f:
        f.write(encode(struct.pack("<%dH" % len(src12), *src12), W, H, 3, "rgb", precision=12, quality=95, progressive=True))
    _png(dest, "p12", bytes(v >> 4 for v in src12), W, H)
    lo12 = scene(W, H, 1, 4095)
    with open(os.path.join(dest, "lossless12.jpg"), "wb") as f:
        f.write(encode(struct.pack("<%dH" % len(lo12), *lo12), W, H, 1, "gray", precision=12, lossless=(6, 0)))
    _png(dest, "lossless12", bytes(v >> 4 for v in lo12 for _ in range(3)), W, H)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")

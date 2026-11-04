# Générateur des textures de test DDS / KTX2 (outil de développement, non utilisé à l'exécution).
#
#   python3 tests/gamedev/data/mktex_ref.py tests/gamedev/data
#
# Blocs construits à la main (couleurs unies, résultat connu) : BC1, ETC2 (mode différentiel), EAC R11,
# ASTC (blocs « void extent »). La supercompression zstd utilise la libzstd embarquée par Pillow.

import ctypes, glob, os, struct, sys
from PIL import Image

KTX2_ID = bytes([171, 75, 84, 88, 32, 50, 48, 187, 13, 10, 26, 10])
RED, GREEN, BLUE, WHITE = (255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)
YELLOW, MAGENTA, CYAN = (255, 255, 0), (255, 0, 255), (0, 255, 255)
FACES = [RED, GREEN, BLUE, YELLOW, MAGENTA, CYAN]          # +X -X +Y -Y +Z -Z


def bc1(c):
    v = ((c[0] >> 3) << 11) | ((c[1] >> 2) << 5) | (c[2] >> 3)
    return struct.pack("<HHI", v, v, 0)


def etc2(c):
    # ETC1 différentiel, écarts nuls, table 0, index 2 (-2) pour tous les pixels : couleur - 2 (bornée)
    r, g, b = c[0] >> 3, c[1] >> 3, c[2] >> 3
    return bytes([r << 3, g << 3, b << 3, 0x02]) + struct.pack(">HH", 0xFFFF, 0x0000)


def eac_r11(base):
    # multiplicateur 0, table 0, index 4 (+2) : valeur 11 bits = base * 8 + 4 + 2
    bits = 0
    for i in range(16):
        bits = (bits << 3) | 4
    return bytes([base, 0x00]) + bits.to_bytes(6, "big")


def astc_void(c, a=255):
    lo = 0xFFFFFFFFFFFFFDFC
    hi = (c[0] * 257) | ((c[1] * 257) << 16) | ((c[2] * 257) << 32) | ((a * 257) << 48)
    return struct.pack("<QQ", lo, hi)


def quad_blocks(enc, bw, bh, colors):
    # image de 2 x 2 blocs : rouge, vert / bleu, blanc
    return enc(colors[0]) + enc(colors[1]) + enc(colors[2]) + enc(colors[3])


def solid_blocks(enc, n, c):
    return enc(c) * n


def rgba(w, h, c):
    return bytes(list(c) + [255]) * (w * h)


def ktx2(vk, w, h, levels, depth=0, layers=0, faces=1, sc=0, type_size=1, ulens=None):
    n = len(levels)
    head = 80 + 24 * n
    out = bytearray(KTX2_ID)
    out += struct.pack("<9I", vk, type_size, w, h, depth, layers, faces, n, sc)
    out += struct.pack("<IIIIQQ", 0, 0, 0, 0, 0, 0)
    off = head
    index = bytearray()
    data = bytearray()
    for k, lv in enumerate(levels):
        ul = ulens[k] if ulens else len(lv)
        index += struct.pack("<QQQ", off, len(lv), ul)
        data += lv
        off += len(lv)
    return bytes(out + index + data)


def dds(w, h, mips, fourcc=None, rgba32=False, cube=False, depth=0, payload=b"", dx10=None):
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | (0x20000 if mips > 1 else 0) | (0x800000 if depth else 0)
    hdr = struct.pack("<4sIIIIIII", b"DDS ", 124, flags, h, w, 0, depth, mips) + b"\0" * 44
    if rgba32:
        pf = struct.pack("<II4sIIIII", 32, 0x41, b"\0\0\0\0", 32, 0xFF, 0xFF00, 0xFF0000, 0xFF000000)
    else:
        pf = struct.pack("<II4sIIIII", 32, 0x4, fourcc, 0, 0, 0, 0, 0)
    caps2 = (0x200 | 0xFC00) if cube else 0
    if depth:
        caps2 |= 0x200000
    hdr += pf + struct.pack("<IIIII", 0x1000 | (0x400008 if mips > 1 else 0) | (0x8 if cube else 0), caps2, 0, 0, 0)
    if dx10 is not None:
        hdr += struct.pack("<IIIII", *dx10)
    return hdr + payload


def zstd(data):
    lib = ctypes.CDLL(glob.glob(os.path.join(os.path.dirname(Image.__file__), "..", "pillow.libs", "libzstd*"))[0])
    lib.ZSTD_compressBound.restype = ctypes.c_size_t
    lib.ZSTD_compress.restype = ctypes.c_size_t
    lib.ZSTD_compress.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_int]
    cap = lib.ZSTD_compressBound(len(data))
    out = ctypes.create_string_buffer(cap)
    n = lib.ZSTD_compress(out, cap, data, len(data), 19)
    return out.raw[:n]


def main(d):
    def put(name, data):
        with open(os.path.join(d, name), "wb") as f:
            f.write(data)

    q = [RED, GREEN, BLUE, WHITE]
    # cubemap BC1 8 x 8, 4 niveaux (DDS : chaque face porte sa chaîne de niveaux)
    payload = b""
    for c in FACES:
        for k in range(4):
            s = max(1, 8 >> k)
            payload += solid_blocks(bc1, ((s + 3) // 4) ** 2, c)
    put("cube_bc1.dds", dds(8, 8, 4, b"DXT1", cube=True, payload=payload))
    # cubemap RGBA8 KTX2 4 x 4
    put("cube_rgba.ktx2", ktx2(37, 4, 4, [b"".join(rgba(4, 4, c) for c in FACES)], faces=6))
    # tableau de 3 couches BC1 8 x 8, 2 niveaux
    lv0 = b"".join(solid_blocks(bc1, 4, c) for c in [RED, GREEN, BLUE])
    lv1 = b"".join(solid_blocks(bc1, 1, c) for c in [RED, GREEN, BLUE])
    put("array_bc1.ktx2", ktx2(133, 8, 8, [lv0, lv1], layers=3))
    # tableau DDS DX10 (2 couches RGBA8 4 x 4)
    put("array_rgba.dds", dds(4, 4, 1, b"DX10", payload=rgba(4, 4, YELLOW) + rgba(4, 4, CYAN), dx10=(28, 3, 0, 2, 0)))
    # volume RGBA8 4 x 4 x 4 (tranches rouge, vert, bleu, blanc)
    put("vol_rgba.dds", dds(4, 4, 1, rgba32=True, depth=4, payload=b"".join(rgba(4, 4, c) for c in q)))
    # tableau de 2 cubemaps RGBA8 2 x 2
    put("cubearray_rgba.ktx2", ktx2(37, 2, 2, [b"".join(rgba(2, 2, c) for c in FACES + FACES[::-1])], layers=2, faces=6))
    # BC1 8 x 8 avec supercompression zstd (niveaux 8, 4, 2, 1)
    lvls = [quad_blocks(bc1, 4, 4, q)] + [solid_blocks(bc1, 1, RED)] * 3
    put("zstd_bc1.ktx2", ktx2(133, 8, 8, [zstd(l) for l in lvls], sc=2, ulens=[len(l) for l in lvls]))
    # ETC2 RGB8 8 x 8, EAC R11 8 x 8, ASTC 4x4 8 x 8, ASTC 6x6 12 x 12
    put("etc2.ktx2", ktx2(147, 8, 8, [quad_blocks(etc2, 4, 4, q)]))
    put("eac_r11.ktx2", ktx2(153, 8, 8, [eac_r11(255) + eac_r11(0) + eac_r11(128) + eac_r11(255)]))
    put("astc4.ktx2", ktx2(157, 8, 8, [quad_blocks(astc_void, 4, 4, q)]))
    put("astc6.ktx2", ktx2(165, 12, 12, [quad_blocks(astc_void, 6, 6, q)]))
    # six images d'un ciel (PNG 4 x 4) : sky_px.png ... sky_nz.png
    for tag, c in zip(["px", "nx", "py", "ny", "pz", "nz"], FACES):
        Image.new("RGB", (4, 4), c).save(os.path.join(d, "sky_" + tag + ".png"))
    # Basis Universal (ETC1S) : en-tête seul, doit être refusé avec explication
    put("basis.ktx2", ktx2(0, 8, 8, [b"\0" * 16], sc=1))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")

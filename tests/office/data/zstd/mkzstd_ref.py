# Générateur des fichiers zstd de test (libzstd de Pillow par ctypes). Outil de développement.
#   python3 tests/office/data/zstd/mkzstd_ref.py tests/office/data/zstd
# Écrit <cas>.zst et affiche [cas, taille, crc32] à recopier dans tests/office/test_zstd.al.
import ctypes, glob, os, random, sys, zlib
from PIL import Image
L = ctypes.CDLL(glob.glob(os.path.join(os.path.dirname(Image.__file__), "..", "pillow.libs", "libzstd*"))[0])
L.ZSTD_compressBound.restype = ctypes.c_size_t
L.ZSTD_createCCtx.restype = ctypes.c_void_p
L.ZSTD_compress2.restype = ctypes.c_size_t
L.ZSTD_compress2.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_size_t]
L.ZSTD_CCtx_setParameter.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]


def comp(data, level, checksum=0, size=True):
    cap = L.ZSTD_compressBound(len(data))
    out = ctypes.create_string_buffer(cap)
    c = L.ZSTD_createCCtx()
    L.ZSTD_CCtx_setParameter(c, 100, level)
    L.ZSTD_CCtx_setParameter(c, 201, checksum)
    L.ZSTD_CCtx_setParameter(c, 200, 1 if size else 0)
    n = L.ZSTD_compress2(c, out, cap, data, len(data))
    return out.raw[:n]


random.seed(7)
words = [bytes(random.choice(b"abcdefghijklmnopqrstuvwxyz") for _ in range(random.randint(2, 9))) for _ in range(300)]
text = b" ".join(random.choice(words) for _ in range(9000))
binary = bytes(random.getrandbits(8) if random.random() < 0.3 else (i * 7) & 255 for i in range(30000))
big = bytes((i * i >> 5) & 255 for i in range(300000))        # plusieurs blocs de 128 Kio
skip = b"\x50\x2a\x4d\x18" + (5).to_bytes(4, "little") + b"12345"
cases = {"text19": (comp(text, 19, 1), text), "text1": (comp(text, 1), text), "bin3": (comp(binary, 3), binary),
         "bin22": (comp(binary, 22), binary), "rle": (comp(b"\x2a" * 70000, 5, 0, False), b"\x2a" * 70000),
         "multi": (comp(b"bonjour", 1) + skip + comp(text[:9000], 7), b"bonjour" + text[:9000]),
         "big": (comp(big, 3), big), "empty": (comp(b"", 3), b"")}
d = sys.argv[1]
for k, (z, raw) in cases.items():
    open(os.path.join(d, k + ".zst"), "wb").write(z)
    print('["%s", %d, %d],' % (k, len(raw), zlib.crc32(raw)))
